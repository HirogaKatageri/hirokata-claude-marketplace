#!/bin/bash
# Builds a small orders project with a guild v10 board, in the current (empty) directory.
# Usage: fixture.sh <seed.sql>
set -euo pipefail
PLUGIN="$(cd "$(dirname "$0")/../.." && pwd)"
SEED="$1"
export PATH="$HOME/.turso:$PATH"
g() { git -c user.name=bench -c user.email=bench@example.invalid "$@"; }

g init -q -b main
mkdir -p docs src test .guild
cat > docs/requirements.md <<'MD'
# Orders module — requirements

- **R1 Find orders.** `findOrders(orders, customer)` returns every order of one customer.
- **R2 Average order value.** `averageOrderValue(orders)` returns the mean `amount`.
  An empty list returns `0`.
- **R3 CSV export.** `exportOrdersCsv(orders)` returns the orders as CSV: a header row
  `id,customer,amount`, then one line per order. A value containing a comma or a double
  quote is wrapped in double quotes, with inner quotes doubled.
- **R4 Bulk cancel.** `cancelOrders(orders, ids)` returns a new array where every order
  whose id is in `ids` has `status: 'cancelled'`. The input array is not changed.
MD
cat > package.json <<'JSON'
{ "name": "orders", "version": "1.0.0", "type": "module",
  "scripts": { "test": "node --test" } }
JSON
cat > src/orders.js <<'JS'
export function findOrders(orders, customer) {
  return orders.filter((o) => o.customer === customer);
}

export function averageOrderValue(orders) {
  const total = orders.reduce((sum, o) => sum + o.amount, 0);
  return total / orders.length;
}
JS
cat > test/orders.test.js <<'JS'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { findOrders, averageOrderValue } from '../src/orders.js';

test('finds one customer', () => {
  const orders = [{ id: 1, customer: 'a', amount: 5 }, { id: 2, customer: 'b', amount: 7 }];
  assert.deepEqual(findOrders(orders, 'a').map((o) => o.id), [1]);
});

test('average of two orders', () => {
  assert.equal(averageOrderValue([{ amount: 10 }, { amount: 20 }]), 15);
});
JS
printf '# Changelog\n\n## [Unreleased]\n' > CHANGELOG.md

tursodb .guild/guild.db < "$PLUGIN/schema.sql" > /dev/null
cat > .guild/config.yaml <<'YAML'
# guild configuration. Committed to git.
version: 6
domain: software
backend: local
YAML
printf 'guild.db\nguild.db-*\nguild.db.*\ndashboard.html\n' > .guild/.gitignore
tursodb -q .guild/guild.db < "$SEED" > /dev/null
g add -A && g commit -q -m "chore: orders module and guild board"
