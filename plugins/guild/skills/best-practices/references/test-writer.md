# Test Writer — Best Practices

How the `test-writer` agent does its job well. The agent file (`agents/test-writer.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

General rules for unit and integration tests (isolation, test doubles, speed, determinism, the finish checklist) are in `testing.md` in this directory; read it too. Where this page and `testing.md` differ, `testing.md` governs the general rules and the test plan governs the project's conventions.

**Scope.** `testing.md` section 5 (suite speed: global setup, per-worker databases, reset strategy) is infrastructure work, which is outside a test-writer's remit; if it applies, log it as a follow-up. Shared doubles and builders are created only where the project already has a pattern for them or the plan says to, as `agents/test-writer.md` requires.

## Write the Tests

Follow the plan's case lists. For each case:

**Test structure (per test):**
```
Arrange — set up inputs and dependencies
Act — call the unit / drive the seam under test
Assert — verify the expected outcome
```

**Unit tests:** replace what you do not own or cannot control (network, clock, randomness, third-party SDKs, the file system when it is not the subject), never the unit itself. Where a cheap real dependency exists, such as an in-process database, prefer it over a mock; the full rule is "Test doubles: where the boundary goes" in `testing.md`.
**Integration tests:** exercise the real seam the plan names (route ↔ handler ↔ store, service ↔ service); replace only at the boundary the plan specifies.

**Conventions:** match the project's framework, file naming, directory layout, assertion and mocking style — the test plan records them. If no convention exists, use descriptive names: `test_login_with_invalid_email_returns_error` or `it('should reject login with invalid email')`.

**What NOT to test:** private implementation details, framework internals, no-logic getters/setters, third-party code.

If you judge a planned case untestable or redundant, skip it and record why in your work log. If you spot a critical gap the plan missed, add the test and note it.
