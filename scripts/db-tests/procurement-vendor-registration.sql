-- Real, executable test evidence for PRC-251 (Vendor Registration and Onboarding,
-- CG-S11-PRC-002) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (vndreg1, vndreg2). vndreg1 gets a tenant_admin, a Procurement staff actor (PRC Create/Edit/View), a reviewer (PRC Approve/Reject/View), an override manager (PRC Override/Edit/View), a view-only actor, and a customer_user-layer actor. vndreg2 gets a tenant_admin and a staff actor for cross-tenant checks. A global Supreme Admin is also seeded.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_reviewer_role uuid;
  v_reviewer_draft app.role_versions;
  v_manager_role uuid;
  v_manager_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000025101', 'admin@vndreg1.test'),
    ('00000000-0000-0000-0000-000000025102', 'staff@vndreg1.test'),
    ('00000000-0000-0000-0000-000000025103', 'reviewer@vndreg1.test'),
    ('00000000-0000-0000-0000-000000025104', 'manager@vndreg1.test'),
    ('00000000-0000-0000-0000-000000025105', 'viewer@vndreg1.test'),
    ('00000000-0000-0000-0000-000000025106', 'customer@vndreg1.test'),
    ('00000000-0000-0000-0000-000000025201', 'admin@vndreg2.test'),
    ('00000000-0000-0000-0000-000000025202', 'staff@vndreg2.test'),
    ('00000000-0000-0000-0000-000000025999', 'supreme@vndreg.test');

  perform app.provision_tenant('vndreg1', 'Vendor Reg Co 1', 'idem-vndreg1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'vndreg1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('vndreg2', 'Vendor Reg Co 2', 'idem-vndreg2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'vndreg2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000025101', 'admin@vndreg1.test', 'Vndreg1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vndreg1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000025101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000025102', 'staff@vndreg1.test', 'Vndreg1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vndreg1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000025103', 'reviewer@vndreg1.test', 'Vndreg1 Reviewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'reviewer@vndreg1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000025104', 'manager@vndreg1.test', 'Vndreg1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@vndreg1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000025105', 'viewer@vndreg1.test', 'Vndreg1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@vndreg1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000025106', 'customer@vndreg1.test', 'Vndreg1 Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@vndreg1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000025106', 'customer_user', v_tenant1, 'external-customer-account', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000025201', 'admin@vndreg2.test', 'Vndreg2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vndreg2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000025201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000025202', 'staff@vndreg2.test', 'Vndreg2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vndreg2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000025999', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'PRC Staff', 'Create/Edit/View drafts', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000025102', '00000000-0000-0000-0000-000000025101', 'tester');

  v_reviewer_role := (app.create_role(v_tenant1, 'PRC Reviewer', 'Approve/Reject/View', 'tester')).id;
  v_reviewer_draft := app.create_role_version(v_reviewer_role, 'tester');
  perform app.set_role_version_permissions(v_reviewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Approve', 'Reject', 'View')), 'tester');
  perform app.publish_role_version(v_reviewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_reviewer_role and status = 'published'), '00000000-0000-0000-0000-000000025103', '00000000-0000-0000-0000-000000025101', 'tester');

  v_manager_role := (app.create_role(v_tenant1, 'PRC Manager', 'Override/Edit/View', 'tester')).id;
  v_manager_draft := app.create_role_version(v_manager_role, 'tester');
  perform app.set_role_version_permissions(v_manager_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Override', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000025104', '00000000-0000-0000-0000-000000025101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'PRC Viewer', 'View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000025105', '00000000-0000-0000-0000-000000025101', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'PRC Staff T2', 'Create/Edit/View', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000025202', '00000000-0000-0000-0000-000000025201', 'tester');
end $$;

\echo '>> RBAC seed: the five new PRC permission rows exist exactly once (ADR-0020)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.permissions where resource_module_code = 'PRC'
    and action in ('Reject', 'Override', 'Download', 'Import', 'View personal data');
  if v_count <> 5 then
    raise exception 'assertion failed: expected exactly 5 new PRC permission rows, found %', v_count;
  end if;
end $$;

\echo '>> full lifecycle happy path: draft -> add children -> submit -> begin_review -> approve -> activate -> suspend -> reactivate -> suspend -> archive'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000025103';
  v_manager uuid := '00000000-0000-0000-0000-000000025104';
  v_viewer uuid := '00000000-0000-0000-0000-000000025105';
  v_profile app.vendor_profiles;
  v_contact app.vendor_contacts;
  v_history_count integer;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Contoso Logistik', 'Contoso', 'PT', 'REG-0001', 'trucking', 30, 'staff_created', 'idem-lifecycle-1', v_staff, 'staff');
  if v_profile.lifecycle_status <> 'draft' then
    raise exception 'assertion failed: expected draft, got %', v_profile.lifecycle_status;
  end if;

  -- submit is blocked without a contact/address/service.
  begin
    perform app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff, 'staff');
    raise exception 'assertion failed: expected missing_required_contact';
  exception
    when others then
      if sqlerrm not like 'missing_required_contact%' then raise; end if;
  end;

  v_contact := app.add_vendor_contact(v_profile.master_record_id, 'Jane Vendor', 'Ops Manager', 'jane@contoso-log.test', '0811-000-001', true, v_staff, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'trucking', v_staff, 'staff');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_staff, 'staff');

  -- viewer cannot submit (insufficient_authority: PRC:Edit).
  begin
    perform app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for viewer submitting';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff, 'staff');
  if v_profile.lifecycle_status <> 'submitted' then
    raise exception 'assertion failed: expected submitted, got %', v_profile.lifecycle_status;
  end if;

  -- staff (PRC:Edit only) cannot begin review (requires PRC:Approve).
  begin
    perform app.begin_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, v_staff, 'staff');
    raise exception 'assertion failed: expected insufficient_authority for staff beginning review';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_profile := app.begin_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, v_reviewer, 'reviewer');
  if v_profile.lifecycle_status <> 'under_review' then
    raise exception 'assertion failed: expected under_review, got %', v_profile.lifecycle_status;
  end if;

  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_reviewer, 'reviewer');
  if v_profile.lifecycle_status <> 'approved' then
    raise exception 'assertion failed: expected approved, got %', v_profile.lifecycle_status;
  end if;

  -- this decision followed a real begin_vendor_profile_review call -- from_status
  -- must correctly record 'under_review' (the control case for the reject-path
  -- regression test elsewhere in this file, which decides directly from 'submitted').
  if (
    select from_status from app.vendor_profile_lifecycle_events
    where master_record_id = v_profile.master_record_id and to_status = 'approved'
  ) <> 'under_review' then
    raise exception 'assertion failed: expected the approve lifecycle event''s from_status to be under_review after a real begin_vendor_profile_review call';
  end if;

  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_reviewer, 'reviewer');
  if v_profile.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected active, got %', v_profile.lifecycle_status;
  end if;

  -- reviewer (no PRC:Override) cannot suspend.
  begin
    perform app.suspend_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'quality issue', v_reviewer, 'reviewer');
    raise exception 'assertion failed: expected insufficient_authority for reviewer suspending';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- suspend requires a reason.
  begin
    perform app.suspend_vendor_profile(v_profile.master_record_id, v_profile.record_version, '', v_manager, 'manager');
    raise exception 'assertion failed: expected reason_required';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_profile := app.suspend_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'quality issue', v_manager, 'manager');
  if v_profile.lifecycle_status <> 'suspended' or v_profile.suspend_reason <> 'quality issue' then
    raise exception 'assertion failed: expected suspended with reason, got % / %', v_profile.lifecycle_status, v_profile.suspend_reason;
  end if;

  v_profile := app.reactivate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_manager, 'manager');
  if v_profile.lifecycle_status <> 'active' or v_profile.suspend_reason is not null then
    raise exception 'assertion failed: expected active with cleared suspend_reason, got % / %', v_profile.lifecycle_status, v_profile.suspend_reason;
  end if;

  -- archive is blocked directly from active (must suspend first).
  begin
    perform app.archive_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'closing', v_manager, 'manager');
    raise exception 'assertion failed: expected invalid_transition archiving directly from active';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  v_profile := app.suspend_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'closing down', v_manager, 'manager');
  v_profile := app.archive_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'closing', v_manager, 'manager');
  if v_profile.lifecycle_status <> 'archived' then
    raise exception 'assertion failed: expected archived, got %', v_profile.lifecycle_status;
  end if;

  select count(*) into v_history_count from app.get_vendor_lifecycle_history(v_profile.master_record_id, v_staff);
  if v_history_count <> 9 then
    raise exception 'assertion failed: expected 9 lifecycle history events (none->draft, draft->submitted, submitted->under_review, under_review->approved, approved->active, active->suspended, suspended->active, active->suspended, suspended->archived), found %', v_history_count;
  end if;
end $$;

\echo '>> reject path: submitted vendor profile is rejected back to draft with a revision reason, then resubmittable'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000025103';
  v_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Reject Test', null, 'PT', null, 'warehousing', null, 'staff_created', 'idem-reject-1', v_staff, 'staff');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Bob Reject', null, null, null, true, v_staff, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Reject 1', 'Bandung', null, null, 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'warehousing', v_staff, 'staff');
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff, 'staff');

  -- reject requires a reason.
  begin
    perform app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'reject', null, v_reviewer, 'reviewer');
    raise exception 'assertion failed: expected reason_required for reject with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'reject', 'missing legal documentation', v_reviewer, 'reviewer');
  if v_profile.lifecycle_status <> 'draft' or v_profile.revision_reason <> 'missing legal documentation' then
    raise exception 'assertion failed: expected draft with revision_reason set, got % / %', v_profile.lifecycle_status, v_profile.revision_reason;
  end if;

  -- this decision was made directly from 'submitted' (begin_vendor_profile_review was
  -- never called) -- the lifecycle_events row's from_status must record the REAL
  -- prior status, not a hardcoded 'under_review' literal (found and fixed in
  -- adversarial review: both CASE branches in decide_vendor_profile_review produced
  -- the same literal regardless of the actual prior status).
  if (
    select from_status from app.vendor_profile_lifecycle_events
    where master_record_id = v_profile.master_record_id and to_status = 'draft' and reason = 'missing legal documentation'
  ) <> 'submitted' then
    raise exception 'assertion failed: expected the reject lifecycle event''s from_status to be the real prior status (submitted), not a hardcoded under_review literal';
  end if;

  -- resubmittable.
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff, 'staff');
  if v_profile.lifecycle_status <> 'submitted' then
    raise exception 'assertion failed: expected resubmitted, got %', v_profile.lifecycle_status;
  end if;
end $$;

\echo '>> blacklist: reachable from active, requires reason AND evidence'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000025103';
  v_manager uuid := '00000000-0000-0000-0000-000000025104';
  v_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Blacklist Test', null, 'PT', null, 'trucking', null, 'staff_created', 'idem-blacklist-1', v_staff, 'staff');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Ann Black', null, null, null, true, v_staff, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Black 1', 'Medan', null, null, 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'trucking', v_staff, 'staff');
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff, 'staff');
  v_profile := app.begin_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, v_reviewer, 'reviewer');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_reviewer, 'reviewer');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_reviewer, 'reviewer');

  begin
    perform app.blacklist_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'fraud', null, v_manager, 'manager');
    raise exception 'assertion failed: expected evidence_required';
  exception
    when others then
      if sqlerrm not like 'evidence_required%' then raise; end if;
  end;

  v_profile := app.blacklist_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'confirmed fraud', 'app.files:11111111-1111-1111-1111-111111111111', v_manager, 'manager');
  if v_profile.lifecycle_status <> 'blacklisted' then
    raise exception 'assertion failed: expected blacklisted, got %', v_profile.lifecycle_status;
  end if;
end $$;

\echo '>> duplicate-candidate detection: trigram search finds a similar legal_name; submission is blocked while a candidate is pending; dismissing it unblocks submission'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_existing app.vendor_profiles;
  v_new app.vendor_profiles;
  v_candidate app.vendor_duplicate_candidates;
  v_search_count integer;
begin
  v_existing := app.create_vendor_profile_draft(v_tenant1, 'PT Nusantara Cargo Ekspres', 'Nusantara Cargo', 'PT', null, 'trucking', null, 'staff_created', 'idem-dupe-existing', v_staff, 'staff');

  select count(*) into v_search_count from app.search_vendor_duplicate_candidates(v_tenant1, 'PT Nusantara Cargo Express', null, v_staff, 10);
  if v_search_count = 0 then
    raise exception 'assertion failed: expected trigram search to find a similar existing legal_name';
  end if;

  v_new := app.create_vendor_profile_draft(v_tenant1, 'PT Nusantara Cargo Express', null, 'PT', null, 'trucking', null, 'staff_created', 'idem-dupe-new', v_staff, 'staff');
  perform app.add_vendor_contact(v_new.master_record_id, 'Dupe Contact', null, null, null, true, v_staff, 'staff');
  perform app.add_vendor_address(v_new.master_record_id, 'legal', 'Jl. Dupe 1', 'Semarang', null, null, 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_new.master_record_id, 'trucking', v_staff, 'staff');

  v_candidate := app.flag_vendor_duplicate_candidate(v_new.master_record_id, v_existing.master_record_id, 'trigram legal_name similarity', 0.7, v_staff, 'staff');

  begin
    perform app.submit_vendor_profile_for_review(v_new.master_record_id, v_new.record_version, v_staff, 'staff');
    raise exception 'assertion failed: expected unresolved_duplicate_candidates to block submission';
  exception
    when others then
      if sqlerrm not like 'unresolved_duplicate_candidates%' then raise; end if;
  end;

  perform app.decide_vendor_duplicate_candidate(v_candidate.id, v_candidate.record_version, 'dismissed', 'confirmed genuinely different legal entities', v_staff, 'staff');

  v_new := app.submit_vendor_profile_for_review(v_new.master_record_id, v_new.record_version, v_staff, 'staff');
  if v_new.lifecycle_status <> 'submitted' then
    raise exception 'assertion failed: expected submission to succeed after dismissing the duplicate candidate, got %', v_new.lifecycle_status;
  end if;

  -- never auto-merged: the existing vendor profile is untouched.
  if (select lifecycle_status from app.vendor_profiles where master_record_id = v_existing.master_record_id) <> 'draft' then
    raise exception 'assertion failed: expected the candidate vendor profile to remain untouched (never auto-merged)';
  end if;
end $$;

\echo '>> duplicate-candidate decision ''linked'' -- the path closest to merge territory -- unblocks submission the SAME way ''dismissed'' does, and NEITHER master_records row is touched by app.merge_master_records or any other write'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_existing app.vendor_profiles;
  v_new app.vendor_profiles;
  v_candidate app.vendor_duplicate_candidates;
  v_existing_master_before app.master_records;
  v_existing_master_after app.master_records;
begin
  v_existing := app.create_vendor_profile_draft(v_tenant1, 'PT Borneo Freight Solusi', 'Borneo Freight', 'PT', null, 'trucking', null, 'staff_created', 'idem-linked-existing', v_staff, 'staff');
  select * into v_existing_master_before from app.master_records where id = v_existing.master_record_id;

  v_new := app.create_vendor_profile_draft(v_tenant1, 'PT Borneo Freight Solutions', null, 'PT', null, 'trucking', null, 'staff_created', 'idem-linked-new', v_staff, 'staff');
  perform app.add_vendor_contact(v_new.master_record_id, 'Linked Contact', null, null, null, true, v_staff, 'staff');
  perform app.add_vendor_address(v_new.master_record_id, 'legal', 'Jl. Linked 1', 'Balikpapan', null, null, 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_new.master_record_id, 'trucking', v_staff, 'staff');

  v_candidate := app.flag_vendor_duplicate_candidate(v_new.master_record_id, v_existing.master_record_id, 'trigram legal_name similarity', 0.8, v_staff, 'staff');

  perform app.decide_vendor_duplicate_candidate(v_candidate.id, v_candidate.record_version, 'linked', 'confirmed the same real-world vendor, linking for reviewer awareness', v_staff, 'staff');

  if (select decision from app.vendor_duplicate_candidates where id = v_candidate.id) <> 'linked' then
    raise exception 'assertion failed: expected the candidate decision to be recorded as linked';
  end if;

  v_new := app.submit_vendor_profile_for_review(v_new.master_record_id, v_new.record_version, v_staff, 'staff');
  if v_new.lifecycle_status <> 'submitted' then
    raise exception 'assertion failed: expected submission to succeed after linking the duplicate candidate, got %', v_new.lifecycle_status;
  end if;

  -- the two vendor identities remain fully separate: never auto-merged. Both
  -- master_records rows and both vendor_profiles rows survive untouched by the
  -- 'linked' decision -- a regression wiring 'linked' to app.merge_master_records
  -- (or to any write beyond vendor_duplicate_candidates itself) would fail here.
  select * into v_existing_master_after from app.master_records where id = v_existing.master_record_id;
  if v_existing_master_after.id is distinct from v_existing_master_before.id
     or v_existing_master_after.code is distinct from v_existing_master_before.code
     or v_existing_master_after.name is distinct from v_existing_master_before.name then
    raise exception 'assertion failed: expected the existing vendor''s master_records row to be byte-for-byte untouched by a linked decision';
  end if;
  if (select lifecycle_status from app.vendor_profiles where master_record_id = v_existing.master_record_id) <> 'draft' then
    raise exception 'assertion failed: expected the linked candidate vendor profile to remain untouched (never auto-merged)';
  end if;
  if not exists (select 1 from app.vendor_profiles where master_record_id = v_new.master_record_id) then
    raise exception 'assertion failed: expected the new vendor profile to still exist as its own separate identity after linking';
  end if;
end $$;

\echo '>> intake token: issuance, redemption creates a submitted vendor profile with a primary contact, replay-with-same-content is idempotent, replay-with-different-content is a conflict, expired and revoked tokens are rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_issued record;
  v_redeemed record;
  v_replay record;
  v_conflict record;
  v_profile app.vendor_profiles;
  v_contact_count integer;
  v_revoked_issued record;
  v_expired_hash text;
  v_expired_token_id uuid;
begin
  select * into v_issued from app.create_vendor_intake_token(v_tenant1, 'invitee@newvendor.test', 7, 'idem-token-1', v_staff, 'staff');
  if v_issued.raw_token is null then
    raise exception 'assertion failed: expected a raw_token on first issuance';
  end if;

  select * into v_redeemed from app.redeem_vendor_intake_token_and_submit(
    v_issued.raw_token, 'client-key-1', 'PT Invitee Logistics', 'Invitee', 'PT', 'REG-9001', 'trucking', 45,
    'Token Contact', 'contact@newvendor.test', '0812-000-002'
  );
  if v_redeemed.submit_status <> 'ok' or v_redeemed.master_record_id is null then
    raise exception 'assertion failed: expected ok redemption, got % / %', v_redeemed.submit_status, v_redeemed.master_record_id;
  end if;

  select * into v_profile from app.vendor_profiles where master_record_id = v_redeemed.master_record_id;
  if v_profile.lifecycle_status <> 'submitted' or v_profile.intake_source <> 'invited' then
    raise exception 'assertion failed: expected submitted/invited, got % / %', v_profile.lifecycle_status, v_profile.intake_source;
  end if;

  select count(*) into v_contact_count from app.vendor_contacts where master_record_id = v_redeemed.master_record_id and is_primary and status = 'active';
  if v_contact_count <> 1 then
    raise exception 'assertion failed: expected exactly one primary contact from token redemption, found %', v_contact_count;
  end if;

  -- replay with the SAME content is idempotent (token is single-use by construction).
  select * into v_replay from app.redeem_vendor_intake_token_and_submit(
    v_issued.raw_token, 'client-key-1', 'PT Invitee Logistics', 'Invitee', 'PT', 'REG-9001', 'trucking', 45,
    'Token Contact', 'contact@newvendor.test', '0812-000-002'
  );
  if v_replay.submit_status <> 'ok' or v_replay.master_record_id <> v_redeemed.master_record_id then
    raise exception 'assertion failed: expected idempotent replay to return the same master_record_id, got % / %', v_replay.submit_status, v_replay.master_record_id;
  end if;

  -- replay with DIFFERENT content is a conflict, never silently overwritten.
  select * into v_conflict from app.redeem_vendor_intake_token_and_submit(
    v_issued.raw_token, 'client-key-1', 'PT Totally Different Co', null, 'PT', null, 'trucking', null, null, null, null
  );
  if v_conflict.submit_status <> 'conflict' then
    raise exception 'assertion failed: expected conflict for a redeemed token replayed with different content, got %', v_conflict.submit_status;
  end if;

  -- an unknown/garbage raw token is not_found.
  select * into v_conflict from app.redeem_vendor_intake_token_and_submit('not-a-real-token', 'client-key-2', 'PT Anything', null, null, null, null, null, null, null, null);
  if v_conflict.submit_status <> 'not_found' then
    raise exception 'assertion failed: expected not_found for a garbage token, got %', v_conflict.submit_status;
  end if;

  -- revoked token cannot be redeemed.
  select * into v_revoked_issued from app.create_vendor_intake_token(v_tenant1, 'revoke-me@newvendor.test', 7, 'idem-token-revoke', v_staff, 'staff');
  perform app.revoke_vendor_intake_token(v_revoked_issued.token_id, 'invited the wrong email', v_staff, 'staff');
  select * into v_conflict from app.redeem_vendor_intake_token_and_submit(v_revoked_issued.raw_token, 'client-key-3', 'PT Revoked Co', null, null, null, null, null, null, null, null);
  if v_conflict.submit_status <> 'not_found' then
    raise exception 'assertion failed: expected not_found for a revoked token, got %', v_conflict.submit_status;
  end if;

  -- expired token cannot be redeemed (backdate expires_at directly at the storage layer, this is test fixture setup, not a product action).
  v_expired_hash := encode(digest('expired-raw-token-fixture', 'sha256'), 'hex');
  insert into app.vendor_intake_tokens (tenant_id, token_hash, intended_email, expires_at, created_by)
  values (v_tenant1, v_expired_hash, 'expired@newvendor.test', now() - interval '1 day', 'tester')
  returning id into v_expired_token_id;
  select * into v_conflict from app.redeem_vendor_intake_token_and_submit('expired-raw-token-fixture', 'client-key-4', 'PT Expired Co', null, null, null, null, null, null, null, null);
  if v_conflict.submit_status <> 'not_found' then
    raise exception 'assertion failed: expected not_found for an expired token, got %', v_conflict.submit_status;
  end if;

  -- a token whose status is the LITERAL 'expired' value (not merely a still-'pending'
  -- row past its own expires_at) is also rejected. Found in adversarial review: the
  -- original guard only special-cased 'revoked' and inferred expiry from
  -- expires_at while status='pending', never checking status='expired' directly --
  -- latent today (nothing yet writes that literal value), but the column is
  -- explicitly modeled for it and a future expiry-sweep job would have silently
  -- reopened every such token for redemption.
  declare
    v_literal_expired_hash text := encode(digest('literal-expired-raw-token-fixture', 'sha256'), 'hex');
  begin
    insert into app.vendor_intake_tokens (tenant_id, token_hash, intended_email, expires_at, status, created_by)
    values (v_tenant1, v_literal_expired_hash, 'literal-expired@newvendor.test', now() + interval '30 days', 'expired', 'tester');
    select * into v_conflict from app.redeem_vendor_intake_token_and_submit('literal-expired-raw-token-fixture', 'client-key-5', 'PT Literal Expired Co', null, null, null, null, null, null, null, null);
    if v_conflict.submit_status <> 'not_found' then
      raise exception 'assertion failed: expected not_found for a token whose status is literally ''expired'', got %', v_conflict.submit_status;
    end if;
    if exists (select 1 from app.vendor_profiles where legal_name = 'PT Literal Expired Co') then
      raise exception 'assertion failed: a literally-expired token must never create a vendor profile';
    end if;
  end;

  -- idempotency-key-reused-for-a-different-target on token issuance is rejected.
  begin
    perform app.create_vendor_intake_token(v_tenant1, 'a-totally-different-email@newvendor.test', 7, 'idem-token-1', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict reusing idem-token-1 for a different intended_email';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
end $$;

\echo '>> a still-valid, unexpired intake token cannot be redeemed once its own tenant is suspended (matches submit_vendor_profile_self_registration''s own sibling rule) -- tenant is restored to active immediately after so later tests are unaffected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_issued record;
  v_result record;
begin
  select * into v_issued from app.create_vendor_intake_token(v_tenant1, 'suspend-window@newvendor.test', 7, 'idem-token-suspend-window', v_staff, 'staff');

  update app.tenants set canonical_status = 'suspended' where id = v_tenant1;

  select * into v_result from app.redeem_vendor_intake_token_and_submit(
    v_issued.raw_token, 'client-key-6', 'PT Suspended Window Co', null, null, null, null, null, null, null, null
  );
  if v_result.submit_status <> 'not_found' then
    raise exception 'assertion failed: expected not_found redeeming a valid token while its own tenant is suspended, got %', v_result.submit_status;
  end if;
  if exists (select 1 from app.vendor_profiles where legal_name = 'PT Suspended Window Co') then
    raise exception 'assertion failed: a token redemption must never succeed while its own tenant is suspended';
  end if;

  update app.tenants set canonical_status = 'active' where id = v_tenant1;

  -- the SAME still-'pending' token now redeems successfully once the tenant is active again.
  select * into v_result from app.redeem_vendor_intake_token_and_submit(
    v_issued.raw_token, 'client-key-6', 'PT Suspended Window Co', null, null, null, null, null, null, null, null
  );
  if v_result.submit_status <> 'ok' then
    raise exception 'assertion failed: expected the same token to redeem successfully once its tenant is active again, got %', v_result.submit_status;
  end if;
end $$;

\echo '>> self-registration: disabled by default (BP-A08), enabling via the Configuration Engine unblocks it, and idempotency-key target-mismatch is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_admin uuid := '00000000-0000-0000-0000-000000025101';
  v_result record;
  v_draft app.config_versions;
begin
  select * into v_result from app.submit_vendor_profile_self_registration(
    v_tenant1, 'self-client-1', 'PT Self Reg Blocked', null, 'PT', null, 'trucking', null, 'Self Contact', 'self@newvendor.test', null, 'idem-self-1'
  );
  if v_result.submit_status <> 'disabled' then
    raise exception 'assertion failed: expected disabled (self-registration off by default), got %', v_result.submit_status;
  end if;

  v_draft := app.create_config_draft('feature', v_tenant1, 'tenant', null, v_admin, 'admin');
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'procurement.vendor_self_registration.enabled', 'value', true)), v_admin, 'admin');
  perform app.publish_config_version(v_draft.id, v_admin, now(), 'admin');

  select * into v_result from app.submit_vendor_profile_self_registration(
    v_tenant1, 'self-client-2', 'PT Self Reg Enabled', null, 'PT', null, 'trucking', null, 'Self Contact', 'self@newvendor.test', null, 'idem-self-2'
  );
  if v_result.submit_status <> 'ok' or v_result.master_record_id is null then
    raise exception 'assertion failed: expected ok once self-registration is enabled, got % / %', v_result.submit_status, v_result.master_record_id;
  end if;
  if (select intake_source from app.vendor_profiles where master_record_id = v_result.master_record_id) <> 'self_registered' then
    raise exception 'assertion failed: expected intake_source=self_registered';
  end if;

  -- idempotent replay with the same content.
  select * into v_result from app.submit_vendor_profile_self_registration(
    v_tenant1, 'self-client-2', 'PT Self Reg Enabled', null, 'PT', null, 'trucking', null, 'Self Contact', 'self@newvendor.test', null, 'idem-self-2'
  );
  if v_result.submit_status <> 'ok' then
    raise exception 'assertion failed: expected idempotent ok replay, got %', v_result.submit_status;
  end if;

  -- idempotency-key reused for a different target is a conflict, never silently returned/overwritten.
  select * into v_result from app.submit_vendor_profile_self_registration(
    v_tenant1, 'self-client-2', 'PT Totally Different Self Co', null, 'PT', null, 'trucking', null, null, null, null, 'idem-self-2'
  );
  if v_result.submit_status <> 'conflict' then
    raise exception 'assertion failed: expected conflict reusing idem-self-2 for a different legal_name, got %', v_result.submit_status;
  end if;
end $$;

\echo '>> self-registration remains disabled for a DIFFERENT tenant that never published the flag (tenant-scoped, never a global switch)'
do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'vndreg2');
  v_result record;
begin
  select * into v_result from app.submit_vendor_profile_self_registration(
    v_tenant2, 'self-client-t2', 'PT Tenant2 Self', null, 'PT', null, 'trucking', null, null, null, null, 'idem-self-t2'
  );
  if v_result.submit_status <> 'disabled' then
    raise exception 'assertion failed: expected disabled for tenant2 (its own flag was never published), got %', v_result.submit_status;
  end if;
end $$;

\echo '>> idempotency-key replay AND idempotency-key-reused-for-a-different-target on create_vendor_profile_draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_first app.vendor_profiles;
  v_replay app.vendor_profiles;
begin
  v_first := app.create_vendor_profile_draft(v_tenant1, 'PT Idem Draft Co', null, 'PT', null, 'trucking', null, 'staff_created', 'idem-draft-replay', v_staff, 'staff');
  v_replay := app.create_vendor_profile_draft(v_tenant1, 'PT Idem Draft Co', null, 'PT', null, 'trucking', null, 'staff_created', 'idem-draft-replay', v_staff, 'staff');
  if v_replay.master_record_id <> v_first.master_record_id then
    raise exception 'assertion failed: expected idempotent replay to return the same master_record_id';
  end if;

  begin
    perform app.create_vendor_profile_draft(v_tenant1, 'PT A Totally Different Co', null, 'PT', null, 'trucking', null, 'staff_created', 'idem-draft-replay', v_staff, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict for idem-draft-replay reused with a different legal_name';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;
end $$;

\echo '>> record_version stale-version rejection, on both the pre-check and the post-UPDATE re-check'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Stale Version Co', null, 'PT', null, 'trucking', null, 'staff_created', 'idem-stale-1', v_staff, 'staff');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Stale Contact', null, null, null, true, v_staff, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Stale 1', 'Bogor', null, null, 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'trucking', v_staff, 'staff');

  -- pre-check: caller passes an expected_version that is already wrong.
  begin
    perform app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version + 99, v_staff, 'staff');
    raise exception 'assertion failed: expected stale_version on the pre-check';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- winner succeeds and genuinely advances record_version.
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff, 'staff');

  -- a second call reusing the now-stale (pre-winner) version must also fail -- proves
  -- the post-UPDATE re-check, not just the pre-check, since the row genuinely moved
  -- between the caller's read and this call.
  begin
    perform app.begin_vendor_profile_review(v_profile.master_record_id, v_profile.record_version - 1, '00000000-0000-0000-0000-000000025103', 'reviewer');
    raise exception 'assertion failed: expected stale_version reusing an already-superseded expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
end $$;

\echo '>> child-record CRUD is draft-only: once submitted, add/update/remove of contacts/addresses/services/coverage is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Draft Only Co', null, 'PT', null, 'trucking', null, 'staff_created', 'idem-draftonly-1', v_staff, 'staff');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Draft Contact', null, null, null, true, v_staff, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Draft 1', 'Malang', null, null, 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'trucking', v_staff, 'staff');
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff, 'staff');

  begin
    perform app.add_vendor_service(v_profile.master_record_id, 'warehousing', v_staff, 'staff');
    raise exception 'assertion failed: expected vendor_profile_not_draft adding a service after submission';
  exception
    when others then
      if sqlerrm not like 'vendor_profile_not_draft%' then raise; end if;
  end;
end $$;

\echo '>> cross-tenant isolation: vndreg2''s staff, holding zero membership in vndreg1, is rejected on every RPC against vndreg1''s real vendor, and raw RLS denies a direct select'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_t2_staff uuid := '00000000-0000-0000-0000-000000025202';
  v_target_master_record_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-lifecycle-1');
begin
  begin
    perform app.get_vendor_profile(v_target_master_record_id, v_t2_staff);
    raise exception 'assertion failed: expected insufficient_authority for a vndreg2 actor reading a vndreg1 vendor profile';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    -- reuses a REAL, already-consumed vndreg1 idempotency key -- must still be
    -- rejected on authority grounds, never silently short-circuited into vndreg1's
    -- real data (idempotent-replay-after-authority regression, bug class a).
    perform app.create_vendor_profile_draft(v_tenant1, 'PT Cross Tenant Attempt', null, 'PT', null, 'trucking', null, 'staff_created', 'idem-lifecycle-1', v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected insufficient_authority for a vndreg2 actor creating a draft under vndreg1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000025202", "role": "authenticated"}', true);

  if exists (select 1 from app.vendor_profiles where master_record_id = v_target_master_record_id) then
    raise exception 'assertion failed: raw RLS leak -- vndreg2 staff directly selected a vndreg1 vendor profile row';
  end if;

  reset role;
end $$;

\echo '>> RLS default-deny for a customer_user-layer principal: tenant membership alone is not enough -- a customer_user-layer actor in the SAME tenant reads zero vendor rows at the raw-RLS level'
do $$
declare
  v_target_master_record_id uuid := (select vp.master_record_id from app.vendor_profiles vp join app.tenants t on t.id = vp.tenant_id where t.slug = 'vndreg1' and vp.idempotency_key = 'idem-lifecycle-1');
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000025106", "role": "authenticated"}', true);

  if exists (select 1 from app.vendor_profiles where master_record_id = v_target_master_record_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.vendor_profiles directly, even inside its own tenant';
  end if;
  if exists (select 1 from app.vendor_contacts where master_record_id = v_target_master_record_id) then
    raise exception 'assertion failed: a customer_user-layer principal must never read app.vendor_contacts directly';
  end if;

  reset role;
end $$;

\echo '>> field masking: a caller without PRC:View personal data sees a contact''s name/title but not email/phone; a caller WITH it sees everything'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_admin uuid := '00000000-0000-0000-0000-000000025101';
  v_target_master_record_id uuid := (select master_record_id from app.vendor_profiles where tenant_id = v_tenant1 and idempotency_key = 'idem-lifecycle-1');
  v_masked_row record;
  v_unmasked_row record;
begin
  select * into v_masked_row from app.list_vendor_contacts(v_target_master_record_id, v_staff) limit 1;
  if v_masked_row.email is not null or v_masked_row.phone is not null then
    raise exception 'assertion failed: expected email/phone masked for a caller without PRC:View personal data';
  end if;
  if v_masked_row.name is null then
    raise exception 'assertion failed: expected name to remain visible even when email/phone are masked';
  end if;

  -- tenant_admin holds is_supreme_admin/tenant_admin authority, but evaluate_permission
  -- for a plain PRC action still requires a real role grant -- grant the admin a
  -- PRC:View + PRC:View personal data role to observe the unmasked path.
  declare
    v_role uuid;
    v_draft app.role_versions;
  begin
    v_role := (app.create_role(v_tenant1, 'PRC Personal Data Viewer', 'View + View personal data', 'tester')).id;
    v_draft := app.create_role_version(v_role, 'tester');
    perform app.set_role_version_permissions(v_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('View', 'View personal data')), 'tester');
    perform app.publish_role_version(v_draft.id, now(), 'tester');
    -- Assigned by the global Supreme Admin, never by v_admin themself -- app.assign_role
    -- refuses a self-assignment of a role carrying a protected permission
    -- (self_escalation), and 'View personal data' is seeded protected=true.
    perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), v_admin, '00000000-0000-0000-0000-000000025999', 'tester');
  end;

  select * into v_unmasked_row from app.list_vendor_contacts(v_target_master_record_id, v_admin) limit 1;
  if v_unmasked_row.email is null then
    raise exception 'assertion failed: expected email visible for a caller WITH PRC:View personal data';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004 regression guard): anon holds no direct table/EXECUTE access to any new vendor object; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly; the two anonymous intake RPCs are service_role-only, never anon'
do $$
declare
  v_has_priv boolean;
begin
  select has_table_privilege('anon', 'app.vendor_profiles', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not have SELECT on app.vendor_profiles'; end if;

  select has_table_privilege('authenticated', 'app.vendor_profiles', 'INSERT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not have direct INSERT on app.vendor_profiles'; end if;

  select has_table_privilege('service_role', 'app.vendor_profiles', 'INSERT') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: service_role must have direct INSERT on app.vendor_profiles'; end if;

  select has_function_privilege('anon', 'app.redeem_vendor_intake_token_and_submit(text, text, text, text, text, text, text, integer, text, text, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.redeem_vendor_intake_token_and_submit'; end if;

  select has_function_privilege('anon', 'app.submit_vendor_profile_self_registration(uuid, text, text, text, text, text, text, integer, text, text, text, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.submit_vendor_profile_self_registration'; end if;

  select has_function_privilege('service_role', 'app.redeem_vendor_intake_token_and_submit(text, text, text, text, text, text, text, integer, text, text, text)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: service_role must hold EXECUTE on app.redeem_vendor_intake_token_and_submit'; end if;

  select has_function_privilege('anon', 'app.resolve_vendor_self_registration_target(text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.resolve_vendor_self_registration_target'; end if;

  select has_function_privilege('service_role', 'app.resolve_vendor_self_registration_target(text)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: service_role must hold EXECUTE on app.resolve_vendor_self_registration_target'; end if;

  select has_table_privilege('authenticated', 'app.vendor_code_counters', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not have SELECT on app.vendor_code_counters (restored deny-all RLS regression guard)'; end if;

  select relrowsecurity into v_has_priv from pg_class where oid = 'app.vendor_code_counters'::regclass;
  if not v_has_priv then raise exception 'assertion failed: expected RLS enabled on app.vendor_code_counters, mirroring app.quotation_number_counters (COM-151)'; end if;

  if not exists (select 1 from pg_policies where schemaname = 'app' and tablename = 'vendor_code_counters' and policyname = 'vendor_code_counters_none') then
    raise exception 'assertion failed: expected the vendor_code_counters_none deny-all policy to exist';
  end if;

  select has_function_privilege('authenticated', 'app.next_vendor_code(uuid)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not hold direct EXECUTE on app.next_vendor_code (ISS-2026-033 lesson)'; end if;
end $$;

\echo '>> never touched: app.master_records/app.master_types/app.vendor_rate_versions structural shape is unchanged by this migration'
do $$
declare
  v_count integer;
  v_has_link_column boolean;
begin
  select count(*) into v_count from app.master_types where code in ('vendor', 'vendor_rate');
  if v_count <> 2 then
    raise exception 'assertion failed: expected both vendor and vendor_rate master types to remain exactly as PLT-120/OPS-172 seeded them, found %', v_count;
  end if;

  -- vendor_master_id is explicitly Prompt 255's own future addition to
  -- app.vendor_rate_versions, never this migration's -- confirms the boundary held.
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'vendor_rate_versions' and column_name = 'vendor_master_id'
  ) into v_has_link_column;
  if v_has_link_column then
    raise exception 'assertion failed: app.vendor_rate_versions.vendor_master_id must not exist yet -- it is Prompt 255''s own additive scope, not PRC-251''s';
  end if;
end $$;
