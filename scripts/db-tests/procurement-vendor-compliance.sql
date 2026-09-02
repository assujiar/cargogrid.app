-- Real, executable test evidence for PRC-253 (Compliance and Document Expiry,
-- CG-S11-PRC-004) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (pcmp1, pcmp2). pcmp1 gets a tenant_admin, PRC staff (Create/Edit/View), an approver (Approve/Reject/View), an override manager (Override/Create/Edit/View), a view-only actor, and a customer_user-layer actor. pcmp2 gets a tenant_admin and a staff actor for cross-tenant checks. A global Supreme Admin is also seeded.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_manager_role uuid;
  v_manager_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000091101', 'admin@pcmp1.test'),
    ('00000000-0000-0000-0000-000000091102', 'staff@pcmp1.test'),
    ('00000000-0000-0000-0000-000000091103', 'approver@pcmp1.test'),
    ('00000000-0000-0000-0000-000000091104', 'manager@pcmp1.test'),
    ('00000000-0000-0000-0000-000000091105', 'viewer@pcmp1.test'),
    ('00000000-0000-0000-0000-000000091106', 'customer@pcmp1.test'),
    ('00000000-0000-0000-0000-000000091107', 'reviewer@pcmp1.test'),
    ('00000000-0000-0000-0000-000000091201', 'admin@pcmp2.test'),
    ('00000000-0000-0000-0000-000000091202', 'staff@pcmp2.test'),
    ('00000000-0000-0000-0000-000000091999', 'supreme@pcmp.test');

  perform app.provision_tenant('pcmp1', 'Vendor Compliance Co 1', 'idem-pcmp1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'pcmp1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('pcmp2', 'Vendor Compliance Co 2', 'idem-pcmp2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'pcmp2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000091101', 'admin@pcmp1.test', 'Pcmp1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@pcmp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000091101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000091102', 'staff@pcmp1.test', 'Pcmp1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@pcmp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000091103', 'approver@pcmp1.test', 'Pcmp1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@pcmp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000091104', 'manager@pcmp1.test', 'Pcmp1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@pcmp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000091105', 'viewer@pcmp1.test', 'Pcmp1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@pcmp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000091106', 'customer@pcmp1.test', 'Pcmp1 Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@pcmp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000091106', 'customer_user', v_tenant1, 'external-customer-account', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000091201', 'admin@pcmp2.test', 'Pcmp2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@pcmp2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000091201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000091202', 'staff@pcmp2.test', 'Pcmp2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@pcmp2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000091999', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'PRC Compliance Staff', 'Create/Edit/View/Download', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'Download')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000091102', '00000000-0000-0000-0000-000000091101', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'PRC Compliance Approver', 'Approve/Reject/View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Approve', 'Reject', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000091103', '00000000-0000-0000-0000-000000091101', 'tester');

  v_manager_role := (app.create_role(v_tenant1, 'PRC Compliance Manager', 'Override/Create/Edit/View', 'tester')).id;
  v_manager_draft := app.create_role_version(v_manager_role, 'tester');
  perform app.set_role_version_permissions(v_manager_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Override', 'Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000091104', '00000000-0000-0000-0000-000000091101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'PRC Compliance Viewer', 'View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000091105', '00000000-0000-0000-0000-000000091101', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'PRC Compliance Staff T2', 'Create/Edit/View', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000091202', '00000000-0000-0000-0000-000000091201', 'tester');
end $$;

\echo '>> setup: a trucking vendor and a warehousing vendor in pcmp1 (for vendor_category scope-mismatch tests), plus one pcmp2 vendor; register + publish the vendor_compliance_document document type in both tenants'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pcmp2');
  v_admin1 uuid := '00000000-0000-0000-0000-000000091101';
  v_admin2 uuid := '00000000-0000-0000-0000-000000091201';
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_t2_staff uuid := '00000000-0000-0000-0000-000000091202';
  v_profile app.vendor_profiles;
  v_wh_profile app.vendor_profiles;
  v_doctype_draft app.config_versions;
  v_t2_doctype_draft app.config_versions;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Contoso Trucking', 'Contoso', 'PT', 'REG-9201', 'trucking', 30, 'staff_created', 'idem-pcmp-vendor-1', v_staff, 'staff');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Jane Vendor', 'Ops Manager', 'jane@contoso-pcmp.test', '0811-920-001', true, v_staff, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'trucking', v_staff, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'linehaul', v_staff, 'staff');

  v_wh_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Contoso Warehousing', null, 'PT', 'REG-9202', 'warehousing', 30, 'staff_created', 'idem-pcmp-vendor-wh', v_staff, 'staff');
  perform app.add_vendor_service(v_wh_profile.master_record_id, 'warehousing', v_staff, 'staff');

  perform app.create_vendor_profile_draft(v_tenant2, 'PT Pcmp2 Vendor', null, 'PT', 'REG-9301', 'trucking', 30, 'staff_created', 'idem-pcmp2-vendor-1', v_t2_staff, 'staff');

  perform app.register_document_type('vendor_compliance_document', 'Vendor Compliance Document', 'DOC', '00000000-0000-0000-0000-000000091999', 'supreme');
  v_doctype_draft := app.create_config_draft('document:vendor_compliance_document', v_tenant1, 'tenant', null, v_admin1, 'admin');
  perform app.set_config_items(v_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(true))
  ), v_admin1, 'admin');
  perform app.publish_document_type_definition(v_doctype_draft.id, v_admin1, now(), 'admin');

  v_t2_doctype_draft := app.create_config_draft('document:vendor_compliance_document', v_tenant2, 'tenant', null, v_admin2, 'admin2');
  perform app.set_config_items(v_t2_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_admin2, 'admin2');
  perform app.publish_document_type_definition(v_t2_doctype_draft.id, v_admin2, now(), 'admin2');
end $$;

\echo '>> requirement lifecycle: draft -> validation (bad blocking_effect, unregistered doc type, non-positive reminder offset) -> publish (approver only) -> archive; idempotency-key replay and mismatch; stale_version rejection; scope-tuple uniqueness'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_approver uuid := '00000000-0000-0000-0000-000000091103';
  v_viewer uuid := '00000000-0000-0000-0000-000000091105';
  v_req app.vendor_compliance_requirements;
  v_req2 app.vendor_compliance_requirements;
  v_replay app.vendor_compliance_requirements;
begin
  -- unregistered document type is rejected up front.
  begin
    perform app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'not_a_real_doctype', 'Business License', null, 'blocking', true, array[30,14,7], now(), 'idem-pcmp-req-bad-doctype', v_staff, 'staff');
    raise exception 'assertion failed: expected document_type_not_registered';
  exception
    when others then
      if sqlerrm not like 'document_type_not_registered%' then raise; end if;
  end;

  v_req := app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'Business License', 'annual license', 'blocking', true, array[30,14,7], now(), 'idem-pcmp-req-1', v_staff, 'staff');
  if v_req.status <> 'draft' or v_req.requirement_family_id is null then
    raise exception 'assertion failed: expected draft with a minted requirement_family_id, got status=%', v_req.status;
  end if;

  -- idempotency-key replay returns the same row; target mismatch is rejected.
  v_replay := app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'Business License', 'annual license', 'blocking', true, array[30,14,7], now(), 'idem-pcmp-req-1', v_staff, 'staff');
  if v_replay.id <> v_req.id then
    raise exception 'assertion failed: expected idempotency replay to return the exact same row';
  end if;
  begin
    perform app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'A Completely Different Name', null, 'blocking', true, array[30], now(), 'idem-pcmp-req-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different name';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- fix-pass addition (MEDIUM-severity finding, adversarial review): a reused key
  -- with the IDENTICAL name/scope but a DIFFERENT reminder_offsets schedule (drives
  -- the expiring_soon threshold) is likewise rejected, not silently ignored.
  begin
    perform app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'Business License', 'annual license', 'blocking', true, array[90,60,30], now(), 'idem-pcmp-req-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different reminder_offsets schedule';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  -- an explicit, different effective_from is likewise rejected...
  begin
    perform app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'Business License', 'annual license', 'blocking', true, array[30,14,7], now() + interval '30 days', 'idem-pcmp-req-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different explicit effective_from';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  -- ...but omitting effective_from on the replay (relying on the default) is never a
  -- spurious mismatch against whatever concrete timestamp was actually stored.
  if (app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'Business License', 'annual license', 'blocking', true, array[30,14,7], null, 'idem-pcmp-req-1', v_staff, 'staff')).id <> v_req.id then
    raise exception 'assertion failed: expected an omitted effective_from on replay to never be treated as a mismatch';
  end if;

  -- invalid blocking_effect / non-positive reminder offset.
  begin
    perform app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'Bad Blocking', null, 'sometimes', true, array[30], now(), 'idem-pcmp-req-badblocking', v_staff, 'staff');
    raise exception 'assertion failed: expected invalid_blocking_effect';
  exception
    when others then
      if sqlerrm not like 'invalid_blocking_effect%' then raise; end if;
  end;
  begin
    perform app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'Bad Offset', null, 'blocking', true, array[0], now(), 'idem-pcmp-req-badoffset', v_staff, 'staff');
    raise exception 'assertion failed: expected invalid_reminder_offset';
  exception
    when others then
      if sqlerrm not like 'invalid_reminder_offset%' then raise; end if;
  end;

  -- a viewer (View only) cannot publish (requires PRC:Approve).
  begin
    perform app.publish_vendor_compliance_requirement(v_req.id, v_req.record_version, null, v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for viewer publishing';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  -- staff (no Approve) cannot publish either.
  begin
    perform app.publish_vendor_compliance_requirement(v_req.id, v_req.record_version, null, v_staff, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for staff publishing';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- stale_version: update using an expired expected_version.
  perform app.update_vendor_compliance_requirement_draft(v_req.id, v_req.record_version, 'trucking', null, 'vendor_compliance_document', 'Business License (renamed)', 'annual license', 'blocking', true, array[30,14,7], now(), v_staff, 'staff');
  begin
    perform app.update_vendor_compliance_requirement_draft(v_req.id, v_req.record_version, 'trucking', null, 'vendor_compliance_document', 'Another rename', null, 'blocking', true, array[30], now(), v_staff, 'staff');
    raise exception 'assertion failed: expected stale_version on update with a stale expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  select * into v_req from app.vendor_compliance_requirements where id = v_req.id;

  v_req := app.publish_vendor_compliance_requirement(v_req.id, v_req.record_version, null, v_approver, 'approver');
  if v_req.status <> 'published' then
    raise exception 'assertion failed: expected published, got %', v_req.status;
  end if;

  -- publishing a draft is a one-way transition -- a second publish on the same row fails.
  begin
    perform app.publish_vendor_compliance_requirement(v_req.id, v_req.record_version, null, v_approver, 'approver');
    raise exception 'assertion failed: expected invalid_transition republishing an already-published requirement';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- scope-tuple uniqueness: a second, independent (not a supersede) requirement
  -- targeting the identical tenant/vendor_category/service_type/document_type_code
  -- cannot also publish.
  v_req2 := app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'Duplicate Scope License', null, 'blocking', true, array[30], now(), 'idem-pcmp-req-dupscope', v_staff, 'staff');
  begin
    perform app.publish_vendor_compliance_requirement(v_req2.id, v_req2.record_version, null, v_approver, 'approver');
    raise exception 'assertion failed: expected active_requirement_exists for a second independent published requirement at the same scope';
  exception
    when others then
      if sqlerrm not like 'active_requirement_exists%' then raise; end if;
  end;
  -- but publishing it AS a supersede of the first one succeeds, archiving the first
  -- and carrying its requirement_family_id forward.
  select * into v_req from app.vendor_compliance_requirements where id = v_req.id;
  v_req2 := app.publish_vendor_compliance_requirement(v_req2.id, v_req2.record_version, v_req.id, v_approver, 'approver');
  select * into v_req from app.vendor_compliance_requirements where id = v_req.id;
  if v_req.status <> 'archived' or v_req2.requirement_family_id <> v_req.requirement_family_id then
    raise exception 'assertion failed: expected the first requirement archived and the second to carry its requirement_family_id forward, got status=% family_match=%', v_req.status, (v_req2.requirement_family_id = v_req.requirement_family_id);
  end if;

  -- archive with a mandatory non-empty reason.
  begin
    perform app.archive_vendor_compliance_requirement(v_req2.id, v_req2.record_version, '', v_staff, 'staff');
    raise exception 'assertion failed: expected reason_required for an empty archive reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;
end $$;

\echo '>> a second, warning-effect, non-expiring requirement targeting warehousing only (for the requirement_not_applicable and requires_expiry=false paths)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_approver uuid := '00000000-0000-0000-0000-000000091103';
  v_req app.vendor_compliance_requirements;
begin
  v_req := app.create_vendor_compliance_requirement_draft(v_tenant1, 'warehousing', null, 'vendor_compliance_document', 'Warehouse Safety Poster', 'never expires, warning only', 'warning', false, array[30], now(), 'idem-pcmp-req-warehouse-warning', v_staff, 'staff');
  v_req := app.publish_vendor_compliance_requirement(v_req.id, v_req.record_version, null, v_approver, 'approver');
  if v_req.blocking_effect <> 'warning' or v_req.requires_expiry then
    raise exception 'assertion failed: expected a published warning/non-expiring requirement';
  end if;
end $$;

\echo '>> document lifecycle: unsafe (pending-scan) upload rejected; cross-tenant and wrong-record-type evidence rejected; requirement_not_applicable for wrong vendor_category; requirement_not_published for a draft requirement; inconsistent issue/expiry rejected; a clean, correctly-scoped upload submits, verifies, and drives the eligibility-hold projection'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pcmp2');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_t2_staff uuid := '00000000-0000-0000-0000-000000091202';
  v_approver uuid := '00000000-0000-0000-0000-000000091103';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_wh_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-wh');
  v_req_id uuid := (select id from app.vendor_compliance_requirements where tenant_id = v_tenant1 and status = 'published' and vendor_category = 'trucking');
  v_draft_req app.vendor_compliance_requirements;
  v_file app.files;
  v_foreign_file app.files;
  v_wrong_record_file app.files;
  v_doc app.vendor_compliance_documents;
begin
  v_file := app.initiate_file_upload(
    v_tenant1, 'vendor_compliance_document', 'vendor_compliance', v_vendor_id,
    'business-license.pdf', 'application/pdf', 51200, 'internal', false, null, null, null,
    'idem-pcmp-evidence-1', v_staff, 'staff'
  );

  -- still pending scan -- rejected.
  begin
    perform app.submit_vendor_compliance_document(v_vendor_id, v_req_id, v_file.id, current_date - 300, current_date + 10, 'idem-pcmp-doc-1', v_staff, 'staff');
    raise exception 'assertion failed: expected compliance_unsafe_evidence for a still-pending-scan file';
  exception
    when others then
      if sqlerrm not like 'compliance_unsafe_evidence%' then raise; end if;
  end;

  -- cross-tenant evidence laundering is rejected even once scanned clean.
  v_foreign_file := app.initiate_file_upload(
    v_tenant2, 'vendor_compliance_document', 'vendor_compliance', gen_random_uuid(),
    'unrelated-pcmp2-file.pdf', 'application/pdf', 1024, 'internal', false, null, null, null,
    'idem-pcmp2-foreign-evidence', v_t2_staff, 'staff2'
  );
  perform app.record_file_scan_result(v_foreign_file.id, 'clean', 'test-scanner-ref', v_t2_staff, 'staff2');
  begin
    perform app.submit_vendor_compliance_document(v_vendor_id, v_req_id, v_foreign_file.id, current_date - 300, current_date + 10, 'idem-pcmp-doc-foreign', v_staff, 'staff');
    raise exception 'assertion failed: expected compliance_evidence_file_mismatch for a cross-tenant file';
  exception
    when others then
      if sqlerrm not like 'compliance_evidence_file_mismatch%' then raise; end if;
  end;

  -- same-tenant, wrong record_type/record_id is also rejected.
  v_wrong_record_file := app.initiate_file_upload(
    v_tenant1, 'vendor_compliance_document', 'vendor_profile', v_vendor_id,
    'wrong-record-type.pdf', 'application/pdf', 1024, 'internal', false, null, null, null,
    'idem-pcmp-wrongrecord-evidence', v_staff, 'staff'
  );
  perform app.record_file_scan_result(v_wrong_record_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  begin
    perform app.submit_vendor_compliance_document(v_vendor_id, v_req_id, v_wrong_record_file.id, current_date - 300, current_date + 10, 'idem-pcmp-doc-wrongrecord', v_staff, 'staff');
    raise exception 'assertion failed: expected compliance_evidence_file_mismatch for a wrong record_type file';
  exception
    when others then
      if sqlerrm not like 'compliance_evidence_file_mismatch%' then raise; end if;
  end;

  -- requirement_not_applicable: the trucking-scoped requirement does not apply to the warehousing vendor.
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  begin
    perform app.submit_vendor_compliance_document(v_wh_vendor_id, v_req_id, v_file.id, current_date - 300, current_date + 10, 'idem-pcmp-doc-wrongvendor', v_staff, 'staff');
    raise exception 'assertion failed: expected requirement_not_applicable for a warehousing vendor against a trucking-scoped requirement';
  exception
    when others then
      if sqlerrm not like 'requirement_not_applicable%' then raise; end if;
  end;

  -- requirement_not_published: a still-draft requirement cannot receive a submission.
  v_draft_req := app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', null, 'vendor_compliance_document', 'Still Draft Requirement', null, 'blocking', true, array[30], now(), 'idem-pcmp-req-stilldraft', v_staff, 'staff');
  begin
    perform app.submit_vendor_compliance_document(v_vendor_id, v_draft_req.id, v_file.id, current_date - 300, current_date + 10, 'idem-pcmp-doc-draftreq', v_staff, 'staff');
    raise exception 'assertion failed: expected requirement_not_published for a draft requirement';
  exception
    when others then
      if sqlerrm not like 'requirement_not_published%' then raise; end if;
  end;

  -- inconsistent issue/expiry date.
  begin
    perform app.submit_vendor_compliance_document(v_vendor_id, v_req_id, v_file.id, current_date, current_date - 1, 'idem-pcmp-doc-badrange', v_staff, 'staff');
    raise exception 'assertion failed: expected inconsistent_issue_expiry_date';
  exception
    when others then
      if sqlerrm not like 'inconsistent_issue_expiry_date%' then raise; end if;
  end;

  -- finally, a genuinely clean, correctly-scoped submission succeeds.
  v_doc := app.submit_vendor_compliance_document(v_vendor_id, v_req_id, v_file.id, current_date - 300, current_date + 10, 'idem-pcmp-doc-1', v_staff, 'staff');
  if v_doc.verification_status <> 'pending' or v_doc.version_number <> 1 or not v_doc.is_latest_version then
    raise exception 'assertion failed: expected a fresh pending document, got status=% version=%', v_doc.verification_status, v_doc.version_number;
  end if;

  -- idempotency-key replay with the IDENTICAL expiry_date returns the same row...
  if (app.submit_vendor_compliance_document(v_vendor_id, v_req_id, v_file.id, current_date - 300, current_date + 10, 'idem-pcmp-doc-1', v_staff, 'staff')).id <> v_doc.id then
    raise exception 'assertion failed: expected an identical-args idempotency replay to return the exact same document row';
  end if;
  -- ...but fix-pass addition (HIGH-severity finding, adversarial review): a replay
  -- carrying a DIFFERENT expiry_date -- the single most consequential field in this
  -- entire capability -- must be rejected outright, not silently ignored.
  begin
    perform app.submit_vendor_compliance_document(v_vendor_id, v_req_id, v_file.id, current_date - 300, current_date + 999, 'idem-pcmp-doc-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused submission key with a different expiry_date';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
  -- a different issue_date is likewise rejected.
  begin
    perform app.submit_vendor_compliance_document(v_vendor_id, v_req_id, v_file.id, current_date - 1, current_date + 10, 'idem-pcmp-doc-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused submission key with a different issue_date';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- a second, independent submission against the SAME (vendor, requirement_version)
  -- slot while one is already active is rejected -- renewal is the only path.
  begin
    perform app.submit_vendor_compliance_document(v_vendor_id, v_req_id, v_file.id, current_date - 300, current_date + 10, 'idem-pcmp-doc-duplicate-slot', v_staff, 'staff');
    raise exception 'assertion failed: expected active_submission_exists for a second submission against an occupied slot';
  exception
    when others then
      if sqlerrm not like 'active_submission_exists%' then raise; end if;
  end;

  -- viewer cannot verify (requires PRC:Approve).
  begin
    perform app.decide_vendor_compliance_document(v_doc.id, v_doc.record_version, 'verified', null, '00000000-0000-0000-0000-000000091105', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for viewer verifying';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- a rejection/revision_requested decision requires a non-empty reason.
  begin
    perform app.decide_vendor_compliance_document(v_doc.id, v_doc.record_version, 'rejected', null, v_approver, 'approver');
    raise exception 'assertion failed: expected reason_required for a rejection with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_doc := app.decide_vendor_compliance_document(v_doc.id, v_doc.record_version, 'verified', null, v_approver, 'approver');
  if v_doc.verification_status <> 'verified' or v_doc.verified_by_auth_user_id <> v_approver then
    raise exception 'assertion failed: expected verified document, got %', v_doc.verification_status;
  end if;

  -- a decision on an already-decided document is rejected.
  begin
    perform app.decide_vendor_compliance_document(v_doc.id, v_doc.record_version, 'verified', null, v_approver, 'approver');
    raise exception 'assertion failed: expected invalid_transition deciding an already-decided document';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- eligibility projection: verified, expiry 10 days out (inside the requirement's
  -- own max reminder offset of 30) -- expiring_soon, never a hold (only expired/
  -- rejected/not_submitted trigger a blocking hold).
  perform app.recalculate_vendor_compliance_status(v_vendor_id, v_staff, 'staff');
  if not exists (
    select 1 from app.vendor_compliance_status s
    where s.vendor_master_record_id = v_vendor_id and s.status = 'expiring_soon' and not s.eligibility_hold
  ) then
    raise exception 'assertion failed: expected expiring_soon with no eligibility_hold for a document 10 days from expiry under a 30-day reminder offset';
  end if;
end $$;

\echo '>> renewal: creates a linked new version without deleting the prior evidence row or its underlying file; version lineage is readable end to end'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_prev app.vendor_compliance_documents;
  v_new_file app.files;
  v_renewed app.vendor_compliance_documents;
  v_version_count integer;
  v_prior_still_exists boolean;
begin
  select * into v_prev from app.vendor_compliance_documents where vendor_master_record_id = v_vendor_id and idempotency_key = 'idem-pcmp-doc-1';

  v_new_file := app.initiate_file_upload(
    v_tenant1, 'vendor_compliance_document', 'vendor_compliance', v_vendor_id,
    'business-license-renewed.pdf', 'application/pdf', 51200, 'internal', false, null, null, null,
    'idem-pcmp-evidence-renewal-1', v_staff, 'staff'
  );

  -- renewal with a still-pending-scan file is rejected identically to first submission.
  begin
    perform app.renew_vendor_compliance_document(v_prev.id, v_new_file.id, current_date, current_date + 365, v_staff, 'staff');
    raise exception 'assertion failed: expected compliance_unsafe_evidence renewing with a pending-scan file';
  exception
    when others then
      if sqlerrm not like 'compliance_unsafe_evidence%' then raise; end if;
  end;

  perform app.record_file_scan_result(v_new_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  v_renewed := app.renew_vendor_compliance_document(v_prev.id, v_new_file.id, current_date, current_date + 365, v_staff, 'staff');

  if v_renewed.version_group_id <> v_prev.version_group_id or v_renewed.version_number <> v_prev.version_number + 1 or not v_renewed.is_latest_version then
    raise exception 'assertion failed: expected renewal to share version_group_id and increment version_number, got group_match=% version=%', (v_renewed.version_group_id = v_prev.version_group_id), v_renewed.version_number;
  end if;

  select is_latest_version into v_prior_still_exists from app.vendor_compliance_documents where id = v_prev.id;
  if v_prior_still_exists is null or v_prior_still_exists then
    raise exception 'assertion failed: expected the prior document row to still exist with is_latest_version=false, never deleted';
  end if;
  if not exists (select 1 from app.files where id = v_prev.file_id) then
    raise exception 'assertion failed: expected the prior underlying app.files row to still exist -- renewal never deletes evidence';
  end if;

  -- a renewal must start from the latest version -- renewing the now-superseded row again is rejected.
  begin
    perform app.renew_vendor_compliance_document(v_prev.id, v_new_file.id, current_date, current_date + 365, v_staff, 'staff');
    raise exception 'assertion failed: expected vendor_compliance_document_not_latest renewing a superseded row';
  exception
    when others then
      if sqlerrm not like 'vendor_compliance_document_not_latest%' then raise; end if;
  end;

  select count(*) into v_version_count from app.list_vendor_compliance_document_versions(v_prev.version_group_id, v_staff);
  if v_version_count <> 2 then
    raise exception 'assertion failed: expected the version-lineage read to return exactly 2 rows, got %', v_version_count;
  end if;
end $$;

\echo '>> legal hold reuses app.set_file_legal_hold directly against the underlying app.files row -- no parallel legal-hold column exists on app.vendor_compliance_documents, and a held file blocks deletion exactly as PLT-128 already guarantees'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_doc app.vendor_compliance_documents;
  v_supreme uuid := '00000000-0000-0000-0000-000000091999';
begin
  select * into v_doc from app.vendor_compliance_documents where vendor_master_record_id = v_vendor_id and is_latest_version and idempotency_key is null order by created_at desc limit 1;

  perform app.set_file_legal_hold(v_doc.file_id, true, 'litigation hold pending contract dispute', v_supreme, 'supreme');
  begin
    perform app.request_file_deletion(v_doc.file_id, 'attempted deletion while under legal hold', v_supreme, 'supreme');
    raise exception 'assertion failed: expected document_legal_hold_blocks_deletion for a file under legal hold';
  exception
    when others then
      if sqlerrm not like 'document_legal_hold_blocks_deletion%' then raise; end if;
  end;
  perform app.set_file_legal_hold(v_doc.file_id, false, null, v_supreme, 'supreme');

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'vendor_compliance_documents' and column_name ilike '%legal_hold%'
  ) then
    -- expected: no such column exists on this migration's own table.
    null;
  else
    raise exception 'assertion failed: expected NO legal_hold column on app.vendor_compliance_documents (must reuse app.files'' own column, not fork it)';
  end if;
end $$;

\echo '>> evidence access (fix-pass addition, HIGH-severity finding, adversarial review): app.access_vendor_compliance_document_evidence composes PRC:Download authority with PLT-128''s own app.authorize_file_access (malware-scan + record/sensitivity gate) -- granted for clean evidence with file metadata, denied (not raised) with every file-identifying field nulled out once the underlying file is later flagged infected, insufficient_authority for an actor lacking PRC:Download or cross-tenant, invalid_access_type rejected, storage_path never returned, and PLT-128''s own app.file_access_logs independently records both attempts'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_viewer uuid := '00000000-0000-0000-0000-000000091105';
  v_t2_staff uuid := '00000000-0000-0000-0000-000000091202';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_doc app.vendor_compliance_documents;
  v_result record;
begin
  select * into v_doc from app.vendor_compliance_documents where vendor_master_record_id = v_vendor_id and is_latest_version and idempotency_key is null order by created_at desc limit 1;

  -- granted: staff holds PRC:Download, the file is clean.
  select * into v_result from app.access_vendor_compliance_document_evidence(v_doc.id, 'metadata_view', v_staff, 'staff', null);
  if v_result.access_result <> 'granted' or v_result.original_filename is null then
    raise exception 'assertion failed: expected a granted evidence access with file metadata, got result=% filename=%', v_result.access_result, v_result.original_filename;
  end if;

  -- insufficient_authority: viewer holds View only, not Download.
  begin
    perform app.access_vendor_compliance_document_evidence(v_doc.id, 'metadata_view', v_viewer, 'viewer', null);
    raise exception 'assertion failed: expected insufficient_authority for a viewer lacking PRC:Download';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- insufficient_authority: cross-tenant actor.
  begin
    -- ISS-2026-146: the probing actor is v_t2_staff 091202 (pcmp2's staff, zero membership in pcmp1).
    -- app.access_vendor_compliance_document_evidence now folds a caller with zero
    -- membership in the probed record's own tenant into the SAME generic vendor_compliance_document_not_found
    -- a nonexistent id already produced, instead of an insufficient_authority message
    -- carrying that tenant's real tenant_id. The refusal itself is unchanged.
    perform app.access_vendor_compliance_document_evidence(v_doc.id, 'metadata_view', v_t2_staff, 'staff2', null);
    raise exception 'assertion failed: expected vendor_compliance_document_not_found (ISS-2026-146) for a pcmp2 actor accessing a pcmp1 document''s evidence';
  exception
    when others then
      if sqlerrm not like 'vendor_compliance_document_not_found%' then raise; end if;
  end;

  -- invalid_access_type.
  begin
    perform app.access_vendor_compliance_document_evidence(v_doc.id, 'bogus_type', v_staff, 'staff', null);
    raise exception 'assertion failed: expected invalid_access_type for a bogus access type';
  exception
    when others then
      if sqlerrm not like 'invalid_access_type%' then raise; end if;
  end;

  -- denied, not raised, once the underlying file is later flagged infected -- every
  -- file-identifying field is nulled out, never leaked to a denied requester.
  -- ISS-2026-231: this raw re-flag IS the disclosed RPD-022 out-of-band correction path,
  -- and since 20260831130000 that path has to say so. The declaration is not ceremony: it
  -- is what distinguishes this deliberate simulation from an accidental or hostile write,
  -- which were previously byte-identical. It also lands a row in app.file_scan_corrections.
  perform set_config('app.scan_correction_reason', 'db-test: simulating the disclosed RPD-022 out-of-band re-flag of an already-clean file', true);
  update app.files set malware_scan_status = 'infected' where id = v_doc.file_id;
  select * into v_result from app.access_vendor_compliance_document_evidence(v_doc.id, 'download', v_staff, 'staff', null);
  if v_result.access_result <> 'denied' or v_result.original_filename is not null or v_result.access_reason is null then
    raise exception 'assertion failed: expected a denied result with nulled-out metadata for infected evidence, got result=% filename=% reason=%', v_result.access_result, v_result.original_filename, v_result.access_reason;
  end if;
  -- HDN-377 (Storage and Signed URL Audit) regression: this exact content-gate
  -- denial branch (PRC:Download authority passes, app.authorize_file_access itself
  -- denies) previously left file_id unmasked, contradicting this RPC's own "every
  -- file-identifying field nulled out" contract -- the assertion above never
  -- actually checked file_id, only original_filename, so it silently passed both
  -- before and would have kept passing after the leak. Checked explicitly now.
  if v_result.file_id is not null then
    raise exception 'assertion failed: expected file_id to also be nulled out on a denied (infected) evidence access, got file_id=%', v_result.file_id;
  end if;
  update app.files set malware_scan_status = 'clean' where id = v_doc.file_id;

  -- PLT-128's own independent audit trail recorded both the granted metadata_view and
  -- the denied download attempt above.
  if (select count(*) from app.file_access_logs where file_id = v_doc.file_id and accessed_by_auth_user_id = v_staff) < 2 then
    raise exception 'assertion failed: expected at least 2 app.file_access_logs rows for the staff actor''s own granted+denied evidence access attempts';
  end if;

  -- no raw storage_path is ever exposed through this RPC's own return shape.
  if exists (
    select 1 from information_schema.parameters
    where specific_schema = 'app' and specific_name like 'access_vendor_compliance_document_evidence%' and parameter_name = 'storage_path'
  ) then
    raise exception 'assertion failed: expected no storage_path column in app.access_vendor_compliance_document_evidence''s own return shape';
  end if;
end $$;

\echo '>> ISS-2026-224 regression: a second reviewer who holds PRC:Download but did not upload the evidence and shares no org unit/customer account with the uploader is GRANTED evidence access (not denied via document_record_access_denied, the identical shape a genuinely unauthorized caller gets) -- the "second reviewer verifies evidence" workflow app.access_vendor_compliance_document_evidence''s own header comment claims to support'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000091101';
  v_reviewer uuid := '00000000-0000-0000-0000-000000091107';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_doc app.vendor_compliance_documents;
  v_reviewer_role uuid;
  v_reviewer_draft app.role_versions;
  v_result record;
begin
  select * into v_doc from app.vendor_compliance_documents where vendor_master_record_id = v_vendor_id and is_latest_version and idempotency_key is null order by created_at desc limit 1;

  perform app.invite_user(v_tenant1, v_reviewer, 'reviewer@pcmp1.test', 'Pcmp1 Reviewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'reviewer@pcmp1.test'), 'active', 'onboarded', 'tester');

  -- Download-only role, deliberately never given Create/Edit/View so this is a clean
  -- probe of the record-scope gate alone, not any other PRC:* authority.
  v_reviewer_role := (app.create_role(v_tenant1, 'PRC Compliance Second Reviewer', 'Download only -- ISS-2026-224 regression', 'tester')).id;
  v_reviewer_draft := app.create_role_version(v_reviewer_role, 'tester');
  perform app.set_role_version_permissions(v_reviewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'Download'), 'tester');
  perform app.publish_role_version(v_reviewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_reviewer_role and status = 'published'), v_reviewer, v_admin1, 'tester');

  -- v_reviewer is NOT the uploader (staff, 091102), shares no org unit and no
  -- customer-account membership with the uploader -- before this fix,
  -- app.can_access_record's ownership/share/customer-scope model had no vocabulary
  -- for "holds the tenant's own PRC:Download review permission", so this got
  -- document_record_access_denied identically to an actually-unauthorized caller.
  select * into v_result from app.access_vendor_compliance_document_evidence(v_doc.id, 'metadata_view', v_reviewer, 'reviewer', null);
  if v_result.access_result <> 'granted' or v_result.original_filename is null then
    raise exception 'assertion failed: ISS-2026-224 -- expected a non-uploading actor holding PRC:Download to be granted evidence access, got result=% reason=%', v_result.access_result, v_result.access_reason;
  end if;
end $$;

\echo '>> HDN-377 (Storage and Signed URL Audit) regression: app.vendor_compliance_documents_select_scoped RLS now requires real PRC:View authority, not just active tenant membership -- an active tenant_admin with zero PRC role assignment previously read every row (verification_status/rejection_reason/expiry_date/file_id) directly via RLS, live-forced independent of the RPC path''s own already-correct PRC:Download gate'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000091101", "role": "authenticated"}';
  select count(*) into v_count from app.vendor_compliance_documents;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows visible via RLS to a tenant_admin holding zero PRC role assignment, got %', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000091102", "role": "authenticated"}';
  select count(*) into v_count from app.vendor_compliance_documents;
  if v_count = 0 then
    raise exception 'assertion failed: expected staff (holding PRC:View via PRC:Create/Edit/View/Download) to still see rows via RLS';
  end if;
  reset role;
end $$;

\echo '>> expiry computation: a past-expiry document drives status=expired with eligibility_hold=true for a BLOCKING requirement, but never for a WARNING requirement'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_approver uuid := '00000000-0000-0000-0000-000000091103';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_warning_req app.vendor_compliance_requirements;
  v_blocking_req app.vendor_compliance_requirements;
  v_file1 app.files;
  v_file2 app.files;
  v_doc1 app.vendor_compliance_documents;
  v_doc2 app.vendor_compliance_documents;
begin
  -- distinct service_type per family (trucking/linehaul) -- the vendor holds an
  -- active app.vendor_services row for both, and this keeps each family's own scope
  -- tuple (tenant, vendor_category, service_type, document_type_code) distinct from
  -- the OTHER already-published trucking-scoped families in this test suite, since
  -- vendor_compliance_requirements_published_scope_unique allows at most one
  -- published requirement per exact scope tuple at a time.
  v_warning_req := app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', 'trucking', 'vendor_compliance_document', 'Optional Trucking Cert', null, 'warning', true, array[30], now(), 'idem-pcmp-req-warning-expiry', v_staff, 'staff');
  v_warning_req := app.publish_vendor_compliance_requirement(v_warning_req.id, v_warning_req.record_version, null, v_approver, 'approver');

  v_blocking_req := app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', 'linehaul', 'vendor_compliance_document', 'Mandatory Trucking Permit', null, 'blocking', true, array[30], now(), 'idem-pcmp-req-blocking-expiry', v_staff, 'staff');
  v_blocking_req := app.publish_vendor_compliance_requirement(v_blocking_req.id, v_blocking_req.record_version, null, v_approver, 'approver');

  v_file1 := app.initiate_file_upload(v_tenant1, 'vendor_compliance_document', 'vendor_compliance', v_vendor_id, 'warning-doc.pdf', 'application/pdf', 1024, 'internal', false, null, null, null, 'idem-pcmp-evidence-warning-expiry', v_staff, 'staff');
  perform app.record_file_scan_result(v_file1.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  v_doc1 := app.submit_vendor_compliance_document(v_vendor_id, v_warning_req.id, v_file1.id, current_date - 400, current_date - 30, 'idem-pcmp-doc-warning-expiry', v_staff, 'staff');
  v_doc1 := app.decide_vendor_compliance_document(v_doc1.id, v_doc1.record_version, 'verified', null, v_approver, 'approver');

  v_file2 := app.initiate_file_upload(v_tenant1, 'vendor_compliance_document', 'vendor_compliance', v_vendor_id, 'blocking-doc.pdf', 'application/pdf', 1024, 'internal', false, null, null, null, 'idem-pcmp-evidence-blocking-expiry', v_staff, 'staff');
  perform app.record_file_scan_result(v_file2.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  v_doc2 := app.submit_vendor_compliance_document(v_vendor_id, v_blocking_req.id, v_file2.id, current_date - 400, current_date - 30, 'idem-pcmp-doc-blocking-expiry', v_staff, 'staff');
  v_doc2 := app.decide_vendor_compliance_document(v_doc2.id, v_doc2.record_version, 'verified', null, v_approver, 'approver');

  perform app.recalculate_vendor_compliance_status(v_vendor_id, v_staff, 'staff');

  if not exists (
    select 1 from app.vendor_compliance_status s where s.vendor_master_record_id = v_vendor_id and s.requirement_family_id = v_warning_req.requirement_family_id and s.status = 'expired' and not s.eligibility_hold
  ) then
    raise exception 'assertion failed: expected the WARNING requirement to read status=expired with eligibility_hold=false';
  end if;
  if not exists (
    select 1 from app.vendor_compliance_status s where s.vendor_master_record_id = v_vendor_id and s.requirement_family_id = v_blocking_req.requirement_family_id and s.status = 'expired' and s.eligibility_hold
  ) then
    raise exception 'assertion failed: expected the BLOCKING requirement to read status=expired with eligibility_hold=true';
  end if;

  -- the downstream-composable eligibility read reflects the same projection.
  if not exists (select 1 from app.get_vendor_compliance_eligibility(v_vendor_id, v_staff) e where e.requirement_family_id = v_blocking_req.requirement_family_id and e.eligibility_hold) then
    raise exception 'assertion failed: expected app.get_vendor_compliance_eligibility to surface the blocking hold';
  end if;
end $$;

\echo '>> waiver: request -> self-approval blocked -> a different actor approves -> status becomes waived, eligibility_hold clears even though the underlying document is expired -> revoke reinstates the hold; reject requires a reason; idempotency-key replay and mismatch'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_approver uuid := '00000000-0000-0000-0000-000000091103';
  v_manager uuid := '00000000-0000-0000-0000-000000091104';
  v_viewer uuid := '00000000-0000-0000-0000-000000091105';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_blocking_req_id uuid := (select id from app.vendor_compliance_requirements where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-req-blocking-expiry');
  v_waiver app.vendor_compliance_waivers;
  v_replay app.vendor_compliance_waivers;
begin
  v_waiver := app.request_vendor_compliance_waiver(v_blocking_req_id, v_vendor_id, 'temporary operational exception pending renewal', current_date, current_date + 14, 'idem-pcmp-waiver-1', v_staff, 'staff');
  if v_waiver.status <> 'pending' then
    raise exception 'assertion failed: expected a pending waiver, got %', v_waiver.status;
  end if;

  -- idempotency replay + target mismatch.
  v_replay := app.request_vendor_compliance_waiver(v_blocking_req_id, v_vendor_id, 'temporary operational exception pending renewal', current_date, current_date + 14, 'idem-pcmp-waiver-1', v_staff, 'staff');
  if v_replay.id <> v_waiver.id then
    raise exception 'assertion failed: expected idempotency replay to return the exact same waiver row';
  end if;
  begin
    perform app.request_vendor_compliance_waiver(v_blocking_req_id, v_vendor_id, 'temporary operational exception pending renewal', current_date, current_date + 30, 'idem-pcmp-waiver-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for a reused waiver key with a different valid_until';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- self-approval is blocked outright, checked before the authority evaluation.
  begin
    perform app.decide_vendor_compliance_waiver(v_waiver.id, v_waiver.record_version, 'approved', null, v_staff, 'staff');
    raise exception 'assertion failed: expected self_approval_not_allowed for the requester deciding their own waiver';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  -- a viewer (no Approve) cannot decide either.
  begin
    perform app.decide_vendor_compliance_waiver(v_waiver.id, v_waiver.record_version, 'approved', null, v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer deciding a waiver';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Security-regression review fix (this same checkpoint, spot-checking the build
  -- log's own now-superseded "checked and found NOT affected" claim): a viewer who
  -- ALSO supplies a deliberately stale p_expected_version must still be denied on
  -- insufficient_authority grounds, NEVER stale_version -- the real record_version
  -- must not be disclosed to a caller not yet shown to hold PRC:Approve/PRC:Reject.
  begin
    perform app.decide_vendor_compliance_waiver(v_waiver.id, 999999, 'approved', null, v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority (never stale_version) for a viewer supplying a stale expected_version';
  exception
    when others then
      if sqlerrm like 'stale_version%' then
        raise exception 'assertion failed: record_version was disclosed to an unauthorized caller before the authority check -- %', sqlerrm;
      end if;
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Same regression, for the waiver's own requester (self-approval identity check):
  -- must still be self_approval_not_allowed, never stale_version, with a stale version.
  begin
    perform app.decide_vendor_compliance_waiver(v_waiver.id, 999999, 'approved', null, v_staff, 'staff');
    raise exception 'assertion failed: expected self_approval_not_allowed (never stale_version) for the requester supplying a stale expected_version';
  exception
    when others then
      if sqlerrm like 'stale_version%' then
        raise exception 'assertion failed: record_version was disclosed to the requester before the self-approval check -- %', sqlerrm;
      end if;
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  -- the fixture waiver's real record_version/status are untouched by any of the
  -- three rejected calls above (mirrors the vendor_profiles block's own sanity check).
  if (select record_version from app.vendor_compliance_waivers where id = v_waiver.id) <> v_waiver.record_version
     or (select status from app.vendor_compliance_waivers where id = v_waiver.id) <> 'pending' then
    raise exception 'assertion failed: expected the waiver to be untouched by the rejected decide_vendor_compliance_waiver calls above';
  end if;

  -- rejecting requires a reason.
  begin
    perform app.decide_vendor_compliance_waiver(v_waiver.id, v_waiver.record_version, 'rejected', null, v_manager, 'manager');
    raise exception 'assertion failed: expected reason_required rejecting a waiver with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- deciding a waiver requires PRC:Approve/Reject -- the manager role only holds
  -- Override/Create/Edit/View (a deliberately distinct authority from deciding),
  -- so the approver (Approve/Reject/View, and NOT the requester) decides here.
  v_waiver := app.decide_vendor_compliance_waiver(v_waiver.id, v_waiver.record_version, 'approved', 'accepted, renewal in progress', v_approver, 'approver');
  if v_waiver.status <> 'approved' or v_waiver.approved_by_auth_user_id <> v_approver then
    raise exception 'assertion failed: expected an approved waiver decided by the approver, got status=%', v_waiver.status;
  end if;

  -- deciding an already-decided waiver fails.
  begin
    perform app.decide_vendor_compliance_waiver(v_waiver.id, v_waiver.record_version, 'approved', null, v_approver, 'approver');
    raise exception 'assertion failed: expected invalid_transition deciding an already-decided waiver';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  if not exists (
    select 1 from app.vendor_compliance_status s
    join app.vendor_compliance_requirements r on r.id = v_blocking_req_id
    where s.vendor_master_record_id = v_vendor_id and s.requirement_family_id = r.requirement_family_id and s.status = 'waived' and not s.eligibility_hold
  ) then
    raise exception 'assertion failed: expected the family status to read waived/no-hold once the waiver was approved, even though the underlying document is still expired';
  end if;

  -- revoke (Override) reinstates the underlying expired/hold projection.
  v_waiver := app.revoke_vendor_compliance_waiver(v_waiver.id, v_waiver.record_version, 'renewal complete, waiver no longer needed', v_manager, 'manager');
  if not exists (
    select 1 from app.vendor_compliance_status s
    join app.vendor_compliance_requirements r on r.id = v_blocking_req_id
    where s.vendor_master_record_id = v_vendor_id and s.requirement_family_id = r.requirement_family_id and s.status = 'expired' and s.eligibility_hold
  ) then
    raise exception 'assertion failed: expected revoking the waiver to reinstate status=expired with eligibility_hold=true';
  end if;

  -- staff (no Override) cannot revoke -- record_version is fresh (post-revoke) here,
  -- so the version check passes and the authority check is the one that fires,
  -- even though the waiver is already terminal (status is checked AFTER authority).
  begin
    perform app.revoke_vendor_compliance_waiver(v_waiver.id, v_waiver.record_version, 'attempted revoke without Override', v_staff, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for staff revoking a waiver (requires PRC:Override)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> bounded waiver-expiry sweep: a past-valid_until approved waiver is cosmetically flipped to expired by the bounded sweep; eligibility-hold correctness never depended on the sweep having run'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_approver uuid := '00000000-0000-0000-0000-000000091103';
  v_manager uuid := '00000000-0000-0000-0000-000000091104';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_blocking_req_id uuid := (select id from app.vendor_compliance_requirements where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-req-blocking-expiry');
  v_waiver app.vendor_compliance_waivers;
  v_expired_count integer;
  v_more_remaining boolean;
begin
  v_waiver := app.request_vendor_compliance_waiver(v_blocking_req_id, v_vendor_id, 'already-lapsed window for sweep test', current_date - 30, current_date - 5, 'idem-pcmp-waiver-lapsed', v_staff, 'staff');
  v_waiver := app.decide_vendor_compliance_waiver(v_waiver.id, v_waiver.record_version, 'approved', 'approved retroactively for test setup', v_approver, 'approver');
  if v_waiver.status <> 'approved' then
    raise exception 'assertion failed: expected the lapsed-window waiver to still approve (no >= now() constraint on valid_until)';
  end if;

  select expired_count, more_remaining into v_expired_count, v_more_remaining from app.expire_vendor_compliance_waivers(v_tenant1, v_manager, 'manager', 500);
  if v_expired_count < 1 then
    raise exception 'assertion failed: expected at least 1 waiver flipped to expired by the sweep, got %', v_expired_count;
  end if;

  select status into v_waiver.status from app.vendor_compliance_waivers where id = v_waiver.id;
  if v_waiver.status <> 'expired' then
    raise exception 'assertion failed: expected the lapsed waiver''s own status column to read expired after the sweep, got %', v_waiver.status;
  end if;

  -- staff (no Override) cannot run the sweep.
  begin
    perform app.expire_vendor_compliance_waivers(v_tenant1, v_staff, 'staff', 500);
    raise exception 'assertion failed: expected insufficient_authority for staff running the waiver-expiry sweep';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> requirement-version snapshot immutability: republishing the family does not retroactively change an already-submitted document''s own requirement_version_id, but the family''s live status re-evaluates against whichever version is currently published'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_approver uuid := '00000000-0000-0000-0000-000000091103';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_old_req_id uuid := (select id from app.vendor_compliance_requirements where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-req-warning-expiry');
  v_family_id uuid;
  v_new_req app.vendor_compliance_requirements;
  v_doc_snapshot_id uuid;
begin
  select requirement_family_id into v_family_id from app.vendor_compliance_requirements where id = v_old_req_id;
  select requirement_version_id into v_doc_snapshot_id from app.vendor_compliance_documents where vendor_master_record_id = v_vendor_id and idempotency_key = 'idem-pcmp-doc-warning-expiry';
  if v_doc_snapshot_id <> v_old_req_id then
    raise exception 'assertion failed: sanity check failed -- the document should be linked to the original requirement version';
  end if;

  v_new_req := app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', 'trucking', 'vendor_compliance_document', 'Optional Trucking Cert (corrected reminder schedule)', null, 'warning', true, array[45,20,5], now(), 'idem-pcmp-req-warning-expiry-v2', v_staff, 'staff');
  v_new_req := app.publish_vendor_compliance_requirement(v_new_req.id, v_new_req.record_version, v_old_req_id, v_approver, 'approver');
  if v_new_req.requirement_family_id <> v_family_id then
    raise exception 'assertion failed: expected the republished version to carry the same requirement_family_id forward';
  end if;

  -- the document's own snapshot link is untouched by the republish.
  select requirement_version_id into v_doc_snapshot_id from app.vendor_compliance_documents where vendor_master_record_id = v_vendor_id and idempotency_key = 'idem-pcmp-doc-warning-expiry';
  if v_doc_snapshot_id <> v_old_req_id then
    raise exception 'assertion failed: expected the document''s own requirement_version_id to remain pinned to the original (now-archived) version after republish';
  end if;

  -- but the family's live status row now resolves against the NEW published version.
  perform app.recalculate_vendor_compliance_status(v_vendor_id, v_staff, 'staff');
  if not exists (
    select 1 from app.vendor_compliance_status s where s.vendor_master_record_id = v_vendor_id and s.requirement_family_id = v_family_id and s.current_requirement_version_id = v_new_req.id
  ) then
    raise exception 'assertion failed: expected the family''s live status row to now point at the newly published requirement version, re-evaluating the same unmodified document';
  end if;
end $$;

\echo '>> bounded tenant-wide recalculation sweep (PRC:Override) and per-vendor recalculation (PRC:Edit) authority gates'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_viewer uuid := '00000000-0000-0000-0000-000000091105';
  v_manager uuid := '00000000-0000-0000-0000-000000091104';
  v_recalculated integer;
  v_more_remaining boolean;
begin
  begin
    perform app.recalculate_vendor_compliance_status((select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1'), v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer recalculating one vendor (requires PRC:Edit)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.recalculate_tenant_vendor_compliance_status(v_tenant1, v_staff, 'staff', 200);
    raise exception 'assertion failed: expected insufficient_authority for staff running the tenant-wide sweep (requires PRC:Override)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select vendors_recalculated, more_remaining into v_recalculated, v_more_remaining from app.recalculate_tenant_vendor_compliance_status(v_tenant1, v_manager, 'manager', 200);
  if v_recalculated < 2 then
    raise exception 'assertion failed: expected at least 2 vendors recalculated in the tenant-wide sweep, got %', v_recalculated;
  end if;
  if v_more_remaining then
    raise exception 'assertion failed: expected more_remaining=false for a tiny tenant well under the 200-vendor budget';
  end if;
end $$;

\echo '>> reminder escalation tiers (fix-pass addition, MEDIUM-severity finding, adversarial review): a multi-offset reminder schedule ({30,14,7}) surfaces WHICH tier a document has already crossed, not just an undifferentiated expiring_soon bucket'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_approver uuid := '00000000-0000-0000-0000-000000091103';
  v_vendor_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-pcmp-vendor-1');
  v_req app.vendor_compliance_requirements;
  v_file app.files;
  v_doc app.vendor_compliance_documents;
  v_tier integer;
  v_days integer;
begin
  -- distinct service_type ('reminder-tier-test') keeps this scope tuple independent
  -- of every other trucking-scoped published requirement in this suite.
  v_req := app.create_vendor_compliance_requirement_draft(v_tenant1, 'trucking', 'reminder-tier-test', 'vendor_compliance_document', 'Reminder Tier Test Cert', null, 'warning', true, array[30,14,7], now(), 'idem-pcmp-req-remindertier', v_staff, 'staff');
  v_req := app.publish_vendor_compliance_requirement(v_req.id, v_req.record_version, null, v_approver, 'approver');
  perform app.add_vendor_service(v_vendor_id, 'reminder-tier-test', v_staff, 'staff');

  v_file := app.initiate_file_upload(v_tenant1, 'vendor_compliance_document', 'vendor_compliance', v_vendor_id, 'remindertier-doc.pdf', 'application/pdf', 1024, 'internal', false, null, null, null, 'idem-pcmp-evidence-remindertier', v_staff, 'staff');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', v_staff, 'staff');
  -- 10 days from expiry: crosses the 30-day and 14-day tiers, not yet the 7-day tier
  -- -- the SMALLEST already-crossed offset (14) is the current escalation level, not
  -- the largest (30).
  v_doc := app.submit_vendor_compliance_document(v_vendor_id, v_req.id, v_file.id, current_date - 355, current_date + 10, 'idem-pcmp-doc-remindertier', v_staff, 'staff');
  v_doc := app.decide_vendor_compliance_document(v_doc.id, v_doc.record_version, 'verified', null, v_approver, 'approver');
  perform app.recalculate_vendor_compliance_status(v_vendor_id, v_staff, 'staff');

  select e.reminder_tier_days, e.days_until_expiry into v_tier, v_days from app.get_vendor_compliance_eligibility(v_vendor_id, v_staff) e where e.requirement_family_id = v_req.requirement_family_id;
  if v_tier <> 14 or v_days <> 10 then
    raise exception 'assertion failed: expected reminder_tier_days=14 (the smallest already-crossed offset, not the largest) and days_until_expiry=10 at 10 days from a {30,14,7} schedule, got tier=% days=%', v_tier, v_days;
  end if;

  -- the shared tenant matrix read surfaces the identical computed columns.
  select m.reminder_tier_days into v_tier from app.list_tenant_vendor_compliance_matrix(v_tenant1, v_staff, null, false, v_vendor_id, 100, null) m where m.requirement_family_id = v_req.requirement_family_id;
  if v_tier <> 14 then
    raise exception 'assertion failed: expected app.list_tenant_vendor_compliance_matrix to surface the identical reminder_tier_days=14, got %', v_tier;
  end if;
end $$;

\echo '>> reads: the compliance matrix / expiring-soon-and-holds queue is server-filtered and correctly scoped'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pcmp1');
  v_staff uuid := '00000000-0000-0000-0000-000000091102';
  v_hold_count integer;
begin
  select count(*) into v_hold_count from app.list_tenant_vendor_compliance_matrix(v_tenant1, v_staff, null, true, null, 100, null);
  if v_hold_count < 1 then
    raise exception 'assertion failed: expected at least one eligibility-hold row in the tenant compliance matrix (hold_only=true)';
  end if;
  if exists (select 1 from app.list_tenant_vendor_compliance_matrix(v_tenant1, v_staff, null, true, null, 100, null) m where not m.eligibility_hold) then
    raise exception 'assertion failed: hold_only=true must never return a non-hold row';
  end if;
end $$;

\echo '>> cross-tenant isolation: a pcmp2 actor cannot read or act on any pcmp1 requirement/document/waiver row through the RPC layer'
do $$
declare
  v_t2_staff uuid := '00000000-0000-0000-0000-000000091202';
  v_target_req_id uuid := (select r.id from app.vendor_compliance_requirements r join app.tenants t on t.id = r.tenant_id where t.slug = 'pcmp1' and r.idempotency_key = 'idem-pcmp-req-1');
  v_target_vendor_id uuid := (select master_record_id from app.vendor_profiles where idempotency_key = 'idem-pcmp-vendor-1');
begin
  -- Prompt 269 (ISS-2026-054, C-05): a cross-tenant, zero-membership caller now gets
  -- the SAME vendor_compliance_requirement_not_found a genuinely missing id would
  -- produce, never insufficient_authority (which would have echoed the real tenant_id
  -- in its own error text -- the exact oracle this fix closed).
  begin
    perform app.get_vendor_compliance_requirement(v_target_req_id, v_t2_staff);
    raise exception 'assertion failed: expected vendor_compliance_requirement_not_found for a pcmp2 actor reading a pcmp1 requirement (never insufficient_authority, which would disclose the real tenant_id)';
  exception
    when others then
      if sqlerrm not like 'vendor_compliance_requirement_not_found%' then raise; end if;
  end;

  -- ISS-2026-146: v_t2_staff (pcmp2's staff, '00000000-0000-0000-0000-000000091202') holds
  -- ZERO app.principal_memberships / tenant_user_identities row in pcmp1 -- it was only ever
  -- invited to pcmp2. app.request_vendor_compliance_waiver resolves the vendor by its bare
  -- master_record_id (no p_tenant_id parameter to scope by), so before the fix its
  -- insufficient_authority denial interpolated pcmp1's REAL tenant_id into the message text
  -- for an actor with no relationship to that tenant. The fix folds
  -- app.has_active_tenant_membership into the SAME not-found branch the row-miss case already
  -- raises, so this caller now gets exactly the generic vendor_profile_not_found a nonexistent
  -- vendor id would produce -- the same expectation the sibling block immediately above
  -- already asserts for app.get_vendor_compliance_requirement (ISS-2026-054). The write is
  -- still fully blocked; only the disclosure shape changed.
  begin
    perform app.request_vendor_compliance_waiver(v_target_req_id, v_target_vendor_id, 'cross-tenant attempt', current_date, current_date + 1, 'idem-pcmp-cross-attack', v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected the pcmp1 vendor lookup to reject a pcmp2 actor with a generic vendor_profile_not_found (never insufficient_authority, which would disclose the real tenant_id)';
  exception
    when others then
      if sqlerrm not like 'vendor_profile_not_found%' then raise; end if;
  end;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000091202", "role": "authenticated"}', true);

  if exists (select 1 from app.vendor_compliance_requirements where id = v_target_req_id) then
    raise exception 'assertion failed: raw RLS leak -- pcmp2 staff directly selected a pcmp1 compliance requirement row';
  end if;
  if exists (select 1 from app.vendor_compliance_status where vendor_master_record_id = v_target_vendor_id) then
    raise exception 'assertion failed: raw RLS leak -- pcmp2 staff directly selected a pcmp1 compliance status row';
  end if;

  reset role;
end $$;

\echo '>> Prompt 269 (ISS-2026-054, C-05): app.get_vendor_compliance_waiver/get_vendor_compliance_document/decide_vendor_compliance_waiver -- a pcmp2 actor with zero membership in pcmp1 gets the SAME not-found shape a genuinely missing id would produce, never insufficient_authority (which would disclose the real tenant_id); the write correctly still blocks the actual decision, only the disclosure is fixed'
do $$
declare
  v_t2_staff uuid := '00000000-0000-0000-0000-000000091202';
  v_target_waiver_id uuid := (select w.id from app.vendor_compliance_waivers w join app.tenants t on t.id = w.tenant_id where t.slug = 'pcmp1' and w.idempotency_key = 'idem-pcmp-waiver-1');
  v_target_doc_id uuid := (select d.id from app.vendor_compliance_documents d join app.tenants t on t.id = d.tenant_id where t.slug = 'pcmp1' and d.idempotency_key = 'idem-pcmp-doc-1');
begin
  begin
    perform app.get_vendor_compliance_waiver(v_target_waiver_id, v_t2_staff);
    raise exception 'assertion failed: expected vendor_compliance_waiver_not_found for a pcmp2 actor reading a pcmp1 waiver (never insufficient_authority, which would disclose the real tenant_id)';
  exception
    when others then
      if sqlerrm not like 'vendor_compliance_waiver_not_found%' then raise; end if;
  end;

  begin
    perform app.get_vendor_compliance_document(v_target_doc_id, v_t2_staff);
    raise exception 'assertion failed: expected vendor_compliance_document_not_found for a pcmp2 actor reading a pcmp1 document (never insufficient_authority, which would disclose the real tenant_id)';
  exception
    when others then
      if sqlerrm not like 'vendor_compliance_document_not_found%' then raise; end if;
  end;

  begin
    perform app.decide_vendor_compliance_waiver(v_target_waiver_id, 1, 'approved', null, v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected vendor_compliance_waiver_not_found for a pcmp2 actor deciding a pcmp1 waiver (never insufficient_authority, which would disclose the real tenant_id) -- the write must still be blocked, only the disclosure shape changes';
  exception
    when others then
      if sqlerrm not like 'vendor_compliance_waiver_not_found%' then raise; end if;
  end;

  -- This waiver was already legitimately approved by v_approver earlier in this file
  -- (the maker-checker test above) -- confirm the cross-tenant attempt never touched
  -- it (approved_by_auth_user_id is still the real approver, never the attacker).
  if (select approved_by_auth_user_id from app.vendor_compliance_waivers where id = v_target_waiver_id) = v_t2_staff then
    raise exception 'assertion failed: the cross-tenant decide_vendor_compliance_waiver attempt must never actually have decided the real pcmp1 waiver';
  end if;
end $$;

\echo '>> RLS default-deny for a customer_user-layer principal: tenant membership alone is not enough -- a customer_user-layer actor in the SAME tenant reads zero rows at the raw-RLS level'
do $$
declare
  v_target_req_id uuid := (select r.id from app.vendor_compliance_requirements r join app.tenants t on t.id = r.tenant_id where t.slug = 'pcmp1' and r.idempotency_key = 'idem-pcmp-req-1');
  v_target_vendor_id uuid := (select master_record_id from app.vendor_profiles where idempotency_key = 'idem-pcmp-vendor-1');
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000091106", "role": "authenticated"}', true);

  if exists (select 1 from app.vendor_compliance_requirements where id = v_target_req_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.vendor_compliance_requirements directly, even inside its own tenant';
  end if;
  if exists (select 1 from app.vendor_compliance_documents where vendor_master_record_id = v_target_vendor_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.vendor_compliance_documents directly';
  end if;
  if exists (select 1 from app.vendor_compliance_waivers where vendor_master_record_id = v_target_vendor_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.vendor_compliance_waivers directly';
  end if;
  if exists (select 1 from app.vendor_compliance_status where vendor_master_record_id = v_target_vendor_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.vendor_compliance_status directly';
  end if;

  reset role;
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new PRC-253 function; the private per-family/per-vendor recalculation helpers carry no authenticated/service_role/anon grant at all'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in (
      'create_vendor_compliance_requirement_draft', 'update_vendor_compliance_requirement_draft', 'publish_vendor_compliance_requirement',
      'archive_vendor_compliance_requirement', 'submit_vendor_compliance_document', 'renew_vendor_compliance_document',
      'decide_vendor_compliance_document', 'access_vendor_compliance_document_evidence', 'request_vendor_compliance_waiver', 'decide_vendor_compliance_waiver',
      'revoke_vendor_compliance_waiver', 'expire_vendor_compliance_waivers', 'recalculate_vendor_compliance_status',
      'recalculate_tenant_vendor_compliance_status', 'get_vendor_compliance_requirement', 'list_vendor_compliance_requirements',
      'get_vendor_compliance_document', 'list_vendor_compliance_documents', 'list_vendor_compliance_document_versions',
      'get_vendor_compliance_waiver', 'list_vendor_compliance_waivers', 'get_vendor_compliance_eligibility', 'list_tenant_vendor_compliance_matrix'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on PRC-253 functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in ('_vendor_compliance_requirement_applies', 'assert_vendor_compliance_requirement_editable', '_recalculate_vendor_compliance_status_family', '_recalculate_vendor_compliance_status_all_families')
    and grantee in ('authenticated', 'service_role', 'anon');
  if v_count <> 0 then
    raise exception 'assertion failed: expected the PRC-253 private helpers to carry no authenticated/service_role/anon grant, found %', v_count;
  end if;
end $$;

\echo 'ALL PRC-253 db-test assertions passed.'
