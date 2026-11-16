---
name: svelte-build-deploy
description: >
  Pre-loaded SvelteKit 3 knowledge for the developer-svelte agent. Covers
  project structure, vite.config configuration, file-based routing (+page,
  +layout, +server, +error), param matchers, load functions (universal vs
  server), form actions, page options (prerender / ssr / csr), environment
  variables, building for production, and deployment via adapters (auto,
  node, static, vercel, cloudflare, netlify, bun). Load this skill before
  working on any SvelteKit route, server module, or build configuration.
  Trigger phrases include "sveltekit routing", "+page", "+server", "load
  function", "form actions", "sveltekit adapter", "svelte deploy".
version: 2.0.0
---

# SvelteKit — Build & Deploy

Authoritative reference for working in SvelteKit projects: project layout, routing, data loading, mutations, and getting an app to production.

## Supported Versions

This guidance targets **SvelteKit 3.2** and **Svelte 5.57** (latest stable). SvelteKit 3 requires Node 22.17+, TypeScript 6+, Svelte 5.57.1+, Vite 8.0.12+ and `@sveltejs/vite-plugin-svelte` 7+.

**Always check `package.json` first.** If the project is on SvelteKit 2 (or older Svelte), follow the project's installed version and its existing patterns — see [Working in a SvelteKit 2 project](#working-in-a-sveltekit-2-project). Do not migrate a project to Kit 3 unless the task asks for it; the official migration is `npx sv migrate sveltekit-3`.

**Experimental features** (only use them if the project already enables the flag, or the task asks for it):

| Feature | Flag |
|---------|------|
| Remote functions (`*.remote.ts`) | `experimental.remoteFunctions` **plus** `compilerOptions.experimental.async` |
| `await` in components, async SSR | `compilerOptions.experimental.async` |
| Forked preloading | `experimental.forkPreloads` |

## Project Structure

```
my-app/
├─ src/
│  ├─ lib/                       # imported as #lib (package.json "imports")
│  │  └─ server/                 # server-only code
│  ├─ routes/                    # filesystem routes (root)
│  ├─ service-worker/            # optional; has its own tsconfig.json
│  ├─ app.html                   # HTML shell
│  ├─ error.html                 # static fallback error page
│  ├─ env.ts                     # defineEnvVars — declared env vars
│  ├─ params.ts                  # defineParams — all param matchers
│  ├─ hooks.server.ts            # server hooks
│  ├─ hooks.client.ts            # client hooks
│  ├─ hooks.ts                   # universal hooks (reroute, transport)
│  └─ instrumentation.server.ts  # optional; loaded automatically
├─ static/                       # served verbatim at /
├─ tests/
├─ vite.config.ts                # ALL Kit config — no svelte.config.js
├─ tsconfig.json                 # extends "$app/tsconfig"
└─ package.json                  # "type": "module", "imports": { "#lib": ... }
```

Only `src/routes` and `src/app.html` are required. Create a project with `npx sv create my-app`.

### Configuration (`vite.config.ts`)

SvelteKit 3 does **not** read `svelte.config.js`. All config goes into the `sveltekit()` Vite plugin. The old `kit.*` options are top-level plugin options, next to `compilerOptions`:

```ts
// vite.config.ts
import { defineConfig } from 'vite';
import { sveltekit } from '@sveltejs/kit/vite';
import adapter from '@sveltejs/adapter-node';

export default defineConfig({
  plugins: [
    sveltekit({
      adapter: adapter(),
      paths: { base: '', origin: 'https://example.com' },
      csrf: { trustedOrigins: ['https://trusted-site.com'] }
      // experimental — only if already enabled or the task asks:
      // compilerOptions: { experimental: { async: true } },
      // experimental: { remoteFunctions: true }
    })
  ]
});
```

Removed options: `files.lib`, `vitePlugin`, `preloadStrategy`, `prerender.origin` (use `paths.origin`), `csrf.checkOrigin` (use `csrf.trustedOrigins`), `experimental.tracing` (now top-level `tracing: { server: true }`), `experimental.instrumentation` and `experimental.handleRenderingErrors` (both always on now). The `files` and `alias` options are deprecated.

### Imports and module boundaries

- **`#lib`** replaces `$lib`. It is a Node subpath import declared in `package.json`, and imports need an explicit file extension:

  ```json
  { "imports": { "#lib": "./src/lib/index.js", "#lib/*": "./src/lib/*" } }
  ```
  ```ts
  import { formatDate } from '#lib/utils/date.js';
  ```
- **Server-only modules:** any file with a `server` segment in its name (`server.ts`, `db.server.ts`) and any file inside a `server/` directory anywhere (except `src/routes` and `static`). `$app/env/private` and `$app/server` are server-only too. Importing these from client code is a build error.
- **`$app/*` runtime modules:** `$app/state`, `$app/navigation`, `$app/forms`, `$app/paths`, `$app/env` (`browser`, `building`, `dev`, `version`), `$app/env/private`, `$app/env/public`, `$app/server`, `$app/manifest`, `$app/types`, `$app/service-worker`.
- **`tsconfig.json`** extends `$app/tsconfig` and must declare `include` / `exclude`:

  ```json
  { "extends": "$app/tsconfig", "include": ["src", "test", "*"], "exclude": ["src/service-worker"] }
  ```

## File-based Routing

Inside `src/routes/`, each directory is a URL segment. Files prefixed with `+` are route files:

| File | Role |
|------|------|
| `+page.svelte` | Page UI |
| `+page.ts` | Universal `load` (runs server + client) |
| `+page.server.ts` | Server `load` and form `actions` |
| `+layout.svelte` | Wraps child pages; renders `{@render children()}` |
| `+layout.ts` / `+layout.server.ts` | Layout-level `load` |
| `+error.svelte` | Error page and automatic error boundary |
| `+server.ts` | API endpoint (HTTP method exports) |

Other files in `src/routes` are ignored, so colocating helpers is fine. `+` files whose names contain `test`, `spec` or `stories` (for example `+page.test.ts`) are ignored too.

Dynamic segments use brackets:
- `[slug]` — required parameter
- `[[slug]]` — optional parameter
- `[...rest]` — catch-all
- `[id=integer]` — parameter matcher, defined in `src/params.ts`
- `(group)/` — groups routes under a shared layout without affecting the URL

**Rule of thumb:**
- All files run on the server. All run on the client too, except `+server.ts`.
- `+layout` and `+error` apply to their directory and all subdirectories.

### Param matchers (`src/params.ts`)

All matchers live in one file. A matcher returns the parsed value, or `undefined` for no match. It can also be a Standard Schema (for example valibot):

```ts
// src/params.ts
import { defineParams } from '@sveltejs/kit/params';

export const params = defineParams({
  integer: (param) => (/^\d+$/.test(param) ? Number(param) : undefined),
  fruit: (param) => (param === 'apple' || param === 'orange' ? param : undefined)
});
```

With `src/routes/items/[id=integer]`, `params.id` is typed as a `number`. Matchers run on the server and in the browser.

### `+page.svelte`

```svelte
<script lang="ts">
  import type { PageProps } from './$types';
  let { data, form, params }: PageProps = $props();
</script>

<h1>{data.title}</h1>
```

`PageProps` packages `data`, `form` (when the route has actions) and the typed route `params` into one type. Use it instead of typing fields individually. `export let data` is legacy Svelte 4 syntax.

### `+layout.svelte`

```svelte
<script lang="ts">
  import type { LayoutProps } from './$types';
  let { data, children }: LayoutProps = $props();
</script>

<nav>...</nav>
{@render children()}
```

The layout MUST render `children` somewhere, or pages won't appear.

### `+error.svelte`

```svelte
<script lang="ts">
  import { page } from '$app/state';
</script>

<h1>{page.status}</h1>
<p>{page.error?.message}</p>
```

On Kit 3 the component also receives the error as an `error` prop (`let { error } = $props()`, an `App.Error` with `status` and `message`); `page.error` keeps working on Kit 2 and 3.

SvelteKit walks up the tree to find the closest `+error.svelte`. An error in a layout's `load` uses the `+error.svelte` *above* that layout. Errors in the root layout's `load` fall back to the static `src/error.html`. Each `+error.svelte` also acts as a Svelte error boundary for rendering errors. It is not used for errors inside `handle` or `+server.ts`.

### `+server.ts` (API endpoints)

```ts
import { error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = () => {
  return Response.json({ now: Date.now() });
};

export const POST: RequestHandler = async ({ request }) => {
  const body = await request.json();
  if (!body) error(400, 'Missing body');
  return Response.json({ received: body });
};

// catch-all for unhandled methods
export const fallback: RequestHandler = ({ request }) =>
  new Response(`No handler for ${request.method}`, { status: 405 });
```

- Supported exports: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`, `HEAD`, `QUERY`, and `fallback`.
- Use `Response.json(...)` and `new Response(text)`. The `json()` and `text()` helpers from `@sveltejs/kit` are deprecated.
- `+server.ts` files are NOT wrapped by `+layout` files. To run logic before every request, use `hooks.server.ts`.

## `load` Functions

Two flavors:

| File | Type | Runs on |
|------|------|---------|
| `+page.ts`, `+layout.ts` | Universal | Server (SSR + during prerender) AND client (after hydration) |
| `+page.server.ts`, `+layout.server.ts` | Server-only | Server only — return value is serialized to the client |

```ts
// +page.server.ts
import { error } from '@sveltejs/kit';
import * as db from '#lib/server/database.js';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params, locals }) => {
  if (!locals.user) error(401, 'Login required');
  const post = await db.getPost(params.slug);
  if (!post) error(404, 'Not found');
  return { post };
};
```

**When to use which:**
- **Server `load`** when you need a database, private env vars, secrets, or `cookies` / `locals` access.
- **Universal `load`** when fetching from public APIs (avoids the proxy hop), or when you must return non-serializable values (component constructors, classes).
- Both can coexist on the same route — the server load runs first; its result is the universal load's `event.data`.

**Important `load` traits:**
- Server returns must be devalue-serializable (JSON + `BigInt`, `Date`, `Map`, `Set`, `RegExp`, repeated/cyclical refs, promises). Custom types need the `transport` hook.
- Use the `fetch` from the load event instead of global `fetch`. It inherits cookies, supports relative URLs server-side, calls internal `+server.ts` handlers directly, and inlines responses into the SSR HTML to avoid double-fetches on hydration.
- Promises in the return are streamed to the browser on platforms that support streaming. Attach `.catch(() => {})` to promises you create yourself so an unhandled rejection doesn't crash the server.
- `await parent()` lets a child load read its parent layout's data — call it *after* starting independent work to avoid waterfalls.
- Auth checks belong in `hooks.server.ts` (sets `locals.user`) and per-page `+page.server.ts` guards. Layout loads don't run on every request, so don't rely on them alone for auth.
- No side effects in `load` and no shared module-level state on the server — it leaks between users.

**Re-running:** SvelteKit re-runs a load when:
- A `params` field it accessed changed
- A `url` property it accessed changed
- A `searchParams` key it accessed changed
- A parent it `await parent()`-ed re-ran
- A url it `fetch`ed or `depends()`-ed on was passed to `invalidate(...)`
- `refreshAll()` was called (`invalidateAll()` is deprecated), or the user clicked a link to the current URL

`depends('app:custom-key')` creates your own invalidation token; `invalidate('app:custom-key')` re-runs loads that depend on it. To stop tracking a read, wrap it in the `untrack` function from the load event: `load({ untrack, url }) => { if (untrack(() => url.pathname === '/')) ... }`. On re-run the component is not recreated — derive values from `data` with `$derived`.

### Errors and Redirects

```ts
import { error, redirect } from '@sveltejs/kit';

error(404, 'Not found');
error(404, 'Not found', { code: 'NOT_FOUND' });            // extra props as 3rd argument (declare `code` on App.Error)
redirect(303, '/login');
redirect(307, 'https://example.com', { external: true });  // external URLs must opt in
redirect(307, 'https://example.com/x', { external: ['https://example.com'] }); // or allowlist origins
```

- `error()` and `redirect()` throw on your behalf — don't write `throw error(...)`, and don't call them inside `try { } catch { }` (the catch swallows them).
- Passing an object as the 2nd argument (`error(404, { message })`) is deprecated.
- `App.Error` always includes `status` and `message`; extend it in `src/app.d.ts`.
- Use `isHttpError` / `isRedirect` from `@sveltejs/kit` instead of `instanceof`.
- Every error, expected or not, now goes through `handleError` (see `svelte-advanced` for hook detail).

### `getRequestEvent`

Inside server code, `import { getRequestEvent } from '$app/server'` lets shared helpers (auth guards, logging) reach the current request without passing the event around.

## Form Actions

Server-side mutations triggered by `<form>` submissions. Defined in `+page.server.ts`. Form actions are feature-complete and fully supported (new framework work goes into remote functions, which are still experimental):

```ts
// +page.server.ts
import { fail, redirect } from '@sveltejs/kit';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => ({
  user: locals.user
});

export const actions: Actions = {
  login: async ({ request, cookies }) => {
    const data = await request.formData();
    const email = String(data.get('email') ?? '');
    if (!email) return fail(400, { email, missing: true });

    cookies.set('session', await login(email)); // path defaults to '/'
    redirect(303, '/dashboard');
  },

  logout: async ({ cookies }) => {
    cookies.delete('session', { path: '/' });
    redirect(303, '/');
  }
};
```

```svelte
<!-- +page.svelte -->
<script lang="ts">
  import type { PageProps } from './$types';
  import { enhance } from '$app/forms';
  let { form }: PageProps = $props();
</script>

<form method="POST" action="?/login" use:enhance>
  <input name="email" value={form?.email ?? ''} />
  {#if form?.missing}<p>Email required</p>{/if}
  <button>Sign in</button>
</form>

<form method="POST" action="?/logout" use:enhance>
  <button>Log out</button>
</form>
```

- Use `fail(status, data)` for validation errors — keeps user input around as the `form` prop. The enhanced response uses the `fail()` status code.
- `redirect(303, ...)` after a successful POST follows PRG.
- A route has either one `default` action or named actions (`action="?/name"`), not both.
- `use:enhance` upgrades to fetch+JS but degrades gracefully without it. A form that posts to an action on **another page** now navigates to that page; pass `update({ navigate: false })` in the enhance callback to stay on the current page.
- `update()` options: `reset`, `refreshAll`, `navigate` (`invalidateAll` is a deprecated alias).
- `ActionResult` and `SubmitFunction` types are imported from `$app/forms`.
- `handle` runs before the action but not again before the follow-up `load` — update `event.locals` when an action changes auth cookies.

For type-safe RPC-style mutations, see remote functions in `svelte-advanced` (experimental).

## Page Options

Exported from `+page.ts`, `+page.server.ts`, `+layout.ts`, or `+layout.server.ts`:

```ts
export const prerender = true;       // true | false | 'auto'
export const ssr = false;             // disable server rendering (SPA)
export const csr = false;             // disable client hydration (no JS)
export const trailingSlash = 'never'; // 'never' (default) | 'always' | 'ignore'
export const config = { /* adapter-specific */ };

import type { EntryGenerator } from './$types';
export const entries: EntryGenerator = () => [{ slug: 'hello-world' }];
```

- `prerender = true` requires the page's data to be deterministic at build time. For dynamic routes, export `entries()` listing the params to prerender. Pages with form actions can't be prerendered. `url.searchParams` is not available while prerendering.
- `prerender = 'auto'` prerenders the route but keeps it in the SSR manifest too.
- `ssr = false` in the root layout produces a SPA.
- `csr = false` ships zero JS for that page — no `use:enhance`, full-page navigation.
- Options in a layout are defaults for its children. If both universal and server files export `config`, the universal one wins.

## Hooks

Three files in `src/`:

- `hooks.server.ts` — `handle`, `handleFetch`, `handleError`, `init`
- `hooks.client.ts` — `handleError`, `init`
- `hooks.ts` — universal `reroute` and `transport`

Hook types (`Handle`, `HandleFetch`, `HandleServerError`, `HandleClientError`, `ServerInit`, `Reroute`, `Transport`) and `sequence` come from `@sveltejs/kit/hooks`:

```ts
// hooks.server.ts
import type { Handle } from '@sveltejs/kit/hooks';

export const handle: Handle = async ({ event, resolve }) => {
  const session = event.cookies.get('session');
  event.locals.user = session ? await getUser(session) : null;

  const response = await resolve(event);
  response.headers.set('x-frame-options', 'DENY');
  return response;
};
```

- Compose multiple handles with `sequence(a, b)`.
- `handleValidationError` was removed; validation errors reach `handleError` with `kind: 'validation'`.
- `src/instrumentation.server.ts` loads automatically (when the adapter supports it). Enable OpenTelemetry tracing with `sveltekit({ tracing: { server: true } })`.

Full hook detail (`handleError` kinds, `handleFetch`, `transport`) is in `svelte-advanced`.

## Environment Variables

Declare every variable in `src/env.ts` with `defineEnvVars`, then import it from `$app/env/private` (server-only) or `$app/env/public`:

```ts
// src/env.ts
import { defineEnvVars } from '@sveltejs/kit/env';
import { building } from '$app/env';
import * as v from 'valibot';

export const variables = defineEnvVars({
  DATABASE_URL: { schema: building ? v.optional(v.string()) : v.string() }, // private, dynamic
  PUBLIC_API_URL: { public: true },                                         // public, dynamic
  ANALYTICS_ID: { public: true, static: true },                             // inlined at build
  PORT: { schema: (value) => (value === undefined ? 3000 : Number(value)) }
});
```

```ts
import { DATABASE_URL } from '$app/env/private';
import { PUBLIC_API_URL } from '$app/env/public';
```

- Variables are **private and dynamic by default**. `public: true` exposes one to the client; `static: true` inlines it at build time (enables dead-code elimination).
- `schema` takes a Standard Schema or a plain function. An invalid value stops the app from starting or building.
- `.env` / `.env.local` are loaded in dev and build. adapter-node does not load `.env` in production — run `node --env-file=.env build`.
- Public variables can be used in `app.html` as `%sveltekit.env.NAME%`.
- The `$env/static/*` and `$env/dynamic/*` modules are **deprecated** in Kit 3 (removed in Kit 4). Use them only in projects that still rely on them. The `svelte-env-vars-check` skill audits env var usage.

## Building for Production

```bash
npm run build       # → vite build
npm run preview     # → vite preview (runs in Node, no adapter platform)
```

`vite build` builds the server, client and service worker, prerenders pages, then the **adapter** writes the deployment artifact. Source maps are generated by default. Guard build-time side effects:

```ts
import { building } from '$app/env';
if (!building) await initialiseDatabase();
```

## Adapters

Configured in `vite.config.ts` through the `adapter` option of `sveltekit({...})` (see [Configuration](#configuration-viteconfigts)). Add one with `npx sv add sveltekit-adapter="adapter:node"`. All first-party adapters below require SvelteKit 3.

| Adapter | Latest | Use when |
|---------|--------|----------|
| `@sveltejs/adapter-auto` | 8.x | Default from `sv create`. Detects Vercel, Netlify, Cloudflare, Azure SWA, AWS via SST, Google Cloud Run and Render. Takes no options. Fine for prototyping; pin a specific adapter for production. |
| `@sveltejs/adapter-node` | 6.x | Self-hosted Node.js server (Docker, VPS). Outputs `build/`, run with `node build`. Set `paths.origin` in config (takes precedence over the `ORIGIN` env var). |
| `@sveltejs/adapter-bun` | 1.x | Self-hosted Bun server (Bun 1.4+). Build with `bun run --bun build`, run `bun ./build`. |
| `@sveltejs/adapter-static` | 4.x | Pure static site (SSG). Every route must be prerenderable; set `fallback` (e.g. `'200.html'`) plus `ssr = false` for SPA mode. |
| `@sveltejs/adapter-vercel` | 7.x | Vercel — Node or Bun runtimes, ISR, image optimization, skew protection. The `edge` runtime is no longer supported. |
| `@sveltejs/adapter-cloudflare` | 8.x | Cloudflare Workers (Static Assets) / Pages. Bindings come from `import { env, waitUntil } from 'cloudflare:workers'` — `event.platform.env` is gone. Run `wrangler types` for binding types. |
| `@sveltejs/adapter-netlify` | 7.x | Netlify — functions and edge functions. Publish directory is the adapter's `publish` option. |

On serverless / edge platforms, use `read()` from `$app/server` instead of `fs` to read imported assets.

Per-adapter setup (`adapter-node`'s env vars, `adapter-static`'s SPA fallback, and the Cloudflare / Vercel / Netlify platform bindings) is in `references/adapters.md` — load it once the table above has picked one.

## `app.html`, Links and Paths

Edit `src/app.html` to customize the HTML shell:

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    %sveltekit.head%
  </head>
  <body data-sveltekit-preload-data="hover">
    <div style="display: contents">%sveltekit.body%</div>
  </body>
</html>
```

Other placeholders: `%sveltekit.assets%`, `%sveltekit.nonce%`, `%sveltekit.version%`, `%sveltekit.env.NAME%` (public vars only).

Link options go on `<a>` or any ancestor: `data-sveltekit-preload-data` (`hover` | `tap`), `data-sveltekit-preload-code` (`eager` | `viewport` | `hover` | `tap`), `data-sveltekit-reload`, `data-sveltekit-replacestate`, `data-sveltekit-reset="false"` (keep scroll and focus). Disable an option with `"false"` — `"off"` was removed.

Build app-internal URLs with `$app/paths` so `paths.base` is respected. Paths take **no leading slash**; route IDs do:

```ts
import { asset, resolve } from '$app/paths';
asset('logo.png');
resolve('blog/hello-world');
resolve('/blog/[slug]', { slug: 'hello-world' });
```

`base`, `assets` and `resolveRoute` exports were removed from `$app/paths`.

## Working in a SvelteKit 2 project

When `package.json` shows `@sveltejs/kit` 2.x, keep using the project's existing patterns (`svelte.config.js`, `$lib`, `$env/*`, `src/params/*.ts`). Every Kit 2 → Kit 3 difference, with the version it changed in and its replacement, is in `guild:svelte-best-practices` → [`references/deprecations.md`](../svelte-best-practices/references/deprecations.md). Read it to see which Kit 3 patterns do not apply yet, and which APIs were already deprecated in late 2.x.

Even in Kit 2, prefer `$app/state` over `$app/stores`, `PageProps` / `LayoutProps` (2.16+), and calling `error()` / `redirect()` without `throw`.

## Common Mistakes

1. **Adding a `svelte.config.js` in a Kit 3 project** → it is ignored. Config goes in `sveltekit({...})` in `vite.config.ts`.
2. **Using `$lib` in a Kit 3 project, or omitting the extension** → use `#lib/foo.js`.
3. **Importing a server-only module (`*.server.ts`, anything in a `server/` dir) from client code** → build error. Move shared helpers out.
4. **Calling `redirect()` / `error()` inside a `try`/`catch`** → the catch swallows them.
5. **`throw error(...)` (SvelteKit 1 syntax)** → just `error(...)` — it throws itself.
6. **External `redirect()` without `{ external: true }`** → rejected in Kit 3.
7. **Using global `fetch` in a load** → use the `fetch` from the load event for cookie-forwarding and SSR caching.
8. **Mixing prerender and dynamic data** → if `prerender = true`, the route's load must be deterministic at build time; dynamic routes also need `entries()`.
9. **Calling `refreshAll()` constantly** → it re-runs *every* load. Prefer `invalidate(url)` or `depends()` tokens.
10. **Auth checks in layout loads only** → layouts don't always rerun. Pair with hooks or per-page guards.
11. **Reading Cloudflare bindings from `event.platform.env` in Kit 3** → import `env` from `cloudflare:workers`.
12. **Importing `$app/stores` (`$page`) in a Kit 3 project** → the module is removed. Use `page` from `$app/state`.
13. **Enabling experimental flags on your own** → only use `experimental.remoteFunctions`, `compilerOptions.experimental.async` or `experimental.forkPreloads` if the project already enables them or the task asks.
