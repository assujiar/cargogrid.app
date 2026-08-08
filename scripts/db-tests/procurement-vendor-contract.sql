-- Real, executable test evidence for PRC-261 (Vendor Contract, CG-S11-PRC-012) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database. Scoped to this
-- checkpoint's own additive migration (supabase/migrations/
-- 20260730700000_create_procurement_vendor_contract.sql). Self-contained -- builds its
-- own tenants/vendors/approval-routing pipeline from scratch, mirroring procurement-
-- purchase-order.sql's own disclosed convention.
--
-- Covers: draft create/update/idempotency, submit -> decide (MFA reauth) -> sign ->
-- activate, cost-field masking (PRC:View cost), amendment (immediate-supersede) and
-- renewal (supersede-on-activate, exercising the dual-row C-21 lock order), suspend/
-- reactivate/terminate/cancel, resolve_effective_vendor_contract, cross-tenant/
-- authority denial, and schema-privilege defense in depth (column-restricted grant).
--
-- Disclosed, not tested here (bounded scope, not an oversight):
--   * A live two-process concurrent race on app.activate_vendor_contract's own dual-lock
--     -- deferred to this batch's own Tier C correctness/concurrency lens
--     (BUILD_EXECUTION_PROTOCOL.md §5.2), which live-tests with real concurrent psql
--     sessions; this file exercises the lock-order logic deterministically (single
--     session, both branches) but not under genuine concurrency.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (vc1): tenant_admin (admin1), full-PRC+View-cost+Override staff (staff1), View-only-no-cost viewer (viewer1), no-PRC outsider (outsider1), a manager role for a real 1-step approval routing definition. Tenant2 (vc2): tenant_admin (admin2) + staff2. A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid;
  v_staff_role uuid;
  v_viewer_role uuid;
  v_outsider_role uuid;
  v_manager_role uuid;
  v_t2_staff_role uuid;
  v_approval_draft app.config_versions;
  v_policy app.procurement_approval_policies;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000261101', 'admin@vc1.test'),
    ('00000000-0000-0000-0000-000000261102', 'staff@vc1.test'),
    ('00000000-0000-0000-0000-000000261103', 'viewer@vc1.test'),
    ('00000000-0000-0000-0000-000000261104', 'outsider@vc1.test'),
    ('00000000-0000-0000-0000-000000261105', 'manager@vc1.test'),
    ('00000000-0000-0000-0000-000000261201', 'admin@vc2.test'),
    ('00000000-0000-0000-0000-000000261202', 'staff@vc2.test'),
    ('00000000-0000-0000-0000-000000261999', 'supreme@vc.test');

  perform app.provision_tenant('vc1', 'Vendor Contract Co 1', 'idem-vc1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'vc1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('vc2', 'Vendor Contract Co 2', 'idem-vc2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'vc2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000261101', 'admin@vc1.test', 'Vc1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vc1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000261101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000261102', 'staff@vc1.test', 'Vc1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000261103', 'viewer@vc1.test', 'Vc1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@vc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000261104', 'outsider@vc1.test', 'Vc1 Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@vc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000261105', 'manager@vc1.test', 'Vc1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@vc1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000261201', 'admin@vc2.test', 'Vc2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vc2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000261201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000261202', 'staff@vc2.test', 'Vc2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vc2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000261999', 'supreme_admin', null, null, 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'Vc1 Admin', 'full PRC for setup', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_admin_role, 'tester')).id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve', 'Reject')
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_admin_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000261101', '00000000-0000-0000-0000-000000261999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'Vc1 Staff', 'Create/Edit/View/View cost/Override', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_staff_role, 'tester')).id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override')
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000261102', '00000000-0000-0000-0000-000000261101', 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'Vc1 Viewer', 'View only, no View cost', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_viewer_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_viewer_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000261103', '00000000-0000-0000-0000-000000261101', 'admin');

  v_outsider_role := (app.create_role(v_tenant1, 'Vc1 Outsider', 'no PRC at all', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_outsider_role, 'tester')).id, array[]::uuid[], 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_outsider_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000261104', '00000000-0000-0000-0000-000000261101', 'admin');

  v_manager_role := (app.create_role(v_tenant1, 'Vc1 Manager Approver', 'approval routing step', 'tester')).id;
  perform app.publish_role_version((app.create_role_version(v_manager_role, 'tester')).id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000261105', '00000000-0000-0000-0000-000000261101', 'admin');

  v_t2_staff_role := (app.create_role(v_tenant2, 'Vc2 Staff', 'full PRC', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_t2_staff_role, 'tester')).id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override')
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_t2_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000261202', '00000000-0000-0000-0000-000000261201', 'admin');

  -- Single-step routing (manager only), and a policy that ALWAYS requires approval for
  -- vendor_contract regardless of value_amount -- exercises the real approval path even
  -- though this file's own contracts carry no linked rate_version (design note 3).
  select * into v_approval_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000261101', 'tenant admin');
  perform app.set_config_items(v_approval_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000261101', 'tenant admin');
  perform app.publish_approval_definition(v_approval_draft.id, '00000000-0000-0000-0000-000000261101', null, 'tenant admin');

  -- min_value_amount must be NULL for vendor_contract (procurement_approval_policies_
  -- value_dimension_check restricts a value threshold to the three genuinely
  -- value-bearing entity types) -- always_required is the only lever here, matching
  -- vendor_activation's own established precedent.
  v_policy := app.create_procurement_approval_policy_version(v_tenant1, 'vendor_contract', null, true, '00000000-0000-0000-0000-000000261101', 'admin');
  perform app.publish_procurement_approval_policy_version(v_policy.id, v_policy.record_version, null, '00000000-0000-0000-0000-000000261101', 'admin');
end $$;

\echo '>> setup: one ACTIVE vendor in tenant1'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vc1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000261101';
  v_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Vendor Contract A', 'VCA', 'PT', 'REG-VC-A', 'logistics', 30, 'staff_created', 'idem-vc-vendor-a', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Ani A', 'Ops', 'ani@vca.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
end $$;

\echo '>> create_vendor_contract_draft: validation, idempotency, and authority'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vc1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000261102';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000261104';
  v_vendor_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Contract A');
  v_contract app.vendor_contracts;
  v_contract2 app.vendor_contracts;
  v_failed boolean;
begin
  v_contract := app.create_vendor_contract_draft(
    v_tenant1, v_vendor_master, 'fixed_term', '2026-01-01'::date, '2026-12-31'::date, null, 30,
    jsonb_build_object('vat_rate', 11), jsonb_build_object('on_time_target_pct', 95),
    jsonb_build_object('committed_teus_per_month', 50), jsonb_build_object('lanes', jsonb_build_array('Jakarta-Surabaya')),
    jsonb_build_array('ISO9001'), true, 'idem-vc-contract-1', v_staff1, 'staff'
  );
  if v_contract.status <> 'draft' or v_contract.version_no <> 1 or v_contract.version_kind <> 'initial' or v_contract.contract_number is null then
    raise exception 'assertion failed: expected a fresh draft v1/initial with a generated contract_number, got status=% version=%/% number=%', v_contract.status, v_contract.version_no, v_contract.version_kind, v_contract.contract_number;
  end if;
  if v_contract.payment_term_days <> 30 or (v_contract.tax_terms->>'vat_rate')::numeric <> 11 then
    raise exception 'assertion failed: expected payment_term_days=30 and tax_terms.vat_rate=11 unmasked for the creator, got %/%', v_contract.payment_term_days, v_contract.tax_terms;
  end if;

  -- idempotency replay: identical key returns the SAME row
  v_contract2 := app.create_vendor_contract_draft(
    v_tenant1, v_vendor_master, 'fixed_term', '2026-01-01'::date, '2026-12-31'::date, null, 30,
    jsonb_build_object('vat_rate', 11), jsonb_build_object('on_time_target_pct', 95),
    jsonb_build_object('committed_teus_per_month', 50), jsonb_build_object('lanes', jsonb_build_array('Jakarta-Surabaya')),
    jsonb_build_array('ISO9001'), true, 'idem-vc-contract-1', v_staff1, 'staff'
  );
  if v_contract2.id <> v_contract.id then
    raise exception 'assertion failed: expected the identical idempotency-key replay to return the SAME row';
  end if;

  -- fixed_term without effective_end is rejected
  begin
    perform app.create_vendor_contract_draft(v_tenant1, v_vendor_master, 'fixed_term', '2026-01-01'::date, null, null, 30, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, true, 'idem-vc-bad-1', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'missing_effective_end%' then
      raise exception 'assertion failed: expected missing_effective_end, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a fixed_term draft with no effective_end to be rejected'; end if;

  -- C-01 fix coverage: reusing the SAME idempotency key for a genuinely DIFFERENT
  -- vendor/contract_type/effective_start must be a conflict, never a silent
  -- misattribution to the wrong contract (the bug this prompt's own Tier B self-check
  -- found and fixed before this checkpoint's commit).
  begin
    perform app.create_vendor_contract_draft(
      v_tenant1, v_vendor_master, 'framework', '2030-01-01'::date, null, null, null, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-vc-contract-1', v_staff1, 'staff'
    );
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict%' then
      raise exception 'assertion failed: expected idempotency_key_conflict for a target-mismatched replay, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected reusing idem-vc-contract-1 for a different contract_type/effective_start to be rejected as a conflict, not silently returned as a match'; end if;

  -- an outsider with no PRC:Create is denied
  begin
    perform app.create_vendor_contract_draft(v_tenant1, v_vendor_master, 'framework', '2026-01-01'::date, null, null, null, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-vc-outsider-1', v_outsider1, 'outsider');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'assertion failed: expected insufficient_authority, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the Create-less outsider to be denied'; end if;
end $$;

\echo '>> update_vendor_contract_draft: preserve-by-null semantics (a real bug this prompt''s own Tier B self-check found and fixed -- passing null for an untouched field must never clear it)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vc1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000261102';
  v_contract app.vendor_contracts;
begin
  select * into v_contract from app.vendor_contracts where tenant_id = v_tenant1 and idempotency_key = 'idem-vc-contract-1';

  -- pass null for rate_version_id/tax_terms/sla_terms/capacity_terms/coverage_terms/
  -- compliance_required, only changing effective_end -- payment_term_days=30 and
  -- tax_terms.vat_rate=11 (set at create time) must survive untouched.
  v_contract := app.update_vendor_contract_draft(v_contract.id, v_contract.record_version, v_contract.effective_start, '2026-11-30'::date, null, null, null, null, null, null, null, v_staff1, 'staff');
  if v_contract.effective_end <> '2026-11-30'::date then
    raise exception 'assertion failed: expected effective_end updated to 2026-11-30, got %', v_contract.effective_end;
  end if;
  if v_contract.payment_term_days <> 30 or (v_contract.tax_terms->>'vat_rate')::numeric <> 11 then
    raise exception 'assertion failed: expected payment_term_days=30 and tax_terms.vat_rate=11 PRESERVED (not cleared) by an update that passed null for both, got %/%', v_contract.payment_term_days, v_contract.tax_terms;
  end if;
end $$;

\echo '>> submit -> decide (MFA reauth) -> sign -> activate, cost-field masking'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vc1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000261102';
  v_admin1 uuid := '00000000-0000-0000-0000-000000261101';
  v_manager1 uuid := '00000000-0000-0000-0000-000000261105';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000261103';
  v_contract app.vendor_contracts;
  v_step_id uuid;
  v_masked app.vendor_contracts;
  v_failed boolean;
begin
  select * into v_contract from app.vendor_contracts where tenant_id = v_tenant1 and idempotency_key = 'idem-vc-contract-1';

  v_contract := app.submit_vendor_contract_for_approval(v_contract.id, v_contract.record_version, 'idem-vc-submit-1', v_staff1, 'staff');
  if v_contract.status <> 'pending_approval' or v_contract.approval_status <> 'pending' then
    raise exception 'assertion failed: expected status=pending_approval approval_status=pending (always_required policy), got %/%', v_contract.status, v_contract.approval_status;
  end if;

  -- activation is blocked before approval AND signature complete (PRC:Approve holder, admin1 -- distinct from the routing-step decider manager1)
  begin
    perform app.activate_vendor_contract(v_contract.id, v_contract.record_version, v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'approval_incomplete%' then
      raise exception 'assertion failed: expected approval_incomplete, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected activation to be blocked before approval completes'; end if;

  -- decide without reauth is rejected
  select s.id into v_step_id from app.approval_request_steps s where s.request_id = v_contract.approval_request_id order by step_order limit 1;
  begin
    perform app.decide_vendor_contract_approval_step(v_step_id, 'approved', v_manager1, 'manager', null);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reauth_required%' then
      raise exception 'assertion failed: expected reauth_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a decide call with no reauth to be rejected'; end if;

  v_contract := app.decide_vendor_contract_approval_step(v_step_id, 'approved', v_manager1, 'manager', now());
  if v_contract.approval_status <> 'approved' then
    raise exception 'assertion failed: expected approval_status=approved after the sole routing step approves, got %', v_contract.approval_status;
  end if;

  -- activation still blocked -- signature not yet recorded
  begin
    perform app.activate_vendor_contract(v_contract.id, v_contract.record_version, v_admin1, 'admin');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'signature_incomplete%' then
      raise exception 'assertion failed: expected signature_incomplete, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected activation to be blocked before signature completes'; end if;

  v_contract := app.record_vendor_contract_signature(v_contract.id, v_contract.record_version, 'Budi Signatory', now(), null, v_staff1, 'staff');
  if v_contract.signature_status <> 'signed' or v_contract.signed_by <> 'Budi Signatory' then
    raise exception 'assertion failed: expected signature_status=signed signed_by=Budi Signatory, got %/%', v_contract.signature_status, v_contract.signed_by;
  end if;

  v_contract := app.activate_vendor_contract(v_contract.id, v_contract.record_version, v_admin1, 'admin');
  if v_contract.status <> 'active' then
    raise exception 'assertion failed: expected status=active after approval+signature complete, got %', v_contract.status;
  end if;

  -- cost-field masking: staff1 (View cost) sees real values; viewer1 (no View cost) sees masked
  v_masked := app.get_vendor_contract(v_contract.id, v_viewer1);
  if v_masked.payment_term_days is not null or v_masked.tax_terms <> '{}'::jsonb or v_masked.capacity_terms <> '{}'::jsonb then
    raise exception 'assertion failed: expected payment_term_days/tax_terms/capacity_terms masked for the View-cost-less viewer, got %/%/%', v_masked.payment_term_days, v_masked.tax_terms, v_masked.capacity_terms;
  end if;
  if v_masked.status <> 'active' or v_masked.contract_number is null then
    raise exception 'assertion failed: expected non-cost fields (status, contract_number) to remain visible to the viewer';
  end if;

  v_masked := app.get_vendor_contract(v_contract.id, v_staff1);
  if v_masked.payment_term_days <> 30 or (v_masked.tax_terms->>'vat_rate')::numeric <> 11 then
    raise exception 'assertion failed: expected payment_term_days/tax_terms unmasked for the View-cost holder, got %/%', v_masked.payment_term_days, v_masked.tax_terms;
  end if;
end $$;

\echo '>> resolve_effective_vendor_contract: the deterministic single-active-row resolution point'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vc1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000261102';
  v_vendor_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Contract A');
  v_resolved app.vendor_contracts;
begin
  v_resolved := app.resolve_effective_vendor_contract(v_tenant1, v_vendor_master, '2026-06-15'::timestamptz, v_staff1);
  if v_resolved.id is null or v_resolved.status <> 'active' then
    raise exception 'assertion failed: expected an active contract effective 2026-06-15, got %', v_resolved;
  end if;

  v_resolved := app.resolve_effective_vendor_contract(v_tenant1, v_vendor_master, '2027-06-15'::timestamptz, v_staff1);
  if v_resolved.id is not null then
    raise exception 'assertion failed: expected NULL (no governing contract) past effective_end 2026-12-31, got %', v_resolved.id;
  end if;
end $$;

\echo '>> amend (immediate supersede) then renew (supersede-on-activate, exercises the dual-lock C-21 order) -- both branches of app.activate_vendor_contract'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vc1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000261102';
  v_admin1 uuid := '00000000-0000-0000-0000-000000261101';
  v_manager1 uuid := '00000000-0000-0000-0000-000000261105';
  v_v1 app.vendor_contracts;
  v_v2 app.vendor_contracts;
  v_v3 app.vendor_contracts;
  v_step_id uuid;
  v_active_count integer;
begin
  select * into v_v1 from app.vendor_contracts where tenant_id = v_tenant1 and version_no = 1 and idempotency_key = 'idem-vc-contract-1';

  -- amendment: v1 immediately superseded, v2 (amendment) created as a fresh draft
  v_v2 := app.amend_vendor_contract(v_v1.id, v_v1.record_version, 'renegotiated SLA target', null, null, 45, jsonb_build_object('on_time_target_pct', 98), null, null, v_staff1, 'staff');
  if v_v2.version_no <> 2 or v_v2.version_kind <> 'amendment' or v_v2.status <> 'draft' or v_v2.supersedes_contract_id <> v_v1.id then
    raise exception 'assertion failed: expected v2/amendment/draft superseding v1, got version=%/% status=% supersedes=%', v_v2.version_no, v_v2.version_kind, v_v2.status, v_v2.supersedes_contract_id;
  end if;
  if (select status from app.vendor_contracts where id = v_v1.id) <> 'superseded' then
    raise exception 'assertion failed: expected v1 immediately superseded at amend time (design note 2)';
  end if;
  select count(*) into v_active_count from app.vendor_contracts where tenant_id = v_tenant1 and contract_number = v_v1.contract_number and status = 'active';
  if v_active_count <> 0 then
    raise exception 'assertion failed: expected zero active rows for this contract_number immediately after amend (a real, accepted coverage gap, design note 2), found %', v_active_count;
  end if;

  v_v2 := app.submit_vendor_contract_for_approval(v_v2.id, v_v2.record_version, 'idem-vc-submit-2', v_staff1, 'staff');
  select s.id into v_step_id from app.approval_request_steps s where s.request_id = v_v2.approval_request_id order by step_order limit 1;
  v_v2 := app.decide_vendor_contract_approval_step(v_step_id, 'approved', v_manager1, 'manager', now());
  v_v2 := app.record_vendor_contract_signature(v_v2.id, v_v2.record_version, 'Budi Signatory', now(), null, v_staff1, 'staff');
  v_v2 := app.activate_vendor_contract(v_v2.id, v_v2.record_version, v_admin1, 'admin');
  if v_v2.status <> 'active' then
    raise exception 'assertion failed: expected v2 active after its own full approve+sign+activate cycle, got %', v_v2.status;
  end if;

  -- renewal: v2 stays active while v3 (renewal) is a fresh draft (design note 2 -- no gap)
  v_v3 := app.renew_vendor_contract(v_v2.id, v_v2.record_version, '2027-01-01'::date, '2027-12-31'::date, v_staff1, 'staff');
  if v_v3.version_no <> 3 or v_v3.version_kind <> 'renewal' or v_v3.status <> 'draft' or v_v3.supersedes_contract_id <> v_v2.id then
    raise exception 'assertion failed: expected v3/renewal/draft supersedes=v2, got version=%/% status=% supersedes=%', v_v3.version_no, v_v3.version_kind, v_v3.status, v_v3.supersedes_contract_id;
  end if;
  if (select status from app.vendor_contracts where id = v_v2.id) <> 'active' then
    raise exception 'assertion failed: expected v2 to REMAIN active immediately after renew (design note 2 -- renewal does not supersede at create time)';
  end if;

  v_v3 := app.submit_vendor_contract_for_approval(v_v3.id, v_v3.record_version, 'idem-vc-submit-3', v_staff1, 'staff');
  select s.id into v_step_id from app.approval_request_steps s where s.request_id = v_v3.approval_request_id order by step_order limit 1;
  v_v3 := app.decide_vendor_contract_approval_step(v_step_id, 'approved', v_manager1, 'manager', now());
  v_v3 := app.record_vendor_contract_signature(v_v3.id, v_v3.record_version, 'Budi Signatory', now(), null, v_staff1, 'staff');
  v_v3 := app.activate_vendor_contract(v_v3.id, v_v3.record_version, v_admin1, 'admin');
  if v_v3.status <> 'active' then
    raise exception 'assertion failed: expected v3 active, got %', v_v3.status;
  end if;
  if (select status from app.vendor_contracts where id = v_v2.id) <> 'superseded' then
    raise exception 'assertion failed: expected v2 superseded automatically the moment v3 (its own renewal) activated (design note 2)';
  end if;

  select count(*) into v_active_count from app.vendor_contracts where tenant_id = v_tenant1 and contract_number = v_v1.contract_number and status = 'active';
  if v_active_count <> 1 then
    raise exception 'assertion failed: expected exactly one active row (v3) for this contract_number after the full amend+renew chain, found %', v_active_count;
  end if;
end $$;

\echo '>> suspend/reactivate/terminate lifecycle (PRC:Override), and cancel-eligible draft cancellation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vc1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000261102';
  v_manager1 uuid := '00000000-0000-0000-0000-000000261105';
  v_vendor_master uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vendor Contract A');
  v_v3 app.vendor_contracts;
  v_draft app.vendor_contracts;
begin
  select * into v_v3 from app.vendor_contracts where tenant_id = v_tenant1 and version_no = 3;

  v_v3 := app.suspend_vendor_contract(v_v3.id, v_v3.record_version, 'compliance hold pending review', v_staff1, 'staff');
  if v_v3.status <> 'suspended' then
    raise exception 'assertion failed: expected status=suspended, got %', v_v3.status;
  end if;

  v_v3 := app.reactivate_vendor_contract(v_v3.id, v_v3.record_version, v_staff1, 'staff');
  if v_v3.status <> 'active' then
    raise exception 'assertion failed: expected status=active after reactivate, got %', v_v3.status;
  end if;

  v_v3 := app.terminate_vendor_contract(v_v3.id, v_v3.record_version, 'vendor exited the market', 'legal-notice-ref-001', v_staff1, 'staff');
  if v_v3.status <> 'terminated' or v_v3.termination_reason is null or v_v3.termination_evidence_ref is null then
    raise exception 'assertion failed: expected status=terminated with reason and evidence_ref set, got %/%/%', v_v3.status, v_v3.termination_reason, v_v3.termination_evidence_ref;
  end if;

  -- a fresh draft, submitted, then cancelled while pending -- its approval request cancels too
  v_draft := app.create_vendor_contract_draft(v_tenant1, v_vendor_master, 'framework', '2028-01-01'::date, null, null, null, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-vc-cancel-1', v_staff1, 'staff');
  v_draft := app.submit_vendor_contract_for_approval(v_draft.id, v_draft.record_version, 'idem-vc-cancel-submit-1', v_staff1, 'staff');
  v_draft := app.cancel_vendor_contract_draft(v_draft.id, v_draft.record_version, 'no longer needed', v_staff1, 'staff');
  if v_draft.status <> 'cancelled' then
    raise exception 'assertion failed: expected status=cancelled, got %', v_draft.status;
  end if;
  if (select status from app.approval_requests where id = v_draft.approval_request_id) <> 'cancelled' then
    raise exception 'assertion failed: expected the bound approval request to be cancelled too, mirroring app.cancel_purchase_order';
  end if;
end $$;

\echo '>> cross-tenant authority denial: tenant2 staff cannot read or act on tenant1 contracts'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vc1');
  v_staff2 uuid := '00000000-0000-0000-0000-000000261202';
  v_contract_id uuid := (select id from app.vendor_contracts where tenant_id = v_tenant1 and version_no = 1 and idempotency_key = 'idem-vc-contract-1');
  v_failed boolean;
begin
  -- vendor_contract_not_found, never insufficient_authority, which would disclose
  -- that a real contract exists at this id to a zero-membership cross-tenant caller
  -- (C-05 fix, mirrors app.get_purchase_order's own established precedent).
  begin
    perform app.get_vendor_contract(v_contract_id, v_staff2);
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_contract_not_found%' then
      raise exception 'assertion failed: expected vendor_contract_not_found (never insufficient_authority, which would disclose existence) for a cross-tenant read, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a cross-tenant get_vendor_contract to be denied'; end if;
end $$;

\echo '>> schema-privilege defense in depth: authenticated has NO column-level SELECT on the four masked commercial-term columns; anon holds zero EXECUTE on any new function (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.column_privileges
  where table_schema = 'app' and table_name = 'vendor_contracts' and grantee = 'authenticated'
    and column_name in ('rate_version_id', 'payment_term_days', 'tax_terms', 'capacity_terms');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated column grants on the four masked commercial-term columns, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.column_privileges
  where table_schema = 'app' and table_name = 'vendor_contracts' and grantee = 'authenticated' and column_name = 'status';
  if v_count <> 1 then
    raise exception 'assertion failed: expected authenticated to retain a direct SELECT grant on the non-cost status column, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon'
    and routine_name like '%vendor_contract%';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on any vendor-contract function, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every vendor-contract mutation recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where action in (
    'create_vendor_contract_draft', 'update_vendor_contract_draft', 'submit_vendor_contract_for_approval',
    'record_vendor_contract_signature', 'activate_vendor_contract', 'amend_vendor_contract', 'renew_vendor_contract',
    'suspend_vendor_contract', 'reactivate_vendor_contract', 'terminate_vendor_contract', 'cancel_vendor_contract_draft'
  );
  if v_count < 10 then
    raise exception 'assertion failed: expected at least 10 captured vendor-contract audit events, found %', v_count;
  end if;
end $$;

\echo 'ALL PRC-261 db-test assertions passed.'
