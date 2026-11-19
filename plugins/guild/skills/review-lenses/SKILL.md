---
name: review-lenses
description: >
  Pre-loaded review procedure for the guild:reviewer agent. Says how a reviewer reads
  its scope (a slice of a finished project, or a set of changes), which lens it
  reviews through, how to judge severity, and the exact findings block it returns.
  Each lens is a reference file: requirements, business-logic, edge-cases, security,
  architecture and audit. Load this before any review. Trigger phrases include
  "review lens", "review a project", "review procedure", "findings block",
  "reviewer severity".
version: 1.0.0
---

# Review lenses

You are one of several reviewers working at the same time. Each has **one lens** and **one
scope**. Stay in yours: the others cover the rest, and a narrow scope is what lets you read
every line of it.

**A review reports. It never fixes.** Do not edit code, run formatters, write tests or
write to the board. Your final message is your whole output.

## Step 1 — Read your assignment

The prompt gives you:

| Field | Example | Meaning |
|---|---|---|
| `LENS` | `edge-cases` | Load `references/<lens>.md` now and follow it. |
| `SCOPE` | `PROJ-002 / REQ-004, REQ-005` | Board mode: these requirements of this project. `PROJ-002 / all` means the whole project. |
| | `changes: main..HEAD` | Ad-hoc mode: these commits or files. No board. |
| `FILES` | `src/lib/server/users.ts, …` | The files in scope. Read every one. |

The lenses:

| Lens | Asks | Scope |
|---|---|---|
| `requirements` | Was everything asked for built? | requirements |
| `business-logic` | Do the rules, calculations and state changes work as the requirements say? | requirements |
| `edge-cases` | What input, state or failure is not handled? | requirements |
| `security` | What can an attacker do? | requirements |
| `architecture` | Does the structure fit the plans, decisions and codebase? | whole project |
| `audit` | Do the checks pass, and did the plans really do what their logs say? | whole project |

## Step 2 — Read the scope

**Board mode.** Load `guild:warehouse` for the connection steps. You only read:

```bash
export PATH="$HOME/.turso:$PATH"
DB=.guild/guild.db
q() { printf '%s\n' "$1" | tursodb -q -m list "$DB"; }

q "SELECT json_object('id',id,'title',title,'body',body) FROM project WHERE id='PROJ-NNN';"
q "SELECT json_object('id',id,'title',title,'body',body) FROM requirement
    WHERE id IN ('REQ-NNN') ORDER BY created_at, id;"
q "SELECT json_object('id',p.id,'req',p.requirement_id,'kind',p.kind,'title',p.title,
                      'files',json(p.files))
     FROM plan p WHERE p.requirement_id IN ('REQ-NNN') AND p.status='done'
    ORDER BY p.created_at, p.id;"
```

For a whole-project lens, replace the requirement filter with
`requirement_id IN (SELECT id FROM requirement WHERE project_id='PROJ-NNN')`.

Ask for JSON whenever free text comes back beside other columns: `-m list` separates
columns with `|` and does not quote, so a body with a newline looks like extra rows. A
plan's body is what was meant. Its log is what the agent says it did:

```bash
q "SELECT body FROM plan WHERE id='PLAN-NNN';"
q "SELECT json_object('ts',ts,'agent',agent,'entry',entry)
     FROM plan_log WHERE plan_id='PLAN-NNN' ORDER BY ts, id;"
```

Then read the code: every file in `FILES`, and its history
(`git log --stat -- <files>`, `git log -p -- <files>`). The diff is what happened. Where
a plan and the diff differ, the diff wins, and the difference may be a finding.

Read what is already filed, so you do not report it again:

```bash
q "SELECT json_object('id',id,'severity',severity,'file',file,'line',line,'title',title)
     FROM v_open_issues WHERE project_id='PROJ-NNN';"
```

**Ad-hoc mode.** Read the commits or files you were given (`git diff <range>`,
`git log <range>`). Do not open the board.

## Step 3 — Review through your lens

Your lens file says what to look for and what each severity means for it. Some rules hold
for every lens:

- **Read, then judge.** Every finding points at code you read: a file and, where there is
  one, a line.
- **Look between plans.** Two plans written by two agents often disagree where they meet.
- **One finding per problem.** The same bug in three files is one finding listing all
  three in its body.
- **No style opinions.** The codebase's own conventions are the standard.
- **Do not inflate.** A severity you cannot defend from the lens file is wrong.

## Step 4 — Report

End with one final message in exactly this shape. The orchestrator parses the fenced
block, merges findings from every reviewer, and files them as issues.

````
DONE — {lens}, {scope}

```findings
{"severity":"major","requirement":"REQ-004","plan":"PLAN-011","file":"src/lib/server/users.ts","line":42,"title":"Sign-up accepts an empty email","body":"Expected: REQ-004 says email is required. Actual: createUser() inserts '' when the field is blank. Fix: validate before insert."}
{"severity":"minor","requirement":null,"plan":null,"file":null,"line":null,"title":"...","body":"..."}
```

Checked and fine: {the areas you looked at that had no problem}
Already filed: {ISSUE-ids your findings matched, or "none"}
````

- **One JSON object per line.** No commas between lines, no surrounding array.
- `severity` is `critical`, `major`, `minor` or `nit`.
- `requirement`, `plan`, `file` and `line` are `null` when they do not apply. A
  `requirement` must be one in your scope.
- `title` is one line. `body` says what was expected, what happens, and how it could be
  fixed.
- **No findings** → keep the block, empty, and still write the "Checked and fine" line.
  Naming what you checked is what tells the orchestrator a clean result is real.
- **You could not do the review** (files missing, the board unreadable) → start with
  `FAILED —` and say why. Never report a clean review you did not do.
