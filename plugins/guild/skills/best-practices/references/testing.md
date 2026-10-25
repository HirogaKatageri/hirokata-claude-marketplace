# Testing — Best Practices

How to write unit and integration tests that stay fast, stay deterministic, and fail for the right
reason. It is stack-agnostic: match the project's framework, runner and conventions first, and use
this page for the decisions the project has not already made.

**Order of authority:** the project's existing tests and test plan, then this page. Never rewrite a
project's working conventions to match this page.

## 1. What to test

- **Behavior, not implementation.** Assert what a caller can observe: return values, persisted
  state, emitted events, errors. A refactor that keeps behavior must not break a test.
- **Every acceptance criterion maps to at least one test.** Name the criterion in the test or its
  comment so the trace is readable later.
- **Failure paths are half the job.** For each new unit cover: not found, invalid input, not
  permitted, dependency failure, and the empty and boundary cases (zero, one, many, max).
- **A bug fix starts with a test that fails without the fix.** Mark it as a regression test with
  the bug id.
- **Do not test** private helpers directly, framework or library internals, trivial getters and
  setters, or generated code.
- **Pick the cheapest level that proves the behavior.** Pure logic is a unit test. A seam that
  crosses a real collaborator (route to handler to store, service to service) is an integration
  test. Do not push a unit-sized check up into a slower level.

## 2. Structure and naming

- **One behavior per test.** If the name needs "and", split it.
- **Arrange, act, assert**, separated by blank lines. One act per test.
- **Name the behavior, not the function:** `rejects_login_when_email_is_unverified` beats
  `test_login_2`. The failure message should explain the problem without opening the file.
- **Assert on the outcome that matters**, specifically. `toBe(expected)` beats `toBeTruthy()`.
  Avoid asserting on whole serialized blobs or large snapshots that nobody reviews.
- **No logic in tests.** No loops or branches that decide what to assert. Use a table of cases
  (parameterized test) when the same behavior runs over several inputs.
- **Mirror the source layout** so a test is found where a reader would look for it.

## 3. Test doubles: where the boundary goes

- **Replace what you do not own or cannot control:** network, clock, randomness, email, payment,
  third-party SDKs, the filesystem when it is not the subject.
- **Do not replace what you are testing,** or the layer directly beneath it when its behavior is
  part of the contract. A database-backed service tested against a fake database proves nothing
  about the queries, constraints or triggers that production relies on.
- **Prefer a real dependency that is cheap** (an in-process or containerized database, an
  in-memory implementation that honors the same interface) over a hand-rolled mock that can drift
  from the real thing.
- **Fakes beat mocks beat spies** for readability: a small working fake of an interface survives
  refactors that a call-by-call mock script does not. Assert on interactions only when the
  interaction is the behavior (an email was sent once).
- **Put reusable doubles in one shared place** and reset their state between tests. Do not
  copy-paste setup into every file.

## 4. Test data and isolation

Every test must be runnable alone, in any order, and in parallel with the others.

- **Each test creates what it needs.** Do not depend on rows, files or globals left by another
  test or another file.
- **Use builders or seed helpers with sensible defaults** and let the test override only the
  fields it cares about. The interesting field should be visible in the test.
- **Never assert absolute generated ids, counts of shared state, or ordering you did not request.**
  Resets rarely restart sequences, so "the first row is id 1" breaks the day another test runs
  first.
- **Unique values must be unique per test,** not per file (emails, slugs, names with unique
  constraints). Derive them from a counter or a random suffix, not a literal.
- **Own your cleanup in one place.** The harness resets state after each test. Tests do not each
  clean up, and they do not call the reset themselves.
- **Reset module-level and global state** (current user, feature flags, caches, mocks) that a
  worker keeps between files. A test sets what it needs; it never assumes the previous value.

## 5. Keep the suite fast

Slowness is a design problem, and it compounds: a slow suite gets run less, and a suite that is
run less hides bugs longer. *Example, from one SQL-backed Node integration suite:* most of its time
went on repeated setup rather than on the tests. The table below is written with SQL and
`beforeAll`-style hooks in mind; translate it to the project's own stack.

| Cost that hides in suites | What to do instead |
|---|---|
| Schema migration or app bootstrap in every file's `beforeAll` | Do it **once per run** in a global setup hook. Tests only ever see the latest schema. |
| Heavyweight reset after every test (`TRUNCATE`, drop and recreate, restart a container) | Measure, then pick the cheapest correct reset. For SQL: batched `DELETE`s in one round trip, or a transaction rolled back after each test, are usually far cheaper than `TRUNCATE`. |
| Hand-listed tables in the reset | Read the table list from the catalog so a new table is reset without anyone remembering. |
| Test files run strictly one after another | **Parallelize files, isolate state per worker.** Give each worker its own database or schema (cloning a migrated template is cheap), selected by the runner's worker id, so app code does not change. |
| Redundant resets in `beforeEach` on top of an `afterEach` reset | Keep one. |
| Fixed `sleep`s and long timeouts | Wait on a condition. If a test is slow, find the cause first: it may be intentional (a deliberately padded response) and not worth chasing. |

Rules of engagement:

1. **Measure first.** Instrument one run and split the time into setup, reset, test work and
   import or teardown before changing anything. The expected culprit is often not the real one
   (example: turning off disk sync barely helped a reset whose cost was per-table work).
2. **Change one thing at a time** and re-measure. Record before and after.
3. **Find the knee for worker count.** More workers stop helping once the shared resource (the
   database, a CPU limit) saturates. Fix the number in config instead of using "all cores".
4. **Do not buy speed by dropping isolation.** *Example:* disabling per-file isolation looked fast and
   broke most of a suite through leaked mocks and shared connections. If a speedup needs tests to share
   state, it is not a speedup.
5. **Keep the safety rails.** A reset that deletes every row must refuse to run against a
   database that is not plainly a test database (check the name or an explicit flag).
6. **State what is unverified.** A local speedup is not a CI speedup until CI says so.

## 6. Deterministic by construction

A flaky test is a bug in the test or in the code; neither is acceptable to retry away.

- **Control time:** inject a clock or use fake timers. Never assert against "now" with a tolerance.
- **Control randomness:** seed it, or inject the generator.
- **No network, no real third-party calls.** Use the recorded or faked boundary.
- **No dependence on test order, on the machine's locale, time zone, or working directory.**
- **Await everything.** An unawaited promise passes today and fails under load.
- **Run the suite shuffled and in parallel** before declaring done. Order and race bugs show up
  there first.
- **A flaky test is quarantined with a ticket, not retried silently.**

## 7. Reading failures and reporting

- **Fix the test, not the code, when the test is wrong; report the code when the code is wrong.**
  A test author does not quietly change implementation to make a test pass. Log it as a
  follow-up for the developer.
- **Quote a failing assertion in full** when reporting. Do not paraphrase it.
- **Never weaken an assertion, skip a test, or widen a tolerance to get green** without recording
  why.
- **Say what you did not cover** and why, so a reviewer does not assume it was.

## 8. Finish checklist

- [ ] Every acceptance criterion in scope has a test, and each new unit has its failure paths
- [ ] Each test creates its own data and can run alone, in any order, and in parallel
- [ ] No absolute ids, shared-state counts, or order assumptions in assertions
- [ ] No per-file migration, bootstrap or hand-rolled reset duplicating what the harness does
- [ ] Doubles sit only at the boundary, and shared ones are reset between tests
- [ ] No sleeps, wall-clock, unseeded randomness or network
- [ ] Global and module state set by the test, not assumed
- [ ] The full suite passes, including shuffled and parallel, and lint passes
- [ ] Suite time did not noticeably regress
- [ ] Skipped or added cases against the plan are recorded with reasons
