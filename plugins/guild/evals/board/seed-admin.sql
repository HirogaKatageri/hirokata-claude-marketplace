-- A second project whose only plan names no capability.
PRAGMA foreign_keys = ON;
INSERT INTO project (id, goal_id, title, body, priority, created_at, updated_at) VALUES
 ('PROJ-002', 'GOAL-001', 'Order admin', 'Bulk cancel (R4).', 2,
  '2026-11-01T09:01:01Z', '2026-11-01T09:01:01Z');
INSERT INTO requirement (id, project_id, title, body, priority, created_at, updated_at) VALUES
 ('REQ-003', 'PROJ-002', 'Bulk cancel',
  'R4 in docs/requirements.md. Acceptance: cancelOrders(orders, ids) returns a new array, matching orders get status cancelled, the input is not changed.',
  1, '2026-11-01T09:02:02Z', '2026-11-01T09:02:02Z');
INSERT INTO plan (id, requirement_id, kind, title, body, files, priority, created_at, updated_at) VALUES
 ('PLAN-004', 'REQ-003', 'build', 'Add cancelOrders in src/admin.js',
  'Approach: new file src/admin.js exporting cancelOrders(orders, ids), which maps orders to copies with status cancelled when their id is in ids. Verify: node -e check that the input is unchanged.',
  '["src/admin.js"]', 1, '2026-11-01T09:03:03Z', '2026-11-01T09:03:03Z');
