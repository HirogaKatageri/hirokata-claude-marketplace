#!/bin/bash
set -euo pipefail
g() { git -c user.name=eval -c user.email=eval@example.invalid "$@"; }
g init -q -b main
mkdir -p docs src test
cat > docs/requirements.md <<'MD'
# Orders feature — requirements

- **R1 Find orders.** `findOrders(db, customer)` returns every order of one customer,
  newest first.
- **R2 Average order value.** `averageOrderValue(orders)` returns the mean `amount`.
  An empty list returns `0`.
- **R3 Discounts.** `applyDiscount(order, percent)` reduces the amount by `percent`.
  `percent` must be between 0 and 50 inclusive; anything else throws a `RangeError`.
  The new amount is rounded to 2 decimal places.
- **R4 CSV export.** `exportOrdersCsv(orders)` returns the orders as CSV with a header
  row `id,customer,amount`.
- **R5 Get one order.** `getOrder(db, id, user)` returns the order only when it belongs
  to `user.customer`, or when `user.role` is `admin`. Otherwise it returns `null`.
MD
cat > package.json <<'JSON'
{ "name": "orders", "version": "1.0.0", "type": "module",
  "scripts": { "test": "node --test" } }
JSON
cat > src/db.js <<'JS'
export function createDb(rows) {
  return { query: (sql) => ({ sql, rows }) };
}
JS
g add -A && g commit -q -m "chore: project setup"
g checkout -q -b feat/orders
cat > src/orders.js <<'JS'
export function findOrders(db, customer) {
  return db.query("SELECT * FROM orders WHERE customer = '" + customer + "'");
}

export function averageOrderValue(orders) {
  const total = orders.reduce((sum, o) => sum + o.amount, 0);
  return total / orders.length;
}

export function applyDiscount(order, percent) {
  return { ...order, amount: order.amount * (1 - percent / 100) };
}

export function getOrder(db, id, user) {
  const result = db.query('SELECT * FROM orders WHERE id = ' + Number(id));
  const order = result.rows.find((o) => o.id === Number(id)) ?? null;
  if (user.role === 'admin') return order;
  return order;
}
JS
cat > test/orders.test.js <<'JS'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { averageOrderValue, applyDiscount } from '../src/orders.js';

test('average of two orders', () => {
  assert.equal(averageOrderValue([{ amount: 10 }, { amount: 20 }]), 15);
});

test('ten percent discount', () => {
  assert.equal(applyDiscount({ amount: 100 }, 10).amount, 90);
});
JS
g add -A && g commit -q -m "feat(orders): find orders, average value and discounts"
