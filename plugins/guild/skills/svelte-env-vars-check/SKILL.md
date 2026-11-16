---
name: svelte-env-vars-check
description: >
  This skill should be used when the user says "check svelte env vars",
  "check environment variables", "validate env vars", "check env var patterns",
  "audit environment variables", "audit env vars", "check SvelteKit env",
  "svelte env check", "check src/env.ts", "migrate $env to $app/env", or any
  phrase asking to audit or validate SvelteKit environment variable usage
  patterns (SvelteKit 3 `src/env.ts` + `$app/env/*`, or SvelteKit 2 `$env/*`).
version: 2.0.0
user-invocable: true
---

# SvelteKit Env Vars Check

Audit SvelteKit environment variable usage for public/private compliance,
deprecated modules and `process.env` violations, then optionally migrate to the
correct pattern for the project's SvelteKit version.

## Supported Versions

This skill targets **SvelteKit 3.2** (with Svelte 5.57) and still supports
**SvelteKit 2** projects.

**Step 0 — always do this first.** Read `package.json` and note the installed
`@sveltejs/kit` major version. Use it to choose the rule set below:

- **Kit 3 or newer** → use the [Kit 3 rules](#sveltekit-3-rules). The `$env/*`
  modules are deprecated in Kit 3 and will be removed in Kit 4.
- **Kit 2** → use the [Kit 2 rules](#sveltekit-2-rules). Do not push the Kit 3
  API onto a Kit 2 project. Explicit env vars (`defineEnvVars`) were only an
  experimental option in Kit 2.62+ (behind the `explicitEnvironmentVariables`
  experimental flag; before 2.70 `defineEnvVars` was imported from
  `@sveltejs/kit/hooks`, from 2.70 on from `@sveltejs/kit/env`). Suggest them only
  if the project already uses them or the user asks. If a Kit 2 project has that
  flag on and a `src/env.ts`, audit it with the Kit 3 rules for those variables.

If the project already follows a consistent pattern, match it and flag only real
violations.

Deprecated, removed and legacy APIs, with their replacements, are listed in `guild:svelte-best-practices` → [`references/deprecations.md`](../svelte-best-practices/references/deprecations.md).

---

## SvelteKit 3 Rules

Every variable is declared once in `src/env.ts` (or `src/env.js`) with
`defineEnvVars`, then imported from `$app/env/private` or `$app/env/public`.

```ts
// src/env.ts
import { defineEnvVars } from '@sveltejs/kit/env';

export const variables = defineEnvVars({
	API_KEY: {},                                  // private + dynamic (the default)
	GOOGLE_ANALYTICS_ID: { public: true },        // usable in browser code
	SHOW_DEBUG_OVERLAY: { public: true, static: true }, // inlined at build time
	CACHE_TTL_SECONDS: { description: 'How long to cache responses, in seconds' }
});
```

```ts
import { API_KEY } from '$app/env/private';         // server-only module
import { GOOGLE_ANALYTICS_ID } from '$app/env/public';
```

| Setting | Meaning |
|---------|---------|
| `public: true` | Can be imported from `$app/env/public` and used in browser code. Default is `false` (private). |
| `static: true` | Inlined into the build (allows dead-code elimination). Default is dynamic (read at runtime). |
| `schema` | A Standard Schema validator (Zod, Valibot, ...) or a function that returns the value or throws. An invalid value stops the app from starting or building. |
| `description` | Shown on hover in the editor. |

Notes:
- Public status comes from `public: true`, **not** from a `PUBLIC_` name prefix. Do not rename vars to add `PUBLIC_` on Kit 3.
- A variable must be declared in `src/env.ts` to be importable from `$app/env/*`.
- Public vars can also be used in `src/app.html` as `%sveltekit.env.NAME%`.
- `$app/environment` is renamed to `$app/env` (`browser`, `building`, `dev`, `version`). The old name is a deprecated alias.
- `.env` and `.env.local` are loaded in dev and at build time. `adapter-node` does not load `.env` in production — run `node --env-file=.env build`.

| Pattern | Module | Who can use it |
|---------|--------|----------------|
| Declared with `public: true` | `$app/env/public` | Client and server |
| Declared without `public` | `$app/env/private` | Server only |
| `$env/static/*`, `$env/dynamic/*` | — | **Deprecated** aliases of `$app/env/*` (still work, removed in Kit 4) — migrate to `$app/env/*` |
| `process.env.*` | — | **Never** in app code under `src/` |

## SvelteKit 2 Rules

| Pattern | Module | Who can use it |
|---------|--------|----------------|
| `PUBLIC_*` vars | `$env/static/public` or `$env/dynamic/public` | Client and server |
| Non-public vars | `$env/static/private` or `$env/dynamic/private` | Server only |
| `process.env.*` | — | **Never** in app code under `src/` |

## Violations

1. **Client-side using PRIVATE** — a client file imports a private module (`$app/env/private`, `$env/static/private` or `$env/dynamic/private`).
2. **Server-side not using PRIVATE** — a server file reads env vars through `process.env` or a public module instead of the private module. (This skill's house rule: server code uses private vars only.)
3. **`process.env` anywhere** — any file under `src/` using `process.env.*` instead of the SvelteKit env modules.
4. **Kit 3 only — deprecated `$env/*` import** — any import from `$env/static/*` or `$env/dynamic/*`.
5. **Kit 3 only — declaration mismatch** — a var imported from `$app/env/*` (or used as `%sveltekit.env.NAME%`) that is missing from `src/env.ts`, or imported from `$app/env/public` / used in `app.html` while not declared `public: true`.

---

## Phase 1: Discover Files

### 1.1 Identify server-side files

Server-side files only run on the server:

- `src/**/+page.server.ts`, `src/**/+layout.server.ts`, `src/**/+server.ts`
- `src/hooks.server.ts`, `src/instrumentation.server.ts`
- **Kit 3:** any file whose name has a `server` segment (`x.server.ts`, `server.ts`), and any file inside a `server/` folder anywhere, except under `src/routes` and `static`
- **Kit 2:** files with a `.server.` infix (`x.server.ts`) and `src/lib/server/**/*` (only this folder is server-only). A plain `server.ts` is **not** server-only on Kit 2.

Run:
```bash
find src -type f \( -name "*.server.ts" -o -name "*.server.js" -o -name "+server.ts" -o -name "+server.js" \) | sort
# Kit 3 only: plain server.ts / server.js files are server-only too.
find src -type f \( -name "server.ts" -o -name "server.js" \) | sort
# Kit 3: any server/ folder outside src/routes. Kit 2: use src/lib/server only.
find src -type f -path '*/server/*' -not -path 'src/routes/*' | sort
```

### 1.2 Identify client-side files

Everything else under `src/` that can reach the browser:

- `src/**/*.svelte` (all components and pages)
- `src/**/+page.ts` and `src/**/+layout.ts` (universal loaders — run on client and server)
- `src/hooks.client.ts`, `src/hooks.ts`
- Shared `.ts` / `.js` modules not in the server list from 1.1

Run:
```bash
find src -type f \( -name "*.svelte" -o -name "*.ts" -o -name "*.js" \) | sort
```
Remove the server files from 1.1 to get the client list.

### 1.3 Kit 3 only: read the declarations

Read `src/env.ts` (or `src/env.js`). Record every declared var with its `public`
and `static` settings. If the file is missing, every `$app/env/*` import is a
Violation 5.

---

## Phase 2: Scan for Violations

### 2.1 `process.env` usage (any file)

```bash
grep -rn 'process\.env\.' src/ --include="*.ts" --include="*.js" --include="*.svelte"
```

Record each match: file, line, full line, and var name from `process.env.SOME_VAR`.

### 2.2 Private imports in client-side files

```bash
grep -rn '[$]app/env/private\|[$]env/static/private\|[$]env/dynamic/private' src/ --include="*.svelte" --include="*.ts" --include="*.js"
```

Any match in a client file from 1.2 is a Violation 1.

### 2.3 Public imports or `process.env` in server-side files

```bash
grep -rn '[$]app/env/public\|[$]env/static/public\|[$]env/dynamic/public\|process\.env\.' src/ --include="*.ts" --include="*.js"
```

Any match in a server file from 1.1 is a Violation 2.

### 2.4 Kit 3 only: deprecated `$env/*` imports

```bash
grep -rn '[$]env/\(static\|dynamic\)/' src/ --include="*.svelte" --include="*.ts" --include="*.js"
```

Every match is a Violation 4. Also note any `$app/environment` imports as a
deprecated alias (report them, but they are not env var violations).

### 2.5 Kit 3 only: declaration mismatches

```bash
grep -rn '[$]app/env/\(public\|private\)' src/ --include="*.svelte" --include="*.ts" --include="*.js"
grep -n '%sveltekit\.env\.' src/app.html
```

Compare each imported or `%sveltekit.env.NAME%` var with the declarations from 1.3.
A missing declaration, or a public use of a var without `public: true`, is a Violation 5.

### 2.6 Collect all env var names

From all matches above, extract the var names:
- `process.env.SOME_VAR` → `SOME_VAR`
- `import { SOME_VAR } from '$env/...'` or `'$app/env/...'` → `SOME_VAR`
- `%sveltekit.env.SOME_VAR%` → `SOME_VAR`
- Kit 3: every key in `src/env.ts`

---

## Phase 3: Build and Display the Violations Report

Show the detected SvelteKit version at the top. Show Violations 4 and 5 only on Kit 3.

```
SvelteKit Env Vars Audit Report
================================
SvelteKit version: 3.x (rules: Kit 3)

Violation 1 — Client-side using PRIVATE
---------------------------------------
  src/routes/dashboard/+page.svelte:12
    import { SECRET_KEY } from '$app/env/private'

  Total: N violation(s)

Violation 2 — Server-side not using PRIVATE
-------------------------------------------
  src/routes/api/+server.ts:8
    const key = process.env.API_KEY

  Total: N violation(s)

Violation 3 — process.env usage
-------------------------------
  src/lib/utils.ts:22
    if (process.env.NODE_ENV === 'production')

  Total: N violation(s)

Violation 4 — Deprecated $env/* import (Kit 3)
----------------------------------------------
  src/lib/server/db.ts:1
    import { DB_URL } from '$env/static/private'

  Total: N violation(s)

Violation 5 — Not declared in src/env.ts (Kit 3)
------------------------------------------------
  src/routes/+layout.svelte:3
    import { APP_NAME } from '$app/env/public'   (missing `public: true`)

  Total: N violation(s)

Summary
-------
  Client PRIVATE violations:     N
  Server non-PRIVATE violations: N
  process.env violations:        N
  Deprecated $env/* imports:     N
  Declaration mismatches:        N
  Total violations:              N
```

If a category is empty, show `(none found)`.

If there are zero violations in total:
```
No violations found. All env var usage follows the SvelteKit <version> patterns.
```
Stop here — do not ask about migration.

---

## Phase 4: Ask About Migration

After the report, ask:

```
Would you like to migrate these violations to the correct SvelteKit env var patterns?

Migration will (Kit 3):
  • Declare each var in src/env.ts with defineEnvVars (public / static as needed)
  • Replace process.env.VAR and $env/* imports → import from $app/env/private or $app/env/public
  • Flag private imports in client files for manual review

Migration will (Kit 2):
  • Replace process.env.VAR in client files → import PUBLIC_VAR from $env/static/public (or dynamic)
  • Replace process.env.VAR in server files → import VAR from $env/static/private (or dynamic)
  • Flag private imports in client files for manual review
  • List .env variable names that need a PUBLIC_ prefix

Migrations that cannot be automated safely are flagged for manual review instead.

Proceed with migration? (yes / no)
```

If **no**: skip to Phase 6.

On Kit 3 with many `$env/*` imports, also mention that the official
`npx sv migrate sveltekit-3` has an `environment` task (run with
`--tasks environment`) as an alternative. Do not run it without the user's consent.

### 4.1 Ask About Timing

If **yes**, ask:

```
Should env vars be compile-time (static) or runtime (dynamic)?

  [1] static  — Values are inlined at build time. Allows dead-code elimination,
                but the app must be rebuilt to pick up changes.
  [2] dynamic — Values are read at runtime. Changes apply without a rebuild.
  [3] mixed   — I will specify per-variable.

Choice (1 / 2 / 3):
```

How the choice is applied:

| Kit | Static | Dynamic |
|-----|--------|---------|
| 3 | add `static: true` to the var in `src/env.ts` | leave `static` out (the default) |
| 2 | `$env/static/public` / `$env/static/private` | `$env/dynamic/public` / `$env/dynamic/private` |

**If 3 (mixed):** before migrating each distinct var, ask `VAR_NAME — static or dynamic? (s / d)`
and apply that choice everywhere the var is used.

---

## Phase 5: Perform Migration

Work file by file. Read each file before editing it.

### 5.1 Kit 3: declare vars in `src/env.ts`

1. Create `src/env.ts` if it does not exist (use `.js` if the project has no TypeScript), with the `defineEnvVars` skeleton shown above.
2. For each var being migrated, add an entry if missing:
   - `public: true` if it is used in client code or `app.html`; otherwise leave it private.
   - `static: true` if the timing choice is static.
3. Keep existing entries. Do not add a `schema` unless the user asks — flag vars that would benefit from one (ports, URLs, booleans) in the final report.

### 5.2 Kit 3: replace imports and `process.env`

- `process.env.VAR` in a server file → `import { VAR } from '$app/env/private';`
- `import { VAR } from '$env/static/private'` or `'$env/dynamic/private'` → `import { VAR } from '$app/env/private';`
- `import { VAR } from '$env/static/public'` or `'$env/dynamic/public'` (client file) → `import { VAR } from '$app/env/public';`
- `import { env } from '$env/dynamic/*'` then `env.VAR` → import `VAR` by name from `$app/env/*` and replace `env.VAR` with `VAR`.
- Keep var names as they are. A `PUBLIC_` prefix is allowed but no longer needed — renaming is optional and out of scope.
- Merge into an existing `$app/env/*` import instead of adding a duplicate.

### 5.3 Kit 2: migrate `process.env.VAR` in client-side files

1. New name: `PUBLIC_VAR` (add the `PUBLIC_` prefix if missing).
2. Add `import { PUBLIC_VAR } from '$env/<timing>/public';` (merge into an existing import from the same module).
3. Replace every `process.env.VAR` with `PUBLIC_VAR`.
4. Flag that the user must add `PUBLIC_VAR=<value>` to `.env`.

### 5.4 Kit 2: migrate `process.env.VAR` in server-side files

1. Keep the name `VAR`.
2. Add `import { VAR } from '$env/<timing>/private';` (merge into an existing import).
3. Replace every `process.env.VAR` with `VAR`.

### 5.5 Public imports in server-side files (both versions)

- **Kit 2:** replace `import { PUBLIC_VAR } from '$env/*/public'` with `import { VAR } from '$env/<timing>/private'`, rename uses to `VAR`, and flag that `VAR=<value>` must be added to `.env`. Client imports of `PUBLIC_VAR` stay as they are.
- **Kit 3:** a var is either public or private in `src/env.ts`. If the server needs a private copy, add a separate private entry (for example `VAR`) and flag the `.env` addition. If this is ambiguous, flag for manual review.

### 5.6 Private imports in client-side files (both versions)

These need architectural changes and cannot be automated safely:
```
⚠️  Cannot auto-migrate: src/routes/dashboard/+page.svelte

  This file imports private env vars but runs on the client.
  Private vars must not be exposed to the client.

  Options:
  a) Move the logic to a +page.server.ts, +server.ts or other server-only module
     and pass the result as page data.
  b) If the var is safe to expose:
     - Kit 3: set `public: true` in src/env.ts and import from $app/env/public.
     - Kit 2: rename it to PUBLIC_VAR and import from $env/static/public.

  Flagged for manual review.
```

### 5.7 `process.env.VAR` in universal files (`+page.ts`, `+layout.ts`, `hooks.ts`)

These run on client and server. Flag for manual review:
```
⚠️  Universal file (runs on client + server): src/routes/+page.ts

  process.env.VAR at line N needs manual review.
  - If VAR should be public: Kit 3 → public: true + $app/env/public; Kit 2 → PUBLIC_ prefix + $env/static/public
  - If VAR should be private: move this logic to +page.server.ts
```

### 5.8 After each file migration

State what changed:
```
✓ Migrated: src/routes/api/+server.ts
  - Replaced process.env.API_KEY → import { API_KEY } from '$app/env/private'
  - Declared API_KEY in src/env.ts (private, dynamic)
```

---

## Phase 6: Final Report Table

After the audit (and migration if performed), output a table of all env vars found:

```
Environment Variables Inventory
================================

| Name of Env Var     | Description |
|---------------------|-------------|
| GOOGLE_ANALYTICS_ID | Analytics ID — used in src/app.html. Visibility: client and server. Timing: dynamic. Declared: yes. |
| API_KEY             | Private API key — used in src/routes/api/+server.ts. Visibility: server only. Timing: dynamic. Declared: yes [migrated]. |
| DB_URL              | Database connection string — used in src/lib/server/db.ts. Visibility: server only. Timing: static. Declared: no [manual review]. |
```

**Description column should include:**
- What the var is used for (inferred from context)
- Where it appears (file path)
- Visibility: `Client and server` (Kit 3: `public: true`; Kit 2: `PUBLIC_*`) or `Server only`
- Timing: `static` or `dynamic`
- Kit 3 only: whether it is declared in `src/env.ts`

If migration was performed, mark vars:
- `[migrated]` — successfully auto-migrated
- `[manual review]` — flagged for architectural change

---

## Rules

- **Check the version first** — pick Kit 3 or Kit 2 rules from `package.json`; never mix them in one migration.
- **Never modify files without user confirmation** — always ask first (Phase 4).
- **Read each file before editing** — never blindly apply replacements.
- **Preserve existing import structure** — merge into existing import statements rather than adding duplicates.
- **Flag, don't guess** — if the correct migration for a var is ambiguous, flag it for manual review.
- **Stay in `src/`** — only scan and modify files under `src/` (on Kit 3 this includes `src/env.ts` and `src/app.html`).
- **`.env` changes are out of scope** — tell the user which `.env` entries need adding or renaming, but do not edit `.env` files.
