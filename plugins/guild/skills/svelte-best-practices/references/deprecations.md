# Svelte & SvelteKit Deprecation Log

The single list of every deprecated, removed or legacy Svelte / SvelteKit API the guild knows about, with what to use instead. Other Svelte skills link here instead of keeping their own copies.

Researched 2026-11-16 against Svelte 5.57.3 and SvelteKit 3.2.0 (official docs, changelogs, migration guides, npm).

## How to use this log

1. **Read the installed versions first** (`svelte` and `@sveltejs/kit` in `package.json`). A row only applies once the project is on or past its "Since" version.
2. **Status decides what you do:**

| Status | Meaning | In new code | In existing code |
|---|---|---|---|
| **Removed** | Gone. Using it breaks the build or fails at runtime. | Never use. | Must be replaced when the project is on that version. |
| **Deprecated** | Still works, may warn, scheduled for removal. | Don't use. Write the replacement. | Leave it unless the task touches that code or asks for migration. Never add more of it. |
| **Legacy** | Still supported, but the docs say to use the modern form. | Don't use in runes-mode / new files. | Match the file's existing style; don't half-migrate a file. |

3. **On an older project** (e.g. SvelteKit 2), a row whose "Since" is newer than the installed version does not apply — keep the project's pattern. Example: `$lib` is correct on Kit 2.
4. **Don't migrate on your own.** Upgrading packages or running `sv migrate` only happens when the task asks. When it does, prefer the codemod in the last column, run one task at a time, commit after each, and search for the `@migration-task` comments it leaves.

Codemods: `npx sv migrate svelte-5` (Svelte 4 → 5), `npx sv migrate sveltekit-3` (tasks: `package-json`, `tsconfig`, `svelte-config`, `environment`, `paths`, `external-redirects`, `shallow-routing`, `params`, `app-state`). Upgrade to the latest Kit 2.x first to see deprecation warnings.

---

## 1. Svelte 5 — component syntax

Nothing has been removed in Svelte 5.x; legacy syntax still compiles in non-runes components. In a runes-mode component, legacy syntax is unavailable. Svelte 6 (not released) is expected to remove some of these.

| Old | Status | Since | Use instead | Fix / warning |
|---|---|---|---|---|
| Implicit reactivity: `let count = 0` re-rendering on assign | Legacy | 5.0 | `let count = $state(0)` | `sv migrate svelte-5` |
| `$:` reactive statements | Legacy | 5.0 | `$derived(...)`; `$effect(...)` only for side effects | `sv migrate svelte-5` |
| `export let prop` | Legacy | 5.0 | `let { prop } = $props()` | `sv migrate svelte-5` |
| `$$props`, `$$restProps` | Legacy | 5.0 | `let { a, ...rest } = $props()` | `sv migrate svelte-5` |
| `on:click={...}` | Deprecated | 5.0 | `onclick={...}` | warning `event_directive_deprecated` |
| Event modifiers (`on:click\|preventDefault`) | Legacy (unavailable in runes mode) | 5.0 | Call `event.preventDefault()` in the handler | — |
| `createEventDispatcher` | Deprecated | 5.0 | Callback props (`let { onsave } = $props()`) | — |
| `<slot>`, `$$slots`, `<svelte:fragment slot>` | Deprecated | 5.0 | `{#snippet}` + `{@render}`; `children` prop | warning `slot_element_deprecated` |
| `<svelte:component this={C}>` | Deprecated | 5.0 | `<C />` (components are dynamic) | warning `svelte_component_deprecated` |
| `<svelte:self>` | Deprecated | 5.0 | `import Self from './ThisComponent.svelte'` | warning `svelte_self_deprecated` |
| `<script context="module">` | Deprecated | 5.0 | `<script module>` | warning `script_context_deprecated` |
| `<svelte:options accessors>` / `immutable` | Deprecated | 5.0 | Remove (no effect in runes mode) | warnings `options_deprecated_accessors`, `options_deprecated_immutable` |
| `new Component({ target })` | Removed (components are no longer classes) | 5.0 | `mount(Component, { target, props })` / `hydrate` / `unmount` | `legacy_component_creation` |
| `beforeUpdate` / `afterUpdate` | Deprecated | 5.0 | `$effect.pre` / `$effect` (unavailable in runes mode) | — |
| Stores for shared state (`writable` etc.) | Legacy | 5.0 | Classes with `$state` fields, or `$state` in `.svelte.ts` | Stores still fine for async streams / interop |
| `spring()` / `tweened()` stores | Deprecated | 5.8 | `Spring` / `Tween` classes from `svelte/motion` | — |
| `use:action` | Legacy | 5.29 | `{@attach fn}`; reuse old actions with `fromAction` (5.32) | — |
| `class:name={cond}` directive | Legacy | 5.16 | `class={[base, cond && 'name']}` or `class={{ name: cond }}` | — |
| `setContext(key)` / `getContext(key)` | Legacy | 5.40 | `createContext()` → `[get, set]` (`[get, set, has]` since 5.57) | — |
| `{@const x = ...}` | Legacy | 5.56 | `{const x = ...}`; reactive: `{const x = $derived(...)}` | — |
| Quoted single expressions (`disabled="{x}"`) | Legacy | 5.0 | `disabled={x}` — Svelte 6 will coerce quoted values to strings | — |

## 2. SvelteKit 3 — configuration

| Old | Status | Since | Use instead | Codemod |
|---|---|---|---|---|
| `svelte.config.js` | Removed | Kit 3.0 | `sveltekit({...})` in `vite.config.ts`; `kit.*` options become top-level plugin options | `svelte-config` |
| `files.lib` | Removed | Kit 3.0 | `#lib` subpath import in `package.json` | `svelte-config` |
| `files` option | Deprecated | Kit 3.0 | Monorepo / standard layout | — |
| `alias` option | Deprecated | Kit 3.0 | `package.json` `imports` (subpath imports) | — |
| `typescript.config` | Deprecated | Kit 3.0 | Edit `tsconfig.json` directly | — |
| `vitePlugin` | Removed | Kit 3.0 | Pass vite-plugin-svelte options directly to `sveltekit({...})` | `svelte-config` |
| `preloadStrategy` | Removed | Kit 3.0 | Nothing — always `modulepreload` | `svelte-config` |
| `prerender.origin` | Removed | Kit 3.0 | `paths.origin` | `svelte-config` |
| `csrf.checkOrigin` | Removed | Kit 3.0 | `csrf.trustedOrigins` (CSRF is always on) | `svelte-config` |
| `experimental.tracing` | Removed | Kit 3.0 | Top-level `tracing: { server: true }` | `svelte-config` |
| `experimental.instrumentation` | Removed | Kit 3.0 | `src/instrumentation.server.ts` is picked up automatically | `svelte-config` |
| `experimental.handleRenderingErrors` | Removed | Kit 3.0 | Nothing — always on; each `+error.svelte` is a boundary | `svelte-config` |
| `tsconfig.json` extending `./.svelte-kit/tsconfig.json` | Removed | Kit 3.0 | `"extends": "$app/tsconfig"` with explicit `include` / `exclude` | `tsconfig` |

## 3. SvelteKit 3 — modules and imports

| Old | Status | Since | Use instead | Codemod |
|---|---|---|---|---|
| `$lib/foo` | Removed | Kit 3.0 | `#lib/foo.js` — file extension required | `svelte-config` |
| `$app/stores` (`$page`, `$navigating`, `$updated`) | Deprecated 2.12 → Removed | Kit 3.0 | `$app/state` (`page`, `navigating`, `updated` — no `$`) | `app-state` |
| `$app/environment` | Deprecated (removed in Kit 4) | Kit 3.0 | `$app/env` (`browser`, `building`, `dev`, `version`) | `environment` |
| `$env/static/private`, `$env/static/public`, `$env/dynamic/private`, `$env/dynamic/public` | Deprecated (removed in Kit 4) | Kit 3.0 | Declare in `src/env.ts` with `defineEnvVars`; import from `$app/env/private` / `$app/env/public` | `environment` |
| `$service-worker` | Removed | Kit 3.0 | `version` from `$app/env`; `assets`, `immutable`, `prerendered` from `$app/manifest`; paths from `$app/paths`; types from `$app/service-worker` | — |
| `base`, `assets` from `$app/paths` | Deprecated 2.26 → Removed | Kit 3.0 | `resolve('path')` / `asset('file.png')` — no leading `/` (route IDs keep it: `resolve('/blog/[slug]', { slug })`) | `paths` |
| `resolveRoute` | Deprecated 2.26 → Removed | Kit 3.0 | `resolve()` | `paths` |
| `json()` / `text()` from `@sveltejs/kit` | Deprecated | Kit 3.0 | `Response.json(data)` / `new Response(text)` | — |
| `@sveltejs/kit/node/polyfills` | Removed | Kit 3.0 | Nothing — Node 22.17+ has the globals | — |
| `getRequest` / `setResponse` awaited | Changed | Kit 3.0 | Both are synchronous now; drop `await` | — |

### Types that moved (Kit 3.0)

| Type | Import from |
|---|---|
| `Handle`, `HandleFetch`, `HandleServerError`, `Reroute`, `Transport` … and `sequence` | `@sveltejs/kit/hooks` |
| `defineEnvVars`, `EnvVarConfig` | `@sveltejs/kit/env` |
| `defineParams` | `@sveltejs/kit/params` |
| `RemoteQuery`, `RemoteForm`, `RemoteCommand` | `$app/server` |
| `Page`, `ReadonlyURL`, `ReadonlyURLSearchParams` | `$app/state` |
| `BeforeNavigate`, `OnNavigate`, `AfterNavigate`, `Navigation*`, `GotoOptions` | `$app/navigation` |
| `ActionResult`, `SubmitFunction` | `$app/forms` |
| `Pathname` → renamed `Path`; `Asset` → renamed `AssetPath` | `$app/types` |

## 4. SvelteKit 3 — navigation

| Old | Status | Since | Use instead | Codemod |
|---|---|---|---|---|
| `invalidateAll()` | Deprecated | Kit 3.0 | `refreshAll()` (keeps `page.state`) | — |
| `pushState(url, state)` | Deprecated | Kit 3.0 | `goto(url, { shallow: true, state })` | `shallow-routing` |
| `replaceState(url, state)` | Deprecated | Kit 3.0 | `goto(url, { shallow: true, replace: true, state })` | `shallow-routing` |
| `goto` option `invalidateAll` | Deprecated | Kit 3.0 | `refreshAll` | — |
| `goto` options `keepFocus` / `noScroll` | Deprecated | Kit 3.0 | `reset: false` | — |
| `goto` option `replaceState` | Deprecated | Kit 3.0 | `replace` | — |
| `data-sveltekit-keepfocus` / `data-sveltekit-noscroll` | Replaced | Kit 3.0 | `data-sveltekit-reset="false"` | — |
| `data-sveltekit-*="off"` | Removed | Kit 3.0 | `"false"` | — |
| `export const snapshot = { capture, restore }` | Deprecated | Kit 3.0 | `snapshot({ capture, restore })` from `$app/navigation`, called during component init | — |

## 5. SvelteKit 3 — errors, redirects and hooks

| Old | Status | Since | Use instead | Codemod |
|---|---|---|---|---|
| `throw error(...)` / `throw redirect(...)` | Removed (Kit 1 syntax) | Kit 2.0 | `error(...)` / `redirect(...)` — they throw themselves | `sv migrate sveltekit-2` |
| `error(404, { message, ...extra })` | Deprecated | Kit 3.0 | `error(404, 'Not found', { ...extra })` — message is always a string | — |
| `redirect(303, 'https://other.site')` | Removed for external URLs | Kit 3.0 | `redirect(303, url, { external: true })` (or allow-list) | `external-redirects` |
| `handleValidationError` hook | Removed | Kit 3.0 | `handleError` — validation errors arrive with `kind: 'validation'` | — |
| `handleError` only seeing unexpected errors | Changed | Kit 3.0 | It now receives every error with `kind: 'app' \| 'framework' \| 'validation' \| 'unknown'` and may return `status` | — |

## 6. SvelteKit 3 — routing files

| Old | Status | Since | Use instead | Codemod |
|---|---|---|---|---|
| `src/params/<name>.ts` exporting `match()` → boolean | Removed | Kit 3.0 | One `src/params.ts` with `defineParams({ name: (p) => parsed \| undefined })` | `params` |
| Server-only = only `$lib/server/*` and `*.server.ts` | Widened | Kit 3.0 | Also any file with a `server` name segment and any `server/` directory (except `src/routes`, `static`) | — |
| Any file with a `remote` name segment while remote functions are off | Error | Kit 3.0 | Rename it, or enable `experimental.remoteFunctions` | — |

## 7. Adapters

| Old | Status | Since | Use instead |
|---|---|---|---|
| adapter-vercel `runtime: 'edge'` | Removed | adapter-vercel 7 (Kit 3) | A Node or Bun runtime (`nodejs24.x`, see `svelte-build-deploy/references/adapters.md`) |
| adapter-cloudflare `event.platform.env` / `.ctx` / `.cf` / `.caches` | Removed | adapter-cloudflare 8 (Kit 3) | `import { env, waitUntil } from 'cloudflare:workers'`; `request.cf`; global `caches`. Run `wrangler types`. |
| `@sveltejs/adapter-cloudflare-workers` (Workers Sites) | Deprecated | — | `@sveltejs/adapter-cloudflare` |
| adapter-node `ORIGIN` env var | Changed | adapter-node 6 (Kit 3) | Prefer `paths.origin` in config; the docs say `ORIGIN` is still read when `paths.origin` is unset (the changelog says removed — don't rely on it in new setups) |
| adapter-netlify `publish` read from `netlify.toml` | Changed | adapter-netlify 7 (Kit 3) | `publish` is an adapter option; needs Netlify CLI 17.31+ |

### For adapter authors (Kit 3.0)

`builder.config.kit` removed; `builder.createEntries` removed; `builder.generateManifest` → `builder.generateServerInstance` + `builder.manifest`; `builder.mkdirp` / `builder.rimraf` deprecated.

## Unconfirmed

These conflict in the official sources. Follow the safer reading shown:

- `error(status, {...})`: the changelog says *deprecated*; the migration guide says the message *must* be a string. Treat it as unusable in new code.
- adapter-node `ORIGIN`: see the adapters table above.
- Whether `data-sveltekit-keepfocus` / `data-sveltekit-noscroll` still work as aliases on Kit 3. Use `data-sveltekit-reset`.
