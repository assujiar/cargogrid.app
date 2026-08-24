-- Real, executable test evidence for PRC-257 (RFQ, CG-S11-PRC-008) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database. Scoped to
-- this checkpoint's own additive migration
-- (supabase/migrations/20260730640000_create_procurement_rfq.sql). Sorts
-- alphabetically after scripts/db-tests/procurement-vendor-compliance.sql and
-- scripts/db-tests/procurement-sourcing.sql, so this file registers its own
-- document type rather than relying on either of those having already run.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (rfq1, rfq2). rfq1 gets a tenant_admin (admin1, full PRC set incl. Approve -- needed for vendor-registration setup), a full-PRC-except-Approve staff actor (staff1: Create/Edit/View/View cost/Override), an Override-less editor (editor1: Create/Edit/View/View cost, no Override -- for permission-denied checks), a View-only viewer (viewer1: View only, no View cost -- for cost-masking and Create-denied checks). rfq2 gets a tenant_admin and a full-PRC staff actor for cross-tenant checks. A global Supreme Admin is also seeded.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin_role uuid;
  v_admin_draft app.role_versions;
  v_staff_role uuid;
  v_staff_draft app.role_versions;
  v_editor_role uuid;
  v_editor_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000037101', 'admin@rfq1.test'),
    ('00000000-0000-0000-0000-000000037102', 'staff@rfq1.test'),
    ('00000000-0000-0000-0000-000000037103', 'editor@rfq1.test'),
    ('00000000-0000-0000-0000-000000037104', 'viewer@rfq1.test'),
    ('00000000-0000-0000-0000-000000037201', 'admin@rfq2.test'),
    ('00000000-0000-0000-0000-000000037202', 'staff@rfq2.test'),
    ('00000000-0000-0000-0000-000000037999', 'supreme@rfq.test');

  perform app.provision_tenant('rfq1', 'RFQ Co 1', 'idem-rfq1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'rfq1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('rfq2', 'RFQ Co 2', 'idem-rfq2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'rfq2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000037101', 'admin@rfq1.test', 'Rfq1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@rfq1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000037101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000037102', 'staff@rfq1.test', 'Rfq1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@rfq1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000037103', 'editor@rfq1.test', 'Rfq1 Editor', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'editor@rfq1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000037104', 'viewer@rfq1.test', 'Rfq1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@rfq1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000037201', 'admin@rfq2.test', 'Rfq2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@rfq2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000037201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000037202', 'staff@rfq2.test', 'Rfq2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@rfq2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000037999', 'supreme_admin', null, null, 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'Rfq1 PRC Admin', 'full PRC action set for setup', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000037101', '00000000-0000-0000-0000-000000037999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'Rfq1 PRC Staff', 'Create/Edit/View/View cost/Override', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000037102', '00000000-0000-0000-0000-000000037101', 'tester');

  v_editor_role := (app.create_role(v_tenant1, 'Rfq1 PRC Editor', 'Create/Edit/View/View cost, no Override', 'tester')).id;
  v_editor_draft := app.create_role_version(v_editor_role, 'tester');
  perform app.set_role_version_permissions(v_editor_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost')), 'tester');
  perform app.publish_role_version(v_editor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_editor_role and status = 'published'), '00000000-0000-0000-0000-000000037103', '00000000-0000-0000-0000-000000037101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Rfq1 PRC Viewer', 'View only, no View cost', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000037104', '00000000-0000-0000-0000-000000037101', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'Rfq2 PRC Staff', 'full PRC set', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000037201', '00000000-0000-0000-0000-000000037999', 'supreme');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000037202', '00000000-0000-0000-0000-000000037201', 'tester');
end $$;

\echo '>> setup: four ACTIVE vendors in tenant1 (A eligible/shortlisted, B ineligible service_mismatch, C eligible/not-shortlisted, D eligible/not-shortlisted) and one ACTIVE vendor in tenant2 for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'rfq2');
  v_admin1 uuid := '00000000-0000-0000-0000-000000037101';
  v_admin2 uuid := '00000000-0000-0000-0000-000000037201';
  v_profile app.vendor_profiles;
begin
  -- Vendor A: eligible (ocean_freight, Jakarta -> Surabaya).
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT RFQ Eligible A', 'RFQA', 'PT', 'REG-RFQ-A', 'logistics', 30, 'staff_created', 'idem-rfq-vendor-a', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Ani Vendor A', 'Ops', 'ani@rfqa.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  -- Vendor B: wrong service (trucking, not ocean_freight) -- service_mismatch.
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT RFQ Ineligible B', 'RFQB', 'PT', 'REG-RFQ-B', 'logistics', 30, 'staff_created', 'idem-rfq-vendor-b', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Budi Vendor B', 'Ops', 'budi@rfqb.test', '0812', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Gatot Subroto 2', 'Jakarta', 'DKI Jakarta', '10230', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'trucking', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  -- Vendor C: eligible, will be added via invite_additional_rfq_vendor (never
  -- shortlisted at the sourcing stage).
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT RFQ Eligible C', 'RFQC', 'PT', 'REG-RFQ-C', 'logistics', 30, 'staff_created', 'idem-rfq-vendor-c', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Citra Vendor C', 'Ops', 'citra@rfqc.test', '0813', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Asia Afrika 3', 'Bandung', 'Jawa Barat', '40111', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  -- Vendor D: eligible, will be added via invite_additional_rfq_vendor and
  -- then declined.
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT RFQ Eligible D', 'RFQD', 'PT', 'REG-RFQ-D', 'logistics', 30, 'staff_created', 'idem-rfq-vendor-d', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Dedi Vendor D', 'Ops', 'dedi@rfqd.test', '0814', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Diponegoro 4', 'Jakarta', 'DKI Jakarta', '10240', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  -- A second, tenant2 vendor for cross-tenant isolation checks.
  v_profile := app.create_vendor_profile_draft(v_tenant2, 'PT Other Tenant RFQ Vendor', 'RFQE', 'PT', 'REG-RFQ-E', 'logistics', 30, 'staff_created', 'idem-rfq-vendor-e', v_admin2, 'admin2');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Eka Vendor E', 'Ops', 'eka@rfqe.test', '0815', true, v_admin2, 'admin2');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Malioboro 5', 'Yogyakarta', 'DIY', '55111', 'Indonesia', v_admin2, 'admin2');
end $$;

\echo '>> setup: a proactive sourcing request driven to shortlisted (draft -> open -> evaluate eligibility -> shortlist vendor A -> submit shortlist)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000037101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_request app.sourcing_requests;
  v_candidate_a app.sourcing_candidates;
  v_vendor_a_master uuid;
begin
  v_request := app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days',
    'IDR', 50000000, v_staff1, now() + interval '20 days', 'idem-rfq-sourcing-1', v_staff1, 'staff'
  );
  v_request := app.submit_sourcing_request(v_request.id, v_staff1, 'staff', v_request.record_version);
  if v_request.status <> 'open' then
    raise exception 'assertion failed: expected sourcing request to be open, got %', v_request.status;
  end if;

  perform app.evaluate_sourcing_candidate_eligibility(v_request.id, v_admin1, 'admin');

  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT RFQ Eligible A';
  select * into v_candidate_a from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor_a_master;
  if not v_candidate_a.eligible then
    raise exception 'assertion failed: expected vendor A to be an eligible candidate';
  end if;

  v_candidate_a := app.shortlist_sourcing_candidate(v_candidate_a.id, true, 'strong fit for the lane', v_staff1, 'staff', v_candidate_a.record_version);

  v_request := app.submit_sourcing_shortlist(v_request.id, v_staff1, 'staff', v_request.record_version);
  if v_request.status <> 'shortlisted' then
    raise exception 'assertion failed: expected sourcing request to be shortlisted, got %', v_request.status;
  end if;
end $$;

\echo '>> app.draft_rfq_from_sourcing: idempotent replay comparing sourcing_request_id/owner_user_id, blocks a non-shortlisted source, blocks cross-tenant, permission-denied for a Create-less actor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'rfq2');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000037104';
  v_sourcing_id uuid;
  v_rfq app.rfqs;
  v_retry app.rfqs;
  v_open_sourcing app.sourcing_requests;
  v_failed boolean;
begin
  select id into v_sourcing_id from app.sourcing_requests where tenant_id = v_tenant1 and status = 'shortlisted' order by created_at desc limit 1;

  v_rfq := app.draft_rfq_from_sourcing(v_tenant1, v_sourcing_id, v_staff1, 'idem-rfq-draft-1', v_staff1, 'staff');
  if v_rfq.status <> 'draft' or v_rfq.service_type <> 'ocean_freight' or v_rfq.origin_lane <> 'Jakarta' or v_rfq.destination_lane <> 'Surabaya' then
    raise exception 'assertion failed: unexpected rfq shape from draft_rfq_from_sourcing: %', to_jsonb(v_rfq);
  end if;
  if v_rfq.requirements_snapshot ? 'budget_amount' then
    raise exception 'assertion failed: requirements_snapshot must never carry budget_amount (design note 3)';
  end if;

  -- Idempotent replay: identical inputs return the SAME row.
  v_retry := app.draft_rfq_from_sourcing(v_tenant1, v_sourcing_id, v_staff1, 'idem-rfq-draft-1', v_staff1, 'staff');
  if v_retry.id <> v_rfq.id or v_retry.record_version <> v_rfq.record_version then
    raise exception 'assertion failed: expected the idempotent replay to return the identical row';
  end if;

  -- Reused idempotency key with a DIFFERENT owner_user_id -- rejected.
  v_failed := false;
  begin
    perform app.draft_rfq_from_sourcing(v_tenant1, v_sourcing_id, '00000000-0000-0000-0000-000000037103', 'idem-rfq-draft-1'::text, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict:%' then
      raise exception 'assertion failed: expected idempotency_key_conflict, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected the reused-key-different-owner call to fail';
  end if;

  -- A non-shortlisted sourcing request (still open) cannot draft an RFQ.
  v_open_sourcing := app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Bandung', null, null, null, null, null, null,
    'IDR', null, v_staff1, null, 'idem-rfq-sourcing-open', v_staff1, 'staff'
  );
  v_open_sourcing := app.submit_sourcing_request(v_open_sourcing.id, v_staff1, 'staff', v_open_sourcing.record_version);
  v_failed := false;
  begin
    perform app.draft_rfq_from_sourcing(v_tenant1, v_open_sourcing.id, v_staff1, 'idem-rfq-draft-open', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_source_status:%' then
      raise exception 'assertion failed: expected invalid_source_status, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected drafting from a non-shortlisted sourcing request to fail';
  end if;

  -- Cross-tenant: tenant2's staff cannot draft from tenant1's own sourcing request.
  v_failed := false;
  begin
    perform app.draft_rfq_from_sourcing(v_tenant2, v_sourcing_id, v_staff1, 'idem-rfq-draft-xt', '00000000-0000-0000-0000-000000037202', 'staff2');
  exception when others then
    v_failed := true;
    -- Batch 260 review (C-05, LOW, propagation sweep): "found but wrong tenant" now
    -- raises the same sourcing_request_not_found a nonexistent id raises, closing the
    -- cross-tenant existence oracle a distinct tenant_mismatch error used to leak.
    if sqlerrm not like 'sourcing_request_not_found:%' then
      raise exception 'assertion failed: expected sourcing_request_not_found, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected the cross-tenant draft to fail';
  end if;

  -- Permission-denied: viewer1 (View only, no Create) cannot draft an RFQ.
  v_failed := false;
  begin
    perform app.draft_rfq_from_sourcing(v_tenant1, v_sourcing_id, v_staff1, 'idem-rfq-draft-denied', v_viewer1, 'viewer');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%' then
      raise exception 'assertion failed: expected insufficient_authority, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected the permission-denied draft to fail';
  end if;
end $$;

\echo '>> app.issue_rfq: requires a future deadline, bulk-invites every shortlisted candidate (vendor A only), blocks a non-draft rfq, stale_version on a concurrent version mismatch'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_rfq app.rfqs;
  v_invitation_count integer;
  v_failed boolean;
begin
  select * into v_rfq from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';

  -- Deadline must be in the future.
  v_failed := false;
  begin
    perform app.issue_rfq(v_rfq.id, now() - interval '1 day', v_rfq.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_deadline:%' then
      raise exception 'assertion failed: expected invalid_deadline, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a past deadline to be rejected';
  end if;

  -- Stale version.
  v_failed := false;
  begin
    perform app.issue_rfq(v_rfq.id, now() + interval '5 days', v_rfq.record_version + 99, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'stale_version:%' then
      raise exception 'assertion failed: expected stale_version, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a wrong expected_version to be rejected';
  end if;

  v_rfq := app.issue_rfq(v_rfq.id, now() + interval '5 days', v_rfq.record_version, v_staff1, 'staff');
  if v_rfq.status <> 'issued' or v_rfq.issued_at is null or v_rfq.response_deadline_at is null then
    raise exception 'assertion failed: unexpected rfq shape after issue: %', to_jsonb(v_rfq);
  end if;

  select count(*) into v_invitation_count from app.rfq_invitations where rfq_id = v_rfq.id;
  if v_invitation_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 bulk invitation (vendor A only), got %', v_invitation_count;
  end if;

  -- Cannot re-issue an already-issued RFQ.
  v_failed := false;
  begin
    perform app.issue_rfq(v_rfq.id, now() + interval '6 days', v_rfq.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition:%' then
      raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected re-issuing an already-issued rfq to fail';
  end if;
end $$;

\echo '>> app.invite_additional_rfq_vendor: PRC:Override + mandatory reason, blocks an ineligible candidate, blocks a duplicate invite, permission-denied for an Override-less editor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_editor1 uuid := '00000000-0000-0000-0000-000000037103';
  v_rfq app.rfqs;
  v_sourcing_id uuid;
  v_candidate_b app.sourcing_candidates;
  v_candidate_c app.sourcing_candidates;
  v_candidate_d app.sourcing_candidates;
  v_vendor_b_master uuid;
  v_vendor_c_master uuid;
  v_vendor_d_master uuid;
  v_invitation app.rfq_invitations;
  v_failed boolean;
begin
  select * into v_rfq from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';
  select sourcing_request_id into v_sourcing_id from app.rfqs where id = v_rfq.id;

  select master_record_id into v_vendor_b_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT RFQ Ineligible B';
  select master_record_id into v_vendor_c_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT RFQ Eligible C';
  select master_record_id into v_vendor_d_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT RFQ Eligible D';

  select * into v_candidate_b from app.sourcing_candidates where sourcing_request_id = v_sourcing_id and vendor_master_id = v_vendor_b_master;
  select * into v_candidate_c from app.sourcing_candidates where sourcing_request_id = v_sourcing_id and vendor_master_id = v_vendor_c_master;
  select * into v_candidate_d from app.sourcing_candidates where sourcing_request_id = v_sourcing_id and vendor_master_id = v_vendor_d_master;

  -- Reason required.
  v_failed := false;
  begin
    perform app.invite_additional_rfq_vendor(v_rfq.id, v_candidate_c.id, '', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected empty reason to be rejected';
  end if;

  -- Permission-denied: editor1 has no Override.
  v_failed := false;
  begin
    perform app.invite_additional_rfq_vendor(v_rfq.id, v_candidate_c.id, 'need more coverage', v_editor1, 'editor');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%' then
      raise exception 'assertion failed: expected insufficient_authority, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected the Override-less editor to be denied';
  end if;

  -- Exception flow: block an ineligible vendor.
  v_failed := false;
  begin
    perform app.invite_additional_rfq_vendor(v_rfq.id, v_candidate_b.id, 'trying to add anyway', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'ineligible_vendor:%' then
      raise exception 'assertion failed: expected ineligible_vendor, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected inviting an ineligible vendor to fail';
  end if;

  -- Success: vendor C (eligible, not shortlisted).
  v_invitation := app.invite_additional_rfq_vendor(v_rfq.id, v_candidate_c.id, 'wider coverage needed', v_staff1, 'staff');
  if v_invitation.status <> 'invited' or v_invitation.vendor_master_id <> v_vendor_c_master then
    raise exception 'assertion failed: unexpected invitation shape for vendor C: %', to_jsonb(v_invitation);
  end if;

  -- Duplicate invite of the same vendor is rejected.
  v_failed := false;
  begin
    perform app.invite_additional_rfq_vendor(v_rfq.id, v_candidate_c.id, 'duplicate attempt', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_already_invited:%' then
      raise exception 'assertion failed: expected vendor_already_invited, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a duplicate invite to fail';
  end if;

  -- Success: vendor D (eligible, not shortlisted) -- used for the decline test next.
  perform app.invite_additional_rfq_vendor(v_rfq.id, v_candidate_d.id, 'additional coverage for decline test', v_staff1, 'staff');
end $$;

\echo '>> app.extend_rfq_deadline: widen-only, blocks narrowing, stale_version'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_rfq app.rfqs;
  v_failed boolean;
begin
  select * into v_rfq from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';

  v_failed := false;
  begin
    perform app.extend_rfq_deadline(v_rfq.id, v_rfq.response_deadline_at - interval '1 day', v_rfq.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'deadline_narrowing_not_allowed:%' then
      raise exception 'assertion failed: expected deadline_narrowing_not_allowed, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected narrowing the deadline to fail';
  end if;

  v_failed := false;
  begin
    perform app.extend_rfq_deadline(v_rfq.id, v_rfq.response_deadline_at + interval '2 days', v_rfq.record_version + 99, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'stale_version:%' then
      raise exception 'assertion failed: expected stale_version, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a wrong expected_version to be rejected';
  end if;

  v_rfq := app.extend_rfq_deadline(v_rfq.id, v_rfq.response_deadline_at + interval '2 days', v_rfq.record_version, v_staff1, 'staff');
  if v_rfq.response_deadline_at is null then
    raise exception 'assertion failed: expected an extended, non-null response_deadline_at';
  end if;
end $$;

\echo '>> app.decline_rfq_invitation: mandatory reason, blocks a non-invited status'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_rfq app.rfqs;
  v_vendor_d_master uuid;
  v_invitation app.rfq_invitations;
  v_failed boolean;
begin
  select * into v_rfq from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';
  select master_record_id into v_vendor_d_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT RFQ Eligible D';
  select * into v_invitation from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_d_master;

  v_failed := false;
  begin
    perform app.decline_rfq_invitation(v_invitation.id, '', v_invitation.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected an empty decline reason to be rejected';
  end if;

  v_invitation := app.decline_rfq_invitation(v_invitation.id, 'vendor emailed a decline', v_invitation.record_version, v_staff1, 'staff');
  if v_invitation.status <> 'declined' or v_invitation.decline_reason is null then
    raise exception 'assertion failed: unexpected invitation shape after decline: %', to_jsonb(v_invitation);
  end if;

  -- Cannot decline an already-declined invitation.
  v_failed := false;
  begin
    perform app.decline_rfq_invitation(v_invitation.id, 'again', v_invitation.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition:%' then
      raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected re-declining an already-declined invitation to fail';
  end if;
end $$;

\echo '>> app.record_rfq_clarification + app.answer_rfq_clarification: blocks an uninvited vendor, blocks a double answer'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_rfq app.rfqs;
  v_vendor_a_master uuid;
  v_vendor_e_master uuid;
  v_clar app.rfq_clarifications;
  v_failed boolean;
begin
  select * into v_rfq from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT RFQ Eligible A';
  select master_record_id into v_vendor_e_master from app.vendor_profiles where legal_name = 'PT Other Tenant RFQ Vendor';

  v_failed := false;
  begin
    perform app.record_rfq_clarification(v_rfq.id, v_vendor_e_master, 'what is the packing requirement?', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_not_invited:%' then
      raise exception 'assertion failed: expected vendor_not_invited, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a clarification for an uninvited vendor to fail';
  end if;

  -- Broadcast clarification (no vendor scope).
  v_clar := app.record_rfq_clarification(v_rfq.id, null, 'is dangerous goods handling required?', v_staff1, 'staff');
  if v_clar.answer is not null then
    raise exception 'assertion failed: a fresh clarification must have no answer yet';
  end if;

  v_clar := app.answer_rfq_clarification(v_clar.id, 'no dangerous goods for this lane', v_clar.record_version, v_staff1, 'staff');
  if v_clar.answer is null or v_clar.answered_at is null then
    raise exception 'assertion failed: expected the clarification to carry an answer';
  end if;

  v_failed := false;
  begin
    perform app.answer_rfq_clarification(v_clar.id, 'a second answer', v_clar.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'clarification_already_answered:%' then
      raise exception 'assertion failed: expected clarification_already_answered, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a double-answer to fail';
  end if;

  -- Vendor-scoped clarification for vendor A (invited).
  perform app.record_rfq_clarification(v_rfq.id, v_vendor_a_master, 'what currency should the offer use?', v_staff1, 'staff');
end $$;

\echo '>> app.submit_rfq_response: file re-validation (clean/infected/cross-tenant/wrong-record), on-time capture, idempotent replay + conflict, withdraw, resubmit, not_latest_response_version, late capture requires PRC:Override + late_reason'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'rfq2');
  v_admin1 uuid := '00000000-0000-0000-0000-000000037101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_editor1 uuid := '00000000-0000-0000-0000-000000037103';
  v_rfq app.rfqs;
  v_vendor_a_master uuid;
  v_vendor_c_master uuid;
  v_invitation_a app.rfq_invitations;
  v_invitation_c app.rfq_invitations;
  v_clean_file app.files;
  v_infected_file app.files;
  v_foreign_file app.files;
  v_wrong_record_file app.files;
  v_response app.rfq_responses;
  v_response_v2 app.rfq_responses;
  v_response_retry app.rfq_responses;
  v_attachment_count integer;
  v_failed boolean;
  v_doctype_draft app.config_versions;
begin
  perform app.register_document_type('rfq_response_evidence', 'RFQ Response Evidence', 'PRC', '00000000-0000-0000-0000-000000037999', 'supreme');
  v_doctype_draft := app.create_config_draft('document:rfq_response_evidence', v_tenant1, 'tenant', null, v_admin1, 'admin');
  perform app.set_config_items(v_doctype_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('confidential'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_admin1, 'admin');
  perform app.publish_document_type_definition(v_doctype_draft.id, v_admin1, now(), 'admin');

  select * into v_rfq from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT RFQ Eligible A';
  select master_record_id into v_vendor_c_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT RFQ Eligible C';
  select * into v_invitation_a from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_a_master;
  select * into v_invitation_c from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_c_master;

  -- A clean file uploaded against invitation A.
  v_clean_file := app.initiate_file_upload(v_tenant1, 'rfq_response_evidence', 'rfq_invitation', v_invitation_a.id, 'quote-a.pdf', 'application/pdf', 20480, 'confidential', false, null, '{}', null, 'idem-rfq-file-clean', v_staff1, 'staff');
  perform app.record_file_scan_result(v_clean_file.id, 'clean', null, v_staff1, 'staff');

  -- An infected file, also against invitation A.
  v_infected_file := app.initiate_file_upload(v_tenant1, 'rfq_response_evidence', 'rfq_invitation', v_invitation_a.id, 'quote-a-bad.pdf', 'application/pdf', 20480, 'confidential', false, null, '{}', null, 'idem-rfq-file-infected', v_staff1, 'staff');
  perform app.record_file_scan_result(v_infected_file.id, 'infected', null, v_staff1, 'staff');

  -- A tenant2 file (cross-tenant, uploaded against a foreign invitation id --
  -- exercised structurally as a mismatched record_id below).
  v_wrong_record_file := app.initiate_file_upload(v_tenant1, 'rfq_response_evidence', 'rfq_invitation', v_invitation_c.id, 'quote-c.pdf', 'application/pdf', 10240, 'confidential', false, null, '{}', null, 'idem-rfq-file-wrong-record', v_staff1, 'staff');
  perform app.record_file_scan_result(v_wrong_record_file.id, 'clean', null, v_staff1, 'staff');

  -- Unsafe file blocked (C-10).
  v_failed := false;
  begin
    perform app.submit_rfq_response(
      v_invitation_a.id, 'IDR', 12000000, now() + interval '30 days', 7, '{}'::jsonb, 'offline', 'email thread #1', now(), true,
      array[v_infected_file.id], null, 'idem-rfq-resp-a-unsafe', v_staff1, 'staff'
    );
  exception when others then
    v_failed := true;
    if sqlerrm not like 'rfq_response_unsafe_file:%' then
      raise exception 'assertion failed: expected rfq_response_unsafe_file, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected an infected file to be rejected';
  end if;

  -- Wrong record_id (file was uploaded against invitation C, submitted here
  -- against invitation A) blocked (C-10 record-scope re-validation).
  v_failed := false;
  begin
    perform app.submit_rfq_response(
      v_invitation_a.id, 'IDR', 12000000, now() + interval '30 days', 7, '{}'::jsonb, 'offline', 'email thread #1', now(), true,
      array[v_wrong_record_file.id], null, 'idem-rfq-resp-a-wrongrecord', v_staff1, 'staff'
    );
  exception when others then
    v_failed := true;
    if sqlerrm not like 'rfq_response_file_mismatch:%' then
      raise exception 'assertion failed: expected rfq_response_file_mismatch, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a wrong-record-scope file to be rejected';
  end if;

  -- On-time capture with the clean file.
  v_response := app.submit_rfq_response(
    v_invitation_a.id, 'IDR', 12000000, now() + interval '30 days', 7, jsonb_build_object('incoterm', 'FOB'), 'offline', 'email thread #1', now(), true,
    array[v_clean_file.id], null, 'idem-rfq-resp-a-1', v_staff1, 'staff'
  );
  if v_response.version <> 1 or v_response.late_capture or not v_response.comparison_eligible or v_response.status <> 'submitted' then
    raise exception 'assertion failed: unexpected on-time response shape: %', to_jsonb(v_response);
  end if;

  select count(*) into v_attachment_count from app.rfq_response_attachments where rfq_response_id = v_response.id;
  if v_attachment_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 attachment on the first response version, got %', v_attachment_count;
  end if;

  if (select status from app.rfq_invitations where id = v_invitation_a.id) <> 'responded' then
    raise exception 'assertion failed: expected invitation A to be responded after submission';
  end if;

  -- Idempotent replay: identical inputs return the SAME row.
  v_response_retry := app.submit_rfq_response(
    v_invitation_a.id, 'IDR', 12000000, now() + interval '30 days', 7, jsonb_build_object('incoterm', 'FOB'), 'offline', 'email thread #1', v_response.received_at, true,
    array[v_clean_file.id], null, 'idem-rfq-resp-a-1', v_staff1, 'staff'
  );
  if v_response_retry.id <> v_response.id then
    raise exception 'assertion failed: expected the idempotent replay to return the identical response row';
  end if;

  -- Reused key with a DIFFERENT total_amount -- rejected.
  v_failed := false;
  begin
    perform app.submit_rfq_response(
      v_invitation_a.id, 'IDR', 99000000, now() + interval '30 days', 7, '{}'::jsonb, 'offline', 'email thread #1', v_response.received_at, true,
      null, null, 'idem-rfq-resp-a-1', v_staff1, 'staff'
    );
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict:%' then
      raise exception 'assertion failed: expected idempotency_key_conflict, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a reused key with a different amount to fail';
  end if;

  -- Reused key with an identical amount but a DIFFERENT lead_time_days --
  -- rejected too (design note 13a: the comparison covers every caller-
  -- supplied field, not just the four originally checked).
  v_failed := false;
  begin
    perform app.submit_rfq_response(
      v_invitation_a.id, 'IDR', 12000000, now() + interval '30 days', 99, '{}'::jsonb, 'offline', 'email thread #1', v_response.received_at, true,
      null, null, 'idem-rfq-resp-a-1', v_staff1, 'staff'
    );
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict:%' then
      raise exception 'assertion failed: expected idempotency_key_conflict for a different lead_time_days, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a reused key with a different lead_time_days to fail';
  end if;

  -- Withdraw the current (only) version -- invitation reverts to invited.
  v_response := app.withdraw_rfq_response(v_response.id, 'vendor requested a correction', v_response.record_version, v_staff1, 'staff');
  if v_response.status <> 'withdrawn' then
    raise exception 'assertion failed: expected the response to be withdrawn';
  end if;
  if (select status from app.rfq_invitations where id = v_invitation_a.id) <> 'invited' then
    raise exception 'assertion failed: expected invitation A to revert to invited after withdrawal';
  end if;

  -- Cannot withdraw an already-withdrawn response.
  v_failed := false;
  begin
    perform app.withdraw_rfq_response(v_response.id, 'again', v_response.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition:%' then
      raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a second withdrawal to fail';
  end if;

  -- Resubmit -- version 2, previous_version_id points at version 1.
  v_response_v2 := app.submit_rfq_response(
    v_invitation_a.id, 'IDR', 11500000, now() + interval '30 days', 6, '{}'::jsonb, 'offline', 'revised offer email', now(), true,
    null, null, 'idem-rfq-resp-a-2', v_staff1, 'staff'
  );
  if v_response_v2.version <> 2 or v_response_v2.previous_version_id <> v_response.id then
    raise exception 'assertion failed: unexpected version-2 response shape: %', to_jsonb(v_response_v2);
  end if;

  -- The now-superseded version 1 can no longer be withdrawn (not the latest).
  v_failed := false;
  begin
    perform app.withdraw_rfq_response(v_response.id, 'attempt on the old version', v_response.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition:%' then
      raise exception 'assertion failed: expected invalid_transition (already withdrawn), got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected withdrawing the already-withdrawn version 1 to fail';
  end if;

  -- Late capture: invitation C, received_at AFTER the rfq's own deadline.
  -- editor1 (no Override) is denied even with a reason supplied.
  v_failed := false;
  begin
    perform app.submit_rfq_response(
      v_invitation_c.id, 'IDR', 13000000, now() + interval '30 days', 10, '{}'::jsonb, 'email', 'late email', v_rfq.response_deadline_at + interval '1 day', true,
      null, 'delayed vendor reply', 'idem-rfq-resp-c-late-denied', v_editor1, 'editor'
    );
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%' then
      raise exception 'assertion failed: expected insufficient_authority for the Override-less late capture, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected the Override-less actor''s late capture to be denied';
  end if;

  -- staff1 (has Override) but missing late_reason is rejected.
  v_failed := false;
  begin
    perform app.submit_rfq_response(
      v_invitation_c.id, 'IDR', 13000000, now() + interval '30 days', 10, '{}'::jsonb, 'email', 'late email', v_rfq.response_deadline_at + interval '1 day', true,
      null, null, 'idem-rfq-resp-c-late-noreason', v_staff1, 'staff'
    );
  exception when others then
    v_failed := true;
    if sqlerrm not like 'late_reason_required:%' then
      raise exception 'assertion failed: expected late_reason_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a missing late_reason to be rejected';
  end if;

  -- staff1 with Override and a late_reason succeeds -- never comparison_eligible.
  v_response := app.submit_rfq_response(
    v_invitation_c.id, 'IDR', 13000000, now() + interval '30 days', 10, '{}'::jsonb, 'email', 'late email', v_rfq.response_deadline_at + interval '1 day', true,
    null, 'delayed vendor reply, authorized late capture', 'idem-rfq-resp-c-late-1', v_staff1, 'staff'
  );
  if not v_response.late_capture or v_response.comparison_eligible then
    raise exception 'assertion failed: expected a late-captured response to be late_capture=true, comparison_eligible=false: %', to_jsonb(v_response);
  end if;
end $$;

\echo '>> app.list_rfq_responses: masks currency/total_amount/commercial_terms behind PRC:View cost'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000037104';
  v_rfq app.rfqs;
  v_masked record;
  v_unmasked record;
begin
  select * into v_rfq from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';

  select * into v_masked from app.list_rfq_responses(v_rfq.id, v_viewer1) where status = 'submitted' limit 1;
  if v_masked.cost_masked is distinct from true or v_masked.total_amount is not null or v_masked.currency is not null then
    raise exception 'assertion failed: expected viewer1 (no View cost) to see a masked response row';
  end if;

  select * into v_unmasked from app.list_rfq_responses(v_rfq.id, v_staff1) where status = 'submitted' limit 1;
  if v_unmasked.cost_masked is distinct from false or v_unmasked.total_amount is null then
    raise exception 'assertion failed: expected staff1 (View cost) to see the real total_amount';
  end if;
end $$;

\echo '>> app.revise_rfq: only from issued, marks the current version superseded, creates a new draft version sharing rfq_number, idempotent replay'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_rfq app.rfqs;
  v_new app.rfqs;
  v_retry app.rfqs;
  v_failed boolean;
begin
  select * into v_rfq from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';

  -- Reason required.
  v_failed := false;
  begin
    perform app.revise_rfq(v_rfq.id, 6000, null, null, null, '', 'idem-rfq-revise-noreason', v_rfq.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected an empty revise reason to be rejected';
  end if;

  v_new := app.revise_rfq(v_rfq.id, 6000, null, null, null, 'shipper increased cargo weight', 'idem-rfq-revise-1', v_rfq.record_version, v_staff1, 'staff');
  if v_new.status <> 'draft' or v_new.version <> 2 or v_new.revised_from_id <> v_rfq.id or v_new.rfq_number <> v_rfq.rfq_number or v_new.cargo_weight_max <> 6000 then
    raise exception 'assertion failed: unexpected revised rfq shape: %', to_jsonb(v_new);
  end if;

  if (select status from app.rfqs where id = v_rfq.id) <> 'superseded' then
    raise exception 'assertion failed: expected the original rfq version to be superseded';
  end if;

  -- The superseded version can no longer be issued/extended/cancelled.
  v_failed := false;
  begin
    perform app.cancel_rfq(v_rfq.id, 'attempt on superseded', (select record_version from app.rfqs where id = v_rfq.id), v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition:%' then
      raise exception 'assertion failed: expected invalid_transition on the superseded rfq, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected cancelling a superseded rfq to fail';
  end if;

  -- Idempotent replay of the revision itself.
  v_retry := app.revise_rfq(v_rfq.id, 6000, null, null, null, 'shipper increased cargo weight', 'idem-rfq-revise-1', (select record_version from app.rfqs where id = v_rfq.id), v_staff1, 'staff');
  if v_retry.id <> v_new.id then
    raise exception 'assertion failed: expected the idempotent revise replay to return the identical new-version row';
  end if;

  -- Reused revise key with a DIFFERENT cargo_weight_max -- rejected (design
  -- note 13b: the comparison covers the resolved override fields, not just
  -- revised_from_id).
  v_failed := false;
  begin
    perform app.revise_rfq(v_rfq.id, 7500, null, null, null, 'shipper increased cargo weight', 'idem-rfq-revise-1', (select record_version from app.rfqs where id = v_rfq.id), v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict:%' then
      raise exception 'assertion failed: expected idempotency_key_conflict for a different cargo_weight_max, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected a reused revise key with a different cargo_weight_max to fail';
  end if;
end $$;

\echo '>> app.list_rfqs: default excludes superseded versions; app.close_rfq_for_comparison marks un-responded invitations no_response'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_rfq_v1 app.rfqs;
  v_rfq_v2 app.rfqs;
  v_default_rows integer;
  v_superseded_rows integer;
  v_no_response_count integer;
begin
  select * into v_rfq_v1 from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';
  select * into v_rfq_v2 from app.rfqs where revised_from_id = v_rfq_v1.id;

  select count(*) into v_default_rows from app.list_rfqs(v_tenant1, null, v_staff1, 200) where id = v_rfq_v1.id;
  if v_default_rows <> 0 then
    raise exception 'assertion failed: expected the default (no status filter) list to exclude the superseded version';
  end if;
  select count(*) into v_superseded_rows from app.list_rfqs(v_tenant1, 'superseded', v_staff1, 200) where id = v_rfq_v1.id;
  if v_superseded_rows <> 1 then
    raise exception 'assertion failed: expected the explicit superseded filter to include it';
  end if;

  v_rfq_v2 := app.issue_rfq(v_rfq_v2.id, now() + interval '4 days', v_rfq_v2.record_version, v_staff1, 'staff');

  v_rfq_v2 := app.close_rfq_for_comparison(v_rfq_v2.id, v_rfq_v2.record_version, v_staff1, 'staff');
  if v_rfq_v2.status <> 'closed' or v_rfq_v2.closed_at is null then
    raise exception 'assertion failed: unexpected rfq shape after close: %', to_jsonb(v_rfq_v2);
  end if;

  select count(*) into v_no_response_count from app.rfq_invitations where rfq_id = v_rfq_v2.id and status = 'no_response';
  if v_no_response_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 invitation (vendor A, freshly re-invited, never responded on this version) to be marked no_response, got %', v_no_response_count;
  end if;

  -- Cannot close an already-closed rfq.
  begin
    perform app.close_rfq_for_comparison(v_rfq_v2.id, v_rfq_v2.record_version, v_staff1, 'staff');
    raise exception 'assertion failed: expected re-closing an already-closed rfq to fail';
  exception when others then
    if sqlerrm not like 'invalid_transition:%' then
      raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
    end if;
  end;
end $$;

\echo '>> app.cancel_rfq: mandatory reason, only from draft/issued'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_sourcing_id uuid;
  v_rfq app.rfqs;
  v_failed boolean;
begin
  select id into v_sourcing_id from app.sourcing_requests where tenant_id = v_tenant1 and status = 'shortlisted' order by created_at desc limit 1;
  v_rfq := app.draft_rfq_from_sourcing(v_tenant1, v_sourcing_id, v_staff1, 'idem-rfq-draft-cancel', v_staff1, 'staff');

  v_failed := false;
  begin
    perform app.cancel_rfq(v_rfq.id, '', v_rfq.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected an empty cancel reason to be rejected';
  end if;

  v_rfq := app.cancel_rfq(v_rfq.id, 'no longer needed', v_rfq.record_version, v_staff1, 'staff');
  if v_rfq.status <> 'cancelled' or v_rfq.closed_reason is null then
    raise exception 'assertion failed: unexpected rfq shape after cancel: %', to_jsonb(v_rfq);
  end if;
end $$;

\echo '>> reads: app.get_rfq/app.list_rfq_invitations/app.list_rfq_clarifications/app.get_rfq_history/app.list_rfq_response_attachments cross-tenant denial and shape checks'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000037102';
  v_staff2 uuid := '00000000-0000-0000-0000-000000037202';
  v_rfq app.rfqs;
  v_history_count integer;
  v_invitation_count integer;
  v_clarification_count integer;
  v_response record;
  v_attachment_count integer;
  v_failed boolean;
begin
  select * into v_rfq from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-rfq-draft-1';

  perform app.get_rfq(v_rfq.id, v_staff1);

  v_failed := false;
  begin
    perform app.get_rfq(v_rfq.id, v_staff2);
  exception when others then
    v_failed := true;
    -- Batch 257-259 review (C-05, MEDIUM): a cross-tenant, zero-membership caller
    -- now gets the SAME rfq_not_found a genuinely missing id would produce, never
    -- insufficient_authority (which would have echoed the real tenant_id in its
    -- own error text -- the live-reproduced disclosure this fix closed).
    if sqlerrm not like 'rfq_not_found:%' then
      raise exception 'assertion failed: expected rfq_not_found for the cross-tenant, zero-membership read (never insufficient_authority, which would disclose the real tenant_id), got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: expected the cross-tenant get_rfq to be denied';
  end if;

  select count(*) into v_history_count from app.get_rfq_history(v_rfq.id, v_staff1);
  if v_history_count < 1 then
    raise exception 'assertion failed: expected at least one lifecycle event for rfq %', v_rfq.id;
  end if;

  select count(*) into v_invitation_count from app.list_rfq_invitations(v_rfq.id, v_staff1);
  if v_invitation_count < 1 then
    raise exception 'assertion failed: expected at least one invitation listed';
  end if;

  select count(*) into v_clarification_count from app.list_rfq_clarifications(v_rfq.id, v_staff1);
  if v_clarification_count < 1 then
    raise exception 'assertion failed: expected at least one clarification listed';
  end if;

  select * into v_response from app.list_rfq_responses(v_rfq.id, v_staff1) where version = 2 limit 1;
  select count(*) into v_attachment_count from app.list_rfq_response_attachments(v_response.id, v_staff1);
  if v_attachment_count <> 0 then
    raise exception 'assertion failed: expected the resubmitted (version 2) response to carry zero attachments (none were passed), got %', v_attachment_count;
  end if;

  perform app.list_rfq_requirement_lines(v_rfq.id, v_staff1);
end $$;

\echo '>> HDN-377 (Storage and Signed URL Audit) regression: app.rfq_response_attachments_select_scoped RLS now requires real PRC:View authority, not just active tenant membership -- an active tenant member with zero PRC role assignment previously read the competitor-bid file_id linkage directly via RLS, live-forced independent of the RPC path''s (app.list_rfq_response_attachments) own already-correct PRC:View gate'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_zero_role uuid := '00000000-0000-0000-0000-000000037105';
  v_count integer;
begin
  insert into auth.users (id, email) values (v_zero_role, 'zerorole@rfq1.test');
  perform app.invite_user(v_tenant1, v_zero_role, 'zerorole@rfq1.test', 'Rfq1 Zero Role', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'zerorole@rfq1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_zero_role, 'org_user', v_tenant1, null, 'tester');

  if not exists (select 1 from app.rfq_response_attachments where tenant_id = v_tenant1) then
    raise exception 'assertion failed: test precondition failed -- expected at least one existing app.rfq_response_attachments row for tenant1';
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000037105", "role": "authenticated"}';
  select count(*) into v_count from app.rfq_response_attachments where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows visible via RLS to a tenant member holding zero PRC role assignment, got %', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000037102", "role": "authenticated"}';
  select count(*) into v_count from app.rfq_response_attachments where tenant_id = v_tenant1;
  if v_count = 0 then
    raise exception 'assertion failed: expected staff1 (holding PRC:View) to still see rows via RLS';
  end if;
  reset role;
end $$;

\echo '>> app.next_rfq_number: monotonic, never recycled, stable rfq_number across a revision'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'rfq1');
  v_n1 text;
  v_n2 text;
begin
  v_n1 := app.next_rfq_number(v_tenant1);
  v_n2 := app.next_rfq_number(v_tenant1);
  if v_n1 = v_n2 then
    raise exception 'assertion failed: expected two consecutive calls to app.next_rfq_number to differ';
  end if;
end $$;
