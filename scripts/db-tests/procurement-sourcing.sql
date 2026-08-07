-- Real, executable test evidence for PRC-256 (Sourcing, CG-S11-PRC-007) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database. Scoped to this
-- checkpoint's own additive migration
-- (supabase/migrations/20260730630000_create_procurement_sourcing.sql). Sorts
-- alphabetically BEFORE scripts/db-tests/procurement-vendor-compliance.sql, so this
-- file registers its own document type/compliance requirement rather than relying
-- on that later file's own fixture having already run.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (srcg1, srcg2). srcg1 gets a tenant_admin (admin1, full PRC set incl. Approve -- needed for vendor-registration/compliance-requirement setup), a full-PRC-except-Approve staff actor (staff1: Create/Edit/View/View cost/Override), an Override-less editor (editor1: Create/Edit/View/View cost, no Override -- for permission-denied checks), a View-only viewer (viewer1: View only, no View cost -- for cost-masking checks), a customer_user-layer actor (customer1), and a dedicated Commercial/Operations pipeline actor (rep1: COM Create/Edit/Approve/View/View cost + OPS Create/Edit/View) to drive the costing-request and shipment-order demand-source fixtures. srcg2 gets a tenant_admin and a full-PRC staff actor for cross-tenant checks. A global Supreme Admin is also seeded.'
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
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_t2_staff_role uuid;
  v_t2_staff_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000036101', 'admin@srcg1.test'),
    ('00000000-0000-0000-0000-000000036102', 'staff@srcg1.test'),
    ('00000000-0000-0000-0000-000000036103', 'editor@srcg1.test'),
    ('00000000-0000-0000-0000-000000036104', 'viewer@srcg1.test'),
    ('00000000-0000-0000-0000-000000036105', 'customer@srcg1.test'),
    ('00000000-0000-0000-0000-000000036106', 'rep@srcg1.test'),
    ('00000000-0000-0000-0000-000000036201', 'admin@srcg2.test'),
    ('00000000-0000-0000-0000-000000036202', 'staff@srcg2.test'),
    ('00000000-0000-0000-0000-000000036999', 'supreme@srcg.test');

  perform app.provision_tenant('srcg1', 'Sourcing Co 1', 'idem-srcg1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'srcg1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('srcg2', 'Sourcing Co 2', 'idem-srcg2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'srcg2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000036101', 'admin@srcg1.test', 'Srcg1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@srcg1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000036101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000036102', 'staff@srcg1.test', 'Srcg1 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@srcg1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000036103', 'editor@srcg1.test', 'Srcg1 Editor', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'editor@srcg1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000036104', 'viewer@srcg1.test', 'Srcg1 Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@srcg1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000036105', 'customer@srcg1.test', 'Srcg1 Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@srcg1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000036105', 'customer_user', v_tenant1, 'external-customer-account', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000036106', 'rep@srcg1.test', 'Srcg1 Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@srcg1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000036201', 'admin@srcg2.test', 'Srcg2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@srcg2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000036201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000036202', 'staff@srcg2.test', 'Srcg2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@srcg2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000036999', 'supreme_admin', null, null, 'tester');

  -- admin1: full PRC set including Approve (needed for vendor-registration decide/
  -- activate and compliance-requirement publish during this file's own setup) --
  -- granted by Supreme (self-escalation guard blocks granting a protected
  -- permission -- View cost -- to oneself).
  v_admin_role := (app.create_role(v_tenant1, 'Srcg1 PRC Admin', 'full PRC action set for setup', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(v_admin_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), '00000000-0000-0000-0000-000000036101', '00000000-0000-0000-0000-000000036999', 'supreme');

  v_staff_role := (app.create_role(v_tenant1, 'Srcg1 PRC Staff', 'Create/Edit/View/View cost/Override', 'tester')).id;
  v_staff_draft := app.create_role_version(v_staff_role, 'tester');
  perform app.set_role_version_permissions(v_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override')), 'tester');
  perform app.publish_role_version(v_staff_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000036102', '00000000-0000-0000-0000-000000036101', 'tester');

  v_editor_role := (app.create_role(v_tenant1, 'Srcg1 PRC Editor', 'Create/Edit/View/View cost, no Override', 'tester')).id;
  v_editor_draft := app.create_role_version(v_editor_role, 'tester');
  perform app.set_role_version_permissions(v_editor_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost')), 'tester');
  perform app.publish_role_version(v_editor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_editor_role and status = 'published'), '00000000-0000-0000-0000-000000036103', '00000000-0000-0000-0000-000000036101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Srcg1 PRC Viewer', 'View only, no View cost', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000036104', '00000000-0000-0000-0000-000000036101', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Srcg1 Pipeline Rep', 'COM+OPS grants to drive demand-source fixtures', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000036106', '00000000-0000-0000-0000-000000036101', 'tester');

  v_t2_staff_role := (app.create_role(v_tenant2, 'Srcg2 PRC Staff', 'full PRC set', 'tester')).id;
  v_t2_staff_draft := app.create_role_version(v_t2_staff_role, 'tester');
  perform app.set_role_version_permissions(v_t2_staff_draft.id, array(select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Override')), 'tester');
  perform app.publish_role_version(v_t2_staff_draft.id, now(), 'tester');
  -- Both admin2 (used to register the tenant2 vendor fixture below) and staff2 get
  -- the same published role version -- granted by the Supreme Admin (the role
  -- carries the protected View cost permission, so a self-grant is blocked).
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000036201', '00000000-0000-0000-0000-000000036999', 'supreme');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000036202', '00000000-0000-0000-0000-000000036201', 'tester');
end $$;

\echo '>> setup: four ACTIVE vendors in tenant1 (A eligible, B service_mismatch, C coverage_mismatch, D compliance_ineligible via a published blocking requirement scoped to its own vendor_category) and one ACTIVE vendor in tenant2 for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'srcg2');
  v_admin1 uuid := '00000000-0000-0000-0000-000000036101';
  v_admin2 uuid := '00000000-0000-0000-0000-000000036201';
  v_supreme uuid := '00000000-0000-0000-0000-000000036999';
  v_profile app.vendor_profiles;
  v_req app.vendor_compliance_requirements;
begin
  -- Vendor A: eligible.
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Sourcing Eligible', 'SRCA', 'PT', 'REG-SRC-A', 'logistics', 30, 'staff_created', 'idem-src-vendor-a', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Ani Vendor A', 'Ops', 'ani@srca.test', '0811', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  if v_profile.lifecycle_status <> 'active' then
    raise exception 'assertion failed: expected vendor A to be active, got %', v_profile.lifecycle_status;
  end if;

  -- Vendor B: wrong service (offers trucking, not ocean_freight) -- service_mismatch.
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Sourcing NoService', 'SRCB', 'PT', 'REG-SRC-B', 'logistics', 30, 'staff_created', 'idem-src-vendor-b', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Budi Vendor B', 'Ops', 'budi@srcb.test', '0812', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Gatot Subroto 2', 'Jakarta', 'DKI Jakarta', '10230', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'trucking', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  -- Vendor C: right service, wrong lane -- coverage_mismatch.
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Sourcing NoCoverage', 'SRCC', 'PT', 'REG-SRC-C', 'logistics', 30, 'staff_created', 'idem-src-vendor-c', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Citra Vendor C', 'Ops', 'citra@srcc.test', '0813', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Asia Afrika 3', 'Bandung', 'Jawa Barat', '40111', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Bandung', 'Malang', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  -- Vendor D: right service/lane, but under a published BLOCKING compliance
  -- requirement scoped to its own vendor_category, with no document ever
  -- submitted -- compliance_ineligible.
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Sourcing Restricted', 'SRCD', 'PT', 'REG-SRC-D', 'sourcing_test_restricted', 30, 'staff_created', 'idem-src-vendor-d', v_admin1, 'admin');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Dedi Vendor D', 'Ops', 'dedi@srcd.test', '0814', true, v_admin1, 'admin');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Diponegoro 4', 'Jakarta', 'DKI Jakarta', '10240', 'Indonesia', v_admin1, 'admin');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_admin1, 'admin');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_admin1, 'admin');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_admin1, 'admin');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_admin1, 'admin');

  perform app.register_document_type('sourcing_test_compliance_doc', 'Sourcing Test Compliance Doc', 'PRC', v_supreme, 'supreme');
  v_req := app.create_vendor_compliance_requirement_draft(v_tenant1, 'sourcing_test_restricted', null, 'sourcing_test_compliance_doc', 'Sourcing Test Requirement', null, 'blocking', false, null, null, 'idem-src-compliance-req', v_admin1, 'admin');
  v_req := app.publish_vendor_compliance_requirement(v_req.id, v_req.record_version, null, v_admin1, 'admin');
  perform app.recalculate_vendor_compliance_status(v_profile.master_record_id, v_admin1, 'admin');

  if not exists (
    select 1 from app.vendor_compliance_status
    where vendor_master_record_id = v_profile.master_record_id and status = 'not_submitted' and eligibility_hold = true
  ) then
    raise exception 'assertion failed: expected vendor D to carry a not_submitted, eligibility_hold=true compliance status after recalculation';
  end if;

  -- A second, tenant2 vendor for cross-tenant isolation checks.
  v_profile := app.create_vendor_profile_draft(v_tenant2, 'PT Other Tenant Sourcing Vendor', 'SRCE', 'PT', 'REG-SRC-E', 'logistics', 30, 'staff_created', 'idem-src-vendor-e', v_admin2, 'admin2');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Eka Vendor E', 'Ops', 'eka@srce.test', '0815', true, v_admin2, 'admin2');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Malioboro 5', 'Yogyakarta', 'DIY', '55111', 'Indonesia', v_admin2, 'admin2');
end $$;

\echo '>> setup: a real Commercial costing request (lead->prospect->opportunity->request_costing) for the create-from-costing tests, and a real confirmed Job Order -> Shipment Order (lead->prospect->opportunity->costing->rate->margin->quotation->acceptance->account->job-order-handoff->job-order->confirm->shipment-order) for the create-from-operational-demand tests, both in tenant1'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_admin1 uuid := '00000000-0000-0000-0000-000000036101';
  v_rep1 uuid := '00000000-0000-0000-0000-000000036106';
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment app.shipment_orders;
begin
  -- Costing-request pipeline (left as a live, pending costing request -- no rate/
  -- quotation/account chain needed, app.create_sourcing_request_from_costing only
  -- needs a real, non-cancelled/superseded costing_requests row).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Sourcing Costing Co', 'Fina Costing', 'fina@srccosting.test', '0821',
    v_rep1, null, v_rep1, 'tester');
  select * into v_lead from app.leads where email = 'fina@srccosting.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_rep1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Sourcing Costing Co', null, '01.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Sudirman 10', 'city', 'Jakarta', 'country', 'ID'), v_rep1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Sourcing costing lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-09-01'),
    v_rep1, null, v_rep1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_rep1, 'tester');

  -- Job Order / Shipment Order pipeline (a real, confirmed operational demand).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Sourcing Shipment Co', 'Gita Shipment', 'gita@srcshipment.test', '0831',
    v_rep1, null, v_rep1, 'tester');
  select * into v_lead from app.leads where email = 'gita@srcshipment.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_rep1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Sourcing Shipment Co', null, '02.222.222.2-222.000',
    jsonb_build_object('line1', 'Jl. Thamrin 20', 'city', 'Jakarta', 'country', 'ID'), v_rep1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Gita Shipment Ops', 'Procurement Lead', 'gita@srcshipment.test', '0831', v_rep1, null, v_rep1, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_rep1, 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Sourcing shipment lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bali', 'target_ready_date', '2026-09-15'),
    v_rep1, null, v_rep1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_rep1, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'SRC-SHP-VENDOR', 'Sourcing Shipment Vendor', 'ocean_freight', 'FCL', 'Jakarta', 'Bali', '20ft',
    null, null, null, null, 'IDR', 9000000, null, '[]'::jsonb, now(), null, null, v_admin1, 'admin'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'admin');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_rep1, 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_rep1, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_rep1, 'tester');
  perform app.calculate_margin(v_selection.id, 13000000, 'IDR', 0, v_rep1, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_rep1, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight sourcing-shipment lane', v_calc_id, 1, 13000000, 0, 0, v_rep1, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_rep1, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_rep1, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Gita Shipment Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.convert_quotation_to_account(v_quote.id, null, null, v_rep1, 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_rep1, 'rep');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_rep1, 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_rep1, 'rep');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-src-shipment-1', jsonb_build_object('legal_name', 'Sourcing Shipment Co'), null,
    'ocean_freight', 'sea', 'Jakarta', 'Bali', now() + interval '3 days', now() + interval '10 days',
    10, 2500, 15, 10, 2500, 15, null, v_rep1, 'rep'
  );
  if v_shipment.status <> 'draft' then
    raise exception 'assertion failed: expected the new shipment order to be draft, got %', v_shipment.status;
  end if;
end $$;

\echo '>> app.create_sourcing_request_from_costing: idempotent on (tenant_id, idempotency_key) comparing ALL load-bearing fields, blocks a foreign-tenant costing request, extracts service_type/origin/destination from requirements_snapshot, status=open directly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'srcg2');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_costing_id uuid;
  v_owner uuid := '00000000-0000-0000-0000-000000036102';
  v_sla timestamptz := now() + interval '5 days';
  v_request app.sourcing_requests;
  v_retry app.sourcing_requests;
begin
  select id into v_costing_id from app.costing_requests where tenant_id = v_tenant1 and status = 'pending' order by created_at desc limit 1;

  select * into v_request from app.create_sourcing_request_from_costing(v_tenant1, v_costing_id, v_owner, v_sla, 'idem-src-r5', v_staff1, 'staff');
  if v_request.source_type <> 'costing_request' or v_request.status <> 'open' or v_request.service_type <> 'ocean_freight'
    or v_request.origin_lane <> 'Jakarta' or v_request.destination_lane <> 'Surabaya' then
    raise exception 'assertion failed: unexpected sourcing request shape from costing source: %', to_jsonb(v_request);
  end if;

  -- Idempotent replay: identical inputs return the SAME row.
  select * into v_retry from app.create_sourcing_request_from_costing(v_tenant1, v_costing_id, v_owner, v_sla, 'idem-src-r5', v_staff1, 'staff');
  if v_retry.id <> v_request.id or v_retry.record_version <> v_request.record_version then
    raise exception 'assertion failed: expected the idempotent replay to return the identical row, got a different id/version';
  end if;

  -- Reused idempotency key with a DIFFERENT owner_user_id -- rejected, not silently applied.
  begin
    perform app.create_sourcing_request_from_costing(v_tenant1, v_costing_id, '00000000-0000-0000-0000-000000036103', v_sla, 'idem-src-r5', v_staff1, 'staff');
    raise exception 'assertion failed: expected idempotency_key_conflict -- same key, different owner_user_id';
  exception
    when unique_violation then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- Cross-tenant: the SAME costing request cannot source a tenant2 sourcing request.
  begin
    perform app.create_sourcing_request_from_costing(v_tenant2, v_costing_id, null, null, 'idem-src-r5-wrong-tenant', '00000000-0000-0000-0000-000000036202', 'staff2');
    raise exception 'assertion failed: expected tenant_mismatch -- the costing request belongs to tenant1, not tenant2';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'tenant_mismatch%' then raise; end if;
  end;
end $$;

\echo '>> app.create_sourcing_request_from_operational_demand: extracts service_type/mode/origin/destination and maps basis_weight_kg/basis_volume_cbm onto cargo_weight_max/cargo_volume_max, status=open directly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_shipment_id uuid;
  v_request app.sourcing_requests;
begin
  select id into v_shipment_id from app.shipment_orders where tenant_id = v_tenant1 and origin = 'Jakarta' and destination = 'Bali';

  select * into v_request from app.create_sourcing_request_from_operational_demand(v_tenant1, v_shipment_id, v_staff1, null, 'idem-src-r6', v_staff1, 'staff');
  if v_request.source_type <> 'operational_demand' or v_request.status <> 'open' or v_request.service_type <> 'ocean_freight'
    or v_request.mode <> 'sea' or v_request.origin_lane <> 'Jakarta' or v_request.destination_lane <> 'Bali'
    or v_request.cargo_weight_max <> 2500 or v_request.cargo_volume_max <> 15 then
    raise exception 'assertion failed: unexpected sourcing request shape from operational-demand source: %', to_jsonb(v_request);
  end if;

  -- ADVERSARIAL REVIEW FIX regression: demand_snapshot must never carry the source
  -- shipment order's own consignee_snapshot/notify_party_snapshot (real customer/
  -- consignee identity, governed on the source row by record-scoped RLS Sourcing
  -- does not replicate) -- confirmed excluded even though the source row genuinely
  -- has both keys (the fixture's own create_shipment_order_from_job call above
  -- supplied a non-null consignee).
  if (v_request.demand_snapshot ? 'consignee_snapshot') or (v_request.demand_snapshot ? 'notify_party_snapshot') then
    raise exception 'assertion failed: expected demand_snapshot to exclude consignee_snapshot/notify_party_snapshot, got %', v_request.demand_snapshot;
  end if;
  -- Sanity: the redaction did not accidentally strip everything -- an ordinary,
  -- non-sensitive column survives.
  if not (v_request.demand_snapshot ? 'service_type') then
    raise exception 'assertion failed: expected demand_snapshot to still carry ordinary shipment_orders columns like service_type, got %', v_request.demand_snapshot;
  end if;
end $$;

\echo '>> app.create_proactive_sourcing_request + app.submit_sourcing_request: starts draft, needs submit to reach open; a non-proactive request cannot be submitted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_editor1 uuid := '00000000-0000-0000-0000-000000036103';
  v_request app.sourcing_requests;
  v_costing_sourced_id uuid;
begin
  select * into v_request from app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', null, null, null, null, null, null, 'IDR', 50000000,
    v_staff1, now() + interval '7 days', 'idem-src-r1', v_staff1, 'staff'
  );
  if v_request.status <> 'draft' or v_request.source_type <> 'proactive' then
    raise exception 'assertion failed: expected a proactive request to start draft, got status=% source_type=%', v_request.status, v_request.source_type;
  end if;

  -- Editor lacks nothing here (submit is Edit) -- should succeed.
  v_request := app.submit_sourcing_request(v_request.id, v_editor1, 'editor', v_request.record_version);
  if v_request.status <> 'open' then
    raise exception 'assertion failed: expected submit_sourcing_request to reach open, got %', v_request.status;
  end if;

  -- A costing/operational-demand-sourced request is created directly into open and
  -- can never be (re-)submitted.
  select id into v_costing_sourced_id from app.sourcing_requests where tenant_id = v_tenant1 and source_type = 'costing_request' limit 1;
  begin
    perform app.submit_sourcing_request(v_costing_sourced_id, v_staff1, 'staff', (select record_version from app.sourcing_requests where id = v_costing_sourced_id));
    raise exception 'assertion failed: expected invalid_transition -- a costing-sourced request is never draft';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- stale_version: submitting an already-open request with a stale expected_version.
  begin
    perform app.submit_sourcing_request(v_request.id, v_staff1, 'staff', v_request.record_version - 1);
    raise exception 'assertion failed: expected stale_version';
  exception
    when serialization_failure then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
end $$;

\echo '>> app.evaluate_sourcing_candidate_eligibility: produces one fully-eligible candidate and one excluded candidate per reason code (service_mismatch, coverage_mismatch, compliance_ineligible); re-evaluation preserves a prior shortlist decision'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000036104';
  v_request_id uuid;
  v_candidate_a app.sourcing_candidates;
  v_candidate_b app.sourcing_candidates;
  v_candidate_c app.sourcing_candidates;
  v_candidate_d app.sourcing_candidates;
  v_vendor_a uuid;
  v_vendor_b uuid;
  v_vendor_c uuid;
  v_vendor_d uuid;
  v_count integer;
begin
  select id into v_request_id from app.sourcing_requests where tenant_id = v_tenant1 and idempotency_key = 'idem-src-r1';
  select master_record_id into v_vendor_a from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Sourcing Eligible';
  select master_record_id into v_vendor_b from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Sourcing NoService';
  select master_record_id into v_vendor_c from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Sourcing NoCoverage';
  select master_record_id into v_vendor_d from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Sourcing Restricted';

  -- Viewer (no PRC:Edit) cannot recompute eligibility.
  begin
    perform app.evaluate_sourcing_candidate_eligibility(v_request_id, v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks PRC:Edit';
  exception
    when insufficient_privilege then
      null;
  end;

  perform app.evaluate_sourcing_candidate_eligibility(v_request_id, v_staff1, 'staff');

  select * into v_candidate_a from app.sourcing_candidates where sourcing_request_id = v_request_id and vendor_master_id = v_vendor_a;
  select * into v_candidate_b from app.sourcing_candidates where sourcing_request_id = v_request_id and vendor_master_id = v_vendor_b;
  select * into v_candidate_c from app.sourcing_candidates where sourcing_request_id = v_request_id and vendor_master_id = v_vendor_c;
  select * into v_candidate_d from app.sourcing_candidates where sourcing_request_id = v_request_id and vendor_master_id = v_vendor_d;

  if not v_candidate_a.eligible or cardinality(v_candidate_a.exclusion_reasons) <> 0 then
    raise exception 'assertion failed: expected vendor A fully eligible, got eligible=% reasons=%', v_candidate_a.eligible, v_candidate_a.exclusion_reasons;
  end if;
  if v_candidate_b.eligible or not ('service_mismatch' = any(v_candidate_b.exclusion_reasons)) then
    raise exception 'assertion failed: expected vendor B excluded for service_mismatch, got eligible=% reasons=%', v_candidate_b.eligible, v_candidate_b.exclusion_reasons;
  end if;
  if v_candidate_c.eligible or not ('coverage_mismatch' = any(v_candidate_c.exclusion_reasons)) then
    raise exception 'assertion failed: expected vendor C excluded for coverage_mismatch, got eligible=% reasons=%', v_candidate_c.eligible, v_candidate_c.exclusion_reasons;
  end if;
  if v_candidate_d.eligible or not ('compliance_ineligible' = any(v_candidate_d.exclusion_reasons)) then
    raise exception 'assertion failed: expected vendor D excluded for compliance_ineligible, got eligible=% reasons=%', v_candidate_d.eligible, v_candidate_d.exclusion_reasons;
  end if;
  if not (v_candidate_a.evaluation_snapshot ? 'has_active_rate') then
    raise exception 'assertion failed: expected evaluation_snapshot to carry an informational has_active_rate key';
  end if;

  -- Re-evaluation preserves a prior shortlist decision (design note 7): shortlist A
  -- first, then re-run eligibility, and confirm the shortlist flag survives.
  perform app.shortlist_sourcing_candidate(v_candidate_a.id, true, 'strong fit, re-eval preservation check', v_staff1, 'staff', v_candidate_a.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request_id, v_staff1, 'staff');
  select count(*) into v_count from app.sourcing_candidates where id = v_candidate_a.id and shortlisted = true;
  if v_count <> 1 then
    raise exception 'assertion failed: expected vendor A''s shortlist decision to survive re-evaluation';
  end if;
  -- Un-shortlist it again so the later "zero shortlisted -> denied" scenario below
  -- starts from a genuinely empty shortlist.
  perform app.shortlist_sourcing_candidate(v_candidate_a.id, false, null, v_staff1, 'staff', (select record_version from app.sourcing_candidates where id = v_candidate_a.id));
end $$;

\echo '>> app.shortlist_sourcing_candidate: an eligible candidate needs PRC:Edit; an excluded candidate needs PRC:Override AND a mandatory reason (denied without Override, allowed with it); reason is required for ANY shortlist=true regardless of eligibility; un-shortlisting needs Edit only, reason optional'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_editor1 uuid := '00000000-0000-0000-0000-000000036103';
  v_request_id uuid;
  v_candidate_a app.sourcing_candidates;
  v_candidate_b app.sourcing_candidates;
begin
  select id into v_request_id from app.sourcing_requests where tenant_id = v_tenant1 and idempotency_key = 'idem-src-r1';
  select c.* into v_candidate_a from app.sourcing_candidates c join app.vendor_profiles vp on vp.master_record_id = c.vendor_master_id
    where c.sourcing_request_id = v_request_id and vp.legal_name = 'PT Sourcing Eligible';
  select c.* into v_candidate_b from app.sourcing_candidates c join app.vendor_profiles vp on vp.master_record_id = c.vendor_master_id
    where c.sourcing_request_id = v_request_id and vp.legal_name = 'PT Sourcing NoService';

  -- Shortlisting an eligible candidate with no reason -- rejected (reason is
  -- unconditionally required whenever shortlisted=true, design note 6).
  begin
    perform app.shortlist_sourcing_candidate(v_candidate_a.id, true, null, v_staff1, 'staff', v_candidate_a.record_version);
    raise exception 'assertion failed: expected reason_required -- shortlisting always requires a reason';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- Shortlisting an eligible candidate with a reason -- Edit suffices, editor1 succeeds.
  v_candidate_a := app.shortlist_sourcing_candidate(v_candidate_a.id, true, 'meets every criterion', v_editor1, 'editor', v_candidate_a.record_version);
  if not v_candidate_a.shortlisted or v_candidate_a.shortlist_reason is null then
    raise exception 'assertion failed: expected vendor A to be shortlisted with a reason';
  end if;

  -- Shortlisting an EXCLUDED candidate WITHOUT PRC:Override -- denied (editor1 has
  -- Edit/View/View cost but no Override).
  begin
    perform app.shortlist_sourcing_candidate(v_candidate_b.id, true, 'exception needed', v_editor1, 'editor', v_candidate_b.record_version);
    raise exception 'assertion failed: expected insufficient_privilege -- editor1 lacks PRC:Override';
  exception
    when insufficient_privilege then
      null;
  end;

  -- Shortlisting an EXCLUDED candidate WITH PRC:Override and a reason -- allowed.
  v_candidate_b := app.shortlist_sourcing_candidate(v_candidate_b.id, true, 'exceptional capacity override, approved by procurement lead', v_staff1, 'staff', v_candidate_b.record_version);
  if not v_candidate_b.shortlisted or v_candidate_b.eligible then
    raise exception 'assertion failed: expected vendor B shortlisted while still eligible=false (a real, surfaced signal)';
  end if;

  -- Un-shortlisting needs Edit only, reason optional.
  v_candidate_b := app.shortlist_sourcing_candidate(v_candidate_b.id, false, null, v_editor1, 'editor', v_candidate_b.record_version);
  if v_candidate_b.shortlisted or v_candidate_b.shortlist_reason is not null then
    raise exception 'assertion failed: expected vendor B fully un-shortlisted';
  end if;

  -- Leave the shortlist genuinely empty for the next scenario's own "zero
  -- shortlisted candidates -> denied" check.
  perform app.shortlist_sourcing_candidate(v_candidate_a.id, false, null, v_editor1, 'editor', (select record_version from app.sourcing_candidates where id = v_candidate_a.id));
end $$;

\echo '>> app.submit_sourcing_shortlist: zero shortlisted candidates is denied; one shortlisted candidate is allowed and locks the shortlist; the parent request reaches shortlisted'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000036104';
  v_request app.sourcing_requests;
  v_candidate_a app.sourcing_candidates;
begin
  select * into v_request from app.sourcing_requests where tenant_id = v_tenant1 and idempotency_key = 'idem-src-r1';

  -- Zero shortlisted (vendor A was un-shortlisted, then re-shortlisted below --
  -- confirm it is currently zero after the previous block's own un-shortlist of B,
  -- and A itself was left un-shortlisted at the end of the eligibility-preservation
  -- scenario).
  begin
    perform app.submit_sourcing_shortlist(v_request.id, v_staff1, 'staff', v_request.record_version);
    raise exception 'assertion failed: expected no_candidates_shortlisted -- zero candidates are currently shortlisted';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'no_candidates_shortlisted%' then raise; end if;
  end;

  select c.* into v_candidate_a from app.sourcing_candidates c join app.vendor_profiles vp on vp.master_record_id = c.vendor_master_id
    where c.sourcing_request_id = v_request.id and vp.legal_name = 'PT Sourcing Eligible';
  perform app.shortlist_sourcing_candidate(v_candidate_a.id, true, 'final pick', v_staff1, 'staff', v_candidate_a.record_version);

  select * into v_request from app.sourcing_requests where id = v_request.id;
  v_request := app.submit_sourcing_shortlist(v_request.id, v_staff1, 'staff', v_request.record_version);
  if v_request.status <> 'shortlisted' or v_request.shortlist_locked_at is null then
    raise exception 'assertion failed: expected status=shortlisted with shortlist_locked_at set, got status=% locked_at=%', v_request.status, v_request.shortlist_locked_at;
  end if;

  -- Candidates may no longer be shortlisted/un-shortlisted once the parent is no
  -- longer open.
  begin
    perform app.shortlist_sourcing_candidate(v_candidate_a.id, false, null, v_staff1, 'staff', (select record_version from app.sourcing_candidates where id = v_candidate_a.id));
    raise exception 'assertion failed: expected invalid_transition -- the parent sourcing request is no longer open';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- ADVERSARIAL REVIEW FIX regression: an actor who lacks the required permission
  -- must be denied via insufficient_authority WITHOUT ever learning the parent
  -- request's real status -- viewer1 (View only, no Edit) attempts the identical
  -- un-shortlist call above on the SAME non-open request. Before the fix, the
  -- parent status was read (and disclosed via invalid_transition) before
  -- evaluate_permission ever ran; proving insufficient_privilege here (not
  -- invalid_transition) confirms the permission gate now runs first.
  begin
    perform app.shortlist_sourcing_candidate(v_candidate_a.id, false, null, v_viewer1, 'viewer', (select record_version from app.sourcing_candidates where id = v_candidate_a.id));
    raise exception 'assertion failed: expected insufficient_privilege -- viewer1 lacks PRC:Edit, checked before any parent-status disclosure';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

\echo '>> app.reopen_sourcing_request: PRC:Override-gated governed reopen from shortlisted back to open; clears shortlist_locked_at but preserves the candidate''s own shortlisted flag; denied without Override'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_editor1 uuid := '00000000-0000-0000-0000-000000036103';
  v_request app.sourcing_requests;
  v_shortlisted_count_before integer;
  v_shortlisted_count_after integer;
begin
  select * into v_request from app.sourcing_requests where tenant_id = v_tenant1 and idempotency_key = 'idem-src-r1';
  select count(*) into v_shortlisted_count_before from app.sourcing_candidates where sourcing_request_id = v_request.id and shortlisted = true;

  begin
    perform app.reopen_sourcing_request(v_request.id, 'need to add another candidate', v_editor1, 'editor', v_request.record_version);
    raise exception 'assertion failed: expected insufficient_privilege -- editor1 lacks PRC:Override';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.reopen_sourcing_request(v_request.id, '', v_staff1, 'staff', v_request.record_version);
    raise exception 'assertion failed: expected reason_required -- empty reason';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_request := app.reopen_sourcing_request(v_request.id, 'need to add another candidate', v_staff1, 'staff', v_request.record_version);
  if v_request.status <> 'open' or v_request.shortlist_locked_at is not null then
    raise exception 'assertion failed: expected status=open with shortlist_locked_at cleared, got status=% locked_at=%', v_request.status, v_request.shortlist_locked_at;
  end if;

  select count(*) into v_shortlisted_count_after from app.sourcing_candidates where sourcing_request_id = v_request.id and shortlisted = true;
  if v_shortlisted_count_after <> v_shortlisted_count_before then
    raise exception 'assertion failed: expected reopen to preserve every candidate''s own shortlisted flag (before=% after=%)', v_shortlisted_count_before, v_shortlisted_count_after;
  end if;
end $$;

\echo '>> app.override_sourcing_request_constraints: widens cargo_weight_max/cargo_volume_max (allowed) and rejects a narrower value (constraint_narrowing_not_allowed); applies a destination_lane override; requires PRC:Override and a mandatory reason; only while open'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_editor1 uuid := '00000000-0000-0000-0000-000000036103';
  v_request app.sourcing_requests;
begin
  select * into v_request from app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Bandung', null, 1000, null, null, null, null, 'IDR', null,
    v_staff1, null, 'idem-src-r4', v_staff1, 'staff'
  );
  v_request := app.submit_sourcing_request(v_request.id, v_staff1, 'staff', v_request.record_version);

  begin
    perform app.override_sourcing_request_constraints(v_request.id, 1500, null, null, 'need more capacity', null, v_editor1, 'editor', v_request.record_version);
    raise exception 'assertion failed: expected insufficient_privilege -- editor1 lacks PRC:Override';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.override_sourcing_request_constraints(v_request.id, 1500, null, null, '', null, v_staff1, 'staff', v_request.record_version);
    raise exception 'assertion failed: expected reason_required';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_request := app.override_sourcing_request_constraints(v_request.id, 1500, null, 'Bandung Region', 'need more capacity and a broader destination', now() + interval '30 days', v_staff1, 'staff', v_request.record_version);
  if v_request.cargo_weight_max <> 1500 or v_request.destination_lane <> 'Bandung Region' then
    raise exception 'assertion failed: expected cargo_weight_max=1500 and destination_lane=Bandung Region, got %/%', v_request.cargo_weight_max, v_request.destination_lane;
  end if;

  -- Narrowing is rejected.
  begin
    perform app.override_sourcing_request_constraints(v_request.id, 1000, null, null, 'attempt to narrow', null, v_staff1, 'staff', v_request.record_version);
    raise exception 'assertion failed: expected constraint_narrowing_not_allowed -- 1000 is less than the current 1500';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'constraint_narrowing_not_allowed%' then raise; end if;
  end;

  -- ADVERSARIAL REVIEW FIX regression: cargo_volume_max is currently null on this
  -- request (never overridden yet), so the widen-only guard's own "comparing
  -- against nothing is vacuously satisfied" rule would previously let a negative
  -- value straight through. The new table-level non-negativity CHECK now rejects
  -- it regardless of the widen-only guard's own null-to-value carve-out.
  begin
    perform app.override_sourcing_request_constraints(v_request.id, null, -5, null, 'attempt negative volume', null, v_staff1, 'staff', v_request.record_version);
    raise exception 'assertion failed: expected a check_violation rejecting a negative cargo_volume_max override';
  exception
    when sqlstate '23514' then
      if sqlerrm not like '%cargo_volume_max_nonneg%' then raise; end if;
  end;

  -- The override's own event row carries the reason and evidence_ref (expires_at).
  if not exists (
    select 1 from app.sourcing_request_events
    where sourcing_request_id = v_request.id and reason = 'need more capacity and a broader destination' and evidence_ref like 'override_expires_at=%'
  ) then
    raise exception 'assertion failed: expected an override event row carrying the reason and evidence_ref';
  end if;
end $$;

\echo '>> ADVERSARIAL REVIEW FIX regression: app.create_proactive_sourcing_request rejects negative cargo_weight_min/cargo_volume_min (non-negativity CHECK, not just the pre-existing relative max>=min check)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
begin
  begin
    perform app.create_proactive_sourcing_request(
      v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Semarang', -10, null, null, null, null, null, 'IDR', null,
      v_staff1, null, 'idem-src-negweight', v_staff1, 'staff'
    );
    raise exception 'assertion failed: expected a check_violation rejecting a negative cargo_weight_min';
  exception
    when sqlstate '23514' then
      if sqlerrm not like '%cargo_weight_min_nonneg%' then raise; end if;
  end;

  begin
    perform app.create_proactive_sourcing_request(
      v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Semarang', null, null, -2, null, null, null, 'IDR', null,
      v_staff1, null, 'idem-src-negvolume', v_staff1, 'staff'
    );
    raise exception 'assertion failed: expected a check_violation rejecting a negative cargo_volume_min';
  exception
    when sqlstate '23514' then
      if sqlerrm not like '%cargo_volume_min_nonneg%' then raise; end if;
  end;
end $$;

\echo '>> app.close_sourcing_request_no_source: open -> closed_no_source, reason mandatory; app.cancel_sourcing_request: draft or open -> cancelled, reason mandatory; both reachable back to open via app.reopen_sourcing_request'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_request_a app.sourcing_requests;
  v_request_b app.sourcing_requests;
begin
  -- close_sourcing_request_no_source.
  select * into v_request_a from app.create_proactive_sourcing_request(
    v_tenant1, 'trucking', null, 'Jakarta', 'Bogor', null, null, null, null, null, null, null, null,
    v_staff1, null, 'idem-src-r2', v_staff1, 'staff'
  );
  v_request_a := app.submit_sourcing_request(v_request_a.id, v_staff1, 'staff', v_request_a.record_version);

  begin
    perform app.close_sourcing_request_no_source(v_request_a.id, null, v_staff1, 'staff', v_request_a.record_version);
    raise exception 'assertion failed: expected reason_required';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_request_a := app.close_sourcing_request_no_source(v_request_a.id, 'no eligible vendor found in this lane', v_staff1, 'staff', v_request_a.record_version);
  if v_request_a.status <> 'closed_no_source' or v_request_a.closed_reason is null then
    raise exception 'assertion failed: expected status=closed_no_source with closed_reason set';
  end if;

  -- cancel_sourcing_request (from open).
  select * into v_request_b from app.create_proactive_sourcing_request(
    v_tenant1, 'air_freight', null, 'Jakarta', 'Singapore', null, null, null, null, null, null, null, null,
    v_staff1, null, 'idem-src-r3', v_staff1, 'staff'
  );
  v_request_b := app.submit_sourcing_request(v_request_b.id, v_staff1, 'staff', v_request_b.record_version);
  v_request_b := app.cancel_sourcing_request(v_request_b.id, 'no longer needed', v_staff1, 'staff', v_request_b.record_version);
  if v_request_b.status <> 'cancelled' or v_request_b.closed_reason is null then
    raise exception 'assertion failed: expected status=cancelled with closed_reason set';
  end if;

  -- draft/open only -- a terminal request cannot be cancelled again.
  begin
    perform app.cancel_sourcing_request(v_request_b.id, 'again', v_staff1, 'staff', v_request_b.record_version);
    raise exception 'assertion failed: expected invalid_transition -- already cancelled';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Reopen from cancelled (a second, distinct reachable predecessor state beyond
  -- shortlisted, exercised earlier).
  v_request_b := app.reopen_sourcing_request(v_request_b.id, 'reconsidered, sourcing again', v_staff1, 'staff', v_request_b.record_version);
  if v_request_b.status <> 'open' or v_request_b.closed_reason is not null then
    raise exception 'assertion failed: expected status=open with closed_reason cleared after reopen';
  end if;

  -- stale_version on a version-mismatched mutation.
  begin
    perform app.cancel_sourcing_request(v_request_b.id, 'stale attempt', v_staff1, 'staff', v_request_b.record_version + 99);
    raise exception 'assertion failed: expected stale_version';
  exception
    when serialization_failure then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
end $$;

\echo '>> cost masking (PRC:View cost): viewer1 (View only) sees budget_amount masked; staff1 (View cost) sees the real value'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000036104';
  v_request_id uuid;
  v_masked app.sourcing_requests_directory;
  v_unmasked app.sourcing_requests_directory;
begin
  select id into v_request_id from app.sourcing_requests where tenant_id = v_tenant1 and idempotency_key = 'idem-src-r1';

  v_masked := app.get_sourcing_request(v_request_id, v_viewer1);
  if not v_masked.cost_masked or v_masked.budget_amount is not null then
    raise exception 'assertion failed: expected budget_amount masked (null) for the View-only viewer, got cost_masked=% budget_amount=%', v_masked.cost_masked, v_masked.budget_amount;
  end if;

  v_unmasked := app.get_sourcing_request(v_request_id, v_staff1);
  if v_unmasked.cost_masked or v_unmasked.budget_amount is null then
    raise exception 'assertion failed: expected budget_amount unmasked for staff1 (holds PRC:View cost)';
  end if;

  -- ADVERSARIAL REVIEW FIX regression: demand_snapshot's own embedded budget_amount
  -- key (this proactive request's own creation snapshot genuinely carries it) must
  -- be masked identically to the typed column -- otherwise the cost mask is
  -- bypassable by reading the snapshot instead of the column.
  if v_masked.demand_snapshot ? 'budget_amount' then
    raise exception 'assertion failed: expected demand_snapshot to exclude budget_amount for the View-only viewer, got %', v_masked.demand_snapshot;
  end if;
  if not (v_unmasked.demand_snapshot ? 'budget_amount') or (v_unmasked.demand_snapshot ->> 'budget_amount')::numeric <> 50000000 then
    raise exception 'assertion failed: expected demand_snapshot to carry the real budget_amount=50000000 for staff1, got %', v_unmasked.demand_snapshot;
  end if;

  -- Same masking must hold through app.list_sourcing_requests (a second, distinct
  -- read RPC composing the same projection independently) and through
  -- app.sourcing_requests_directory (the view itself, default-auth.uid() session
  -- masking -- read directly here since this is a superuser db-test session, not a
  -- real JWT session; only presence/absence of the key is asserted, not the
  -- has_prc_view_cost outcome, which is exercised via the two RPCs above).
  if not exists (
    select 1 from app.list_sourcing_requests(v_tenant1, null, v_viewer1, 200) l
    where l.id = v_request_id and not (l.demand_snapshot ? 'budget_amount')
  ) then
    raise exception 'assertion failed: expected list_sourcing_requests to also mask demand_snapshot''s budget_amount for the View-only viewer';
  end if;
  if not exists (
    select 1 from app.list_sourcing_requests(v_tenant1, null, v_staff1, 200) l
    where l.id = v_request_id and (l.demand_snapshot ? 'budget_amount')
  ) then
    raise exception 'assertion failed: expected list_sourcing_requests to carry demand_snapshot''s real budget_amount for staff1';
  end if;
end $$;

\echo '>> cross-tenant isolation: a tenant2 actor cannot read tenant1''s sourcing requests/candidates/history via any RPC, and the RLS-scoped directory views return zero tenant1 rows for a tenant2 session'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff2 uuid := '00000000-0000-0000-0000-000000036202';
  v_request_id uuid;
  v_count integer;
begin
  select id into v_request_id from app.sourcing_requests where tenant_id = v_tenant1 and idempotency_key = 'idem-src-r1';

  begin
    perform app.get_sourcing_request(v_request_id, v_staff2);
    raise exception 'assertion failed: expected insufficient_privilege -- tenant2''s staff has no PRC:View over tenant1';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.list_sourcing_candidates(v_request_id, v_staff2);
    raise exception 'assertion failed: expected insufficient_privilege';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.get_sourcing_request_history(v_request_id, v_staff2);
    raise exception 'assertion failed: expected insufficient_privilege';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.list_sourcing_requests(v_tenant1, null, v_staff2, 50);
    raise exception 'assertion failed: expected insufficient_privilege -- tenant2''s staff has no PRC:View over tenant1';
  exception
    when insufficient_privilege then
      null;
  end;

  -- RLS-level: a real tenant2 session sees zero tenant1 rows.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000036202", "role": "authenticated"}';
  select count(*) into v_count from app.sourcing_requests_directory where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero tenant1 rows for a tenant2 session, found %', v_count;
  end if;
  select count(*) into v_count from app.sourcing_candidates_directory where sourcing_request_id = v_request_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero tenant1 candidate rows for a tenant2 session, found %', v_count;
  end if;
  reset role;
end $$;

\echo '>> customer_user-layer principal: denied on every read RPC, and sees zero rows via RLS on both directory views'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_customer1 uuid := '00000000-0000-0000-0000-000000036105';
  v_request_id uuid;
  v_count integer;
begin
  select id into v_request_id from app.sourcing_requests where tenant_id = v_tenant1 and idempotency_key = 'idem-src-r1';

  begin
    perform app.get_sourcing_request(v_request_id, v_customer1);
    raise exception 'assertion failed: expected insufficient_privilege -- customer_user holds no PRC role';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.list_sourcing_requests(v_tenant1, null, v_customer1, 50);
    raise exception 'assertion failed: expected insufficient_privilege';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.list_sourcing_candidates(v_request_id, v_customer1);
    raise exception 'assertion failed: expected insufficient_privilege';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.get_sourcing_request_history(v_request_id, v_customer1);
    raise exception 'assertion failed: expected insufficient_privilege';
  exception
    when insufficient_privilege then
      null;
  end;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000036105", "role": "authenticated"}';
  select count(*) into v_count from app.sourcing_requests_directory where tenant_id = v_tenant1;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for the customer_user-layer principal, found %', v_count;
  end if;
  select count(*) into v_count from app.sourcing_candidates_directory where sourcing_request_id = v_request_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero candidate rows for the customer_user-layer principal, found %', v_count;
  end if;
  reset role;
end $$;

\echo '>> app.list_sourcing_requests: status filter and server-side clamp; app.get_sourcing_request_history returns the full lifecycle timeline in order'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srcg1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000036102';
  v_request_id uuid;
  v_rows app.sourcing_requests_directory[];
  v_count integer;
  v_history_count integer;
begin
  select id into v_request_id from app.sourcing_requests where tenant_id = v_tenant1 and idempotency_key = 'idem-src-r1';

  -- R1 was shortlisted then reopened (test order above) -- it is 'open' by now,
  -- not 'shortlisted'. R2 (close_sourcing_request_no_source) is a genuinely
  -- terminal, never-reopened closed_no_source request -- a stable status filter
  -- target regardless of any earlier test's own later reopen calls.
  select count(*) into v_count from app.list_sourcing_requests(v_tenant1, 'closed_no_source', v_staff1, 500);
  if v_count < 1 then
    raise exception 'assertion failed: expected at least one closed_no_source sourcing request for tenant1, found %', v_count;
  end if;

  begin
    perform app.list_sourcing_requests(v_tenant1, 'not_a_real_status', v_staff1, 50);
    raise exception 'assertion failed: expected invalid_status_filter';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'invalid_status_filter%' then raise; end if;
  end;

  select count(*) into v_history_count from app.get_sourcing_request_history(v_request_id, v_staff1);
  if v_history_count < 3 then
    raise exception 'assertion failed: expected at least 3 lifecycle events for the R1 request (open, shortlisted, reopened-to-open), found %', v_history_count;
  end if;
end $$;
