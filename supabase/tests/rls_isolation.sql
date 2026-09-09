-- RLS isolation smoke checks for Phase 1.
-- Run against a STAGING database after applying migrations.
-- DO NOT run against production.
--
-- Expected: User A cannot SELECT/UPDATE org B rows.

-- Prerequisites (manual setup in staging):
-- 1) Create auth users user_a and user_b
-- 2) Create org_a (member: user_a owner) and org_b (member: user_b owner)
-- 3) As user_a JWT, attempt:

-- select * from organizations where id = '<org_b>';
-- Expect: 0 rows

-- update organizations set legal_name = 'hack' where id = '<org_b>';
-- Expect: 0 rows affected

-- insert into branches (organization_id, name) values ('<org_b>', 'x');
-- Expect: policy violation

-- select * from audit_events where organization_id = '<org_b>';
-- Expect: 0 rows

-- As viewer role on org_a:
-- update organizations set legal_name = 'x' where id = '<org_a>';
-- Expect: denied (can_mutate_org false for viewer)

select 'See docs/qa/PHASE-1-QA.md for the executed checklist' as note;
