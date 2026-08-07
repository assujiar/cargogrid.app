-- Real, executable test evidence for PRC-259 (Procurement Approval,
-- CG-S11-PRC-010) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Scoped to this checkpoint's own additive migration
-- (supabase/migrations/20260730660000_create_procurement_approval.sql).
-- Sorts alphabetically after every other procurement-*.sql file -- self-contained,
-- builds its own tenants/vendors/sourcing/RFQ/comparison pipeline from scratch,
-- mirroring procurement-vendor-comparison.sql's own disclosed convention.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (apr1): tenant_admin (admin1, full PRC+FIN), a full-PRC staff actor (staff1: Create/Edit/View/View cost/Override), an approve-only actor (approver1: View/View cost/Approve), a manager role + finance role for a real 2-step sequential approval routing definition, an outsider with no PRC role at all (outsider1). Tenant2 (apr2): tenant_admin (admin2) + staff2, for cross-tenant checks. A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid;
  v_admin_draft app.role_versions;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_outsider_role uuid;
  v_outsider_draft app.role_versions;
  v_manager_role uuid;
  v_finance_role uuid;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
  v_approval_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000394101', 'admin@apr1.test'),
    ('00000000-0000-0000-0000-000000394102', 'staff@apr1.test'),
    ('00000000-0000-0000-0000-000000394103', 'approver@apr1.test'),
    ('00000000-0000-0000-0000-000000394104', 'outsider@apr1.test'),
    ('00000000-0000-0000-0000-000000394105', 'manager@apr1.test'),
    ('00000000-0000-0000-0000-000000394106', 'finance@apr1.test'),
    ('00000000-0000-0000-0000-000000394201', 'admin@apr2.test'),
    ('00000000-0000-0000-0000-000000394202', 'staff@apr2.test'),
    ('00000000-0000-0000-0000-000000394999', 'supreme@apr.test');

  perform app.provision_tenant('apr1', 'Approval Co 1', 'idem-apr1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'apr1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('apr2', 'Approval Co 2', 'idem-apr2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'apr2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000394101', 'admin@apr1.test', 'Apr1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@apr1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000394101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000394102', 'staff@apr1.test', 'Apr1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@apr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000394103', 'approver@apr1.test', 'Apr1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@apr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000394104', 'outsider@apr1.test', 'Apr1 Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@apr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000394105', 'manager@apr1.test', 'Apr1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@apr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000394106', 'finance@apr1.test', 'Apr1 Finance', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'finance@apr1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000394201', 'admin@apr2.test', 'Apr2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@apr2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000394201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000394202', 'staff@apr2.test', 'Apr2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@apr2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000394999', 'supreme_admin', null, null, 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'Apr1 Admin', 'full PRC for setup', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve', 'Reject')
  ), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000394101', '00000000-0000-0000-0000-000000394999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'Apr1 Staff', 'Create/Edit/View/View cost/Override + FIN:View', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override'))
      or (resource_module_code = 'FIN' and action = 'View')
  ), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000394102', '00000000-0000-0000-0000-000000394101', 'admin');

  v_approver_role := (app.create_role(v_tenant1, 'Apr1 Approver', 'View/View cost/Approve/Reject', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('View', 'View cost', 'Approve', 'Reject')
  ), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000394103', '00000000-0000-0000-0000-000000394101', 'admin');

  v_outsider_role := (app.create_role(v_tenant1, 'Apr1 Outsider', 'no PRC at all', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(v_outsider_draft.id, array[]::uuid[], 'tester');
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000394104', '00000000-0000-0000-0000-000000394101', 'admin');

  v_manager_role := (app.create_role(v_tenant1, 'Apr1 Manager Approver', 'approval routing step 1', 'tester')).id;
  perform app.publish_role_version((app.create_role_version(v_manager_role, 'tester')).id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000394105', '00000000-0000-0000-0000-000000394101', 'admin');

  v_finance_role := (app.create_role(v_tenant1, 'Apr1 Finance Approver', 'approval routing step 2', 'tester')).id;
  perform app.publish_role_version((app.create_role_version(v_finance_role, 'tester')).id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_finance_role and status = 'published'), '00000000-0000-0000-0000-000000394106', '00000000-0000-0000-0000-000000394101', 'admin');

  v_t2_staff_role := (app.create_role(v_tenant2, 'Apr2 Staff', 'full PRC', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve', 'Reject')
  ), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000394201', '00000000-0000-0000-0000-000000394999', 'supreme');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000394202', '00000000-0000-0000-0000-000000394201', 'admin');

  -- One real 2-step sequential routing definition (manager then finance), the SAME
  -- shared tenant-wide config_type_code='approval' object every governed entity_type
  -- reuses (this migration's own header -- mirrors COM-153/COM-157 exactly).
  select * into v_approval_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000394101', 'tenant admin');
  perform app.set_config_items(v_approval_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role::text, 'required_approvals', 1),
      jsonb_build_object('step_order', 2, 'approver_type', 'role', 'role_id', v_finance_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000394101', 'tenant admin');
  perform app.publish_approval_definition(v_approval_draft.id, '00000000-0000-0000-0000-000000394101', null, 'tenant admin');
end;
$$;

-- ===========================================================================
-- Vendor activation binding
-- ===========================================================================

\echo '>> vendor activation, no published vendor_activation policy: decide_vendor_profile_review(approve) leaves approval_status=not_required, activate_vendor_profile succeeds immediately'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Apr Vendor A', 'APRA', 'PT', 'REG-APR-A', 'logistics', 30, 'staff_created', 'idem-apr-vendor-a', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Ani A', 'Ops', 'ani@apra.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  if v_profile.approval_status <> 'not_required' or v_profile.approval_request_id is not null then
    raise exception 'assertion failed: expected approval_status=not_required approval_request_id=null (no published policy), got %/%', v_profile.approval_status, v_profile.approval_request_id;
  end if;

  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  if v_profile.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected active, got %', v_profile.lifecycle_status;
  end if;
end;
$$;

\echo '>> app.create_procurement_approval_policy_version / publish: vendor_activation always_required=true, mirroring app.quotation_approval_rules'' own versioning discipline'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_policy app.procurement_approval_policies;
begin
  begin
    perform app.create_procurement_approval_policy_version(v_tenant1, 'vendor_activation', 1000, null, v_admin1, 'admin');
    raise exception 'assertion failed: expected check_violation -- min_value_amount is not a valid dimension for vendor_activation';
  exception
    when sqlstate '23514' then
      null; -- expected (procurement_approval_policies_value_dimension_check)
  end;

  begin
    perform app.create_procurement_approval_policy_version(v_tenant1, 'not_a_real_type', null, true, v_admin1, 'admin');
    raise exception 'assertion failed: expected check_violation -- invalid entity_type';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_policy from app.create_procurement_approval_policy_version(v_tenant1, 'vendor_activation', null, true, v_admin1, 'admin');
  if v_policy.status <> 'draft' then
    raise exception 'assertion failed: expected a fresh policy to start draft, got %', v_policy.status;
  end if;

  select * into v_policy from app.publish_procurement_approval_policy_version(v_policy.id, v_policy.record_version, null, v_admin1, 'admin');
  if v_policy.status <> 'published' then
    raise exception 'assertion failed: expected published, got %', v_policy.status;
  end if;
end;
$$;

\echo '>> vendor activation, published always_required policy: decide_vendor_profile_review(approve) routes for real (approval_status=pending, a real app.approval_requests row bound entity_type=vendor_activation); activate_vendor_profile is blocked (vendor_activation_approval_pending) until the routed request resolves; outsider denied deciding step 1; manager approves step 1 (still pending), finance approves step 2 (approval_status syncs to approved); activate_vendor_profile then succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000394104';
  v_manager1 uuid := '00000000-0000-0000-0000-000000394105';
  v_finance1 uuid := '00000000-0000-0000-0000-000000394106';
  v_profile app.vendor_profiles;
  v_step1_id uuid;
  v_step2_id uuid;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Apr Vendor B', 'APRB', 'PT', 'REG-APR-B', 'logistics', 30, 'staff_created', 'idem-apr-vendor-b', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Budi B', 'Ops', 'budi@aprb.test', '0812', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Gatot Subroto 2', 'Jakarta', 'DKI Jakarta', '10230', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  if v_profile.approval_status <> 'pending' or v_profile.approval_request_id is null or v_profile.lifecycle_status <> 'approved' then
    raise exception 'assertion failed: expected lifecycle_status=approved approval_status=pending approval_request_id set, got %/%/%', v_profile.lifecycle_status, v_profile.approval_status, v_profile.approval_request_id;
  end if;
  if (select entity_type from app.approval_requests where id = v_profile.approval_request_id) <> 'vendor_activation'
    or (select entity_id from app.approval_requests where id = v_profile.approval_request_id) <> v_profile.master_record_id then
    raise exception 'assertion failed: expected the bound request to carry entity_type=vendor_activation entity_id=%', v_profile.master_record_id;
  end if;

  begin
    perform app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
    raise exception 'assertion failed: expected vendor_activation_approval_pending -- governance approval is still pending';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'vendor_activation_approval_pending:%' then
        raise exception 'assertion failed: expected vendor_activation_approval_pending, got %', sqlerrm;
      end if;
  end;

  select id into v_step1_id from app.approval_request_steps where request_id = v_profile.approval_request_id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_profile.approval_request_id and step_order = 2;

  begin
    perform app.decide_vendor_activation_approval_step(v_step1_id, 'approved', v_outsider1, 'outsider', null);
    raise exception 'assertion failed: expected insufficient_privilege -- outsider holds no manager/finance role assignment';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  perform app.decide_vendor_activation_approval_step(v_step1_id, 'approved', v_manager1, 'manager', 'Looks good');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  if v_profile.approval_status <> 'pending' then
    raise exception 'assertion failed: expected the vendor to remain pending after only step 1 of 2 approved, got %', v_profile.approval_status;
  end if;

  perform app.decide_vendor_activation_approval_step(v_step2_id, 'approved', v_finance1, 'finance', 'Approved');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  if v_profile.approval_status <> 'approved' then
    raise exception 'assertion failed: expected approval_status=approved once every required step passed, got %', v_profile.approval_status;
  end if;
  if v_profile.lifecycle_status <> 'approved' then
    raise exception 'assertion failed: expected lifecycle_status to still be approved (decide wrapper never itself activates), got %', v_profile.lifecycle_status;
  end if;

  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  if v_profile.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected active once governance approval cleared, got %', v_profile.lifecycle_status;
  end if;

  begin
    perform app.decide_vendor_activation_approval_step(v_step1_id, 'approved', v_manager1, 'manager', null);
    raise exception 'assertion failed: expected this to have thrown (request already resolved)';
  exception
    when others then
      if sqlerrm not like 'approval_request_not_pending:%' then
        raise;
      end if;
  end;
end;
$$;

\echo '>> app.decide_vendor_activation_approval_step refuses a non-vendor_activation approval request (not_a_vendor_activation_approval)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_manager1 uuid := '00000000-0000-0000-0000-000000394105';
  v_config_version_id uuid;
  v_generic_request app.approval_requests;
  v_generic_step_id uuid;
begin
  select cv.id into v_config_version_id
  from app.config_versions cv join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'approval' and co.tenant_id = v_tenant1 and co.scope_level = 'tenant' and cv.status = 'published';

  select * into v_generic_request from app.request_approval(v_config_version_id, v_tenant1, 'generic', null, 'idem-generic-apr-test', v_admin1, 'tenant admin');
  select id into v_generic_step_id from app.approval_request_steps where request_id = v_generic_request.id and step_order = 1;

  begin
    perform app.decide_vendor_activation_approval_step(v_generic_step_id, 'approved', v_manager1, 'manager', null);
    raise exception 'assertion failed: expected check_violation -- entity_type=generic is not a vendor activation approval';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'not_a_vendor_activation_approval:%' then
        raise exception 'assertion failed: expected not_a_vendor_activation_approval, got %', sqlerrm;
      end if;
  end;
end;
$$;

-- ===========================================================================
-- Rate approval binding
-- ===========================================================================

\echo '>> rate approval, no published rate_version policy: create_rate_version leaves governance_approval_status=not_required, approve_rate_version succeeds immediately'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_rate app.vendor_rate_versions;
begin
  v_rate := app.create_rate_version(
    v_tenant1, 'VENDOR-APR-1', 'Apr Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    v_admin1, 'admin'
  );
  if v_rate.governance_approval_status <> 'not_required' or v_rate.governance_approval_request_id is not null then
    raise exception 'assertion failed: expected governance_approval_status=not_required governance_approval_request_id=null (no published policy), got %/%', v_rate.governance_approval_status, v_rate.governance_approval_request_id;
  end if;

  v_rate := app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');
  if v_rate.approval_status <> 'approved' then
    raise exception 'assertion failed: expected approval_status=approved, got %', v_rate.approval_status;
  end if;
end;
$$;

\echo '>> published rate_version policy min_value_amount=5,000,000 IDR: a rate at 10,000,000 crosses it -- create_rate_version routes for real (governance_approval_status=pending); approve_rate_version is blocked (rate_governance_approval_pending) until resolved; after both steps approve, approve_rate_version succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_manager1 uuid := '00000000-0000-0000-0000-000000394105';
  v_finance1 uuid := '00000000-0000-0000-0000-000000394106';
  v_policy app.procurement_approval_policies;
  v_rate app.vendor_rate_versions;
  v_step1_id uuid;
  v_step2_id uuid;
begin
  select * into v_policy from app.create_procurement_approval_policy_version(v_tenant1, 'rate_version', 5000000, false, v_admin1, 'admin');
  select * into v_policy from app.publish_procurement_approval_policy_version(v_policy.id, v_policy.record_version, null, v_admin1, 'admin');

  v_rate := app.create_rate_version(
    v_tenant1, 'VENDOR-APR-2', 'Apr Ocean Line 2', 'ocean_freight', 'FCL', 'Jakarta', 'Medan', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    v_admin1, 'admin'
  );
  if v_rate.governance_approval_status <> 'pending' or v_rate.governance_approval_request_id is null then
    raise exception 'assertion failed: expected governance_approval_status=pending governance_approval_request_id set, got %/%', v_rate.governance_approval_status, v_rate.governance_approval_request_id;
  end if;
  if (select entity_type from app.approval_requests where id = v_rate.governance_approval_request_id) <> 'rate_version'
    or (select entity_id from app.approval_requests where id = v_rate.governance_approval_request_id) <> v_rate.id then
    raise exception 'assertion failed: expected the bound request to carry entity_type=rate_version entity_id=%', v_rate.id;
  end if;

  begin
    perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');
    raise exception 'assertion failed: expected rate_governance_approval_pending';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'rate_governance_approval_pending:%' then
        raise exception 'assertion failed: expected rate_governance_approval_pending, got %', sqlerrm;
      end if;
  end;

  select id into v_step1_id from app.approval_request_steps where request_id = v_rate.governance_approval_request_id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_rate.governance_approval_request_id and step_order = 2;
  perform app.decide_rate_version_approval_step(v_step1_id, 'approved', v_manager1, 'manager', null);
  perform app.decide_rate_version_approval_step(v_step2_id, 'approved', v_finance1, 'finance', null);

  select * into v_rate from app.vendor_rate_versions where id = v_rate.id;
  if v_rate.governance_approval_status <> 'approved' then
    raise exception 'assertion failed: expected governance_approval_status=approved once every required step passed, got %', v_rate.governance_approval_status;
  end if;

  v_rate := app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');
  if v_rate.approval_status <> 'approved' then
    raise exception 'assertion failed: expected the pre-existing approval_status to reach approved once governance cleared, got %', v_rate.approval_status;
  end if;
end;
$$;

\echo '>> a rate BELOW the published 5,000,000 IDR threshold never routes (governance_approval_status=not_required), approve_rate_version succeeds immediately'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_rate app.vendor_rate_versions;
begin
  v_rate := app.create_rate_version(
    v_tenant1, 'VENDOR-APR-3', 'Apr Ocean Line 3', 'ocean_freight', 'FCL', 'Jakarta', 'Semarang', '20ft',
    null, null, null, null, 'IDR', 1000000, null, '[]'::jsonb, now(), null, null,
    v_admin1, 'admin'
  );
  if v_rate.governance_approval_status <> 'not_required' then
    raise exception 'assertion failed: expected governance_approval_status=not_required below threshold, got %', v_rate.governance_approval_status;
  end if;
  v_rate := app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');
  if v_rate.approval_status <> 'approved' then
    raise exception 'assertion failed: expected approval_status=approved, got %', v_rate.approval_status;
  end if;
end;
$$;

-- ===========================================================================
-- Vendor selection/comparison approval binding
-- ===========================================================================

\echo '>> setup: sourcing (shortlist A) -> RFQ (issue invites A) -> one response -> close for comparison -> create comparison -> recommend'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000394102';
  v_request app.sourcing_requests;
  v_candidate app.sourcing_candidates;
  v_vendor_master uuid;
  v_rfq app.rfqs;
  v_invitation app.rfq_invitations;
begin
  v_request := app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days',
    'IDR', 50000000, v_staff1, now() + interval '20 days', 'idem-apr-sourcing-1', v_staff1, 'staff'
  );
  v_request := app.submit_sourcing_request(v_request.id, v_staff1, 'staff', v_request.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request.id, v_admin1, 'admin');

  select master_record_id into v_vendor_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Apr Vendor A';
  select * into v_candidate from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor_master;
  v_candidate := app.shortlist_sourcing_candidate(v_candidate.id, true, 'fit', v_staff1, 'staff', v_candidate.record_version);
  v_request := app.submit_sourcing_shortlist(v_request.id, v_staff1, 'staff', v_request.record_version);

  v_rfq := app.draft_rfq_from_sourcing(v_tenant1, v_request.id, v_staff1, 'idem-apr-rfq-1', v_staff1, 'staff');
  v_rfq := app.issue_rfq(v_rfq.id, now() + interval '5 days', v_rfq.record_version, v_staff1, 'staff');
  select * into v_invitation from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_master;
  perform app.submit_rfq_response(v_invitation.id, 'IDR', 15000000, now() + interval '30 days', 20, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-apr-resp-a', v_staff1, 'staff');
  v_rfq := app.close_rfq_for_comparison(v_rfq.id, v_rfq.record_version, v_staff1, 'staff');
end;
$$;

\echo '>> vendor selection, no published vendor_selection policy: submit_vendor_comparison_for_approval leaves approval_status=not_required (status still reaches submitted)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000394102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000394103';
  v_rfq_id uuid;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
begin
  select id into v_rfq_id from app.rfqs where tenant_id = v_tenant1 and status = 'closed' order by created_at asc limit 1;
  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, null, 'idem-apr-cmp-1', v_staff1, 'staff');
  select * into v_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id limit 1;
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_offer.id, null, v_comparison.record_version, v_staff1, 'staff');

  v_comparison := app.submit_vendor_comparison_for_approval(v_comparison.id, v_offer.id, null, v_comparison.record_version, v_approver1, 'approver');
  if v_comparison.status <> 'submitted' or v_comparison.approval_status <> 'not_required' or v_comparison.approval_request_id is not null then
    raise exception 'assertion failed: expected status=submitted approval_status=not_required approval_request_id=null (no published policy), got %/%/%', v_comparison.status, v_comparison.approval_status, v_comparison.approval_request_id;
  end if;
end;
$$;

\echo '>> published vendor_selection policy always_required=true: submit_vendor_comparison_for_approval routes for real (approval_status=pending, entity_type=vendor_selection); after both routing steps approve, approval_status syncs to approved (status stays submitted throughout -- the release gate is Prompt 260''s own future PO-award RPC, not this migration)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000394102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000394103';
  v_manager1 uuid := '00000000-0000-0000-0000-000000394105';
  v_finance1 uuid := '00000000-0000-0000-0000-000000394106';
  v_policy app.procurement_approval_policies;
  v_request2 app.sourcing_requests;
  v_candidate2 app.sourcing_candidates;
  v_vendor_master uuid;
  v_rfq2 app.rfqs;
  v_invitation2 app.rfq_invitations;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
  v_step1_id uuid;
  v_step2_id uuid;
begin
  select * into v_policy from app.create_procurement_approval_policy_version(v_tenant1, 'vendor_selection', null, true, v_admin1, 'admin');
  select * into v_policy from app.publish_procurement_approval_policy_version(v_policy.id, v_policy.record_version, null, v_admin1, 'admin');

  -- A second, independent sourcing -> RFQ -> comparison chain so this test is isolated
  -- from the not_required case above (that comparison is already terminal/submitted).
  v_request2 := app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days',
    'IDR', 50000000, v_staff1, now() + interval '20 days', 'idem-apr-sourcing-2', v_staff1, 'staff'
  );
  v_request2 := app.submit_sourcing_request(v_request2.id, v_staff1, 'staff', v_request2.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request2.id, v_admin1, 'admin');
  select master_record_id into v_vendor_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Apr Vendor A';
  select * into v_candidate2 from app.sourcing_candidates where sourcing_request_id = v_request2.id and vendor_master_id = v_vendor_master;
  v_candidate2 := app.shortlist_sourcing_candidate(v_candidate2.id, true, 'fit', v_staff1, 'staff', v_candidate2.record_version);
  v_request2 := app.submit_sourcing_shortlist(v_request2.id, v_staff1, 'staff', v_request2.record_version);
  v_rfq2 := app.draft_rfq_from_sourcing(v_tenant1, v_request2.id, v_staff1, 'idem-apr-rfq-2', v_staff1, 'staff');
  v_rfq2 := app.issue_rfq(v_rfq2.id, now() + interval '5 days', v_rfq2.record_version, v_staff1, 'staff');
  select * into v_invitation2 from app.rfq_invitations where rfq_id = v_rfq2.id and vendor_master_id = v_vendor_master;
  perform app.submit_rfq_response(v_invitation2.id, 'IDR', 16000000, now() + interval '30 days', 20, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-apr-resp-a2', v_staff1, 'staff');
  v_rfq2 := app.close_rfq_for_comparison(v_rfq2.id, v_rfq2.record_version, v_staff1, 'staff');

  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq2.id, 'IDR', null, null, null, null, 'idem-apr-cmp-2', v_staff1, 'staff');
  select * into v_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id limit 1;
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_offer.id, null, v_comparison.record_version, v_staff1, 'staff');

  v_comparison := app.submit_vendor_comparison_for_approval(v_comparison.id, v_offer.id, null, v_comparison.record_version, v_approver1, 'approver');
  if v_comparison.status <> 'submitted' or v_comparison.approval_status <> 'pending' or v_comparison.approval_request_id is null then
    raise exception 'assertion failed: expected status=submitted approval_status=pending approval_request_id set, got %/%/%', v_comparison.status, v_comparison.approval_status, v_comparison.approval_request_id;
  end if;
  if (select entity_type from app.approval_requests where id = v_comparison.approval_request_id) <> 'vendor_selection' then
    raise exception 'assertion failed: expected entity_type=vendor_selection';
  end if;

  select id into v_step1_id from app.approval_request_steps where request_id = v_comparison.approval_request_id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_comparison.approval_request_id and step_order = 2;
  perform app.decide_vendor_selection_approval_step(v_step1_id, 'approved', v_manager1, 'manager', null);
  perform app.decide_vendor_selection_approval_step(v_step2_id, 'approved', v_finance1, 'finance', null);

  select * into v_comparison from app.vendor_comparisons where id = v_comparison.id;
  if v_comparison.approval_status <> 'approved' then
    raise exception 'assertion failed: expected approval_status=approved once every required step passed, got %', v_comparison.approval_status;
  end if;
  if v_comparison.status <> 'submitted' then
    raise exception 'assertion failed: expected status to remain submitted (the sync wrapper never itself performs a further release), got %', v_comparison.status;
  end if;
end;
$$;

\echo '>> a fresh, second-tenant comparison rejection: manager rejects step 1, approval_status syncs to rejected, request itself is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000394102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000394103';
  v_manager1 uuid := '00000000-0000-0000-0000-000000394105';
  v_request3 app.sourcing_requests;
  v_candidate3 app.sourcing_candidates;
  v_vendor_master uuid;
  v_rfq3 app.rfqs;
  v_invitation3 app.rfq_invitations;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
  v_step1_id uuid;
begin
  v_request3 := app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days',
    'IDR', 50000000, v_staff1, now() + interval '20 days', 'idem-apr-sourcing-3', v_staff1, 'staff'
  );
  v_request3 := app.submit_sourcing_request(v_request3.id, v_staff1, 'staff', v_request3.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request3.id, v_admin1, 'admin');
  select master_record_id into v_vendor_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Apr Vendor A';
  select * into v_candidate3 from app.sourcing_candidates where sourcing_request_id = v_request3.id and vendor_master_id = v_vendor_master;
  v_candidate3 := app.shortlist_sourcing_candidate(v_candidate3.id, true, 'fit', v_staff1, 'staff', v_candidate3.record_version);
  v_request3 := app.submit_sourcing_shortlist(v_request3.id, v_staff1, 'staff', v_request3.record_version);
  v_rfq3 := app.draft_rfq_from_sourcing(v_tenant1, v_request3.id, v_staff1, 'idem-apr-rfq-3', v_staff1, 'staff');
  v_rfq3 := app.issue_rfq(v_rfq3.id, now() + interval '5 days', v_rfq3.record_version, v_staff1, 'staff');
  select * into v_invitation3 from app.rfq_invitations where rfq_id = v_rfq3.id and vendor_master_id = v_vendor_master;
  perform app.submit_rfq_response(v_invitation3.id, 'IDR', 17000000, now() + interval '30 days', 20, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-apr-resp-a3', v_staff1, 'staff');
  v_rfq3 := app.close_rfq_for_comparison(v_rfq3.id, v_rfq3.record_version, v_staff1, 'staff');

  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq3.id, 'IDR', null, null, null, null, 'idem-apr-cmp-3', v_staff1, 'staff');
  select * into v_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id limit 1;
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
  v_comparison := app.submit_vendor_comparison_for_approval(v_comparison.id, v_offer.id, null, v_comparison.record_version, v_approver1, 'approver');

  select id into v_step1_id from app.approval_request_steps where request_id = v_comparison.approval_request_id and step_order = 1;
  perform app.decide_vendor_selection_approval_step(v_step1_id, 'rejected', v_manager1, 'manager', 'Price too high vs. budget');

  select * into v_comparison from app.vendor_comparisons where id = v_comparison.id;
  if v_comparison.approval_status <> 'rejected' then
    raise exception 'assertion failed: expected approval_status=rejected, got %', v_comparison.approval_status;
  end if;
  if (select status from app.approval_requests where id = v_comparison.approval_request_id) <> 'rejected' then
    raise exception 'assertion failed: expected the bound request itself to be rejected';
  end if;
end;
$$;

-- ===========================================================================
-- Exception/override binding
-- ===========================================================================

\echo '>> app.create_procurement_exception_request: permission-denied (no Override), reason/exception_type required, cross-tenant tenant_mismatch via wrong actor, then a real create with no published exception_override policy (auto-approved immediately, status=approved)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'apr2');
  v_staff1 uuid := '00000000-0000-0000-0000-000000394102';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000394104';
  v_staff2 uuid := '00000000-0000-0000-0000-000000394202';
  v_req app.procurement_exception_requests;
begin
  begin
    perform app.create_procurement_exception_request(v_tenant1, 'vendor_activation', null, 'expedited_activation', 'urgent shipment', null, 'idem-apr-exc-denied', v_outsider1, 'outsider');
    raise exception 'assertion failed: expected insufficient_privilege -- outsider holds no PRC:Override';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  begin
    perform app.create_procurement_exception_request(v_tenant1, 'vendor_activation', null, 'expedited_activation', '', null, 'idem-apr-exc-noreason', v_staff1, 'staff');
    raise exception 'assertion failed: expected check_violation -- empty reason';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'reason_required:%' then
        raise exception 'assertion failed: expected reason_required, got %', sqlerrm;
      end if;
  end;

  -- Tenant2's own staff acting for tenant1: evaluate_permission resolves against
  -- tenant1's own role assignments, which staff2 holds none of -- denied, never a
  -- cross-tenant read leak.
  begin
    perform app.create_procurement_exception_request(v_tenant1, 'vendor_activation', null, 'expedited_activation', 'urgent shipment', null, 'idem-apr-exc-xtenant', v_staff2, 'staff2');
    raise exception 'assertion failed: expected insufficient_privilege -- staff2 holds no PRC role in tenant1';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_req from app.create_procurement_exception_request(v_tenant1, 'vendor_activation', null, 'expedited_activation', 'urgent shipment for a strategic customer', 'skip 2nd review step', 'idem-apr-exc-1', v_staff1, 'staff');
  if v_req.status <> 'approved' or v_req.approval_status <> 'not_required' or v_req.approval_request_id is not null then
    raise exception 'assertion failed: expected status=approved approval_status=not_required approval_request_id=null (no published policy), got %/%/%', v_req.status, v_req.approval_status, v_req.approval_request_id;
  end if;
end;
$$;

\echo '>> idempotency replay: same key + identical tuple short-circuits to the same row; same key + a different reason raises idempotency_key_conflict (taxonomy C-01, full target tuple compared, not just the key)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000394102';
  v_req1 app.procurement_exception_requests;
  v_req2 app.procurement_exception_requests;
begin
  select * into v_req1 from app.create_procurement_exception_request(v_tenant1, 'rate_version', null, 'manual_price_match', 'match competitor quote', null, 'idem-apr-exc-replay', v_staff1, 'staff');
  select * into v_req2 from app.create_procurement_exception_request(v_tenant1, 'rate_version', null, 'manual_price_match', 'match competitor quote', null, 'idem-apr-exc-replay', v_staff1, 'staff');
  if v_req1.id <> v_req2.id then
    raise exception 'assertion failed: expected the identical-tuple replay to return the SAME row';
  end if;

  begin
    perform app.create_procurement_exception_request(v_tenant1, 'rate_version', null, 'manual_price_match', 'a completely different reason', null, 'idem-apr-exc-replay', v_staff1, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict -- same key, different reason';
  exception
    when unique_violation then
      if sqlerrm not like 'idempotency_key_conflict:%' then
        raise exception 'assertion failed: expected idempotency_key_conflict, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> published exception_override policy always_required=true: create routes for real (status=submitted, approval_status=pending); manager+finance approve both routing steps, decide wrapper syncs BOTH approval_status and status to approved (the grant IS the terminal outcome for this entity); cancel is then blocked because status is no longer submitted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000394101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000394102';
  v_manager1 uuid := '00000000-0000-0000-0000-000000394105';
  v_finance1 uuid := '00000000-0000-0000-0000-000000394106';
  v_policy app.procurement_approval_policies;
  v_req app.procurement_exception_requests;
  v_step1_id uuid;
  v_step2_id uuid;
begin
  select * into v_policy from app.create_procurement_approval_policy_version(v_tenant1, 'exception_override', null, true, v_admin1, 'admin');
  select * into v_policy from app.publish_procurement_approval_policy_version(v_policy.id, v_policy.record_version, null, v_admin1, 'admin');

  select * into v_req from app.create_procurement_exception_request(v_tenant1, 'purchase_order', null, 'po_threshold_bypass', 'emergency spare parts order, PO threshold not met but customer SLA at risk', null, 'idem-apr-exc-routed', v_staff1, 'staff');
  if v_req.status <> 'submitted' or v_req.approval_status <> 'pending' or v_req.approval_request_id is null then
    raise exception 'assertion failed: expected status=submitted approval_status=pending approval_request_id set, got %/%/%', v_req.status, v_req.approval_status, v_req.approval_request_id;
  end if;
  if (select entity_type from app.approval_requests where id = v_req.approval_request_id) <> 'exception_override'
    or (select entity_id from app.approval_requests where id = v_req.approval_request_id) <> v_req.id then
    raise exception 'assertion failed: expected the bound request to carry entity_type=exception_override entity_id=%', v_req.id;
  end if;

  select id into v_step1_id from app.approval_request_steps where request_id = v_req.approval_request_id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_req.approval_request_id and step_order = 2;
  perform app.decide_procurement_exception_approval_step(v_step1_id, 'approved', v_manager1, 'manager', null);

  -- Still mid-routing (1 of 2 steps approved) -- status stays submitted until the
  -- request reaches a final state, so a withdrawal here is still legitimate business
  -- behavior (mirrors "requesters submit/withdraw eligible records," access rule §26)
  -- and is not itself under test in this block.

  perform app.decide_procurement_exception_approval_step(v_step2_id, 'approved', v_finance1, 'finance', null);

  select * into v_req from app.procurement_exception_requests where id = v_req.id;
  if v_req.approval_status <> 'approved' or v_req.status <> 'approved' then
    raise exception 'assertion failed: expected BOTH approval_status and status to reach approved, got %/%', v_req.approval_status, v_req.status;
  end if;

  begin
    perform app.cancel_procurement_exception_request(v_req.id, v_req.record_version, 'too late now', v_admin1, 'admin');
    raise exception 'assertion failed: expected invalid_transition -- status is now approved, no longer submitted';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'invalid_transition:%' then
        raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> cancel: a pending (not yet decided) exception request can be withdrawn by its requester; the bound approval_requests row is cancelled too'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000394102';
  v_req app.procurement_exception_requests;
begin
  select * into v_req from app.create_procurement_exception_request(v_tenant1, 'exception_override', null, 'waive_compliance_doc', 'renew insurance certificate next week', null, 'idem-apr-exc-cancel', v_staff1, 'staff');
  if v_req.status <> 'submitted' or v_req.approval_status <> 'pending' then
    raise exception 'assertion failed: expected status=submitted approval_status=pending, got %/%', v_req.status, v_req.approval_status;
  end if;

  select * into v_req from app.cancel_procurement_exception_request(v_req.id, v_req.record_version, 'no longer needed', v_staff1, 'staff');
  if v_req.status <> 'cancelled' then
    raise exception 'assertion failed: expected status=cancelled, got %', v_req.status;
  end if;
  if (select status from app.approval_requests where id = v_req.approval_request_id) <> 'cancelled' then
    raise exception 'assertion failed: expected the bound approval request to also be cancelled';
  end if;
end;
$$;

\echo '>> app.get_procurement_approval_context_snapshot: value_amount/currency masked (null, cost_masked=true) for a viewer without PRC:View cost, visible for staff1 (holds View cost); reasons/entity_type always visible regardless'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000394102';
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_viewer1 uuid := '00000000-0000-0000-0000-000000394104';
  v_request_id uuid;
  v_amount numeric;
  v_currency text;
  v_masked boolean;
  v_reasons text[];
begin
  -- Reuse outsider1's identity but grant it a View-only role for this one check
  -- (outsider1 otherwise holds zero PRC permissions, proven above).
  v_viewer_role := (app.create_role(v_tenant1, 'Apr1 View Only', 'PRC:View only, no View cost', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, '00000000-0000-0000-0000-000000394101', 'admin');

  select governance_approval_request_id into v_request_id from app.vendor_rate_versions where tenant_id = v_tenant1 and origin_lane = 'Jakarta' and destination_lane = 'Medan';

  select value_amount, currency, cost_masked, reasons into v_amount, v_currency, v_masked, v_reasons
  from app.get_procurement_approval_context_snapshot(v_request_id, v_viewer1);
  if v_amount is not null or v_currency is not null or not v_masked then
    raise exception 'assertion failed: expected value_amount/currency masked (null, cost_masked=true) for a View-cost-less viewer, got %/%/%', v_amount, v_currency, v_masked;
  end if;
  if v_reasons is null or array_length(v_reasons, 1) is null then
    raise exception 'assertion failed: expected reasons to remain visible regardless of cost masking';
  end if;

  select value_amount, currency, cost_masked into v_amount, v_currency, v_masked
  from app.get_procurement_approval_context_snapshot(v_request_id, v_staff1);
  if v_amount is null or v_currency is null or v_masked then
    raise exception 'assertion failed: expected value_amount/currency visible for staff1 (holds View cost), got %/%/%', v_amount, v_currency, v_masked;
  end if;
  if v_amount <> 10000000 or v_currency <> 'IDR' then
    raise exception 'assertion failed: expected the exact snapshotted amount/currency (10000000/IDR), got %/%', v_amount, v_currency;
  end if;
end;
$$;

\echo '>> RLS: app.procurement_approval_policies is directly readable by any active tenant member (tenant-wide reference data, unmasked); a sibling-tenant actor sees zero rows'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_visible_count integer;
  v_xtenant_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000394102", "role": "authenticated"}';
  select count(*) into v_visible_count from app.procurement_approval_policies where tenant_id = v_tenant1;
  if v_visible_count < 3 then
    raise exception 'assertion failed: expected staff1 to see at least the 3 published policies created above, got %', v_visible_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000394202", "role": "authenticated"}';
  select count(*) into v_xtenant_count from app.procurement_approval_policies where tenant_id = v_tenant1;
  if v_xtenant_count <> 0 then
    raise exception 'assertion failed: expected the sibling-tenant actor to be denied via record-scope, found % row(s)', v_xtenant_count;
  end if;
  reset role;
end;
$$;

\echo '>> audit trail: every real governed decision self-captured a canonical app.audit_logs entry'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'apr1');
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.vendor_profiles' and action = 'decide_vendor_profile_review' and tenant_id = v_tenant1;
  if v_count < 2 then raise exception 'assertion failed: expected at least 2 decide_vendor_profile_review audit events, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.procurement_exception_requests' and action = 'create_procurement_exception_request' and tenant_id = v_tenant1;
  if v_count <> 4 then raise exception 'assertion failed: expected exactly 4 successful create_procurement_exception_request audit events (denied/reason-less/cross-tenant attempts left no trace, the idempotency replay is a second real call), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.approval_request_steps' and action = 'decide_approval_step' and tenant_id = v_tenant1;
  if v_count < 8 then raise exception 'assertion failed: expected at least 8 successful decide_approval_step audit events across vendor activation/rate/selection/exception, found %', v_count; end if;
end;
$$;
