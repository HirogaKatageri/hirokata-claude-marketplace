---
name: best-practices
description: >
  This skill should be used when the user asks for best practices or good
  practices, or why a practice is recommended, for unit and integration testing
  ("testing best practices", "flaky tests", "slow tests", "test fixtures",
  "mocking vs fakes") or for Svelte 5 / SvelteKit ("svelte best practices",
  "sveltekit best practices", "svelte performance", "svelte accessibility",
  "sveltekit seo"). Not for running a QA pass (use qa) or reviewing a change set
  (use comprehensive-review).
version: 1.3.0
---

# Best Practices

A router to the guild's best-practice references. Each reference is guidance for one area: what to
do, what to avoid, and why. Read the reference that matches the request, plus any paired page this
file names. Do not read the rest.

**Order of authority:** the project's existing conventions and plan, then the reference. Never
rewrite a project's working conventions to match a reference.

## References

| Area | Read | Covers |
|---|---|---|
| Testing (unit and integration) | `references/testing.md` | What to test and what not to; structure and naming; the test-double boundary; test data and isolation; suite speed; determinism; reporting failures; a finish checklist |
| Svelte 5 / SvelteKit | `references/svelte.md` | State management strategy; server-only modules; performance (loading, rendering); accessibility; SEO; TypeScript; testing with vitest and playwright; error handling; migration and compatibility; a hygiene checklist |

### Agent practices

One page per guild agent, named for the agent: the craft that agent applies, with the board
mechanics left in its agent file. Agents do not find these pages by skill triggering; each agent
file names its own page by `${CLAUDE_PLUGIN_ROOT}` path in a `Best Practices` section. A user can
also ask for one.

| Agent | Read | Covers |
|---|---|---|
| `developer` | `references/developer.md` | Exploring the codebase; implementation principles; what to write and not write |
| `developer-svelte` | `references/developer-svelte.md` | Exploring a Svelte project; Svelte 5 implementation principles; the validation checklist. Pairs with `svelte.md` |
| `reviewer-architecture` | `references/reviewer-architecture.md` | Plan alignment; separation of concerns; pattern consistency; coupling; code organization |
| `reviewer-business-logic` | `references/reviewer-business-logic.md` | Acceptance criteria; business rules; data integrity; testability |
| `reviewer-edge-case` | `references/reviewer-edge-case.md` | Boundaries; null and undefined; error scenarios; concurrency; data and state edge cases |
| `reviewer-security` | `references/reviewer-security.md` | Injection; authentication and authorization; data protection; dependencies; input validation |
| `product-reviewer` | `references/product-reviewer.md` | Requirements-versus-diff method and quality standards |
| `test-planner` | `references/test-planner.md` | Surveying test infrastructure; designing the unit and integration plan. Pairs with `testing.md` |
| `test-writer` | `references/test-writer.md` | Test structure; doubles per level; conventions; what not to test. Pairs with `testing.md` |
| `qa-strategist` | `references/qa-strategist.md` | The strategist's emphasis on the `qa-mindset` pillars; surveying the product surface |
| `qa-tester` | `references/qa-tester.md` | Explore then automate; running the app; what to assert under the hybrid oracle rule; authoring e2e specs. Defers to `qa-mindset` for the discipline |
| `researcher` | `references/researcher.md` | Tools and what to weigh when researching |
| `librarian` | `references/librarian.md` | Which document kind a finding becomes; the decision test; the ADR and page shapes |
| `project-manager` | `references/project-manager.md` | Scope; what to uncover; questioning approach; communication style |
| `strategist` | `references/strategist.md` | Designing the work: components, boundaries, dependency order, parallel waves, risks |

## How to Use

1. Identify the area the request touches. For a test request, read `references/testing.md`. For
   a Svelte or SvelteKit request, read `references/svelte.md`. For a question about how a guild
   agent does its job, read that agent's page. The `test-planner`, `test-writer` and
   `developer-svelte` pages pair with `testing.md` or `svelte.md`; read both.
2. Apply the reference to the task at hand. Cite the section when explaining *why* a choice was
   made, so the user can trace the advice.
3. For a "what" or "why" question, answer from the reference and name the section. Do not recite
   the whole page.
4. When the request matches no reference, say so and fall back to the project's own conventions.
   Do not stretch a reference to an area it does not cover.

## Coexistence with Other Skills

- **Testing in a Svelte project:** read both references. Where they differ on framework details
  (vitest, playwright, component testing), `references/svelte.md` wins; `references/testing.md`
  still governs the general rules (isolation, determinism, the test-double boundary).
- **Writing Svelte code:** the best-practice reference covers cross-cutting choices only. The
  component model, routing and deployment live in `guild:svelte-core`,
  `guild:svelte-build-deploy` and `guild:svelte-advanced`.
- **Product QA and e2e passes:** `guild:qa` and `guild:qa-mindset` own the discipline: pillars,
  hybrid oracle, what-if catalog. `references/qa-strategist.md` and `references/qa-tester.md` add
  only what those two agents do with it, and point back at `qa-mindset`.
- **Reviewing a change set:** `guild:comprehensive-review` runs the reviewers. The reviewer pages
  here hold their checklists.

## Adding a Reference

To add an area (for example API design, logging, database migrations):

1. Create `references/<area>.md` (an agent's page is named for the agent), with no frontmatter,
   written in the same shape: numbered sections, rules with their reasons, and a finish checklist
   where it fits.
2. Add a row to the table above.
3. Add the area's trigger phrases to the `description`, each tied to the area name, so the skill
   loads for it without matching unrelated questions.
