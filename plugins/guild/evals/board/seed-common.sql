PRAGMA foreign_keys = ON;
UPDATE guild_state SET value = 'user' WHERE key = 'actor';
INSERT INTO goal (id, title, body, success_criteria, priority, created_at, updated_at) VALUES
 ('GOAL-001', 'Finish the orders module', 'Every requirement in docs/requirements.md is built and tested.',
  'R1 to R4 in docs/requirements.md are implemented and npm test passes', 1,
  '2026-11-01T09:00:00Z', '2026-11-01T09:00:00Z');
INSERT INTO project (id, goal_id, title, body, priority, created_at, updated_at) VALUES
 ('PROJ-001', 'GOAL-001', 'Orders reporting', 'CSV export (R3) and a safe average (R2).', 1,
  '2026-11-01T09:01:00Z', '2026-11-01T09:01:00Z');
INSERT INTO requirement (id, project_id, title, body, priority, created_at, updated_at) VALUES
 ('REQ-001', 'PROJ-001', 'CSV export',
  'R3 in docs/requirements.md. Acceptance: header row id,customer,amount; one line per order; values with a comma or double quote are quoted and inner quotes doubled.',
  1, '2026-11-01T09:02:00Z', '2026-11-01T09:02:00Z'),
 ('REQ-002', 'PROJ-001', 'Average of an empty list is 0',
  'R2 in docs/requirements.md. Acceptance: averageOrderValue([]) returns 0; existing behaviour unchanged.',
  2, '2026-11-01T09:02:01Z', '2026-11-01T09:02:01Z');
INSERT INTO plan (id, requirement_id, kind, title, body, files, priority, created_at, updated_at) VALUES
 ('PLAN-001', 'REQ-001', 'build', 'Add exportOrdersCsv to src/orders.js',
  'Approach: add and export exportOrdersCsv(orders) in src/orders.js. Steps: 1. write a quote(value) helper that wraps values containing a comma or a double quote in double quotes and doubles inner quotes; 2. return the header id,customer,amount followed by one line per order, joined with \n. Verify: node -e "import(''./src/orders.js'').then(m => console.log(m.exportOrdersCsv([{id:1,customer:''a,b'',amount:3}])))" prints the header and 1,"a,b",3.',
  '["src/orders.js"]', 1, '2026-11-01T09:03:00Z', '2026-11-01T09:03:00Z'),
 ('PLAN-002', 'REQ-001', 'test', 'Tests for exportOrdersCsv',
  'Write test/export.test.js with node:test: 1. header only for an empty list; 2. one plain order; 3. a customer containing a comma is quoted; 4. a customer containing a double quote has it doubled. Verify: npm test passes.',
  '["test/export.test.js"]', 2, '2026-11-01T09:03:01Z', '2026-11-01T09:03:01Z'),
 ('PLAN-003', 'REQ-002', 'build', 'Return 0 for an empty list in averageOrderValue',
  'Approach: in src/orders.js, return 0 from averageOrderValue when orders is empty. Add test/average.test.js with node:test checking averageOrderValue([]) === 0. Verify: npm test passes.',
  '["src/orders.js", "test/average.test.js"]', 3, '2026-11-01T09:03:02Z', '2026-11-01T09:03:02Z');
INSERT INTO plan_capability (plan_id, capability, required) VALUES
 ('PLAN-001', 'implement', 1), ('PLAN-001', 'backend', 0),
 ('PLAN-002', 'test-authoring', 1),
 ('PLAN-003', 'implement', 1);
INSERT INTO plan_dependency (plan_id, depends_on) VALUES
 ('PLAN-002', 'PLAN-001'),
 ('PLAN-003', 'PLAN-001');
UPDATE guild_state SET value = 'orchestrator' WHERE key = 'actor';
