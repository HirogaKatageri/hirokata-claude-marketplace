---
name: new-goal
description: >
  This skill should be used when the user asks to "add a goal", "new goal", "set a
  goal", "I want to build", "I want to achieve", "new requirement", "add a
  requirement", "I need a feature", "queue a feature", "add to the guild", or wants to
  add new work to the guild board. Works out where the request belongs — a new goal
  with its success criteria, a new project under an open goal, or a new requirement
  under an open project — writes it with the user, and hands over to guild:check-in,
  which fills in the rest and puts every plan in front of the user for approval.
version: 1.0.0
user-invocable: true
arguments:
  - name: request
    description: What the user wants, in their own words
    required: false
---

# New Goal — adding work to the guild

You turn what the user wants into the right row on the board, then hand over to
`guild:check-in`. You write **one** thing: a goal, a project or a requirement. Everything
under it (projects, requirements, plans) is check-in's job, so it is never written twice.

**Load `guild:warehouse` first** for the connection steps and the hex rule. Every piece of
free text crosses as `CAST(x'<hex>' AS TEXT)`.

## The three places new work can go

| The request is… | Example | It becomes |
|---|---|---|
| a new outcome | "Build a CMS" | a **goal**, with success criteria |
| a large piece of an open goal | "The CMS also needs a media library" | a **project** under that goal |
| one more thing an open project must do | "Sign-up should also accept Google accounts" | a **requirement** under that project |

## Step 1 — The board

```bash
export PATH="$HOME/.turso:$PATH"
[ -f .guild/config.yaml ] && tursodb -q -m list .guild/guild.db "SELECT version FROM schema_version"
```

- **No config** → create the board exactly as `guild:check-in` Step 1.1 does.
- **Version below 10** → stop and say: "This is a version 9 board. Run `/guild:check-in`
  first, which offers to archive it and start fresh."
- **`backend: kumiai`** → stop. Schema 10 is local only for now.

## Step 2 — Understand the request

If the user has not said what they want, ask in plain text and wait for the answer. Then
read what is open:

```sql
SELECT id, title, success_criteria FROM goal WHERE status <> 'done'
 ORDER BY priority, created_at;
SELECT p.id, p.goal_id, p.title FROM project p
 WHERE p.status <> 'done' ORDER BY p.priority, p.created_at;
```

**Nothing open** → it is a new goal. Go to Step 3.

**Something open** → decide where the request most likely fits, then confirm with one
`AskUserQuestion`. Put your best guess first and mark it "(Recommended)":

- **New goal** → Step 3
- **New project under {GOAL-id} {title}** → Step 4 (one option per goal it could fit)
- **New requirement under {PROJ-id} {title}** → Step 5 (one option per project it could fit)

Offer at most four options. Do not offer a project under a goal that is `done`.

## Step 3 — A new goal

A goal needs two things the user must give: **what** they want, and **how to tell** it is
done.

1. **Title.** Short, in the user's words: "Build a CMS".
2. **Success criteria.** Either a number with a target ("p95 page load under 1 second") or
   a plain outcome someone can check ("Editors can publish a page without a developer").
   Offer two or three candidates with `AskUserQuestion`, written from what they said, and
   let them pick one or write their own in "Other". Never leave it vague: "works well" is
   not a criterion.
3. **Priority**, only if other goals are open: higher, same or lower than them (1 to 5).
4. **Depends on**, only if other goals are open: does this goal need another one finished
   first? Most do not. Ask only when the request hints at it.

Write it:

```sql
PRAGMA foreign_keys = ON;
UPDATE guild_state SET value = 'user' WHERE key = 'actor';

INSERT INTO goal (id, title, body, success_criteria, priority, created_at, updated_at)
SELECT 'GOAL-' || printf('%03d',
         COALESCE(MAX(CAST(substr(id, instr(id, '-') + 1) AS INTEGER)), 0) + 1),
       CAST(x'<hex title>' AS TEXT), CAST(x'<hex of the request, in the user words>' AS TEXT),
       CAST(x'<hex criteria>' AS TEXT), 3,
       strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
  FROM goal
RETURNING id, title;

-- only if it depends on another goal
INSERT INTO goal_dependency (goal_id, depends_on) VALUES ('GOAL-004', 'GOAL-002');
```

The actor is `user` because the goal is the user's decision. Set it back to `orchestrator`
before handing over.

## Step 4 — A new project under an open goal

The project-manager writes it, so it is shaped like the goal's other projects. Spawn
`guild:project-manager` with the *projects* prompt from
`guild:check-in` → `references/dispatch-prompts.md`, in **check-in** mode, and add:

```
The user wants this added to {GOAL-id}: "{the request, in their words}".
Write ONLY the project or projects this request needs. Do not change or repeat the
goal's existing projects. Add a project_dependency where a new project needs an
existing one finished first.
```

Relay its `NEEDS INPUT:` questions with `AskUserQuestion` and `SendMessage` the answers to
the same agent, until it reports. Then read back what it wrote:

```sql
SELECT id, title FROM project WHERE goal_id = '{GOAL-id}' ORDER BY created_at DESC;
```

**A done goal.** If the user wants to add to a goal that is already `done`, write a new
goal instead. A closed goal stays closed.

## Step 5 — A new requirement under an open project

Spawn `guild:project-manager` with the *requirements* prompt, in **check-in** mode, and
add:

```
The user wants this added to {PROJ-id}: "{the request, in their words}".
Write ONLY the requirement or requirements this request needs. Do not change or
repeat the project's existing requirements.
```

Relay questions the same way, then read back:

```sql
SELECT id, title FROM requirement WHERE project_id = '{PROJ-id}' ORDER BY created_at DESC;
```

**A done project.** A project closes when its last requirement does. A new requirement under
a `done` project leaves the project `done` while new work sits inside it, and its review is
already over. So for a done project, offer a **new project** under the same goal instead
(Step 4).

## Step 6 — Hand over

Say what was written, in one or two lines:

```
Added GOAL-004 "Build a CMS" — done when editors can publish a page without a developer.
```

Then one `AskUserQuestion`:

- **Plan it now** → invoke `guild:check-in`. It finds the new row in Step 3 (projects,
  requirements, then plans) and brings every plan to you for approval.
- **Later** → stop. The next check-in or shift picks it up.

## Rules

1. Write one thing: a goal, a project or a requirement. Never plans. Never statuses.
2. A goal always has success criteria the user agreed to.
3. Ask the user to place the request. Never guess silently.
4. Never add work under something that is `done`. Offer a new project or goal instead.
5. Hand over to check-in. Do not copy its steps here.
