---
name: svelte-core
description: >
  Pre-loaded Svelte 5 core knowledge for the developer-svelte agent, targeting
  Svelte 5.57+. Covers the component model, runes ($state, $derived, $effect,
  $props, $bindable), basic markup, control flow, declaration tags, snippets,
  bindings, scoped styles, lifecycle, and context. Load this skill before
  writing or editing any .svelte, .svelte.ts, or .svelte.js file. Trigger
  phrases include "svelte core", "svelte runes", "svelte 5 component",
  "svelte state", "svelte derived", "svelte effect", "svelte props",
  "svelte bind".
version: 1.1.0
---

# Svelte 5 — Core Knowledge

Authoritative reference for writing modern Svelte 5 components and reactive modules. Read this in full before touching any `.svelte` / `.svelte.ts` / `.svelte.js` file.

## Supported Versions

- This guidance targets **Svelte 5.57+** (latest stable: 5.57.3). Svelte 6 is not released; do not use or invent Svelte 6 APIs.
- SvelteKit projects should be on **SvelteKit 3.x** (3.0 requires Svelte 5.57.1 or newer).
- **Always check `package.json` first.** Features below are tagged with the Svelte version that added them (for example "5.56+"). If the installed version is older, do not use that feature. Follow the patterns already in the codebase instead.
- **Experimental features** are marked with their flag name. Only use them if the project already enables the flag, or the task explicitly asks for it.

Deprecated, removed and legacy APIs, with their replacements, are listed in `guild:svelte-best-practices` → [`references/deprecations.md`](../svelte-best-practices/references/deprecations.md).

## File Types

- `.svelte` — a component. Has `<script>`, markup, and `<style>` blocks.
- `.svelte.ts` / `.svelte.js` — a reactive module. The compiler transforms runes here too. Use these for shared reactive state and reusable reactive logic.
- `.ts` / `.js` — plain modules. Runes are NOT transformed here. Don't use `$state` etc. in plain `.ts` files; rename to `.svelte.ts` if you need reactivity.

## Component Anatomy

```svelte
<script lang="ts">
  // imports, props, state, derived, effects, functions
  let { name = 'world' }: { name?: string } = $props();
  let count = $state(0);
  let doubled = $derived(count * 2);
</script>

<h1>Hello {name}</h1>
<button onclick={() => count++}>{doubled}</button>

<style>
  h1 { color: tomato; }
</style>
```

A component is its file. Each `.svelte` file exports one component as the default export. To export named values, use `<script module>` (not the legacy `context="module"`):

```svelte
<script module lang="ts">
  export const VERSION = '1.0';
</script>
<script lang="ts">
  // instance script
</script>
```

`<script module>` runs once when the module is first evaluated. The instance `<script>` runs per component instance.

Components are functions, not classes. Render a dynamic component directly (`<Thing />` where `Thing` is a variable); `<svelte:component>` is legacy. For recursion, import the component itself instead of `<svelte:self>`.

## Runes

Runes are compiler keywords. They look like functions but are syntax — don't import them. Always use parentheses (`$state(0)`, not `$state 0`).

### `$state`

Creates reactive state.

```svelte
<script>
  let count = $state(0);
  let todos = $state([{ done: false, text: 'add more todos' }]);
</script>
```

- Plain objects and arrays become deeply-reactive **proxies**. Mutating nested properties (`todos[0].done = true`) and array methods (`push`, `splice`) trigger updates.
- Class instances are NOT proxied. Use `$state` on class **fields**, or as the first assignment to a property in the constructor (constructor form: 5.31+):
  ```js
  class Todo {
    done = $state(false);
    constructor(text) {
      this.text = $state(text);
    }
    // arrow function keeps `this` when used as onclick={todo.reset}
    reset = () => { this.text = ''; this.done = false; };
  }
  ```
- Destructuring loses reactivity: `let { done } = todos[0]` captures the value at that moment.
- `$state.raw(value)` — not deeply reactive. Mutations are ignored; only reassignment triggers updates. Use for large arrays/objects you replace wholesale.
- `$state.snapshot(proxy)` — returns a plain (non-proxy) deep copy. Use before passing state to external libraries or `structuredClone`.
- Only make values `$state` when they actually need to be reactive.

### `$derived`

Computed reactive values.

```svelte
<script>
  let count = $state(0);
  let doubled = $derived(count * 2);      // an expression, not a function
  let total = $derived.by(() => {
    let sum = 0;
    for (const n of items) sum += n;
    return sum;
  });
</script>
```

- Expression must be **side-effect-free**. State writes inside are not allowed.
- Dependencies are auto-tracked: any state read synchronously inside the expression. Use `untrack(() => ...)` to exclude a read.
- Use `$derived.by(() => { ... })` when you need statements (loops, conditionals, multiple lines).
- Derived values are returned as-is, not made deeply reactive.
- Destructuring a derived keeps each variable reactive: `let { a, b } = $derived(stuff())`.
- Values that depend on props should be `$derived`, because props can change.
- Deriveds can be **temporarily overridden** by reassignment (5.25+, unless declared with `const`). They recompute when dependencies change. Useful for optimistic UI:
  ```ts
  let likes = $derived(post.likes);
  async function like() {
    likes += 1;            // optimistic
    try { await api.like(); } catch { likes -= 1; }
  }
  ```
- Push-pull reactivity: deriveds re-evaluate lazily when read; downstream updates skip if the result is referentially identical.
- Class fields can be `$derived`.

### `$effect`

Side effects that run after the DOM updates. Treat `$effect` as an escape hatch.

```svelte
<script>
  let canvas = $state();
  let color = $state('red');

  $effect(() => {
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = color;
    ctx.fillRect(0, 0, 100, 100);

    return () => ctx.clearRect(0, 0, 100, 100); // optional teardown
  });
</script>

<canvas bind:this={canvas} width="100" height="100"></canvas>
```

- Runs in the browser only — never during SSR. So never wrap an effect body in `if (browser)`.
- Tracks state read **synchronously** inside the function (including through function calls). Reads after an `await` or inside `setTimeout` are not tracked. Dependencies are whatever was read on the last run.
- Re-runs when a dependency changes. The teardown runs before each re-run and on destroy.
- `$effect.pre(...)` — runs before DOM updates. Replaces `beforeUpdate`.
- `$effect.tracking()` — `true` inside an effect or the template, `false` during component setup.
- `$effect.root(() => { ... })` — creates a non-tracked scope with no auto-cleanup; returns a function that destroys it.
- **Avoid updating state in effects.** Prefer the alternatives:
  - computing a value → `$derived` (or an overridable derived)
  - reacting to user input → an event handler or a function binding
  - syncing with an external library or a DOM node → `{@attach}` (see `svelte-advanced`)
  - observing an external source → `createSubscriber` from `svelte/reactivity`
  - debugging → `$inspect`
  - If you really must write state in an effect, wrap the reads with `untrack`.

### `$props`

Reads component inputs.

```svelte
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    adjective?: string;
    children?: Snippet;
    [key: string]: unknown;
  }

  let { adjective = 'cool', children, ...rest }: Props = $props();
</script>
```

- Destructure with defaults inline. Fallbacks apply when the prop is unset or `undefined`. Renaming works (`{ super: trouper } = $props()`).
- Rest props (`...rest`) capture everything else (replaces `$$props` / `$$restProps`).
- **Don't mutate props.** A child may reassign a prop locally, but pass callback props for changes, or use `$bindable` for two-way data.
- `children` is reserved for the implicit content snippet.
- `$props.id()` (5.20+) — ID unique per component instance, consistent between SSR and hydration. Use for `for` / `aria-labelledby`.

### `$bindable`

Marks a prop as two-way bindable from the parent.

```svelte
<!-- Input.svelte -->
<script lang="ts">
  let { value = $bindable(''), ...props }: { value?: string } = $props();
</script>
<input bind:value {...props} />
```

```svelte
<!-- Parent.svelte -->
<script>
  let name = $state('');
</script>
<Input bind:value={name} />
```

- Bindable means the prop *can* be bound, not that it *must* be.
- In runes mode, you cannot bind to props that are not `$bindable`.
- Only mark props bindable when two-way binding is genuinely needed; default to one-way + callbacks.

### `$inspect`

Dev-time debugging — logs when tracked values change. It is a no-op in production builds.

```ts
$inspect(count, message);                    // logs on init and on every change
$inspect(count).with((type, value) => {      // type is 'init' | 'update'
  if (type === 'update') debugger;
});

$effect(() => {
  $inspect.trace();   // 5.14+; must be the FIRST statement; logs which state caused the re-run
  doSomeWork();
});
```

### `$host`

Only for components compiled as custom elements (`<svelte:options customElement="my-el" />`). Returns the host element, for example to dispatch events:

```ts
$host().dispatchEvent(new CustomEvent('increment'));
```

## Sharing State Across Modules

In `.svelte.ts` / `.svelte.js`:

```ts
// counter.svelte.ts — DON'T export state that gets reassigned
export let count = $state(0);
export function increment() { count += 1; }   // compile error: state_invalid_export
```

Correct patterns:

```ts
// 1. Export an object whose properties you mutate
export const counter = $state({ count: 0 });
export function increment() { counter.count += 1; }
```

```ts
// 2. Export getters/functions, keep state private
let count = $state(0);
export function getCount() { return count; }
export function increment() { count += 1; }
```

```ts
// 3. Classes with $state fields — the recommended way to share reactive logic
export class Counter {
  count = $state(0);
  increment = () => { this.count += 1; };
}
```

Values are passed by value — passing `count` to a function passes the current value, not a live reference. To pass live state, pass a getter `() => count`, an object whose property you read, or a class instance.

During SSR, module-level state is shared between all requests. For per-user or per-request state, put the instance in **context** (see below) instead of a module-level variable.

## Markup

### Text expressions

```svelte
<p>Hello {name}!</p>
<p>{a + b} = {a} + {b}</p>
```

`null` and `undefined` render nothing.

### Attributes

```svelte
<button disabled={busy} class={['btn', { active: isActive }]}>Go</button>
<input {value} />                 <!-- shorthand: same as value={value} -->
<div {...attrs}></div>            <!-- spread; order matters -->
```

- Don't wrap a single expression in quotes (`disabled={x}`, not `disabled="{x}"`). Svelte 6 will turn quoted values into strings.
- Boolean attributes are included when truthy; other attributes are omitted when `null` / `undefined`.
- JavaScript comments are allowed between attributes (5.53+):
  ```svelte
  <div
    // explains the next attribute
    data-foo="bar"
  ></div>
  ```

### Events

Use **HTML event attributes**, not the legacy `on:` directive:

```svelte
<button onclick={handleClick}>Click</button>
<button {onclick}>Shorthand</button>
<input oninput={(e) => value = e.currentTarget.value} />
```

- Attribute names are case-sensitive: `onclick`, not `onClick`.
- There are no event modifiers in runes mode. Call `preventDefault()`, `stopPropagation()` etc. inside the handler:
  ```svelte
  <form onsubmit={(e) => { e.preventDefault(); save(); }}>
  ```
- For capture phase, suffix the attribute: `onclickcapture`.
- Component events are **callback props** (`onsave={...}`). `createEventDispatcher` is deprecated.
- Event handlers run after binding updates (`oninput` fires after `bind:value` has updated).
- For window/document events use `<svelte:window onkeydown={...} />` and `<svelte:document onvisibilitychange={...} />` instead of `addEventListener` in `onMount` or `$effect`. If you must listen manually, use `on(target, type, handler)` from `svelte/events`.

### Control flow

```svelte
{#if user}
  <p>Hi {user.name}</p>
{:else if guest}
  <p>Welcome guest</p>
{:else}
  <p>Sign in</p>
{/if}

{#each items as item, i (item.id)}
  <li>{i}: {item.text}</li>
{:else}
  <li>Empty</li>
{/each}

{#each { length: 8 }, rank}       <!-- no `as` needed (5.4+) -->
  <span>{rank}</span>
{/each}

{#await promise}
  <p>Loading…</p>
{:then value}
  <p>{value}</p>
{:catch err}
  <p>Error: {err.message}</p>
{/await}

{#key id}
  <Component />          <!-- destroyed and re-created when `id` changes -->
{/key}
```

- **Always key `{#each}` blocks** with a value that uniquely identifies the item. Never use the index as the key. Without a key, Svelte updates by position, so transitions, animations and component state can attach to the wrong item.
- Avoid destructuring the item in `{#each}` when you bind to or mutate it.
- `{#each}` accepts arrays, array-likes and iterables (`Map`, `Set`).
- `{#key}` is expensive — use it sparingly.
- During SSR, `{#await}` renders only the pending branch.

### `await` expressions (experimental)

Flag: `compilerOptions.experimental.async: true` (5.36+). Only use if the project already enables it or the task asks for it. The flag is expected to be removed in Svelte 6.

```svelte
<p>{await getGreeting(name)}</p>
```

- `await` works at the top level of `<script>`, inside `$derived(...)`, and in markup.
- In a SvelteKit 3 project the flag goes in `vite.config`: `sveltekit({ compilerOptions: { experimental: { async: true } } })`. `svelte.config.js` is not supported in SvelteKit 3. In a SvelteKit 2 or plain Svelte + Vite project it goes in `compilerOptions` in `svelte.config.js`.
- Loading and error UI comes from `<svelte:boundary>` (`pending` / `failed` snippets) and `$effect.pending()` — see `svelte-advanced`.
- Independent `await`s in markup run in parallel. Sequential `$derived(await ...)` calls in the script create a waterfall on first run (Svelte logs an `await_waterfall` warning at runtime).

### Declaration tags `{const}` / `{let}` (5.56+)

Declare values anywhere in the template. They are lexically scoped to the surrounding block.

```svelte
{#each boxes as box}
  {const area = box.width * box.height}
  <p>{box.width} × {box.height} = {area}</p>
{/each}

{#if editing}
  {let name = $state(user.name)}
  {const greeting = $derived(`Hello ${name}`)}
  <input bind:value={name} />
  <p>{greeting}</p>
{/if}
```

- Reactive values need `$state` / `$derived` explicitly.
- Declaration tags only work in runes mode (not in legacy-mode components).
- `{@const x = y}` is now **legacy**. In new code on 5.56+, use `{const x = $derived(y)}`. On older versions, keep using `{@const}` (it can only be the direct child of a block, component or `<svelte:boundary>`).

### Snippets and `{@render}`

Snippets are reusable markup chunks. They replace slots (`<slot>`, `$$slots` and `<svelte:fragment>` are deprecated).

```svelte
<!-- Define -->
{#snippet row(item)}
  <tr><td>{item.name}</td><td>{item.price}</td></tr>
{/snippet}

<!-- Render -->
<table>
  {#each items as item (item.id)}
    {@render row(item)}
  {/each}
</table>
```

- Parameters can have defaults and be destructured, but rest parameters are not allowed.
- Snippets are lexically scoped and can be recursive. Top-level snippets can be referenced inside `<script>`.
- Snippets that don't use instance state can be exported from `<script module>` (5.5+): `export { row };`.

Children of a component become a snippet named `children`:

```svelte
<!-- Card.svelte -->
<script>
  let { children } = $props();
</script>
<div class="card">{@render children?.()}</div>

<!-- Usage -->
<Card>Hello</Card>
```

Pass named snippet props by declaring them inside the component tag, or explicitly as props (`<DataTable {header} {row} />`):

```svelte
<DataTable {items}>
  {#snippet header()}<tr><th>Name</th></tr>{/snippet}
  {#snippet row(item)}<tr><td>{item.name}</td></tr>{/snippet}
</DataTable>
```

Type a snippet prop with `import type { Snippet } from 'svelte'` (arguments as a tuple):

```ts
let { row }: { row: Snippet<[Item]> } = $props();
```

### Other markup tags

- `{@html string}` — inject raw HTML. Sanitize first; XSS risk. The content is not scoped by component styles.
- `{@debug var1, var2}` — pause in devtools when listed values change (variable names only).
- `{@attach fn}` (5.29+) — attach reactive behaviour to an element (see `svelte-advanced`).

### Bindings

```svelte
<input bind:value={name} />
<input type="checkbox" bind:checked={agreed} />
<input type="number" bind:value={age} />      <!-- numeric inputs bind numbers -->
<input type="file" bind:files />
<select bind:value={selected}>...</select>
<textarea bind:value={text}></textarea>

<video bind:duration bind:currentTime bind:paused>...</video>

<div bind:clientWidth={w} bind:clientHeight={h}>...</div>
<div bind:this={el}>...</div>
```

- `bind:this` is `undefined` until the component mounts; read it in an effect or event handler.
- Binding to a component prop requires `$bindable` on the child.
- `defaultValue` / `defaultChecked` set the value restored on form reset (5.6+). `<select bind:value defaultValue="b">` works since 5.57.

Function bindings (5.9+) — a getter and a setter. Prefer these over effects for linked or transformed inputs:

```svelte
<input bind:value={() => name, (v) => name = v.toUpperCase()} />

<!-- read-only binding: use null as the getter -->
<div bind:clientWidth={null, redraw}>...</div>
```

### `class` and `style`

```svelte
<div class={['btn', { active, large: size === 'lg' }]}>...</div>
<div class={[faded && 'opacity-50', props.class]}>...</div>
<div style:color={theme.primary} style:--gap="8px">...</div>
```

- `class` accepts strings, arrays, or objects (5.16+), using the same rules as `clsx`. Type it with `ClassValue` from `svelte/elements` (5.19+).
- Prefer the `class` attribute over the `class:` directive. `class:` still works but is less composable.
- `style:` directives win over the `style` attribute. Use `style:--name={value}` to pass JavaScript values to CSS.

### `use:` actions and `{@attach}`

```svelte
<div use:tooltip={'Hello'}>...</div>
```

On 5.29+, prefer attachments via `{@attach}` for new code (see `svelte-advanced`). Existing `use:` actions still work.

## Scoped Styles

Styles in `<style>` are scoped to the component — Svelte adds a hash class.

```svelte
<style>
  p { color: tomato; }            /* only this component's <p> */
  :global(body) { margin: 0; }    /* escape hatch */
  div :global(strong) { color: goldenrod; }
  .prose :global {                /* block form: everything inside is global */
    a { color: inherit; }
  }
</style>
```

- `:global(selector)` or a `:global { ... }` block opts out of scoping.
- Custom CSS properties pass naturally through scoped styles, so they're the right tool for theming.
- Keyframes are scoped by default; use the `-global-` prefix to expose them: `@keyframes -global-spin {}`.

To pass styles into a component, use CSS custom properties:

```svelte
<!-- Slider.svelte -->
<style>
  .track { background: var(--slider-bg, #eee); }
</style>
<!-- Usage -->
<Slider --slider-bg="lightblue" />
```

Svelte wraps the component in an element with `display: contents` to apply these, so a parent's `>` child selector will not match the component's root.

## Lifecycle

Components only have creation and destruction. The helpers from `svelte`:

- `onMount(fn)` — runs once after first render, client-only. A returned function runs on destroy (only when `fn` is synchronous).
- `onDestroy(fn)` — runs when the component is destroyed (server and client).
- `tick()` — returns a promise that resolves once pending state changes have applied to the DOM.
- `flushSync(fn?)` — applies pending state changes synchronously.
- `untrack(fn)` — read state without registering it as a dependency.
- `beforeUpdate` / `afterUpdate` are deprecated and not available in runes components. Use `$effect.pre` / `$effect`.

## Context

For passing values down the component tree without prop-drilling. Context must be set during component initialisation.

Prefer `createContext` (5.40+) — it is type-safe and needs no key. Since 5.57 it returns `[get, set, has]`:

```ts
// user-context.ts
import { createContext } from 'svelte';

interface User { name: string }

export const [getUserContext, setUserContext, hasUserContext] = createContext<User>();
```

```svelte
<!-- Parent.svelte -->
<script lang="ts">
  import { setUserContext } from './user-context';
  const user = $state({ name: 'Ada' });
  setUserContext(user);
</script>

<!-- Child.svelte (any depth) -->
<script lang="ts">
  import { getUserContext } from './user-context';
  const user = getUserContext();   // throws if no ancestor set it
</script>
```

- On 5.40 – 5.56, `createContext` returns only `[get, set]`.
- The classic API (`setContext(key, value)`, `getContext(key)`, `hasContext(key)`, `getAllContexts()`) still works. Use a `Symbol` key for non-public contexts. Use it when the project is older than 5.40 or already uses it.
- For reactive context, pass a `$state` object or class instance and mutate its properties. Reassigning the variable breaks the link. For primitives, pass a getter.

## Stores (legacy for shared state)

Stores from `svelte/store` (`writable`, `readable`, `derived`, `readonly`, `get`) are still supported and work with the `$store` auto-subscription syntax at the top level of a component. Use them when:
- The codebase already uses them and you're matching the pattern.
- You need complex async data streams, manual control over subscriptions, or RxJS interop.

For new shared state, prefer classes with `$state` fields (or `$state` objects) in `.svelte.ts` modules.

## Common Mistakes to Avoid

1. **Passing a regular class method as a handler** (`onclick={todo.reset}`) — `this` becomes the element. Use an arrow-function class field or an inline function (`onclick={() => todo.reset()}`).
2. **Using `$:` reactive statements in runes mode** — they're a Svelte 4 feature. Use `$derived` or `$effect`.
3. **Using `export let` in runes mode** — use `$props()`.
4. **Using `on:click` or event modifiers in runes mode** — use `onclick` and call `preventDefault()` in the handler.
5. **Mutating a non-`$state` object expecting reactivity** — only state declared with `$state` is reactive.
6. **Effects deriving or syncing state** — use `$derived`, an event handler, or a function binding.
7. **Putting runes in `.ts` files** — rename to `.svelte.ts`.
8. **Destructuring reactive state and expecting the locals to update** — destructuring captures values; keep the access path (`obj.prop`) instead.
9. **Keying `{#each}` by index, or not keying at all.**
10. **Wrapping `$effect` bodies in `if (browser)`** — effects never run on the server.
11. **Using legacy syntax in new code** — `<slot>`, `createEventDispatcher`, `<svelte:component>`, `class:`, `use:` (5.29+: use `{@attach}`), `{@const}` (5.56+: use `{const}`).
12. **Using `await` at the top level of `<script>`, in `$derived`, or in markup without `experimental.async` enabled.** (`await` inside ordinary async functions and `{#await}` blocks needs no flag.)
