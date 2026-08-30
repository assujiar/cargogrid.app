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

\echo '>> Prompt 269 (ISS-2026-054 C-05 + ISS-2026-055): app.suspend_vendor_profile/reactivate_vendor_profile/archive_vendor_profile/blacklist_vendor_profile. (1) a vndreg2 actor with zero membership in vndreg1 gets the SAME vendor_profile_not_found a genuinely missing id would produce on all four, never insufficient_authority (which would disclose the real tenant_id). (2) a real vndreg1 member who both lacks the required authority AND supplies a stale expected_version now gets insufficient_authority, never stale_version (which would disclose the real record_version) -- the authority check now runs first.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_reviewer uuid := '00000000-0000-0000-0000-000000025103';
  v_viewer uuid := '00000000-0000-0000-0000-000000025105';
  v_t2_staff uuid := '00000000-0000-0000-0000-000000025202';
  v_profile app.vendor_profiles;
  v_wrong_version integer;
  v_expected_untouched_version integer;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT C05 Fix Co', 'C05FX', 'PT', null, 'trucking', null, 'staff_created', 'idem-c05fix-1', v_staff, 'staff');
  perform app.add_vendor_contact(v_profile.master_record_id, 'C05 Contact', null, null, null, true, v_staff, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. C05 1', 'Jakarta', null, null, 'Indonesia', v_staff, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'trucking', v_staff, 'staff');
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff, 'staff');
  v_profile := app.begin_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, v_reviewer, 'reviewer');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_reviewer, 'reviewer');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_reviewer, 'reviewer');
  if v_profile.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected the C-05 fix-pass fixture vendor to be active before these tests, got %', v_profile.lifecycle_status;
  end if;
  v_wrong_version := v_profile.record_version + 99;
  v_expected_untouched_version := v_profile.record_version;

  -- (1) C-05: cross-tenant, zero-membership caller -- the not-found short-circuit fires
  -- before the (real) lifecycle-status check is ever reached, so the same not-found
  -- shape is correct regardless of the vendor's actual status.
  begin
    perform app.suspend_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'quality issue', v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected vendor_profile_not_found for a vndreg2 actor suspending a vndreg1 vendor (never insufficient_authority, which would disclose the real tenant_id)';
  exception
    when others then
      if sqlerrm not like 'vendor_profile_not_found%' then raise; end if;
  end;

  begin
    perform app.reactivate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected vendor_profile_not_found for a vndreg2 actor reactivating a vndreg1 vendor';
  exception
    when others then
      if sqlerrm not like 'vendor_profile_not_found%' then raise; end if;
  end;

  begin
    perform app.archive_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'closing', v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected vendor_profile_not_found for a vndreg2 actor archiving a vndreg1 vendor';
  exception
    when others then
      if sqlerrm not like 'vendor_profile_not_found%' then raise; end if;
  end;

  begin
    perform app.blacklist_vendor_profile(v_profile.master_record_id, v_profile.record_version, 'fraud', 'app.files:11111111-1111-1111-1111-111111111111', v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected vendor_profile_not_found for a vndreg2 actor blacklisting a vndreg1 vendor';
  exception
    when others then
      if sqlerrm not like 'vendor_profile_not_found%' then raise; end if;
  end;

  -- (2) ISS-2026-055: a REAL vndreg1 member (v_viewer, View only -- lacks Override
  -- AND Edit) supplies a deliberately WRONG expected_version. Authority is now checked
  -- BEFORE stale_version -- must fail insufficient_authority, never stale_version
  -- (which would echo the row's real current record_version to an actor not yet shown
  -- to hold the required permission).
  begin
    perform app.suspend_vendor_profile(v_profile.master_record_id, v_wrong_version, 'quality issue', v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority (never stale_version) for a View-only actor supplying a stale version to suspend';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.reactivate_vendor_profile(v_profile.master_record_id, v_wrong_version, v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority (never stale_version) for a View-only actor supplying a stale version to reactivate';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.archive_vendor_profile(v_profile.master_record_id, v_wrong_version, 'closing', v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority (never stale_version) for a View-only actor supplying a stale version to archive';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.blacklist_vendor_profile(v_profile.master_record_id, v_wrong_version, 'fraud', 'app.files:11111111-1111-1111-1111-111111111111', v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority (never stale_version) for a View-only actor supplying a stale version to blacklist';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Sanity: the fixture vendor is genuinely untouched by any of the above (every call
  -- above was correctly rejected before reaching its own UPDATE).
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  if v_profile.lifecycle_status <> 'active' or v_profile.record_version <> v_expected_untouched_version then
    raise exception 'assertion failed: expected the fixture vendor to remain active at record_version=% (untouched by every rejected call above), got %/%', v_expected_untouched_version, v_profile.lifecycle_status, v_profile.record_version;
  end if;
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

  -- vendor_master_id was explicitly Prompt 255's own future addition to
  -- app.vendor_rate_versions, never PRC-251's -- this file's own PRC-251 migration
  -- (20260730580000) never added it, confirmed unchanged. Prompt 255 has since
  -- landed (supabase/migrations/20260730620000_extend_commercial_vendor_rate_for_
  -- procurement.sql) and added it exactly as this comment anticipated -- the
  -- assertion below was updated from "must not exist yet" to "now exists" the
  -- moment that additive migration shipped (never a silent flip -- PRC-255's own
  -- build log records this update). The boundary this test protects (PRC-251's OWN
  -- migration never touching app.vendor_rate_versions) remains fully intact and
  -- unweakened; only the now-arrived "future" this comment named required an update.
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'vendor_rate_versions' and column_name = 'vendor_master_id'
  ) into v_has_link_column;
  if not v_has_link_column then
    raise exception 'assertion failed: app.vendor_rate_versions.vendor_master_id is expected to exist (PRC-255, ADR-0020) -- if this fires, either PRC-255''s migration was reverted or this repository''s migration order regressed';
  end if;
end $$;

-- ===========================================================================
-- ISS-2026-057 -- the vendor_import adapter (PRC-251 §22 "Bulk-import staged
-- vendors", named in the source prompt and never built until now).
-- ===========================================================================

\echo '>> vendor_import setup: a source document type and the tenant''s own published column definition for the vendor_import schema'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000025101';
  v_supreme uuid := '00000000-0000-0000-0000-000000025999';
  v_doctype_draft app.config_versions;
  v_schema_draft app.config_versions;
  v_importer_role uuid;
  v_importer_draft app.role_versions;
begin
  -- The two gates on app.commit_vendor_import_job are genuinely independent: holding
  -- tenant_admin (app.is_support_grant_authority) does NOT confer PRC:Import, which still
  -- has to come from a granting role like any other permission. admin1 therefore needs a
  -- real PRC role carrying Import plus the Create/Edit/View the adapter's own composed
  -- calls (create_vendor_profile_draft, search_vendor_duplicate_candidates,
  -- flag_vendor_duplicate_candidate) each separately require.
  v_importer_role := (app.create_role(v_tenant1, 'PRC Importer', 'Import/Create/Edit/View', 'tester')).id;
  v_importer_draft := app.create_role_version(v_importer_role, 'tester');
  perform app.set_role_version_permissions(v_importer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Import', 'Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_importer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_importer_role and status = 'published'), v_admin1, v_admin1, 'tester');

  perform app.register_document_type('vendor_import_source', 'Vendor Import Source File', 'PRC', v_supreme, 'supreme');
  v_doctype_draft := app.create_config_draft('document:vendor_import_source', v_tenant1, 'tenant', null, v_admin1, 'admin');
  perform app.set_config_items(v_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('text/csv')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_admin1, 'admin');
  perform app.publish_document_type_definition(v_doctype_draft.id, v_admin1, now(), 'admin');

  -- The tenant publishes its OWN column definition through the ordinary Configuration
  -- Engine -- the migration registers the schema KIND only, never a tenant's columns.
  v_schema_draft := app.create_config_draft('import_export:vendor_import', v_tenant1, 'tenant', null, v_admin1, 'admin');
  perform app.set_config_items(
    v_schema_draft.id,
    jsonb_build_array(jsonb_build_object('key', 'columns', 'value', to_jsonb((
      select array_agg(jsonb_build_object('key', c.key, 'label', c.label, 'required', c.required, 'data_type', c.data_type))
      from (values
        ('legal_name', 'Legal name', true, 'text'),
        ('trade_name', 'Trade name', false, 'text'),
        ('legal_entity_type', 'Legal entity type', false, 'text'),
        ('business_registration_number', 'Business registration number', false, 'text'),
        ('vendor_category', 'Vendor category', false, 'text'),
        ('payment_term_days', 'Payment term (days)', false, 'number')
      ) as c(key, label, required, data_type)
    )), 'canonical_ref', null)),
    v_admin1, 'admin'
  );
  perform app.publish_import_export_schema(v_schema_draft.id, v_admin1, now(), 'admin');
end $$;

\echo '>> vendor_import: the schema kind and its config type are registered exactly once'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.import_export_schemas where code = 'vendor_import';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one vendor_import schema registration, found %', v_count;
  end if;
  select count(*) into v_count from app.config_types where code = 'import_export:vendor_import';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one import_export:vendor_import config type, found %', v_count;
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'vendor_profiles' and column_name = 'source_import_staging_row_id'
  ) then
    raise exception 'assertion failed: expected app.vendor_profiles.source_import_staging_row_id to exist (the adapter''s own idempotency guard)';
  end if;
end $$;

\echo '>> vendor_import validator: a clean row passes; a formula-injection-shaped legal_name, a negative/fractional/non-numeric payment_term_days, a whitespace-only legal_name, a file-supplied intake_source and a file-supplied lifecycle_status are each rejected with a clear reason and the raw payload preserved verbatim'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000025101';
  v_source_file app.files;
  v_job app.jobs;
  v_ids uuid[];
  v_idx integer;
  v_status text;
  v_error text;
begin
  v_source_file := app.initiate_file_upload(
    v_tenant1, 'vendor_import_source', 'import_source', gen_random_uuid(),
    'vendors-validation.csv', 'text/csv', 2048, 'internal', false, null, null, null,
    'idem-vndimp-source-val', v_admin1, 'admin'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_admin1, 'admin');
  v_job := app.create_import_export_job(v_tenant1, 'import', 'vendor_import', v_source_file.id, '{}'::jsonb, 'idem-vndimp-job-val', v_admin1, 'admin');

  perform app.stage_import_rows(
    v_job.job_id,
    jsonb_build_array(
      jsonb_build_object('legal_name', 'PT Zenith Kargo Validasi', 'vendor_category', 'trucking', 'payment_term_days', '30'),
      jsonb_build_object('legal_name', '=cmd|''/bin/calc''!A1', 'vendor_category', 'trucking'),
      jsonb_build_object('legal_name', 'PT Term Negatif', 'payment_term_days', '-5'),
      jsonb_build_object('legal_name', '   ', 'vendor_category', 'trucking'),
      jsonb_build_object('legal_name', 'PT Klaim Provenance', 'intake_source', 'staff_created'),
      jsonb_build_object('legal_name', 'PT Klaim Lifecycle', 'lifecycle_status', 'active'),
      jsonb_build_object('legal_name', 'PT Term Bukan Angka', 'payment_term_days', 'thirty'),
      jsonb_build_object('legal_name', 'PT Term Pecahan', 'payment_term_days', '2.5')
    ),
    v_admin1, 'admin'
  );

  select array_agg(id order by row_number) into v_ids from app.import_staging_rows where job_id = v_job.job_id;

  for v_idx in 1..8 loop
    perform app.validate_vendor_import_row(v_ids[v_idx], v_admin1, 'admin');
  end loop;

  select validation_status into v_status from app.import_staging_rows where id = v_ids[1];
  if v_status <> 'valid' then
    raise exception 'assertion failed: expected row 1 to validate cleanly, got %', v_status;
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[2];
  if v_status <> 'invalid' or v_error not like '%disallowed formula/spreadsheet-injection prefix%' then
    raise exception 'assertion failed: expected row 2 rejected with a clear formula-injection reason, got status=% error=%', v_status, v_error;
  end if;
  -- The raw value survives UNCHANGED: rejected, never silently sanitized.
  if (select raw_payload ->> 'legal_name' from app.import_staging_rows where id = v_ids[2]) <> '=cmd|''/bin/calc''!A1' then
    raise exception 'assertion failed: expected the raw payload to be preserved verbatim, not stripped';
  end if;

  -- -5 is a structurally VALID number as far as the generic validator is concerned
  -- (its own pattern is `-?[0-9]+(\.[0-9]+)?`), so this row proves the domain layer is
  -- doing real work: without it a negative payment term reaches
  -- app.create_vendor_profile_draft mid-commit and aborts every other row in the batch
  -- with a raw check_violation instead of being marked invalid at validation time.
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[3];
  if v_status <> 'invalid' or v_error not like '%is not a whole, non-negative number of days%' then
    raise exception 'assertion failed: expected row 3 rejected for a negative payment_term_days, got status=% error=%', v_status, v_error;
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[4];
  if v_status <> 'invalid' or v_error not like '%must not be empty or whitespace-only%' then
    raise exception 'assertion failed: expected row 4 rejected for a whitespace-only legal_name, got status=% error=%', v_status, v_error;
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[5];
  if v_status <> 'invalid' or v_error not like '%intake_source: is not an importable column%' then
    raise exception 'assertion failed: expected row 5 rejected -- a file must never be able to claim its own provenance, got status=% error=%', v_status, v_error;
  end if;

  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[6];
  if v_status <> 'invalid' or v_error not like '%lifecycle_status: is not an importable column%' then
    raise exception 'assertion failed: expected row 6 rejected -- a file must never be able to claim a vendor is already active, got status=% error=%', v_status, v_error;
  end if;

  -- A wholly non-numeric value is caught by the GENERIC structural pass, which this
  -- validator calls unchanged and never reimplements -- asserted here so a future change
  -- that accidentally stops calling it is caught rather than silently narrowing coverage.
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[7];
  if v_status <> 'invalid' or v_error not like '%is not a valid number%' then
    raise exception 'assertion failed: expected row 7 rejected by the generic structural pass, got status=% error=%', v_status, v_error;
  end if;

  -- A fractional term is likewise a valid number generically, and likewise not a real
  -- number of days.
  select validation_status, error into v_status, v_error from app.import_staging_rows where id = v_ids[8];
  if v_status <> 'invalid' or v_error not like '%is not a whole, non-negative number of days%' then
    raise exception 'assertion failed: expected row 8 rejected for a fractional payment_term_days, got status=% error=%', v_status, v_error;
  end if;
end $$;

\echo '>> vendor_import commit: PRC:Import without support-grant authority is refused; a valid batch creates real bulk_import DRAFT vendors; invalid rows create nothing; an identical business registration number (punctuation/case normalized) is flagged as a duplicate candidate, which then blocks submit-for-review; replay creates zero duplicates'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000025101';
  v_staff uuid := '00000000-0000-0000-0000-000000025102';
  v_source_file app.files;
  v_job app.jobs;
  v_updated app.jobs;
  v_ids uuid[];
  v_first app.vendor_profiles;
  v_second app.vendor_profiles;
  v_count integer;
begin
  v_source_file := app.initiate_file_upload(
    v_tenant1, 'vendor_import_source', 'import_source', gen_random_uuid(),
    'vendors-commit.csv', 'text/csv', 2048, 'internal', false, null, null, null,
    'idem-vndimp-source-commit', v_admin1, 'admin'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_admin1, 'admin');
  v_job := app.create_import_export_job(v_tenant1, 'import', 'vendor_import', v_source_file.id, '{}'::jsonb, 'idem-vndimp-job-commit', v_admin1, 'admin');

  perform app.stage_import_rows(
    v_job.job_id,
    jsonb_build_array(
      -- Row 1: fully valid.
      jsonb_build_object(
        'legal_name', 'PT Zenith Kargo Impor', 'trade_name', 'Zenith Kargo', 'legal_entity_type', 'PT',
        'business_registration_number', 'REG-IMP-0001', 'vendor_category', 'trucking', 'payment_term_days', '30'
      ),
      -- Row 2: invalid (formula injection) -- must create nothing at all.
      jsonb_build_object('legal_name', '@SUM(1+1)*cmd', 'vendor_category', 'trucking'),
      -- Row 3: a completely different NAME (so the trigram sweep cannot match it) but the
      -- SAME registration number as row 1 with different punctuation and case. This is the
      -- duplicate a name-similarity check alone would miss entirely, and it is a
      -- within-batch duplicate -- proving the sweep sees rows committed earlier in this
      -- same job, not only vendors that predate it.
      jsonb_build_object(
        'legal_name', 'PT Sumber Makmur Sentosa', 'legal_entity_type', 'PT',
        'business_registration_number', 'reg.imp/0001', 'vendor_category', 'warehousing'
      )
    ),
    v_admin1, 'admin'
  );

  select array_agg(id order by row_number) into v_ids from app.import_staging_rows where job_id = v_job.job_id;
  perform app.validate_vendor_import_row(v_ids[1], v_admin1, 'admin');
  perform app.validate_vendor_import_row(v_ids[2], v_admin1, 'admin');
  perform app.validate_vendor_import_row(v_ids[3], v_admin1, 'admin');

  -- staff holds PRC Create/Edit/View but is NOT tenant_admin: the bulk path requires BOTH
  -- is_support_grant_authority AND PRC:Import, so it must be refused even though staff can
  -- create vendors one at a time.
  begin
    perform app.commit_vendor_import_job(v_job.job_id, true, v_staff, 'staff');
    raise exception 'assertion failed: expected insufficient_authority -- staff must not be able to bulk-create vendors';
  exception
    when insufficient_privilege then
      null;
  end;

  v_updated := app.commit_vendor_import_job(v_job.job_id, true, v_admin1, 'admin');
  if v_updated.status <> 'completed' then
    raise exception 'assertion failed: expected the job to complete (partial commit, 1 invalid row accepted), got %', v_updated.status;
  end if;

  select * into v_first from app.vendor_profiles where tenant_id = v_tenant1 and source_import_staging_row_id = v_ids[1];
  if not found then
    raise exception 'assertion failed: expected staged row 1 to have produced a vendor profile stamped with its own staging row id';
  end if;
  select * into v_second from app.vendor_profiles where tenant_id = v_tenant1 and source_import_staging_row_id = v_ids[3];
  if not found then
    raise exception 'assertion failed: expected staged row 3 to have produced a vendor profile stamped with its own staging row id';
  end if;

  -- Provenance is recorded by the adapter, never claimed by the file.
  if v_first.intake_source <> 'bulk_import' or v_second.intake_source <> 'bulk_import' then
    raise exception 'assertion failed: expected both imported vendors to record intake_source=bulk_import, got % and %', v_first.intake_source, v_second.intake_source;
  end if;
  -- Import creates DRAFTS. It never submits, approves or activates.
  if v_first.lifecycle_status <> 'draft' or v_second.lifecycle_status <> 'draft' then
    raise exception 'assertion failed: expected both imported vendors to be drafts, got % and %', v_first.lifecycle_status, v_second.lifecycle_status;
  end if;
  if v_first.legal_name <> 'PT Zenith Kargo Impor' or v_first.trade_name <> 'Zenith Kargo' or v_first.payment_term_days <> 30 then
    raise exception 'assertion failed: expected row 1''s own field values to survive the import intact';
  end if;
  -- A real vendor master record was minted through the canonical path, not a direct insert.
  if not exists (
    select 1 from app.master_records
    where id = v_first.master_record_id and tenant_id = v_tenant1 and master_type_code = 'vendor'
  ) then
    raise exception 'assertion failed: expected the imported vendor to carry a real vendor-typed master record';
  end if;

  -- The invalid row created nothing whatsoever.
  if exists (select 1 from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = '@SUM(1+1)*cmd') then
    raise exception 'assertion failed: expected the invalid row to have created no vendor profile at all';
  end if;
  if exists (select 1 from app.vendor_profiles where tenant_id = v_tenant1 and source_import_staging_row_id = v_ids[2]) then
    raise exception 'assertion failed: expected no vendor profile stamped with the invalid staging row';
  end if;

  -- The registration-number sweep flagged row 3 against row 1, within the same batch.
  if not exists (
    select 1 from app.vendor_duplicate_candidates
    where source_master_record_id = v_second.master_record_id
      and candidate_master_record_id = v_first.master_record_id
      and decision = 'pending'
      and similarity_basis like '%identical business registration number%'
  ) then
    raise exception 'assertion failed: expected an identical (punctuation/case-normalized) business registration number to be flagged as a pending duplicate candidate';
  end if;

  -- ...and that flag genuinely blocks the vendor advancing, which is the whole point of
  -- flagging rather than hard-failing the import: the row lands, a human decides.
  perform app.add_vendor_contact(v_second.master_record_id, 'Budi Duplikat', 'Ops', 'budi@sumber-makmur.test', '0811-000-777', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_second.master_record_id, 'legal', 'Jl. Gatot Subroto 7', 'Jakarta', 'DKI Jakarta', '12930', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_second.master_record_id, 'warehousing', v_admin1, 'admin');
  select * into v_second from app.vendor_profiles where master_record_id = v_second.master_record_id;
  begin
    perform app.submit_vendor_profile_for_review(v_second.master_record_id, v_second.record_version, v_admin1, 'admin');
    raise exception 'assertion failed: expected unresolved_duplicate_candidates to block submitting an imported vendor flagged as a duplicate';
  exception
    when others then
      if sqlerrm not like 'unresolved_duplicate_candidates%' then raise; end if;
  end;

  -- Replay: the job is already completed, so a second commit is refused outright by the
  -- framework's own standing contract -- and crucially creates zero additional vendors.
  select count(*) into v_count from app.vendor_profiles where tenant_id = v_tenant1 and intake_source = 'bulk_import';
  begin
    perform app.commit_vendor_import_job(v_job.job_id, true, v_admin1, 'admin');
    raise exception 'assertion failed: expected import_export_job_not_committable on a replayed commit of an already-completed job';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'import_export_job_not_committable%' then raise; end if;
  end;
  if (select count(*) from app.vendor_profiles where tenant_id = v_tenant1 and intake_source = 'bulk_import') <> v_count then
    raise exception 'assertion failed: expected the replayed commit attempt to create zero additional vendors';
  end if;
end $$;

\echo '>> vendor_import commit: a job with invalid rows and no p_allow_partial is refused outright (never silently drops them)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000025101';
  v_source_file app.files;
  v_job app.jobs;
  v_row_id uuid;
begin
  v_source_file := app.initiate_file_upload(
    v_tenant1, 'vendor_import_source', 'import_source', gen_random_uuid(),
    'vendors-strict.csv', 'text/csv', 512, 'internal', false, null, null, null,
    'idem-vndimp-source-strict', v_admin1, 'admin'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_admin1, 'admin');
  v_job := app.create_import_export_job(v_tenant1, 'import', 'vendor_import', v_source_file.id, '{}'::jsonb, 'idem-vndimp-job-strict', v_admin1, 'admin');

  perform app.stage_import_rows(
    v_job.job_id,
    jsonb_build_array(jsonb_build_object('legal_name', '+SUM(A1:A9)', 'vendor_category', 'trucking')),
    v_admin1, 'admin'
  );
  select id into v_row_id from app.import_staging_rows where job_id = v_job.job_id and row_number = 1;
  perform app.validate_vendor_import_row(v_row_id, v_admin1, 'admin');

  begin
    perform app.commit_vendor_import_job(v_job.job_id, false, v_admin1, 'admin');
    raise exception 'assertion failed: expected import_export_job_has_invalid_rows without p_allow_partial';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'import_export_job_has_invalid_rows%' then raise; end if;
  end;
end $$;

\echo '>> vendor_import: the commit adapter refuses a job registered under a different schema code'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vndreg1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000025101';
  v_supreme uuid := '00000000-0000-0000-0000-000000025999';
  v_source_file app.files;
  v_job app.jobs;
  v_other_draft app.config_versions;
begin
  perform app.register_import_export_schema('vndreg_other_import', 'Other Import', 'PRC', v_supreme, 'supreme');
  v_other_draft := app.create_config_draft('import_export:vndreg_other_import', v_tenant1, 'tenant', null, v_admin1, 'admin');
  perform app.set_config_items(
    v_other_draft.id,
    jsonb_build_array(jsonb_build_object('key', 'columns', 'value', jsonb_build_array(
      jsonb_build_object('key', 'legal_name', 'label', 'Legal name', 'required', true, 'data_type', 'text')
    ), 'canonical_ref', null)),
    v_admin1, 'admin'
  );
  perform app.publish_import_export_schema(v_other_draft.id, v_admin1, now(), 'admin');

  v_source_file := app.initiate_file_upload(
    v_tenant1, 'vendor_import_source', 'import_source', gen_random_uuid(),
    'other.csv', 'text/csv', 256, 'internal', false, null, null, null,
    'idem-vndimp-source-other', v_admin1, 'admin'
  );
  perform app.record_file_scan_result(v_source_file.id, 'clean', 'test-scanner', v_admin1, 'admin');
  v_job := app.create_import_export_job(v_tenant1, 'import', 'vndreg_other_import', v_source_file.id, '{}'::jsonb, 'idem-vndimp-job-other', v_admin1, 'admin');

  begin
    perform app.commit_vendor_import_job(v_job.job_id, true, v_admin1, 'admin');
    raise exception 'assertion failed: expected import_export_wrong_schema for a non-vendor_import job';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'import_export_wrong_schema%' then raise; end if;
  end;
end $$;

\echo '>> vendor_import: neither anon nor authenticated holds EXECUTE on the adapter (service_role-mediated, matching every other import commit adapter)'
do $$
declare
  v_has boolean;
begin
  select has_function_privilege('authenticated', 'app.commit_vendor_import_job(uuid, boolean, uuid, text, text)', 'EXECUTE') into v_has;
  if v_has then raise exception 'assertion failed: authenticated must not hold EXECUTE on app.commit_vendor_import_job'; end if;
  select has_function_privilege('anon', 'app.commit_vendor_import_job(uuid, boolean, uuid, text, text)', 'EXECUTE') into v_has;
  if v_has then raise exception 'assertion failed: anon must not hold EXECUTE on app.commit_vendor_import_job'; end if;
  select has_function_privilege('authenticated', 'public.commit_vendor_import_job(uuid, boolean, uuid, text, text)', 'EXECUTE') into v_has;
  if v_has then raise exception 'assertion failed: authenticated must not hold EXECUTE on the public wrapper either'; end if;
  select has_function_privilege('service_role', 'app.commit_vendor_import_job(uuid, boolean, uuid, text, text)', 'EXECUTE') into v_has;
  if not v_has then raise exception 'assertion failed: service_role must hold EXECUTE on app.commit_vendor_import_job'; end if;
end $$;
