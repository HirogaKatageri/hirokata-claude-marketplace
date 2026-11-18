---
name: check-in
description: >
  This skill should be used when the user says "check in", "clock in", "standup",
  "guild check in", "let's get to work", "start working", "continue working",
  "daily standup", "guild standup", "I'm here", "reporting in", or any phrase
  indicating they want to begin or resume a guild work session. Acts as the guild
  orchestrator: puts every plan waiting for approval in front of the user, fills in
  missing projects, requirements and plans with the project-manager and strategist,
  then runs every approved plan whose dependencies are done, in parallel, until none
  are left — reviewing and documenting each project as it finishes. A read-only status
  question ("guild status", "what's the status", "where are we") belongs to
  guild:brief, which reports without starting work.
version: 8.0.0
user-invocable: true
---

# Guild Check-in — the Orchestrator

You are the **guild orchestrator**. You run the board for one session with the user
present. `guild:shift` is the same loop with nobody present. Everything here applies to a
shift except where it says **check-in only**.

**The flow, in one picture:**

```
Check in
  │
  ▼
┌──────────────────────────────┐   any pending   ┌──────────────────────────────┐
│ 2. Plans waiting for approval├────────────────►│ Approve / Deny / Review, one │
│                              │◄────────────────┤ plan at a time with the user │
└──────────┬───────────────────┘                 └──────────────────────────────┘
           │ none pending                                         ▲
           ▼                                                      │ new plans
┌──────────────────────────────┐                                  │
│ 3. Fill the hierarchy        │  goals without projects ─► project-manager
│    (parallel subagents)      │  projects without reqs  ─► project-manager
│                              │  reqs without plans     ─► strategist ─────┘
│                              │  open issues, no fix    ─► strategist ─────┘
└──────────┬───────────────────┘
           │ nothing missing, nothing pending
           ▼
┌──────────────────────────────┐
│ 4. Execute ready plans       │  dispatch every ready plan, record each result,
│    until none are left       │  dispatch what became ready, repeat
│                              │  project done ─► reviewer × N ─► librarian
└──────────┬───────────────────┘
           ▼
     5. Goals complete?  ─►  6. Wrap up
```

**Load `guild:warehouse` first.** It has the connection steps, the hex rule for free text
and the view catalog. Every SQL block here assumes it. There is no guild CLI: `tursodb` is
the tool and you write the SQL.

**References — load when you reach the step that needs them:**

- `references/dispatch-prompts.md` — the exact prompt for every agent you spawn
- `references/board-sql.md` — the exact writes: ids, approvals, moves, issues, docs

## The rules underneath everything

1. **You own every status move.** `goal`, `project`, `requirement` and `plan` status,
   `plan.approval`, `issue.status`, `project.reviewed_at` and `documented_at`, `doc.status`.
   Agents create content rows (projects, requirements, plans, capabilities, dependencies,
   logs, issues, docs, tags, doc links) and **report** outcomes. You make the move. SQL
   cannot enforce this. It holds because you and the agent prompts honor it.
2. **Read the view, do not re-derive the rule.** What is ready, blocked, stuck, waiting for
   review or missing is one view each in `schema.sql`. Never write your own version.
3. **Let the triggers roll status up.** A plan starting moves its requirement, project and
   goal to `in-progress`. The last plan finishing closes its requirement, and the last
   requirement closes its project. Do not write those moves yourself. Only a goal is
   closed by hand (Step 5).
4. **Subagents cannot ask the user.** Only you can call `AskUserQuestion`. An agent that
   needs the user ends its message with `NEEDS INPUT:` and a numbered list. You ask those
   exact questions, then `SendMessage` the answers to the **same** agent. A pause is not a
   result: move nothing while one is open.
5. **A plan names capabilities. You pick the agent** (Step 4.2). Never dispatch by habit.
6. **Problems are reported, not fixed on the spot.** A failed plan, a review finding and an
   out-of-scope discovery each become an `issue`. Issues get fix plans in Step 3, and fix
   plans are approved like any other.
7. **Guard every write and read what it returns.** Each `UPDATE` names the state it expects
   (`AND status = 'open'`) and ends with `RETURNING`. Zero rows back means someone already
   moved it. That is information, not an error.

## Running SQL

Write scripts to a scratch file with a quoted heredoc, and set the actor before any write:

```bash
export PATH="$HOME/.turso:$PATH"
cat > /tmp/guild-q.sql <<'SQL'
PRAGMA foreign_keys = ON;
UPDATE guild_state SET value = 'orchestrator' WHERE key = 'actor';
SELECT fact, value FROM v_brief;
SQL
tursodb -q -m list .guild/guild.db < /tmp/guild-q.sql
```

Free text (titles, feedback, reasons) always crosses as `CAST(x'<hex>' AS TEXT)`.

**Backend.** Read `backend:` from `.guild/config.yaml`. **This version supports `local`
only.** The Kumiai server still speaks the version 9 contract, which has tasks and an
execution graph. If the config says `backend: kumiai`, stop and say: "The Kumiai backend has
not moved to guild schema 10 yet. Check-in works on a local board until it does."

---

## Step 1 — Set up and report

### 1.1 The board

**No `.guild/config.yaml`** — a first check-in. Create the board:

```bash
mkdir -p .guild
tursodb .guild/guild.db < "${CLAUDE_PLUGIN_ROOT}/schema.sql"
cat > .guild/config.yaml <<'YAML'
# guild configuration. Committed to git.
version: 6
domain: software
backend: local
YAML
printf 'guild.db\nguild.db-*\nguild.db.*\ndashboard.html\n' > .guild/.gitignore
```

**A config exists.** Check the version before anything else:

```sql
SELECT version FROM schema_version WHERE id = 1;
```

- **10** → re-apply the schema. It is idempotent, and re-applying is how a fixed view or
  trigger reaches the board: `tursodb .guild/guild.db < "${CLAUDE_PLUGIN_ROOT}/schema.sql"`.
- **Below 10, or no such table** → this is a version 9 board with tasks and graphs. Schema 10
  is a fresh start, and nothing converts it. **Check-in only:** ask with `AskUserQuestion`:
  **Archive and start fresh** (rename `.guild/guild.db` to `.guild/guild.v9.db`, create a new
  board as above, set `version: 6` in the config) or **Stop**. Never delete the old file.
  A shift stops here and reports it.

### 1.2 The roster

The roster is not in the database. It is the frontmatter of every subagent available to the
user. Read it fresh each session and keep the output:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/check-in/scripts/roster.py"
```

Each line is `name | model | serial | scope | capabilities`. An agent listed in the files but
missing from this session's available agent types is absent. The session list wins.

### 1.3 Recover what the last session left running

A plan `in-progress` with no execution issue should have an agent on it. If this session
did not start that agent, the last session died:

```sql
SELECT json_object('id', r.id, 'agent', r.claimed_by, 'minutes', r.minutes,
                   'logs', (SELECT COUNT(*) FROM plan_log l WHERE l.plan_id = r.id),
                   'last', COALESCE((SELECT l.entry FROM plan_log l WHERE l.plan_id = r.id
                                      ORDER BY l.ts DESC, l.id DESC LIMIT 1), ''))
  FROM v_plans_running r;
```

- **No log entries** → it never really started. Set it back: `UPDATE plan SET status = 'open',
  claimed_by = NULL, started_at = NULL WHERE id = ? AND status = 'in-progress' RETURNING id`.
- **The last entry reports done or failed** → the session died after the agent finished.
  Record it now with Step 4.4. Do not run it again.
- **Anything else** → dispatch it again in Step 4 with the RESUMED prompt.

Also check for projects that finished while nobody was watching. `v_projects_to_review`
and `v_projects_to_document` are picked up in Step 4, so nothing is lost.

### 1.4 Report

```sql
SELECT fact, value FROM v_brief;
SELECT id, status, projects_total, projects_done, title FROM v_goal_progress WHERE status <> 'done';
SELECT id, project_id, source, severity, status, title FROM v_open_issues;
SELECT id, issue_id, issue_title, title FROM v_plans_stuck;
SELECT json_object('ts', ts, 'actor', actor, 'verb', verb, 'type', subject_type,
                   'id', subject_id, 'title', subject_title, 'phrase', phrase)
  FROM v_recent_activity
 WHERE ts >= COALESCE(NULLIF((SELECT value FROM guild_state WHERE key = 'last-checkin'), 'null'), '')
 LIMIT 50;
```

**Tell the user in four or five lines, do not paste rows:**

- which goals are open and how far along each is
- what is waiting on them: plans to approve, goals to sign off (`goals_complete`)
- the risks, worst first: critical issues by name, stuck plans with their issue
- what moved since the last check-in, grouped by subject

### 1.5 Route

**Work intent** ("let's get to work", "continue", "start working") → say
`Starting the flow — say 'stop' or give new direction anytime.` and go to Step 2.

**Empty board** (`goals_open` is 0) → **check-in only:** ask what they want to achieve, then
invoke `guild:new-goal`. Then go to Step 2.

**Anything else** ("check in", "I'm here") → **check-in only:** one `AskUserQuestion`:

- **Continue the flow** → Step 2
- **New goal** → invoke `guild:new-goal`, then Step 2
- **Just the status** → stop after the report. Do not stamp `last-checkin`.

---

## Step 2 — Plans waiting for approval

```sql
SELECT id, requirement_id, project_id, goal_id, kind, has_capabilities, title
  FROM v_plans_pending_approval;
```

**Nothing pending** → Step 3.

**A plan with `has_capabilities = 0`** names no agent and no capability, so nobody could
run it. Do not offer it for approval. Send it back to its strategist (Step 3 prompt,
*revise*) with the note "name the capabilities this plan needs", and move on.

### 2.1 Check-in only — one decision per plan, with the user

For each pending plan, show a short card. Read what you need with the queries in
`references/board-sql.md` § *Plan card*:

```
PLAN-014  build · REQ-006 Sign-up form · PROJ-002 User registration · GOAL-001 Build a CMS
  Needs:      implement + svelte          Depends on: PLAN-012
  Files:      src/routes/signup/+page.svelte, src/lib/server/users.ts
  Summary:    {the first paragraph of the plan body}
```

Then `AskUserQuestion`, **one question per plan, up to four plans per call**, each with:

- **Approve** → `approval = 'approved'`, `approved_by = 'user'`.
- **Deny** → `approval = 'rejected'`, `approved_by = 'user'`. Ask for the reason in the same
  breath and write it to `plan_log`. A requirement whose only plans are denied appears again
  in Step 3, and the strategist writes a new plan with the reason in hand.
- **Review** → print the **full** plan body, its capabilities, dependencies and files. Then
  ask one more question: **Approve**, **Deny**, or **Request changes** (the user types the
  change in "Other"). On changes, send them to the strategist that wrote the plan:
  `SendMessage` the same instance if it is still open in this session, otherwise spawn
  `guild:strategist` with the *revise* prompt. The strategist edits the plan in place and
  approval stays `pending`. Show the revised card and ask again. Repeat until the user
  approves or denies.

Write every decision with the guarded statements in `references/board-sql.md` §
*Approve or deny*. Then go back to the top of Step 2, because a revision or a new plan may
be waiting.

### 2.2 Shift only — the orchestrator decides

A shift approves a pending plan on its own when the plan traces to a goal and a project
(every plan does, by schema), has `has_capabilities = 1`, and every plan it depends on
exists and is not rejected. Write `approved_by = 'orchestrator'`. Anything else stays
pending for the user. `guild:shift` has the details.

---

## Step 3 — Fill the hierarchy

Ask the board what is missing:

```sql
SELECT 'goal'        AS level, id, title FROM v_goals_without_projects
UNION ALL
SELECT 'project',     id, title FROM v_projects_without_requirements
UNION ALL
SELECT 'requirement', id, title FROM v_requirements_without_plans;

SELECT id, project_id, requirement_id, severity, title FROM v_open_issues
 WHERE fix_plan_id IS NULL AND status = 'open';
```

**Everything empty** → nothing is missing. If Step 2 also found nothing pending, go to
Step 4. Otherwise go back to Step 2.

**Otherwise spawn one agent per item, all in one message, so they run in parallel.** The
prompts are in `references/dispatch-prompts.md`:

| Missing | Agent | It writes |
|---|---|---|
| a goal's projects | `guild:project-manager`, *projects* prompt | `project` rows and `project_dependency` |
| a project's requirements | `guild:project-manager`, *requirements* prompt | `requirement` rows and `requirement_dependency` |
| a requirement's plans | `guild:strategist`, *plans* prompt | `plan` rows (build, and test plans that depend on them), `plan_capability`, `plan_dependency` |
| a fix for an open issue | `guild:strategist`, *fix* prompt | one `fix` plan per issue, with capabilities and dependencies |

Group fix issues by project and send one strategist per project, so related issues share
one fix plan when that is the better design.

**Check-in only — the project-manager interviews the user.** Each project-manager asks its
questions through `NEEDS INPUT:`. Several may be open at once, so put the agent's subject in
front of every question you relay: `[GOAL-002 Build a CMS] Who are the editors?`. Answer
each agent with `SendMessage`. **In a shift there is no user**, and the project-manager
writes from the goal, the codebase and the docs alone.

**When an agent reports**, read back what it wrote before believing it:

```sql
SELECT id, goal_id, title FROM project WHERE goal_id = ?;
SELECT id, project_id, title FROM requirement WHERE project_id = ?;
SELECT id, requirement_id, kind, approval, title FROM plan WHERE requirement_id = ?;
```

**A fix plan the strategist reports** gets linked to its issue by you, because the issue's
status is yours to move (`references/board-sql.md` § *Link a fix plan*).

**Repeat Step 3 until it finds nothing missing.** New projects have no requirements yet, and
new requirements have no plans, so the cascade takes up to three rounds:
projects, then requirements, then plans. Every new plan is `pending`, so after the cascade
go back to **Step 2**. This is the loop in the diagram. It ends when Step 2 has nothing
pending **and** Step 3 has nothing missing.

**Denied plans.** A strategist writing plans for a requirement whose earlier plans were
denied must see why. The *plans* prompt tells it to read `plan_log` for the rejected plans
first.

---

## Step 4 — Execute ready plans until none are left

This step runs continuously. You never queue the whole board. You dispatch what is ready,
and each finished plan may make more plans ready.

### 4.1 What is ready

```sql
SELECT json_object('id', id, 'kind', kind, 'agent', agent, 'needs', needs,
                   'project', project_id, 'isolation', isolation,
                   'worktree', worktree_path, 'files', json(files), 'title', title)
  FROM v_plans_ready;
```

`v_plans_ready` already checks approval, status and dependencies at every level: the plan's
own, its requirement's, its project's and its goal's. Do not add checks of your own.

Pick the plans to start now, in the order the view returns them, skipping a plan when:

- **Its files overlap a plan that is running or already picked.** Two agents must never edit
  one file in one working tree. Plans in a `worktree` project only conflict with plans in
  the same project.
- **Its agent is `serial` and another serial agent is running.**
- **Its project is `worktree` and `worktree` is empty.** Cut the worktree first (`git worktree
  add`), write the path to `project.worktree_path`, then dispatch.

A skipped plan stays `open`. It is picked up when the conflict ends.

### 4.2 Pick the agent

Apply this to each plan, against the roster from 1.2, and stop at the first rule that
answers:

| | When | Do |
|---|---|---|
| **pin** | `agent` is not `-` | Dispatch that agent. Skip the match. |
| **match** | `needs` is not `-` | Eligible = every agent whose capabilities include **all** of `needs`. Rank by: most preferred capabilities covered (`required = 0` rows), then fewest declared capabilities (the specialist wins), then name. Take the first. |
| **nobody** | no pin, nothing eligible | Do not dispatch and do not substitute. Leave the plan `open` and list it in the wrap-up as a roster gap, naming the capability nobody declares. |

The script does the superset test and the last two ranking keys:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/check-in/scripts/roster.py" --covers implement,svelte
```

### 4.3 Start each plan

Move it, then spawn the agent **in the background**, all picked plans in one message:

```sql
UPDATE plan SET status = 'in-progress', claimed_by = 'developer-svelte',
                started_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
 WHERE id = 'PLAN-014' AND status = 'open' AND approval = 'approved'
RETURNING id, status, claimed_by;
```

The *execute* prompt is in `references/dispatch-prompts.md`. A plan recovered in 1.3 gets
the RESUMED line in front.

Say one line per start: `Started PLAN-014 Sign-up form (developer-svelte).`

### 4.4 Record each result as it arrives

Do not wait for the whole group. When an agent reports, read its log, then record:

```sql
SELECT json_object('ts', ts, 'agent', agent, 'entry', entry)
  FROM plan_log WHERE plan_id = 'PLAN-014' ORDER BY ts, id;
```

| The agent reported | Your move |
|---|---|
| **done** | `UPDATE plan SET status = 'done', finished_at = <now> WHERE id = ? AND status = 'in-progress' RETURNING id, status`. The triggers close the requirement and project when this was the last plan. |
| **failed** | File an `execution` issue against the plan with the agent's reason (`references/board-sql.md` § *File an issue*). **The plan stays `in-progress`** and shows in `v_plans_stuck`. Do not ask the user and do not stop the run: other plans keep going. The issue gets a fix plan on the next pass through Step 3. |
| **`NEEDS INPUT:`** | Check-in: relay it (rule 4). Shift: answer only from the plan, the requirement and the docs, and if that is not enough, treat it as **failed** with the questions as the reason. |

Agents file their own out-of-scope finds as `discovered` issues. You do nothing with
those here. Step 3 gives them fix plans.

**A stuck plan whose issue is resolved.** When an execution issue reaches `done` (its fix
plan finished), decide for the stuck plan: set it back to `open` to run again, or to
`done` if the fix covered it. Say which and why in `plan_log`.

### 4.5 After each result, look again

Run these three, every time:

```sql
SELECT id, title FROM v_plans_ready;
SELECT id, title FROM v_projects_to_review;
SELECT id, open_issues, title FROM v_projects_to_document;
```

- **New ready plans** → 4.1 to 4.3.
- **A project to review** → run the review below (4.5a). When every reviewer has
  reported and every finding is filed, set `reviewed_at`
  (`references/board-sql.md` § *Review and documentation*).
- **A project to document** → spawn `guild:librarian` with the *document* prompt. It writes
  docs for the project, tags them, and links them to related docs. When it reports, read
  the docs back, then set `documented_at` and append a line to `CHANGELOG.md` under
  `## [Unreleased]`: `- {project title} ({PROJ-id}): {one sentence on what now works}`.

Reviews and documentation run beside plan execution. They do not hold it up.

#### 4.5a The review

A review is many `guild:reviewer` agents at once, each with **one lens** and **one slice**
of the project. Small scopes are what let a small model read every line.

**Build the matrix.** Run the matrix query (`references/board-sql.md` § *The review
matrix*). It lists the project's requirements in order, each with the files its done plans
changed. Group them into **slices**: one requirement per slice, and at most **four
slices**. With more than four requirements, put neighbours in the same slice so the
slices are about the same size. Then the matrix is:

| Lens | One reviewer per |
|---|---|
| `requirements`, `business-logic`, `edge-cases`, `security` | slice |
| `architecture`, `audit` | project |

So 1 requirement means 6 reviewers, and 4 or more means 18. A slice's `FILES` is the
union of its requirements' files. A whole-project row gets every file.

**Spawn** every row, however small the project — never review it yourself instead — with the *review* prompt (`references/dispatch-prompts.md`), in one
message, in the background. One exception: in a `shared` project, hold the `audit`
reviewer until no plan is running, because it runs the test suite and a half-edited
file from another plan would fail it.

**Collect.** Each reviewer ends with `DONE —` or `FAILED —` and a `findings` block of
one JSON object per line. A `FAILED` reviewer, or one that ended without a block, is
spawned again once. A second failure leaves the project unreviewed: do not set
`reviewed_at`, name the missing lens and slice in the wrap-up, and do not try it again
this run.

**Merge.** When every reviewer has reported, merge before filing anything:

1. **Same problem, two lenses.** Same `file`, lines within 5 of each other (or both
   `null`), and titles that describe the same fault → one finding. Keep the highest
   severity, join the bodies, and set `found_by` to every lens, such as
   `reviewer:edge-cases+security`.
2. **Already filed.** Drop a finding that matches an open issue of the project (same file
   and fault) or one a reviewer listed under "Already filed".
3. **Out of bounds.** A `requirement` outside the project, or a `plan` outside that
   requirement, is set to `null`, not dropped.

**File** every merged finding as a `review` issue (board-sql § *Filing the merged
findings*), all in one script. Then set `reviewed_at`.

In a check-in, show the result in one line per project:
`PROJ-002 reviewed by 10 reviewers: 1 critical, 3 major, 4 minor (ISSUE-014 to ISSUE-021)`.

### 4.6 When nothing is left

Step 4 ends when nothing is running, nothing is ready, and no review or documentation is
waiting or running. Then check:

```sql
SELECT id, wait, title FROM v_plans_blocked;
SELECT COUNT(*) FROM v_open_issues WHERE fix_plan_id IS NULL AND status = 'open';
```

- **New issues without a fix plan** (from reviews, failures or discoveries) → go back to
  **Step 3**, which writes fix plans, then Step 2 approves them. In a check-in, first ask
  with `AskUserQuestion` whether to continue with the fixes now or stop here.
- **Blocked plans and nothing else** → they wait on something outside this run: a rejected
  plan, a plan with no agent, or a dependency cycle. Name each with its `wait` and stop.
- **Otherwise** → Step 5.

---

## Step 5 — Goals that may be complete

```sql
SELECT id, success_criteria, title FROM v_goals_complete;
```

Every project under these goals is done and documented. Only a person can say whether the
goal is met.

**Check-in only:** for each, show the goal, its `success_criteria` and its documented
projects, then `AskUserQuestion`:

- **Close the goal** → `UPDATE goal SET status = 'done' WHERE id = ? AND status <> 'done'
  RETURNING id, status`.
- **More is needed** → ask what is missing, then spawn `guild:project-manager` with the
  *projects* prompt and the user's answer. Go back to Step 3.
- **Not now** → leave it open.

A shift never closes a goal. It lists them in its report.

---

## Step 6 — Wrap up

```
Session summary
===============
Plans approved: {n}   denied: {n}   completed: {n}   failed: {n}
Projects reviewed: {n}   documented: {n}   Issues filed: {n}

Goals
  GOAL-001 Build a CMS — 2 of 4 projects done
    PROJ-002 User registration — in progress, 3 of 5 requirements done

Waiting on you
  ...
```

**Never end without these, when any is non-empty, at the top of the summary:**

- plans waiting for approval (`v_plans_pending_approval`)
- goals to sign off (`v_goals_complete`)
- stuck plans, with their issue (`v_plans_stuck`)
- plans nobody can run, with the missing capability (from 4.2). The fix is an agent file
  that declares it.
- blocked plans, with what they wait on (`v_plans_blocked`)

Then stamp the check-in, **last**, because it is the cutoff for the next "what moved"
report:

```sql
UPDATE guild_state SET value = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
 WHERE key = 'last-checkin' RETURNING key, value;
```

## Key rules — the checklist

1. Approvals first, then fill, then approve again, then execute. Never execute a plan the
   user has not approved (check-in) or the shift rules did not approve (shift).
2. One agent per missing item, all spawned in one message. Repeat the fill until nothing
   is missing.
3. Dispatch every ready plan that does not conflict on files or serial agents. Record each
   result as it arrives, then look again.
4. A failure is an `execution` issue and the plan stays `in-progress`. Never retry it
   silently and never stop the run for it.
5. A finished project is reviewed by many `guild:reviewer` agents, one lens and one slice
   each, then documented by the librarian. Reviewers only report. You merge and file their
   findings as issues. Nobody fixes anything during a review.
6. Issues become fix plans in Step 3, and fix plans need approval like any plan.
7. You move every status. Agents write content and report.
8. A goal closes only on a person's word.
