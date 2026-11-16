---
name: svelte-advanced
description: >
  Pre-loaded advanced Svelte 5 / SvelteKit 3 techniques for the developer-svelte
  agent. Covers attachments ({@attach}), actions (use:), transitions and
  animations, the motion module, custom elements, packaging libraries, server
  hooks, async Svelte, remote functions, service workers, shallow routing,
  snapshots, and view transitions. Load when the task involves animation, dom
  integration, library packaging, advanced data flow, or pwa features. Trigger
  phrases include "svelte transition", "svelte animation", "svelte attachment",
  "svelte action", "remote function", "shallow routing", "service worker",
  "custom element", "svelte await", "svelte boundary".
version: 2.0.0
---

# Svelte 5 / SvelteKit 3 — Advanced Techniques

For tasks that go beyond standard component work: animation, DOM integration, packaging, advanced server flows, and PWA features.

## Supported Versions

- This guidance targets **Svelte 5.57+** and **SvelteKit 3.2+** (Kit 3 needs Node 22.17+, TypeScript 6, Vite 8 and `@sveltejs/vite-plugin-svelte` 7).
- Always check `package.json` first. If the project uses an older version (for example SvelteKit 2), follow the APIs that version has and the patterns already in the codebase. Do not upgrade or migrate unless the task asks for it (the Kit 3 upgrade is `npx sv migrate sveltekit-3`).
- In SvelteKit 3, all config lives in `sveltekit({...})` in `vite.config.ts`. `svelte.config.js` is no longer supported. Older projects still use `svelte.config.js` with a `kit: {...}` block.
- **Experimental features** are marked below with their flag. Only use them if the project already enables the flag or the task asks for it. They are not covered by semantic versioning.

| Feature | Flag |
|---|---|
| `await` in components, `$effect.pending()`, `fork`, `hydratable` | `compilerOptions.experimental.async` (Svelte 5.36+) |
| Remote functions | `experimental.remoteFunctions` **and** `compilerOptions.experimental.async` |
| Forked link preloading | `experimental.forkPreloads` |

Deprecated, removed and legacy APIs, with their replacements, are listed in `guild:svelte-best-practices` → [`references/deprecations.md`](../svelte-best-practices/references/deprecations.md).

## Transitions

Apply enter/exit animations to elements that conditionally render.

```svelte
<script>
  import { fade, fly } from 'svelte/transition';
  import { prefersReducedMotion } from 'svelte/motion';
  let visible = $state(true);
</script>

{#if visible}
  <div transition:fade={{ duration: 300 }}>fades both in and out</div>
{/if}

{#if visible}
  <div in:fly={{ y: prefersReducedMotion.current ? 0 : 20, duration: 200 }} out:fade>independent in/out</div>
{/if}
```

Built-ins from `svelte/transition`: `fade`, `fly`, `slide`, `scale`, `blur`, `draw` (SVG path), `crossfade` (paired enter/exit between elements).

A custom transition is a function returning a config:

```ts
import { cubicOut } from 'svelte/easing';

export function spin(node: Element, { duration = 400 }) {
  return {
    duration,
    easing: cubicOut,
    css: (t: number) => `transform: rotate(${t * 360}deg); opacity: ${t}`
  };
}
```

Prefer `css` over `tick(t, u)`; use `tick` only when you need frame-by-frame JS work.

Transitions are **local** by default (they don't play when a parent block is created or destroyed). Use `transition:fade|global` to opt in.

**Accessibility:** transitions are driven by the Web Animations API, not CSS. A global `@media (prefers-reduced-motion: reduce)` rule has **no effect** on them. Read `prefersReducedMotion.current` (from `svelte/motion`) and reduce or skip the motion yourself.

Transitions and animations still use directives (`transition:`, `in:`, `out:`, `animate:`). There is no attachment-based replacement.

## Animations (`animate:`)

Smoothly reorder items inside a keyed `{#each}` block.

```svelte
<script>
  import { flip } from 'svelte/animate';
  let items = $state([...]);
</script>

{#each items as item (item.id)}
  <li animate:flip={{ duration: 300 }}>{item.text}</li>
{/each}
```

`flip` (First-Last-Invert-Play) is the standard. Required: the `(item.id)` key — otherwise Svelte can't track identity through reorders.

## Motion Module

`svelte/motion` provides the `Spring` and `Tween` classes (5.8+):

```svelte
<script lang="ts">
  import { Spring, Tween } from 'svelte/motion';

  let { value }: { value: number } = $props();

  const x = new Spring(0, { stiffness: 0.1, damping: 0.4 });
  const opacity = new Tween(1, { duration: 300 });
  const follow = Spring.of(() => value); // tracks a value; call during component init
</script>

<button onclick={() => { x.target = 200; opacity.target = 0; }}>animate</button>
<div style:transform="translateX({x.current}px)" style:opacity={opacity.current}>...</div>
```

- Set `.target` (or `await x.set(value, { instant: true })`), read `.current`.
- The old `spring()` and `tweened()` stores are **deprecated**. Use `Spring` and `Tween`.
- `prefersReducedMotion` is a `MediaQuery`; read `prefersReducedMotion.current` and respect it.

## Attachments (`{@attach}`)

The preferred way (5.29+) to run code against a DOM element. An attachment runs in an effect when the element mounts, re-runs when state it reads changes, and can return a cleanup function.

```svelte
<script lang="ts">
  import type { Attachment } from 'svelte/attachments';

  const focusOnMount: Attachment<HTMLInputElement> = (element) => {
    element.focus();
    return () => { /* cleanup if needed */ };
  };

  function tooltip(content: string): Attachment {
    return (element) => {
      const tip = createTooltip(element, content);
      return () => tip.destroy();
    };
  }
</script>

<input {@attach focusOnMount} />
<button {@attach tooltip(text)}>?</button>        <!-- factory: re-created when `text` changes -->
<input {@attach enabled && focusOnMount} />      <!-- falsy = no attachment -->
```

- An element can have any number of attachments.
- **Expensive setup:** pass a getter and read it inside a nested `$effect`, so setup does not re-run on every change:

  ```ts
  function chart(getData: () => Data): Attachment {
    return (node) => {
      const c = expensiveSetup(node);
      $effect(() => { c.update(getData()); });
      return () => c.destroy();
    };
  }
  ```

- **On components:** `{@attach ...}` on a component becomes a Symbol-keyed prop. When the wrapper spreads `{...props}` onto an element, the attachment is forwarded.
- **In props objects:** use `createAttachmentKey()` from `svelte/attachments` as the key: `{ class: 'x', [createAttachmentKey()]: (node) => {...} }`.
- Prefer `{@attach}` over `$effect` for syncing an element with an external library.

## Actions (`use:`) — legacy

Actions still work, but the docs now say to use `{@attach}` instead of `use:` for new code. Only write actions when the codebase already uses them or you are on Svelte older than 5.29.

```ts
import type { Action } from 'svelte/action';

export const tooltip: Action<HTMLElement, string> = (node, text) => {
  const tip = document.createElement('div');
  tip.textContent = text ?? '';
  return {
    update: (newText) => { tip.textContent = newText ?? ''; },
    destroy: () => { tip.remove(); }
  };
};
```

To use an existing action as an attachment, wrap it with `fromAction` (5.32+). The second argument is a **function** that returns the action's argument:

```svelte
<script>
  import { fromAction } from 'svelte/attachments';
</script>

<button {@attach fromAction(tooltip, () => text)}>?</button>
```

## Async Svelte — EXPERIMENTAL (`compilerOptions.experimental.async`)

Needs Svelte 5.36+ and the flag. Only use it if the project already enables it or the task asks for it. The details can change outside a major release; the flag goes away in Svelte 6, where async becomes the default.

```ts
// vite.config.ts (SvelteKit 3)
sveltekit({ compilerOptions: { experimental: { async: true } } })
```

With the flag, `await` is allowed at the top level of a component `<script>`, inside `$derived(...)`, and in markup:

```svelte
<script>
  import { getAbortSignal } from 'svelte';
  let { id } = $props();

  async function getData(id) {
    const res = await fetch(`/items/${id}`, { signal: getAbortSignal() });
    return res.json();
  }

  const data = $derived(await getData(id));
</script>

<p>{data.name}</p>
{#if $effect.pending()}<p>updating…</p>{/if}
```

- **Synchronized updates:** the UI does not show new state until the `await`s that depend on it resolve, so it never shows a mix of old and new.
- **Concurrency:** independent `await`s in markup run in parallel. Sequential `await`s in `<script>` run one after another; avoid waterfalls (`await_waterfall` warning).
- **Loading UI:** a `<svelte:boundary>` `pending` snippet shows only on first load. For later updates use `$effect.pending()` (number of pending promises in the current boundary).
- **Errors** in `await` go to the nearest `<svelte:boundary>`.
- `settled()` (from `svelte`) resolves once state changes and the async work they cause have finished and the DOM is updated. `tick()` only waits for pending state changes to be applied.
- `getAbortSignal()` (5.35+) aborts when the current derived or effect re-runs or is destroyed. Call it only while a derived or effect is running.
- `$state.eager(value)` (5.41+) updates the UI right away even while related `await`s are pending. Use it sparingly, for instant user feedback such as `aria-current`.
- With the flag on: `setContext` must run at init (not after an `await`), and `flushSync` cannot be called inside an effect.
- `fork(fn)` (5.42) and `hydratable(key, fn)` (5.44) are low-level APIs for frameworks and library authors (SvelteKit uses them for preloading and remote functions). Do not reach for them in normal app code.

## Custom Elements (Web Components)

Compile a Svelte component into a real custom element:

```svelte
<svelte:options customElement="my-counter" />

<script lang="ts">
  let { count = 0 }: { count?: number } = $props();
</script>

<button onclick={() => count++}>{count}</button>
```

- Requires the `customElement: true` compiler option. In SvelteKit 3 set it in `sveltekit({ compilerOptions: { customElement: true } })` in `vite.config.ts`. Since 5.54 it can be a function of the file, so only some files compile as custom elements.
- Register by importing the file, or register an untagged component with `customElements.define('my-element', MyElement.element)`.
- Use `$host()` to access the host element (for example to `dispatchEvent`).
- List props explicitly. `let props = $props()` alone cannot expose properties.
- The options object form takes `tag`, `shadow` (`"open"`, `"none"`, or a `ShadowRootInit` object such as `{ mode: 'closed' }` since 5.49), `props` (`attribute`, `reflect`, `type`), and `extend` (subclass the generated class, for example for form-associated elements).
- Caveats: styles are encapsulated (no global CSS), not suitable for SSR, slotted content renders eagerly, no context across custom elements, and do not name props starting with `on`.

## Packaging Libraries

`@sveltejs/package` (`svelte-package` command) builds a publishable package from `src/lib/` into `dist/` with `.d.ts` files:

```bash
npm run package    # runs svelte-package → dist/
```

`package.json` should expose:

```json
{
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "svelte": "./dist/index.js"
    }
  },
  "files": ["dist"],
  "sideEffects": ["**/*.css"],
  "svelte": "./dist/index.js"
}
```

- Don't bundle Svelte source when publishing — keep `.svelte` files intact so consumers' compilers can process them.
- Use package.json subpath imports (`#lib/...`) for aliases. `svelte-package` rewrites `#`-prefixed imports to relative paths.
- Avoid SvelteKit-only modules (`$app/env`, `$app/state`, `$app/navigation`) unless the library is only for SvelteKit apps. Use `esm-env` (`BROWSER`) and pass URLs or callbacks as props instead.
- Removing an `exports` path or condition is a breaking change.

## SvelteKit Hooks (Deep Dive)

Hooks live in `src/hooks.server.ts`, `src/hooks.client.ts`, and `src/hooks.ts` (universal). In SvelteKit 3, hook types and `sequence` come from **`@sveltejs/kit/hooks`** (`Handle`, `HandleFetch`, `HandleServerError`, `HandleClientError`, `ServerInit`, `Reroute`, `Transport`).

### `handle` (server)

Wraps every request. Use for auth, locals population, response headers.

```ts
import { sequence } from '@sveltejs/kit/hooks';
import type { Handle } from '@sveltejs/kit/hooks';

const auth: Handle = async ({ event, resolve }) => {
  event.locals.user = await getUserFromCookie(event.cookies);
  return resolve(event);
};

const securityHeaders: Handle = async ({ event, resolve }) => {
  const response = await resolve(event);
  response.headers.set('x-frame-options', 'DENY');
  return response;
};

export const handle = sequence(auth, securityHeaders);
```

`resolve(event, opts)` accepts:
- `transformPageChunk: ({ html }) => html.replace('%lang%', lang)` — mutate HTML chunks during streaming.
- `filterSerializedResponseHeaders: (name) => true` — control which fetch response headers get inlined into SSR HTML.
- `preload: ({ type, path }) => true` — control which assets get preloaded.

Static assets and prerendered pages do not go through `handle`. For remote function requests, `event.route`/`params`/`url` come from the client (for `form`/`command` they describe the calling page; for queries `handle` sees the remote endpoint URL) — never use them for authorization.

### `handleError` (server + client) — changed in SvelteKit 3

Now called for **every** error, including expected ones thrown with `error(...)`, with a `kind` value: `'app'` (from `error()`), `'framework'` (404/405/413), `'validation'` (server only; remote function input failed its schema, has `issues`), or `'unknown'`. Return a serializable `App.Error` (it becomes `page.error`). Must never throw. `handleValidationError` was removed — handle `kind === 'validation'` here.

```ts
import type { HandleServerError } from '@sveltejs/kit/hooks';

export const handleError: HandleServerError = async ({ kind, error, event }) => {
  if (kind === 'app') return error;            // safe, came from error(...)
  if (kind === 'framework') return error;      // safe, 404/405/413
  const errorId = crypto.randomUUID();
  reportToSentry(error, { event, errorId });
  return { message: 'Something went wrong', errorId };
};
```

Rendering errors always go through `handleError` and the nearest `<svelte:boundary>`; each `+error.svelte` acts as an automatic boundary. An async client `handleError` needs `compilerOptions.experimental.async`.

### `handleFetch` (server)

Modifies the `fetch` provided to load functions.

```ts
import type { HandleFetch } from '@sveltejs/kit/hooks';

export const handleFetch: HandleFetch = async ({ event, request, fetch }) => {
  if (request.url.startsWith('https://api.internal/')) {
    request.headers.set('cookie', event.request.headers.get('cookie') ?? '');
  }
  return fetch(request);
};
```

### `init`, `reroute`, `transport`

- `init` (server + client) — one-time async setup, e.g. `export const init: ServerInit = async () => { await db.connect(); };`
- `reroute` (universal, `src/hooks.ts`) — map a URL to a different pathname before routing. Can be async. Must be pure, because the result is cached on the client.
- `transport` (universal, `src/hooks.ts`) — custom encode/decode for types beyond devalue's defaults (e.g. `Decimal`, domain classes) so they survive the server→client trip. In Kit 3 it is also used for `page.state` and snapshots.

```ts
import type { Transport } from '@sveltejs/kit/hooks';

export const transport: Transport = {
  Vector: {
    encode: (v) => v instanceof Vector && [v.x, v.y],
    decode: ([x, y]) => new Vector(x, y)
  }
};
```

## Remote Functions — EXPERIMENTAL (`experimental.remoteFunctions`)

Type-safe server functions callable from components (SvelteKit 2.27+, still experimental in 3.2). Only use them if the project already enables them or the task asks for it. They need **both** flags:

```ts
// vite.config.ts (SvelteKit 3)
sveltekit({
  experimental: { remoteFunctions: true },
  compilerOptions: { experimental: { async: true } }
})
```

A remote module is any file with a `remote` segment in its name (`data.remote.ts`, `remote.ts`). It can live anywhere in `src` except inside a `server` folder. The remote helpers (`query`, `form`, `command`, `prerender`, `requested`, `getRequestEvent`) and their types (`RemoteQuery`, `RemoteForm`, `RemoteCommand`) come from `$app/server`; `error`, `redirect` and `invalid` still come from `@sveltejs/kit`.

```ts
// src/routes/blog/data.remote.ts
import * as v from 'valibot';
import { error, redirect } from '@sveltejs/kit';
import { query, form, command, getRequestEvent } from '$app/server';
import * as db from '#lib/server/database.js';
import { requireLogin } from '#lib/server/auth.js'; // redirects to /login if signed out

export const getPost = query(v.string(), async (slug) => {
  const post = await db.getPost(slug);
  if (!post) error(404, 'Not found');
  return post;
});

export const likePost = command(v.string(), async (slug) => {
  // commands cannot redirect, so a redirecting requireLogin() would fail here
  if (!getRequestEvent().locals.user) error(401, 'Unauthorized');
  await db.incrementLikes(slug);
});

export const createPost = form(
  v.object({ title: v.pipe(v.string(), v.nonEmpty()), content: v.string() }),
  async ({ title, content }) => {
    requireLogin();
    const slug = await db.createPost(title, content);
    redirect(303, `/blog/${slug}`);
  }
);
```

```svelte
<script lang="ts">
  import { getPost, likePost, createPost } from './data.remote';
  let { params } = $props();
  const post = $derived(await getPost(params.slug));
</script>

<h1>{post.title}</h1>
<button onclick={() => likePost(params.slug)}>Like</button>

<form {...createPost}>
  <input {...createPost.fields.title.as('text')} />
  {#each createPost.fields.title.issues() ?? [] as issue}<p>{issue.message}</p>{/each}
  <textarea {...createPost.fields.content.as('text')}></textarea>
  <button disabled={!!createPost.pending}>Publish</button>
</form>
```

The kinds:
- `query(schema, fn)` — read. Same arguments return the same cached instance; refresh with `getPost(slug).refresh()`. Without `await`, the resource has `loading`, `error`, `current`, `ready`. In Kit 3, reading `event.url`, `params` or `route` inside a query **throws** — pass what you need as arguments. Queries don't work on fully prerendered pages.
- `query.batch(schema, fn)` — batches calls made in the same macrotask (solves n+1). `fn` gets an array of args and returns `(arg, index) => result`.
- `query.live(asyncGenerator)` — streams values to the client. Has `connected`, `done`, `reconnect()`; no `refresh()`.
- `form(schema, fn)` — `<form>` mutation that works without JS. **In Kit 3, every control must use `{...form.fields.x.as(type)}`**; a hand-written `name="..."` is rejected. Use `.as('radio', value)`, `.as('checkbox', value, checked)`, `.as('submit', value)` for multiple buttons. Use `form.for(id)` for repeated forms, `form.enhance(async (f) => { await f.submit(); })` for custom submit (the form is not reset automatically), and `invalid(issue.title('message'))` (`invalid` from `@sveltejs/kit`; `issue` is the handler's second argument) for server-side validation issues. Field names starting with `_` (e.g. `_password`) are not echoed back on failure.
- `command(schema, fn)` — write, called from event handlers, **not during render**. Cannot `redirect` (use `error(401)` for auth failures, or return `{ redirect: location }` and handle it on the client). Prefer `form` where possible (progressive enhancement).
- `prerender(schema, fn, { inputs, dynamic })` — runs at build time; never for private data.

Rules:
- Validate every argument with a Standard Schema (Valibot, Zod). Use `'unchecked'` only with a clear reason.
- **Check auth inside each remote function** (a shared `requireLogin()` using `getRequestEvent().locals`). Don't rely on the calling page. A helper that calls `redirect` works in `query`/`form`/`prerender` but not in `command`.
- **Refreshing data:** a successful `form` refreshes all queries and loads by default; a `command` refreshes nothing. Inside the handler, `void getPosts().refresh()` or `getPost(id).set(value)` refreshes only those (and replaces the form's default). Client-requested updates (`await likePost(id).updates(getPosts)`, optimistic `getPosts().withOverride(fn)`) must be accepted on the server with `requested(getPosts, limit)` — `limit` is required, and every requested query must be refreshed, set, reconnected (live) or explicitly ignored (`ignore()` / `ignoreAll()`), otherwise it errors on the client.
- Arguments and results are serialized with devalue (plus your `transport` types).

## Shallow Routing

Create history entries without navigating — for modals, lightboxes and drawers that should close on the back button. In **SvelteKit 3, `pushState` and `replaceState` are deprecated**; use `goto` with `shallow: true`.

```svelte
<script lang="ts">
  import { goto, preloadData } from '$app/navigation';
  import { page } from '$app/state';
</script>

<a
  href="/photos/42"
  onclick={async (e) => {
    if (innerWidth < 640 || e.shiftKey || e.metaKey || e.ctrlKey) return; // normal navigation
    e.preventDefault();
    const result = await preloadData('/photos/42');
    if (result.type === 'loaded' && result.status === 200) {
      goto('/photos/42', { shallow: true, state: { selected: result.data } });
    } else {
      goto('/photos/42');               // fall back to a full navigation
    }
  }}
>
  View
</a>

{#if page.state.selected}
  <Modal data={page.state.selected} onclose={() => history.back()} />
{/if}
```

- `goto(url, { shallow: true, replace: true, state })` replaces the current entry.
- `persistState: true` keeps `page.state` after a reload.
- Type `page.state` via `App.PageState`. `page.shallow` gives the route that would render on reload.
- Shallow navigations now run `beforeNavigate`/`onNavigate`/`afterNavigate` with `navigation.shallow === true`; filter on it where needed.
- On SvelteKit 2 use `pushState('', state)` / `replaceState('', state)` instead.

## Snapshots

Keep ephemeral UI state (form drafts, scroll in a list) across back/forward navigation. SvelteKit 3 adds a `snapshot()` helper, called during component init; values are serialized with devalue and stored in `sessionStorage`.

```svelte
<script>
  import { snapshot } from '$app/navigation';
  let comment = $state('');
  snapshot({ capture: () => comment, restore: (value) => (comment = value) });
</script>
```

`export const snapshot = { capture, restore }` in `+page.svelte` is deprecated in Kit 3 (still the API on Kit 2).

## Service Workers

`src/service-worker/index.ts` (or `src/service-worker.js`) is bundled and registered automatically (as `type: 'module'` in Kit 3; not bundled in dev). In **SvelteKit 3 the `$service-worker` module is removed**:

```ts
import { self } from '$app/service-worker';
import { version } from '$app/env';
import { immutable, assets } from '$app/manifest';
import { resolve } from '$app/paths';

const CACHE = `cache-${version}`;
const ASSETS = [...immutable, ...assets].map((a) => resolve(a.path));

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
});

self.addEventListener('fetch', (event) => {
  // strategy of choice (cache-first, network-first, stale-while-revalidate)
});
```

- Old → new: `build` → `immutable`, `files` → `assets`, `prerendered` → `$app/manifest`, `version` → `$app/env`, `base` → `resolve()`.
- The service worker has its own `tsconfig.json` extending `$app/tsconfig/service-worker`; exclude `src/service-worker` from the root tsconfig.
- Don't cache `query.live` responses.
- Disable auto-registration with `sveltekit({ serviceWorker: { register: false } })`.
- On SvelteKit 2, keep using `$service-worker` (`build`, `files`, `version`).

## View Transitions

Use the View Transitions API for cross-page animations. `onNavigate` must be called **during component initialization**, so put it in the root `+layout.svelte`:

```svelte
<!-- src/routes/+layout.svelte -->
<script>
  import { onNavigate } from '$app/navigation';
  let { children } = $props();

  onNavigate((navigation) => {
    if (!document.startViewTransition) return;
    return new Promise((resolve) => {
      document.startViewTransition(async () => {
        resolve();
        await navigation.complete;
      });
    });
  });
</script>

{@render children()}
```

CSS `view-transition-name: ...` per element controls the morph. Keep the returned promise fast — navigation waits for it.

## `<svelte:boundary>`

Error and async boundaries inside a component (5.3+):

```svelte
<svelte:boundary onerror={(error) => report(error)}>
  <FlakyComponent />

  {#snippet failed(error, reset)}
    <p>Something broke</p>
    <button onclick={reset}>Try again</button>
  {/snippet}

  {#snippet pending()}
    <p>Loading…</p>
  {/snippet}
</svelte:boundary>
```

- `failed(error, reset)` renders on error; `reset()` re-runs the children. `onerror` is for reporting.
- Catches errors during rendering and effects — **not** in event handlers, `setTimeout`, or other async work outside rendering.
- `pending` shows while `await` expressions inside are first resolving (needs the async flag).
- Since 5.53 boundaries also work on the server when `render` is given `transformError`. In SvelteKit 3, errors reach the `failed` snippet already processed by `handleError` (typed `App.Error`).

## Special Elements

- `<svelte:window>`, `<svelte:document>`, `<svelte:body>` — add global listeners (`<svelte:window onkeydown={...} />`) instead of `addEventListener` in `onMount`/`$effect`.
- `<svelte:head>` — inject into `<head>`.
- `<svelte:element this={tag}>` — render a tag chosen at runtime.
- `<svelte:options>` — per-component compiler options (`customElement`, `runes`, `namespace`, `css`). `accessors`/`immutable` do nothing in runes mode.
- Recursive components: `import Self from './Tree.svelte'` and render `<Self />`. `<svelte:self>` is legacy.
- Dynamic components: render `<Component />` directly from a variable. `<svelte:component>` is legacy.
- For imperative listeners use `on(target, event, handler)` from `svelte/events` (returns a remove function) instead of `addEventListener`, so ordering with `onclick`-style handlers stays correct.

## Reactive Built-ins

`svelte/reactivity` exports `SvelteMap`, `SvelteSet`, `SvelteDate`, `SvelteURL`, `SvelteURLSearchParams`, `MediaQuery` and `createSubscriber`. Use the collection classes instead of the native versions when you want their mutations to be tracked:

```ts
import { SvelteMap, SvelteSet } from 'svelte/reactivity';

const selected = new SvelteSet<string>();
selected.add('foo');                         // triggers reactivity

const cache = new SvelteMap<string, Item>();
cache.getOrInsertComputed(id, (id) => load(id)); // 5.57+
```

- Values inside `SvelteMap`/`SvelteSet` are **not** deeply reactive.
- `new MediaQuery('min-width: 800px', fallback)` exposes `.current`; `fallback` is the server value. Prefer CSS media queries when they are enough (avoids hydration mismatches).
- `createSubscriber(start)` (5.7+) turns an external event source into reactive reads. The docs recommend it over `$effect` for observing things outside Svelte:

  ```ts
  import { createSubscriber } from 'svelte/reactivity';
  import { on } from 'svelte/events';

  export class OnlineStatus {
    #subscribe = createSubscriber((update) => {
      const offA = on(window, 'online', update);
      const offB = on(window, 'offline', update);
      return () => { offA(); offB(); };
    });
    get current() {
      this.#subscribe();
      return navigator.onLine;
    }
  }
  ```

`svelte/reactivity/window` (5.11+) exposes reactive window values with `.current`: `innerWidth`, `innerHeight`, `outerWidth`, `outerHeight`, `scrollX`, `scrollY`, `screenLeft`, `screenTop`, `devicePixelRatio`, `online`.
