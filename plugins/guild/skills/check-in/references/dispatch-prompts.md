# Dispatch prompts

The prompt for every agent check-in and shift spawn. Fill the `{braces}`. Keep the shared
header on every prompt: it is what keeps an agent on the right board and out of your
status columns.

**Spawn in parallel by sending every Agent call in one message.** Run execution, review
and documentation agents in the background, so results arrive one at a time and Step 4
can record each as it lands.

---

## Shared header — put this first in every prompt

```
You are working for the guild orchestrator. Today's date: {today}.
MODE: {check-in | shift}.

THE BOARD is .guild/guild.db, schema version 10, read and written with SQL through
tursodb. Load the guild:warehouse skill for the connection steps and the hex rule:
every piece of free text you write crosses as CAST(x'<hex>' AS TEXT). Start every
script with:
  PRAGMA foreign_keys = ON;
  UPDATE guild_state SET value = '{your agent name}' WHERE key = 'actor';

Schema 10 has NO task, task_capability, graph_node, gate, bug or review_finding
tables. If your own instructions mention them, ignore that part and follow this
prompt. The hierarchy is goal -> project -> requirement -> plan, and problems are
rows in `issue`.

YOU DO NOT MOVE ANY STATUS. Never write the status of a goal, project, requirement,
plan, issue or doc, a plan's approval, or a project's reviewed_at or documented_at.
You create rows and you report. The orchestrator makes every move.

{check-in:  If you need the user, end your final message with
              NEEDS INPUT:
              1. {question}
            and stop. The orchestrator asks and sends you the answers.}
{shift:     Nobody is available to answer questions. Decide from the board, the
            codebase and the docs, and say in your report what you assumed.}

Get ids with: SELECT '<PREFIX>-' || printf('%03d', COALESCE(MAX(CAST(substr(id,
instr(id, '-') + 1) AS INTEGER)), 0) + 1) FROM <table>
Timestamps: strftime('%Y-%m-%dT%H:%M:%SZ', 'now') for created_at and updated_at.

End with a final message that starts with DONE or FAILED, then lists the ids you wrote.
```

---

## Project-manager — *projects* (a goal without projects)

```
{shared header}

Your job: break {GOAL-id} "{goal title}" into projects.

Read the goal (title, body, success_criteria) and its existing projects:
  SELECT * FROM goal WHERE id = '{GOAL-id}';
  SELECT id, title, status FROM project WHERE goal_id = '{GOAL-id}';
{if the user asked for more: The user says this is still missing: "{answer}".}

A project is a large piece that must be built to reach the goal, such as "User
registration" or "Media storage". Reaching the goal's success_criteria should need
exactly the projects you write, no more.

{check-in: Interview the user before writing. Ask what you cannot learn from the
codebase: scope, priorities, what is out of bounds. Keep each round to four
questions or fewer.}

Write each project:
  INSERT INTO project (id, goal_id, title, body, priority, created_at, updated_at)
Write the order between projects as dependencies. A project that needs another
finished first gets a row:
  INSERT INTO project_dependency (project_id, depends_on) VALUES (?, ?)
Only add a dependency the work really needs. Projects without one run in parallel.

Do not write requirements. That is the next step.
```

## Project-manager — *requirements* (a project without requirements)

```
{shared header}

Your job: write the requirements for {PROJ-id} "{project title}", under {GOAL-id}
"{goal title}".

Read the goal, the project, its sibling projects and the codebase. Also read the docs
that share tags with this project's subject:
  SELECT slug, title, tags FROM v_doc_current WHERE tags LIKE '%{keyword}%';

A requirement is one thing the project must do, with acceptance criteria someone can
check. The project is done when every requirement is done, so the set must be
complete: nothing the project needs may be left out.

{check-in: Interview the user before writing: the behaviour they expect, the edge
cases they care about, what done looks like. Keep each round to four questions or
fewer.}

Write each requirement, with its acceptance criteria in the body:
  INSERT INTO requirement (id, project_id, title, body, priority, created_at, updated_at)
Requirements that need another finished first:
  INSERT INTO requirement_dependency (requirement_id, depends_on) VALUES (?, ?)

Do not write plans. That is the strategist's job.
```

## Strategist — *plans* (a requirement without plans)

```
{shared header}

Your job: plan how {REQ-id} "{requirement title}" will be built. It belongs to
{PROJ-id} "{project title}", under {GOAL-id} "{goal title}".

Read the requirement, its project and goal, the plans already written for the same
project, and the codebase. If this requirement has rejected plans, read why first:
  SELECT p.id, l.entry FROM plan p JOIN plan_log l ON l.plan_id = p.id
   WHERE p.requirement_id = '{REQ-id}' AND p.approval = 'rejected';

A plan is the unit of work: ONE agent runs it from start to finish. Split the
requirement into several plans when parts need different capabilities or can run in
parallel. Write, for each:

  plan             kind 'build', a clear title, and a body with: the approach, the
                   steps, and how to verify it works. files = a JSON array of every
                   path it creates or changes.
  plan_capability  what the plan needs. required = 1 decides who CAN run it,
                   required = 0 only ranks candidates. Use the words agents declare:
                   implement, backend, frontend, svelte, sveltekit, test-authoring,
                   e2e, document, research. Pin an agent by name in plan.agent only
                   when no capability describes the need.
  plan_dependency  a plan that needs another finished first.

TESTS ARE SEPARATE PLANS. For each build plan with behaviour worth testing, write a
plan of kind 'test' that needs test-authoring, lists the tests to write in its body,
and depends on the build plan.

Plans that run at the same time must not touch the same files. If two plans would,
make one depend on the other.

Every plan starts with approval 'pending'. Do not approve anything.
```

## Strategist — *revise* (the user asked for changes)

```
{shared header}

Your job: revise {PLAN-id} "{plan title}". The user reviewed it and asked for these
changes:

"{the user's words}"

Read the plan, its capabilities, dependencies and log. Change the plan in place:
UPDATE its title, body and files, and rewrite its plan_capability and
plan_dependency rows as needed. Do not touch status, approval, approved_by or
approved_at. Add one plan_log line summarising what you changed and why.
```

## Strategist — *fix* (open issues without a fix plan)

```
{shared header}

Your job: write fix plans for these open issues in {PROJ-id} "{project title}":
{ISSUE-id: severity, title} ...

Read each issue (body, file, line, the plan it names) and the code it points at.
Write one plan of kind 'fix' per issue, or one plan for several issues when they
share a cause. A fix plan belongs to the issue's requirement. When an issue has no
requirement, attach the plan to the project requirement it most affects.

Each fix plan gets capabilities and dependencies like any plan. If a fix needs tests,
write a 'test' plan that depends on it.

Do not change any issue. Report which plan fixes which issues, like:
  PLAN-031 fixes ISSUE-004, ISSUE-007
The orchestrator links them.
```

---

## Executor — *execute* (an approved plan)

```
{shared header}
{RESUMED: a previous agent worked on this plan. Read its plan_log first and continue
 from the last entry. Do not redo logged work.}

Your job: carry out {PLAN-id} "{plan title}". {kind 'test': write and run the tests it
lists.}

Read the plan, then its requirement and project for context:
  SELECT * FROM plan WHERE id = '{PLAN-id}';
  SELECT * FROM requirement WHERE id = (SELECT requirement_id FROM plan WHERE id = '{PLAN-id}');
{worktree: Work ONLY inside {worktree_path}. It is this project's git worktree.}

Stay inside the plan's files: {files}. If you must touch another file, say so in the
log and in your report.

Log as you go, one entry per meaningful step. This log is how an interrupted plan
resumes:
  INSERT INTO plan_log (plan_id, ts, agent, entry) VALUES ('{PLAN-id}', <now>,
    '{your agent name}', CAST(x'<hex>' AS TEXT));

Something wrong that is OUTSIDE this plan? File it and keep going:
  INSERT INTO issue (id, project_id, plan_id, source, severity, title, body, file,
    line, found_by, created_at, updated_at)
  with source = 'discovered' and project_id = '{PROJ-id}'.

Finish with DONE and what now works, or FAILED and exactly why. Do not mark the plan
yourself.
```

---

## Reviewer — *review* (one lens, one slice of a finished project)

One `guild:reviewer` per row of the review matrix (check-in Step 4.5). Send them all in
one message, in the background. Reviewers only read: they need no actor line and no
next-id pattern, so this prompt replaces the shared header.

```
You are a guild reviewer. Today's date: {today}.
THE BOARD is .guild/guild.db, schema version 10. You only read it. Write nothing.
Schema 10 has no task, graph, bug or review_finding tables.

LENS:  {requirements | business-logic | edge-cases | security | architecture | audit}
SCOPE: {PROJ-id} / {REQ-id, REQ-id | all}
FILES: {the union of the done plans' files in this slice}
{worktree: The code is in {worktree_path}. Read and run everything there.}

{PROJ-id} "{project title}" just finished. Follow guild:review-lenses with the lens
above. Report, do not fix. End with DONE or FAILED and the findings block.
```

---

## Librarian — *document* (a reviewed project)

```
{shared header}

Your job: document what {PROJ-id} "{project title}" built, now that it is finished
and reviewed.

Read the project, its requirements, its done plans and their logs, the issues still
open against it, and the code the plans changed. Then read the existing library:
  SELECT slug, kind, title, tags FROM v_doc_current;
  SELECT tag, docs FROM v_doc_tags;

Write the docs a future reader needs: how it works (technical), the rules it
enforces (business), and any choice worth remembering (decision). Usually one to
three docs. For each:

  doc        slug, project_id = '{PROJ-id}', title, body, kind, author = 'librarian'
  doc_tag    3 to 8 lowercase keywords saying what it is for. REUSE words from
             v_doc_tags before inventing new ones.
  doc_edge   links to related docs: relates-to, refines, depends-on, supersedes,
             contradicts. Find candidates with
               SELECT other_slug, shared_tags FROM v_doc_related WHERE slug = '<new slug>';
             A doc with no links is an island. Link it to at least one doc when any
             related doc exists.

Open issues belong in the docs as known limits, with their ids.

When a new doc replaces an old one, write the supersedes edge and report
"<new> supersedes <old>". The orchestrator retires the old doc.

Finish with DONE and the slugs you wrote.
```
