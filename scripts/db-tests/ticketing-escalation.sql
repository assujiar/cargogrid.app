-- Real, executable test evidence for HRT-291 (Ticket Escalation,
-- CG-S12-HRT-019). Run via `pnpm run db:test` against a real, disposable
-- Postgres database (and standalone via psql).
--
-- Self-contained: own two-tenant/employee/role/queue/category fixture, own
-- fresh, unclaimed UUID range (00000000-0000-0000-0000-0000002911xx /
-- ...02xx). Tenant slugs `esc1`/`esc2` (grep-verified unclaimed).
--
-- Covers, live: policy/level authoring, draft-only editing, publish
-- (completeness check, supersede-own-prior-version, genuine ambiguous-match
-- detection); manual escalation (reason-required, terminal-status block,
-- stale-version rejection, missing/ineligible-target rejection, level
-- increment, real ledger row); acknowledge (idempotent replay,
-- already-resolved rejection); suppression (authority gate, reason/expiry
-- required, already-suppressed conflict, blocks a new manual escalate,
-- expiry auto-revoke); manual resolve/de-escalate (idempotent replay);
-- SLA-breach-triggered auto-escalation via the batch evaluator, including
-- its own job-level AND ledger-level idempotent replay; inactivity-triggered
-- escalation; cooldown pacing a second level within one evaluation pass;
-- ticket-resolution auto-resolving an open escalation; a reopened ticket
-- starting a fresh escalation cycle; notification dedup (queue the same
-- escalation twice, assert exactly one app.notifications row); channel=
-- helpdesk rejection across every new RPC; cross-tenant isolation via RPC
-- and raw-table RLS; actor_holds_customer_user_layer exclusion; the
-- customer-safe is_escalated-only projection; the breach queue browser;
-- schema-privilege defense in depth (anon has zero access).

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
  v_calendar uuid; v_calendar_version uuid;
  v_sla_policy uuid; v_sla_policy_version uuid;
  v_account_a uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000291101', 'admin@esc1.test'),
    ('00000000-0000-0000-0000-000000291102', 'staff1@esc1.test'),
    ('00000000-0000-0000-0000-000000291103', 'staff2@esc1.test'),
    ('00000000-0000-0000-0000-000000291105', 'req1@esc1.test'),
    ('00000000-0000-0000-0000-000000291110', 'customer1@esc1.test'),
    ('00000000-0000-0000-0000-000000291201', 'admin@esc2.test');

  perform app.provision_tenant('esc1', 'Esc Co 1', 'idem-esc1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'esc1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('esc2', 'Esc Co 2', 'idem-esc2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'esc2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000291101', 'admin@esc1.test', 'Esc1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@esc1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000291101', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000291102', 'staff1@esc1.test', 'Esc1 Staff One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff1@esc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000291103', 'staff2@esc1.test', 'Esc1 Staff Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff2@esc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000291105', 'req1@esc1.test', 'Esc1 Requester One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'req1@esc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000291110', 'customer1@esc1.test', 'Esc1 Customer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer1@esc1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000291201', 'admin@esc2.test', 'Esc2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@esc2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000291201', 'tenant_admin', v_tenant2, null, 'tester');

  -- admin holds TKT:Edit AND TKT:Assign (policy authoring + suppression
  -- authority); staff1/staff2 hold neither, only plain queue membership.
  v_admin_role := (app.create_role(v_tenant1, 'Escalation Admin', 'TKT Edit/Assign', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Edit', 'Assign', 'Close', 'Reopen')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000291101', '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000291102', '00000000-0000-0000-0000-000000291101', 'tester');

  -- HR authority (needed only to seed the fixture's own employee drafts
  -- below via app.create_employee_draft -- unrelated to the escalation
  -- capability itself, mirrors ticketing-assignment.sql's own fixture).
  v_hr_role := (app.create_role(v_tenant1, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
  v_hr_draft := app.create_role_version(v_hr_role, 'tester');
  perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
  perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000291101', '00000000-0000-0000-0000-000000291101', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-ESC1', 'Esc1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-ESC1', 'Esc1 Branch', 'tester')).id;
  v_dept := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-SUP', 'Support', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Esc1 Admin', 'full_time', 'adminwork@esc1.test', 'adminp@esc1.test', '0900000001', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Admin', null, (select id from app.users where email = 'admin@esc1.test'), null, 'hr_created', 'idem-admin-esc1', '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@esc1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@esc1.test'), 1, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@esc1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@esc1.test'), 3, '00000000-0000-0000-0000-000000291101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Esc1 Staff One', 'full_time', 'staff1work@esc1.test', 'staff1p@esc1.test', '0900000002', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff1@esc1.test'), null, 'hr_created', 'idem-staff1-esc1', '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test'), 1, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test'), 3, '00000000-0000-0000-0000-000000291101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Esc1 Staff Two', 'full_time', 'staff2work@esc1.test', 'staff2p@esc1.test', '0900000003', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff2@esc1.test'), null, 'hr_created', 'idem-staff2-esc1', '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@esc1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@esc1.test'), 1, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@esc1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@esc1.test'), 3, '00000000-0000-0000-0000-000000291101', 'tester');

  perform app.create_employee_draft(v_tenant1, 'Esc1 Requester One', 'full_time', 'req1work@esc1.test', 'req1p@esc1.test', '0900000004', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Staff', null, (select id from app.users where email = 'req1@esc1.test'), null, 'hr_created', 'idem-req1-esc1', '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@esc1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@esc1.test'), 1, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@esc1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000291101', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@esc1.test'), 3, '00000000-0000-0000-0000-000000291101', 'tester');

  v_queue := (app.create_ticket_queue(v_tenant1, v_dept, 'SUP', 'Support', 'Support queue', '00000000-0000-0000-0000-000000291102', 'staff1')).id;
  v_category := (app.create_ticket_category(v_tenant1, 'GENERAL', 'General Issue', v_queue, '00000000-0000-0000-0000-000000291102', 'staff1')).id;
  perform app.add_ticket_queue_member(v_queue, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test'), '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.add_ticket_queue_member(v_queue, (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@esc1.test'), '00000000-0000-0000-0000-000000291102', 'staff1');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Escalation Customer A', 'fp-esc1-a', '{}'::jsonb, v_company, 'tester')
  returning id into v_account_a;
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000291110', 'customer_user', v_tenant1, v_account_a::text, 'tester');
  perform app.set_ticket_category_customer_visibility(v_category, true, '00000000-0000-0000-0000-000000291102', 'staff1');

  -- A real, published SLA policy (response target=1 minute -- deliberately
  -- tiny so app.replay_ticket_sla_clock_elapsed genuinely reports a breach
  -- without any real wall-clock wait) backing section 7's own
  -- SLA-breach-triggered escalation test below.
  v_calendar := (app.create_sla_calendar(v_tenant1, 'CAL24', '24x7 calendar', '00000000-0000-0000-0000-000000291102', 'staff1')).id;
  v_calendar_version := (app.create_sla_calendar_version(v_calendar, 'UTC', true, '00000000-0000-0000-0000-000000291102', 'staff1')).id;
  perform app.publish_sla_calendar_version(v_calendar_version, 1, '00000000-0000-0000-0000-000000291102', 'staff1');
  v_sla_policy := (app.create_sla_policy(v_tenant1, 'SLA-ESC', 'Escalation SLA', '00000000-0000-0000-0000-000000291102', 'staff1')).id;
  v_sla_policy_version := (app.create_sla_policy_version(v_sla_policy, 'internal', v_category, null, null, v_queue, null, v_calendar, 1, 2, 0, '00000000-0000-0000-0000-000000291102', 'staff1')).id;
  perform app.publish_sla_policy_version(v_sla_policy_version, 1, '00000000-0000-0000-0000-000000291102', 'staff1');

  raise notice 'fixture ready: tenant1=%, tenant2=%, queue=%, category=%, account_a=%', v_tenant1, v_tenant2, v_queue, v_category, v_account_a;
end;
$$;

\echo '>> 1. policy/level authoring: draft-only editing, publish completeness check, supersede-own-prior-version, genuine ambiguous-match, invalid-shape rejections'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test');
  v_policy app.ticket_escalation_policies;
  v_v1 app.ticket_escalation_policy_versions;
  v_v2 app.ticket_escalation_policy_versions;
  v_level1 app.ticket_escalation_levels;
  v_level1_again app.ticket_escalation_levels;
  v_resolved record;
  v_policy_a app.ticket_escalation_policies; v_policy_b app.ticket_escalation_policies;
  v_va app.ticket_escalation_policy_versions; v_vb app.ticket_escalation_policy_versions;
begin
  v_policy := app.create_ticket_escalation_policy(v_tenant1, 'GEN-ESC', 'General escalation', '00000000-0000-0000-0000-000000291102', 'staff1');
  v_v1 := app.create_ticket_escalation_policy_version(v_policy.id, 'internal', v_category, null, v_queue, 0, '00000000-0000-0000-0000-000000291102', 'staff1');

  -- Publish must fail with zero levels configured.
  begin
    perform app.publish_ticket_escalation_policy_version(v_v1.id, v_v1.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');
    raise exception 'FAIL: publishing a policy version with zero levels should be rejected';
  exception when others then
    if sqlerrm not like 'escalation_policy_incomplete%' then raise exception 'FAIL: expected escalation_policy_incomplete, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: publish rejects a policy version with no configured levels';

  v_level1 := app.add_ticket_escalation_level(v_v1.id, 1, 'inactivity', 30, null, 'employee', null, v_staff1_emp, true, false, 15, '00000000-0000-0000-0000-000000291102', 'staff1');
  if v_level1.threshold_minutes <> 30 or v_level1.target_employee_id <> v_staff1_emp then
    raise exception 'FAIL: unexpected level shape after creation';
  end if;

  -- Idempotent edit-in-place: same (version, level_number) updates, never duplicates.
  v_level1_again := app.add_ticket_escalation_level(v_v1.id, 1, 'inactivity', 45, null, 'employee', null, v_staff1_emp, true, false, 20, '00000000-0000-0000-0000-000000291102', 'staff1');
  if v_level1_again.id <> v_level1.id or v_level1_again.threshold_minutes <> 45 then
    raise exception 'FAIL: re-adding the same level_number should update in place, not create a second row';
  end if;
  if (select count(*) from app.ticket_escalation_levels where policy_version_id = v_v1.id) <> 1 then
    raise exception 'FAIL: expected exactly one level row after the idempotent edit';
  end if;
  raise notice 'PASS: add_ticket_escalation_level is a real, idempotent insert-or-update-in-place on (policy_version_id, level_number)';

  -- Reassign requires an employee target.
  begin
    perform app.add_ticket_escalation_level(v_v1.id, 2, 'priority_threshold', null, 'urgent', 'queue', v_queue, null, true, true, 30, '00000000-0000-0000-0000-000000291102', 'staff1');
    raise exception 'FAIL: action_reassign=true with a queue target should be rejected';
  exception when others then
    if sqlerrm not like 'invalid_target%' then raise exception 'FAIL: expected invalid_target, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: a queue-targeted level cannot configure action_reassign=true';

  perform app.add_ticket_escalation_level(v_v1.id, 2, 'priority_threshold', null, 'urgent', 'queue', v_queue, null, true, false, 30, '00000000-0000-0000-0000-000000291102', 'staff1');

  perform app.publish_ticket_escalation_policy_version(v_v1.id, v_v1.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');

  select * into v_resolved from app.preview_ticket_escalation(v_tenant1, 'internal', v_category, 'normal', v_queue, '00000000-0000-0000-0000-000000291102');
  if not v_resolved.matched or v_resolved.policy_version_id <> v_v1.id or v_resolved.level_count <> 2 then
    raise exception 'FAIL: expected preview to match v1 with 2 levels, got matched=%, version=%, levels=%', v_resolved.matched, v_resolved.policy_version_id, v_resolved.level_count;
  end if;
  raise notice 'PASS: preview_ticket_escalation matches the published policy version and reports its real level count';

  -- Publish a v2 -> v1 superseded, resolution now returns v2 (applied from
  -- the start, HRT-289/290's own self-found fix reused as precedent).
  v_v2 := app.create_ticket_escalation_policy_version(v_policy.id, 'internal', v_category, null, v_queue, 5, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.add_ticket_escalation_level(v_v2.id, 1, 'inactivity', 10, null, 'employee', null, v_staff1_emp, true, false, 5, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.publish_ticket_escalation_policy_version(v_v2.id, v_v2.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');
  if (select status from app.ticket_escalation_policy_versions where id = v_v1.id) <> 'superseded' then
    raise exception 'FAIL: v1 should be superseded after v2''s own publish';
  end if;
  select * into v_resolved from app.preview_ticket_escalation(v_tenant1, 'internal', v_category, 'normal', v_queue, '00000000-0000-0000-0000-000000291102');
  if v_resolved.policy_version_id <> v_v2.id then
    raise exception 'FAIL: expected v2 to be the resolved version after supersede, got %', v_resolved.policy_version_id;
  end if;
  raise notice 'PASS: publish supersedes the SAME policy''s own prior published version';

  -- Genuine ambiguous match: two DIFFERENT policies, identical scope,
  -- identical precedence_rank, priority=low (isolated from every other test).
  v_policy_a := app.create_ticket_escalation_policy(v_tenant1, 'AMBIG-A', 'Ambiguous A', '00000000-0000-0000-0000-000000291102', 'staff1');
  v_policy_b := app.create_ticket_escalation_policy(v_tenant1, 'AMBIG-B', 'Ambiguous B', '00000000-0000-0000-0000-000000291102', 'staff1');
  v_va := app.create_ticket_escalation_policy_version(v_policy_a.id, 'internal', v_category, 'low', v_queue, 7, '00000000-0000-0000-0000-000000291102', 'staff1');
  v_vb := app.create_ticket_escalation_policy_version(v_policy_b.id, 'internal', v_category, 'low', v_queue, 7, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.add_ticket_escalation_level(v_va.id, 1, 'inactivity', 10, null, 'employee', null, v_staff1_emp, true, false, 5, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.add_ticket_escalation_level(v_vb.id, 1, 'inactivity', 10, null, 'employee', null, v_staff1_emp, true, false, 5, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.publish_ticket_escalation_policy_version(v_va.id, v_va.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.publish_ticket_escalation_policy_version(v_vb.id, v_vb.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');
  begin
    perform app.preview_ticket_escalation(v_tenant1, 'internal', v_category, 'low', v_queue, '00000000-0000-0000-0000-000000291102');
    raise exception 'FAIL: expected ticket_escalation_policy_ambiguous_match for two tying published policies';
  exception when others then
    if sqlerrm not like 'ticket_escalation_policy_ambiguous_match%' then raise exception 'FAIL: expected ticket_escalation_policy_ambiguous_match, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: a genuine tie between two different policies'' published versions raises ticket_escalation_policy_ambiguous_match';

  -- Reject helpdesk channel at creation time.
  begin
    perform app.create_ticket_escalation_policy_version(v_policy.id, 'helpdesk', null, null, null, 0, '00000000-0000-0000-0000-000000291102', 'staff1');
    raise exception 'FAIL: helpdesk channel should be rejected for an escalation policy version';
  exception when others then
    if sqlerrm not like 'invalid_channel%' then raise exception 'FAIL: expected invalid_channel, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: escalation policy versions reject channel=helpdesk (decision 1)';
end;
$$;

\echo '>> 2. manual escalation: reason-required, terminal-status block, stale-version rejection, missing/ineligible-target rejection, happy path + ledger + level increment'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test');
  v_staff2_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@esc1.test');
  v_ticket app.tickets;
  v_escalation app.ticket_escalations;
  v_escalation2 app.ticket_escalations;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Manual escalate test', 'body', 'idem-manual-1', '00000000-0000-0000-0000-000000291105', 'req1');

  begin
    perform app.escalate_ticket(v_ticket.id, v_ticket.record_version, 'employee', null, v_staff1_emp, false, null, '00000000-0000-0000-0000-000000291102', 'staff1');
    raise exception 'FAIL: escalate_ticket without a reason should be rejected';
  exception when others then
    if sqlerrm not like 'reason_required%' then raise exception 'FAIL: expected reason_required, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: escalate_ticket rejects a missing/empty reason';

  begin
    perform app.escalate_ticket(v_ticket.id, v_ticket.record_version, 'employee', null, '00000000-0000-0000-0000-000000000000', false, 'needs senior attention', '00000000-0000-0000-0000-000000291102', 'staff1');
    raise exception 'FAIL: escalating to a nonexistent employee target should be rejected';
  exception when others then
    if sqlerrm not like 'escalation_target_not_eligible%' then raise exception 'FAIL: expected escalation_target_not_eligible, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: escalate_ticket rejects a missing/ineligible target (test data requirement: missing/revoked target)';

  v_escalation := app.escalate_ticket(v_ticket.id, v_ticket.record_version, 'employee', null, v_staff1_emp, false, 'needs senior attention', '00000000-0000-0000-0000-000000291102', 'staff1');
  if v_escalation.current_level <> 1 or v_escalation.status <> 'active' or v_escalation.last_trigger_type <> 'manual' then
    raise exception 'FAIL: unexpected escalation state after first manual escalate, level=%, status=%, trigger=%', v_escalation.current_level, v_escalation.status, v_escalation.last_trigger_type;
  end if;
  if (select count(*) from app.ticket_escalation_events where ticket_id = v_ticket.id and event_type = 'triggered' and level_number = 1) <> 1 then
    raise exception 'FAIL: expected exactly one triggered ledger row for level 1';
  end if;
  raise notice 'PASS: manual escalation happy path -- real level advance, real ledger row';

  -- Stale version: the ticket''s own record_version has NOT changed (escalate
  -- does not touch app.tickets), so re-supplying the ORIGINAL (now-stale
  -- relative to a concurrent caller''s expectation) version still succeeds
  -- for a genuinely fresh read -- prove staleness instead via a deliberately
  -- wrong expected_version.
  begin
    perform app.escalate_ticket(v_ticket.id, v_ticket.record_version + 99, 'employee', null, v_staff1_emp, false, 'again', '00000000-0000-0000-0000-000000291102', 'staff1');
    raise exception 'FAIL: a wrong expected_version should raise stale_version';
  exception when others then
    if sqlerrm not like 'stale_version%' then raise exception 'FAIL: expected stale_version, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: escalate_ticket enforces the ticket''s own record_version (stale-version rejection)';

  -- A second manual escalate (fresh version) advances to level 2.
  v_escalation2 := app.escalate_ticket(v_ticket.id, v_ticket.record_version, 'queue', (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP'), null, false, 'still unresolved, notify the whole queue', '00000000-0000-0000-0000-000000291102', 'staff1');
  if v_escalation2.current_level <> 2 then
    raise exception 'FAIL: expected level 2 after a second manual escalate, got %', v_escalation2.current_level;
  end if;
  if v_escalation2.record_version <= v_escalation.record_version then
    raise exception 'FAIL: expected the escalation row''s own record_version to advance';
  end if;
  raise notice 'PASS: repeated manual escalation advances the level monotonically';

  -- Terminal-status block: cancel the ticket, then a further escalate is refused.
  perform app.transition_ticket_status(v_ticket.id, (select record_version from app.tickets where id = v_ticket.id), 'cancelled', 'no longer needed', '00000000-0000-0000-0000-000000291105', 'req1');
  begin
    perform app.escalate_ticket(v_ticket.id, (select record_version from app.tickets where id = v_ticket.id), 'employee', null, v_staff1_emp, false, 'too late', '00000000-0000-0000-0000-000000291102', 'staff1');
    raise exception 'FAIL: escalating a cancelled ticket should be rejected';
  exception when others then
    if sqlerrm not like 'invalid_transition%' then raise exception 'FAIL: expected invalid_transition, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: escalate_ticket blocks a terminal-status (cancelled) ticket';
end;
$$;

\echo '>> 3. acknowledge: idempotent replay, already-resolved rejection; resolve/de-escalate: idempotent replay'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test');
  v_ticket app.tickets;
  v_escalation app.ticket_escalations;
  v_ack1 app.ticket_escalations;
  v_ack2 app.ticket_escalations;
  v_resolved1 app.ticket_escalations;
  v_resolved2 app.ticket_escalations;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Ack/resolve test', 'body', 'idem-ackres-1', '00000000-0000-0000-0000-000000291105', 'req1');
  v_escalation := app.escalate_ticket(v_ticket.id, v_ticket.record_version, 'employee', null, v_staff1_emp, false, 'please review', '00000000-0000-0000-0000-000000291102', 'staff1');

  v_ack1 := app.acknowledge_ticket_escalation(v_ticket.id, v_escalation.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');
  if v_ack1.status <> 'acknowledged' or v_ack1.acknowledged_by <> 'staff1' then
    raise exception 'FAIL: acknowledge should set status=acknowledged and record the actor';
  end if;

  v_ack2 := app.acknowledge_ticket_escalation(v_ticket.id, v_ack1.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');
  if v_ack2.record_version <> v_ack1.record_version then
    raise exception 'FAIL: re-acknowledging an already-acknowledged escalation should be a clean no-op, not bump record_version';
  end if;
  if (select count(*) from app.ticket_escalation_events where ticket_id = v_ticket.id and event_type = 'acknowledged') <> 1 then
    raise exception 'FAIL: idempotent replay must not insert a second acknowledged ledger row';
  end if;
  raise notice 'PASS: acknowledge_ticket_escalation is idempotent (C-01)';

  v_resolved1 := app.resolve_ticket_escalation(v_ticket.id, v_ack2.record_version, 'handled directly', '00000000-0000-0000-0000-000000291102', 'staff1');
  if v_resolved1.status <> 'resolved' or v_resolved1.resolved_reason <> 'manual_recovery' then
    raise exception 'FAIL: resolve should set status=resolved, resolved_reason=manual_recovery';
  end if;

  v_resolved2 := app.resolve_ticket_escalation(v_ticket.id, v_resolved1.record_version, 'again', '00000000-0000-0000-0000-000000291102', 'staff1');
  if v_resolved2.record_version <> v_resolved1.record_version then
    raise exception 'FAIL: re-resolving an already-resolved escalation should be a clean no-op';
  end if;
  if (select count(*) from app.ticket_escalation_events where ticket_id = v_ticket.id and event_type = 'recovered') <> 1 then
    raise exception 'FAIL: idempotent replay must not insert a second recovered ledger row';
  end if;
  raise notice 'PASS: resolve_ticket_escalation (manual de-escalate) is idempotent, event_type=recovered distinct from the auto-evaluator''s own event_type=resolved';

  begin
    perform app.acknowledge_ticket_escalation(v_ticket.id, v_resolved2.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');
    raise exception 'FAIL: acknowledging an already-resolved escalation should be rejected';
  exception when others then
    if sqlerrm not like 'invalid_transition%' then raise exception 'FAIL: expected invalid_transition, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: acknowledge_ticket_escalation refuses an already-resolved escalation';
end;
$$;

\echo '>> 4. suppression: authority gate, reason/expiry required, already-suppressed conflict, blocks a new manual escalate, revoke, expiry auto-revoke'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test');
  v_ticket app.tickets;
  v_suppression app.ticket_escalation_suppressions;
  v_revoked app.ticket_escalation_suppressions;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Suppression test', 'body', 'idem-suppress-1', '00000000-0000-0000-0000-000000291105', 'req1');

  -- staff2 lacks TKT:Assign -- authority gate.
  begin
    perform app.suppress_ticket_escalation(v_ticket.id, 'already handling', now() + interval '1 hour', '00000000-0000-0000-0000-000000291103', 'staff2');
    raise exception 'FAIL: a plain queue member without TKT:Assign should not be able to suppress escalation';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise exception 'FAIL: expected insufficient_authority, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: suppression requires TKT:Assign authority (a higher bar than plain staff)';

  begin
    perform app.suppress_ticket_escalation(v_ticket.id, '', now() + interval '1 hour', '00000000-0000-0000-0000-000000291101', 'admin');
    raise exception 'FAIL: an empty reason should be rejected';
  exception when others then
    if sqlerrm not like 'reason_required%' then raise exception 'FAIL: expected reason_required, got: %', sqlerrm; end if;
  end;

  begin
    perform app.suppress_ticket_escalation(v_ticket.id, 'already handling', now() - interval '1 hour', '00000000-0000-0000-0000-000000291101', 'admin');
    raise exception 'FAIL: a past expiry should be rejected';
  exception when others then
    if sqlerrm not like 'invalid_expiry%' then raise exception 'FAIL: expected invalid_expiry, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: suppression requires a real reason and a real future expiry';

  v_suppression := app.suppress_ticket_escalation(v_ticket.id, 'already handling directly', now() + interval '1 hour', '00000000-0000-0000-0000-000000291101', 'admin');

  begin
    perform app.suppress_ticket_escalation(v_ticket.id, 'again', now() + interval '2 hours', '00000000-0000-0000-0000-000000291101', 'admin');
    raise exception 'FAIL: a second suppression while one is already active should be rejected';
  exception when others then
    if sqlerrm not like 'escalation_already_suppressed%' then raise exception 'FAIL: expected escalation_already_suppressed, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: at most one active suppression per ticket -- a second attempt is a clean, discriminated conflict';

  begin
    perform app.escalate_ticket(v_ticket.id, v_ticket.record_version, 'employee', null, v_staff1_emp, false, 'need help anyway', '00000000-0000-0000-0000-000000291102', 'staff1');
    raise exception 'FAIL: manual escalation should be blocked while a real suppression is active';
  exception when others then
    if sqlerrm not like 'escalation_suppressed%' then raise exception 'FAIL: expected escalation_suppressed, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: an active suppression blocks a new manual escalation too';

  -- Never hides compliance reporting: the suppression itself IS a real,
  -- readable ledger event regardless of the suppression''s own effect.
  if (select count(*) from app.ticket_escalation_events where ticket_id = v_ticket.id and event_type = 'suppressed') <> 1 then
    raise exception 'FAIL: expected a real suppressed ledger row -- suppression must never hide compliance reporting';
  end if;

  v_revoked := app.revoke_ticket_escalation_suppression(v_ticket.id, v_suppression.id, v_suppression.record_version, 'resolved directly, lifting suppression', '00000000-0000-0000-0000-000000291101', 'admin');
  if v_revoked.revoked_at is null then
    raise exception 'FAIL: revoke should set a real revoked_at';
  end if;

  -- Idempotent revoke replay.
  if (app.revoke_ticket_escalation_suppression(v_ticket.id, v_suppression.id, v_revoked.record_version, 'again', '00000000-0000-0000-0000-000000291101', 'admin')).revoked_at <> v_revoked.revoked_at then
    raise exception 'FAIL: re-revoking an already-revoked suppression should be a clean no-op';
  end if;
  raise notice 'PASS: revoke_ticket_escalation_suppression works and is idempotent';

  -- Now escalation succeeds again (no active suppression).
  perform app.escalate_ticket(v_ticket.id, (select record_version from app.tickets where id = v_ticket.id), 'employee', null, v_staff1_emp, false, 'suppression lifted, escalating', '00000000-0000-0000-0000-000000291102', 'staff1');
  raise notice 'PASS: manual escalation succeeds again once the suppression is revoked';

  -- Suppression expiry: a fresh ticket, a suppression that already expired
  -- (backdated directly at the row level, since app.suppress_ticket_
  -- escalation itself refuses a past expiry) is auto-revoked by the NEXT
  -- check, and a new suppression may then be created.
  declare
    v_ticket2 app.tickets;
    v_stale_suppression app.ticket_escalation_suppressions;
    v_fresh_suppression app.ticket_escalation_suppressions;
  begin
    v_ticket2 := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Suppression expiry test', 'body', 'idem-suppress-expiry-1', '00000000-0000-0000-0000-000000291105', 'req1');
    v_stale_suppression := app.suppress_ticket_escalation(v_ticket2.id, 'temporary hold', now() + interval '1 hour', '00000000-0000-0000-0000-000000291101', 'admin');
    update app.ticket_escalation_suppressions set expires_at = now() - interval '1 minute' where id = v_stale_suppression.id;

    v_fresh_suppression := app.suppress_ticket_escalation(v_ticket2.id, 'a fresh suppression after the stale one expired', now() + interval '1 hour', '00000000-0000-0000-0000-000000291101', 'admin');
    if v_fresh_suppression.id = v_stale_suppression.id then
      raise exception 'FAIL: expected a genuinely NEW suppression row, not a reuse of the expired one';
    end if;
    if (select revoked_reason from app.ticket_escalation_suppressions where id = v_stale_suppression.id) <> 'expired' then
      raise exception 'FAIL: the stale suppression should have been auto-revoked with revoked_reason=expired';
    end if;
    raise notice 'PASS: an expired-but-unrevoked suppression is auto-revoked (revoked_reason=expired) the next time it is checked, and a fresh suppression may then be created';
  end;
end;
$$;

\echo '>> 5. idempotent retry (C-01/C-02): calling app._apply_ticket_escalation twice with the IDENTICAL natural key never creates a second triggered ledger row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test');
  v_ticket app.tickets;
  v_policy app.ticket_escalation_policies;
  v_version app.ticket_escalation_policy_versions;
  v_level app.ticket_escalation_levels;
  v_count integer;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Retry idempotency test', 'body', 'idem-retry-1', '00000000-0000-0000-0000-000000291105', 'req1');
  v_policy := app.create_ticket_escalation_policy(v_tenant1, 'RETRY-ESC', 'Retry escalation', '00000000-0000-0000-0000-000000291102', 'staff1');
  v_version := app.create_ticket_escalation_policy_version(v_policy.id, 'internal', v_category, 'urgent', v_queue, 20, '00000000-0000-0000-0000-000000291102', 'staff1');
  v_level := app.add_ticket_escalation_level(v_version.id, 1, 'inactivity', 5, null, 'employee', null, v_staff1_emp, false, false, 5, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.publish_ticket_escalation_policy_version(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');

  select * into v_ticket from app.tickets where id = v_ticket.id;
  update app.tickets set priority = 'urgent' where id = v_ticket.id;
  select * into v_ticket from app.tickets where id = v_ticket.id;

  perform app._apply_ticket_escalation(v_ticket, v_version.id, v_level.id, 1, 'inactivity', 'employee', null, v_staff1_emp, false, false, null, '00000000-0000-0000-0000-000000291101', 'admin', null);
  perform app._apply_ticket_escalation(v_ticket, v_version.id, v_level.id, 1, 'inactivity', 'employee', null, v_staff1_emp, false, false, null, '00000000-0000-0000-0000-000000291101', 'admin', null);

  select count(*) into v_count from app.ticket_escalation_events where ticket_id = v_ticket.id and event_type = 'triggered' and level_number = 1;
  if v_count <> 1 then
    raise exception 'CRITICAL: two identical _apply_ticket_escalation calls for the SAME natural key (ticket, policy_version, trigger_type, level_number, reopen_count) produced % triggered ledger rows, expected exactly 1', v_count;
  end if;
  raise notice 'PASS: a real retry of the exact same natural key never creates a second triggered event -- the real partial unique index + exception handler (C-01/C-02), not merely a pre-check';
end;
$$;

\echo '>> 6. SLA-breach-triggered auto-escalation via the batch evaluator: real reassignment, notification, job-level idempotent replay'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test');
  v_ticket app.tickets;
  v_clock app.ticket_sla_clocks;
  v_policy app.ticket_escalation_policies;
  v_version app.ticket_escalation_policy_versions;
  v_escalation app.ticket_escalations;
  v_triggered_count integer;
  v_batch_result record;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'high', 'SLA breach auto-escalation test', 'body', 'idem-sla-esc-1', '00000000-0000-0000-0000-000000291105', 'req1');
  v_clock := app.start_ticket_sla_clock(v_ticket.id, '00000000-0000-0000-0000-000000291102', 'staff1');
  update app.ticket_sla_clocks set started_at = now() - interval '10 minutes' where id = v_clock.id;

  perform app.run_ticket_sla_evaluation_batch(v_tenant1, now(), 'esc-sla-eval-1', '00000000-0000-0000-0000-000000291101', 'admin');
  if not exists (select 1 from app.ticket_sla_clock_events e where e.clock_id = v_clock.id and e.phase = 'response' and e.event_type = 'breached') then
    raise exception 'FAIL: expected a real SLA response-breach event to back this test';
  end if;

  -- A MORE specific policy (priority=high set) than the fixture''s own
  -- GEN-ESC v2 (priority=null) -- wins precedence for this high-priority
  -- ticket, isolating this test from section 1''s own inactivity level.
  v_policy := app.create_ticket_escalation_policy(v_tenant1, 'SLA-ESC-POLICY', 'SLA breach escalation', '00000000-0000-0000-0000-000000291102', 'staff1');
  v_version := app.create_ticket_escalation_policy_version(v_policy.id, 'internal', v_category, 'high', v_queue, 50, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.add_ticket_escalation_level(v_version.id, 1, 'sla_response_breach', null, null, 'employee', null, v_staff1_emp, true, true, 5, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.publish_ticket_escalation_policy_version(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');

  select * into v_batch_result from app.run_ticket_escalation_evaluation_batch(v_tenant1, now(), 'esc-eval-batch-1', '00000000-0000-0000-0000-000000291101', 'admin');
  if v_batch_result.evaluated_count = 0 then
    raise exception 'FAIL: expected the batch to evaluate at least one ticket';
  end if;

  select * into v_escalation from app.ticket_escalations where ticket_id = v_ticket.id;
  if v_escalation.current_level <> 1 or v_escalation.last_trigger_type <> 'sla_response_breach' or v_escalation.policy_version_id <> v_version.id then
    raise exception 'FAIL: expected the SLA-breach policy version to have triggered level 1, got level=%, trigger=%, policy_version=%', v_escalation.current_level, v_escalation.last_trigger_type, v_escalation.policy_version_id;
  end if;
  raise notice 'PASS: the batch evaluator auto-triggers escalation from a real app.ticket_sla_clock_events breach row -- the MORE specific published policy version wins precedence';

  -- action_reassign=true, target=employee -- reuses app._apply_ticket_assignment (HRT-290) directly.
  if (select assignee_employee_id from app.tickets where id = v_ticket.id) <> v_staff1_emp then
    raise exception 'FAIL: expected the ticket to be reassigned to the configured escalation target via the shared HRT-290 assignment engine';
  end if;
  if (select count(*) from app.ticket_assignment_events where ticket_id = v_ticket.id and event_type = 'reassign') <> 1 then
    raise exception 'FAIL: expected exactly one app.ticket_assignment_events row from the escalation-driven reassignment (the SAME ledger claim/assign/auto-route already write to)';
  end if;
  if (select count(*) from app.ticket_escalation_events where ticket_id = v_ticket.id and event_type = 'reassigned') <> 1 then
    raise exception 'FAIL: expected exactly one reassigned escalation-ledger row';
  end if;
  raise notice 'PASS: action_reassign fires through the shared app._apply_ticket_assignment engine -- one real state change, both ledgers updated';

  -- Job-level idempotent replay: the SAME period_label is a pending-status
  -- no-op (mirrors app.run_ticket_sla_evaluation_batch, HRT-289).
  select count(*) into v_triggered_count from app.ticket_escalation_events where ticket_id = v_ticket.id and event_type = 'triggered';
  perform app.run_ticket_escalation_evaluation_batch(v_tenant1, now(), 'esc-eval-batch-1', '00000000-0000-0000-0000-000000291101', 'admin');
  if (select count(*) from app.ticket_escalation_events where ticket_id = v_ticket.id and event_type = 'triggered') <> v_triggered_count then
    raise exception 'FAIL: replaying the SAME period_label should be a job-level no-op, not re-evaluate';
  end if;
  raise notice 'PASS: app.run_ticket_escalation_evaluation_batch is idempotent per (tenant, period_label) at the job level, mirroring app.run_ticket_sla_evaluation_batch exactly';
end;
$$;

\echo '>> 7. cooldown paces a second level within one cycle; ticket resolution/closure/cancellation auto-resolves an open escalation on the next pass (C-18); a reopened ticket starts a genuinely fresh escalation cycle'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_queue uuid := (select id from app.ticket_queues where tenant_id = v_tenant1 and code = 'SUP');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test');
  v_ticket app.tickets;
  v_policy app.ticket_escalation_policies;
  v_version app.ticket_escalation_policy_versions;
  v_level2 app.ticket_escalation_levels;
  v_escalation app.ticket_escalations;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'urgent', 'Cooldown pacing test', 'body', 'idem-cooldown-1', '00000000-0000-0000-0000-000000291105', 'req1');
  update app.tickets set updated_at = now() - interval '20 minutes' where id = v_ticket.id;

  v_policy := app.create_ticket_escalation_policy(v_tenant1, 'COOLDOWN-ESC', 'Cooldown pacing escalation', '00000000-0000-0000-0000-000000291102', 'staff1');
  v_version := app.create_ticket_escalation_policy_version(v_policy.id, 'internal', v_category, 'urgent', v_queue, 30, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.add_ticket_escalation_level(v_version.id, 1, 'inactivity', 5, null, 'employee', null, v_staff1_emp, false, false, 60, '00000000-0000-0000-0000-000000291102', 'staff1');
  v_level2 := app.add_ticket_escalation_level(v_version.id, 2, 'inactivity', 5, null, 'employee', null, v_staff1_emp, false, false, 60, '00000000-0000-0000-0000-000000291102', 'staff1');
  perform app.publish_ticket_escalation_policy_version(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000291102', 'staff1');

  perform app.run_ticket_escalation_evaluation_batch(v_tenant1, now(), 'esc-cooldown-1', '00000000-0000-0000-0000-000000291101', 'admin');
  select * into v_escalation from app.ticket_escalations where ticket_id = v_ticket.id;
  if v_escalation.current_level <> 1 then
    raise exception 'FAIL: expected level 1 to fire first, got %', v_escalation.current_level;
  end if;

  -- Immediately re-evaluate (fresh period_label so it is not a job-level
  -- no-op) -- level 1''s own 60-minute cooldown has not elapsed, so level 2
  -- must NOT fire yet.
  perform app.run_ticket_escalation_evaluation_batch(v_tenant1, now(), 'esc-cooldown-2', '00000000-0000-0000-0000-000000291101', 'admin');
  if (select current_level from app.ticket_escalations where ticket_id = v_ticket.id) <> 1 then
    raise exception 'FAIL: level 2 fired before level 1''s own cooldown elapsed -- cooldown is not load-bearing (C-20)';
  end if;
  raise notice 'PASS: cooldown_minutes genuinely paces the NEXT level -- a fresh evaluation pass within the cooldown window does not advance further';

  -- Backdate last_triggered_at past the cooldown window -> level 2 now fires.
  update app.ticket_escalations set last_triggered_at = now() - interval '61 minutes' where ticket_id = v_ticket.id;
  perform app.run_ticket_escalation_evaluation_batch(v_tenant1, now(), 'esc-cooldown-3', '00000000-0000-0000-0000-000000291101', 'admin');
  select * into v_escalation from app.ticket_escalations where ticket_id = v_ticket.id;
  if v_escalation.current_level <> 2 or v_escalation.current_level_id <> v_level2.id then
    raise exception 'FAIL: expected level 2 to fire once the cooldown window elapsed, got level %', v_escalation.current_level;
  end if;
  raise notice 'PASS: once the current level''s own cooldown elapses, the NEXT level fires on the following evaluation pass';

  -- Ticket resolution auto-resolves the open escalation (C-18) -- reusing
  -- the manually-escalated-then-cancelled ticket from section 2.
  declare
    v_cancelled_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-manual-1');
  begin
    -- This ticket's own escalation may already have been auto-resolved by
    -- an EARLIER batch pass in section 6/7 above (app.run_ticket_
    -- escalation_evaluation_batch evaluates every open-escalation ticket in
    -- the tenant on every call, not only the test's own current focus
    -- ticket) -- run one more pass regardless and assert the real,
    -- observable end state rather than an ordering assumption.
    perform app.run_ticket_escalation_evaluation_batch(v_tenant1, now(), 'esc-resolve-cancelled-1', '00000000-0000-0000-0000-000000291101', 'admin');
    if (select status from app.ticket_escalations where ticket_id = v_cancelled_ticket_id) <> 'resolved'
       or (select resolved_reason from app.ticket_escalations where ticket_id = v_cancelled_ticket_id) <> 'ticket_cancelled' then
      raise exception 'FAIL: expected the cancelled ticket''s own open escalation to be auto-resolved with resolved_reason=ticket_cancelled';
    end if;
    if not exists (select 1 from app.ticket_escalation_events where ticket_id = v_cancelled_ticket_id and event_type = 'resolved' and reason = 'ticket_cancelled') then
      raise exception 'FAIL: expected a real resolved ledger row';
    end if;
    raise notice 'PASS: a cancelled ticket''s own open escalation is auto-resolved by the evaluator on the next pass (C-18) -- event_type=resolved, distinct from the manual event_type=recovered';
  end;

  -- A reopened ticket starts a genuinely fresh cycle: the SAME natural key
  -- (policy_version, trigger_type=inactivity, level_number=1) that already
  -- fired once for this ticket is refused as a duplicate UNLESS the ticket''s
  -- own reopen_count has since advanced.
  declare
    v_fresh_ticket app.tickets;
    v_reopened_ticket app.tickets;
  begin
    select * into v_fresh_ticket from app.tickets where id = v_ticket.id;
    -- Direct retry, SAME reopen_count -- must be refused (proves the natural
    -- key, not merely demonstrated by the batch''s own level-progression
    -- logic which would not re-offer an already-passed level_number anyway).
    begin
      perform app._apply_ticket_escalation(v_fresh_ticket, v_version.id, (select current_level_id from app.ticket_escalations where ticket_id = v_ticket.id), 1, 'inactivity', 'employee', null, v_staff1_emp, false, false, null, '00000000-0000-0000-0000-000000291101', 'admin', null);
    exception when others then
      raise exception 'FAIL: _apply_ticket_escalation itself should never raise on a same-cycle replay -- it advances/updates the escalation row regardless (only the TRIGGERED ledger insert is naturally-keyed); got: %', sqlerrm;
    end;
    -- The escalation row''s own current_level was already 2 (from the
    -- cooldown test above) -- re-applying level_number=1 here is a
    -- DIFFERENT natural key than the level-1 event already on record only if
    -- reopen_count differs; same reopen_count means this call reuses the
    -- SAME (ticket, policy_version, trigger_type=inactivity, level_number=1,
    -- reopen_count) key as the very first section-7 trigger above.
    if (select count(*) from app.ticket_escalation_events where ticket_id = v_ticket.id and policy_version_id = v_version.id and trigger_type = 'inactivity' and level_number = 1) <> 1 then
      raise exception 'FAIL: a same-cycle replay of level_number=1 must not create a second triggered row for the SAME reopen_count';
    end if;

    -- Advance the ticket''s own reopen_count via a real resolve->reopen
    -- cycle, then confirm the IDENTICAL natural key now succeeds as a
    -- genuinely new row.
    perform app.transition_ticket_status(v_ticket.id, (select record_version from app.tickets where id = v_ticket.id), 'open', null, '00000000-0000-0000-0000-000000291102', 'staff1');
    perform app.transition_ticket_status(v_ticket.id, (select record_version from app.tickets where id = v_ticket.id), 'resolved', 'handled', '00000000-0000-0000-0000-000000291102', 'staff1');
    perform app.transition_ticket_status(v_ticket.id, (select record_version from app.tickets where id = v_ticket.id), 'open', 'reopening, issue recurred', '00000000-0000-0000-0000-000000291102', 'staff1');
    select * into v_reopened_ticket from app.tickets where id = v_ticket.id;
    if v_reopened_ticket.reopen_count <= v_fresh_ticket.reopen_count then
      raise exception 'FAIL: expected reopen_count to have advanced after resolve->reopen';
    end if;

    perform app._apply_ticket_escalation(v_reopened_ticket, v_version.id, (select current_level_id from app.ticket_escalations where ticket_id = v_ticket.id), 1, 'inactivity', 'employee', null, v_staff1_emp, false, false, null, '00000000-0000-0000-0000-000000291101', 'admin', null);
    if (select count(*) from app.ticket_escalation_events where ticket_id = v_ticket.id and policy_version_id = v_version.id and trigger_type = 'inactivity' and level_number = 1) <> 2 then
      raise exception 'FAIL: expected a genuinely SECOND triggered row for level_number=1 once reopen_count advanced -- a reopened ticket is honestly a new escalation cycle (decision 6)';
    end if;
    raise notice 'PASS: the natural key includes the ticket''s own reopen_count -- a reopened, re-breaching ticket starts a genuinely fresh escalation cycle rather than being permanently blocked by its own prior cycle''s history';
  end;
end;
$$;

\echo '>> 8. notification dedup: queuing the identical escalation notification twice produces exactly one app.notifications row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_config_version_id uuid;
  v_recipient uuid := '00000000-0000-0000-0000-000000291102';
  v_dedupe_key text := 'dedupe-test-ticket:1:sla_response_breach';
  v_count integer;
begin
  select v.id into v_config_version_id
  from app.config_versions v
  join app.config_objects o on o.id = v.config_object_id
  where o.config_type_code = 'notification:ticket_escalated' and v.status = 'published'
  order by v.version_number desc
  limit 1;
  if v_config_version_id is null then
    raise exception 'FAIL: expected the migration-bootstrapped, published ticket_escalated notification template to exist';
  end if;

  perform app.queue_notification(
    v_config_version_id, v_tenant1, 'ticket_escalated', v_recipient, 'in_app', 'en',
    jsonb_build_object('ticket_number', 'TKT-TEST-000001', 'escalation_level', 1, 'trigger_type', 'sla_response_breach'),
    v_dedupe_key, v_recipient, 'admin'
  );
  perform app.queue_notification(
    v_config_version_id, v_tenant1, 'ticket_escalated', v_recipient, 'in_app', 'en',
    jsonb_build_object('ticket_number', 'TKT-TEST-000001', 'escalation_level', 1, 'trigger_type', 'sla_response_breach'),
    v_dedupe_key, v_recipient, 'admin'
  );

  select count(*) into v_count from app.notifications
  where tenant_id = v_tenant1 and notification_type_code = 'ticket_escalated' and recipient_auth_user_id = v_recipient and requested_channel = 'in_app' and dedupe_key = v_dedupe_key;
  if v_count <> 1 then
    raise exception 'CRITICAL: queuing the identical escalation notification twice produced % app.notifications rows, expected exactly 1', v_count;
  end if;
  raise notice 'PASS: sequential notification dedup on (tenant, notification_type, recipient, requested_channel, dedupe_key) holds -- exactly one app.notifications row for two identical queue_notification calls (disclosed scope: this proves SEQUENTIAL dedup; app.queue_notification''s own pre-check-without-exception-handler is a pre-existing PLT-127 gap under genuine CONCURRENCY, outside this migration''s file scope, not introduced or worsened here)';

  -- The real end-to-end path (via _queue_ticket_escalation_notification, an
  -- escalation actually triggering) also produced exactly one notification
  -- row for section 6''s own SLA-breach ticket -- confirmed directly.
  select count(*) into v_count from app.notifications n
  where n.tenant_id = v_tenant1
    and n.notification_type_code = 'ticket_escalated'
    and n.dedupe_key = (select id from app.tickets where idempotency_key = 'idem-sla-esc-1')::text || ':1:sla_response_breach';
  if v_count <> 1 then
    raise exception 'FAIL: expected exactly one real escalation-driven notification row for the section-6 SLA-breach ticket, got %', v_count;
  end if;
  raise notice 'PASS: the real escalation-triggered notification path (app._queue_ticket_escalation_notification) produced exactly one app.notifications row for a genuine trigger';
end;
$$;

\echo '>> 9. cross-tenant isolation (RPC and raw-table RLS) and actor_holds_customer_user_layer exclusion'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_ticket_id uuid := (select id from app.tickets where idempotency_key = 'idem-sla-esc-1');
  v_count integer;
begin
  select count(*) into v_count from app.list_ticket_escalation_policies(v_tenant1, '00000000-0000-0000-0000-000000291201');
  if v_count <> 0 then
    raise exception 'CRITICAL: tenant2''s admin read tenant1''s escalation policies via RPC';
  end if;

  begin
    perform app.list_ticket_escalation_events(v_ticket_id, '00000000-0000-0000-0000-000000291201');
    raise exception 'FAIL: an unrelated tenant''s admin must be refused (ticket_not_found) reading escalation events for a ticket they cannot access';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found, got: %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000291201", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.ticket_escalation_policies where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant actor to tenant1''s ticket_escalation_policies, count=%', v_count;
  end if;
  select count(*) into v_count from app.ticket_escalations where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant actor to tenant1''s ticket_escalations, count=%', v_count;
  end if;
  select count(*) into v_count from app.ticket_escalation_events where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant actor to tenant1''s ticket_escalation_events, count=%', v_count;
  end if;
  select count(*) into v_count from app.ticket_escalation_suppressions where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant actor to tenant1''s ticket_escalation_suppressions, count=%', v_count;
  end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
  raise notice 'PASS: cross-tenant isolation holds via RPC and raw-table RLS for every new table';

  -- actor_holds_customer_user_layer exclusion: customer1 (a real,
  -- structurally-valid watcher/requester-side party is NOT required here --
  -- the RLS predicate excludes ANY customer_user-layer actor from these
  -- tables outright, decision 15) must read zero rows directly.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000291110", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.ticket_escalations where ticket_id = v_ticket_id;
  if v_count <> 0 then
    raise exception 'CRITICAL: a customer_user-layer actor''s raw-table read of app.ticket_escalations was not excluded by actor_holds_customer_user_layer';
  end if;
  select count(*) into v_count from app.ticket_escalation_events where ticket_id = v_ticket_id;
  if v_count <> 0 then
    raise exception 'CRITICAL: a customer_user-layer actor''s raw-table read of app.ticket_escalation_events was not excluded by actor_holds_customer_user_layer';
  end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
  raise notice 'PASS: actor_holds_customer_user_layer narrowing is applied from the start on every per-ticket escalation table (decision 15), matching every sibling table in this same phase';
end;
$$;

\echo '>> 10. channel=helpdesk rejection across every staff-facing escalation RPC'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test');
  v_hd app.tickets;
begin
  perform app.set_ticket_category_helpdesk_visibility(v_category, true, '00000000-0000-0000-0000-000000291102', 'staff1');
  v_hd := app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', 'medium', null, 'production', null, 'Helpdesk escalation test', 'body', 'idem-hd-esc-1', '00000000-0000-0000-0000-000000291101', 'admin');

  begin
    perform app.escalate_ticket(v_hd.id, v_hd.record_version, 'employee', null, v_staff1_emp, false, 'testing', '00000000-0000-0000-0000-000000291101', 'admin');
    raise exception 'FAIL: escalate_ticket must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'channel_not_supported%' then raise exception 'FAIL: expected channel_not_supported, got: %', sqlerrm; end if;
  end;
  begin
    perform app.acknowledge_ticket_escalation(v_hd.id, 1, '00000000-0000-0000-0000-000000291101', 'admin');
    raise exception 'FAIL: acknowledge_ticket_escalation must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found, got: %', sqlerrm; end if;
  end;
  begin
    perform app.suppress_ticket_escalation(v_hd.id, 'testing', now() + interval '1 hour', '00000000-0000-0000-0000-000000291101', 'admin');
    raise exception 'FAIL: suppress_ticket_escalation must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found, got: %', sqlerrm; end if;
  end;
  begin
    perform app.resolve_ticket_escalation(v_hd.id, 1, 'testing', '00000000-0000-0000-0000-000000291101', 'admin');
    raise exception 'FAIL: resolve_ticket_escalation must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found, got: %', sqlerrm; end if;
  end;
  begin
    perform app.list_ticket_escalation_events(v_hd.id, '00000000-0000-0000-0000-000000291101');
    raise exception 'FAIL: list_ticket_escalation_events must reject a helpdesk-channel ticket';
  exception when others then
    if sqlerrm not like 'channel_not_supported%' then raise exception 'FAIL: expected channel_not_supported, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: every staff-facing escalation RPC explicitly, cleanly rejects a helpdesk-channel ticket (decision 1) -- no non-Supreme-Admin escalation model exists for that channel, matching HRT-288/290''s own precedent';
end;
$$;

\echo '>> 11. breach/stuck queue browser; the customer-safe is_escalated-only projection (never internal hierarchy/target/notes)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'esc1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Escalation Customer A');
  v_staff1_emp uuid := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@esc1.test');
  v_cust_ticket app.tickets;
  v_row record;
  v_found boolean := false;
  v_status_row record;
begin
  -- Breach queue: at least the SLA-breach ticket from section 6 (still
  -- current_level=1, status=active) and the cooldown ticket from section 7
  -- (current_level=2, status=active) appear; the auto-resolved cancelled
  -- ticket from section 2/7 does NOT (status=resolved is excluded).
  for v_row in select * from app.list_ticket_breach_queue(v_tenant1, '00000000-0000-0000-0000-000000291101', null, 50, null) loop
    if v_row.ticket_number = (select ticket_number from app.tickets where idempotency_key = 'idem-sla-esc-1') then
      v_found := true;
    end if;
    if v_row.escalation_status = 'resolved' then
      raise exception 'FAIL: list_ticket_breach_queue must never include a resolved escalation';
    end if;
  end loop;
  if not v_found then
    raise exception 'FAIL: expected the section-6 SLA-breach ticket to appear in the breach queue';
  end if;
  raise notice 'PASS: list_ticket_breach_queue surfaces active/acknowledged escalations only, never resolved ones';

  -- Customer-safe status projection: a customer-channel ticket that has
  -- never been escalated reports is_escalated=false; once staff escalate it,
  -- the SAME customer sees is_escalated=true and NOTHING else (no level, no
  -- target, no trigger -- the RPC''s own return shape structurally cannot
  -- carry them).
  v_cust_ticket := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Customer escalation visibility test', 'body', 'idem-cust-esc-1', '00000000-0000-0000-0000-000000291110', 'customer1');
  select * into v_status_row from app.get_ticket_escalation_status_for_requester(v_cust_ticket.id, '00000000-0000-0000-0000-000000291110');
  if v_status_row.is_escalated is distinct from false then
    raise exception 'FAIL: expected is_escalated=false before any escalation';
  end if;

  perform app.escalate_ticket(v_cust_ticket.id, v_cust_ticket.record_version, 'employee', null, v_staff1_emp, false, 'needs priority handling', '00000000-0000-0000-0000-000000291102', 'staff1');
  select * into v_status_row from app.get_ticket_escalation_status_for_requester(v_cust_ticket.id, '00000000-0000-0000-0000-000000291110');
  if v_status_row.is_escalated is distinct from true then
    raise exception 'FAIL: expected is_escalated=true once staff escalate the ticket';
  end if;
  raise notice 'PASS: app.get_ticket_escalation_status_for_requester returns a single is_escalated boolean -- structurally incapable of carrying level/target/trigger/hierarchy (decision 12)';

  -- The same customer is refused (anti-enumeration) reading the STAFF
  -- projection or the event ledger for their own ticket.
  begin
    perform app.get_ticket_escalation(v_cust_ticket.id, '00000000-0000-0000-0000-000000291110');
    -- get_ticket_escalation is is_ticket_staff-gated and returns zero rows
    -- (not an exception) for a non-staff caller -- confirm exactly that.
  exception when others then
    raise exception 'FAIL: get_ticket_escalation should return zero rows for a non-staff caller, not raise: %', sqlerrm;
  end;
  if exists (select 1 from app.get_ticket_escalation(v_cust_ticket.id, '00000000-0000-0000-0000-000000291110')) then
    raise exception 'CRITICAL: a customer requester read the staff-only escalation projection for their own ticket';
  end if;
  begin
    perform app.list_ticket_escalation_events(v_cust_ticket.id, '00000000-0000-0000-0000-000000291110');
    raise exception 'FAIL: a customer_user must be refused (ticket_not_found) reading the escalation ledger for their own ticket';
  exception when others then
    if sqlerrm not like 'ticket_not_found%' then raise exception 'FAIL: expected ticket_not_found, got: %', sqlerrm; end if;
  end;
  raise notice 'PASS: the customer requester can never reach the staff-only escalation projection or event ledger for their own ticket';
end;
$$;

\echo '>> 12. schema-privilege defense in depth: anon has zero access to any new table/function; authenticated has zero EXECUTE on internal-only helpers'
do $$
declare
  v_has_table_priv boolean;
  v_has_fn_priv boolean;
begin
  select bool_or(has_table_privilege('anon', t.oid, 'SELECT'))
  into v_has_table_priv
  from pg_class t
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'app' and t.relname in (
    'ticket_escalation_policies', 'ticket_escalation_policy_versions', 'ticket_escalation_levels',
    'ticket_escalations', 'ticket_escalation_events', 'ticket_escalation_suppressions'
  );
  if coalesce(v_has_table_priv, false) then
    raise exception 'CRITICAL: anon has SELECT on a new HRT-291 table';
  end if;

  select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
  into v_has_fn_priv
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'escalate_ticket', 'acknowledge_ticket_escalation', 'resolve_ticket_escalation',
      'suppress_ticket_escalation', 'revoke_ticket_escalation_suppression',
      'create_ticket_escalation_policy', 'create_ticket_escalation_policy_version', 'add_ticket_escalation_level',
      'publish_ticket_escalation_policy_version', 'preview_ticket_escalation', 'run_ticket_escalation_evaluation_batch',
      'list_ticket_escalation_policies', 'list_ticket_escalation_policy_versions', 'list_ticket_escalation_levels',
      'get_ticket_escalation', 'get_ticket_escalation_status_for_requester', 'list_ticket_escalation_events',
      'list_ticket_escalation_suppressions', 'list_ticket_breach_queue',
      '_ticket_priority_rank', '_ticket_escalation_target_eligible', '_resolve_ticket_escalation_policy_version_for_ticket',
      '_apply_ticket_escalation', '_queue_ticket_escalation_notification', '_evaluate_ticket_escalation'
    );
  if coalesce(v_has_fn_priv, false) then
    raise exception 'CRITICAL: anon has EXECUTE on a new HRT-291 function (ERR-2026-004 class)';
  end if;

  select bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  into v_has_fn_priv
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      '_ticket_priority_rank', '_ticket_escalation_target_eligible', '_resolve_ticket_escalation_policy_version_for_ticket',
      '_apply_ticket_escalation', '_queue_ticket_escalation_notification', '_evaluate_ticket_escalation'
    );
  if coalesce(v_has_fn_priv, false) then
    raise exception 'CRITICAL: authenticated has EXECUTE on an internal (service_role-only) HRT-291 helper function';
  end if;

  raise notice 'PASS: anon has zero table/function access to any HRT-291 object; authenticated has zero EXECUTE on the internal-only helpers';
end;
$$;

\echo '>> ticketing-escalation.sql: ALL PASSED'
