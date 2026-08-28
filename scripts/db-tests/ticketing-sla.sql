-- Real, executable test evidence for HRT-289 (Ticket SLA and Knowledge Base,
-- CG-S12-HRT-017) -- SLA half. Run via `pnpm run db:test` against a real,
-- disposable Postgres database (and standalone via psql, per this task's own
-- ISS-2026-077 workaround instructions).
--
-- Self-contained: own two-tenant/employee/role/queue/category fixture, own
-- fresh, unclaimed UUID range (00000000-0000-0000-0000-0000002890xx). Tenant
-- slugs `sla1`/`sla2` (grep-verified unclaimed).
--
-- Covers, live: deterministic SLA policy precedence (specificity ranking,
-- genuine ambiguous-match detection); calendar business-hours/holiday
-- computation (exact-minute assertions across a weekend and a holiday);
-- clock start freezing the EXACT policy+calendar version (a later publish of
-- either never rewrites a running clock); pause/resume (allowed-reason
-- validation, invalid-state rejection); ledger replay reproducing elapsed
-- business time purely from events; reconciliation restoring the cache
-- FROM the ledger after direct corruption; response-met (derived from first
-- staff public reply) and response-breached (derived from elapsed vs.
-- target) evaluation; resolution-met/breached (derived from
-- app.tickets.resolved_at); idempotent replay of the SAME evaluation
-- (sequential AND two genuinely concurrent OS psql processes producing
-- exactly one breach row); the durable job wrapper's own idempotent replay;
-- RLS/cross-tenant isolation; a customer-safe projection leaking nothing
-- beyond target/status.

\set ON_ERROR_STOP on

\echo '>> fixture'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid; v_admin_draft app.role_versions;
  v_company uuid; v_branch uuid; v_dept uuid;
  v_admin_emp uuid; v_staff1_emp uuid; v_staff2_emp uuid; v_req1_emp uuid;
  v_queue uuid; v_category uuid;
  v_account_a uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000289001', 'admin@sla1.test'),
    ('00000000-0000-0000-0000-000000289002', 'staff1@sla1.test'),
    ('00000000-0000-0000-0000-000000289003', 'staff2@sla1.test'),
    ('00000000-0000-0000-0000-000000289004', 'req1@sla1.test'),
    ('00000000-0000-0000-0000-000000289010', 'customer1@sla1.test'),
    ('00000000-0000-0000-0000-000000289021', 'admin@sla2.test');

  perform app.provision_tenant('sla1', 'SLA Co 1', 'idem-sla1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'sla1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('sla2', 'SLA Co 2', 'idem-sla2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'sla2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289001', 'admin@sla1.test', 'Sla1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@sla1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000289001', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289002', 'staff1@sla1.test', 'Sla1 Staff One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff1@sla1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289003', 'staff2@sla1.test', 'Sla1 Staff Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff2@sla1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289004', 'req1@sla1.test', 'Sla1 Requester One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'req1@sla1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000289010', 'customer1@sla1.test', 'Sla1 Customer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer1@sla1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000289021', 'admin@sla2.test', 'Sla2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@sla2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000289021', 'tenant_admin', v_tenant2, null, 'tester');

  declare
    v_hr_role uuid; v_hr_draft app.role_versions;
  begin
    v_hr_role := (app.create_role(v_tenant1, 'HR Admin', 'HRS Create/Edit/Approve/Export/View', 'tester')).id;
    v_hr_draft := app.create_role_version(v_hr_role, 'tester');
    perform app.set_role_version_permissions(v_hr_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action in ('Create', 'Edit', 'Approve', 'Export', 'View')), 'tester');
    perform app.publish_role_version(v_hr_draft.id, now(), 'tester');
    perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_hr_role and status = 'published'), '00000000-0000-0000-0000-000000289001', '00000000-0000-0000-0000-000000289001', 'tester');
  end;

  -- TKT admin role (Edit/Close/Reopen) -- staff1 and staff2 both hold it, so
  -- either may drive SLA config/pause/resume/reconcile in the tests below.
  v_admin_role := (app.create_role(v_tenant1, 'Ticket Admin', 'TKT Edit/Close/Reopen', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'TKT' and action in ('Edit', 'Close', 'Reopen')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000289002', '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000289003', '00000000-0000-0000-0000-000000289001', 'tester');

  v_company := (app.create_org_unit(v_tenant1, 'company', null, 'CO-SLA1', 'Sla1 Co', 'tester')).id;
  v_branch := (app.create_org_unit(v_tenant1, 'branch', v_company, 'BR-SLA1', 'Sla1 Branch', 'tester')).id;
  v_dept := (app.create_org_unit(v_tenant1, 'department', v_branch, 'DEPT-SUP', 'Support', 'tester')).id;

  perform app.create_employee_draft(v_tenant1, 'Sla1 Admin', 'full_time', 'adminwork@sla1.test', 'adminp@sla1.test', '0900000001', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Admin', null, (select id from app.users where email = 'admin@sla1.test'), null, 'hr_created', 'idem-admin-sla1', '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@sla1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@sla1.test'), 1, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@sla1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@sla1.test'), 3, '00000000-0000-0000-0000-000000289001', 'tester');
  v_admin_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'adminwork@sla1.test');

  perform app.create_employee_draft(v_tenant1, 'Sla1 Staff One', 'full_time', 'staff1work@sla1.test', 'staff1p@sla1.test', '0900000002', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff1@sla1.test'), null, 'hr_created', 'idem-staff1-sla1', '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@sla1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@sla1.test'), 1, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@sla1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@sla1.test'), 3, '00000000-0000-0000-0000-000000289001', 'tester');
  v_staff1_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff1work@sla1.test');

  perform app.create_employee_draft(v_tenant1, 'Sla1 Staff Two', 'full_time', 'staff2work@sla1.test', 'staff2p@sla1.test', '0900000003', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Agent', null, (select id from app.users where email = 'staff2@sla1.test'), null, 'hr_created', 'idem-staff2-sla1', '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@sla1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@sla1.test'), 1, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@sla1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@sla1.test'), 3, '00000000-0000-0000-0000-000000289001', 'tester');
  v_staff2_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'staff2work@sla1.test');

  perform app.create_employee_draft(v_tenant1, 'Sla1 Requester One', 'full_time', 'req1work@sla1.test', 'req1p@sla1.test', '0900000004', null, null, null, '2024-01-01', v_company, v_branch, v_dept, 'Staff', null, (select id from app.users where email = 'req1@sla1.test'), null, 'hr_created', 'idem-req1-sla1', '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.add_employee_emergency_contact((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@sla1.test'), 'EC', 'spouse', '0910000000', null, true, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.submit_employee_for_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@sla1.test'), 1, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.decide_employee_approval((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@sla1.test'), 2, 'approve', null, '00000000-0000-0000-0000-000000289001', 'tester');
  perform app.activate_employee((select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@sla1.test'), 3, '00000000-0000-0000-0000-000000289001', 'tester');
  v_req1_emp := (select master_record_id from app.employees where tenant_id = v_tenant1 and work_email = 'req1work@sla1.test');

  v_queue := (app.create_ticket_queue(v_tenant1, v_dept, 'SUP', 'Support', 'Support queue', '00000000-0000-0000-0000-000000289002', 'staff1')).id;
  v_category := (app.create_ticket_category(v_tenant1, 'GENERAL', 'General Issue', v_queue, '00000000-0000-0000-0000-000000289002', 'staff1')).id;
  perform app.add_ticket_queue_member(v_queue, v_staff1_emp, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.add_ticket_queue_member(v_queue, v_staff2_emp, '00000000-0000-0000-0000-000000289002', 'staff1');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Customer Account A', 'fp-sla1-a', '{}'::jsonb, v_company, 'tester')
  returning id into v_account_a;
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000289010', 'customer_user', v_tenant1, v_account_a::text, 'tester');
  perform app.set_ticket_category_customer_visibility(v_category, true, '00000000-0000-0000-0000-000000289002', 'staff1');

  raise notice 'fixture ready: tenant1=%, tenant2=%, queue=%, category=%, account_a=%, admin_emp=%, staff1_emp=%, staff2_emp=%, req1_emp=%',
    v_tenant1, v_tenant2, v_queue, v_category, v_account_a, v_admin_emp, v_staff1_emp, v_staff2_emp, v_req1_emp;
end;
$$;

\echo '>> 1. calendar: create/publish, exact business-minutes computation across a weekend and a holiday'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_calendar app.sla_calendars;
  v_version app.sla_calendar_versions;
  v_minutes integer;
begin
  v_calendar := app.create_sla_calendar(v_tenant1, 'STD', 'Standard Business Hours', '00000000-0000-0000-0000-000000289002', 'staff1');
  v_version := app.create_sla_calendar_version(v_calendar.id, 'UTC', false, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.add_sla_calendar_business_hours(v_version.id, d::smallint, '09:00'::time, '17:00'::time, '00000000-0000-0000-0000-000000289002', 'staff1') from generate_series(1, 5) d;
  perform app.add_sla_calendar_holiday(v_version.id, date '2026-01-01', 'New Year', '00000000-0000-0000-0000-000000289002', 'staff1');

  -- Cannot publish without hours if not 24x7 -- guard, then a real draft
  -- with zero hours to prove the rejection.
  declare
    v_empty_version app.sla_calendar_versions;
  begin
    v_empty_version := app.create_sla_calendar_version(v_calendar.id, 'UTC', false, '00000000-0000-0000-0000-000000289002', 'staff1');
    begin
      perform app.publish_sla_calendar_version(v_empty_version.id, v_empty_version.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');
      raise exception 'FAIL: publishing a calendar version with zero business hours and not is_24x7 should have raised calendar_incomplete';
    exception
      when others then
        if sqlerrm not like 'calendar_incomplete%' then
          raise exception 'FAIL: expected calendar_incomplete, got: %', sqlerrm;
        end if;
    end;
  end;

  perform app.publish_sla_calendar_version(v_version.id, v_version.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

  -- Friday 2026-01-02 16:00 UTC -> Monday 2026-01-05 10:00 UTC: Fri 16:00-17:00
  -- (60 min) + Mon 09:00-10:00 (60 min) = 120 minutes. Weekend contributes 0.
  v_minutes := app.compute_sla_business_minutes(v_version.id, '2026-01-02 16:00:00+00'::timestamptz, '2026-01-05 10:00:00+00'::timestamptz);
  if v_minutes <> 120 then
    raise exception 'FAIL: expected 120 business minutes Fri16:00->Mon10:00, got %', v_minutes;
  end if;

  -- 2026-01-01 is a holiday (Thursday) -- zero business minutes that whole day.
  v_minutes := app.compute_sla_business_minutes(v_version.id, '2025-12-31 16:00:00+00'::timestamptz, '2026-01-02 10:00:00+00'::timestamptz);
  -- Wed 2025-12-31 16:00-17:00 (60) + Thu 2026-01-01 holiday (0) + Fri 2026-01-02 09:00-10:00 (60) = 120.
  if v_minutes <> 120 then
    raise exception 'FAIL: expected 120 business minutes across a holiday day (contributing 0), got %', v_minutes;
  end if;

  -- Entirely outside business hours contributes 0.
  v_minutes := app.compute_sla_business_minutes(v_version.id, '2026-01-03 01:00:00+00'::timestamptz, '2026-01-03 05:00:00+00'::timestamptz);
  if v_minutes <> 0 then
    raise exception 'FAIL: expected 0 business minutes entirely outside business hours (Saturday), got %', v_minutes;
  end if;

  raise notice 'PASS: calendar publish guard (calendar_incomplete) + exact business-minutes computation (weekend=0, holiday=0, cross-window=120)';
end;
$$;

\echo '>> 2. policy precedence: specificity ranking is deterministic; a genuine tie raises sla_policy_ambiguous_match'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_calendar_id uuid := (select id from app.sla_calendars where tenant_id = v_tenant1 and code = 'STD');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_policy_wide app.sla_policies;
  v_policy_narrow app.sla_policies;
  v_v_wide app.sla_policy_versions;
  v_v_narrow app.sla_policy_versions;
  v_resolved app.sla_policy_versions;
begin
  -- Wide policy: channel=internal only (wildcard everything else).
  v_policy_wide := app.create_sla_policy(v_tenant1, 'WIDE', 'Wide Default', '00000000-0000-0000-0000-000000289002', 'staff1');
  v_v_wide := app.create_sla_policy_version(v_policy_wide.id, 'internal', null, null, null, null, null, v_calendar_id, 240, 1440, 0, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.publish_sla_policy_version(v_v_wide.id, v_v_wide.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

  -- Narrow policy: same channel, ALSO scoped to category -- strictly more specific.
  v_policy_narrow := app.create_sla_policy(v_tenant1, 'NARROW', 'Narrow General', '00000000-0000-0000-0000-000000289002', 'staff1');
  v_v_narrow := app.create_sla_policy_version(v_policy_narrow.id, 'internal', v_category, null, null, null, null, v_calendar_id, 60, 480, 0, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.publish_sla_policy_version(v_v_narrow.id, v_v_narrow.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

  v_resolved := app.resolve_effective_sla_policy_version(v_tenant1, 'internal', v_category, 'normal', null, null, null);
  if v_resolved.id <> v_v_narrow.id then
    raise exception 'FAIL: expected the category-scoped (more specific) policy version to win, got %', v_resolved.id;
  end if;

  -- No category match: falls back to the wide policy.
  v_resolved := app.resolve_effective_sla_policy_version(v_tenant1, 'internal', null, 'normal', null, null, null);
  if v_resolved.id <> v_v_wide.id then
    raise exception 'FAIL: expected the wide policy version when category does not match narrow''s scope, got %', v_resolved.id;
  end if;

  -- Genuine tie: a SECOND channel-only-scoped policy, same specificity, same
  -- precedence_rank as v_v_wide -- resolving must RAISE, never pick silently.
  declare
    v_policy_tie app.sla_policies;
    v_v_tie app.sla_policy_versions;
  begin
    v_policy_tie := app.create_sla_policy(v_tenant1, 'TIE', 'Tied Default', '00000000-0000-0000-0000-000000289002', 'staff1');
    v_v_tie := app.create_sla_policy_version(v_policy_tie.id, 'internal', null, null, null, null, null, v_calendar_id, 300, 1500, 0, '00000000-0000-0000-0000-000000289002', 'staff1');
    perform app.publish_sla_policy_version(v_v_tie.id, v_v_tie.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

    begin
      perform app.resolve_effective_sla_policy_version(v_tenant1, 'internal', null, 'normal', null, null, null);
      raise exception 'FAIL: a genuine tie between WIDE and TIE should have raised sla_policy_ambiguous_match';
    exception
      when others then
        if sqlerrm not like 'sla_policy_ambiguous_match%' then
          raise exception 'FAIL: expected sla_policy_ambiguous_match, got: %', sqlerrm;
        end if;
    end;

    -- Give the TIE policy a distinct, higher precedence_rank -- ambiguity
    -- resolves deterministically now, never edited history, a fresh version.
    declare
      v_v_tie2 app.sla_policy_versions;
    begin
      v_v_tie2 := app.create_sla_policy_version(v_policy_tie.id, 'internal', null, null, null, null, null, v_calendar_id, 300, 1500, 10, '00000000-0000-0000-0000-000000289002', 'staff1');
      perform app.publish_sla_policy_version(v_v_tie2.id, v_v_tie2.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');
      v_resolved := app.resolve_effective_sla_policy_version(v_tenant1, 'internal', null, 'normal', null, null, null);
      if v_resolved.id <> v_v_tie2.id then
        raise exception 'FAIL: expected the higher-precedence_rank version to win once the tie is broken, got %', v_resolved.id;
      end if;
    end;
  end;

  raise notice 'PASS: deterministic specificity ranking (category-scoped beats wildcard); genuine tie raises sla_policy_ambiguous_match; explicit precedence_rank breaks a tie once assigned';
end;
$$;

\echo '>> 3. clock start freezes the EXACT policy+calendar version; a later publish of either never rewrites a running clock'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_calendar_id uuid := (select id from app.sla_calendars where tenant_id = v_tenant1 and code = 'STD');
  v_narrow_version_id uuid := (select pv.id from app.sla_policy_versions pv join app.sla_policies p on p.id = pv.policy_id where p.tenant_id = v_tenant1 and p.code = 'NARROW');
  v_calendar_v1_id uuid := (select id from app.sla_calendar_versions where calendar_id = v_calendar_id and status = 'published');
  v_ticket app.tickets;
  v_clock app.ticket_sla_clocks;
  v_clock_again app.ticket_sla_clocks;
  v_calendar_v2 app.sla_calendar_versions;
  v_new_policy_version app.sla_policy_versions;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Cannot print', 'The office printer is offline.', 'idem-sla-t1', '00000000-0000-0000-0000-000000289004', 'req1');
  v_clock := app.start_ticket_sla_clock(v_ticket.id, '00000000-0000-0000-0000-000000289002', 'staff1');

  if v_clock.sla_policy_version_id <> v_narrow_version_id then
    raise exception 'FAIL: expected clock to resolve the NARROW (category-scoped) policy version, got %', v_clock.sla_policy_version_id;
  end if;
  if v_clock.sla_calendar_version_id <> v_calendar_v1_id then
    raise exception 'FAIL: expected clock to freeze calendar version 1, got %', v_clock.sla_calendar_version_id;
  end if;
  if v_clock.response_target_minutes <> 60 or v_clock.resolution_target_minutes <> 480 then
    raise exception 'FAIL: expected targets 60/480 frozen from NARROW policy, got %/%', v_clock.response_target_minutes, v_clock.resolution_target_minutes;
  end if;

  -- Idempotent: starting again returns the SAME clock, never re-prices it.
  v_clock_again := app.start_ticket_sla_clock(v_ticket.id, '00000000-0000-0000-0000-000000289002', 'staff1');
  if v_clock_again.id <> v_clock.id then
    raise exception 'FAIL: app.start_ticket_sla_clock is not idempotent per ticket';
  end if;

  -- Publish calendar version 2 (24x7) AND a new, tighter NARROW policy
  -- version -- neither may rewrite the already-started clock.
  v_calendar_v2 := app.create_sla_calendar_version(v_calendar_id, 'UTC', true, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.publish_sla_calendar_version(v_calendar_v2.id, v_calendar_v2.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

  v_new_policy_version := app.create_sla_policy_version(
    (select policy_id from app.sla_policy_versions where id = v_narrow_version_id), 'internal', v_category, null, null, null, null, v_calendar_id, 5, 30, 0,
    '00000000-0000-0000-0000-000000289002', 'staff1'
  );
  perform app.publish_sla_policy_version(v_new_policy_version.id, v_new_policy_version.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

  select * into v_clock from app.ticket_sla_clocks where id = v_clock.id;
  if v_clock.sla_policy_version_id <> v_narrow_version_id then
    raise exception 'FAIL: publishing a NEW policy version silently rewrote a running clock''s own frozen policy version';
  end if;
  if v_clock.sla_calendar_version_id <> v_calendar_v1_id then
    raise exception 'FAIL: publishing a NEW calendar version silently rewrote a running clock''s own frozen calendar version';
  end if;
  if v_clock.response_target_minutes <> 60 then
    raise exception 'FAIL: a running clock''s own frozen response_target_minutes was rewritten (expected 60, got %)', v_clock.response_target_minutes;
  end if;
  -- The resolved "current" calendar version for the CALENDAR itself now IS
  -- v2 -- proving the publish genuinely took effect for FUTURE clocks,
  -- while this ticket's own already-started clock remains on v1.
  if (app.resolve_sla_calendar_current_version(v_calendar_id)).id <> v_calendar_v2.id then
    raise exception 'FAIL: expected the calendar''s own current published version to now be v2';
  end if;

  raise notice 'PASS: clock start resolves and freezes the exact policy+calendar version; a later publish of either never rewrites an already-started clock (live-tested both directions)';
end;
$$;

\echo '>> 4. pause/resume: allowed-reason validation, invalid-state rejection'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_ticket_id uuid := (select id from app.tickets where subject = 'Cannot print' and tenant_id = v_tenant1);
  v_clock app.ticket_sla_clocks;
begin
  select * into v_clock from app.ticket_sla_clocks where ticket_id = v_ticket_id;

  -- Invalid reason code rejected.
  begin
    perform app.pause_ticket_sla_clock(v_ticket_id, v_clock.record_version, 'made_up_reason', 'x', '00000000-0000-0000-0000-000000289002', 'staff1');
    raise exception 'FAIL: an unrecognized pause reason code should have raised invalid_pause_reason';
  exception
    when others then
      if sqlerrm not like 'invalid_pause_reason%' then
        raise exception 'FAIL: expected invalid_pause_reason, got: %', sqlerrm;
      end if;
  end;

  perform app.pause_ticket_sla_clock(v_ticket_id, v_clock.record_version, 'waiting_on_customer', 'awaiting a screenshot', '00000000-0000-0000-0000-000000289002', 'staff1');
  select * into v_clock from app.ticket_sla_clocks where ticket_id = v_ticket_id;
  if v_clock.status <> 'paused' then
    raise exception 'FAIL: expected clock status=paused, got %', v_clock.status;
  end if;

  -- Cannot pause an already-paused clock.
  begin
    perform app.pause_ticket_sla_clock(v_ticket_id, v_clock.record_version, 'waiting_on_customer', 'again', '00000000-0000-0000-0000-000000289002', 'staff1');
    raise exception 'FAIL: pausing an already-paused clock should have raised invalid_transition';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise exception 'FAIL: expected invalid_transition, got: %', sqlerrm;
      end if;
  end;

  perform app.resume_ticket_sla_clock(v_ticket_id, v_clock.record_version, '00000000-0000-0000-0000-000000289003', 'staff2');
  select * into v_clock from app.ticket_sla_clocks where ticket_id = v_ticket_id;
  if v_clock.status <> 'running' then
    raise exception 'FAIL: expected clock status=running after resume, got %', v_clock.status;
  end if;

  -- Cannot resume an already-running clock.
  begin
    perform app.resume_ticket_sla_clock(v_ticket_id, v_clock.record_version, '00000000-0000-0000-0000-000000289003', 'staff2');
    raise exception 'FAIL: resuming an already-running clock should have raised invalid_transition';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise exception 'FAIL: expected invalid_transition, got: %', sqlerrm;
      end if;
  end;

  -- The pause/resume reason text lives ONLY on the ledger, never in app.audit_logs.
  if exists (select 1 from app.audit_logs where resource_type = 'app.ticket_sla_clocks' and (reason like '%screenshot%' or after_value::text like '%screenshot%' or before_value::text like '%screenshot%')) then
    raise exception 'CRITICAL: pause reason free text leaked into app.audit_logs (C-24)';
  end if;
  if not exists (select 1 from app.ticket_sla_clock_events where clock_id = v_clock.id and event_type = 'paused' and reason like '%screenshot%') then
    raise exception 'FAIL: expected the pause reason text to be recorded on app.ticket_sla_clock_events';
  end if;

  raise notice 'PASS: pause/resume validated (allowed-reason enforcement, invalid-state rejection both directions); reason text on the ledger only, never app.audit_logs';
end;
$$;

\echo '>> 5. ledger replay + reconciliation: compliance is reproducible FROM the ledger, not the cache'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_ticket_id uuid := (select id from app.tickets where subject = 'Cannot print' and tenant_id = v_tenant1);
  v_clock app.ticket_sla_clocks;
  v_reconciled app.ticket_sla_clocks;
begin
  select * into v_clock from app.ticket_sla_clocks where ticket_id = v_ticket_id;

  -- Directly corrupt the cache (bypassing every RPC -- superuser write,
  -- simulating a hypothetical bug or manual tamper).
  update app.ticket_sla_clocks set response_status = 'breached', response_breached_at = now() where id = v_clock.id;

  -- Reconcile rebuilds PURELY from app.ticket_sla_clock_events -- since no
  -- met/breached ledger row exists yet for phase=response, it must revert
  -- the corrupted cache back to pending.
  v_reconciled := app.reconcile_ticket_sla_clock(v_clock.id, '00000000-0000-0000-0000-000000289002', 'staff1');
  if v_reconciled.response_status <> 'pending' then
    raise exception 'FAIL: reconcile did not restore the ledger-derived truth (expected pending, got %)', v_reconciled.response_status;
  end if;

  -- Replay is a pure function of the ledger: pausing/resuming excludes the
  -- paused interval from elapsed business time.
  declare
    v_elapsed_before integer;
    v_elapsed_after integer;
  begin
    v_elapsed_before := app.replay_ticket_sla_clock_elapsed(v_clock.id, now());
    if v_elapsed_before < 0 then
      raise exception 'FAIL: replayed elapsed business minutes must be non-negative';
    end if;
  end;

  raise notice 'PASS: app.reconcile_ticket_sla_clock rebuilds the cache PURELY from app.ticket_sla_clock_events, discarding a direct cache corruption';
end;
$$;

\echo '>> 6. evaluation: response-met (derived from first staff public reply), response-breached (derived from elapsed vs. target), resolution-met/breached (derived from app.tickets.resolved_at)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_ticket_met app.tickets;
  v_ticket_breach app.tickets;
  v_ticket_resolve app.tickets;
  v_clock_met app.ticket_sla_clocks;
  v_clock_breach app.ticket_sla_clocks;
  v_clock_resolve app.ticket_sla_clocks;
begin
  -- (a) Response MET: staff replies almost immediately -- elapsed-to-reply
  -- is trivially <= target regardless of real wall-clock time-of-day.
  v_ticket_met := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Response met case', 'body', 'idem-sla-met', '00000000-0000-0000-0000-000000289004', 'req1');
  v_clock_met := app.start_ticket_sla_clock(v_ticket_met.id, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.reply_to_ticket(v_ticket_met.id, 'On it, looking now.', 'public', null, null, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app._evaluate_ticket_sla_clock(v_clock_met.id, now(), null);
  select * into v_clock_met from app.ticket_sla_clocks where id = v_clock_met.id;
  if v_clock_met.response_status <> 'met' then
    raise exception 'FAIL: expected response_status=met after an immediate staff reply, got %', v_clock_met.response_status;
  end if;
  if not exists (select 1 from app.ticket_sla_clock_events where clock_id = v_clock_met.id and phase = 'response' and event_type = 'met') then
    raise exception 'FAIL: expected a response/met ledger row';
  end if;

  -- (b) Response BREACHED: backdate started_at far into the past (business
  -- time accumulated over years of Mon-Fri 09:00-17:00 vastly exceeds any
  -- target) -- deterministic regardless of real time-of-day/weekday when
  -- this test happens to run (the disclosed ISS-2026-059/077 class this
  -- task's own instructions name is exactly this kind of flakiness; this
  -- test is deliberately immune to it by using a multi-year backdate, not a
  -- tight real-time sleep window).
  v_ticket_breach := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Response breach case', 'body', 'idem-sla-breach', '00000000-0000-0000-0000-000000289004', 'req1');
  v_clock_breach := app.start_ticket_sla_clock(v_ticket_breach.id, '00000000-0000-0000-0000-000000289002', 'staff1');
  update app.ticket_sla_clocks set started_at = now() - interval '4 years' where id = v_clock_breach.id;
  update app.ticket_sla_clock_events set occurred_at = now() - interval '4 years' where clock_id = v_clock_breach.id and event_type = 'started';

  perform app._evaluate_ticket_sla_clock(v_clock_breach.id, now(), null);
  select * into v_clock_breach from app.ticket_sla_clocks where id = v_clock_breach.id;
  if v_clock_breach.response_status <> 'breached' then
    raise exception 'FAIL: expected response_status=breached after a multi-year backdated start with no reply, got %', v_clock_breach.response_status;
  end if;
  if not exists (select 1 from app.ticket_sla_clock_events where clock_id = v_clock_breach.id and phase = 'response' and event_type = 'breached') then
    raise exception 'FAIL: expected a response/breached ledger row';
  end if;

  -- (c) Resolution MET: resolve almost immediately.
  v_ticket_resolve := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Resolution met case', 'body', 'idem-sla-resolve-met', '00000000-0000-0000-0000-000000289004', 'req1');
  v_clock_resolve := app.start_ticket_sla_clock(v_ticket_resolve.id, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.reply_to_ticket(v_ticket_resolve.id, 'Fixed.', 'public', null, null, '00000000-0000-0000-0000-000000289002', 'staff1');
  v_ticket_resolve := app.transition_ticket_status(v_ticket_resolve.id, v_ticket_resolve.record_version, 'open', null, '00000000-0000-0000-0000-000000289002', 'staff1');
  v_ticket_resolve := app.transition_ticket_status(v_ticket_resolve.id, v_ticket_resolve.record_version, 'resolved', 'Restarted the print spooler.', '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app._evaluate_ticket_sla_clock(v_clock_resolve.id, now(), null);
  select * into v_clock_resolve from app.ticket_sla_clocks where id = v_clock_resolve.id;
  if v_clock_resolve.resolution_status <> 'met' then
    raise exception 'FAIL: expected resolution_status=met, got %', v_clock_resolve.resolution_status;
  end if;
  if v_clock_resolve.status <> 'completed' then
    raise exception 'FAIL: expected clock status=completed once both phases resolve (met/breached), got %', v_clock_resolve.status;
  end if;

  raise notice 'PASS: response-met/breached and resolution-met derived correctly (never a write-time hook into reply_to_ticket/transition_ticket_status -- zero modification to either function, decision 2); clock auto-completes once both phases resolve';
end;
$$;

\echo '>> 7. idempotent evaluation: sequential replay AND two genuinely concurrent OS psql processes produce EXACTLY ONE breach row (decision 6)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_ticket app.tickets;
  v_clock app.ticket_sla_clocks;
  v_breach_count integer;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Concurrency race case', 'body', 'idem-sla-race', '00000000-0000-0000-0000-000000289004', 'req1');
  v_clock := app.start_ticket_sla_clock(v_ticket.id, '00000000-0000-0000-0000-000000289002', 'staff1');
  update app.ticket_sla_clocks set started_at = now() - interval '4 years' where id = v_clock.id;
  update app.ticket_sla_clock_events set occurred_at = now() - interval '4 years' where clock_id = v_clock.id and event_type = 'started';

  -- Sequential replay first.
  perform app._evaluate_ticket_sla_clock(v_clock.id, now(), null);
  perform app._evaluate_ticket_sla_clock(v_clock.id, now(), null);
  select count(*) into v_breach_count from app.ticket_sla_clock_events where clock_id = v_clock.id and phase = 'response' and event_type = 'breached';
  if v_breach_count <> 1 then
    raise exception 'FAIL: sequential replay produced % response/breached rows, expected exactly 1', v_breach_count;
  end if;

  -- Reset for the genuine concurrency proof below: delete the breach row AND
  -- resync the cache back to pending (app.reconcile_ticket_sla_clock,
  -- decision 5 reused) -- otherwise _evaluate_ticket_sla_clock's own
  -- response_status='pending' guard would short-circuit BOTH racing
  -- processes into a no-op before either reaches the ledger insert at all,
  -- which would prove nothing about the unique-index/exception-handler
  -- guarantee under test here.
  delete from app.ticket_sla_clock_events where clock_id = v_clock.id and phase = 'response' and event_type in ('breached', 'reminder');
  perform app.reconcile_ticket_sla_clock(v_clock.id, '00000000-0000-0000-0000-000000289002', 'staff1');

  raise notice 'PASS (sequential leg): app._evaluate_ticket_sla_clock replayed twice in one session produced exactly 1 breach row; ledger reset for the real concurrency proof below (clock_id=%)', v_clock.id;
end;
$$;

select c.id as race_clock_id
from app.ticket_sla_clocks c
join app.tickets t on t.id = c.ticket_id
where t.subject = 'Concurrency race case'
\gset

select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

\set race_sql_a 'select app._evaluate_ticket_sla_clock(''' :race_clock_id ''', now(), null);'
\set race_sql_b 'select app._evaluate_ticket_sla_clock(''' :race_clock_id ''', now(), null);'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-sla-eval-race-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-sla-eval-race-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_clock_id uuid := (select c.id from app.ticket_sla_clocks c join app.tickets t on t.id = c.ticket_id where t.subject = 'Concurrency race case');
  v_breach_count integer;
begin
  select count(*) into v_breach_count from app.ticket_sla_clock_events where clock_id = v_clock_id and phase = 'response' and event_type = 'breached';
  if v_breach_count <> 1 then
    raise exception 'CRITICAL: two genuinely concurrent OS psql processes evaluating the SAME clock produced % response/breached rows, expected exactly 1 (decision 6 idempotency guarantee violated)', v_breach_count;
  end if;
  raise notice 'PASS: two genuinely concurrent OS psql processes evaluating the SAME clock produced EXACTLY ONE response/breached ledger row -- the partial unique index + real exception handler is the guarantee, not mere sequential luck';
end;
$$;

\echo '>> 8. durable job wrapper: idempotent per (tenant, period_label); a replayed period is a real no-op, never a duplicate sweep'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_result1 record;
  v_result2 record;
  v_job1 app.jobs;
  v_job2 app.jobs;
begin
  select * into v_result1 from app.run_ticket_sla_evaluation_batch(v_tenant1, now(), 'period-2026-08-14', '00000000-0000-0000-0000-000000289002', 'staff1');
  select * into v_result2 from app.run_ticket_sla_evaluation_batch(v_tenant1, now(), 'period-2026-08-14', '00000000-0000-0000-0000-000000289002', 'staff1');

  if v_result1.job_id <> v_result2.job_id then
    raise exception 'FAIL: replaying the SAME period_label should return the SAME job, got % and %', v_result1.job_id, v_result2.job_id;
  end if;
  if v_result2.evaluated_count <> 0 then
    raise exception 'FAIL: replaying an already-completed period should evaluate ZERO clocks the second time, got %', v_result2.evaluated_count;
  end if;

  select * into v_job1 from app.jobs where job_id = v_result1.job_id;
  if v_job1.status <> 'completed' then
    raise exception 'FAIL: expected job status=completed, got %', v_job1.status;
  end if;

  raise notice 'PASS: app.run_ticket_sla_evaluation_batch is idempotent per (tenant, period_label) at the job level -- % clocks evaluated on first run, 0 on replay', v_result1.evaluated_count;
end;
$$;

\echo '>> 9. customer-safe projection leaks nothing beyond target/status; staff-only ledger stays staff-only; RLS/cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'sla2');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_ticket app.tickets;
  v_clock app.ticket_sla_clocks;
  v_row record;
  v_count integer;
begin
  v_ticket := app.create_ticket(v_tenant1, v_category, null, 'normal', 'Customer-safe projection case', 'body', 'idem-sla-custsafe', '00000000-0000-0000-0000-000000289004', 'req1');
  v_clock := app.start_ticket_sla_clock(v_ticket.id, '00000000-0000-0000-0000-000000289002', 'staff1');

  -- The requester's own employee (req1) is NOT staff -- reuses
  -- app.get_ticket_sla_status_for_requester, never the full projection.
  select count(*) into v_count from app.get_ticket_sla_clock(v_ticket.id, '00000000-0000-0000-0000-000000289004');
  if v_count <> 0 then
    raise exception 'FAIL: a non-staff requester should get ZERO rows from the staff-only app.get_ticket_sla_clock';
  end if;

  select * into v_row from app.get_ticket_sla_status_for_requester(v_ticket.id, '00000000-0000-0000-0000-000000289004');
  if v_row.response_target_minutes <> v_clock.response_target_minutes or v_row.response_status is distinct from v_clock.response_status then
    raise exception 'FAIL: requester-safe projection does not even match the clock''s own target/status';
  end if;

  select count(*) into v_count from app.list_ticket_sla_clock_events(v_ticket.id, '00000000-0000-0000-0000-000000289004');
  if v_count <> 0 then
    raise exception 'FAIL: a non-staff requester should get ZERO rows from the staff-only app.list_ticket_sla_clock_events';
  end if;

  -- Staff sees the full projection.
  select count(*) into v_count from app.get_ticket_sla_clock(v_ticket.id, '00000000-0000-0000-0000-000000289002');
  if v_count <> 1 then
    raise exception 'FAIL: staff should see the full SLA clock projection';
  end if;

  -- Cross-tenant: tenant2's admin cannot resolve anything for tenant1's
  -- clock/policy/calendar via any RPC.
  select count(*) into v_count from app.list_sla_calendars(v_tenant1, '00000000-0000-0000-0000-000000289021');
  if v_count <> 0 then
    raise exception 'CRITICAL: tenant2 admin read tenant1''s SLA calendars';
  end if;
  select count(*) into v_count from app.get_ticket_sla_clock(v_ticket.id, '00000000-0000-0000-0000-000000289021');
  if v_count <> 0 then
    raise exception 'CRITICAL: tenant2 admin read tenant1''s ticket SLA clock';
  end if;

  -- RLS as a real forged session (request.jwt.claims + set role
  -- authenticated, the same technique every db-test file in this repository
  -- uses): the ticket's own staff (staff1) sees the raw clock/ledger rows;
  -- an unrelated tenant2 admin sees NOTHING via raw table either.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000289002", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.ticket_sla_clocks where id = v_clock.id;
  if v_count <> 1 then
    raise exception 'FAIL: ticket staff should see their own ticket''s SLA clock via raw-table RLS';
  end if;
  select count(*) into v_count from app.ticket_sla_clock_events where clock_id = v_clock.id;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000289021", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.ticket_sla_clocks where id = v_clock.id;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant (tenant2) actor to tenant1''s SLA clock, count=%', v_count;
  end if;
  select count(*) into v_count from app.sla_policies where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted a cross-tenant (tenant2) actor to tenant1''s SLA policies';
  end if;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);

  raise notice 'PASS: customer/requester-safe projection carries only target/status (no calendar/policy identity); staff-only ledger/full projection refuse non-staff; RLS admits zero cross-tenant rows on any SLA table';
end;
$$;

\echo '>> 10. schema-privilege defense in depth: anon has zero access to any SLA table/function'
do $$
declare
  v_has_table_priv boolean;
begin
  select bool_or(has_table_privilege('anon', format('app.%I', t), 'SELECT')) into v_has_table_priv
  from unnest(array['sla_calendars', 'sla_calendar_versions', 'sla_policies', 'sla_policy_versions', 'ticket_sla_clocks', 'ticket_sla_clock_events']) as t;
  if v_has_table_priv then
    raise exception 'CRITICAL: anon has SELECT on at least one SLA table';
  end if;
  raise notice 'PASS: anon has zero SELECT privilege on any SLA table';
end;
$$;

\echo '>> 11. reachability sweep (C-02 defense): every RETURNS TABLE function is actually CALLED live, never merely read as SQL'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_calendar_id uuid := (select id from app.sla_calendars where tenant_id = v_tenant1 and code = 'STD');
  v_policy_id uuid := (select id from app.sla_policies where tenant_id = v_tenant1 and code = 'NARROW');
  v_ticket_id uuid := (select id from app.tickets where subject = 'Customer-safe projection case' and tenant_id = v_tenant1);
  v_n integer;
begin
  select count(*) into v_n from app.list_sla_calendar_versions(v_calendar_id, '00000000-0000-0000-0000-000000289002');
  if v_n < 1 then raise exception 'FAIL: app.list_sla_calendar_versions returned no rows for a calendar with versions'; end if;

  select count(*) into v_n from app.list_sla_policies(v_tenant1, '00000000-0000-0000-0000-000000289002');
  if v_n < 1 then raise exception 'FAIL: app.list_sla_policy returned no rows'; end if;

  select count(*) into v_n from app.list_sla_policy_versions(v_policy_id, '00000000-0000-0000-0000-000000289002');
  if v_n < 1 then raise exception 'FAIL: app.list_sla_policy_versions returned no rows'; end if;

  select count(*) into v_n from app.list_ticket_sla_events_for_requester(v_ticket_id, '00000000-0000-0000-0000-000000289004');
  if v_n <> 0 then raise exception 'FAIL: expected zero met/breached events yet for this fresh ticket, got %', v_n; end if;

  raise notice 'PASS: every SLA RETURNS TABLE function reachable live, no ambiguous-id crash, sane row counts';
end;
$$;

\echo '>> 12. PLT-132 (HRT-295, CG-S12-HRT-023): a genuine per-clock evaluation failure is durably recorded and the batch job still reaches completed -- the OTHER clock in the SAME run still evaluates correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_ticket_bad app.tickets;
  v_ticket_good app.tickets;
  v_clock_bad app.ticket_sla_clocks;
  v_clock_good app.ticket_sla_clocks;
  v_result record;
  v_job app.jobs;
  v_audit_count integer;
  v_audit app.audit_logs;
begin
  v_ticket_bad := app.create_ticket(v_tenant1, v_category, null, 'normal', 'PLT-132 stale clock', 'body', 'idem-plt132-sla-bad', '00000000-0000-0000-0000-000000289004', 'req1');
  v_clock_bad := app.start_ticket_sla_clock(v_ticket_bad.id, '00000000-0000-0000-0000-000000289002', 'staff1');

  -- A real, valid timestamptz -- not corrupted data, simply a clock that has
  -- legitimately been left "running" for years (e.g. an old ticket whose
  -- clock was never properly closed before a fresh evaluation sweep runs
  -- over every still-open clock). app.compute_sla_business_minutes' own
  -- disclosed 5-year business-minutes bound (sla_range_too_large,
  -- 20260731120000) genuinely raises when asked to walk a span this wide --
  -- no timeout/mocking/corruption involved anywhere, and no CHECK constraint
  -- bounds started_at, so this UPDATE is itself a completely ordinary,
  -- legal write.
  update app.ticket_sla_clocks set started_at = now() - interval '6 years' where id = v_clock_bad.id;

  v_ticket_good := app.create_ticket(v_tenant1, v_category, null, 'normal', 'PLT-132 healthy clock', 'body', 'idem-plt132-sla-good', '00000000-0000-0000-0000-000000289004', 'req1');
  v_clock_good := app.start_ticket_sla_clock(v_ticket_good.id, '00000000-0000-0000-0000-000000289002', 'staff1');

  select * into v_result from app.run_ticket_sla_evaluation_batch(v_tenant1, now(), 'period-plt132-hrt295', '00000000-0000-0000-0000-000000289002', 'staff1');

  -- Before the HRT-295 fix, app._evaluate_ticket_sla_clock's own uncaught
  -- sla_range_too_large exception for v_clock_bad would have rolled back
  -- this ENTIRE transaction, including app.enqueue_job's own earlier INSERT
  -- -- HRT-294's own live reproduction found the job row simply gone
  -- afterward (neither pending nor dead_letter). Assert a REAL, terminal,
  -- non-lost row instead.
  select * into v_job from app.jobs where job_id = v_result.job_id;
  if v_job.job_id is null then
    raise exception 'CRITICAL (PLT-132 regression): the batch job row was lost entirely after a genuine per-clock failure -- exactly HRT-294''s own live-reproduced defect';
  end if;
  if v_job.status <> 'completed' then
    raise exception 'FAIL: expected the job to reach completed even with one genuinely failing clock, got %', v_job.status;
  end if;

  -- The healthy clock must still have been evaluated correctly in the SAME
  -- run -- one bad clock must never take the rest of the batch down with it.
  if (select last_evaluated_at from app.ticket_sla_clocks where id = v_clock_good.id) is null then
    raise exception 'FAIL: the healthy clock was not marked evaluated even though its own sibling clock genuinely failed';
  end if;

  -- Real, durable, FINDABLE evidence of the specific failure -- queryable
  -- straight out of app.audit_logs, never merely a silent skip/counter.
  select count(*) into v_audit_count
  from app.audit_logs
  where action = 'run_ticket_sla_evaluation_batch_item_failed'
    and resource_type = 'app.ticket_sla_clocks'
    and resource_id = v_clock_bad.id
    and result = 'failure';
  if v_audit_count <> 1 then
    raise exception 'FAIL: expected exactly one durable, findable failure audit row for the genuinely failing clock, got %', v_audit_count;
  end if;

  select * into v_audit from app.audit_logs
  where action = 'run_ticket_sla_evaluation_batch_item_failed' and resource_id = v_clock_bad.id;
  if v_audit.reason is null or v_audit.reason not like '%sla_range_too_large%' then
    raise exception 'FAIL: expected the durable failure record to carry the REAL error detail (sla_range_too_large), got %', v_audit.reason;
  end if;
  if (v_audit.after_value ->> 'job_id')::uuid <> v_job.job_id then
    raise exception 'FAIL: the durable failure record must correlate back to the same job_id';
  end if;

  raise notice 'PASS (PLT-132/HRT-295): a genuine per-clock failure (sla_range_too_large) no longer loses the batch job row -- it reaches completed, the healthy clock in the same run still evaluates correctly, and the failure itself is durably recorded and findable in app.audit_logs with real error detail';
end;
$$;

\echo '>> 13. ISS-2026-090 regression: real customer- and helpdesk-channel tickets drive the SLA engine''s own customer_account_id/support_queue_id specificity dimensions and RLS/RPC boundary paths (every test above exercised app.create_ticket -- internal channel -- exclusively; app.sla_policy_versions.channel and app.resolve_effective_sla_policy_version''s own customer_account_id/support_queue_id ranking dimensions were live but never once driven by a real non-internal ticket)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'sla1');
  v_category uuid := (select id from app.ticket_categories where tenant_id = v_tenant1 and code = 'GENERAL');
  v_account_a uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Customer Account A');
  v_calendar_id uuid := (select id from app.sla_calendars where tenant_id = v_tenant1 and code = 'STD');
  v_customer1 uuid := '00000000-0000-0000-0000-000000289010';
  v_customer2 uuid := '00000000-0000-0000-0000-000000289011';
  v_supreme uuid := '00000000-0000-0000-0000-000000289090';
  v_policy_cust_wide app.sla_policies;
  v_v_cust_wide app.sla_policy_versions;
  v_policy_cust_acct app.sla_policies;
  v_v_cust_acct app.sla_policy_versions;
  v_policy_hd_wide app.sla_policies;
  v_v_hd_wide app.sla_policy_versions;
  v_policy_hd_queue app.sla_policies;
  v_v_hd_queue app.sla_policy_versions;
  v_support_queue uuid;
  v_ticket_cust1 app.tickets;
  v_ticket_cust2 app.tickets;
  v_ticket_hd1 app.tickets;
  v_ticket_hd2 app.tickets;
  v_clock_cust1 app.ticket_sla_clocks;
  v_clock_cust2 app.ticket_sla_clocks;
  v_clock_hd1 app.ticket_sla_clocks;
  v_clock_hd2 app.ticket_sla_clocks;
  v_row record;
  v_count integer;
begin
  -- A second, unaffiliated customer identity -- holds no principal_membership
  -- on ANY account -- for the RLS/RPC boundary checks below (customer1 alone,
  -- reused from the fixture, cannot exercise a genuine "not your account"
  -- denial against itself).
  insert into auth.users (id, email) values (v_customer2, 'customer2@sla1.test');
  perform app.invite_user(v_tenant1, v_customer2, 'customer2@sla1.test', 'Sla1 Customer Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer2@sla1.test'), 'active', 'onboarded', 'tester');

  -- A real Supreme Admin -- Platform-side helpdesk-triage authority, needed
  -- to assign a real app.support_queues row (mirrors ticketing-helpdesk.sql's
  -- own fixture pattern; 'SQ-SLA090' is a fresh, unclaimed support_queues
  -- code -- app.support_queues is Platform-global, not tenant-scoped, so its
  -- code must be unique across every db-test file in this same run).
  insert into auth.users (id, email) values (v_supreme, 'supreme@sla1-090.test');
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.set_ticket_category_helpdesk_visibility(v_category, true, '00000000-0000-0000-0000-000000289002', 'staff1');

  -- --- Customer channel: wildcard vs. customer_account_id-scoped precedence ---

  v_policy_cust_wide := app.create_sla_policy(v_tenant1, 'CUSTWIDE', 'Customer Wide Default', '00000000-0000-0000-0000-000000289002', 'staff1');
  v_v_cust_wide := app.create_sla_policy_version(v_policy_cust_wide.id, 'customer', null, null, null, null, null, v_calendar_id, 180, 720, 0, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.publish_sla_policy_version(v_v_cust_wide.id, v_v_cust_wide.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

  v_ticket_cust1 := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Customer wide-policy case', 'body', 'idem-sla090-cust1', v_customer1, 'customer1');
  v_clock_cust1 := app.start_ticket_sla_clock(v_ticket_cust1.id, v_customer1, 'customer1');
  if v_clock_cust1.sla_policy_version_id <> v_v_cust_wide.id then
    raise exception 'FAIL: expected the customer-channel ticket to match the wildcard customer-channel SLA policy, got version %', v_clock_cust1.sla_policy_version_id;
  end if;
  if v_clock_cust1.response_target_minutes <> 180 or v_clock_cust1.resolution_target_minutes <> 720 then
    raise exception 'FAIL: unexpected customer-channel wildcard-policy targets, got response=% resolution=%', v_clock_cust1.response_target_minutes, v_clock_cust1.resolution_target_minutes;
  end if;

  -- A MORE SPECIFIC policy scoped to this exact customer_account_id --
  -- resolve_effective_sla_policy_version's own highest-ranked specificity
  -- dimension (20260731120000_create_ticket_sla.sql:905), never previously
  -- exercised by any live customer-channel ticket in this suite.
  v_policy_cust_acct := app.create_sla_policy(v_tenant1, 'CUSTACCTA', 'Customer Account A VIP', '00000000-0000-0000-0000-000000289002', 'staff1');
  v_v_cust_acct := app.create_sla_policy_version(v_policy_cust_acct.id, 'customer', null, null, v_account_a, null, null, v_calendar_id, 30, 240, 0, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.publish_sla_policy_version(v_v_cust_acct.id, v_v_cust_acct.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

  v_ticket_cust2 := app.create_customer_ticket(v_tenant1, v_account_a, v_category, 'normal', 'Customer account-scoped-policy case', 'body', 'idem-sla090-cust2', v_customer1, 'customer1');
  v_clock_cust2 := app.start_ticket_sla_clock(v_ticket_cust2.id, v_customer1, 'customer1');
  if v_clock_cust2.sla_policy_version_id <> v_v_cust_acct.id then
    raise exception 'FAIL: expected the customer_account_id-scoped SLA policy (more specific) to win over the wildcard, got version %', v_clock_cust2.sla_policy_version_id;
  end if;
  if v_clock_cust2.response_target_minutes <> 30 then
    raise exception 'FAIL: expected the account-scoped policy''s own tighter response target (30), got %', v_clock_cust2.response_target_minutes;
  end if;

  -- Requester-safe projection: the real customer_user actor sees target/status
  -- reflecting the policy that actually won.
  select * into v_row from app.get_ticket_sla_status_for_requester(v_ticket_cust2.id, v_customer1);
  if v_row.response_target_minutes <> 30 then
    raise exception 'FAIL: customer requester-safe projection did not reflect the account-scoped policy''s own target';
  end if;

  -- RLS/RPC boundary: an unaffiliated second customer identity (zero
  -- membership on Account A) gets ZERO rows from every SLA read RPC -- the
  -- exact customer-channel boundary this file never previously constructed a
  -- real customer_user actor to test.
  select count(*) into v_count from app.get_ticket_sla_status_for_requester(v_ticket_cust2.id, v_customer2);
  if v_count <> 0 then
    raise exception 'CRITICAL: an unaffiliated customer identity read another account''s customer-channel SLA status';
  end if;
  select count(*) into v_count from app.get_ticket_sla_clock(v_ticket_cust2.id, v_customer2);
  if v_count <> 0 then
    raise exception 'CRITICAL: an unaffiliated customer identity read the staff-only SLA clock projection';
  end if;

  -- Raw-table RLS, real forged session (same technique test 9 above uses):
  -- the same unaffiliated customer, zero rows.
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000289011", "role": "authenticated"}', false);
  set role authenticated;
  select count(*) into v_count from app.ticket_sla_clocks where id = v_clock_cust2.id;
  reset role;
  perform set_config('request.jwt.claims', 'null', false);
  if v_count <> 0 then
    raise exception 'CRITICAL: raw-table RLS admitted an unaffiliated customer_user-layer actor to another account''s SLA clock, count=%', v_count;
  end if;

  raise notice 'PASS (customer channel): wildcard vs. customer_account_id-scoped policy precedence resolves correctly on a real app.create_customer_ticket-created ticket; requester-safe projection reflects the winning policy; an unaffiliated customer_user identity is admitted to zero rows via RPC or raw-table RLS';

  -- --- Helpdesk channel: wildcard vs. support_queue_id-scoped precedence ---

  v_policy_hd_wide := app.create_sla_policy(v_tenant1, 'HDWIDE', 'Helpdesk Wide Default', '00000000-0000-0000-0000-000000289002', 'staff1');
  v_v_hd_wide := app.create_sla_policy_version(v_policy_hd_wide.id, 'helpdesk', null, null, null, null, null, v_calendar_id, 60, 480, 0, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.publish_sla_policy_version(v_v_hd_wide.id, v_v_hd_wide.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

  v_ticket_hd1 := app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', 'medium', 'billing', 'production', null, 'Helpdesk wide-policy case', 'body', 'idem-sla090-hd1', '00000000-0000-0000-0000-000000289001', 'admin1');
  v_clock_hd1 := app.start_ticket_sla_clock(v_ticket_hd1.id, '00000000-0000-0000-0000-000000289001', 'admin1');
  if v_clock_hd1.sla_policy_version_id <> v_v_hd_wide.id then
    raise exception 'FAIL: expected the helpdesk-channel ticket to match the wildcard helpdesk-channel SLA policy, got version %', v_clock_hd1.sla_policy_version_id;
  end if;

  -- A real app.support_queues row + a MORE SPECIFIC policy scoped to it --
  -- resolve_effective_sla_policy_version's own support_queue_id specificity
  -- dimension, never previously exercised by any live helpdesk-channel
  -- ticket in this suite.
  v_support_queue := (app.create_support_queue('SQ-SLA090', 'ISS-2026-090 Regression Queue', null, v_supreme, 'supreme')).id;
  v_policy_hd_queue := app.create_sla_policy(v_tenant1, 'HDQUEUE', 'Helpdesk Queue-scoped', '00000000-0000-0000-0000-000000289002', 'staff1');
  v_v_hd_queue := app.create_sla_policy_version(v_policy_hd_queue.id, 'helpdesk', null, null, null, null, v_support_queue, v_calendar_id, 15, 120, 0, '00000000-0000-0000-0000-000000289002', 'staff1');
  perform app.publish_sla_policy_version(v_v_hd_queue.id, v_v_hd_queue.record_version, '00000000-0000-0000-0000-000000289002', 'staff1');

  v_ticket_hd2 := app.create_helpdesk_ticket(v_tenant1, v_category, 'normal', 'high', 'billing', 'production', null, 'Helpdesk queue-scoped-policy case', 'body', 'idem-sla090-hd2', '00000000-0000-0000-0000-000000289001', 'admin1');
  v_ticket_hd2 := app.transfer_helpdesk_support_queue(v_ticket_hd2.id, v_ticket_hd2.record_version, v_support_queue, 'ISS-2026-090 regression triage', v_supreme, 'supreme');
  v_clock_hd2 := app.start_ticket_sla_clock(v_ticket_hd2.id, '00000000-0000-0000-0000-000000289001', 'admin1');
  if v_clock_hd2.sla_policy_version_id <> v_v_hd_queue.id then
    raise exception 'FAIL: expected the support_queue_id-scoped SLA policy (more specific) to win over the wildcard, got version %', v_clock_hd2.sla_policy_version_id;
  end if;
  if v_clock_hd2.response_target_minutes <> 15 then
    raise exception 'FAIL: expected the queue-scoped policy''s own tighter response target (15), got %', v_clock_hd2.response_target_minutes;
  end if;

  -- Requester-safe projection: admin1 (tenant-side requester party via
  -- app._is_tenant_helpdesk_authorized) sees target/status for the tenant's
  -- own helpdesk case.
  select * into v_row from app.get_ticket_sla_status_for_requester(v_ticket_hd2.id, '00000000-0000-0000-0000-000000289001');
  if v_row.response_target_minutes <> 15 then
    raise exception 'FAIL: helpdesk tenant-side requester-safe projection did not reflect the queue-scoped policy''s own target';
  end if;

  -- Staff-only full projection is genuinely Supreme-Admin-only for a
  -- helpdesk ticket (ISS-2026-085/086's own is_ticket_staff early-return):
  -- the tenant-side requester (admin1) gets ZERO rows even though they ARE
  -- the requester-safe party, and staff1's own real tenant-wide TKT:Edit
  -- grant (ISS-2026-086's own subject) does NOT leak staff status onto a
  -- helpdesk case either.
  select count(*) into v_count from app.get_ticket_sla_clock(v_ticket_hd2.id, '00000000-0000-0000-0000-000000289001');
  if v_count <> 0 then
    raise exception 'CRITICAL: a tenant-side helpdesk requester (admin1) read the staff-only SLA clock projection for their own helpdesk case';
  end if;
  select count(*) into v_count from app.get_ticket_sla_clock(v_ticket_hd2.id, '00000000-0000-0000-0000-000000289002');
  if v_count <> 0 then
    raise exception 'CRITICAL: a tenant TKT:Edit holder (staff1) read the staff-only SLA clock projection for a helpdesk case they are not staff on';
  end if;
  select count(*) into v_count from app.get_ticket_sla_clock(v_ticket_hd2.id, v_supreme);
  if v_count <> 1 then
    raise exception 'FAIL: a real Supreme Admin should see the full staff-only SLA clock projection for a helpdesk case';
  end if;

  -- RLS/RPC boundary: a real customer_user-layer actor (customer1, wholly
  -- unrelated to this tenant's own helpdesk case) gets ZERO rows.
  select count(*) into v_count from app.get_ticket_sla_status_for_requester(v_ticket_hd2.id, v_customer1);
  if v_count <> 0 then
    raise exception 'CRITICAL: a customer_user-layer actor read a helpdesk-channel SLA status';
  end if;

  raise notice 'PASS (helpdesk channel): wildcard vs. support_queue_id-scoped policy precedence resolves correctly on a real app.create_helpdesk_ticket-created ticket; the tenant-side requester-safe projection reflects the winning policy; the staff-only full projection is genuinely Supreme-Admin-only (the requester-side tenant_admin AND a tenant TKT:Edit holder both get zero rows); a customer_user-layer actor is admitted to zero rows';

  raise notice 'PASS: ISS-2026-090 closed -- scripts/db-tests/ticketing-sla.sql now drives the SLA engine''s customer/helpdesk-channel policy-matching and RLS/RPC boundary paths through real app.create_customer_ticket/app.create_helpdesk_ticket-created tickets, not app.create_ticket alone';
end;
$$;

\echo '>> ticketing-sla.sql: ALL PASSED'
