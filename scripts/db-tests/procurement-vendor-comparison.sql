-- Real, executable test evidence for PRC-258 (Vendor Comparison,
-- CG-S11-PRC-009) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Scoped to this checkpoint's own additive migration
-- (supabase/migrations/20260730650000_create_procurement_vendor_comparison.sql).
-- Sorts alphabetically after scripts/db-tests/procurement-sourcing.sql,
-- procurement-rfq.sql, procurement-vendor-*.sql -- self-contained, does not
-- rely on any of those having already run (own tenants/vendors/sourcing/RFQ
-- pipeline built from scratch below, mirroring procurement-rfq.sql's own
-- disclosed convention).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (cmp1) with a tenant_admin (admin1, full PRC+FIN), a comparison-editing staff actor (staff1: PRC Create/Edit/View/View cost/Override + FIN:View), an approval-only actor (approver1: PRC View/View cost/Approve + FIN:View), a View-cost-less editor (editor1: PRC Create/Edit/View, no View cost, no FIN -- for permission-denied checks), a View-only viewer (viewer1: PRC View only), a PRC-full-but-FIN-less actor (financeless1: PRC incl View cost/Approve, NO FIN role at all -- for the FIN:View gate check); a second tenant (cmp2) with a tenant_admin and a full-PRC+FIN staff actor for cross-tenant checks; a global Supreme Admin.'
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
  v_editor_role uuid;
  v_editor_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_financeless_role uuid;
  v_financeless_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000038101', 'admin@cmp1.test'),
    ('00000000-0000-0000-0000-000000038102', 'staff@cmp1.test'),
    ('00000000-0000-0000-0000-000000038103', 'approver@cmp1.test'),
    ('00000000-0000-0000-0000-000000038104', 'editor@cmp1.test'),
    ('00000000-0000-0000-0000-000000038105', 'viewer@cmp1.test'),
    ('00000000-0000-0000-0000-000000038106', 'financeless@cmp1.test'),
    ('00000000-0000-0000-0000-000000038201', 'admin@cmp2.test'),
    ('00000000-0000-0000-0000-000000038202', 'staff@cmp2.test'),
    ('00000000-0000-0000-0000-000000038999', 'supreme@cmp.test');

  perform app.provision_tenant('cmp1', 'Comparison Co 1', 'idem-cmp1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cmp1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('cmp2', 'Comparison Co 2', 'idem-cmp2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cmp2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038101', 'admin@cmp1.test', 'Cmp1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@cmp1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000038101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038102', 'staff@cmp1.test', 'Cmp1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cmp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038103', 'approver@cmp1.test', 'Cmp1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@cmp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038104', 'editor@cmp1.test', 'Cmp1 Editor', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'editor@cmp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038105', 'viewer@cmp1.test', 'Cmp1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@cmp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000038106', 'financeless@cmp1.test', 'Cmp1 Financeless', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeless@cmp1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000038201', 'admin@cmp2.test', 'Cmp2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@cmp2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000038201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000038202', 'staff@cmp2.test', 'Cmp2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cmp2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000038999', 'supreme_admin', null, null, 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'Cmp1 Admin', 'full PRC+FIN for setup', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve'))
      or (resource_module_code = 'FIN' and action in ('View', 'Edit', 'Approve'))
  ), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000038101', '00000000-0000-0000-0000-000000038999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'Cmp1 Staff', 'Create/Edit/View/View cost/Override + FIN:View', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override'))
      or (resource_module_code = 'FIN' and action = 'View')
  ), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000038102', '00000000-0000-0000-0000-000000038101', 'admin');

  v_approver_role := (app.create_role(v_tenant1, 'Cmp1 Approver', 'View/View cost/Approve + FIN:View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('View', 'View cost', 'Approve'))
      or (resource_module_code = 'FIN' and action = 'View')
  ), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000038103', '00000000-0000-0000-0000-000000038101', 'admin');

  v_editor_role := (app.create_role(v_tenant1, 'Cmp1 Editor', 'Create/Edit/View, no View cost, no FIN', 'tester')).id;
  v_editor_draft := app.create_role_version(v_editor_role, 'tester');
  perform app.set_role_version_permissions(v_editor_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_editor_role and status = 'published'), '00000000-0000-0000-0000-000000038104', '00000000-0000-0000-0000-000000038101', 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'Cmp1 Viewer', 'View only, no View cost', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000038105', '00000000-0000-0000-0000-000000038101', 'admin');

  v_financeless_role := (app.create_role(v_tenant1, 'Cmp1 Financeless', 'full PRC incl View cost/Approve, NO FIN role at all', 'tester')).id;
  v_financeless_draft := app.create_role_version(v_financeless_role, 'tester');
  perform app.set_role_version_permissions(v_financeless_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Approve', 'Override')), 'tester');
  perform app.publish_role_version(v_financeless_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_financeless_role and status = 'published'), '00000000-0000-0000-0000-000000038106', '00000000-0000-0000-0000-000000038101', 'admin');

  v_t2_staff_role := (app.create_role(v_tenant2, 'Cmp2 Staff', 'full PRC+FIN', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve'))
      or (resource_module_code = 'FIN' and action in ('View', 'Edit', 'Approve'))
  ), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000038201', '00000000-0000-0000-0000-000000038999', 'supreme');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000038202', '00000000-0000-0000-0000-000000038201', 'admin');
end $$;

\echo '>> setup: four ACTIVE vendors in tenant1 (A/B/D eligible+shortlisted, C eligible/not-shortlisted for the invite_additional_rfq_vendor override path)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000038101';
  v_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Cmp Vendor A', 'CMPA', 'PT', 'REG-CMP-A', 'logistics', 30, 'staff_created', 'idem-cmp-vendor-a', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Ani A', 'Ops', 'ani@cmpa.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Cmp Vendor B', 'CMPB', 'PT', 'REG-CMP-B', 'logistics', 30, 'staff_created', 'idem-cmp-vendor-b', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Budi B', 'Ops', 'budi@cmpb.test', '0812', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Gatot Subroto 2', 'Jakarta', 'DKI Jakarta', '10230', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Cmp Vendor C', 'CMPC', 'PT', 'REG-CMP-C', 'logistics', 30, 'staff_created', 'idem-cmp-vendor-c', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Citra C', 'Ops', 'citra@cmpc.test', '0813', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Asia Afrika 3', 'Bandung', 'Jawa Barat', '40111', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Cmp Vendor D', 'CMPD', 'PT', 'REG-CMP-D', 'logistics', 30, 'staff_created', 'idem-cmp-vendor-d', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Dedi D', 'Ops', 'dedi@cmpd.test', '0814', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Diponegoro 4', 'Jakarta', 'DKI Jakarta', '10240', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
end $$;

\echo '>> setup: an approved tenant-scoped USD -> IDR spot exchange rate (SGD -> IDR deliberately NOT registered, to exercise the auto fx_rate_missing exclusion path)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000038101';
  v_rate app.finance_exchange_rates;
begin
  v_rate := app.create_finance_exchange_rate_draft(v_tenant1, 'spot', 'USD', 'IDR', 15500, 'manual', now() - interval '1 hour', null, v_admin1, 'admin');
  perform app.approve_finance_exchange_rate(v_rate.id, v_rate.record_version, v_admin1, 'admin');
end $$;

\echo '>> setup: sourcing (shortlist A/B/D) -> RFQ (issue invites A/B/D, invite C via override) -> four responses (A IDR on-basis, B USD cross-currency, C SGD unconvertible, D IDR but already-expired validity) -> close for comparison'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000038101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_request app.sourcing_requests;
  v_candidate_a app.sourcing_candidates;
  v_candidate_b app.sourcing_candidates;
  v_candidate_c app.sourcing_candidates;
  v_candidate_d app.sourcing_candidates;
  v_vendor_a_master uuid;
  v_vendor_b_master uuid;
  v_vendor_c_master uuid;
  v_vendor_d_master uuid;
  v_rfq app.rfqs;
  v_invitation_a app.rfq_invitations;
  v_invitation_b app.rfq_invitations;
  v_invitation_c app.rfq_invitations;
  v_invitation_d app.rfq_invitations;
begin
  v_request := app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days',
    'IDR', 50000000, v_staff1, now() + interval '20 days', 'idem-cmp-sourcing-1', v_staff1, 'staff'
  );
  v_request := app.submit_sourcing_request(v_request.id, v_staff1, 'staff', v_request.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request.id, v_admin1, 'admin');

  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor A';
  select master_record_id into v_vendor_b_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor B';
  select master_record_id into v_vendor_c_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor C';
  select master_record_id into v_vendor_d_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor D';

  select * into v_candidate_a from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor_a_master;
  select * into v_candidate_b from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor_b_master;
  select * into v_candidate_c from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor_c_master;
  select * into v_candidate_d from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor_d_master;

  v_candidate_a := app.shortlist_sourcing_candidate(v_candidate_a.id, true, 'fit', v_staff1, 'staff', v_candidate_a.record_version);
  v_candidate_b := app.shortlist_sourcing_candidate(v_candidate_b.id, true, 'fit', v_staff1, 'staff', v_candidate_b.record_version);
  v_candidate_d := app.shortlist_sourcing_candidate(v_candidate_d.id, true, 'fit', v_staff1, 'staff', v_candidate_d.record_version);
  -- C is deliberately never shortlisted -- added later via app.invite_additional_rfq_vendor.

  v_request := app.submit_sourcing_shortlist(v_request.id, v_staff1, 'staff', v_request.record_version);

  v_rfq := app.draft_rfq_from_sourcing(v_tenant1, v_request.id, v_staff1, 'idem-cmp-rfq-1', v_staff1, 'staff');
  v_rfq := app.issue_rfq(v_rfq.id, now() + interval '5 days', v_rfq.record_version, v_staff1, 'staff');
  perform app.invite_additional_rfq_vendor(v_rfq.id, v_candidate_c.id, 'add vendor C for a wider comparison', v_staff1, 'staff');

  select * into v_invitation_a from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_a_master;
  select * into v_invitation_b from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_b_master;
  select * into v_invitation_c from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_c_master;
  select * into v_invitation_d from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_d_master;

  perform app.submit_rfq_response(v_invitation_a.id, 'IDR', 15000000, now() + interval '30 days', 20, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-cmp-resp-a', v_staff1, 'staff');
  perform app.submit_rfq_response(v_invitation_b.id, 'USD', 1000, now() + interval '30 days', 25, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-cmp-resp-b', v_staff1, 'staff');
  perform app.submit_rfq_response(v_invitation_c.id, 'SGD', 1300, now() + interval '30 days', 22, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-cmp-resp-c', v_staff1, 'staff');
  perform app.submit_rfq_response(v_invitation_d.id, 'IDR', 14000000, now() - interval '1 day', 18, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-cmp-resp-d', v_staff1, 'staff');

  v_rfq := app.close_rfq_for_comparison(v_rfq.id, v_rfq.record_version, v_staff1, 'staff');
  if v_rfq.status <> 'closed' then
    raise exception 'assertion failed: expected rfq to be closed, got %', v_rfq.status;
  end if;
end $$;

\echo '>> app.create_vendor_comparison: permission-denied (Create-less viewer, View-cost-less editor, FIN:View-less financeless actor), invalid_currency, invalid_criteria, cross-tenant tenant_mismatch, then a real create with 4 offers and correct auto-exclusion/normalization'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cmp2');
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_staff2 uuid := '00000000-0000-0000-0000-000000038202';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000038105';
  v_editor1 uuid := '00000000-0000-0000-0000-000000038104';
  v_financeless1 uuid := '00000000-0000-0000-0000-000000038106';
  v_rfq_id uuid;
  v_comparison app.vendor_comparisons;
  v_offer_count integer;
  v_a_offer app.vendor_comparison_offers;
  v_b_offer app.vendor_comparison_offers;
  v_c_offer app.vendor_comparison_offers;
  v_d_offer app.vendor_comparison_offers;
  v_vendor_a_master uuid;
  v_vendor_b_master uuid;
  v_failed boolean;
begin
  select id into v_rfq_id from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-rfq-1';
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor A';
  select master_record_id into v_vendor_b_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor B';

  v_failed := false;
  begin
    perform app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, null, 'idem-cmp-denied-viewer', v_viewer1, 'viewer');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%PRC:Create%' then
      raise exception 'assertion failed: expected insufficient_authority (PRC:Create) for the Create-less viewer, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the Create-less viewer to be denied'; end if;

  v_failed := false;
  begin
    perform app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, null, 'idem-cmp-denied-editor', v_editor1, 'editor');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%PRC:View cost%' then
      raise exception 'assertion failed: expected insufficient_authority (PRC:View cost) for the View-cost-less editor, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the View-cost-less editor to be denied'; end if;

  v_failed := false;
  begin
    perform app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, null, 'idem-cmp-denied-financeless', v_financeless1, 'financeless');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%FIN:View%' then
      raise exception 'assertion failed: expected insufficient_authority (FIN:View) for the FIN-less actor, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the FIN:View-less actor to be denied'; end if;

  v_failed := false;
  begin
    perform app.create_vendor_comparison(v_tenant1, v_rfq_id, 'XXX', null, null, null, null, 'idem-cmp-bad-currency', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_currency:%' then
      raise exception 'assertion failed: expected invalid_currency, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an unregistered currency to be rejected'; end if;

  v_failed := false;
  begin
    perform app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, '[{"key":"service","label":"Service","weight":100}]'::jsonb, 'idem-cmp-bad-criteria-1', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_criteria:%' then
      raise exception 'assertion failed: expected invalid_criteria (missing price), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected criteria without a price entry to be rejected'; end if;

  v_failed := false;
  begin
    perform app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, '[{"key":"price","label":"Price","weight":60},{"key":"service","label":"Service","weight":30}]'::jsonb, 'idem-cmp-bad-criteria-2', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_criteria:%' then
      raise exception 'assertion failed: expected invalid_criteria (weights != 100), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected criteria not summing to 100 to be rejected'; end if;

  v_failed := false;
  begin
    perform app.create_vendor_comparison(v_tenant2, v_rfq_id, 'IDR', null, null, null, null, 'idem-cmp-xtenant', v_staff2, 'staff2');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'tenant_mismatch:%' then
      raise exception 'assertion failed: expected tenant_mismatch for the cross-tenant create, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the cross-tenant create to fail'; end if;

  -- The real create.
  v_comparison := app.create_vendor_comparison(
    v_tenant1, v_rfq_id, 'IDR', 5000, 40, 1,
    '[{"key":"price","label":"Price","weight":70},{"key":"service","label":"Service Quality","weight":30}]'::jsonb,
    'idem-cmp-create-1', v_staff1, 'staff'
  );
  if v_comparison.status <> 'draft' or v_comparison.comparison_currency <> 'IDR' then
    raise exception 'assertion failed: unexpected comparison shape: %', to_jsonb(v_comparison);
  end if;

  select count(*) into v_offer_count from app.vendor_comparison_offers where comparison_id = v_comparison.id;
  if v_offer_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 offers (A/B/C/D), got %', v_offer_count;
  end if;

  select * into v_a_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_a_master;
  select * into v_b_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_b_master;
  select * into v_c_offer from app.vendor_comparison_offers o join app.vendor_profiles vp on vp.master_record_id = o.vendor_master_id where o.comparison_id = v_comparison.id and vp.legal_name = 'PT Cmp Vendor C';
  select * into v_d_offer from app.vendor_comparison_offers o join app.vendor_profiles vp on vp.master_record_id = o.vendor_master_id where o.comparison_id = v_comparison.id and vp.legal_name = 'PT Cmp Vendor D';

  if not v_a_offer.included or v_a_offer.normalized_amount <> 15000000.00 then
    raise exception 'assertion failed: expected offer A included with normalized_amount=15000000.00, got included=% amount=%', v_a_offer.included, v_a_offer.normalized_amount;
  end if;
  if not v_b_offer.included or v_b_offer.normalized_amount <> 15500000.00 then
    raise exception 'assertion failed: expected offer B included with normalized_amount=15500000.00 (1000 USD * 15500), got included=% amount=%', v_b_offer.included, v_b_offer.normalized_amount;
  end if;
  if v_c_offer.included or v_c_offer.exclusion_reason <> 'auto:fx_rate_missing' or v_c_offer.normalized_amount is not null then
    raise exception 'assertion failed: expected offer C auto-excluded (fx_rate_missing, no SGD rate registered), got included=% reason=% amount=%', v_c_offer.included, v_c_offer.exclusion_reason, v_c_offer.normalized_amount;
  end if;
  if v_d_offer.included or v_d_offer.exclusion_reason <> 'auto:offer_expired' or v_d_offer.normalized_amount is not null then
    raise exception 'assertion failed: expected offer D auto-excluded (offer_expired, validity_until already past), got included=% reason=% amount=%', v_d_offer.included, v_d_offer.exclusion_reason, v_d_offer.normalized_amount;
  end if;

  if v_a_offer.price_score <> 100.00 or v_a_offer.rank <> 1 then
    raise exception 'assertion failed: expected offer A (lowest normalized cost) to have price_score=100.00 and rank=1, got price_score=% rank=%', v_a_offer.price_score, v_a_offer.rank;
  end if;
  if v_b_offer.rank <> 2 or v_b_offer.price_score >= 100.00 then
    raise exception 'assertion failed: expected offer B to rank 2nd with a price_score below 100, got rank=% price_score=%', v_b_offer.rank, v_b_offer.price_score;
  end if;
  if v_c_offer.rank is not null or v_d_offer.rank is not null then
    raise exception 'assertion failed: expected both excluded offers to carry a null rank';
  end if;
  -- No criteria scored yet -- unscored non-price counts as 0, so composite = 0.70 * price_score.
  if v_a_offer.composite_score <> 70.00 then
    raise exception 'assertion failed: expected offer A composite_score=70.00 (0.70 * 100 price_score + 0.30 * 0 unscored service), got %', v_a_offer.composite_score;
  end if;

  -- Idempotency replay: identical inputs return the SAME row.
  declare
    v_retry app.vendor_comparisons;
  begin
    v_retry := app.create_vendor_comparison(
      v_tenant1, v_rfq_id, 'IDR', 5000, 40, 1,
      '[{"key":"price","label":"Price","weight":70},{"key":"service","label":"Service Quality","weight":30}]'::jsonb,
      'idem-cmp-create-1', v_staff1, 'staff'
    );
    if v_retry.id <> v_comparison.id or v_retry.record_version <> v_comparison.record_version then
      raise exception 'assertion failed: expected the idempotent replay to return the identical row';
    end if;
  end;

  -- Reused key, different currency -- rejected.
  v_failed := false;
  begin
    perform app.create_vendor_comparison(v_tenant1, v_rfq_id, 'USD', 5000, 40, 1, null, 'idem-cmp-create-1', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict:%' then
      raise exception 'assertion failed: expected idempotency_key_conflict, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the reused-key-different-currency call to fail'; end if;
end $$;

\echo '>> app.create_vendor_comparison: no_comparable_responses when the source rfq has zero submitted, comparison-eligible responses'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000038101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_request app.sourcing_requests;
  v_candidate_a app.sourcing_candidates;
  v_vendor_a_master uuid;
  v_rfq app.rfqs;
  v_failed boolean;
begin
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor A';

  v_request := app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days',
    'IDR', 50000000, v_staff1, now() + interval '20 days', 'idem-cmp-sourcing-empty', v_staff1, 'staff'
  );
  v_request := app.submit_sourcing_request(v_request.id, v_staff1, 'staff', v_request.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request.id, v_admin1, 'admin');
  select * into v_candidate_a from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor_a_master;
  v_candidate_a := app.shortlist_sourcing_candidate(v_candidate_a.id, true, 'fit', v_staff1, 'staff', v_candidate_a.record_version);
  v_request := app.submit_sourcing_shortlist(v_request.id, v_staff1, 'staff', v_request.record_version);

  v_rfq := app.draft_rfq_from_sourcing(v_tenant1, v_request.id, v_staff1, 'idem-cmp-rfq-empty', v_staff1, 'staff');
  v_rfq := app.issue_rfq(v_rfq.id, now() + interval '5 days', v_rfq.record_version, v_staff1, 'staff');
  -- Nobody responds.
  v_rfq := app.close_rfq_for_comparison(v_rfq.id, v_rfq.record_version, v_staff1, 'staff');

  v_failed := false;
  begin
    perform app.create_vendor_comparison(v_tenant1, v_rfq.id, 'IDR', null, null, null, null, 'idem-cmp-create-empty', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'no_comparable_responses:%' then
      raise exception 'assertion failed: expected no_comparable_responses, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected creating a comparison from an rfq with zero responses to fail'; end if;
end $$;

\echo '>> app.link_vendor_comparison_offer_rate: composes app.calculate_vendor_rate + app.convert_finance_amount, blocks a not-approved rate, blocks a vendor mismatch, blocks a null/zero basis_quantity'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000038101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_comparison app.vendor_comparisons;
  v_a_offer app.vendor_comparison_offers;
  v_b_offer app.vendor_comparison_offers;
  v_vendor_a_master uuid;
  v_vendor_b_master uuid;
  v_rate_draft app.vendor_rate_versions;
  v_rate_approved app.vendor_rate_versions;
  v_failed boolean;
begin
  select * into v_comparison from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-create-1';
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor A';
  select master_record_id into v_vendor_b_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor B';
  select * into v_a_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_a_master;
  select * into v_b_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_b_master;

  -- A pending_approval rate cannot be linked.
  -- p_vendor_master_id (22nd, trailing-optional per PRC-255/ADR-0020) links this
  -- rate to vendor A's REAL canonical identity (app.vendor_profiles.master_record_id,
  -- master_type_code='vendor') -- distinct from master_record_id (the vendor_rate-
  -- typed identity app.create_rate_version itself get-or-creates from vendor_code/
  -- vendor_name) -- exactly the column app.link_vendor_comparison_offer_rate
  -- compares against (migration design note re: master_record_id vs vendor_master_id).
  v_rate_draft := app.create_rate_version(v_tenant1, 'CMPA', 'PT Cmp Vendor A', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', null, null, null, null, null, 'IDR', 14000, null, '[]'::jsonb, now(), null, null, v_admin1, 'admin', v_vendor_a_master);
  v_failed := false;
  begin
    perform app.link_vendor_comparison_offer_rate(v_a_offer.id, v_rate_draft.id, v_a_offer.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_rate_status:%' then
      raise exception 'assertion failed: expected invalid_rate_status for a not-yet-approved rate, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected linking a pending_approval rate to fail'; end if;

  perform app.approve_rate_version(v_rate_draft.id, v_rate_draft.record_version, v_admin1, 'admin');
  select * into v_rate_approved from app.vendor_rate_versions where id = v_rate_draft.id;

  -- Vendor mismatch: A's own approved rate cannot be linked to B's offer.
  v_failed := false;
  begin
    perform app.link_vendor_comparison_offer_rate(v_b_offer.id, v_rate_approved.id, v_b_offer.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_mismatch:%' then
      raise exception 'assertion failed: expected vendor_mismatch, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected linking vendor A''s rate to vendor B''s offer to fail'; end if;

  -- The real link: base_amount 14000 * basis_quantity 1 = computed_amount 14000.00 (IDR, same currency -> identity conversion).
  v_a_offer := app.link_vendor_comparison_offer_rate(v_a_offer.id, v_rate_approved.id, v_a_offer.record_version, v_staff1, 'staff');
  if v_a_offer.rate_version_id <> v_rate_approved.id or v_a_offer.engine_computed_amount <> 14000.00 or v_a_offer.engine_currency <> 'IDR' or v_a_offer.normalized_amount <> 14000.00 then
    raise exception 'assertion failed: unexpected offer shape after linking the rate engine: %', to_jsonb(v_a_offer);
  end if;
  if v_a_offer.engine_breakdown is null or not (v_a_offer.engine_breakdown ? 'computed_amount') then
    raise exception 'assertion failed: expected engine_breakdown to carry the full app.calculate_vendor_rate result';
  end if;

  -- A basis_quantity-less comparison cannot link a rate.
  declare
    v_rfq_id uuid;
    v_no_qty_comparison app.vendor_comparisons;
    v_no_qty_offer app.vendor_comparison_offers;
  begin
    select id into v_rfq_id from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-rfq-1';
    v_no_qty_comparison := app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, null, 'idem-cmp-create-no-qty', v_staff1, 'staff');
    select * into v_no_qty_offer from app.vendor_comparison_offers where comparison_id = v_no_qty_comparison.id and vendor_master_id = v_vendor_a_master;

    v_failed := false;
    begin
      perform app.link_vendor_comparison_offer_rate(v_no_qty_offer.id, v_rate_approved.id, v_no_qty_offer.record_version, v_staff1, 'staff');
    exception when others then
      v_failed := true;
      if sqlerrm not like 'invalid_basis_quantity:%' then
        raise exception 'assertion failed: expected invalid_basis_quantity, got %', sqlerrm;
      end if;
    end;
    if not v_failed then raise exception 'assertion failed: expected linking a rate with no basis_quantity to fail'; end if;
  end;
end $$;

\echo '>> app.score_vendor_comparison_offer_criterion: rejects price/unknown criterion, upserts a real 0-100 score, recomputes composite_score'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_comparison app.vendor_comparisons;
  v_a_offer app.vendor_comparison_offers;
  v_vendor_a_master uuid;
  v_score app.vendor_comparison_offer_scores;
  v_failed boolean;
begin
  select * into v_comparison from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-create-1';
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor A';
  select * into v_a_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_a_master;

  v_failed := false;
  begin
    perform app.score_vendor_comparison_offer_criterion(v_a_offer.id, 'price', 90, null, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_criterion:%' then
      raise exception 'assertion failed: expected invalid_criterion for a manual price score, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected scoring "price" manually to fail'; end if;

  v_failed := false;
  begin
    perform app.score_vendor_comparison_offer_criterion(v_a_offer.id, 'compliance', 90, null, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'unknown_criterion:%' then
      raise exception 'assertion failed: expected unknown_criterion, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected scoring an unconfigured criterion to fail'; end if;

  v_score := app.score_vendor_comparison_offer_criterion(v_a_offer.id, 'service', 90, 'strong track record', v_staff1, 'staff');
  if v_score.score <> 90 or v_score.criterion_weight <> 30 then
    raise exception 'assertion failed: unexpected score row: %', to_jsonb(v_score);
  end if;

  -- With the rate linked (design note 4), A is now normalized_amount=14000.00, still lowest -> price_score=100.
  -- composite = 0.70 * 100 + 0.30 * 90 = 97.00.
  select * into v_a_offer from app.vendor_comparison_offers where id = v_a_offer.id;
  if v_a_offer.composite_score <> 97.00 or v_a_offer.non_price_score <> 90.00 then
    raise exception 'assertion failed: expected composite_score=97.00, non_price_score=90.00 after scoring service=90, got composite=% non_price=%', v_a_offer.composite_score, v_a_offer.non_price_score;
  end if;

  -- Upsert: re-scoring the same criterion replaces, never duplicates.
  perform app.score_vendor_comparison_offer_criterion(v_a_offer.id, 'service', 80, 'revised down', v_staff1, 'staff');
  declare
    v_count integer;
  begin
    select count(*) into v_count from app.vendor_comparison_offer_scores where comparison_offer_id = v_a_offer.id and criterion_key = 'service';
    if v_count <> 1 then
      raise exception 'assertion failed: expected exactly one score row per (offer, criterion) after re-scoring, got %', v_count;
    end if;
  end;
end $$;

\echo '>> app.set_vendor_comparison_offer_inclusion: mandatory reason to exclude, blocks stale_version, re-include clears exclusion_reason and rank recomputes'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_comparison app.vendor_comparisons;
  v_b_offer app.vendor_comparison_offers;
  v_vendor_b_master uuid;
  v_failed boolean;
begin
  select * into v_comparison from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-create-1';
  select master_record_id into v_vendor_b_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor B';
  select * into v_b_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_b_master;

  v_failed := false;
  begin
    perform app.set_vendor_comparison_offer_inclusion(v_b_offer.id, false, '', v_b_offer.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required for an empty exclusion reason, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an empty exclusion reason to be rejected'; end if;

  v_failed := false;
  begin
    perform app.set_vendor_comparison_offer_inclusion(v_b_offer.id, false, 'invalid quote', v_b_offer.record_version + 99, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'stale_version:%' then
      raise exception 'assertion failed: expected stale_version, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a wrong expected_version to be rejected'; end if;

  v_b_offer := app.set_vendor_comparison_offer_inclusion(v_b_offer.id, false, 'quote later found invalid', v_b_offer.record_version, v_staff1, 'staff');
  if v_b_offer.included or v_b_offer.exclusion_reason <> 'quote later found invalid' or v_b_offer.rank is not null then
    raise exception 'assertion failed: unexpected offer shape after manual exclusion: %', to_jsonb(v_b_offer);
  end if;

  v_b_offer := app.set_vendor_comparison_offer_inclusion(v_b_offer.id, true, null, v_b_offer.record_version, v_staff1, 'staff');
  if not v_b_offer.included or v_b_offer.exclusion_reason is not null or v_b_offer.rank is null then
    raise exception 'assertion failed: unexpected offer shape after re-inclusion: %', to_jsonb(v_b_offer);
  end if;
end $$;

\echo '>> app.recommend_vendor_comparison_offer: mandatory reason for a non-lowest recommendation, allowed for the lowest with no reason, re-recommendation before submission is allowed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_comparison app.vendor_comparisons;
  v_a_offer app.vendor_comparison_offers;
  v_b_offer app.vendor_comparison_offers;
  v_vendor_a_master uuid;
  v_vendor_b_master uuid;
  v_failed boolean;
begin
  select * into v_comparison from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-create-1';
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor A';
  select master_record_id into v_vendor_b_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor B';
  select * into v_a_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_a_master;
  select * into v_b_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_b_master;

  v_failed := false;
  begin
    perform app.recommend_vendor_comparison_offer(v_comparison.id, v_b_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required for recommending the non-lowest offer B, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected recommending offer B (not lowest) with no reason to fail'; end if;

  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_a_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
  if v_comparison.status <> 'recommended' or v_comparison.recommended_offer_id <> v_a_offer.id then
    raise exception 'assertion failed: unexpected comparison shape after recommending the lowest offer: %', to_jsonb(v_comparison);
  end if;

  -- Re-recommending before submission (a governed change of mind) is allowed.
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_b_offer.id, 'management prefers vendor B''s faster lead time', v_comparison.record_version, v_staff1, 'staff');
  if v_comparison.recommended_offer_id <> v_b_offer.id or v_comparison.recommended_reason is null then
    raise exception 'assertion failed: expected the re-recommendation to update recommended_offer_id/reason: %', to_jsonb(v_comparison);
  end if;

  -- Restore the lowest-cost recommendation for the submit-flow test below.
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_a_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
end $$;

\echo '>> app.submit_vendor_comparison_for_approval: PRC:Approve required (not Edit), mandatory reason to select a non-recommended offer, terminal afterward'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000038103';
  v_comparison app.vendor_comparisons;
  v_a_offer app.vendor_comparison_offers;
  v_b_offer app.vendor_comparison_offers;
  v_vendor_a_master uuid;
  v_vendor_b_master uuid;
  v_failed boolean;
begin
  select * into v_comparison from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-create-1';
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor A';
  select master_record_id into v_vendor_b_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Cmp Vendor B';
  select * into v_a_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_a_master;
  select * into v_b_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_b_master;

  v_failed := false;
  begin
    perform app.submit_vendor_comparison_for_approval(v_comparison.id, v_a_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%PRC:Approve%' then
      raise exception 'assertion failed: expected insufficient_authority (PRC:Approve) for staff1 (Edit, not Approve), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the Edit-only staff actor to be denied PRC:Approve'; end if;

  v_failed := false;
  begin
    perform app.submit_vendor_comparison_for_approval(v_comparison.id, v_b_offer.id, null, v_comparison.record_version, v_approver1, 'approver');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required for selecting offer B when A is recommended, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected selecting the non-recommended offer with no reason to fail'; end if;

  v_comparison := app.submit_vendor_comparison_for_approval(v_comparison.id, v_b_offer.id, 'override: vendor B''s faster lead time outweighs the small price gap', v_comparison.record_version, v_approver1, 'approver');
  if v_comparison.status <> 'submitted' or v_comparison.selected_offer_id <> v_b_offer.id or v_comparison.selection_reason is null then
    raise exception 'assertion failed: unexpected comparison shape after submission: %', to_jsonb(v_comparison);
  end if;

  -- Terminal: every offer/root mutation now fails invalid_transition.
  v_failed := false;
  begin
    perform app.set_vendor_comparison_offer_inclusion(v_a_offer.id, false, 'too late', v_a_offer.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition:%' then
      raise exception 'assertion failed: expected invalid_transition after submission, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected offer mutation after submission to fail'; end if;

  v_failed := false;
  begin
    perform app.recommend_vendor_comparison_offer(v_comparison.id, v_a_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_transition:%' then
      raise exception 'assertion failed: expected invalid_transition re-recommending after submission, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected re-recommendation after submission to fail'; end if;
end $$;

\echo '>> app.revise_vendor_comparison: mandatory reason, marks the current version superseded, creates a new draft version, idempotent replay compares the full resolved tuple'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_rfq_id uuid;
  v_comparison app.vendor_comparisons;
  v_revised app.vendor_comparisons;
  v_retry app.vendor_comparisons;
  v_failed boolean;
begin
  select id into v_rfq_id from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-rfq-1';
  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', 5000, 40, 1, null, 'idem-cmp-revise-base', v_staff1, 'staff');

  v_failed := false;
  begin
    perform app.revise_vendor_comparison(v_comparison.id, null, 6000, null, null, null, '', 'idem-cmp-revise-1', v_comparison.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required for an empty revise reason, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an empty revise reason to be rejected'; end if;

  v_revised := app.revise_vendor_comparison(v_comparison.id, null, 6000, null, null, null, 'wider weight basis re-requested', 'idem-cmp-revise-1', v_comparison.record_version, v_staff1, 'staff');
  if v_revised.status <> 'draft' or v_revised.revised_from_id <> v_comparison.id or v_revised.version <> 2 or v_revised.basis_weight <> 6000 then
    raise exception 'assertion failed: unexpected revised comparison shape: %', to_jsonb(v_revised);
  end if;

  select status into strict v_comparison.status from app.vendor_comparisons where id = v_comparison.id;
  if v_comparison.status <> 'superseded' then
    raise exception 'assertion failed: expected the original comparison version to be superseded, got %', v_comparison.status;
  end if;

  -- Idempotent replay (same key, same resolved tuple) returns the SAME new row.
  v_retry := app.revise_vendor_comparison(v_comparison.id, null, 6000, null, null, null, 'wider weight basis re-requested', 'idem-cmp-revise-1', v_comparison.record_version, v_staff1, 'staff');
  if v_retry.id <> v_revised.id then
    raise exception 'assertion failed: expected the idempotent revise replay to return the identical new-version row';
  end if;

  -- Reused key, different basis_weight -- rejected.
  v_failed := false;
  begin
    perform app.revise_vendor_comparison(v_comparison.id, null, 7000, null, null, null, 'different basis', 'idem-cmp-revise-1', v_comparison.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict:%' then
      raise exception 'assertion failed: expected idempotency_key_conflict for a reused key with a different basis_weight, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the reused-key-different-basis revise to fail'; end if;
end $$;

\echo '>> reads: app.get_vendor_comparison/app.list_vendor_comparisons/app.list_vendor_comparison_offer_scores/app.get_vendor_comparison_history cross-tenant denial and shape checks'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_staff2 uuid := '00000000-0000-0000-0000-000000038202';
  v_comparison app.vendor_comparisons;
  v_history_count integer;
  v_list_count integer;
  v_failed boolean;
begin
  select * into v_comparison from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-create-1';

  perform app.get_vendor_comparison(v_comparison.id, v_staff1);

  v_failed := false;
  begin
    perform app.get_vendor_comparison(v_comparison.id, v_staff2);
  exception when others then
    v_failed := true;
    -- Batch 257-259 review (C-05, MEDIUM): a cross-tenant, zero-membership caller
    -- now gets the SAME vendor_comparison_not_found a genuinely missing id would
    -- produce, never insufficient_authority (which would have echoed the real
    -- tenant_id in its own error text -- the live-reproduced disclosure this fix
    -- closed).
    if sqlerrm not like 'vendor_comparison_not_found:%' then
      raise exception 'assertion failed: expected vendor_comparison_not_found for the cross-tenant, zero-membership read (never insufficient_authority, which would disclose the real tenant_id), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the cross-tenant get_vendor_comparison to be denied'; end if;

  select count(*) into v_history_count from app.get_vendor_comparison_history(v_comparison.id, v_staff1);
  if v_history_count < 2 then
    raise exception 'assertion failed: expected at least 2 lifecycle events (draft, recommended, submitted) for comparison %, got %', v_comparison.id, v_history_count;
  end if;

  select count(*) into v_list_count from app.list_vendor_comparisons(v_tenant1, null, null, v_staff1, 50);
  if v_list_count < 1 then
    raise exception 'assertion failed: expected at least one comparison listed';
  end if;

  perform app.list_vendor_comparison_offers(v_comparison.id, v_staff1);
end $$;

\echo '>> REAL two-process concurrent revise race: two independent psql sessions both call app.revise_vendor_comparison on the SAME draft comparison with the SAME expected_version -- exactly one must succeed (creating a new version), the other must fail stale_version'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cmp1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000038102';
  v_rfq_id uuid;
  v_comparison app.vendor_comparisons;
begin
  select id into v_rfq_id from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-cmp-rfq-1';
  perform app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', 5000, 40, 1, null, 'idem-cmp-race-base', v_staff1, 'staff');
end $$;

select id as race_comparison_id, record_version as race_comparison_version from app.vendor_comparisons where idempotency_key = 'idem-cmp-race-base' \gset
select current_database() as pg_test_db \gset

\set race_sql_a 'select app.revise_vendor_comparison(''' :race_comparison_id ''', null, null, null, null, null, ''race leg A'', ''idem-cmp-race-a'', ' :race_comparison_version ', ''00000000-0000-0000-0000-000000038102'', ''staff'');'
\set race_sql_b 'select app.revise_vendor_comparison(''' :race_comparison_id ''', null, null, null, null, null, ''race leg B'', ''idem-cmp-race-b'', ' :race_comparison_version ', ''00000000-0000-0000-0000-000000038102'', ''staff'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-vendor-comparison-race-a.out
\setenv RACE_OUT_B /tmp/cargogrid-vendor-comparison-race-b.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_race_comparison_id uuid := (select id from app.vendor_comparisons where idempotency_key = 'idem-cmp-race-base');
  v_superseded_status text;
  v_new_version_count integer;
begin
  select status into v_superseded_status from app.vendor_comparisons where id = v_race_comparison_id;
  if v_superseded_status <> 'superseded' then
    raise exception 'assertion failed: expected the raced comparison to end up superseded (exactly one revise won), got %', v_superseded_status;
  end if;

  select count(*) into v_new_version_count from app.vendor_comparisons where revised_from_id = v_race_comparison_id;
  if v_new_version_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE new version to have been created by the race (never zero, never two), got % -- see /tmp/cargogrid-vendor-comparison-race-a.out and -b.out for both real process outcomes', v_new_version_count;
  end if;

  raise notice 'concurrent revise race proof: exactly 1 of 2 racing app.revise_vendor_comparison calls (same expected_version) created a new version -- the record_version-scoped UPDATE + post-UPDATE stale_version check correctly serialized two real, independent psql processes';
end $$;
