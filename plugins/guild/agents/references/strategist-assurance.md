# Assurance — which build plans get a test plan

Load this in Step 2 of the strategist, after you have drawn the build plans and before you
write them.

**Not every build plan needs a test plan.** A test plan costs an agent run and an approval.
For some work it buys nothing: a renamed file, a copy edit or a config value has no behaviour
a test could pin. So decide per build plan, and say the answer in that plan's **Notes**.

Review is not your decision. Every finished project is reviewed through six lenses,
including an audit that runs the checks your Verify sections name, so you never plan
review.

## The question

**Could running something catch a defect in this build plan?**

| Answer | When | What you write |
|---|---|---|
| **tests** | The work has behaviour a test can pin: it computes, decides, stores, parses, validates, authenticates, routes or migrates. A bug would be a wrong answer. | A `test` plan that depends on the build plan, needs `test-authoring`, and lists each test with the acceptance criterion it covers. |
| **checks** | No behaviour to pin, but a command can catch a defect: a build, a type check, a linter, a schema validation, a link check. | No test plan. Put the commands in the build plan's **Verify** section. The agent runs them before reporting DONE. |
| **none** | Nothing to run: a rename, a comment, a one-line copy change. | No test plan. Say "Assurance: none, because ..." in **Notes**. |

## Always tests when

- the work touches authentication, authorization, secrets, money, personal data or production
  data
- it ships a database migration
- the requirement asks for tests in so many words
- other code will depend on what it builds (a shared module, an API contract)

## When unsure, write the test plan

A test plan written cautiously costs the user one approval. A test plan skipped on a guess can
cost a defect that ships.

## End-to-end tests

When an acceptance criterion can only be checked by driving the running app (a sign-up flow,
a page that must render), the test plan needs `e2e` as well as `test-authoring`. Only
`qa-tester` declares `e2e`, and it runs one at a time, so keep e2e test plans few and focused.

## Writing the test plan body

```markdown
# Tests for {build plan title}

## Covers
{PLAN-id of the build plan, and the acceptance criteria of REQ-id under test.}

## Tests
1. {name} — checks {behaviour}. Criterion {n}.
2. ...

## Verify
{The command that runs these tests, and what passing looks like.}
```

List the tests by behaviour, not by implementation. The test agent decides how to write them.
