# Librarian — Best Practices

How the `librarian` agent does its job well. The agent file (`agents/librarian.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

## Decide what this requirement actually produced

Not every requirement yields all four kinds below. Write what is there and nothing more.

| You found | Write | `kind` |
|---|---|---|
| a rule about the domain — what a refund *is*, when an account is dormant, an invariant the product now promises | one `business` doc per rule-set, named for the domain concept | `business` |
| a subsystem that now works a particular way | one `technical` doc per subsystem, **updated in place** if it exists | `technical` |
| a choice with a real alternative that was rejected | **one `decision` doc per choice** | `decision` |
| an operation somebody will have to perform | a `runbook` | `runbook` |

**The decision test, and hold to it.** A decision doc is worth writing when **a reasonable
engineer could have chosen otherwise**. "We used the existing logger" is not a decision.
"We put sessions in Redis rather than Postgres, accepting another service to run" is. If you
cannot name the alternative and the cost of the choice, you are documenting an
implementation detail — put it in the `technical` doc instead.

**Do not invent a decision the sources do not support.** If the plan is silent on why, say so
in the doc (`Rationale: not recorded at the time`) rather than reconstructing a plausible
one. A fabricated rationale is worse than a missing one, because the next reader will believe
it.

## Doc format

`title`, `kind`, `status`, `area` and `updated_at` are **columns**, projected by every
reader. Do not restate them in the body.

For a `decision`, use the ADR shape — it is the one format worth being strict about, because
the value is entirely in the parts people skip:

```markdown
# {Title — state the decision, not the topic}

## Context
{What was true that forced a choice. The constraint, not the feature.}

## Decision
{What we are doing, in one or two sentences, in the present tense.}

## Alternatives considered
- **{Option}** — {why not}
- **{Option}** — {why not}

## Consequences
{What this costs us. What it makes easy. What it makes hard.
 An ADR with no negative consequence has not been thought about.}

## Provenance
{REQ/PLAN/finding ids this came out of. The edges carry this too — the line is for humans.}
```

For `business` and `technical`, lead with what a reader needs before they can act, and keep
the rules and the examples separate — a rule stated once and illustrated twice survives
editing far better than three worked examples with the rule implied.
