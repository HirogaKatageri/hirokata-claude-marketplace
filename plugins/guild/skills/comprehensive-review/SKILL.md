---
name: comprehensive-review
description: Use this skill when the user wants to review code changes, verify implementation quality, or check readiness before a PR or deployment. Trigger on phrases like "review my changes", "run comprehensive review", "check all my code", "am I ready for PR", "before I create a PR", "before I merge", "code audit", "quality check", "verify my implementation", "is my feature complete", "run all reviewers", "check if my implementation is complete", "deep code review", "deep review", or any multi-dimensional code analysis request. Also use proactively when the user says they've finished a phase, completed a feature, or are wrapping up work — even if they don't explicitly ask for a "review". Covers requirements, business logic and tests, edge cases, security, architecture, and an audit that runs the project's checks.
version: 1.0.0
user-invocable: true
---

# Comprehensive Review

Reviews a set of changes with many `guild:reviewer` agents at once, each with one lens
and one slice of the changes, then merges their findings into one report. It reads and
reports. It never fixes code and never writes to the guild board.

A finished guild project is reviewed by check-in itself (`guild:check-in` Step 4.5a),
which files the findings as issues. This skill is the on-demand version for "am I ready?"

## Step 1 — The scope

1. **The changes.** Use what the user named (a branch, a commit range, files). Otherwise
   take the current branch against its base: `git diff --stat main...HEAD` plus
   uncommitted changes. Nothing changed → ask for a range or files.
2. **The requirements.** When `.guild/config.yaml` exists, read the board (read only):

   ```bash
   export PATH="$HOME/.turso:$PATH"
   printf "SELECT json_object('id',id,'project',project_id,'status',status,'title',title)
      FROM requirement ORDER BY created_at, id;\n" | tursodb -q -m list .guild/guild.db
   ```

   Otherwise look for plan or requirement files in `docs/`, `planning/` or
   `requirements/`. Pick the ones the changes are for and confirm with the user when it
   is unclear. None at all → ask, or skip the `requirements` lens if the user says so.

## Step 2 — The matrix

Split the changed files into **slices**: group them by feature or top folder, at most
**four slices**, of about the same size. Fewer than about 15 changed files is one slice.

| Lens | One reviewer per |
|---|---|
| `requirements`, `business-logic`, `edge-cases`, `security` | slice |
| `architecture`, `audit` | all the changes |

## Step 3 — Spawn

**Always spawn the reviewers, however small the change.** Do not review the code
yourself instead: a single reader misses what six narrow ones catch, and the audit lens
is the only one that runs the checks. Your job is the scope, the merge and the report.

All reviewers in one message. Each prompt:

```
You are a reviewer in AD-HOC mode. Do not write to any board.
LENS:  {lens}
SCOPE: changes: {range}
FILES: {the slice's files, or every changed file}
REQUIREMENTS: {REQ-ids on the guild board, or file paths, or "none"}
Follow guild:review-lenses with the lens above. Report, do not fix. End with DONE or
FAILED and the findings block.
```

A reviewer that ends `FAILED`, or without a findings block, is spawned again once. A
second failure is named in the report as a lens not reviewed.

## Step 4 — Merge

Same problem from two lenses (same file, lines within 5, the same fault) → one finding
with the highest severity and both lenses named. Then sort by severity.

## Step 5 — Report

```markdown
# Comprehensive Review

**Scope:** {range}, {n} files, {n} reviewers ({lenses} × {slices})
**Status:** {Ready | Ready with warnings | Needs work | Blocked}
**Findings:** {n} critical, {n} major, {n} minor, {n} nit

| Lens | Result |
|---|---|
| Requirements | {n of m met, or "skipped: no requirements"} |
| Business logic | {n findings} |
| Edge cases | {n findings} |
| Security | {n findings} |
| Architecture | {n findings} |
| Audit | {the commands run and their result, such as "pnpm test: 48 passed"} |

## Fix before merging
1. **{title}** ({severity}, {lenses}) — `{file}:{line}`
   {body}

## Fix soon
…

## Worth knowing
…

## Checked and fine
{each reviewer's "Checked and fine" line, one per lens}
```

**Status:** any critical, or a failing build or test suite → **Blocked**. Any major →
**Needs work**. Only minor and nit → **Ready with warnings**. Nothing → **Ready**.
`references/review-interpretation.md` has more on reading results across lenses.

## Limits

This skill finds problems. It does not fix them, and it does not replace a person's
judgment on the result.
