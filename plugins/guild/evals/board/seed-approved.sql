-- The three PROJ-001 plans, approved by the user.
UPDATE plan SET approval = 'approved', approved_by = 'user', approved_at = '2026-11-01T10:00:00Z'
 WHERE id IN ('PLAN-001', 'PLAN-002', 'PLAN-003');
