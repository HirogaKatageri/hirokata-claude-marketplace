# Adapter configuration detail

Per-adapter setup, once the overview table in the main skill has picked one.

## Supported versions

This file targets **SvelteKit 3.2** (needs Node 22.17+, Svelte 5.57.1+, Vite 8) and these adapter versions. Every adapter below needs `@sveltejs/kit` ^3.

| Adapter | Version |
|---|---|
| `@sveltejs/adapter-auto` | 8.0.1 |
| `@sveltejs/adapter-node` | 6.0.2 |
| `@sveltejs/adapter-bun` | 1.0.1 (new) |
| `@sveltejs/adapter-static` | 4.0.1 |
| `@sveltejs/adapter-vercel` | 7.0.3 |
| `@sveltejs/adapter-cloudflare` | 8.0.2 |
| `@sveltejs/adapter-netlify` | 7.0.1 |

Check `package.json` first. If the project is still on SvelteKit 2 (adapters on the `version-2` line, such as adapter-node 5.x or adapter-cloudflare 7.x), follow the project's existing config and the APIs of its installed adapter. Do not mix Kit 3 options into a Kit 2 project.

## Where the adapter goes

In SvelteKit 3, `svelte.config.js` is no longer supported. Pass the adapter to the `sveltekit()` plugin in `vite.config.js` / `vite.config.ts`:

```js
// vite.config.js (SvelteKit 3)
import { defineConfig } from 'vite';
import { sveltekit } from '@sveltejs/kit/vite';
import adapter from '@sveltejs/adapter-node';

export default defineConfig({
  plugins: [sveltekit({ adapter: adapter() })]
});
```

In a SvelteKit 2 project, the adapter stays in `svelte.config.js` under `kit: { adapter }`.

To add an adapter with the CLI: `npx sv add sveltekit-adapter="adapter:node"` (also `adapter:bun`, and others).

All examples below show only the `adapter(...)` call. It goes in `sveltekit({ adapter: ... })`.

## `adapter-auto`

The default from `sv create`. It detects Cloudflare, Netlify, Vercel, Azure Static Web Apps, AWS via SST, Google Cloud Run and Render (the last two use adapter-node). It takes **no options**. Pin a specific adapter for production so you can set options.

## `adapter-node`

Outputs a standalone Node server:

```js
import adapter from '@sveltejs/adapter-node';
adapter({ out: 'build', precompress: true, envPrefix: '' });
```

- Run with `node build`. `.env` is not loaded in production, so use `node --env-file=.env build` if needed.
- Devdependencies are bundled into the output (with Rolldown). Packages in `dependencies` stay external, so install them on the server.
- Common env vars: `PORT` (default 3000), `HOST` (default 0.0.0.0), `SOCKET_PATH`, `BODY_SIZE_LIMIT` (default 512K, `Infinity` disables), `SHUTDOWN_TIMEOUT` (default 30), `IDLE_TIMEOUT`, `KEEP_ALIVE_TIMEOUT`, `HEADERS_TIMEOUT`.
- Behind a reverse proxy: set `PROTOCOL_HEADER`, `HOST_HEADER`, `PORT_HEADER`, `ADDRESS_HEADER` and `XFF_DEPTH` to match the proxy.
- Public origin: prefer the `paths.origin` config option (new in Kit 3). It takes precedence over the `ORIGIN` env var.
- Static files are served only for `GET` and `HEAD` (others get 405), with content-hash ETags. `precompress` defaults to `true`.
- Graceful shutdown: `process.on('sveltekit:shutdown', async (reason) => { ... })`, where `reason` is `SIGINT`, `SIGTERM` or `IDLE`.
- Custom server: `import { handler } from './build/handler.js'` and mount it in your own server. Only the header and body env vars apply there. In Kit 3, `getRequest` / `setResponse` from `@sveltejs/kit/node` are synchronous, and `@sveltejs/kit/node/polyfills` is removed.

## `adapter-bun` (new)

Official Bun server adapter. Needs Bun 1.4 or later.

```js
import adapter from '@sveltejs/adapter-bun';
adapter({
  out: 'build',
  precompress: false,
  envPrefix: '',
  serverOptions: { idleTimeout: 30 },
  buildOptions: { compile: true } // single executable at build/server
});
```

Build with `bun run --bun build` (`--bun` overrides Vite's Node shebang), run with `bun ./build`, or `./build/server` when `compile` is set. `precompress` defaults to off and is ignored when `buildOptions.compile` is set. `event.platform.server` is the Bun server instance (for example `platform.server.pendingRequests`). Env vars mirror adapter-node (`HOST`, `PORT`, `SOCKET_PATH`, `BODY_SIZE_LIMIT`, `ORIGIN`, the proxy header vars, `XFF_DEPTH`, `SHUTDOWN_TIMEOUT`), plus `REUSE_PORT`, `IPV6_ONLY`, `CONNECTION_IDLE_TIMEOUT` and `DEVELOPMENT`.

## `adapter-static`

Pure static output:

```js
import adapter from '@sveltejs/adapter-static';
adapter({
  pages: 'build',
  assets: 'build',
  fallback: undefined, // '200.html' for SPA mode ('404.html' on GitHub Pages)
  precompress: false,
  strict: true
});
```

- Every page must be prerendered: put `export const prerender = true;` in the root `+layout.js`.
- SPA mode: set `fallback: '200.html'` and `export const ssr = false;` in the root layout.
- GitHub Pages under a sub-path: in `sveltekit({...})`, set `paths: { base: process.argv.includes('dev') ? '' : process.env.BASE_PATH }`.
- If the host does not serve `/a.html` for a request to `/a`, set `export const trailingSlash = 'always';` in the root layout so pages are written as `/a/index.html`.
- Remote function queries cannot be used when the whole site is prerendered.
- On Vercel it works with zero config (omit options).

## `adapter-vercel`

- The **`edge` runtime is removed** in adapter-vercel 7. Do not use `runtime: 'edge'`.
- Per-route options go in `export const config` (typed as `import('@sveltejs/adapter-vercel').Config`) in `+page` / `+layout` / `+server` files:

```js
/** @type {import('@sveltejs/adapter-vercel').Config} */
export const config = {
  runtime: 'nodejs24.x', // 'nodejs22.x' | 'nodejs24.x' | 'nodejs26.x' | 'bun1.x' | 'bun1.4.x'
  regions: ['iad1'],
  memory: 1024,
  maxDuration: 30,
  isr: { expiration: 60 } // also bypassToken, allowQuery
};
```

- Other options: `split`, and the adapter-level `images` option for image optimization. Skew protection is supported.
- With no `runtime` set, the adapter uses the Node version chosen in the Vercel dashboard (or Bun when you build with Bun).
- ISR has no effect on prerendered routes. `bypassToken` must be at least 32 characters.
- For `waitUntil`, use `@vercel/functions`.
- `node:fs` does not work in the functions. Use `read` from `$app/server`, or prerender the route.

## `adapter-cloudflare`

Targets Cloudflare Workers (with Static Assets) and Pages. Needs wrangler `^4.118.0`.

```js
import adapter from '@sveltejs/adapter-cloudflare';
adapter({
  config: undefined, // path to wrangler config
  platformProxy: { configPath: undefined, environment: undefined, persist: undefined },
  fallback: 'plaintext',
  routes: { include: ['/*'], exclude: ['<all>'] }
});
```

`wrangler.jsonc` for Workers:

```jsonc
{
  "name": "<any-name-you-want>",
  "main": ".svelte-kit/cloudflare/_worker.js",
  "compatibility_date": "<YYYY-MM-DD>",
  "compatibility_flags": ["nodejs_als"], // or "nodejs_compat"
  "assets": { "binding": "ASSETS", "directory": ".svelte-kit/cloudflare" }
}
```

Test the build locally with wrangler 4: `wrangler dev .svelte-kit/cloudflare/_worker.js` (Workers) or `wrangler pages dev .svelte-kit/cloudflare` (Pages).

- **Kit 3 change:** `event.platform.env`, `platform.ctx`, `platform.cf` and `platform.caches` are removed. Read bindings (KV, D1, R2) and `waitUntil` from `cloudflare:workers`, use `request.cf`, and use the global `caches`:

```ts
import { env, waitUntil } from 'cloudflare:workers';
const row = await env.DB.prepare('SELECT 1').first();
```

- Bindings are emulated in dev and preview, based on your wrangler config (tune with `platformProxy`). Generate binding types with `wrangler types`.
- For plain environment variables, prefer SvelteKit's `$app/env/*` modules over `env` from `cloudflare:workers`.
- There is no file system. Use `read` from `$app/server` instead of `fs`.
- `adapter-cloudflare-workers` (Workers Sites) is deprecated. Use `adapter-cloudflare`.
- In a SvelteKit 2 project, bindings still come from `event.platform.env`.

## `adapter-netlify`

```js
import adapter from '@sveltejs/adapter-netlify';
adapter({ edge: false, split: false, publish: 'build' });
```

- Uses the Netlify Frameworks API. Needs Netlify CLI 17.31.0 or later.
- The publish folder is now the adapter's `publish` option. It is no longer read from `netlify.toml`.
- `edge: true` deploys to Netlify Edge Functions.
- Netlify context is available as `event.platform?.context`.
