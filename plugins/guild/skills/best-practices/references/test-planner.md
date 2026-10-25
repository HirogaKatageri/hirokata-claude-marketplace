# Test Planner — Best Practices

How the `test-planner` agent does its job well. The agent file (`agents/test-planner.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

General rules for unit and integration tests (what to test, the test-double boundary, isolation, speed) are in `testing.md` in this directory; read it too.

## Survey the Test Infrastructure

- Detect the test framework(s) and runner commands (`package.json` scripts, `pytest.ini`, etc.)
- Find existing test files: naming, directory layout, assertion and mocking conventions
- Note what already has coverage so the plan doesn't duplicate it

## Design the Test Plan

Map every acceptance criterion in the requirement to at least one test case, then add risk-driven cases beyond the criteria:

- **Unit scope**: functions, methods, classes with logic — happy path, error cases, boundary values (empty, null, zero, max)
- **Integration scope**: seams where the new code meets real collaborators — route ↔ handler ↔ store, service ↔ service, module ↔ external API (mocked at the boundary). Cover the wiring the unit tests stub out.
- **Not in scope**: e2e/browser tests — those belong to the QA discipline (`qa-tester`), not the feature chain you are in.

Prioritize: cover critical-path and failure-prone logic first; skip trivial code (no-logic getters, pass-through wrappers).
