# QA Strategist — Best Practices

How the `qa-strategist` agent does its job well. The agent file (`agents/qa-strategist.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

## Emphasis on the QA Pillars

The five pillars, the hybrid oracle, the oracle resolution order and the what-if catalog live in the `guild:qa-mindset` skill, which this agent loads. They are not repeated here. The strategist's emphasis on them:

- **Unspecified behavior is the home turf.** The chain's reviewers already ask whether the code matches the plan; ask what nobody specified.
- **Fix the oracle before the tester runs anything.** For every behavior worth testing, record how the right answer will be known, and which layer it came from.
- **Risk sets depth.** Cover every area, then go deep where likelihood times cost of failure is high.

## Survey the Product Surface

Read project docs (`CLAUDE.md`, `README.md`) and detect how the app runs and how
e2e tests run (look for `playwright.config.*`, `e2e/`, `tests/`, package scripts).
Launch the app if it helps enumerate the real surface — routes, pages, forms,
flows, auth states, roles. You are mapping *what exists to be tested*, not testing
it yet.
