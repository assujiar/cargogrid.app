-- Real, executable test evidence for PRC-260 (Purchase Order, CG-S11-PRC-011) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database. Scoped to this
-- checkpoint's own additive migration (supabase/migrations/
-- 20260730680000_create_procurement_purchase_order.sql). Sorts alphabetically after
-- procurement-approval.sql/procurement-rfq.sql/procurement-sourcing.sql/procurement-
-- vendor-*.sql -- self-contained, does not rely on any of those having already run (own
-- tenants/vendors/sourcing/RFQ/comparison/approval-routing pipeline built from scratch
-- below, mirroring procurement-vendor-comparison.sql's own disclosed convention).
--
-- Two tenants (po1/po2), role-scoped actors, a real 2-step sequential approval routing
-- definition (manager then finance, mirroring procurement-approval.sql's own setup
-- exactly), cross-tenant/permission-denied/idempotency-replay scenarios, and a REAL
-- two-process concurrent race on app.amend_purchase_order (reusing
-- scripts/db-tests/wms-picking-concurrency-helper.sh, the same helper PRC-258's own
-- revise-race test uses).
--
-- Disclosed, not tested here (bounded scope, not an oversight):
--   * End-to-end p_tax_code composition (a real approved FIN-195 tax rule + a successful
--     app.calculate_finance_tax call inside app.draft_purchase_order_from_selection) --
--     app.calculate_finance_tax itself is already tested at FIN-195's own level and is
--     composed here unmodified. The one piece of genuinely NEW code this migration adds
--     around it -- the tax-rule-currency-mismatch guard -- is not exercised here; only
--     the proactive FIN:View authority gate (checked before any tax rule is resolved) is.
--   * app.decide_purchase_order_approval_step's not_a_purchase_order_approval branch --
--     identical in shape to the already-proven pattern in the three sibling wrappers
--     (app.decide_vendor_activation_approval_step et al., PRC-259's own db-test), a
--     straight copy, not independently re-derived here.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (po1): tenant_admin (admin1, full PRC+FIN), a full-PRC+FIN staff actor (staff1: Create/Edit/View/View cost/Override), an approve-only actor (approver1: View/View cost/Approve), a View-cost-less editor (editor1: Create/Edit/View, no View cost), a View-only viewer (viewer1), a PRC-full-but-FIN-less actor (financeless1), an outsider with no PRC role at all (outsider1), a manager + finance role for a real 2-step sequential approval routing definition. Tenant2 (po2): tenant_admin (admin2) + staff2, for cross-tenant checks. A global Supreme Admin.'
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
  v_outsider_role uuid;
  v_outsider_draft app.role_versions;
  v_manager_role uuid;
  v_finance_role uuid;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
  v_approval_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000260101', 'admin@po1.test'),
    ('00000000-0000-0000-0000-000000260102', 'staff@po1.test'),
    ('00000000-0000-0000-0000-000000260103', 'approver@po1.test'),
    ('00000000-0000-0000-0000-000000260104', 'editor@po1.test'),
    ('00000000-0000-0000-0000-000000260105', 'viewer@po1.test'),
    ('00000000-0000-0000-0000-000000260106', 'financeless@po1.test'),
    ('00000000-0000-0000-0000-000000260107', 'outsider@po1.test'),
    ('00000000-0000-0000-0000-000000260108', 'manager@po1.test'),
    ('00000000-0000-0000-0000-000000260109', 'finance@po1.test'),
    ('00000000-0000-0000-0000-000000260201', 'admin@po2.test'),
    ('00000000-0000-0000-0000-000000260202', 'staff@po2.test'),
    ('00000000-0000-0000-0000-000000260999', 'supreme@po.test');

  perform app.provision_tenant('po1', 'Purchase Order Co 1', 'idem-po1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'po1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('po2', 'Purchase Order Co 2', 'idem-po2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'po2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000260101', 'admin@po1.test', 'Po1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@po1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000260101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000260102', 'staff@po1.test', 'Po1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@po1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000260103', 'approver@po1.test', 'Po1 Approver', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@po1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000260104', 'editor@po1.test', 'Po1 Editor', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'editor@po1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000260105', 'viewer@po1.test', 'Po1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@po1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000260106', 'financeless@po1.test', 'Po1 Financeless', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeless@po1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000260107', 'outsider@po1.test', 'Po1 Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@po1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000260108', 'manager@po1.test', 'Po1 Manager', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@po1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000260109', 'finance@po1.test', 'Po1 Finance', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'finance@po1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000260201', 'admin@po2.test', 'Po2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@po2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000260201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000260202', 'staff@po2.test', 'Po2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@po2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000260999', 'supreme_admin', null, null, 'tester');

  v_admin_role := (app.create_role(v_tenant1, 'Po1 Admin', 'full PRC+FIN for setup', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve', 'Reject'))
      or (resource_module_code = 'FIN' and action in ('View', 'Edit', 'Approve'))
  ), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000260101', '00000000-0000-0000-0000-000000260999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'Po1 Staff', 'Create/Edit/View/View cost/Override + FIN:View', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override'))
      or (resource_module_code = 'FIN' and action = 'View')
  ), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000260102', '00000000-0000-0000-0000-000000260101', 'admin');

  v_approver_role := (app.create_role(v_tenant1, 'Po1 Approver', 'View/View cost/Approve + FIN:View', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('View', 'View cost', 'Approve'))
      or (resource_module_code = 'FIN' and action = 'View')
  ), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000260103', '00000000-0000-0000-0000-000000260101', 'admin');

  v_editor_role := (app.create_role(v_tenant1, 'Po1 Editor', 'Create/Edit/View, no View cost, no FIN', 'tester')).id;
  v_editor_draft := app.create_role_version(v_editor_role, 'tester');
  perform app.set_role_version_permissions(v_editor_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_editor_role and status = 'published'), '00000000-0000-0000-0000-000000260104', '00000000-0000-0000-0000-000000260101', 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'Po1 Viewer', 'View only, no View cost', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000260105', '00000000-0000-0000-0000-000000260101', 'admin');

  v_financeless_role := (app.create_role(v_tenant1, 'Po1 Financeless', 'full PRC incl View cost/Override, NO FIN role at all', 'tester')).id;
  v_financeless_draft := app.create_role_version(v_financeless_role, 'tester');
  perform app.set_role_version_permissions(v_financeless_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override')), 'tester');
  perform app.publish_role_version(v_financeless_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_financeless_role and status = 'published'), '00000000-0000-0000-0000-000000260106', '00000000-0000-0000-0000-000000260101', 'admin');

  v_outsider_role := (app.create_role(v_tenant1, 'Po1 Outsider', 'no PRC at all', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(v_outsider_draft.id, array[]::uuid[], 'tester');
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000260107', '00000000-0000-0000-0000-000000260101', 'admin');

  v_manager_role := (app.create_role(v_tenant1, 'Po1 Manager Approver', 'approval routing step 1', 'tester')).id;
  perform app.publish_role_version((app.create_role_version(v_manager_role, 'tester')).id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000260108', '00000000-0000-0000-0000-000000260101', 'admin');

  v_finance_role := (app.create_role(v_tenant1, 'Po1 Finance Approver', 'approval routing step 2', 'tester')).id;
  perform app.publish_role_version((app.create_role_version(v_finance_role, 'tester')).id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_finance_role and status = 'published'), '00000000-0000-0000-0000-000000260109', '00000000-0000-0000-0000-000000260101', 'admin');

  v_t2_staff_role := (app.create_role(v_tenant2, 'Po2 Staff', 'full PRC+FIN', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(
    select id from app.permissions where (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override'))
      or (resource_module_code = 'FIN' and action = 'View')
  ), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000260201', '00000000-0000-0000-0000-000000260999', 'supreme');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000260202', '00000000-0000-0000-0000-000000260201', 'admin');

  -- One real 2-step sequential routing definition (manager then finance), the SAME
  -- shared tenant-wide config_type_code='approval' object every governed entity_type
  -- reuses (PRC-259's own migration header, mirrors procurement-approval.sql's own test
  -- setup exactly).
  select * into v_approval_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000260101', 'tenant admin');
  perform app.set_config_items(v_approval_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_manager_role::text, 'required_approvals', 1),
      jsonb_build_object('step_order', 2, 'approver_type', 'role', 'role_id', v_finance_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000260101', 'tenant admin');
  perform app.publish_approval_definition(v_approval_draft.id, '00000000-0000-0000-0000-000000260101', null, 'tenant admin');
end $$;

\echo '>> setup: two ACTIVE vendors in tenant1 (A payment_term_days=30, B payment_term_days=45)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000260101';
  v_profile app.vendor_profiles;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Po Vendor A', 'POA', 'PT', 'REG-PO-A', 'logistics', 30, 'staff_created', 'idem-po-vendor-a', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Ani A', 'Ops', 'ani@poa.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Po Vendor B', 'POB', 'PT', 'REG-PO-B', 'logistics', 45, 'staff_created', 'idem-po-vendor-b', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Budi B', 'Ops', 'budi@pob.test', '0812', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Gatot Subroto 2', 'Jakarta', 'DKI Jakarta', '10230', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
end $$;

\echo '>> sourcing (shortlist A/B) -> RFQ (issue invites A/B) -> two responses -> close for comparison -- one shared source pipeline every comparison in this file draws from'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000260101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_request app.sourcing_requests;
  v_candidate_a app.sourcing_candidates;
  v_candidate_b app.sourcing_candidates;
  v_vendor_a_master uuid;
  v_vendor_b_master uuid;
  v_rfq app.rfqs;
  v_invitation_a app.rfq_invitations;
  v_invitation_b app.rfq_invitations;
begin
  v_request := app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days',
    'IDR', 50000000, v_staff1, now() + interval '20 days', 'idem-po-sourcing-1', v_staff1, 'staff'
  );
  v_request := app.submit_sourcing_request(v_request.id, v_staff1, 'staff', v_request.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request.id, v_admin1, 'admin');

  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Po Vendor A';
  select master_record_id into v_vendor_b_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Po Vendor B';

  select * into v_candidate_a from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor_a_master;
  select * into v_candidate_b from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor_b_master;

  v_candidate_a := app.shortlist_sourcing_candidate(v_candidate_a.id, true, 'fit', v_staff1, 'staff', v_candidate_a.record_version);
  v_candidate_b := app.shortlist_sourcing_candidate(v_candidate_b.id, true, 'fit', v_staff1, 'staff', v_candidate_b.record_version);

  v_request := app.submit_sourcing_shortlist(v_request.id, v_staff1, 'staff', v_request.record_version);

  v_rfq := app.draft_rfq_from_sourcing(v_tenant1, v_request.id, v_staff1, 'idem-po-rfq-1', v_staff1, 'staff');
  v_rfq := app.issue_rfq(v_rfq.id, now() + interval '5 days', v_rfq.record_version, v_staff1, 'staff');

  select * into v_invitation_a from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_a_master;
  select * into v_invitation_b from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor_b_master;

  perform app.submit_rfq_response(v_invitation_a.id, 'IDR', 15000000, now() + interval '30 days', 20, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-po-resp-a', v_staff1, 'staff');
  perform app.submit_rfq_response(v_invitation_b.id, 'IDR', 16500000, now() + interval '30 days', 25, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-po-resp-b', v_staff1, 'staff');

  v_rfq := app.close_rfq_for_comparison(v_rfq.id, v_rfq.record_version, v_staff1, 'staff');
  if v_rfq.status <> 'closed' then
    raise exception 'assertion failed: expected rfq to be closed, got %', v_rfq.status;
  end if;
end $$;

\echo '>> comparison-1 (select vendor A): create/recommend/submit -- terminal submitted, approval_status not_required (no vendor_selection policy published)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000260103';
  v_rfq_id uuid;
  v_vendor_a_master uuid;
  v_comparison app.vendor_comparisons;
  v_a_offer app.vendor_comparison_offers;
begin
  select id into v_rfq_id from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-po-rfq-1';
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Po Vendor A';

  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, null, 'idem-po-cmp-1', v_staff1, 'staff');
  select * into v_a_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_a_master;
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_a_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
  v_comparison := app.submit_vendor_comparison_for_approval(v_comparison.id, v_a_offer.id, null, v_comparison.record_version, v_approver1, 'approver');
  if v_comparison.status <> 'submitted' or v_comparison.approval_status <> 'not_required' then
    raise exception 'assertion failed: expected status=submitted approval_status=not_required, got %/%', v_comparison.status, v_comparison.approval_status;
  end if;
end $$;

\echo '>> comparison-x (recommended, NOT submitted) -- used only for the invalid_source_status check below'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_rfq_id uuid;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
begin
  select id into v_rfq_id from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-po-rfq-1';
  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, null, 'idem-po-cmp-x', v_staff1, 'staff');
  select * into v_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id order by normalized_amount asc limit 1;
  perform app.recommend_vendor_comparison_offer(v_comparison.id, v_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
end $$;

-- ===========================================================================
-- app.draft_purchase_order_from_selection
-- ===========================================================================

\echo '>> app.draft_purchase_order_from_selection: permission-denied (Create-less viewer, View-cost-less editor, FIN:View-less financeless with a tax code), invalid_source_status (recommended-not-submitted comparison), idempotency_key_required, then a real draft inheriting vendor As payment terms, exact subtotal/total, and snapshotted lines'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000260105';
  v_editor1 uuid := '00000000-0000-0000-0000-000000260104';
  v_financeless1 uuid := '00000000-0000-0000-0000-000000260106';
  v_comparison1_id uuid;
  v_comparisonx_id uuid;
  v_po app.purchase_orders;
  v_line_count integer;
  v_failed boolean;
begin
  select id into v_comparison1_id from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-po-cmp-1';
  select id into v_comparisonx_id from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-po-cmp-x';

  v_failed := false;
  begin
    perform app.draft_purchase_order_from_selection(v_tenant1, v_comparison1_id, 'idem-po-denied-viewer', v_viewer1, 'viewer', null, null, null, null, null, null, null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%PRC:Create%' then
      raise exception 'assertion failed: expected insufficient_authority (PRC:Create) for the Create-less viewer, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the Create-less viewer to be denied'; end if;

  v_failed := false;
  begin
    perform app.draft_purchase_order_from_selection(v_tenant1, v_comparison1_id, 'idem-po-denied-editor', v_editor1, 'editor', null, null, null, null, null, null, null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%PRC:View cost%' then
      raise exception 'assertion failed: expected insufficient_authority (PRC:View cost) for the View-cost-less editor, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the View-cost-less editor to be denied'; end if;

  v_failed := false;
  begin
    perform app.draft_purchase_order_from_selection(v_tenant1, v_comparison1_id, 'idem-po-denied-financeless', v_financeless1, 'financeless', 'PPN', null, null, null, null, null, null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%FIN:View%' then
      raise exception 'assertion failed: expected insufficient_authority (FIN:View) for the FIN-less actor supplying a tax code, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the FIN:View-less actor with a tax code to be denied'; end if;

  v_failed := false;
  begin
    perform app.draft_purchase_order_from_selection(v_tenant1, v_comparisonx_id, 'idem-po-bad-source-status', v_staff1, 'staff', null, null, null, null, null, null, null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_source_status:%' then
      raise exception 'assertion failed: expected invalid_source_status for a recommended-not-submitted comparison, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected drafting from a non-submitted comparison to be rejected'; end if;

  v_failed := false;
  begin
    perform app.draft_purchase_order_from_selection(v_tenant1, v_comparison1_id, '', v_staff1, 'staff', null, null, null, null, null, null, null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_required:%' then
      raise exception 'assertion failed: expected idempotency_key_required, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an empty idempotency key to be rejected'; end if;

  v_po := app.draft_purchase_order_from_selection(v_tenant1, v_comparison1_id, 'idem-po-draft-1', v_staff1, 'staff', null, null, '2026-09-01', null, null, 'FOB Jakarta', 'first PO');
  if v_po.status <> 'draft' or v_po.po_number is null or v_po.currency <> 'IDR' or v_po.subtotal_amount <> 15000000 or v_po.tax_amount <> 0 or v_po.total_amount <> 15000000 then
    raise exception 'assertion failed: expected a draft PO with po_number set, currency=IDR, subtotal=total=15000000, tax=0, got status=% po_number=% currency=% subtotal=% tax=% total=%', v_po.status, v_po.po_number, v_po.currency, v_po.subtotal_amount, v_po.tax_amount, v_po.total_amount;
  end if;
  if v_po.payment_term_days <> 30 then
    raise exception 'assertion failed: expected payment_term_days inherited from vendor A (30), got %', v_po.payment_term_days;
  end if;
  if v_po.approval_status <> 'not_required' then
    raise exception 'assertion failed: expected a fresh draft to carry approval_status=not_required (no routing yet -- that happens at submit), got %', v_po.approval_status;
  end if;

  select count(*) into v_line_count from app.purchase_order_lines where purchase_order_id = v_po.id;
  if v_line_count <> 1 then
    raise exception 'assertion failed: expected exactly one snapshotted line (the RFQs own single auto-populated requirement line), got %', v_line_count;
  end if;
end $$;

\echo '>> idempotency replay: same key + identical tuple returns the SAME row; same key + a different tuple field raises idempotency_key_conflict (taxonomy C-01)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_comparison1_id uuid;
  v_po1 app.purchase_orders;
  v_po2 app.purchase_orders;
begin
  select id into v_comparison1_id from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-po-cmp-1';

  v_po1 := app.draft_purchase_order_from_selection(v_tenant1, v_comparison1_id, 'idem-po-draft-1', v_staff1, 'staff', null, null, '2026-09-01', null, null, 'FOB Jakarta', 'first PO');
  v_po2 := app.draft_purchase_order_from_selection(v_tenant1, v_comparison1_id, 'idem-po-draft-1', v_staff1, 'staff', null, null, '2026-09-01', null, null, 'FOB Jakarta', 'first PO');
  if v_po1.id <> v_po2.id then
    raise exception 'assertion failed: expected the identical-tuple replay to return the SAME row';
  end if;

  begin
    perform app.draft_purchase_order_from_selection(v_tenant1, v_comparison1_id, 'idem-po-draft-1', v_staff1, 'staff', null, null, null, null, null, null, 'a completely different note');
    raise exception 'assertion failed: expected idempotency_key_conflict -- same key, different notes';
  exception
    when unique_violation then
      if sqlerrm not like 'idempotency_key_conflict:%' then
        raise exception 'assertion failed: expected idempotency_key_conflict, got %', sqlerrm;
      end if;
  end;
end $$;

\echo '>> duplicate_issue: a second draft attempt from the SAME already-consumed comparison (a fresh idempotency key) is rejected -- at most one active PO per comparison'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_comparison1_id uuid;
  v_failed boolean := false;
begin
  select id into v_comparison1_id from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-po-cmp-1';
  begin
    perform app.draft_purchase_order_from_selection(v_tenant1, v_comparison1_id, 'idem-po-draft-dup', v_staff1, 'staff', null, null, null, null, null, null, null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'duplicate_issue:%' then
      raise exception 'assertion failed: expected duplicate_issue, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a second draft from the same comparison to be rejected as duplicate_issue'; end if;
end $$;

\echo '>> cross-tenant: po2 staff cannot draft from po1s comparison (tenant_mismatch), and cannot read po1s PO by id (C-05: not_found, never a real-tenant-disclosing insufficient_authority)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'po2');
  v_staff2 uuid := '00000000-0000-0000-0000-000000260202';
  v_comparison1_id uuid;
  v_po1_id uuid;
  v_failed boolean;
begin
  select id into v_comparison1_id from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-po-cmp-1';
  select id into v_po1_id from app.purchase_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-po-draft-1';

  v_failed := false;
  begin
    perform app.draft_purchase_order_from_selection(v_tenant2, v_comparison1_id, 'idem-po-xtenant', v_staff2, 'staff2', null, null, null, null, null, null, null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'tenant_mismatch:%' then
      raise exception 'assertion failed: expected tenant_mismatch, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a cross-tenant draft attempt to be rejected'; end if;

  v_failed := false;
  begin
    perform app.get_purchase_order(v_po1_id, v_staff2);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'purchase_order_not_found:%' then
      raise exception 'assertion failed: expected purchase_order_not_found for the cross-tenant, zero-membership read (never insufficient_authority, which would disclose the real tenant_id), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the cross-tenant get_purchase_order to be denied'; end if;
end $$;

-- ===========================================================================
-- Lifecycle: submit -> issue -> (concurrent amend race) -> submit -> issue ->
-- acknowledge -> fulfillment -> cancel/amend blocked.
-- ===========================================================================

\echo '>> submit_purchase_order_for_approval: permission-denied (viewer, no Edit), stale_version, real submit (approval_status stays not_required, no purchase_order policy yet); issue_purchase_order: real issue'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000260105';
  v_po app.purchase_orders;
  v_failed boolean;
begin
  select * into v_po from app.purchase_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-po-draft-1';

  v_failed := false;
  begin
    perform app.submit_purchase_order_for_approval(v_po.id, v_po.record_version, v_viewer1, 'viewer');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority:%PRC:Edit%' then
      raise exception 'assertion failed: expected insufficient_authority (PRC:Edit), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the Edit-less viewer to be denied submit'; end if;

  v_failed := false;
  begin
    perform app.submit_purchase_order_for_approval(v_po.id, v_po.record_version + 99, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'stale_version:%' then
      raise exception 'assertion failed: expected stale_version, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a wrong expected_version to be rejected'; end if;

  v_po := app.submit_purchase_order_for_approval(v_po.id, v_po.record_version, v_staff1, 'staff');
  if v_po.status <> 'submitted' or v_po.approval_status <> 'not_required' then
    raise exception 'assertion failed: expected status=submitted approval_status=not_required, got %/%', v_po.status, v_po.approval_status;
  end if;

  v_po := app.issue_purchase_order(v_po.id, v_po.record_version, v_staff1, 'staff');
  if v_po.status <> 'issued' then
    raise exception 'assertion failed: expected status=issued, got %', v_po.status;
  end if;
end $$;

\echo '>> REAL two-process concurrent amend race: two independent psql sessions both call app.amend_purchase_order on the SAME issued PO with the SAME expected_version -- exactly one must succeed (creating a new draft version), the other must fail stale_version'
select id as race_po_id, record_version as race_po_version from app.purchase_orders where idempotency_key = 'idem-po-draft-1' \gset
select current_database() as pg_test_db \gset

\set race_sql_a 'select app.amend_purchase_order(''' :race_po_id ''', ' :race_po_version ', ''race leg A'', ''idem-po-race-a'', ''00000000-0000-0000-0000-000000260102'', ''staff'');'
\set race_sql_b 'select app.amend_purchase_order(''' :race_po_id ''', ' :race_po_version ', ''race leg B'', ''idem-po-race-b'', ''00000000-0000-0000-0000-000000260102'', ''staff'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-purchase-order-race-a.out
\setenv RACE_OUT_B /tmp/cargogrid-purchase-order-race-b.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_race_po_id uuid := (select id from app.purchase_orders where idempotency_key = 'idem-po-draft-1');
  v_superseded_status text;
  v_new_version_count integer;
begin
  select status into v_superseded_status from app.purchase_orders where id = v_race_po_id;
  if v_superseded_status <> 'superseded' then
    raise exception 'assertion failed: expected the raced PO to end up superseded (exactly one amend won), got %', v_superseded_status;
  end if;

  select count(*) into v_new_version_count from app.purchase_orders where revised_from_id = v_race_po_id;
  if v_new_version_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE new version to have been created by the race (never zero, never two), got % -- see /tmp/cargogrid-purchase-order-race-a.out and -b.out for both real process outcomes', v_new_version_count;
  end if;

  raise notice 'concurrent amend race proof: exactly 1 of 2 racing app.amend_purchase_order calls (same expected_version) created a new version -- the record_version-scoped UPDATE + post-UPDATE stale_version check correctly serialized two real, independent psql processes';
end $$;

\echo '>> the winning amended version: submit -> issue -> acknowledge -> fulfillment (partial -> fulfilled, monotonic) -> cancel/amend then blocked (fulfillment_in_progress)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_race_po_id uuid := (select id from app.purchase_orders where idempotency_key = 'idem-po-draft-1');
  v_po app.purchase_orders;
  v_failed boolean;
begin
  select * into v_po from app.purchase_orders where revised_from_id = v_race_po_id;
  if v_po.status <> 'draft' or v_po.version <> 2 then
    raise exception 'assertion failed: expected the new amended version to be draft v2, got status=% version=%', v_po.status, v_po.version;
  end if;

  v_po := app.submit_purchase_order_for_approval(v_po.id, v_po.record_version, v_staff1, 'staff');
  v_po := app.issue_purchase_order(v_po.id, v_po.record_version, v_staff1, 'staff');

  v_failed := false;
  begin
    perform app.acknowledge_purchase_order(v_po.id, v_po.record_version, '', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required for an empty acknowledgement note, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an empty acknowledgement note to be rejected'; end if;

  v_po := app.acknowledge_purchase_order(v_po.id, v_po.record_version, 'vendor confirmed by email', v_staff1, 'staff');
  if v_po.status <> 'acknowledged' then
    raise exception 'assertion failed: expected status=acknowledged, got %', v_po.status;
  end if;

  v_failed := false;
  begin
    perform app.record_purchase_order_fulfillment_status(v_po.id, v_po.record_version, 'fulfilled', '', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reason_required:%' then
      raise exception 'assertion failed: expected reason_required for an empty fulfillment_reference, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an empty fulfillment_reference to be rejected'; end if;

  v_po := app.record_purchase_order_fulfillment_status(v_po.id, v_po.record_version, 'partial', 'shipment SHP-001 departed', v_staff1, 'staff');
  if v_po.fulfillment_status <> 'partial' then
    raise exception 'assertion failed: expected fulfillment_status=partial, got %', v_po.fulfillment_status;
  end if;

  v_failed := false;
  begin
    perform app.cancel_purchase_order(v_po.id, v_po.record_version, 'trying to cancel mid-fulfillment', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'fulfillment_in_progress:%' then
      raise exception 'assertion failed: expected fulfillment_in_progress, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected cancel to be blocked once fulfillment has begun'; end if;

  v_failed := false;
  begin
    perform app.amend_purchase_order(v_po.id, v_po.record_version, 'trying to amend mid-fulfillment', 'idem-po-amend-blocked', v_staff1, 'staff', null, null, null, null, null, null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'fulfillment_in_progress:%' then
      raise exception 'assertion failed: expected fulfillment_in_progress, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected amend to be blocked once fulfillment has begun'; end if;

  v_po := app.record_purchase_order_fulfillment_status(v_po.id, v_po.record_version, 'fulfilled', 'shipment SHP-001 delivered, POD on file', v_staff1, 'staff');
  if v_po.fulfillment_status <> 'fulfilled' then
    raise exception 'assertion failed: expected fulfillment_status=fulfilled, got %', v_po.fulfillment_status;
  end if;

  v_failed := false;
  begin
    perform app.record_purchase_order_fulfillment_status(v_po.id, v_po.record_version, 'partial', 'trying to regress', v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'invalid_fulfillment_transition:%' then
      raise exception 'assertion failed: expected invalid_fulfillment_transition (monotonic, no regression), got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a fulfilled -> partial regression to be rejected'; end if;
end $$;

-- ===========================================================================
-- Governance-routed PO: comparison-2 (select vendor B), a published always_required
-- purchase_order policy, the full 2-step decide flow (reauth freshness, self checks).
-- ===========================================================================

\echo '>> comparison-2 (select vendor B): create/recommend/submit -- terminal submitted, approval_status not_required (no vendor_selection policy)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000260103';
  v_rfq_id uuid;
  v_vendor_b_master uuid;
  v_comparison app.vendor_comparisons;
  v_b_offer app.vendor_comparison_offers;
begin
  select id into v_rfq_id from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-po-rfq-1';
  select master_record_id into v_vendor_b_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Po Vendor B';

  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, null, 'idem-po-cmp-2', v_staff1, 'staff');
  select * into v_b_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_b_master;
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_b_offer.id, 'vendor B preferred for reliability despite a higher price', v_comparison.record_version, v_staff1, 'staff');
  v_comparison := app.submit_vendor_comparison_for_approval(v_comparison.id, v_b_offer.id, null, v_comparison.record_version, v_approver1, 'approver');
end $$;

\echo '>> published always_required purchase_order policy: submit_purchase_order_for_approval routes for real (approval_status=pending, entity_type=purchase_order); issue is blocked until both routing steps approve'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000260101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_comparison2_id uuid;
  v_policy app.procurement_approval_policies;
  v_po app.purchase_orders;
  v_failed boolean;
begin
  select * into v_policy from app.create_procurement_approval_policy_version(v_tenant1, 'purchase_order', null, true, v_admin1, 'admin');
  select * into v_policy from app.publish_procurement_approval_policy_version(v_policy.id, v_policy.record_version, null, v_admin1, 'admin');

  select id into v_comparison2_id from app.vendor_comparisons where tenant_id = v_tenant1 and idempotency_key = 'idem-po-cmp-2';
  v_po := app.draft_purchase_order_from_selection(v_tenant1, v_comparison2_id, 'idem-po-draft-2', v_staff1, 'staff', null, null, null, null, null, null, null);

  v_po := app.submit_purchase_order_for_approval(v_po.id, v_po.record_version, v_staff1, 'staff');
  if v_po.status <> 'submitted' or v_po.approval_status <> 'pending' or v_po.approval_request_id is null then
    raise exception 'assertion failed: expected status=submitted approval_status=pending approval_request_id set, got %/%/%', v_po.status, v_po.approval_status, v_po.approval_request_id;
  end if;
  if (select entity_type from app.approval_requests where id = v_po.approval_request_id) <> 'purchase_order'
    or (select entity_id from app.approval_requests where id = v_po.approval_request_id) <> v_po.id then
    raise exception 'assertion failed: expected the bound request to carry entity_type=purchase_order entity_id=%', v_po.id;
  end if;

  v_failed := false;
  begin
    perform app.issue_purchase_order(v_po.id, v_po.record_version, v_staff1, 'staff');
  exception when others then
    v_failed := true;
    if sqlerrm not like 'purchase_order_approval_pending:%' then
      raise exception 'assertion failed: expected purchase_order_approval_pending, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected issue to be blocked while governance approval is still pending'; end if;
end $$;

\echo '>> app.decide_purchase_order_approval_step: outsider denied deciding step 1; stale/future reauth rejected; manager approves step 1 (still pending); finance approves step 2 (approval_status syncs to approved); issue then succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000260107';
  v_manager1 uuid := '00000000-0000-0000-0000-000000260108';
  v_finance1 uuid := '00000000-0000-0000-0000-000000260109';
  v_po app.purchase_orders;
  v_step1_id uuid;
  v_step2_id uuid;
  v_failed boolean;
begin
  select * into v_po from app.purchase_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-po-draft-2';
  select id into v_step1_id from app.approval_request_steps where request_id = v_po.approval_request_id and step_order = 1;
  select id into v_step2_id from app.approval_request_steps where request_id = v_po.approval_request_id and step_order = 2;

  v_failed := false;
  begin
    perform app.decide_purchase_order_approval_step(v_step1_id, 'approved', v_outsider1, 'outsider', now(), null);
  exception
    when insufficient_privilege then
      v_failed := true;
  end;
  if not v_failed then raise exception 'assertion failed: expected insufficient_privilege -- outsider holds no manager/finance role assignment'; end if;

  v_failed := false;
  begin
    perform app.decide_purchase_order_approval_step(v_step1_id, 'approved', v_manager1, 'manager', now() - interval '10 minutes', null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reauth_required:%' then
      raise exception 'assertion failed: expected reauth_required for a stale (>5 minute) reauth timestamp, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a stale reauth timestamp to be rejected'; end if;

  v_failed := false;
  begin
    perform app.decide_purchase_order_approval_step(v_step1_id, 'approved', v_manager1, 'manager', now() + interval '1 minute', null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'reauth_required:%' then
      raise exception 'assertion failed: expected reauth_required for a future reauth timestamp, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a future reauth timestamp to be rejected'; end if;

  v_failed := false;
  begin
    perform app.decide_purchase_order_approval_step('00000000-0000-0000-0000-000000260999', 'approved', v_manager1, 'manager', now(), null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'approval_step_not_found:%' then
      raise exception 'assertion failed: expected approval_step_not_found (typed error) for a nonexistent step id, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a nonexistent approval step id to raise a typed not-found error'; end if;

  perform app.decide_purchase_order_approval_step(v_step1_id, 'approved', v_manager1, 'manager', now(), 'looks good');
  select * into v_po from app.purchase_orders where id = v_po.id;
  if v_po.approval_status <> 'pending' then
    raise exception 'assertion failed: expected approval_status to remain pending after only 1 of 2 required steps, got %', v_po.approval_status;
  end if;

  perform app.decide_purchase_order_approval_step(v_step2_id, 'approved', v_finance1, 'finance', now(), null);
  select * into v_po from app.purchase_orders where id = v_po.id;
  if v_po.approval_status <> 'approved' then
    raise exception 'assertion failed: expected approval_status=approved once every required step passed, got %', v_po.approval_status;
  end if;
  if v_po.status <> 'submitted' then
    raise exception 'assertion failed: expected status to remain submitted (the sync wrapper never itself performs a further release), got %', v_po.status;
  end if;

  v_po := app.issue_purchase_order(v_po.id, v_po.record_version, v_staff1, 'staff');
  if v_po.status <> 'issued' then
    raise exception 'assertion failed: expected issue to succeed once governance approval cleared, got %', v_po.status;
  end if;
end $$;

-- ===========================================================================
-- app.vendor_not_active -- comparison-3 (vendor A again), suspended AFTER submit but
-- BEFORE the PO is drafted.
-- ===========================================================================

\echo '>> vendor_not_active: comparison-3 selects a vendor that is suspended between comparison-submit and PO-draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000260101';
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000260103';
  v_rfq_id uuid;
  v_vendor_a_master uuid;
  v_vendor_a app.vendor_profiles;
  v_comparison app.vendor_comparisons;
  v_a_offer app.vendor_comparison_offers;
  v_failed boolean := false;
begin
  select id into v_rfq_id from app.rfqs where tenant_id = v_tenant1 and idempotency_key = 'idem-po-rfq-1';
  select master_record_id into v_vendor_a_master from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Po Vendor A';

  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq_id, 'IDR', null, null, null, null, 'idem-po-cmp-3', v_staff1, 'staff');
  select * into v_a_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor_a_master;
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_a_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
  v_comparison := app.submit_vendor_comparison_for_approval(v_comparison.id, v_a_offer.id, null, v_comparison.record_version, v_approver1, 'approver');

  select * into v_vendor_a from app.vendor_profiles where master_record_id = v_vendor_a_master;
  v_vendor_a := app.suspend_vendor_profile(v_vendor_a_master, v_vendor_a.record_version, 'fraud investigation', v_admin1, 'admin');

  begin
    perform app.draft_purchase_order_from_selection(v_tenant1, v_comparison.id, 'idem-po-draft-suspended-vendor', v_staff1, 'staff', null, null, null, null, null, null, null);
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_not_active:%' then
      raise exception 'assertion failed: expected vendor_not_active, got %', sqlerrm;
    end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected drafting a PO for a suspended vendor to be rejected'; end if;
end $$;

-- ===========================================================================
-- Reads
-- ===========================================================================

\echo '>> reads: get_purchase_order cost masking (View-cost-less editor sees non-cost fields, masked cost fields, cost_masked=true), list_purchase_orders excludes superseded by default, list_purchase_order_lines, get_purchase_order_history'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'po1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000260102';
  v_editor1 uuid := '00000000-0000-0000-0000-000000260104';
  v_po1_id uuid;
  v_masked record;
  v_list_count integer;
  v_superseded_seen boolean;
  v_history_count integer;
  v_row record;
begin
  select id into v_po1_id from app.purchase_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-po-draft-2';

  select * into v_masked from app.get_purchase_order(v_po1_id, v_editor1);
  if v_masked.cost_masked <> true or v_masked.currency is not null or v_masked.total_amount is not null then
    raise exception 'assertion failed: expected cost fields nulled and cost_masked=true for a View-cost-less caller, got cost_masked=% currency=% total_amount=%', v_masked.cost_masked, v_masked.currency, v_masked.total_amount;
  end if;
  if v_masked.status is null then
    raise exception 'assertion failed: expected non-cost fields (status) to remain visible to a View-cost-less caller';
  end if;

  -- PO-1's original draft version was superseded by the amend race above and is
  -- therefore excluded by default; PO-1 v2 and PO-2 remain -- exactly 2, not 3 (the
  -- suspended-vendor attempt never created a row at all).
  select count(*) into v_list_count from app.list_purchase_orders(v_tenant1, v_staff1, null, null, 50);
  if v_list_count < 2 then
    raise exception 'assertion failed: expected at least 2 non-superseded purchase orders listed, got %', v_list_count;
  end if;
  select bool_or(status = 'superseded') into v_superseded_seen from app.list_purchase_orders(v_tenant1, v_staff1, null, null, 50);
  if v_superseded_seen then
    raise exception 'assertion failed: expected list_purchase_orders with no status filter to exclude superseded versions by default';
  end if;

  perform app.list_purchase_order_lines(v_po1_id, v_staff1);

  select count(*) into v_history_count from app.get_purchase_order_history(v_po1_id, v_staff1);
  if v_history_count < 2 then
    raise exception 'assertion failed: expected at least 2 lifecycle events (draft, submitted) for PO %, got %', v_po1_id, v_history_count;
  end if;

  begin
    perform app.list_purchase_orders(v_tenant1, v_staff1, 'not_a_real_status', null, 50);
    raise exception 'assertion failed: expected invalid_status_filter';
  exception when others then
    if sqlerrm not like 'invalid_status_filter:%' then
      raise exception 'assertion failed: expected invalid_status_filter, got %', sqlerrm;
    end if;
  end;
end $$;
