---
name: svelte-best-practices
description: >
  Pre-loaded Svelte 5 / SvelteKit 3 best practices for the developer-svelte
  agent. Covers supported versions, state management strategies, performance
  optimization, accessibility, SEO, TypeScript usage, testing (vitest +
  playwright), error handling, migration, and official Svelte tooling. Load
  alongside the other svelte-* skills before implementing anything
  non-trivial. Trigger phrases include "svelte best practices", "svelte
  performance", "svelte accessibility", "svelte typescript", "svelte
  testing", "sveltekit seo", "sveltekit error handling", "sveltekit 3
  migration".
version: 2.0.0
---

# Svelte 5 / SvelteKit 3 — Best Practices

Cross-cutting guidance: how to choose the right primitives, keep apps fast and accessible, and write code that doesn't break in production.

## Supported Versions

This guidance targets **Svelte 5.57+** and **SvelteKit 3.2+** (Kit 3 needs Node 22.17+, TypeScript 6+, Vite 8.0.12+, `@sveltejs/vite-plugin-svelte` 7+). Svelte 6 is not released.

Before writing code, read `package.json`:

- If the project is on an **older** Svelte 5 minor or on **SvelteKit 2**, follow the installed version and the patterns already in the codebase. Do not use APIs newer than the installed version. Examples of version gates:
  - Svelte < 5.56: no declaration tags — use `{@const}`.
  - Svelte < 5.40: no `createContext` — use `setContext` / `getContext`.
  - Svelte < 5.29: no `{@attach}` — use `use:` actions.
  - Svelte < 5.25: `$derived` values are read-only.
  - SvelteKit 2: `svelte.config.js`, `$lib`, `$app/environment`, `$env/*`, `invalidateAll`, `pushState` / `replaceState` are still the normal APIs.
- Do not upgrade a project's major versions unless the task asks for it.

**Experimental features** — use them only if the project already enables the flag, or the task explicitly asks for it:

| Feature | Flag |
|---|---|
| `await` in components, `$effect.pending()`, `hydratable`, `fork` | `compilerOptions.experimental.async` (Svelte 5.36+) |
| Remote functions (`query`, `form`, `command`, `prerender`) | `experimental.remoteFunctions` **and** `compilerOptions.experimental.async` |
| Forked preloading | `experimental.forkPreloads` |

In SvelteKit 3 these flags live in `sveltekit({...})` inside `vite.config.ts` (there is no `svelte.config.js`).

## State Management Strategy

Pick the smallest scope that works:

1. **Component-local** — `let x = $state(0)` inside a `.svelte` file. Only use `$state` for values that must be reactive (read by the template, `$derived`, or `$effect`); everything else is a normal variable.
2. **Per-feature module** — a `.svelte.ts` file exporting a class with `$state` fields, or an object you mutate (`export const counter = $state({ value: 0 })`). Classes with `$state` fields are the recommended replacement for stores.
3. **Context** — tree-scoped state shared by several components (a form, a dropdown, the current user). Prefer `createContext` (5.40+) for type safety:
   ```ts
   // user-context.ts
   import { createContext } from 'svelte';
   export const [getUserContext, setUserContext, hasUserContext] = createContext<User>(); // `has` since 5.57
   ```
   Pass a `$state` object (mutate its properties) or a getter (`setUserContext(() => data.user)`) so the value stays reactive. Context is also the safe way to share per-request state during SSR.
4. **URL** — for state that should survive reloads, deep-link, or affect SSR (filters, pagination, tabs). Read via `page.url.searchParams` (`page` from `$app/state`), write with `goto('?x=1', { replace: true, reset: false })` (Kit 3; on Kit 2 use `replaceState: true, keepFocus: true, noScroll: true`). `page.url` is read-only in Kit 3 — copy with `new URL(page.url.href)` before mutating.
5. **Snapshots** — ephemeral UI state (draft text, scroll inside a panel) that should survive back/forward. Kit 3: call `snapshot({ capture, restore })` from `$app/navigation` during component init (`export const snapshot` is deprecated).
6. **Cookies / DB** — for state that crosses sessions or needs server enforcement. Set in form actions / `+server` / hooks; read in server `load`.

**Avoid:**
- Exporting `$state` that gets reassigned from a module (importers lose reactivity — see `svelte-core` "Sharing State Across Modules").
- Per-request server state in module scope — modules are shared across requests, so anything written to a module-level variable from a load function leaks between users.
- Side effects in `load` (writing to global state). Return data instead.
- Plain `const x = data.y` in pages/layouts — components are reused across navigations, so derive with `$derived(data.y)`.
- New code with `svelte/store` — stores are still supported but legacy for shared state.

## Server-Only Modules

A module is server-only (importing it from client code is a build error) when:

1. Its filename has a `server` segment (`db.server.ts`, and in Kit 3 also plain `server.ts`), or
2. It lives in **any** `server/` directory outside `src/routes` and `static` (Kit 3). On Kit 2 only `src/lib/server/` counts.
3. It is `+page.server.ts`, `+layout.server.ts`, `+server.ts`, or `hooks.server.ts`.
4. It is `$app/env/private` or `$app/server` (Kit 3), or the deprecated `$env/static/private` / `$env/dynamic/private`.

To mark a published package module as server-only, add `import '$app/server'` at the top. When unsure, check whether a secret could leak. If it could, it goes server-side.

## Performance

### Loading

- **Streaming**: Return promises (not awaited) from server `load` for non-critical data and render them with `{#await}`. Add `.catch(() => {})` to promises you create yourself to avoid unhandled rejections.
- **Avoid waterfalls**: Sibling load functions run in parallel. Start independent work *before* `await parent()`; prefer one server `load` (or a DB join) over chained requests.
- **`fetch` in load**: Always use the load event's `fetch` (not the global). It forwards cookies and reuses SSR responses during hydration.
- **Preload**: `data-sveltekit-preload-data="hover"` (default on `<body>` in new projects) or `"tap"`. Disable with `"false"` — Kit 3 removed the `"off"` value.
- **Code-split**: Routes are auto code-split. For large, conditional feature code, use dynamic `import()` inside `{#await}`.
- **Measure in `preview`**, not `dev` — dev mode is not representative.
- **Images**: use `@sveltejs/enhanced-img` (`npx sv add enhanced-img`).
- **Fonts**: preload critical fonts with the `preload` option of `resolve(event, { preload })` in `handle`.

### Rendering

- Prefer `prerender = true` for pages whose content is build-time stable. Combined with `csr = false` this ships no JS.
- `prerender = 'auto'` prerenders but keeps the route in the server manifest — useful during incremental adoption.
- Use `csr = false` for static content pages (docs, marketing) — eliminates the JS bundle (no `use:enhance`, full-page navigation).
- Use `ssr = false` only for routes that genuinely can't render server-side. SPA mode causes request waterfalls and a flash of empty content.

### Reactivity

- `$derived` is lazy and skips downstream updates when the value is referentially identical. Don't hand-roll memoization.
- `$state.raw` for large arrays/objects you only replace wholesale (API responses). Avoids the proxy cost.
- `$effect` is an escape hatch. Instead of writing state in an effect:
  - derived value → `$derived` / `$derived.by` (deriveds are writable since 5.25 — good for optimistic UI);
  - reacting to user input → the event handler, or a function binding `bind:value={() => v, (x) => set(x)}` (5.9+);
  - syncing a third-party DOM library → `{@attach}` (5.29+);
  - observing something outside Svelte → `createSubscriber` from `svelte/reactivity`;
  - window/document events → `<svelte:window onkeydown={...} />` / `<svelte:document ...>`, not `onMount` / `$effect`.
- Never wrap an effect body in `if (browser)` — effects don't run on the server.
- `{#key}` unmounts everything inside on each change. Use it for transitions, not to force a child's `<script>` to re-run.
- Debug unexpected re-runs with `$inspect.trace('label')` as the first line of an `$effect` or `$derived.by`.
- With experimental async: create promises first, then await them, to avoid the `await_waterfall` warning.

### Bundle

- Avoid importing large libraries at the route level when only one page uses them; dynamic-import them inside the page component.
- Use `precompress` on adapters that support it (adapter-node defaults it to `true`; adapter-bun and adapter-static default to `false`).

## Accessibility

The Svelte compiler emits a11y warnings — **treat them as errors**. They catch real issues:

- `a11y_click_events_have_key_events`, `a11y_no_static_element_interactions`: `onclick` on a non-interactive element. The usual fix is to use a `<button>`.
- `a11y_label_has_associated_control`: pair every `<label>` with `for` or wrap the control.
- `a11y_missing_attribute`: `<img>` needs `alt`, `<a>` needs `href`.
- `a11y_autofocus`: don't auto-focus — disorients screen reader users.

Silence a genuine false positive with `<!-- svelte-ignore a11y_autofocus (reason) -->`, always with a reason.

Use `$props.id()` (5.20+) for SSR-safe `id` / `for` / `aria-*` pairs instead of random IDs:

```svelte
<script>
  const uid = $props.id();
</script>
<label for="{uid}-email">Email</label>
<input id="{uid}-email" type="email" />
```

### Routing, titles & focus

- Give every page a unique `<title>` in `<svelte:head>` — SvelteKit's route announcer reads it after client-side navigation.
- After navigation SvelteKit moves focus to `<body>`. Customize deliberately with `afterNavigate` (e.g. focus the page `<h1>`), and add a "skip to content" link.
- Be careful with preserving focus/scroll: `goto(url, { reset: false })` or `data-sveltekit-reset="false"` in Kit 3 (`keepFocus` / `noScroll` / `data-sveltekit-keepfocus` on Kit 2).
- Set `<html lang="...">` in `src/app.html`, or use a `%lang%` placeholder replaced via `transformPageChunk` in `handle` for multi-language sites.

### `aria-current="page"`

For nav links pointing at the current route:

```svelte
<a href="/" aria-current={page.url.pathname === '/' ? 'page' : undefined}>Home</a>
```

If the project uses experimental async and navigation holds back updates, `$state.eager(page.url.pathname)` (5.41+) shows the new highlight immediately. Use it sparingly, only for feedback on user actions.

### Reduced motion

Svelte transitions run on the Web Animations API, so a CSS `@media (prefers-reduced-motion)` rule does **not** affect them. Use `prefersReducedMotion`:

```svelte
<script>
  import { prefersReducedMotion } from 'svelte/motion';
  import { fly } from 'svelte/transition';
  const duration = $derived(prefersReducedMotion.current ? 0 : 300);
</script>

<p transition:fly={{ y: prefersReducedMotion.current ? 0 : 200, duration }}>...</p>
```

## SEO

- Set `<svelte:head>` per page (`<title>`, `<meta name="description">`, OG tags, canonical URL).
- Prefer SSR or prerendering for any public, indexable page.
- For sitemaps, add `src/routes/sitemap.xml/+server.ts` returning `new Response(xml, { headers: { 'Content-Type': 'application/xml' } })`. In Kit 3 the `json()` / `text()` helpers are deprecated — use `Response.json()` / `new Response()`.
- Use semantic HTML (`<article>`, `<nav>`, `<main>`) — Svelte's a11y warnings nudge you toward this anyway.
- Avoid client-only rendering for marketing pages; crawlers vary in JS support.

## TypeScript

### Project setup

`npx sv create` with TypeScript scaffolds the right config. In **Kit 3**:

- `tsconfig.json` extends `$app/tsconfig` (not `./.svelte-kit/tsconfig.json`) and must declare `include` / `exclude`:
  ```json
  { "extends": "$app/tsconfig", "include": ["src", "test", "*"], "exclude": ["src/service-worker"] }
  ```
- `verbatimModuleSyntax` and `isolatedModules` are required — use `import type` for type-only imports.
- `$lib` is replaced by `#lib` (Node subpath imports in `package.json` `imports`). Imports need explicit extensions: `import { db } from '#lib/server/db.js'`. Don't add path aliases by hand — the `alias` option is deprecated.

`<script lang="ts">` only strips types. Enums and other non-erasable syntax need `vitePreprocess({ script: true })`; prefer erasable syntax instead.

### Components

```svelte
<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLButtonAttributes } from 'svelte/elements';

  interface Props extends HTMLButtonAttributes {
    title: string;
    count?: number;
    children?: Snippet;
    onsave?: (value: string) => void;
  }

  let { title, count = 0, children, onsave, ...rest }: Props = $props();
</script>
```

Use `ClassValue` from `svelte/elements` for `class` props, `Component<Props>` / `ComponentProps<typeof X>` for component types (`SvelteComponent` is legacy).

### Generic components

```svelte
<script lang="ts" generics="T extends { id: string }">
  import type { Snippet } from 'svelte';
  let { items, render }: { items: T[]; render: Snippet<[T]> } = $props();
</script>

{#each items as item (item.id)}
  {@render render(item)}
{/each}
```

### Routes

Import `PageProps`, `LayoutProps`, `PageServerLoad`, `PageLoad`, `LayoutServerLoad`, `LayoutLoad`, `RequestHandler`, `Actions`, `EntryGenerator` from `./$types`. They are generated — never write them by hand. Pages also receive a typed `params` prop (Kit 2.24+). Use `RouteId` / `RouteParams` from `$app/types` for typed route helpers.

Kit 3 moved some types:

| Type | Import from (Kit 3) |
|---|---|
| `Handle`, `HandleFetch`, `HandleServerError`, `HandleClientError`, `Reroute`, `Transport` | `@sveltejs/kit/hooks` |
| `Page`, `ReadonlyURL` | `$app/state` |
| `ActionResult`, `SubmitFunction` | `$app/forms` |
| `BeforeNavigate`, `AfterNavigate`, `OnNavigate`, `GotoOptions` | `$app/navigation` |
| `RemoteQuery`, `RemoteForm`, `RemoteCommand` | `$app/server` |

### App-wide types

`src/app.d.ts`:

```ts
declare global {
  namespace App {
    interface Locals { user?: { id: string; email: string } }
    interface PageData {}
    interface PageState { showModal?: boolean }
    interface Platform {}
    interface Error { code?: string } // `status` and `message` are built in — don't redeclare them
  }
}
export {};
```

`Locals` types `event.locals`. `PageState` types `page.state` (shallow routing). `Platform` types `event.platform` (in Kit 3, Cloudflare bindings come from `import { env } from 'cloudflare:workers'` instead).

## Testing

### Vitest (unit and component tests)

`npx sv add vitest` sets up two Vitest projects:

- **client** — Vitest browser mode (Playwright, Chromium) for `src/**/*.svelte.{test,spec}.{js,ts}`, using `vitest-browser-svelte`.
- **server** — Node environment for `src/**/*.{test,spec}.{js,ts}`.

```ts
// Counter.svelte.spec.ts
import { page } from 'vitest/browser';
import { expect, it } from 'vitest';
import { render } from 'vitest-browser-svelte';
import Counter from './Counter.svelte';

it('increments', async () => {
  render(Counter, { initial: 0 });
  await page.getByRole('button').click();
  await expect.element(page.getByRole('button')).toHaveTextContent('1');
});
```

Follow whatever setup the project already has — jsdom + `@testing-library/svelte` is still an official option.

- Test files that use runes must have `.svelte` in the name (`counter.svelte.test.ts`).
- To test effects outside a component, wrap them in `$effect.root(() => { ... })`, call `flushSync()` after state changes, and call the returned cleanup.
- To test bindings, context, or snippet props, render a small wrapper test component.

### Playwright (E2E)

```ts
// src/routes/home.e2e.ts
import { expect, test } from '@playwright/test';

test('home page', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
});
```

Set it up with `npx sv add playwright`. Its `webServer` config builds and runs the preview server (`npm run build && npm run preview`, port 4173) before the tests, and `testMatch` only picks up `*.e2e.{ts,js}` files — name E2E tests accordingly (or follow the project's existing config).

### Test boundaries

- Pure functions in plain modules → Vitest (server project).
- Components → Vitest browser mode (or the project's existing component-test setup).
- Routes (load functions, form actions) → call the exported functions directly with mock event objects, or cover with Playwright.
- Don't unit-test the framework — trust SvelteKit's primitives.

## Error Handling

### Expected vs. unexpected

- **Expected** (`error(404, '...')`, `fail(400, ...)`): user-facing, status-coded. Use them liberally.
- **Unexpected** (uncaught throws): logged via `handleError`. Never expose internals to the user — unknown errors reach the client as `{ status: 500, message: 'Internal Error' }` unless you return something else.

### Patterns

```ts
// +page.server.ts
import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params, locals }) => {
  const post = await db.getPost(params.slug);
  if (!post) error(404, 'Post not found', { code: 'NOT_FOUND' }); // Kit 3: extra props as 3rd argument
  if (!locals.user && post.private) error(401, 'Login required');
  return { post };
};
```

- Kit 3: passing an object as the second argument (`error(404, { message })`) is deprecated. On Kit 2 the object form is the way to add extra fields.
- Don't call `redirect()` / `error()` inside a `try` block that would catch them. Check with `isHttpError` / `isRedirect`, not `instanceof`.
- Kit 3: external redirects must opt in — `redirect(307, 'https://example.com', { external: true })`.

### `handleError` (Kit 3)

`handleError` now receives **every** error, including expected ones, with a `kind` discriminant (`'app' | 'framework' | 'validation' | 'unknown'`). Return an `App.Error` (optionally with `status`), report only unexpected errors, and never throw from it. `handleValidationError` was removed — validation failures arrive as `kind: 'validation'`. See `svelte-advanced` for the full hook.

### `+error.svelte`

Show the error from the `error` prop (`let { error } = $props()`, an `App.Error` with `status` and `message`) or from `page.error` (`page` from `$app/state`), and link back home or to the previous page. Keep production messages generic; rely on logs for diagnostics. In Kit 3 each `+error.svelte` is also an automatic error boundary for rendering errors.

### Form actions

Return validation problems with `fail(status, data)` instead of throwing — the `form` prop preserves user input. In Kit 3 the enhanced response uses the `fail()` status code, and `use:enhance` on a form posting to another page's action now navigates there (opt out with `update({ navigate: false })`).

```ts
if (!email) return fail(400, { email, missing: true });
```

Form actions are feature-complete and remain the stable choice. Remote `form` functions are experimental (see the flag table above).

### `<svelte:boundary>`

For component-level recovery (e.g., a flaky third-party widget), wrap it in a boundary with a `failed(error, reset)` snippet that offers a retry button. Report with `onerror={(error) => report(error)}`. Boundaries catch errors during rendering and effects, **not** in event handlers, `setTimeout`, or other async work outside rendering. Don't use boundaries to hide bugs.

## Migration & Compatibility

- Runes mode is decided per component: a component that uses runes is in runes mode. `<svelte:options runes={true} />` forces it for one component. To force it for the whole app except dependencies (Svelte 5.54+):
  ```ts
  sveltekit({
    compilerOptions: {
      runes: ({ filename }) => (filename.split(/[/\\]/).includes('node_modules') ? undefined : true)
    }
  })
  ```
- Don't half-migrate a file. Once it is in runes mode, legacy syntax is unavailable.
- In new code use the modern form (see `svelte-core` for details, and `references/deprecations.md` §1 for the full list with versions):
  - `$state` / `$derived` / `$props` — not implicit `let`, `$:`, `export let`, `$$props`, `$$restProps`
  - `onclick` — not `on:click`; callback props — not `createEventDispatcher`
  - snippets + `{@render}` — not `<slot>`, `$$slots`, `<svelte:fragment>`
  - `<Dynamic />` — not `<svelte:component>`; self-import — not `<svelte:self>`
  - `{@attach}` — not `use:` actions; `class={[...]}` / `class={{...}}` — not `class:`
  - `createContext` — not raw `setContext` / `getContext`
  - `{const x = ...}` declaration tags (5.56+) — not `{@const}`
  - `Spring` / `Tween` classes — not the deprecated `spring` / `tweened` stores
- Don't quote single expressions in attributes (`disabled={x}`, not `disabled="{x}"`) — Svelte 6 will coerce quoted values to strings.
- Codemods: `npx sv migrate svelte-5` (Svelte 4 code), `npx sv migrate self-closing-tags`, `npx sv migrate sveltekit-3`.

### Deprecated and removed APIs

The full log lives in [`references/deprecations.md`](references/deprecations.md): every deprecated, removed or legacy Svelte and SvelteKit API, with its status, the version it changed in, the replacement and the codemod. Read it before touching existing Svelte code or upgrading. The most common SvelteKit 3 changes:

- `svelte.config.js` → `sveltekit({...})` in `vite.config.ts`
- `$lib/foo` → `#lib/foo.js`
- `$app/stores` → `$app/state` (removed in Kit 3)
- `$env/*` → `src/env.ts` + `$app/env/private` / `$app/env/public`
- `invalidateAll` → `refreshAll`; `pushState` → `goto(url, { shallow: true, state })`
- `json()` → `Response.json()`; `error(404, { message })` → `error(404, 'message')`

Upgrade to the latest 2.x first to see deprecation warnings, then run `npx sv migrate sveltekit-3` one task at a time (committing after each) until every applicable task has run — the app is not expected to work after only some tasks. Search for the `@migration-task` comments it leaves.

## Warnings That Signal Anti-Patterns

Fix the cause rather than silencing these:

- `state_referenced_locally` — state captured by value (e.g. passed to context). Pass a getter instead.
- `non_reactive_update` — a variable is reassigned and read in the template but isn't `$state`.
- `effect_update_depth_exceeded` — an effect reads and writes the same state. Usually it should be `$derived`, or not state at all.
- `state_unsafe_mutation` — writing state inside `$derived` or a template expression.
- `ownership_invalid_mutation` — a child mutates a prop it doesn't own. Use a callback prop or `$bindable`.
- `console_log_state` — logging a proxy. Use `$inspect(...)` or `$state.snapshot(...)`.
- `hydration_mismatch` / `node_invalid_placement_ssr` — usually invalid HTML nesting (e.g. `<div>` inside `<p>`).
- `element_invalid_self_closing_tag` — `<div />` on a non-void element. Write `<div></div>`.

## Official Svelte Tooling

When available in the environment:

- `npx sv check` (or the project's `npm run check`) — type and Svelte diagnostics. `--fail-on-warnings` makes warnings fail.
- Svelte MCP autofixer — `npx -y @sveltejs/mcp svelte-autofixer ./src/lib/Component.svelte --svelte-version <version from package.json>`. Add `--async` if the project enables experimental async. Re-run until it reports no issues or suggestions. If the Svelte MCP server is connected, `list-sections` + `get-documentation` give the current official docs.

## Hygiene Checklist Before Marking a Task Done

- [ ] Code matches the Svelte / SvelteKit version in `package.json`; experimental APIs only where the project enables the flag
- [ ] Compiler a11y warnings addressed (or suppressed with a reason)
- [ ] No `console.log` left in production paths
- [ ] No server-only imports from client code; `npx sv check` / `npm run check` passes
- [ ] All public-facing pages have `<svelte:head>` with a unique title + description
- [ ] Form actions return `fail(...)` for validation; `error(...)` for expected HTTP errors
- [ ] All `{#each}` blocks are keyed by a stable id (never the index)
- [ ] No `$effect` that only computes a value (use `$derived`); effects with subscriptions return a cleanup
- [ ] Generated types (`./$types`) are imported, not hand-written
- [ ] On Kit 3: no `$app/stores`, `$lib`, `svelte.config.js`, or new `$env/*` imports
