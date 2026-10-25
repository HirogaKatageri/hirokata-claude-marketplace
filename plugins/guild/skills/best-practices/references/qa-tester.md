# QA Tester — Best Practices

How the `qa-tester` agent does its job well. The agent file (`agents/qa-tester.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

The five pillars, the hybrid oracle rule, the oracle resolution order, the what-if catalog and the exploration-versus-automation distinction live in the `guild:qa-mindset` skill, which this agent loads. They are not repeated here. This page is what they mean for the tester's hands.

## Explore First, Then Automate

Do both jobs, in that order: explore to find bugs, then codify the confirmed-good high-risk paths as specs. Every bug you file earns a regression spec once it is fixed.

## Detect How to Run and Test

- **Run the app**: find the dev/preview command (package scripts, `CLAUDE.md`,
  README). Match the project's existing way of launching.
- **E2e framework**: find `playwright.config.*` and the existing e2e dir
  (`e2e/`, `tests/`, `tests/e2e/`). Match the project's conventions — file
  naming, fixtures, selectors (prefer roles / `data-testid` over brittle CSS),
  base URL, auth setup. If Playwright isn't set up and the mission requires it,
  log it as a `Follow-up:` line for `developer` (step 8, Update Your Task, of
  `agents/qa-tester.md`) rather than scaffolding a framework yourself.

## Exercise the Scenarios

Drive the running product through each journey and each row of the what-if input
matrix (the catalog is in `guild:qa-mindset`). For every scenario:

1. State the **expected** result (from the mission's oracle) before observing.
2. Drive the product and observe the **actual** result.
3. Compare, and decide what to assert as below.

## Decide What to Assert

Apply the hybrid oracle rule from `guild:qa-mindset`. In terms of what you produce:

- **Agrees with the oracle, or no oracle but clearly sane** → author a passing
  Playwright spec that locks it as the regression baseline.
- **Contradicts the spec, or fails a what-if sanity check** → do not assert it as
  correct. File a bug (the bug-filing step of `agents/qa-tester.md`). Optionally
  commit a `test.fixme`/skipped spec that documents the *intended* behavior, so the
  gap is tracked and turns green once fixed.
- **Ambiguous and no oracle** → you cannot call `AskUserQuestion` directly; you are
  a subagent, and it only works in the main session. End your final message with a
  `NEEDS INPUT:` block (e.g. "1. Submitting an empty email silently succeeds — is
  that correct?") and stop; the orchestrator relays it to the user and resumes you
  with the answer. Record the answer in your session log so it becomes the oracle
  and is never re-asked. Then assert or file a bug per the answer.

Never silently characterize suspect behavior as "expected" — that bakes bugs into
the regression suite.

## Author the E2e Specs

Write Playwright specs into the **project's real e2e dir** (not `.guild/`), so
they run in CI as normal code. Cover the confirmed-good high-risk journeys and the
input-matrix cases worth locking. Keep specs focused, independent, and named
descriptively. **Run them and confirm they pass** before finishing — a red
baseline is not a baseline. Use the project's runner (e.g. `npx playwright test`).
