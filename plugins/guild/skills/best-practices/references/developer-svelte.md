# Svelte Developer — Best Practices

How the `developer-svelte` agent does its job well. The agent file (`agents/developer-svelte.md`) keeps the procedure — board reads and writes, reporting, what not to do. This page keeps the craft. The project's own conventions and the plan take precedence over anything here.

The framework-level guidance (state strategy, performance, accessibility, SEO, TypeScript, testing, error handling) is in `svelte.md` in this directory; read it too.

## Explore the Codebase

Before writing code:

1. Read the project `README.md` if unfamiliar with the project (`CLAUDE.md` is already in your context — don't re-read it)
2. Check `package.json` to confirm Svelte/SvelteKit versions and the configured adapter
3. Read `svelte.config.js` and `vite.config.*` to understand build setup
4. Find similar features already implemented — follow their patterns
5. Note conventions for: route organization, component structure, state files (`*.svelte.ts`/`*.svelte.js`), styling approach (scoped, Tailwind, CSS modules), test setup
6. Identify shared utilities in `$lib`

## Implement

Write code following these principles:

1. **Svelte 5 first**: Use runes (`$state`, `$derived`, `$effect`, `$props`, `$bindable`). Use the `onclick={...}` event-attribute syntax, not legacy `on:click`. Use snippets (`{#snippet}` / `{@render}`) instead of slots in new code, unless the project's existing pattern is slots.
2. **Match the codebase**: If the project still uses Svelte 4 patterns (`export let`, `on:`, slots, stores), match that — don't half-migrate. Only modernize when the task explicitly calls for it.
3. **Reactive state in the right file**: Component-local state lives inside `.svelte` files; reusable reactive logic goes in `.svelte.ts` / `.svelte.js` modules so the compiler can transform runes.
4. **Keep components small**: A `.svelte` file is a component. Pull pure logic into `$lib` and shared reactive state into `.svelte.ts` modules.
5. **Server vs. client awareness**: `+page.server.ts`, `+server.ts`, `hooks.server.ts`, and anything in `$lib/server/` are server-only. Don't import them from client code. If unsure, read "Server-Only Modules" in `svelte.md` in this directory.
6. **Use SvelteKit primitives**: Prefer `load` functions for data, form actions for mutations, and remote functions where the project uses them. Don't reinvent fetch wrappers when the framework already provides one.
7. **Production quality**: Proper error handling at system boundaries (form actions, load functions, API routes). Validate user input. Use `error()` and `redirect()` from `@sveltejs/kit` rather than throwing strings.
8. **Accessibility**: Heed compiler a11y warnings — they are correctness issues, not noise.
9. **No over-engineering**: Solve the current problem. No speculative abstractions.
10. **Self-documenting**: Clear names > comments. Only comment the "why" when non-obvious.

**What to write:**
- `.svelte`, `.svelte.ts`, `.svelte.js` files
- `+page.svelte`, `+page.ts`, `+page.server.ts`, `+layout.*`, `+server.ts`, `+error.svelte`
- Hooks (`hooks.server.ts`, `hooks.client.ts`, `hooks.ts`) when the plan calls for them
- Test files (only if the plan specifies tests for this task)

**What NOT to write:**
- Markdown documentation files
- README files
- Separate configuration files unless specified in the plan

## Validate

After writing each Svelte file, mentally run it against the rules from `guild:svelte-core` and `guild:best-practices` → `references/svelte.md` (`svelte.md` in this directory):
- Are runes used correctly (no reassignment of `$derived`, no top-level `$effect` outside components/`.svelte.*` modules)?
- Are server-only imports kept off the client?
- Are accessibility attributes present?
- Do props use `$props()` (not `export let`) in new code?

If the project has typecheck or lint scripts (`pnpm check`, `npm run check`, `svelte-check`), run them on the files you touched.
