# Board SQL for the orchestrator

The exact writes check-in and shift make. Every block starts with the same two lines,
because `foreign_keys` is per connection and the actor labels every event:

```sql
PRAGMA foreign_keys = ON;
UPDATE guild_state SET value = 'orchestrator' WHERE key = 'actor';
```

`<now>` below means `strftime('%Y-%m-%dT%H:%M:%SZ', 'now')`. `<hex>` means free text sent as
`CAST(x'<hex>' AS TEXT)`, never as a quoted string.

---

## Next id

Ids are a prefix and a number. Take the next number from the table, never from memory:

```sql
SELECT 'ISSUE-' || printf('%03d',
       COALESCE(MAX(CAST(substr(id, instr(id, '-') + 1) AS INTEGER)), 0) + 1)
  FROM issue;
```

The same form works for `GOAL-`, `PROJ-`, `REQ-` and `PLAN-`. When an id would pass 999,
the number simply grows to four digits. Views never order by id, so nothing breaks.

---

## Plan card

What Step 2 shows for one pending plan:

```sql
SELECT json_object(
  'id', pl.id, 'kind', pl.kind, 'title', pl.title,
  'requirement', r.id || ' ' || r.title,
  'project', p.id || ' ' || p.title,
  'goal', g.id || ' ' || g.title,
  'needs', COALESCE((SELECT group_concat(c.capability || CASE c.required WHEN 1 THEN '' ELSE '?' END, ' + ')
                       FROM plan_capability c WHERE c.plan_id = pl.id), ''),
  'pin', COALESCE(pl.agent, ''),
  'depends_on', COALESCE((SELECT group_concat(d.depends_on, ', ')
                            FROM plan_dependency d WHERE d.plan_id = pl.id), ''),
  'files', json(pl.files),
  'body', pl.body)
  FROM plan pl
  JOIN requirement r ON r.id = pl.requirement_id
  JOIN project p     ON p.id = r.project_id
  JOIN goal g        ON g.id = p.goal_id
 WHERE pl.id = 'PLAN-014';
```

A capability shown with `?` is preferred, not required. For the card, show only the first
paragraph of `body`. For **Review**, show all of it.

---

## Approve or deny

```sql
-- approve
UPDATE plan SET approval = 'approved', approved_by = 'user', approved_at = <now>
 WHERE id = 'PLAN-014' AND approval = 'pending'
RETURNING id, approval;

-- deny, with the reason in the log
UPDATE plan SET approval = 'rejected', approved_by = 'user', approved_at = <now>
 WHERE id = 'PLAN-014' AND approval = 'pending'
RETURNING id, approval;

INSERT INTO plan_log (plan_id, ts, agent, entry)
VALUES ('PLAN-014', <now>, 'user', CAST(x'<hex of: Denied: {reason}>' AS TEXT));
```

In a shift, `approved_by` is `'orchestrator'` and a shift never denies.

A rejected plan is never deleted. Plans that depend on it wait in `v_plans_blocked` until
the strategist's replacement takes its place in their `plan_dependency` rows.

---

## Link a fix plan

When the strategist reports a fix plan for one or more issues:

```sql
UPDATE issue SET fix_plan_id = 'PLAN-031', status = 'in-progress'
 WHERE id IN ('ISSUE-004', 'ISSUE-007') AND status = 'open'
RETURNING id, status, fix_plan_id;
```

When the fix plan reaches `done`, close its issues:

```sql
UPDATE issue SET status = 'done'
 WHERE fix_plan_id = 'PLAN-031' AND status = 'in-progress'
RETURNING id, status;
```

An issue the user wants to drop: `status = 'wontfix'`, with the reason in its `body` or a
`plan_log` line on the related plan. Check-in only.

---

## File an issue

When a plan fails. The agent's reason goes in `body`, and `found_by` is the agent that
failed, not you:

```sql
INSERT INTO issue (id, project_id, requirement_id, plan_id, source, severity,
                   title, body, found_by, created_at, updated_at)
SELECT (SELECT 'ISSUE-' || printf('%03d',
               COALESCE(MAX(CAST(substr(id, instr(id, '-') + 1) AS INTEGER)), 0) + 1) FROM issue),
       r.project_id, pl.requirement_id, pl.id, 'execution', 'major',
       CAST(x'<hex of: PLAN-014 failed: {short reason}>' AS TEXT),
       CAST(x'<hex of the agent report>' AS TEXT),
       pl.claimed_by, <now>, <now>
  FROM plan pl JOIN requirement r ON r.id = pl.requirement_id
 WHERE pl.id = 'PLAN-014'
RETURNING id;
```

Selecting from `plan` means a wrong plan id inserts nothing, instead of an issue pointing
nowhere.

---

## Review and documentation

### The review matrix

The slices for a finished project: its requirements in dependency order, each with the
files of its done plans.

```sql
SELECT r.id, r.title,
       (SELECT json_group_array(DISTINCT f.value)
          FROM plan p, json_each(p.files) f
         WHERE p.requirement_id = r.id AND p.status = 'done') AS files
  FROM requirement r
 WHERE r.project_id = 'PROJ-002'
 ORDER BY r.priority, r.created_at, r.id;
```

### Filing the merged findings

One statement per merged finding, all in one script. The hex rule applies to title and
body. `found_by` names every lens that reported it.

```sql
PRAGMA foreign_keys = ON;
UPDATE guild_state SET value = 'orchestrator' WHERE key = 'actor';

INSERT INTO issue (id, project_id, requirement_id, plan_id, source, severity,
                   title, body, file, line, found_by, created_at, updated_at)
SELECT (SELECT 'ISSUE-' || printf('%03d',
               COALESCE(MAX(CAST(substr(id, instr(id, '-') + 1) AS INTEGER)), 0) + 1) FROM issue),
       p.id, 'REQ-004', 'PLAN-011', 'review', 'major',
       CAST(x'<hex title>' AS TEXT), CAST(x'<hex body>' AS TEXT),
       'src/lib/server/users.ts', 42, 'reviewer:edge-cases+security',
       <now>, <now>
  FROM project p
 WHERE p.id = 'PROJ-002'
   AND EXISTS (SELECT 1 FROM requirement r WHERE r.id = 'REQ-004' AND r.project_id = p.id)
   AND EXISTS (SELECT 1 FROM plan pl WHERE pl.id = 'PLAN-011' AND pl.requirement_id = 'REQ-004')
RETURNING id, severity, title;
```

The two `EXISTS` lines stop a finding from pointing at a requirement or plan of another
project. Drop the one whose value is `NULL`, and write `NULL` in its column. No row back
means the finding named something outside the project: file it again with that field
`NULL`.

### Closing the review and the documentation

```sql
-- every reviewer reported and every finding is filed
UPDATE project SET reviewed_at = <now>
 WHERE id = 'PROJ-002' AND status = 'done' AND reviewed_at IS NULL
RETURNING id, reviewed_at;

-- the librarian has reported and its docs read back
UPDATE project SET documented_at = <now>
 WHERE id = 'PROJ-002' AND reviewed_at IS NOT NULL AND documented_at IS NULL
RETURNING id, documented_at;
```

Check the librarian's work before setting `documented_at`:

```sql
SELECT slug, kind, status, title FROM doc WHERE project_id = 'PROJ-002';
SELECT slug, group_concat(tag, ' ') FROM doc_tag
 WHERE slug IN (SELECT slug FROM doc WHERE project_id = 'PROJ-002') GROUP BY slug;
SELECT from_slug, rel, to_slug FROM doc_edge
 WHERE from_slug IN (SELECT slug FROM doc WHERE project_id = 'PROJ-002');
```

No doc at all means the documentation did not happen. Do not set `documented_at`. Report it.

When the librarian reports that a new doc replaces an old one, the `supersedes` edge is its
write and the old doc's status is yours:

```sql
UPDATE doc SET status = 'superseded'
 WHERE slug = 'old-users' AND status = 'current'
   AND EXISTS (SELECT 1 FROM doc_edge WHERE rel = 'supersedes' AND to_slug = 'old-users')
RETURNING slug, status;
```
