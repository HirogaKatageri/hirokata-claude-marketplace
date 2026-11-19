---
name: shift
description: >
  This skill should be used when the user asks to "work a shift", "start a shift",
  "run unattended", "keep working while I'm away", "guild shift", "take the night
  shift", "work the board while I'm out", "run autonomously", "keep going without me",
  "work overnight", "run until you need me", or any request for the guild to keep
  working with nobody watching. Runs the check-in flow with no user: approves its own
  plans, writes missing projects, requirements and plans without interviews, executes
  ready plans in parallel, reviews and documents finished projects, commits per
  completed plan, and stops when the budget runs out or only the user can move the
  board forward.
version: 6.0.0
user-invocable: true
allowed-tools: Bash(tursodb *), Bash(git *), Bash(python3 *)
---

# Guild Shift — the check-in flow with nobody watching

**A shift is `guild:check-in` with the user taken out.** It runs the same loop: approvals,
fill, execute, review, document. Read `guild:check-in` and follow it exactly, including its
two references, `dispatch-prompts.md` and `board-sql.md`. This page only says **what changes
when nobody is there.**

**Load `guild:warehouse` before the first step.** At 3am nobody notices a swallowed error,
so read every `RETURNING` and every error line.

**Backend:** local only, as in check-in. On `backend: kumiai`, stop and say the Kumiai
backend has not moved to schema 10 yet.

## What changes without the user

| Check-in step | In a shift |
|---|---|
| 1.1 an old board | Stop and report it. Never archive a board on your own. |
| 1.5 route | No question. Run the flow. An empty board (no open goal) ends the shift as `idle`. |
| 2 approvals | **The orchestrator approves**, under the rules in Step 2 below. It never denies. |
| 3 fill | The project-manager **does not interview**. Every prompt says `MODE: shift`. |
| 4.4 `NEEDS INPUT:` | Cannot be answered. The plan is recorded as **failed**, with the questions as the reason. |
| 4.6 issues waiting | No question. Go straight back to Step 3 for fix plans, within the rules below. |
| 5 goals complete | Never close a goal. List them in the report. |

Everything else — the roster match, file and serial conflicts, recording results, reviews,
documentation — is exactly check-in.

## Before you walk away — what you are authorizing

Say this to the user **before the shift starts**. They are handing an unsupervised process
their working tree.

| A shift MAY | A shift MAY NOT |
|---|---|
| Write projects, requirements and plans for open goals | Create, change or close a goal |
| Approve plans that meet the Step 2 rules | Deny a plan, or approve one that fails the rules |
| Run approved plans in parallel | Answer a question on the user's behalf |
| Write fix plans for issues, within the Step 3 cap | Mark an issue `wontfix` |
| Review and document finished projects | Archive or delete a board, or any row |
| Commit each completed plan on a shift branch | Commit to the default branch, push, or rewrite history |
| File issues | Create an agent file |

None of this is enforced by anything. SQL has no identity, git has no allowlist, and
`guild_state.actor` is a label. Every line is a promise you keep.

---

## Step 1 — Preflight

```bash
export PATH="$HOME/.turso:$PATH"
[ -f .guild/config.yaml ] || echo "no guild here"
```

No guild → say so and stop. `guild:check-in` creates one. Use `-m list` for every query:
the default box output cuts long values short.

Run check-in Steps 1.1 to 1.3 (board version, roster, recovery), then read three things,
writing nothing:

```sql
-- is a shift already open? An open shift is a `started` with no `ended`.
SELECT eo.subject_id, eo.ts, eo.payload FROM event eo
 WHERE eo.subject_type = 'shift' AND eo.verb = 'started'
   AND NOT EXISTS (SELECT 1 FROM event ec
                    WHERE ec.subject_type = 'shift' AND ec.verb = 'ended'
                      AND ec.subject_id = eo.subject_id)
 ORDER BY eo.ts DESC, eo.id DESC LIMIT 1;

SELECT fact, value FROM v_brief;

-- is the working tree clean?
```

```bash
git status --porcelain     # must print nothing
```

- **A shift is already open** → resume it with the budget in its `started` payload. Do not
  open a second one and do not ask the budget again.
- **The working tree is dirty** → stop with reason `operator` and say what is dirty. Never
  stash, commit or clean the user's work.
- **No open goal** → stop with reason `idle`. A shift never invents a goal.

**Agree the budget before the first step.** Defaults: **10 plans** and **60 minutes**. If the
user did not name one, ask once with `AskUserQuestion`, then never again. The budget is
fixed when the shift opens. A ceiling you can raise from inside the loop is not a ceiling.

### Open the shift

The `started` and `ended` events are the only hand-written rows in `event`:

```sql
PRAGMA foreign_keys = ON;
UPDATE guild_state SET value = 'orchestrator' WHERE key = 'actor';

INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), 'orchestrator', 'started', 'shift',
       'SHIFT-' || strftime('%Y%m%dT%H%M%SZ', 'now'),
       json_object('max_plans', 10, 'max_minutes', 60,
                   'branch', 'guild/shift-' || strftime('%Y%m%dT%H%M%SZ', 'now'))
 WHERE NOT EXISTS (SELECT 1 FROM event eo
                    WHERE eo.subject_type = 'shift' AND eo.verb = 'started'
                      AND NOT EXISTS (SELECT 1 FROM event ec
                                       WHERE ec.subject_type = 'shift' AND ec.verb = 'ended'
                                         AND ec.subject_id = eo.subject_id))
RETURNING subject_id, ts, payload;

INSERT INTO guild_state (key, value) VALUES ('shift:stall', '0')
ON CONFLICT(key) DO UPDATE SET value = excluded.value;
INSERT INTO guild_state (key, value) VALUES ('shift:events', '0')
ON CONFLICT(key) DO UPDATE SET value = excluded.value;
```

Zero rows back from the first insert means a shift was already open. Read it and use its
budget.

### The branch

One branch per shift, named in the `started` payload. Work in shared projects is committed
there. A `worktree` project commits on its own worktree's branch.

```bash
default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
default=${default:-$(git config --get init.defaultBranch || echo main)}
git switch -c "guild/shift-<ts>" 2>/dev/null || git switch "guild/shift-<ts>"
```

**Never commit while the default branch is checked out.** The git commands a shift may run
are exactly: `status`, `rev-parse`, `symbolic-ref`, `config --get`, `branch`, `switch`,
`worktree add`, `diff`, `log`, `add -- <paths>`, `commit`, `checkout -- <paths>`. Never
`push`, `fetch`, `pull`, `rebase`, `reset`, `stash`, `tag`, `cherry-pick`, or anything with
`-f` or `--force`.

---

## Step 2 — Approvals, by the orchestrator

For each row of `v_plans_pending_approval`, approve it **only when all of these hold**:

1. `has_capabilities = 1`, and the roster from check-in 1.2 has an agent that can run it
   (the pin exists, or `roster.py --covers` returns a row).
2. Every plan it depends on exists and is not `rejected`:

   ```sql
   SELECT d.depends_on, p.approval FROM plan_dependency d JOIN plan p ON p.id = d.depends_on
    WHERE d.plan_id = 'PLAN-014' AND p.approval = 'rejected';      -- must return nothing
   ```
3. Its body says what to do and how to check it. An empty or one-line body is not a plan.

```sql
UPDATE plan SET approval = 'approved', approved_by = 'orchestrator',
                approved_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
 WHERE id = 'PLAN-014' AND approval = 'pending'
RETURNING id, approval;
```

A plan that fails a rule stays `pending` for the user, and the report names the rule. Rule 1
failing is a roster gap. The fix is an agent file, which a shift never writes.

---

## Step 3 — Fill, with two limits

Run check-in Step 3 as written, with `MODE: shift` in every prompt. Two limits keep an
unattended run from feeding itself forever:

- **One fix plan per issue.** Write a fix plan only for an issue that has never had one.
  An issue whose fix plan was rejected or failed waits for the user.
- **A failed fix plan is not fixed again.** An `execution` issue filed against a plan of kind
  `fix` waits for the user. Fixing the fix is how a night disappears.

```sql
-- the issues a shift may plan fixes for
SELECT i.id, i.project_id, i.severity, i.title FROM v_open_issues i
 WHERE i.status = 'open' AND i.fix_plan_id IS NULL
   AND NOT (i.source = 'execution'
            AND (SELECT kind FROM plan WHERE id = i.plan_id) = 'fix');
```

---

## Step 4 — Execute, then commit each plan

Run check-in Step 4 as written. Three things change.

### 4.1 Commit each completed plan

When a plan is recorded `done`, commit **only that plan's files**:

```bash
git add -- src/routes/signup/+page.svelte src/lib/server/users.ts
git commit -m "$(printf 'feat(registration): sign-up form\n\nGuild-Plan: PLAN-014\nGuild-Requirement: REQ-006\nGuild-Project: PROJ-002\n')"
```

Use Conventional Commits for the subject. Stage the plan's `files` by path. If the agent
reported touching other files, stage those too, and only when no running plan lists them.

### 4.2 Quarantine a failed plan's edits

When a plan fails, after filing its `execution` issue, move its partial edits aside so the
next plan starts from a clean tree. Never delete them:

```bash
q=".guild/quarantine/PLAN-014-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$q"
git diff -- <the plan's files> > "$q/partial.diff"
git checkout -- <the plan's files>
```

Files the plan created are **moved** into the quarantine folder, not removed. Put the
folder path in the issue's body.

**A stuck plan whose fix is done** is set back to `open` once, so it runs again. If it fails
a second time, leave it for the user.

### 4.3 A file collision stops new work

If a finished plan changed a file that a still-running plan lists, two agents wrote one file.
Stop starting plans, let the running ones finish and record them, file a `discovered` issue
naming both plans and the file, and end the shift with reason `collision`. **Leave the tree
exactly as it is.** Reconciling it is the user's job.

---

## Step 5 — The stop check, after every recorded result

```sql
-- plans started this shift
SELECT COUNT(DISTINCT subject_id) FROM event
 WHERE subject_type = 'plan' AND verb = 'moved'
   AND json_extract(payload, '$.to') = 'in-progress'
   AND ts >= (SELECT ts FROM event WHERE subject_type = 'shift' AND verb = 'started'
                AND subject_id = 'SHIFT-…');

-- minutes spent
SELECT CAST((julianday('now') - julianday(
         (SELECT ts FROM event WHERE subject_type = 'shift' AND verb = 'started'
            AND subject_id = 'SHIFT-…'))) * 1440 AS INTEGER);

-- events since the shift opened, for the stall check
SELECT COUNT(*) FROM event
 WHERE ts >= (SELECT ts FROM event WHERE subject_type = 'shift' AND verb = 'started'
                AND subject_id = 'SHIFT-…');
```

**Budget reached** → start no new plan, no new fill and no new review. Let running agents
finish and record them, then stop.

**Stall check.** When no agent is running, compare the event count with
`guild_state['shift:events']`. The same number twice in a row means the loop is spinning
without changing anything: stop with `infrastructure`. Write both keys back every time,
including when nothing changed.

**Stop on the first of these, in this order:**

| # | Reason | When |
|---|---|---|
| 1 | `collision` | Step 4.3 |
| 2 | `infrastructure` | the stall check fired, or an agent never reported back |
| 3 | `max-plans` | plans started ≥ `max_plans` |
| 4 | `max-minutes` | minutes ≥ `max_minutes` |
| 5 | `needs-user` | nothing can run, and something waits on the user: pending plans the rules would not approve, issues past the fix limits, stuck plans, goals to sign off |
| 6 | `idle` | nothing can run and nothing waits on the user |
| 7 | `operator` | the user ended it |

`needs-user` is the shift succeeding. It did everything it was allowed to and stopped at a
decision only a person can make.

### Close the shift

```sql
INSERT INTO event (ts, actor, verb, subject_type, subject_id, payload)
SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), 'orchestrator', 'ended', 'shift',
       eo.subject_id,
       json_object('reason', 'needs-user', 'note', CAST(x'<hex>' AS TEXT),
                   'plans', 6, 'minutes', 48)
  FROM event eo
 WHERE eo.subject_type = 'shift' AND eo.verb = 'started'
   AND NOT EXISTS (SELECT 1 FROM event ec
                    WHERE ec.subject_type = 'shift' AND ec.verb = 'ended'
                      AND ec.subject_id = eo.subject_id)
 ORDER BY eo.ts DESC, eo.id DESC LIMIT 1
RETURNING subject_id, payload;
```

`reason` comes only from the table above. The morning report and `guild:brief` read it back.

---

## Step 6 — The morning report

The brief says where the project stands. This report says **what happened while the user
was away**. Its window starts where the shift started:

```sql
SELECT json_object('ts', ts, 'actor', actor, 'verb', verb, 'type', subject_type,
                   'id', subject_id, 'title', subject_title, 'phrase', phrase)
  FROM v_recent_activity
 WHERE ts >= (SELECT ts FROM event WHERE subject_type = 'shift' AND verb = 'started'
               ORDER BY ts DESC, id DESC LIMIT 1);

SELECT id, title FROM v_plans_pending_approval;
SELECT id, issue_id, issue_title, title FROM v_plans_stuck;
SELECT id, wait, title FROM v_plans_blocked;
SELECT id, project_id, source, severity, title FROM v_open_issues;
SELECT id, success_criteria, title FROM v_goals_complete;
```

Say it in this order, naming things rather than counting them:

1. **Why it stopped**, in one sentence.
2. **What waits on the user**: plans it would not approve and which rule failed, issues past
   the fix limits, stuck plans with their quarantine folder, goals to sign off.
3. **What got done**: plans completed with their commits, projects reviewed and documented,
   docs written.
4. **What it would do next.**

"PLAN-014 failed twice; its edits are in `.guild/quarantine/PLAN-014-…`" is a report. "1
failure" is not.

## Arming it, and notifying on it

Running shifts on a schedule, and push notifications when a shift needs the user, are both
opt-in. Set them up only when asked: `references/automation.md`.

## Rules — the checklist

1. A shift is check-in without the user. Follow check-in. This page only lists the changes.
2. Approve only under the Step 2 rules. Never deny, never answer for the user, never close a
   goal.
3. One fix plan per issue, and a failed fix is not fixed again.
4. Commit each completed plan on the shift branch, its files only. Never push, never commit to
   the default branch.
5. Quarantine a failed plan's edits. Never delete them.
6. The budget is fixed when the shift opens.
7. `started` and `ended` are the only hand-written events.
8. End with the reason first, then what waits on the user.
