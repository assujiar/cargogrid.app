-- Real, executable test evidence for HRT-290 (Ticket Assignment,
-- CG-S12-HRT-018). Run via `pnpm run db:test` against a real, disposable
-- Postgres database (and standalone via psql, per ISS-2026-077's own
-- documented workaround for the pre-existing, unrelated wall-clock-date
-- failure in scripts/db-tests/hris-leave-permit-business-trip.sql).
--
-- Self-contained: own two-tenant/employee/role/queue/category fixture, own
-- fresh, unclaimed UUID range (00000000-0000-0000-0000-0000002901xx /
-- ...02xx). Tenant slugs `asn1`/`asn2` (grep-verified unclaimed).
--
-- Covers, live: deterministic routing-rule precedence (specificity ranking,
-- genuine ambiguous-match detection, publish-supersedes-own-prior-version);
-- routing preview against a synthetic ticket; atomic self-service claim
-- (non-member rejection, idempotent same-employee replay, a clean
-- ticket_already_assigned conflict for a genuinely later caller); accept
-- (a real assignment_confirmed_at effect) and decline (mandatory reason,
-- clears assignee, real ledger row); effective eligibility (lifecycle_status
-- AND currently-dated approved leave, both real, existing HRIS data --
-- never a parallel concept) blocking claim AND manual assign, with NO
-- override on either path; a configured workload cap blocking claim (no
-- override) and blocking manual assign UNLESS explicitly overridden;
-- auto-route (queue selection plus a deterministic least-loaded pick, and
-- the disclosed "no eligible candidate" ledger outcome); manual
-- assign/reassign/unassign event-type computation and its idempotent
-- same-assignee replay; transfer_ticket_queue''s own widened ledger logging;
-- a REAL two-OS-process concurrent claim race (sequential AND genuinely
-- concurrent) producing exactly one winner and a clean, discriminated
-- stale_version for the loser -- never a raw constraint violation;
-- cross-channel isolation (helpdesk explicitly rejected by every new RPC,
-- customer-channel tickets DO route/assign staff-side while the
-- customer-facing surface is refused with the identical ticket_not_found an
-- RLS predicate would produce -- anti-enumeration, never a raw employee
-- list); cross-tenant isolation via RPC and raw-table RLS; assignment never
-- broadening linked-record access; schema-privilege defense in depth
-- (anon has zero access).

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid; v_admin_draft app.role_versions;
  v_hr_role uuid; v_hr_draft app.role_versions;
  v_company uuid; v_branch uuid; v_dept uuid;
  v_queue uuid; v_category uuid;
  v_account_a uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000290101', 'admin@asn1.test'),
    ('00000000-0000-0000-0000-000000290102', 'staff1@asn1.test'),
    ('00000000-0000-0000-0000-000000290103', 'staff2@asn1.test'),
    ('00000000-0000-0000-0000-000000290104', 'staff3@asn1.test'),
    ('00000000-0000-0000-0000-000000290105', 'req1@asn1.test'),
    ('00000000-0000-0000-0000-000000290106', 'staff4@asn1.test'),
    ('00000000-0000-0000-0000-000000290107', 'staff5@asn1.test'),
    ('00000000-0000-0000-0000-000000290110', 'customer1@asn1.test'),
    ('00000000-0000-0000-0000-000000290201', 'admin@asn2.test');

  perform app.provision_tenant('asn1', 'ASN Co 1', 'idem-asn1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'asn1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('asn2', 'ASN Co 2', 'idem-asn2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'asn2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000290101', 'admin@asn1.test', 'Asn1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@asn1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000290101', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000290102', 'staff1@asn1.test', 'Asn1 Staff One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff1@asn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000290103', 'staff2@asn1.test', 'Asn1 Staff Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff2@asn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000290104', 'staff3@asn1.test', 'Asn1 Staff Three', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff3@asn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000290105', 'req1@asn1.test', 'Asn1 Requester One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'req1@asn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000290106', 'staff4@asn1.test', 'Asn1 Staff Four', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff4@asn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000290107', 'staff5@asn1.test', 'Asn1 Staff Five', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff5@asn1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000290110', 'customer1@asn1.test', 'Asn1 Customer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer1@asn1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000290201', 'admin@asn2.test', 'Asn2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@asn2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000290201', 'tenant_admin', v_tenant2, null, 'tester');

  v_hr_role := (app.create_role(v_tenant1, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
  v_hr_draft := app.create_role_version(v_hr_role, 'tester');
  perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
  perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000290101', '00000000-0000-0000-0000-000000290101', 'tester');

  -- staff1 holds BOTH TKT:Edit (routing rule/queue/category admin) and
  -- TKT:Assign (manual designation) -- mirrors a real "ticket admin" role;
  -- staff2/staff3/staff4/staff5 hold neither, only plain queue membership
  -- (decision 3/5: "ordinary day-to-day ticket work needs no TKT permission
  -- beyond an explicit active queue-membership grant").
  v_admin_role := (app.create_role(v_tenant1, 'Ticket Admin', 'TKT Edit/Assign', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Edit', 'Assign')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000290102', '00000000-0000-0000-0000-000000290101', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-ASN1', 'Asn1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-ASN1', 'Asn1 Branch', 'tester')).id;
  v_dept := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-SUP', 'Support', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Asn1 Admin', 'full_time', 'adminwork@asn1.test', 'adminp@asn1.test', '0900000001', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Admin', null, (select id from app.users where email = 'admin@asn1.test'), null, 'hr_created', 'idem-admin-asn1', '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@asn1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@asn1.test'), 1, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@asn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@asn1.test'), 3, '00000000-0000-0000-0000-000000290101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Asn1 Staff One', 'full_time', 'staff1work@asn1.test', 'staff1p@asn1.test', '0900000002', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff1@asn1.test'), null, 'hr_created', 'idem-staff1-asn1', '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@asn1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@asn1.test'), 1, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@asn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@asn1.test'), 3, '00000000-0000-0000-0000-000000290101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Asn1 Staff Two', 'full_time', 'staff2work@asn1.test', 'staff2p@asn1.test', '0900000003', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff2@asn1.test'), null, 'hr_created', 'idem-staff2-asn1', '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@asn1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@asn1.test'), 1, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@asn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@asn1.test'), 3, '00000000-0000-0000-0000-000000290101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Asn1 Staff Three', 'full_time', 'staff3work@asn1.test', 'staff3p@asn1.test', '0900000009', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff3@asn1.test'), null, 'hr_created', 'idem-staff3-asn1', '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff3work@asn1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff3work@asn1.test'), 1, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff3work@asn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff3work@asn1.test'), 3, '00000000-0000-0000-0000-000000290101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Asn1 Requester One', 'full_time', 'req1work@asn1.test', 'req1p@asn1.test', '0900000004', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Staff', null, (select id from app.users where email = 'req1@asn1.test'), null, 'hr_created', 'idem-req1-asn1', '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@asn1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@asn1.test'), 1, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@asn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@asn1.test'), 3, '00000000-0000-0000-0000-000000290101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Asn1 Staff Four', 'full_time', 'staff4work@asn1.test', 'staff4p@asn1.test', '0900000007', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff4@asn1.test'), null, 'hr_created', 'idem-staff4-asn1', '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff4work@asn1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff4work@asn1.test'), 1, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff4work@asn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff4work@asn1.test'), 3, '00000000-0000-0000-0000-000000290101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Asn1 Staff Five', 'full_time', 'staff5work@asn1.test', 'staff5p@asn1.test', '0900000008', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff5@asn1.test'), null, 'hr_created', 'idem-staff5-asn1', '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff5work@asn1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff5work@asn1.test'), 1, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff5work@asn1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000290101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff5work@asn1.test'), 3, '00000000-0000-0000-0000-000000290101', 'tester');

  v_queue := (app.create_ticket_queue(v_tenant1, v_dept, 'SUP', 'Support', 'Support queue', '00000000-0000-0000-0000-000000290102', 'staff1')).id;
  v_category := (app.create_ticket_category(v_tenant1, 'GENERAL', 'General Issue', v_queue, '00000000-0000-0000-0000-000000290102', 'staff1')).id;
  perform app.add_ticket_queue_member(v_queue, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@asn1.test'), '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.add_ticket_queue_member(v_queue, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@asn1.test'), '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.add_ticket_queue_member(v_queue, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff3work@asn1.test'), '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.add_ticket_queue_member(v_queue, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff4work@asn1.test'), '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.add_ticket_queue_member(v_queue, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff5work@asn1.test'), '00000000-0000-0000-0000-000000290102', 'staff1');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Customer Account A', 'fp-asn1-a', '{}'::jsonb, v_company, 'tester')
  returning id into v_account_a;
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000290110', 'customer_user', v_tenant1, v_account_a::text, 'tester');
  perform app.set_ticket_category_customer_visibility(v_category, true, '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.set_ticket_category_helpdesk_visibility(v_category, true, '00000000-0000-0000-0000-000000290102', 'staff1');

  raise notice 'fixture ready: tenant1=%, tenant2=%, queue=%, category=%, account_a=%',
    v_tenant1, v_tenant2, v_queue, v_category, v_account_a;
end;
$$;

\echo '>> 1. routing rules: create/version/publish, publish supersedes the SAME rule''s own prior published version, genuine ambiguous-match detection, preview against a synthetic ticket'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'asn1');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_rule app.ticket_routing_rules;
  v_v1 app.ticket_routing_rule_versions;
  v_v2 app.ticket_routing_rule_versions;
  v_resolved record;
  v_rule_a app.ticket_routing_rules; v_rule_b app.ticket_routing_rules;
  v_va app.ticket_routing_rule_versions; v_vb app.ticket_routing_rule_versions;
begin
  -- Base, uncapped, manual-mode rule for priority=null (matches every
  -- 'normal'-priority ticket the rest of this file creates) -- deliberately
  -- never blocks the main-flow tests below via workload cap.
  v_rule := app.create_ticket_routing_rule(v_tenant1, 'GEN-ROUTE', 'General routing', '00000000-0000-0000-0000-000000290102', 'staff1');
  v_v1 := app.create_ticket_routing_rule_version(v_rule.id, 'internal', v_category, null, v_queue, 'manual', null, 0, '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.publish_ticket_routing_rule_version(v_v1.id, v_v1.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');

  select * into v_resolved from app.preview_ticket_routing(v_tenant1, 'internal', v_category, 'normal', '00000000-0000-0000-0000-000000290102');
  if not v_resolved.matched or v_resolved.rule_version_id <> v_v1.id then
    raise exception 'FAIL: expected preview to match v1, got matched=%, version=%', v_resolved.matched, v_resolved.rule_version_id;
  end if;
  raise notice 'PASS: preview_ticket_routing matched the published rule version';

  -- Publish a v2 of the SAME rule -> v1 must be superseded, resolution now
  -- returns v2 (HRT-289''s own self-found "supersede on publish" fix, applied
  -- here from the start).
  v_v2 := app.create_ticket_routing_rule_version(v_rule.id, 'internal', v_category, null, v_queue, 'manual', null, 5, '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.publish_ticket_routing_rule_version(v_v2.id, v_v2.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
  if (select status from app.ticket_routing_rule_versions where id = v_v1.id) <> 'superseded' then
    raise exception 'FAIL: v1 should be superseded after v2''s own publish';
  end if;
  select * into v_resolved from app.preview_ticket_routing(v_tenant1, 'internal', v_category, 'normal', '00000000-0000-0000-0000-000000290102');
  if v_resolved.rule_version_id <> v_v2.id then
    raise exception 'FAIL: expected v2 to be the resolved version after supersede, got %', v_resolved.rule_version_id;
  end if;
  raise notice 'PASS: publish supersedes the SAME rule''s own prior published version; a later version''s own predecessor never ties against it at resolution time';

  -- No match for a scope nothing covers.
  select * into v_resolved from app.preview_ticket_routing(v_tenant1, 'customer', v_category, 'urgent', '00000000-0000-0000-0000-000000290102');
  if v_resolved.matched then
    raise exception 'FAIL: expected no match for an unconfigured customer/urgent scope';
  end if;
  raise notice 'PASS: preview_ticket_routing reports matched=false (never a hard error) when no rule covers the scope';

  -- Genuine ambiguous match: two DIFFERENT rules, identical scope, identical
  -- precedence_rank, priority='low' (isolated from every other test below).
  v_rule_a := app.create_ticket_routing_rule(v_tenant1, 'AMBIG-A', 'Ambiguous A', '00000000-0000-0000-0000-000000290102', 'staff1');
  v_rule_b := app.create_ticket_routing_rule(v_tenant1, 'AMBIG-B', 'Ambiguous B', '00000000-0000-0000-0000-000000290102', 'staff1');
  v_va := app.create_ticket_routing_rule_version(v_rule_a.id, 'internal', v_category, 'low', v_queue, 'manual', null, 7, '00000000-0000-0000-0000-000000290102', 'staff1');
  v_vb := app.create_ticket_routing_rule_version(v_rule_b.id, 'internal', v_category, 'low', v_queue, 'manual', null, 7, '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.publish_ticket_routing_rule_version(v_va.id, v_va.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.publish_ticket_routing_rule_version(v_vb.id, v_vb.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');

  begin
    perform app.preview_ticket_routing(v_tenant1, 'internal', v_category, 'low', '00000000-0000-0000-0000-000000290102');
    raise exception 'FAIL: expected ticket_routing_rule_ambiguous_match for two tying published rules';
  exception when others then
    if sqlerrm not like 'ticket_routing_rule_ambiguous_match%' then
      raise exception 'FAIL: expected ticket_routing_rule_ambiguous_match, got: %', sqlerrm;
    end if;
  end;
  raise notice 'PASS: a genuine tie between two different rules'' published versions raises ticket_routing_rule_ambiguous_match rather than picking arbitrarily';

  -- Reject helpdesk channel and invalid mode/priority at creation time.
  begin
    perform app.create_ticket_routing_rule_version(v_rule.id, 'helpdesk', null, null, v_queue, 'manual', null, 0, '00000000-0000-0000-0000-000000290102', 'staff1');
    raise exception 'FAIL: helpdesk channel should be rejected for a routing rule version';
  exception when others then
    if sqlerrm not like 'invalid_channel%' then raise exception 'FAIL: expected invalid_channel, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: routing rule versions reject channel=helpdesk (decision 2 -- no eligibility model exists for that channel)';
end;
$$;

\echo '>> 2. claim_ticket: non-member rejection, happy path, idempotent replay, ticket_already_assigned discriminated conflict; accept/decline'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'asn1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@asn1.test');
  v_ticket app.tickets;
  v_claimed app.tickets;
  v_replayed app.tickets;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Claim test ticket', 'body', 'idem-claim-1', '00000000-0000-0000-0000-000000290105', 'req1');

  begin
    perform app.claim_ticket(v_ticket.id, v_ticket.record_version, '00000000-0000-0000-0000-000000290105', 'req1');
    raise exception 'FAIL: req1 (the requester, not a queue member) should not be able to claim';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: a non-queue-member (even the ticket''s own requester) cannot claim';

  v_claimed := app.claim_ticket(v_ticket.id, v_ticket.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
  if v_claimed.assignee_employee_id <> v_staff1_emp then
    raise exception 'FAIL: expected staff1 as assignee, got %', v_claimed.assignee_employee_id;
  end if;
  if (select count(*) from app.ticket_assignment_events where ticket_id = v_ticket.id and event_type = 'claim' and source = 'claim') <> 1 then
    raise exception 'FAIL: expected exactly one claim ledger row';
  end if;
  raise notice 'PASS: an active queue member claims an unassigned ticket, logged to the ledger';

  v_replayed := app.claim_ticket(v_claimed.id, v_claimed.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
  if v_replayed.record_version <> v_claimed.record_version then
    raise exception 'FAIL: idempotent re-claim by the SAME already-assigned employee should not bump record_version';
  end if;
  if (select count(*) from app.ticket_assignment_events where ticket_id = v_ticket.id and event_type = 'claim') <> 1 then
    raise exception 'FAIL: idempotent replay must not insert a second ledger row';
  end if;
  raise notice 'PASS: idempotent replay of claim by the SAME already-assigned employee is a clean, non-duplicating no-op';

  begin
    perform app.claim_ticket(v_claimed.id, v_claimed.record_version, '00000000-0000-0000-0000-000000290103', 'staff2');
    raise exception 'FAIL: staff2 should not be able to claim an already-assigned ticket';
  exception when others then
    if sqlerrm not like 'ticket_already_assigned%' then raise exception 'FAIL: expected ticket_already_assigned, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: claiming a ticket already owned by someone else is a clean, discriminated ticket_already_assigned conflict, never a raw constraint violation';

  perform app.accept_ticket_assignment(v_claimed.id, v_claimed.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
  if (select assignment_confirmed_at from app.tickets where id = v_claimed.id) is null then
    raise exception 'FAIL: accept should have set a real assignment_confirmed_at';
  end if;
  if (select assignment_confirmed_by from app.tickets where id = v_claimed.id) <> 'staff1' then
    raise exception 'FAIL: assignment_confirmed_by should record the accepting actor';
  end if;
  raise notice 'PASS: accept_ticket_assignment has a real, tested state effect (never a ledger-only no-op)';

  -- Only the current assignee may accept/decline -- staff2 (not the
  -- assignee) is refused.
  begin
    perform app.accept_ticket_assignment(v_claimed.id, (select record_version from app.tickets where id = v_claimed.id), '00000000-0000-0000-0000-000000290103', 'staff2');
    raise exception 'FAIL: a non-assignee should not be able to accept';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm; end if;
  end;

  begin
    perform app.decline_ticket_assignment(v_claimed.id, (select record_version from app.tickets where id = v_claimed.id), null, '00000000-0000-0000-0000-000000290102', 'staff1');
    raise exception 'FAIL: decline without a reason should be rejected';
  exception when others then
    if sqlerrm not like 'reason_required%' then raise exception 'FAIL: expected reason_required, got: %', sqlerrm; end if;
  end;

  perform app.decline_ticket_assignment(v_claimed.id, (select record_version from app.tickets where id = v_claimed.id), 'too busy', '00000000-0000-0000-0000-000000290102', 'staff1');
  if (select assignee_employee_id from app.tickets where id = v_claimed.id) is not null then
    raise exception 'FAIL: decline should have cleared the assignee, returning the ticket to the queue backlog';
  end if;
  if (select assignment_confirmed_at from app.tickets where id = v_claimed.id) is not null then
    raise exception 'FAIL: decline should also clear assignment_confirmed_at';
  end if;
  if (select count(*) from app.ticket_assignment_events where ticket_id = v_claimed.id and event_type = 'decline') <> 1 then
    raise exception 'FAIL: expected exactly one decline ledger row';
  end if;
  raise notice 'PASS: decline_ticket_assignment (assignee-only, mandatory reason) clears the assignee, back to backlog, real ledger row';
end;
$$;

\echo '>> 3. eligibility: lifecycle_status and currently-dated approved leave block claim AND manual assign, with NO override on either path'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'asn1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_staff3_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff3work@asn1.test');
  v_leave_type_id uuid;
  v_ticket app.tickets;
begin
  update app.employees set lifecycle_status = 'suspended', suspend_reason = 'test suspension' where master_record_id = v_staff3_emp;
  if app._is_employee_ticket_eligible(v_tenant1, v_staff3_emp) then
    raise exception 'FAIL: a suspended employee should not be eligible for ticket assignment';
  end if;
  raise notice 'PASS: app._is_employee_ticket_eligible reads app.employees.lifecycle_status -- suspended is ineligible';
  update app.employees set lifecycle_status = 'active', suspend_reason = null where master_record_id = v_staff3_emp;

  insert into app.leave_types (tenant_id, code, name, category, status, created_by)
  values (v_tenant1, 'annual', 'Annual Leave', 'leave', 'published', 'tester')
  returning id into v_leave_type_id;

  insert into app.leave_requests (
    tenant_id, employee_id, leave_type_id, status, date_from, date_to, day_portion, total_units, reason,
    requested_by_auth_user_id, requested_by, decided_by, decided_at, decided_reason, created_by
  ) values (
    v_tenant1, v_staff3_emp, v_leave_type_id, 'approved', current_date - 1, current_date + 1, 'full_day', 3, 'vacation',
    '00000000-0000-0000-0000-000000290104', 'staff3', 'admin', now(), 'approved by tester', 'tester'
  );

  if app._is_employee_ticket_eligible(v_tenant1, v_staff3_emp) then
    raise exception 'FAIL: an employee on a currently-dated, approved leave request should not be eligible even with lifecycle_status=active';
  end if;
  raise notice 'PASS: app._is_employee_ticket_eligible reads app.leave_requests (currently-dated, approved) -- reuses existing HRIS data, never a parallel "agent status" concept';

  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Eligibility test ticket', 'body', 'idem-elig-1', '00000000-0000-0000-0000-000000290105', 'req1');

  begin
    perform app.claim_ticket(v_ticket.id, v_ticket.record_version, '00000000-0000-0000-0000-000000290104', 'staff3');
    raise exception 'FAIL: staff3 (currently on leave) should not be able to claim';
  exception when others then
    if sqlerrm not like 'employee_not_eligible%' then raise exception 'FAIL: expected employee_not_eligible, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: claim_ticket hard-blocks an ineligible employee';

  begin
    perform app.assign_ticket(v_ticket.id, v_ticket.record_version, v_staff3_emp, '00000000-0000-0000-0000-000000290102', 'staff1', 'urgent, override anyway', true);
    raise exception 'FAIL: manual assign to an on-leave employee must never be allowed, even with p_override_workload_limit=true';
  exception when others then
    if sqlerrm not like 'employee_not_eligible%' then raise exception 'FAIL: expected employee_not_eligible, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: assign_ticket also hard-blocks an ineligible employee -- eligibility has NO override on either path (decision 9), unlike the workload cap';

  delete from app.leave_requests where employee_id = v_staff3_emp;
end;
$$;

\echo '>> 4. workload cap: claim blocked with no override; manual assign blocked by default, succeeds with an explicit override'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'asn1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_staff2_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@asn1.test');
  v_rule app.ticket_routing_rules;
  v_v app.ticket_routing_rule_versions;
  t1 app.tickets; t2 app.tickets;
  v_updated app.tickets;
begin
  v_rule := app.create_ticket_routing_rule(v_tenant1, 'CAP-ROUTE', 'Capacity-capped routing', '00000000-0000-0000-0000-000000290102', 'staff1');
  v_v := app.create_ticket_routing_rule_version(v_rule.id, 'internal', v_category, 'urgent', v_queue, 'manual', 1, 10, '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.publish_ticket_routing_rule_version(v_v.id, v_v.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');

  t1 := app.create_ticket(v_tenant1, v_category, null, 'urgent', 'Cap ticket 1', 'body', 'idem-cap-1', '00000000-0000-0000-0000-000000290105', 'req1');
  t2 := app.create_ticket(v_tenant1, v_category, null, 'urgent', 'Cap ticket 2', 'body', 'idem-cap-2', '00000000-0000-0000-0000-000000290105', 'req1');

  perform app.claim_ticket(t1.id, t1.record_version, '00000000-0000-0000-0000-000000290103', 'staff2');

  begin
    perform app.claim_ticket(t2.id, t2.record_version, '00000000-0000-0000-0000-000000290103', 'staff2');
    raise exception 'FAIL: staff2 should be blocked by the workload cap (already at 1/1) on t2';
  exception when others then
    if sqlerrm not like 'workload_limit_exceeded%' then raise exception 'FAIL: expected workload_limit_exceeded, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: claim_ticket enforces the configured workload cap with NO override';

  begin
    perform app.assign_ticket(t2.id, t2.record_version, v_staff2_emp, '00000000-0000-0000-0000-000000290102', 'staff1');
    raise exception 'FAIL: assign_ticket should also be capped by default (p_override_workload_limit=false)';
  exception when others then
    if sqlerrm not like 'workload_limit_exceeded%' then raise exception 'FAIL: expected workload_limit_exceeded, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: assign_ticket enforces the same cap by default (no override)';

  v_updated := app.assign_ticket(t2.id, t2.record_version, v_staff2_emp, '00000000-0000-0000-0000-000000290102', 'staff1', 'genuinely urgent, override capacity', true);
  if v_updated.assignee_employee_id <> v_staff2_emp then
    raise exception 'FAIL: expected staff2 assigned to t2 via the explicit override';
  end if;
  if (select count(*) from app.ticket_assignment_events where ticket_id = t2.id and event_type = 'manual_assign' and reason = 'genuinely urgent, override capacity') <> 1 then
    raise exception 'FAIL: expected the override reason to be logged to the ledger';
  end if;
  raise notice 'PASS: assign_ticket honors an explicit, TKT:Assign-authorized p_override_workload_limit -- a manager''s deliberate override, never claim''s own path';
end;
$$;

\echo '>> 5. auto_route_ticket: queue selection, deterministic least-loaded pick, disclosed no-candidate outcome'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'asn1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_staff4_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff4work@asn1.test');
  v_staff5_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff5work@asn1.test');
  v_rule app.ticket_routing_rules;
  v_v app.ticket_routing_rule_versions;
  t app.tickets;
  v_routed app.tickets;
begin
  v_rule := app.create_ticket_routing_rule(v_tenant1, 'LL-ROUTE', 'Least-loaded routing', '00000000-0000-0000-0000-000000290102', 'staff1');
  v_v := app.create_ticket_routing_rule_version(v_rule.id, 'internal', v_category, 'high', v_queue, 'least_loaded', null, 10, '00000000-0000-0000-0000-000000290102', 'staff1');
  perform app.publish_ticket_routing_rule_version(v_v.id, v_v.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');

  -- No published rule matches channel=customer (GEN-ROUTE/LL-ROUTE/CAP-ROUTE
  -- are all channel=internal only, zero customer-scoped rules exist in this
  -- tenant) -- ticket_routing_rule_not_matched, a real, disclosed exception,
  -- never a silent no-op.
  declare
    v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
    v_no_match_ticket app.tickets;
    v_raised boolean := false;
  begin
    v_no_match_ticket := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'No rule match', 'body', 'idem-ll-nomatch', '00000000-0000-0000-0000-000000290110', 'customer1');
    begin
      perform app.auto_route_ticket(v_no_match_ticket.id, v_no_match_ticket.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
    exception when others then
      v_raised := true;
      if sqlerrm not like 'ticket_routing_rule_not_matched%' then raise exception 'FAIL: expected ticket_routing_rule_not_matched, got: %', sqlerrm; end if;
    end;
    if not v_raised then
      raise exception 'FAIL: expected ticket_routing_rule_not_matched for an unconfigured (customer-channel) scope';
    end if;
  end;
  raise notice 'PASS: auto_route_ticket raises a real, distinct error when no published rule matches -- never silently no-ops';

  t := app.create_ticket(v_tenant1, v_category, null, 'high', 'Auto-route ticket', 'body', 'idem-ll-1', '00000000-0000-0000-0000-000000290105', 'req1');

  -- Deterministic expectation computed BEFORE the call, the SAME way the
  -- function itself ranks candidates: least active_count, tie-broken by
  -- lexically-smallest employee_id -- never hardcoded to a subset of
  -- members, since prior sections may have left some queue members already
  -- loaded.
  declare
    v_expected_employee_id uuid;
  begin
    select m.employee_id into v_expected_employee_id
    from app.ticket_queue_members m
    where m.queue_id = v_queue and m.status = 'active' and app._is_employee_ticket_eligible(v_tenant1, m.employee_id)
    order by app._count_employee_active_ticket_assignments(v_tenant1, m.employee_id, v_queue) asc, m.employee_id asc
    limit 1;

    v_routed := app.auto_route_ticket(t.id, t.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
    if v_routed.assignee_employee_id <> v_expected_employee_id then
      raise exception 'FAIL: expected the deterministic least-loaded eligible queue member % to be picked, got %', v_expected_employee_id, v_routed.assignee_employee_id;
    end if;
  end;
  if (select count(*) from app.ticket_assignment_events where ticket_id = t.id and event_type = 'auto_route' and source = 'rule_engine') <> 1 then
    raise exception 'FAIL: expected exactly one auto_route ledger row';
  end if;
  raise notice 'PASS: auto_route_ticket (least_loaded) deterministically assigns the least-loaded eligible queue member and logs the outcome';

  -- Suspend EVERY active member of the SUP queue (staff1..staff5) so no
  -- eligible candidate remains -- auto_route_ticket must still succeed
  -- (queue selection always applies) and disclose the "no eligible
  -- candidate" outcome to the ledger rather than silently doing nothing.
  -- The routing decision this triggers (staff1 itself is a queue member,
  -- but the call is made using its own actor identity, which is only
  -- staff-authority, not itself a candidate requirement) still succeeds
  -- because is_ticket_staff authority for auto_route_ticket comes from
  -- TKT:Edit, not from being an eligible candidate.
  update app.employees set lifecycle_status = 'suspended', suspend_reason = 'test'
  where master_record_id in (
    select m.employee_id from app.ticket_queue_members m where m.queue_id = v_queue and m.status = 'active'
  );
  t := app.create_ticket(v_tenant1, v_category, null, 'high', 'Auto-route no candidate', 'body', 'idem-ll-2', '00000000-0000-0000-0000-000000290105', 'req1');
  v_routed := app.auto_route_ticket(t.id, t.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
  if v_routed.assignee_employee_id is not null then
    raise exception 'FAIL: with zero eligible candidates, auto_route_ticket must leave the ticket unassigned, not guess';
  end if;
  if (select count(*) from app.ticket_assignment_events where ticket_id = t.id and event_type = 'auto_route' and reason like 'least-loaded: no eligible%') <> 1 then
    raise exception 'FAIL: expected a disclosed "no eligible candidate" ledger row (section 18: record routing rule/version/input/result/exclusions)';
  end if;
  raise notice 'PASS: auto_route_ticket discloses a real "no eligible candidate" outcome to the ledger rather than a silent no-op';
  update app.employees set lifecycle_status = 'active', suspend_reason = null
  where master_record_id in (
    select m.employee_id from app.ticket_queue_members m where m.queue_id = v_queue and m.status = 'active'
  );
end;
$$;

\echo '>> 6. real, genuinely concurrent OS-process claim race: exactly one winner, a clean discriminated stale_version for the loser, exactly one ledger row'
select id as race_ticket_id
from app.create_ticket(
  (select id from app.tenants where slug = 'asn1'),
  (select id from app.ticket_categories where tenant_id = (select id from app.tenants where slug = 'asn1') and code = 'GENERAL'),
  null, 'normal', 'Race ticket', 'body', 'idem-race-1', '00000000-0000-0000-0000-000000290105', 'req1')
\gset

select current_database() as pg_test_db \gset

\set race_sql_a 'select app.claim_ticket(''' :race_ticket_id ''', 1, ''00000000-0000-0000-0000-000000290106'', ''staff4'');'
\set race_sql_b 'select app.claim_ticket(''' :race_ticket_id ''', 1, ''00000000-0000-0000-0000-000000290107'', ''staff5'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-assignment-claim-race-a.out
\setenv RACE_OUT_B /tmp/cargogrid-assignment-claim-race-b.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_ticket_id uuid := (select id from app.tickets where subject = 'Race ticket' and idempotency_key = 'idem-race-1');
  v_assignee uuid;
  v_claim_count integer;
begin
  select assignee_employee_id into v_assignee from app.tickets where id = v_ticket_id;
  if v_assignee is null then
    raise exception 'CRITICAL: two genuinely concurrent OS psql processes racing to claim the SAME ticket left it UNASSIGNED -- neither won';
  end if;
  if v_assignee not in (
    (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug = 'asn1') and work_email = 'staff4work@asn1.test'),
    (select master_record_id from app.employees where tenant_id = (select id from app.tenants where slug = 'asn1') and work_email = 'staff5work@asn1.test')
  ) then
    raise exception 'CRITICAL: unexpected assignee % after the claim race', v_assignee;
  end if;

  select count(*) into v_claim_count from app.ticket_assignment_events where ticket_id = v_ticket_id and event_type = 'claim';
  if v_claim_count <> 1 then
    raise exception 'CRITICAL: two genuinely concurrent OS psql processes claiming the SAME ticket produced % claim ledger rows, expected exactly 1', v_claim_count;
  end if;

  raise notice 'PASS: two genuinely concurrent OS psql processes raced to claim the SAME ticket -- exactly one won (assignee=%), exactly one claim ledger row, the loser''s own captured error is a clean stale_version/serialization_failure (see the helper''s own printed output above), never a raw constraint violation', v_assignee;
end;
$$;

\echo '>> 7. assign_ticket event-type computation (manual_assign/reassign/unassign), idempotent same-assignee replay; transfer_ticket_queue''s own widened ledger logging'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'asn1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@asn1.test');
  v_staff2_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@asn1.test');
  v_new_queue uuid;
  t app.tickets;
  v_updated app.tickets;
  v_replayed app.tickets;
begin
  t := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Reassign test ticket', 'body', 'idem-reassign-1', '00000000-0000-0000-0000-000000290105', 'req1');

  v_updated := app.assign_ticket(t.id, t.record_version, v_staff1_emp, '00000000-0000-0000-0000-000000290102', 'staff1', 'initial assignment', false);
  if (select event_type from app.ticket_assignment_events where ticket_id = t.id order by occurred_at desc limit 1) <> 'manual_assign' then
    raise exception 'FAIL: null -> staff1 should log event_type=manual_assign';
  end if;

  -- Idempotent replay: same assignee already set -> real no-op, no new ledger row.
  v_replayed := app.assign_ticket(t.id, v_updated.record_version, v_staff1_emp, '00000000-0000-0000-0000-000000290102', 'staff1');
  if v_replayed.record_version <> v_updated.record_version then
    raise exception 'FAIL: re-assigning the SAME employee should be a clean no-op, not bump record_version';
  end if;
  if (select count(*) from app.ticket_assignment_events where ticket_id = t.id) <> 1 then
    raise exception 'FAIL: idempotent same-assignee replay must not insert a second ledger row';
  end if;

  v_updated := app.assign_ticket(t.id, v_updated.record_version, v_staff2_emp, '00000000-0000-0000-0000-000000290102', 'staff1', 'reassigning to staff2', false);
  if (select event_type from app.ticket_assignment_events where ticket_id = t.id order by occurred_at desc limit 1) <> 'reassign' then
    raise exception 'FAIL: staff1 -> staff2 should log event_type=reassign';
  end if;

  v_updated := app.assign_ticket(t.id, v_updated.record_version, null, '00000000-0000-0000-0000-000000290102', 'staff1', 'unassigning', false);
  if (select event_type from app.ticket_assignment_events where ticket_id = t.id order by occurred_at desc limit 1) <> 'unassign' then
    raise exception 'FAIL: staff2 -> null should log event_type=unassign';
  end if;
  raise notice 'PASS: assign_ticket computes manual_assign/reassign/unassign from the real before/after state, and a same-assignee replay is a clean, non-duplicating no-op';

  -- transfer_ticket_queue: same signature, now ALSO logs the new ledger.
  v_new_queue := (app.create_ticket_queue(v_tenant1, (select department_org_unit_id from app.employees where master_record_id = v_staff1_emp), 'SUP2', 'Support Two', 'Second support queue', '00000000-0000-0000-0000-000000290102', 'staff1')).id;
  v_updated := app.assign_ticket(t.id, (select record_version from app.tickets where id = t.id), v_staff1_emp, '00000000-0000-0000-0000-000000290102', 'staff1', 'reassign before transfer', false);
  v_updated := app.transfer_ticket_queue(t.id, v_updated.record_version, v_new_queue, 'moving to the second queue', '00000000-0000-0000-0000-000000290102', 'staff1');
  if v_updated.queue_id <> v_new_queue or v_updated.assignee_employee_id is not null then
    raise exception 'FAIL: transfer should move the queue and clear the assignee';
  end if;
  if (select count(*) from app.ticket_assignment_events where ticket_id = t.id and event_type = 'transfer' and from_queue_id = v_queue and to_queue_id = v_new_queue) <> 1 then
    raise exception 'FAIL: expected exactly one transfer ledger row with the correct from/to queue';
  end if;
  raise notice 'PASS: transfer_ticket_queue (unchanged signature, a genuine create or replace) now also logs app.ticket_assignment_events, clears assignee AND assignment_confirmed_at/by';
end;
$$;

\echo '>> 8. cross-channel isolation: helpdesk explicitly rejected by every new RPC; customer-channel tickets route/assign staff-side normally while the customer-facing surface is refused with the identical ticket_not_found (anti-enumeration, no raw employee list)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'asn1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@asn1.test');
  v_hd app.tickets;
  v_cust app.tickets;
  v_claimed app.tickets;
  v_count integer;
begin
  v_hd := app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', 'medium', null, 'production', null, 'Helpdesk case', 'body', 'idem-hd-1', '00000000-0000-0000-0000-000000290101', 'admin');

  begin
    perform app.claim_ticket(v_hd.id, v_hd.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
    raise exception 'FAIL: claim_ticket must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'channel_not_supported%' then raise exception 'FAIL: expected channel_not_supported, got: %', sqlerrm; end if;
  end;
  begin
    perform app.assign_ticket(v_hd.id, v_hd.record_version, null, '00000000-0000-0000-0000-000000290102', 'staff1');
    raise exception 'FAIL: assign_ticket must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'channel_not_supported%' then raise exception 'FAIL: expected channel_not_supported, got: %', sqlerrm; end if;
  end;
  begin
    perform app.auto_route_ticket(v_hd.id, v_hd.record_version, '00000000-0000-0000-0000-000000290101', 'admin');
    raise exception 'FAIL: auto_route_ticket must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'channel_not_supported%' then raise exception 'FAIL: expected channel_not_supported, got: %', sqlerrm; end if;
  end;
  begin
    perform app.accept_ticket_assignment(v_hd.id, v_hd.record_version, '00000000-0000-0000-0000-000000290101', 'admin');
    raise exception 'FAIL: accept_ticket_assignment must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'channel_not_supported%' then raise exception 'FAIL: expected channel_not_supported, got: %', sqlerrm; end if;
  end;
  begin
    perform app.decline_ticket_assignment(v_hd.id, v_hd.record_version, 'nope', '00000000-0000-0000-0000-000000290101', 'admin');
    raise exception 'FAIL: decline_ticket_assignment must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'channel_not_supported%' then raise exception 'FAIL: expected channel_not_supported, got: %', sqlerrm; end if;
  end;
  begin
    perform app.list_ticket_assignment_candidates(v_hd.id, '00000000-0000-0000-0000-000000290101');
    raise exception 'FAIL: list_ticket_assignment_candidates must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: every new assignment RPC explicitly, cleanly rejects a helpdesk-channel ticket -- Supreme-Admin-gated app.assign_helpdesk_ticket/app.transfer_helpdesk_support_queue remain the ONLY helpdesk dispatch path, unmodified';

  -- Customer-channel: staff-side claim/assign work exactly like internal
  -- (decision 3) -- the customer never sees or selects an assignee, but
  -- staff routing/assignment is identical.
  v_cust := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Customer issue', 'body', 'idem-cust-1', '00000000-0000-0000-0000-000000290110', 'customer1');
  v_claimed := app.claim_ticket(v_cust.id, v_cust.record_version, '00000000-0000-0000-0000-000000290102', 'staff1');
  if v_claimed.assignee_employee_id <> v_staff1_emp then
    raise exception 'FAIL: staff-side claim must work identically for a customer-channel ticket';
  end if;
  raise notice 'PASS: customer-channel tickets route/claim/assign through the SAME staff/queue mechanism as internal (decision 3) -- confirmed live, not merely asserted';

  -- Section 16: the customer requester can never enumerate/select internal
  -- staff -- every candidate/workload/history RPC refuses them with the
  -- SAME response an RLS predicate would produce (no raw employee list, no
  -- distinguishable "you're not allowed" vs "this doesn't exist" oracle).
  begin
    select count(*) into v_count from app.list_ticket_assignment_candidates(v_cust.id, '00000000-0000-0000-0000-000000290110');
    raise exception 'FAIL: a customer_user must never enumerate assignment candidates for their own ticket';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found, got: %', sqlerrm; end if;
  end;
  begin
    select count(*) into v_count from app.list_ticket_assignment_events(v_cust.id, '00000000-0000-0000-0000-000000290110');
    raise exception 'FAIL: a customer_user must be refused (ticket_not_found), never see an empty-but-successful result, for list_ticket_assignment_events on their own ticket';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found from list_ticket_assignment_events for a customer caller, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: section 16 -- a customer requester can never enumerate or select internal/support staff identities through any new RPC, folded into the identical ticket_not_found an RLS predicate would produce';
end;
$$;

\echo '>> 9. cross-tenant isolation: RPC and raw-table RLS admit zero rows to an unrelated tenant''s admin'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'asn1');
  v_count integer;
begin
  select count(*) into v_count from app.list_ticket_routing_rules(v_tenant1, '00000000-0000-0000-0000-000000290201');
  if v_count <> 0 then
    raise exception 'CRITICAL: tenant2''s admin read tenant1''s routing rules via RPC';
  end if;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000290201", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.ticket_routing_rules where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant actor to tenant1''s ticket_routing_rules, count=%', v_count;
  end if;
  select count(*) into v_count from app.ticket_routing_rule_versions where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant actor to tenant1''s ticket_routing_rule_versions, count=%', v_count;
  end if;
  select count(*) into v_count from app.ticket_assignment_events where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant actor to tenant1''s ticket_assignment_events, count=%', v_count;
  end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  -- Tenant1's own staff cannot claim/assign/view workload for a queue that
  -- does not belong to their tenant at all (defense in depth: a forged
  -- tenant2 queue id).
  begin
    perform app.get_ticket_queue_workload('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000290102');
    raise exception 'FAIL: a nonexistent/foreign queue id should raise ticket_queue_not_found';
  exception when others then
    if sqlerrm not like 'ticket_queue_not_found%' then raise exception 'FAIL: expected ticket_queue_not_found, got: %', sqlerrm; end if;
  end;

  raise notice 'PASS: cross-tenant isolation holds via RPC and raw-table RLS for every new table';
end;
$$;

\echo '>> 10. assignment never broadens linked-record access (section 24) -- a fresh claim touches ONLY the ticket''s own assignee field, nothing else'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'asn1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_staff2_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@asn1.test');
  v_role_count_before integer;
  v_role_count_after integer;
  v_membership_count_before integer;
  v_membership_count_after integer;
  t app.tickets;
  v_other_queue uuid;
  v_other_ticket app.tickets;
begin
  select count(*) into v_role_count_before from app.role_assignments where auth_user_id = '00000000-0000-0000-0000-000000290103';
  select count(*) into v_membership_count_before from app.principal_memberships where auth_user_id = '00000000-0000-0000-0000-000000290103';

  t := app.create_ticket(v_tenant1, v_category, null, 'normal', 'No broadened access test', 'body', 'idem-noaccess-1', '00000000-0000-0000-0000-000000290105', 'req1');
  perform app.claim_ticket(t.id, t.record_version, '00000000-0000-0000-0000-000000290103', 'staff2');

  select count(*) into v_role_count_after from app.role_assignments where auth_user_id = '00000000-0000-0000-0000-000000290103';
  select count(*) into v_membership_count_after from app.principal_memberships where auth_user_id = '00000000-0000-0000-0000-000000290103';
  if v_role_count_after <> v_role_count_before or v_membership_count_after <> v_membership_count_before then
    raise exception 'CRITICAL: claiming a ticket changed staff2''s own role_assignments/principal_memberships row count -- an assignment change must touch ONLY the ticket''s own assignee field';
  end if;

  -- staff2 gains no access to a DIFFERENT queue''s ticket merely by being
  -- assigned this one -- structural scope is per-queue-membership, not
  -- inherited from any assignment elsewhere.
  v_other_queue := (app.create_ticket_queue(v_tenant1, (select department_org_unit_id from app.employees where master_record_id = v_staff2_emp), 'ISOL', 'Isolated Queue', 'no staff2 membership here', '00000000-0000-0000-0000-000000290102', 'staff1')).id;
  perform app.create_ticket_category(v_tenant1, 'ISOLCAT', 'Isolated Category', v_other_queue, '00000000-0000-0000-0000-000000290102', 'staff1');
  v_other_ticket := app.create_ticket(
    v_tenant1, (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'ISOLCAT'), v_other_queue,
    'normal', 'Isolated ticket', 'body', 'idem-noaccess-2', '00000000-0000-0000-0000-000000290105', 'req1'
  );
  begin
    perform app.claim_ticket(v_other_ticket.id, v_other_ticket.record_version, '00000000-0000-0000-0000-000000290103', 'staff2');
    raise exception 'FAIL: staff2 must not be able to claim a ticket in a queue they are not a member of, regardless of any prior claim elsewhere';
  exception when others then
    -- staff2 has zero structural relationship to this OTHER ticket (not
    -- staff, not requester, not watcher) -- app.can_access_ticket itself
    -- already returns false, folded into ticket_not_found before the more
    -- specific queue-membership check is ever reached (matches every
    -- sibling RPC''s own anti-enumeration discipline, C-05).
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found (can_access_ticket already excludes staff2 structurally), got: %', sqlerrm; end if;
  end;

  raise notice 'PASS: an assignment change broadens NOTHING beyond the ticket''s own assignee field -- no new role/membership grant, no access to an unrelated queue''s ticket (staff2 remains structurally excluded from it entirely)';
end;
$$;

\echo '>> 11. schema-privilege defense in depth: anon has zero access to any new table/function'
do $$
declare
  v_has_table_priv boolean;
  v_has_fn_priv boolean;
begin
  select bool_or(has_table_privilege('anon', t.oid, 'SELECT'))
  into v_has_table_priv
  from pg_class t
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'app' and t.relname in ('ticket_routing_rules', 'ticket_routing_rule_versions', 'ticket_assignment_events');
  if coalesce(v_has_table_priv, false) then
    raise exception 'CRITICAL: anon has SELECT on a new HRT-290 table';
  end if;

  select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
  into v_has_fn_priv
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'claim_ticket', 'accept_ticket_assignment', 'decline_ticket_assignment', 'auto_route_ticket',
      'create_ticket_routing_rule', 'create_ticket_routing_rule_version', 'publish_ticket_routing_rule_version',
      'preview_ticket_routing', 'list_ticket_routing_rules', 'list_ticket_routing_rule_versions',
      'list_ticket_assignment_candidates', 'get_ticket_queue_workload', 'list_ticket_assignment_events',
      '_is_employee_ticket_eligible', '_count_employee_active_ticket_assignments',
      '_resolve_ticket_routing_rule_for_ticket', '_apply_ticket_assignment'
    );
  if coalesce(v_has_fn_priv, false) then
    raise exception 'CRITICAL: anon has EXECUTE on a new HRT-290 function (ERR-2026-004 class -- Postgres grants EXECUTE to PUBLIC by default on function creation)';
  end if;

  -- authenticated should NOT have execute on the internal-only helpers.
  select bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  into v_has_fn_priv
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in ('_is_employee_ticket_eligible', '_count_employee_active_ticket_assignments', '_resolve_ticket_routing_rule_for_ticket', '_apply_ticket_assignment');
  if coalesce(v_has_fn_priv, false) then
    raise exception 'CRITICAL: authenticated has EXECUTE on an internal (service_role-only) HRT-290 helper function';
  end if;

  raise notice 'PASS: anon has zero table/function access to any HRT-290 object; authenticated has zero EXECUTE on the internal-only helpers';
end;
$$;

\echo '>> ticketing-assignment.sql: ALL PASSED'
