# The warehouse on Kumiai — the same board, served as tools

Load this page when `.guild/config.yaml` says `backend: kumiai`. With `backend: local`, or no
`backend:` line at all, nothing here applies — read `queries.md` and write SQL.

Kumiai serves **the whole warehouse** — every table, every `v_*` view and the event feed — as
typed MCP tools on a server named `kumiai`, against the contract in
`kumiaikata/docs/guild-contract.md` (**1.0.0**). The model is unchanged: the same goal → project →
requirement → plan → task hierarchy, the same graph, the same two gates, the same vocabularies, the
same views. **What changes is the door.** You call a tool instead of writing a statement, and the
rules the engine enforced locally — the CHECKs, the views, the event-writing triggers — are
enforced by Kumiai's Postgres instead.

This page is organised exactly like `queries.md`: **§N here is §N there.** Each recipe names the
local statement it replaces and gives the call. Read the local section for *why* a recipe has the
shape it has — the reasoning did not change, only the syntax did, and it is not repeated here.

Tool names below are written bare (`create_task`); the callable name is `mcp__kumiai__create_task`.

---

## 0. The kumiai preamble

### Which backend, and which workspace

```bash
backend=$(awk '/^backend:/ {print $2}' .guild/config.yaml 2>/dev/null); backend=${backend:-local}
workspace=$(awk '/^kumiai:/ {k=1; next} k && /^[^ #]/ {k=0} k && /workspace:/ {print $2}' .guild/config.yaml)
```

`backend` absent means `local`. **Never guess a workspace id** — it is the one value that decides
whose board you are writing, and it comes from `config.yaml` and nowhere else.

If no `mcp__kumiai__*` tool is available in your session, **stop and say so**. Do not fall back to
`tursodb`: a local write in a kumiai project lands on a board nobody else reads, and the two
boards then disagree with nothing to reconcile them. The fix is the user's — `claude mcp add
--scope project --transport http kumiai <url>/mcp`, then authenticate in `/mcp`.

### The rules that replace the seven

| Local rule (`SKILL.md`) | On Kumiai |
|---|---|
| 1. Free text crosses as hex | **Gone.** Every value is a plain JSON string. Pass a requirement body with its code blocks, `;` and `|` exactly as written — the splitter that rule existed for is not in the path. |
| 2. SQL never passes through a `%` layer | **Gone.** There is no SQL to mangle. |
| 3. `PRAGMA foreign_keys = ON` | **Gone.** Postgres enforces references on every call. |
| 4. Never parse `-m list` positionally | **Gone.** Results are JSON rows. Read fields by name. |
| 5. Read the view, do not re-derive the rule | **Unchanged, and stronger.** Every `v_*` view is `read_view` with `view: "v_…"`. There is no way to write your own join, which is the point. |
| 6. A failing statement does not stop the script | **Inverted. One tool call is one transaction.** A composite call (`create_task`, `instantiate_graph`, `resolve_gate`, `supersede_doc`) lands whole or not at all. There is no half-written script to read back. |
| 7. Errors print on stdout | Errors are MCP tool errors (`isError: true`) whose text is JSON `{"code","message"}`. **Read the code**, never retry blind (below). |

**`actor` replaces `UPDATE guild_state SET value = … WHERE key = 'actor'`.** Every write takes
`actor` — your own member name (`orchestrator`, `strategist`, `developer-svelte`, `user` for the
guild master's own word). Kumiai records it *and* the authenticated user on every event, so the
feed still says who; it is still a label you set honestly, not a permission. **Only
`orchestrator` (and `user`, at a gate) is ever the actor of a status move** — any tool that moves
a `status`, an `approval` or a `disposition`. A member creates rows and reports outcomes; the
skill that spawned it makes the move (§2).

**Keys, not internal ids.** Every guild-shaped row keeps its guild key — `GOAL-001`, `PROJ-001`,
`REQ-001`, `PLAN-001`, `TASK-001`, `BUG-001`, `INSP-001`; nodes keep `REQ-001/implement.TASK-011`;
docs keep their `slug`; coverage keeps its text `id`. Foreign-key columns (`task_id`,
`requirement_id`, …) hold and filter by keys too. **The server derives the next key on create**,
so §1's `MAX(n)+1` expression has no equivalent — read the key off the result, exactly as you read
`RETURNING id` locally.

**Every result is the full row after the write** — the equivalent of `RETURNING *`. "Did it land"
is answered by the result, and `NOT_FOUND` replaces "zero rows back".

**Every `update_*` and `upsert_*` is a patch.** An omitted field keeps its value; `null` clears a
nullable one. So the local "pass back every column you want kept" warning about `DO UPDATE SET`
does not apply — send only what you mean to change.

### Reading: `read_view`, `get`, `list`

```json
read_view {"workspace": "<ws>", "view": "v_open_bounties",
           "where": {"requirement_id": "REQ-007"},
           "order_by": [{"col": "priority", "dir": "asc"}, {"col": "id", "dir": "asc"}],
           "limit": 200}
get       {"workspace": "<ws>", "type": "task", "key": "TASK-011"}
list      {"workspace": "<ws>", "type": "work_log", "where": {"task_id": "TASK-011"},
           "order_by": [{"col": "ts", "dir": "asc"}, {"col": "id", "dir": "asc"}]}
```

- **`where`** maps a column to a scalar (equality), an array (`IN`), or `{"op": …, "value": …}`
  with `op` ∈ `=`, `<>`, `<`, `<=`, `>`, `>=`, `like`, `is_null`, `not_null`. Conditions are
  ANDed. Columns are the view's or table's own guild column names. So the local `status <> 'done'`
  is `{"status": {"op": "<>", "value": "done"}}`, `ts >= '…'` is `{"ts": {"op": ">=", "value":
  "…"}}` (timestamps compare as instants), and `agent IS NULL` is `{"agent": {"op": "is_null"}}`.
- **`like`** takes the SQL pattern — `%`, `_`, `\` to escape — and is case-sensitive on ASCII.
  Escape free text yourself before it becomes a pattern, as locally.
- **Paging.** `limit` is at most 500 (default 200); the result carries `next_offset`. When it is
  not `null` there is more — call again with `offset: next_offset` until it is. **A read that
  stopped at the first page is not the whole answer**, and nothing in the result will say so if
  you do not look at `next_offset`.
- `get` takes `type` ∈ `goal, project, requirement, plan, task, bug, coverage, inspection, doc,
  review_finding, graph_node, gate`. **A `task` comes back with its `capabilities` and
  `depends_on`**, which replaces two local joins.
- `list` reads base tables: everything `get` takes, plus `work_log, task_dependency,
  task_capability, graph_edge, graph_deviation, knowledge_edge, doc_revision, event,
  inspection_coverage, guild_state`. `graph_edge` and `gate` carry `requirement_id`.
- Integer flags come back as the schema stores them: `concurrent`, `task_capability.required`
  and friends are `0`/`1`, exactly as `schema.sql`. The one exception is `get task`'s
  `capabilities`, whose `required` is `true`/`false`.

### What each call returns — read the field, not the whole result

Every result is a JSON **object**. A list of rows is always under a name, never bare:

| call | result |
|---|---|
| `read_view`, `list`, `search_docs` | `{"rows": [...], "next_offset": n \| null}` |
| `get_state` | `{"rows": [{"key", "value"}]}` — `[]` under `rows` when the key is not set |
| `get`, and every single-row write | the row itself (`key` repeats the guild key; `kumiai_id` is internal) |
| `list_workspaces` | `{"workspaces": [...]}` — each `{id, name, isDefault, …}` |
| `claim_task` | `{"task": <task> \| null}` — `null` is "nothing claimable" |
| `instantiate_graph` | `{"nodes", "edges", "gates", "deviations"}` — the requirement's whole graph |
| `resolve_gate` | `{"gate", "node", "plan"}` — `plan` is `null` when no plan is linked (`gate-repairs`) |
| `supersede_doc` | `{"new", "old", "edge"}` |
| `doc_neighbors` | `{"type", "id", "rows": [{direction, rel, other_type, other_id, other_title, …}]}` |
| `check_invariants` | `{"ok", "failures", "checked", "skipped"}` (§6) |
| `fingerprint` | `{"tables": {<table>: {count, max_key, digest}}, "events": {count, max_id}}` |

### Errors

| code | means | do |
|---|---|---|
| `NOT_FOUND` | the key, slug or endpoint is not there | the local "zero rows back". Report it; never create the parent to make it pass |
| `VALIDATION` | a CHECK, an enum, an unknown `where` column | your input is wrong. Fix the word, do not widen it |
| `CONFLICT` | an `expect_status` that did not match, or a uniqueness conflict | **somebody moved it first** — the local zero-row guard. Information, not a fault: re-read, then decide |
| `FORBIDDEN` | the workspace is not your team's | stop. The config points at the wrong board |
| `UNAUTHENTICATED` | the token is missing or expired | stop and ask the user to re-authenticate in `/mcp` |
| `INTERNAL` | the server failed; the message carries nothing | `get` the row before you retry, as for a timeout |

**An argument the tool does not take is `VALIDATION`**, never silently ignored — so a misspelled
`expect_status` cannot turn a guarded move into an overwrite. Spell arguments as this page does.

**Never retry a write you did not see fail.** One call is one transaction, so a timeout is
ambiguous: `get` the row and look before calling again.

### Guarded moves — `expect_status`

Local status moves are guarded in the statement (`… WHERE id = 'TASK-001' AND status = 'todo'`).
On Kumiai the guard is a parameter: every status-moving tool takes `expect_status` (one status or
an array), and a mismatch is `CONFLICT` with nothing written. **Always pass it** wherever the local
recipe guards — the guard is what makes "somebody already moved it" an answer instead of a
silent overwrite.

### Version check — once per session, by whoever opens it

```json
whoami {}
→ {"user": {...}, "team": {...}, "contract": "1.0.0"}
```

**Refuse a different major version.** A 2.x server has changed a tool's meaning, and a guild
that calls it with 1.x arguments writes plausible, wrong rows.

---

## 1. Creating things

### The id pattern

**Not needed.** The server generates `PREFIX-NNN`, zero-padded to three, unique per workspace —
the same shape `queries.md` §1 derives by hand. The referential check that the local `FROM parent
WHERE parent.id = …` performs is the server's: a missing parent is `NOT_FOUND` and nothing is
written.

### Goal, project

```json
create_goal    {"workspace": "<ws>", "actor": "orchestrator",
                "title": "Self-serve onboarding", "priority": 2}
→ {"key": "GOAL-001", ...}

create_project {"workspace": "<ws>", "actor": "orchestrator", "goal": "GOAL-001",
                "title": "Account creation", "priority": 3,
                "concurrent": false, "isolation": "shared"}
→ {"key": "PROJ-001", "ordinal": 1, ...}
```

Leave `ordinal` out to get "next in this goal", the local `COUNT(*)+1`. The defaults above are the
sequential, shared-tree project. The three local `UPDATE project` recipes are one call each:

```json
update_project {"workspace": "<ws>", "actor": "orchestrator", "key": "PROJ-003", "concurrent": true}
update_project {"workspace": "<ws>", "actor": "orchestrator", "key": "PROJ-004", "ordinal": null}
update_project {"workspace": "<ws>", "actor": "orchestrator", "key": "PROJ-003",
                "isolation": "worktree", "worktree_path": ".worktrees/PROJ-003"}
```

Both worktree columns go in **one** call for the same reason they go in one statement locally:
a `shared` project may not carry a path, and the CHECK is enforced server-side.

Kumiai stores guild priority on its own four-step scale (`urgent=1 … low=4`): **a project written
with priority 5 reads back as 4.** That is the contract, not a fault.

```json
read_view {"workspace": "<ws>", "view": "v_projects_runnable"}
read_view {"workspace": "<ws>", "view": "v_projects_runnable", "where": {"goal_id": "GOAL-001"}}
```

### Requirement

```json
create_requirement {"workspace": "<ws>", "actor": "project-manager",
                    "title": "Session-backed authentication",
                    "body": "# Session-backed authentication\n\n## Summary\n…",
                    "project": "PROJ-001", "priority": 1}
→ {"key": "REQ-007", "status": "todo", ...}
```

`project: null` (or leaving it out) is unaffiliated work — it still belongs to the workspace.
Attaching or detaching later is `update_requirement {"key": "REQ-007", "project": "PROJ-002"}`
or `"project": null`.

### Plan

```json
create_plan {"workspace": "<ws>", "actor": "strategist", "requirement": "REQ-007",
             "title": "Session-backed authentication — implementation plan",
             "body": "# … Implementation Plan\n…"}
→ {"key": "PLAN-004", "status": "todo", "approval": "pending", ...}
```

`task: "TASK-014"` makes it a plan written *for* one ticket — the test-planner's test plan.

Status and approval still move separately, because they still answer different questions. **Both
are the orchestrator's**: the strategist reports `plan PLAN-004 written`, and
`guild:new-requirement` marks it:

```json
update_plan {"workspace": "<ws>", "actor": "orchestrator", "key": "PLAN-004", "status": "done",
             "expect_status": ["todo", "in-progress"]}
```

**Approving or rejecting the requirement's plan is `resolve_gate`** (§4), which in one transaction
sets the gate, moves the node, and gives the plan its `approval`, `approved_by` (`decided_by`,
default `'user'`) and `approved_at` — and, on reject, sends it back to `status = 'in-progress'`.
That is the local three-write approval, plus the reject's status move, collapsed into one call.
Pass `plan: "PLAN-004"` to link the plan to the gate in the same call (its `gate_node_id` is set to
the node); without it, the plan already linked to that node is the one approved.

A plan with no gate behind it (a small change approved in conversation) is approved directly:

```json
update_plan {"workspace": "<ws>", "actor": "orchestrator", "key": "PLAN-004",
             "approval": "approved", "approved_by": "user"}
```

Who is still waiting on a person:

```json
read_view {"workspace": "<ws>", "view": "v_plans_pending_approval"}
```

### Task, with its capabilities and dependencies

**One call, atomic** — the local INSERT plus both `task_capability` inserts plus the dependency:

```json
create_task {"workspace": "<ws>", "actor": "strategist", "requirement": "REQ-007",
             "plan": "PLAN-004", "title": "Auth service",
             "objective": "## Objective\n…", "body": "",
             "files": ["src/lib/auth.ts", "src/routes/login/+page.server.ts"],
             "parallel_group": "wave-1", "node_key": "implement", "priority": 2,
             "capabilities": [{"capability": "implement", "required": true},
                              {"capability": "frontend",  "required": true},
                              {"capability": "svelte",    "required": false},
                              {"capability": "sveltekit", "required": false}],
             "depends_on": []}
→ {"key": "TASK-011", "capabilities": [...], "depends_on": [], ...}
```

`files` is a JSON array, `[]` for a ticket that owns no bounded file set. Leave `agent` out to let
the dispatcher match; set it only to **pin**. Later changes:

```json
add_task_dependency    {"workspace": "<ws>", "actor": "strategist", "task": "TASK-012", "depends_on": "TASK-011"}
remove_task_dependency {"workspace": "<ws>", "actor": "strategist", "task": "TASK-012", "depends_on": "TASK-011"}
set_task_capabilities  {"workspace": "<ws>", "actor": "strategist", "task": "TASK-012",
                        "capabilities": [{"capability": "test-authoring", "required": true}]}
update_task            {"workspace": "<ws>", "actor": "orchestrator", "key": "TASK-012",
                        "title": "Retitled by the guild master"}
```

`set_task_capabilities` **replaces** the set — pass every row you want to keep. It is the one
write that is not a patch.

**The capability check is still not a tool call.** The vocabulary is the agent files in both
backends, so `roster.py --covers implement,frontend` is the check, exactly as in `queries.md`.

### Bug

```json
file_bug {"workspace": "<ws>", "actor": "qa-tester",
          "title": "Checkout accepts quantity 0 and places an order for nothing",
          "repro": "1. Add any item…\nExpected: …\nActual: …",
          "body": "Area: Checkout · Mission: MISSION-checkout …",
          "severity": "major", "requirement": "REQ-003", "found_by": "qa-tester"}
→ {"key": "BUG-014", "status": "open", ...}
```

`found_by` defaults to the actor; set it honestly. No `nit` — a bug is not a nit, and the server
rejects one.

### Doc — upsert into the library

```json
upsert_doc {"workspace": "<ws>", "actor": "strategist", "slug": "adr-session-store",
            "title": "Sessions live in Redis", "body": "## Context\n…",
            "kind": "decision", "area": "auth", "source": "strategist"}
```

The server snapshots the previous body into `doc_revision`, which is what `trg_doc_revised` does
locally. A new doc defaults to `kind = 'reference'` and `status = 'current'`; on a rewrite every
omitted field keeps its value. **Leave `status` out of a rewrite** — the local upsert leaves it out
of `DO UPDATE` because a lifecycle is moved by supersession, never by re-saving a page, and the
patch semantics keep that true as long as you do not send it. Validate the slug against a closed
alphabet before you send it, for the same reason as locally — a slug is a key somebody retypes.

### Linking — the referential check is now the server's

```json
link {"workspace": "<ws>", "actor": "strategist", "rel": "decides",
      "from": {"type": "doc", "id": "adr-session-store"},
      "to":   {"type": "requirement", "id": "REQ-004"},
      "note": "Chosen at gate-plan for REQ-004"}
```

**Both ends must exist, or the call is `NOT_FOUND`** — the check the local
`INSERT … SELECT … FROM <target>` shape does by hand. `link` is idempotent on its tuple, so
re-linking is harmless. The rel/type pairings are still enforced (`VALIDATION`). `unlink` with the
same `rel, from, to` is the one removal the library performs, and only while retiring a decision.

### Superseding a decision — the member writes the page, the orchestrator makes one call

The member that made the new decision (strategist, librarian) writes **the new page only**, with
`upsert_doc`, and reports `doc adr-session-store-v2 supersedes adr-session-store` with its reason
— it never calls `supersede_doc`, because that call moves the old doc's status. The skill that
spawned it then retires the old one:

```json
upsert_doc    {"workspace": "<ws>", "actor": "strategist", "slug": "adr-session-store-v2",
               "title": "Sessions move to Postgres", "body": "## Context\n…",
               "kind": "decision", "area": "auth", "source": "strategist"}
supersede_doc {"workspace": "<ws>", "actor": "orchestrator", "old_slug": "adr-session-store",
               "new": {"slug": "adr-session-store-v2"},
               "note": "Redis was a second store to operate for one feature"}
```

`new` without `title` and `body` names a doc that already exists: the server leaves it exactly as
the member wrote it and, in one transaction, adds the `supersedes` edge new → old and sets the old
doc's `status = 'superseded'` — the local steps 2 and 3. `NOT_FOUND` means the reported slug was
never written; stop and say so. (Give `title` and `body` and the same call also writes the new doc
— for a supersession the orchestrator decides itself.) **The old row still stays**, and
`v_decision_log` still lists it with `superseded_by`.

### Reading the graph — one hop, still

```json
doc_neighbors {"workspace": "<ws>", "type": "doc", "id": "adr-session-store"}
doc_neighbors {"workspace": "<ws>", "type": "requirement", "id": "REQ-004", "rel": "decides"}
read_view     {"workspace": "<ws>", "view": "v_doc_neighbors", "where": {"slug": "adr-session-store"}}
read_view     {"workspace": "<ws>", "view": "v_decision_log"}
list          {"workspace": "<ws>", "type": "doc_revision", "where": {"slug": "refund-rules"},
               "order_by": [{"col": "replaced_at", "dir": "desc"}]}
```

`doc_neighbors` also starts from a work row (`type: "requirement"`), which the local view cannot
do without a second query. **A supersession chain is still one call per hop**, looped and capped
by you — the contract has no traversal either:

```text
slug = "adr-session-store"; seen = {}; n = 0
while slug and n < 20:
    if slug in seen: report "cycle at <slug>"; stop
    seen += slug; n += 1
    rows = list {"type": "knowledge_edge",
                 "where": {"rel": "supersedes", "to_type": "doc", "to_id": slug}, "limit": 1}.rows
    slug = rows[0].from_id if rows else None
```

### The two drift reads

```json
read_view {"workspace": "<ws>", "view": "v_doc_stale"}
read_view {"workspace": "<ws>", "view": "v_undocumented_work"}
read_view {"workspace": "<ws>", "view": "v_doc_current", "where": {"edges": 0}}
```

`v_knowledge_dangling` must still be empty; `check_invariants` runs it as G10.

### Searching the library

```json
search_docs {"workspace": "<ws>", "query": "fail()", "kind": "business", "limit": 20}
```

Case-insensitive and **literal** — `%`, `_` and `\` are characters, not wildcards, so the local
escaping dance is the server's. **Still refuse an empty query.** Filter by `kind` (and by `area`
with `read_view v_doc_current`) before you search when you know what you want.

---

## 2. Moving something through status

**Every call in this section is the orchestrator's — on every subject, no exceptions**: tasks,
nodes, gates, requirements, projects, goals, and also plans (`update_plan`), bugs (`update_bug`),
docs (`supersede_doc`), inspections (`update_inspection`) and finding dispositions
(`update_finding`). A member reports the outcome; the orchestrator moves it.

```json
set_task_status {"workspace": "<ws>", "actor": "orchestrator", "key": "TASK-001",
                 "status": "in-progress", "expect_status": "todo", "claimed_by": "developer-svelte"}
set_task_status {"workspace": "<ws>", "actor": "orchestrator", "key": "TASK-001",
                 "status": "done", "expect_status": "in-progress"}
update_requirement {"workspace": "<ws>", "actor": "orchestrator", "key": "REQ-001",
                    "status": "done", "expect_status": ["todo", "in-progress"]}
```

`CONFLICT` is the local zero-rows answer: somebody already moved it. `updated_at` and the `event`
row are the server's. **Do not pass `reason` on a dispatch move** — it is written to `work_log`,
and check-in's recovery triage reads "this ticket has log entries" as "an agent started it".

**`claimed_by` is who took the ticket; `actor` is who moved it.** When the orchestrator dispatches
a member, pass the member as `claimed_by` and yourself as `actor`, so the claim names the member
and the `moved` event names the orchestrator — exactly the local split, where the UPDATE sets
`claimed_by = 'developer'` while `guild_state.actor` is `orchestrator`. (`claim_task {key,
claimant}` is the same claim for the cursor path.) **Never call a status tool with the member as
`actor`**: the move would be attributed to the member, which is the breach §7's C.b assertion
exists to catch. `claimed_by: null` clears the claim and its `claimed_at` — the shift retry's
`claimed_by = NULL, claimed_at = NULL`.

Before closing a requirement:

```json
read_view {"workspace": "<ws>", "view": "v_requirement_progress", "where": {"id": "REQ-001"}}
```

### Failing a task, and the waiver

```json
set_task_status {"workspace": "<ws>", "actor": "orchestrator", "key": "TASK-002", "status": "failed"}
log_work        {"workspace": "<ws>", "actor": "test-writer",  "task": "TASK-002",
                 "entry": "Integration suite cannot reach the test database: …"}
log_work        {"workspace": "<ws>", "actor": "orchestrator", "task": "TASK-002",
                 "entry": "Skipped by user — the migration is being rewritten in REQ-012"}
read_view       {"workspace": "<ws>", "view": "v_failed_tasks"}
```

The waiver is still a prefix: the entry must **begin** exactly `Skipped by user`. `log_work`'s
`agent` is the actor.

### Logging work, filing and dispositioning a finding

```json
log_work    {"workspace": "<ws>", "actor": "developer-svelte", "task": "TASK-001",
             "entry": "Implemented the session store in src/lib/session.ts"}

add_finding {"workspace": "<ws>", "actor": "reviewer-security", "task": "TASK-001",
             "severity": "major", "summary": "Unsigned callback token accepted",
             "detail": "consume() trusts the token's payload before verifying …",
             "file": "src/lib/auth.ts", "line": 42}
→ {"id": 7, "disposition": "open", "reviewer": "reviewer-security", ...}

update_finding {"workspace": "<ws>", "actor": "orchestrator", "id": 7,
                "disposition": "fixing", "fix_task": "TASK-011"}
update_finding {"workspace": "<ws>", "actor": "orchestrator", "id": 7,
                "disposition": "fixed", "fix_ref": "9f2c1ab"}
```

`reviewer` is the actor — a finding's author is still the most important fact about it. A
finding's `id` is a number, not a key.

---

## 3. The daily reads

Every local `SELECT … FROM v_…` is one `read_view`. None mutates anything.

| Local | Kumiai |
|---|---|
| `SELECT fact, value FROM v_brief` | `read_view {"view": "v_brief"}` |
| `SELECT … FROM v_board` | `read_view {"view": "v_board"}` |
| `… v_board WHERE section_no = 4 ORDER BY id DESC LIMIT 20` | `read_view {"view": "v_board", "where": {"section_no": 4}, "order_by": [{"col": "id", "dir": "desc"}], "limit": 20}` |
| `v_requirement_progress`, `v_goal_progress` | `read_view` each |
| `v_requirement_progress WHERE status <> 'done'` | `read_view {"view": "v_requirement_progress", "where": {"status": {"op": "<>", "value": "done"}}}` |
| `v_open_bounties ORDER BY priority, id` | `read_view {"view": "v_open_bounties", "order_by": [{"col": "priority", "dir": "asc"}, {"col": "id", "dir": "asc"}]}` |
| `SELECT * FROM v_next_task` | `read_view {"view": "v_next_task"}` |
| `v_blocked_tasks ORDER BY id` | `read_view {"view": "v_blocked_tasks", "order_by": [{"col": "id", "dir": "asc"}]}` |
| `v_batch WHERE task_id = 'TASK-003'` | `read_view {"view": "v_batch", "where": {"task_id": "TASK-003"}}` |
| `v_in_flight`, `v_open_findings`, `v_open_bugs`, `v_coverage_due` | `read_view` each |

The local `replace(… char(10) …)` flattening has no equivalent and needs none — a JSON string
cannot forge a row. **Flatten a title yourself only where it becomes structure**: a changelog
bullet, a heading, a commit message.

`v_next_task` returning nothing still means "nothing to do", not "finished".

### What moved since the last check-in

```json
get_state {"workspace": "<ws>", "key": "last-checkin"}
→ {"rows": [{"key": "last-checkin", "value": "2026-10-17T18:02:11Z"}]}   // "null" = never

read_view {"workspace": "<ws>", "view": "v_recent_activity",
           "where": {"ts": {"op": ">=", "value": "2026-10-17T18:02:11Z"}},
           "order_by": [{"col": "ts", "dir": "desc"}], "limit": 50}
```

When the value is `"null"` the guild has never checked in: leave the `where` out. A non-null
`next_offset` means the window holds more than 50 moves — say "50+", not "50".

Then stamp the check-in, last, once you have reported:

```json
set_state {"workspace": "<ws>", "actor": "orchestrator", "key": "last-checkin",
           "value": "2026-10-18T09:00:00Z"}
```

The value is the current UTC time you generated, ISO-8601 with a `Z`.

---

## 4. The execution graph

### Instantiate a requirement from a template

**One call, atomic** — every node, every edge, both gate rows and any deviations. The local
template script's `BEGIN … COMMIT` that is not actually atomic becomes a transaction that is.
The template (`templates/standard.md` §1, `maintenance.md` §2) is still the authoritative node
list; this example is `standard` with two implement tickets.

**Preflight first, as its own call** — the server does not refuse a second instantiation any more
than tursodb does:

```json
list {"workspace": "<ws>", "type": "graph_node", "where": {"requirement_id": "REQ-007"}, "limit": 1}
// expect "rows": [] — anything else means the graph exists: adopt it and deviate
```

A node's id is `<REQ>/<node_key>`, or `<REQ>/<node_key>.<suffix>` for a fanned node; `node_key`
is stored bare (`implement`), exactly as the local template stores it. An edge names its ends as
`node_key` or `node_key.suffix`.

```json
instantiate_graph {"workspace": "<ws>", "actor": "strategist", "requirement": "REQ-007",
  "nodes": [
    {"node_key": "gate-plan", "kind": "gate",
     "gate": {"kind": "approve", "prompt": "Plan for REQ-007 is ready for review. Approve implementation?"}},
    {"node_key": "implement", "suffix": "TASK-011", "kind": "work", "task": "TASK-011", "parallel_group": "wave-1"},
    {"node_key": "implement", "suffix": "TASK-012", "kind": "work", "task": "TASK-012", "parallel_group": "wave-1"},
    {"node_key": "test-plan",  "kind": "work"},
    {"node_key": "test-write", "kind": "work"},
    {"node_key": "review", "suffix": "reviewer-security",       "kind": "work", "task": "TASK-015", "parallel_group": "review"},
    {"node_key": "review", "suffix": "reviewer-architecture",   "kind": "work", "parallel_group": "review"},
    {"node_key": "review", "suffix": "reviewer-business-logic", "kind": "work", "parallel_group": "review"},
    {"node_key": "review", "suffix": "reviewer-edge-case",      "kind": "work", "parallel_group": "review"},
    {"node_key": "gate-repairs", "kind": "gate",
     "gate": {"kind": "select-findings", "prompt": "Findings and bugs from REQ-007 — approve which get repaired."}},
    {"node_key": "repair",   "kind": "work"},
    {"node_key": "document", "kind": "work"}
  ],
  "edges": [
    {"from": "gate-plan", "to": "implement.TASK-011"},
    {"from": "gate-plan", "to": "implement.TASK-012"},
    {"from": "implement.TASK-011", "to": "test-plan"},
    {"from": "implement.TASK-012", "to": "test-plan"},
    {"from": "test-plan",  "to": "test-write"},
    {"from": "test-write", "to": "review.reviewer-security"},
    {"from": "test-write", "to": "review.reviewer-architecture"},
    {"from": "test-write", "to": "review.reviewer-business-logic"},
    {"from": "test-write", "to": "review.reviewer-edge-case"},
    {"from": "review.reviewer-security",       "to": "gate-repairs"},
    {"from": "review.reviewer-architecture",   "to": "gate-repairs"},
    {"from": "review.reviewer-business-logic", "to": "gate-repairs"},
    {"from": "review.reviewer-edge-case",      "to": "gate-repairs"},
    {"from": "gate-repairs", "to": "repair"},
    {"from": "repair", "to": "document"}
  ],
  "deviations": []}
```

That is N + 10 = 12 nodes, 2N + 11 = 15 edges and 2 gates, the same arithmetic as locally. The
prompts are plain strings — the em dash and the `?` need no hex. **Edges still point backwards in
declaration order**; it is still the only cycle protection there is.

**An assurance skip's reason goes in the same call; the skip itself does not.** Add the reason to
`deviations` — `{"kind": "drop-node", "node_key": "test-write", "reason": "Verification is
`checks`: the plan's Assurance table names three manual checks and no test"}` — and leave every
node's `status` out, so it is created `pending`. The strategist reports
`skip REQ-007/test-write — deviation recorded`, and `guild:new-requirement` makes the move as
`orchestrator`:

```json
set_node_status {"workspace": "<ws>", "actor": "orchestrator", "node": "REQ-007/test-write",
                 "status": "skipped", "expect_status": "pending"}
```

A node created at `skipped` would have no `node-moved` event (G7 `no-moved-event`), and the
strategist moving it would be §7 C.b. The node and its edges stay; the counts do not change.

Then record which template built it, because no column on the node says so:

```json
set_state {"workspace": "<ws>", "actor": "strategist", "key": "graph-template:REQ-007", "value": "standard"}
```

Fanning a node out later — an implement ticket added after the graph was built gets its own
node **and both of its edges**, in, from `gate-plan`, and out, to `test-plan`, so the barrier
still waits for it and the `N + 10` / `2N + 11` arithmetic still holds with the new N:

```json
add_graph_node      {"workspace": "<ws>", "actor": "strategist", "requirement": "REQ-007",
                     "node_key": "implement", "suffix": "TASK-013", "kind": "work",
                     "task": "TASK-013", "parallel_group": "wave-1"}
add_graph_edge      {"workspace": "<ws>", "actor": "strategist",
                     "from": "REQ-007/gate-plan", "to": "REQ-007/implement.TASK-013"}
add_graph_edge      {"workspace": "<ws>", "actor": "strategist",
                     "from": "REQ-007/implement.TASK-013", "to": "REQ-007/test-plan"}
```

Only `implement` fans out per ticket. **`test-write` and `repair` are anchors and never fan out**
— their tickets run underneath the one node (bind it with `set_node_status {task}`), and
`check_invariants` reports a second `repair` node as `tail-repair-fanned-out`. A later
deviation:

```json
add_graph_deviation {"workspace": "<ws>", "actor": "strategist", "requirement": "REQ-007",
                     "kind": "add-node", "node_key": "research",
                     "reason": "The payments provider's webhook API is undocumented in the repo"}
```

An empty `reason` is still rejected.

### Find what is ready

```json
read_view {"workspace": "<ws>", "view": "v_ready_nodes", "where": {"requirement_id": "REQ-007"},
           "order_by": [{"col": "node_key", "dir": "asc"}, {"col": "parallel_group", "dir": "asc"},
                        {"col": "id", "dir": "asc"}]}
read_view {"workspace": "<ws>", "view": "v_ready_nodes",
           "where": {"kind": "work", "gate_status": {"op": "is_null"}}}
read_view {"workspace": "<ws>", "view": "v_gates_pending"}
```

Reading a requirement's graph back (`templates/standard.md` §7):

```json
list {"workspace": "<ws>", "type": "graph_node",      "where": {"requirement_id": "REQ-007"}, "order_by": [{"col": "id", "dir": "asc"}]}
list {"workspace": "<ws>", "type": "graph_edge",      "where": {"requirement_id": "REQ-007"}}
list {"workspace": "<ws>", "type": "gate",            "where": {"requirement_id": "REQ-007"}}
list {"workspace": "<ws>", "type": "graph_deviation", "where": {"requirement_id": "REQ-007"}}
```

The template's §8 validation queries run server-side as `check_invariants {"process":
"new-requirement", "requirement": "REQ-007"}` (§6 of this page).

### Run a node

```json
set_node_status {"workspace": "<ws>", "actor": "orchestrator",
                 "node": "REQ-007/implement.TASK-011", "status": "running",
                 "expect_status": ["pending", "ready"], "task": "TASK-011"}
set_node_status {"workspace": "<ws>", "actor": "orchestrator",
                 "node": "REQ-007/implement.TASK-011", "status": "done", "expect_status": "running"}
```

`task` binds the ticket when the node is unbound — the local `SET task_id = …`. `skipped` is still
the graph's `waived`.

### Resolve a gate — one call

```json
read_view    {"workspace": "<ws>", "view": "v_ready_nodes", "where": {"id": "REQ-007/gate-repairs"}}
// must return the row — approving a gate whose predecessors are not done unblocks repairs early
resolve_gate {"workspace": "<ws>", "actor": "orchestrator", "node": "REQ-007/gate-repairs",
              "status": "approved", "decision": "Repair 1, 2 and BUG-004. Leave the rest."}
```

Atomic: the gate's status, decision and `decided_at`; the node (`done` on approve, **`skipped` on
reject**, the guild's spelling); and the linked plan's approval (§1). **The local "two writes,
always" is one call here**, and that is the whole improvement — a gate approved with its node left
behind cannot happen. `decided_by` defaults to `'user'`, which is what a gate is: the guild
master's word, recorded by the orchestrator.

---

## 5. The roster — not in this database, in either backend

**Identical in both modes.** The roster is the agent files and `roster.py` reads them; nothing
about it is on Kumiai, nothing is synced to it, and no tool exists for it — deliberately.

The ticket's half of the match, which locally is a `group_concat` over `task_capability`:

```json
get {"workspace": "<ws>", "type": "task", "key": "TASK-001"}
→ {"agent": null, "capabilities": [{"capability": "implement", "required": true},
                                   {"capability": "svelte",    "required": true},
                                   {"capability": "frontend",  "required": false}], ...}
```

`agent` set is the pin. The `required: true` words are `--covers implement,svelte`; the
`required: false` words rank. **No output from `--covers`** is a roster gap, and marking it is
still a deliberate write. The local guard has two halves — still `todo`, and no pin — and the
`get` above already answered the second:

```json
set_task_status {"workspace": "<ws>", "actor": "orchestrator", "key": "TASK-014",
                 "status": "blocked", "expect_status": "todo"}
```

---

## 6. Quality and maintenance

```json
upsert_coverage {"workspace": "<ws>", "actor": "qa-strategist", "id": "checkout-flow",
                 "area": "Checkout flow", "risk": "high",
                 "spec_path": "e2e/checkout.spec.ts", "notes": "Money moves here …"}

create_inspection {"workspace": "<ws>", "actor": "qa-strategist", "scope": "whole product",
                   "trigger": "manual", "coverage": ["checkout-flow", "auth", "cart-persistence"]}
→ {"key": "INSP-001", ...}

update_inspection      {"workspace": "<ws>", "actor": "orchestrator", "key": "INSP-001",
                        "status": "in-progress", "started_at": "2026-10-18T09:00:00Z"}
set_inspection_verdict {"workspace": "<ws>", "actor": "qa-tester", "inspection": "INSP-001",
                        "coverage": "checkout-flow", "verdict": "issues"}
```

`create_inspection`'s `coverage` is the local `inspection_coverage` seeding — pass the ids from
`list {"type": "coverage"}` when the inspection covers every area. `verdict: "not-reached"` is
still the honest answer for an area the inspection ran out of road before.

`upsert_coverage` needs `area` only to create a row; on an existing one it is a patch. Stamp
`last_inspected_at` **only when the area was actually inspected**, in a call of its own, so a
re-saved risk or note can never make a stale area read as fresh:

```json
upsert_coverage {"workspace": "<ws>", "actor": "qa-tester", "id": "checkout-flow",
                 "last_inspected_at": "2026-10-18T09:42:00Z"}
```

### Validation runs on the server

`docs/expectations.md`'s assertions are SQL against `guild.db`. On Kumiai they run **server-side**,
against the same rules, from one call:

```json
check_invariants {"workspace": "<ws>"}                          // §3, the eleven globals
check_invariants {"workspace": "<ws>", "process": "check-in"}   // §3 + that process's section
check_invariants {"workspace": "<ws>", "process": "new-requirement", "requirement": "REQ-007"}
→ {"ok": false,
   "failures": [{"id": "G5", "description": "ticket routing",
                 "rows": [["no-pin-no-capabilities", "TASK-010", "todo"]]}],
   "checked": ["G1", "G2", …, "4.f"],
   "skipped": [{"id": "P4.b", "reason": "the roster is the agent files — roster.py, not SQL"}, …]}
```

`rows` are the offending rows the assertion would have printed — `[breach, row_id, detail]`.
Report them verbatim, as `guild:validate` does locally. `requirement` scopes a per-requirement
section (§4's `REQ-NNN`) and is **required** with `process: "new-requirement"` (`VALIDATION`
without it). Run `new-requirement` where that skill ends — after the graph, **before** `gate-plan`
is resolved: §4.a asserts nothing has moved yet. A failure marked `"advisory": true` (§9.c,
released over an open task) is reported and does not make `ok` false — it is the pre-release
gate's warning, not a stop. `checked` lists what ran; `skipped` names every assertion that stays
local (the roster, git, the dashboard file, the before/after comparisons) with the reason.

Release §9.a's before/after comparison is `fingerprint {"workspace": "<ws>"}` — call it before the
release writes and after, and the only difference permitted is the one `guild_state` row (plus,
on Kumiai, the `released` event the release records).

---

## 7. Things not to do

Everything in `queries.md` §7 still holds. On Kumiai specifically:

- **Do not `record_event` to stand in for a write.** Every mutating tool writes its own event, as
  the triggers do. `record_event` is for the guild's explicit events only — the shift's
  `started`/`ended` and a release — and a hand-written `moved` is a forged feed.
- **There is no delete tool, and do not look for one.** The only two removals are `unlink` (a
  doc → doc edge while retiring a decision) and `remove_task_dependency`. Work is retired by status.
- **Do not open `.guild/guild.db` in a kumiai project**, even to read. If one exists it is a
  different board, and an answer read from it is an answer about the wrong guild.
- **Do not call a status-moving tool with a member as `actor`** — `set_task_status`,
  `set_node_status`, `resolve_gate`, `update_plan {status|approval}`, `update_bug {status}`,
  `supersede_doc`, `update_inspection {status}`, `update_finding {disposition}`, or a
  `status` on `update_requirement` / `update_project` / `update_goal`. `check_invariants
  {process: "check-in"}` reports each one as `status-moved-by-non-orchestrator`. Report the
  outcome; the orchestrator moves it.
- **Do not move a status without `expect_status`** where the local recipe guards it. An unguarded
  move is an overwrite of whatever somebody else just did.
- **Do not stop at the first page.** A non-null `next_offset` is more rows, and a count or a
  "nothing left" taken from page one is a wrong answer that looks right.

---

## Known limits

What the contract still does not do, and what to do about it:

- **No traversal.** `doc_neighbors` and every graph read are one hop, as locally. Loop and cap in
  the caller (§1).
- **Not everything in `docs/expectations.md` is about the board.** §6 checks the built
  `dashboard.html` and §11.f checks git; those run locally, as written, in both backends.
- **Fixtures do not load into Kumiai.** `guild:validate --fixture` seeds a scratch `tursodb` file
  in both backends.
- **Priority 5 reads back as 4** on projects (§1).
