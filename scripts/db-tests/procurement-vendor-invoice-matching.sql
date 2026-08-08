-- Real, executable test evidence for PRC-265 (Vendor Invoice Matching, CG-S11-PRC-016)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database. Scoped to
-- this checkpoint's own additive migrations (supabase/migrations/
-- 20260730750000_create_procurement_vendor_invoice_matching.sql and
-- 20260730760000_wire_vendor_invoice_matching_into_kpi_invoice_accuracy.sql).
-- Self-contained -- builds its own tenants/vendors/CRM-through-job-order/shipment/
-- actual-cost/vendor-bill/PO pipeline from scratch, mirroring finance-vendor-bill.sql's
-- and procurement-purchase-order.sql's own disclosed conventions.
--
-- Covers: create/idempotency (full-tuple, C-01)/missing-vendor-stated-amount rejection;
-- accept-within-tolerance (no active policy -> no auto-clear, explicit accept
-- required); tolerance policy draft/activate (auto-clear ON); PO-linked (po_three_way)
-- exception -> map_vendor_bill_match_line -> request/decide exception approval
-- (self-approval blocked); duplicate-fingerprint detection -> exception -> rejected
-- (blocked); PO currency mismatch (hard block at attach, C-22); dispute raise ->
-- respond -> resolve (self-approval blocked, then a real decision by a different
-- actor); re-evaluate (new version, full lineage retained); cost-field masking
-- (PRC:View cost); cross-tenant isolation; schema-privilege defense in depth
-- (column-restricted grants, taxonomy C-11); readiness/reconciliation reads; the
-- invoice_accuracy KPI wiring (20260730760000) end to end against real match-case
-- evidence.
--
-- Disclosed, not tested here (bounded scope, not an oversight):
--   * A live two-process concurrent race on app.re_evaluate_vendor_bill_match_case's
--     own row lock -- deferred to this batch's own Tier C correctness/concurrency
--     lens (BUILD_EXECUTION_PROTOCOL.md §5.2), which live-tests with real concurrent
--     psql sessions; this file exercises the lock-order logic deterministically
--     (single session) but not under genuine concurrency, mirroring
--     procurement-vendor-contract.sql's own identical disclosed precedent.
--   * Line-level currency_mismatch (app.vendor_bill_match_lines.currency_mismatch) is a
--     defensive safeguard structurally UNREACHABLE through the only creation path this
--     migration composes with today: app.add_actual_cost_component takes no
--     independent currency parameter, so a cost component's currency always inherits
--     its parent app.shipment_actual_costs row -- which is exactly the same currency
--     app.prepare_finance_vendor_bill_from_actual_cost snapshots onto the bill itself
--     (FIN-200). The guard exists for a future evidence source that could disagree;
--     verified by direct code reading rather than a live fixture, mirroring
--     ATW-224/ATW-245's own "currently unreachable in practice" precedent for a
--     structurally-guarded-but-not-yet-exercised branch.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (vim1): tenant_admin (admin1), a broad COM+OPS+FIN+PRC fixture-building actor (staff1, also the primary PRC:Edit test actor), a PRC-Approve/View/View-cost decision actor (approver1, distinct from staff1 for self-approval-block tests), a View-only-no-cost viewer (viewer1), a no-PRC outsider (outsider1). Tenant2 (vim2): tenant_admin (admin2) + staff2. A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team1 uuid;
  v_staff_role uuid;
  v_approver_role uuid;
  v_viewer_role uuid;
  v_outsider_role uuid;
  v_t2_staff_role uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000265101', 'admin@vim1.test'),
    ('00000000-0000-0000-0000-000000265102', 'staff@vim1.test'),
    ('00000000-0000-0000-0000-000000265103', 'approver@vim1.test'),
    ('00000000-0000-0000-0000-000000265104', 'viewer@vim1.test'),
    ('00000000-0000-0000-0000-000000265105', 'outsider@vim1.test'),
    ('00000000-0000-0000-0000-000000265201', 'admin@vim2.test'),
    ('00000000-0000-0000-0000-000000265202', 'staff@vim2.test'),
    ('00000000-0000-0000-0000-000000265999', 'supreme@vim.test');

  perform app.provision_tenant('vim1', 'Vendor Invoice Matching Co 1', 'idem-vim1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'vim1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'VIM1-CO', 'Vim1 Co', 'tester');
  v_team1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'VIM1-CO');

  perform app.provision_tenant('vim2', 'Vendor Invoice Matching Co 2', 'idem-vim2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'vim2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000265101', 'admin@vim1.test', 'Vim1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vim1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000265101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000265102', 'staff@vim1.test', 'Vim1 Staff', v_team1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vim1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000265103', 'approver@vim1.test', 'Vim1 Approver', v_team1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@vim1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000265104', 'viewer@vim1.test', 'Vim1 Viewer', v_team1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@vim1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000265105', 'outsider@vim1.test', 'Vim1 Outsider', v_team1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@vim1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000265201', 'admin@vim2.test', 'Vim2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@vim2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000265201', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000265202', 'staff@vim2.test', 'Vim2 Staff', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@vim2.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000265999', 'supreme_admin', null, null, 'tester');

  v_staff_role := (app.create_role(v_tenant1, 'Vim1 Staff', 'full COM/OPS/FIN/PRC to build and drive the fixture', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_staff_role, 'tester')).id, array(
    select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'Override', 'View', 'View cost'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))
      or (resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Approve', 'Override'))
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_staff_role and status = 'published'), '00000000-0000-0000-0000-000000265102', '00000000-0000-0000-0000-000000265101', 'admin');

  v_approver_role := (app.create_role(v_tenant1, 'Vim1 Approver', 'PRC Approve/View/View cost, decides disputes and exceptions raised by staff1', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_approver_role, 'tester')).id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('Approve', 'View', 'View cost')
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_approver_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000265103', '00000000-0000-0000-0000-000000265101', 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'Vim1 Viewer', 'PRC View only, no View cost', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_viewer_role, 'tester')).id, array(select id from app.permissions where resource_module_code = 'PRC' and action = 'View'), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_viewer_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000265104', '00000000-0000-0000-0000-000000265101', 'admin');

  v_outsider_role := (app.create_role(v_tenant1, 'Vim1 Outsider', 'no PRC at all', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_outsider_role, 'tester')).id, array[]::uuid[], 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_outsider_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000265105', '00000000-0000-0000-0000-000000265101', 'admin');

  v_t2_staff_role := (app.create_role(v_tenant2, 'Vim2 Staff', 'full PRC', 'tester')).id;
  perform app.set_role_version_permissions((app.create_role_version(v_t2_staff_role, 'tester')).id, array(
    select id from app.permissions where resource_module_code = 'PRC' and action in ('Create', 'Edit', 'View', 'View cost', 'Approve', 'Override')
  ), 'tester');
  perform app.publish_role_version((select id from app.role_versions where role_id = v_t2_staff_role and status = 'draft'), now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_staff_role and status = 'published'), '00000000-0000-0000-0000-000000265202', '00000000-0000-0000-0000-000000265201', 'admin');
end $$;

\echo '>> setup: two ACTIVE vendors (vendor1, vendor2), vendor1 gets an active vendor contract (contract_two_way evidence source)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_profile app.vendor_profiles;
  v_contract app.vendor_contracts;
begin
  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Vim Vendor One', 'VIM1V', 'PT', 'REG-VIM-1', 'logistics', 30, 'staff_created', 'idem-vim-vendor-1', v_staff1, 'staff');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Ani One', 'Ops', 'ani@vim1v.test', '0811', true, v_staff1, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Sudirman 1', 'Jakarta', 'DKI Jakarta', '10220', 'Indonesia', v_staff1, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_staff1, 'staff');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_staff1, 'staff');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff1, 'staff');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_staff1, 'staff');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_staff1, 'staff');

  -- effective_start is set safely before every fixture bill_date below (earliest is
  -- 2026-06-01) so app.resolve_effective_vendor_contract genuinely covers them.
  v_contract := app.create_vendor_contract_draft(v_tenant1, v_profile.master_record_id, 'framework', '2026-01-01'::date, null, null, 30, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, false, 'idem-vim-contract-1', v_staff1, 'staff');
  v_contract := app.submit_vendor_contract_for_approval(v_contract.id, v_contract.record_version, 'idem-vim-contract-1-submit', v_staff1, 'staff');
  perform app.activate_vendor_contract(v_contract.id, v_contract.record_version, v_staff1, 'staff');

  v_profile := app.create_vendor_profile_draft(v_tenant1, 'PT Vim Vendor Two', 'VIM2V', 'PT', 'REG-VIM-2', 'logistics', 30, 'staff_created', 'idem-vim-vendor-2', v_staff1, 'staff');
  perform app.add_vendor_contact(v_profile.master_record_id, 'Budi Two', 'Ops', 'budi@vim2v.test', '0812', true, v_staff1, 'staff');
  perform app.add_vendor_address(v_profile.master_record_id, 'legal', 'Jl. Gatot Subroto 2', 'Jakarta', 'DKI Jakarta', '10230', 'Indonesia', v_staff1, 'staff');
  perform app.add_vendor_service(v_profile.master_record_id, 'ocean_freight', v_staff1, 'staff');
  perform app.add_vendor_coverage(v_profile.master_record_id, 'Jakarta', 'Surabaya', v_staff1, 'staff');
  select * into v_profile from app.vendor_profiles where master_record_id = v_profile.master_record_id;
  v_profile := app.submit_vendor_profile_for_review(v_profile.master_record_id, v_profile.record_version, v_staff1, 'staff');
  v_profile := app.decide_vendor_profile_review(v_profile.master_record_id, v_profile.record_version, 'approve', null, v_staff1, 'staff');
  v_profile := app.activate_vendor_profile(v_profile.master_record_id, v_profile.record_version, v_staff1, 'staff');
end $$;

\echo '>> setup: one full CRM-through-job-order pipeline (mirrors finance-vendor-bill.sql), producing bill1/bill2 (vendor1, sequential shipments) and bill3/bill4 (vendor2)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_team1 uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'VIM1-CO');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_admin1 uuid := '00000000-0000-0000-0000-000000265101';
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
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_vendor1 uuid;
  v_vendor2 uuid;
  v_shipment app.shipment_orders;
  v_assignment app.resource_assignments;
  v_cost app.shipment_actual_costs;
begin
  select master_record_id into v_vendor1 from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vim Vendor One';
  select master_record_id into v_vendor2 from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vim Vendor Two';

  perform app.capture_lead(v_tenant1, 'manual', null, 'Vim Invoice Test Co', 'Jane Vim', 'jane@vimtest.test', '0811', v_staff1, v_team1, v_staff1, 'tester');
  select * into v_lead from app.leads where email = 'jane@vimtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_staff1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Vim Invoice Test Co', 'VIT', '66.666.666.9-999.000', jsonb_build_object('line1', 'Jl. Thamrin 1', 'city', 'Jakarta', 'country', 'ID'), v_staff1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Vim', 'Procurement Lead', 'jane@vimtest.test', '0811', v_staff1, v_team1, v_staff1, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_staff1, 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Vim invoice matching test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    v_staff1, v_team1, v_staff1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_staff1, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-VIM-1', 'Contoso Vim Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, v_admin1, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_staff1, 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_staff1, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_staff1, 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, v_staff1, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_staff1, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight vim lane', v_calc_id, 1, 15000000, 0, 0, v_staff1, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_staff1, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_staff1, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Vim', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_staff1, 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_staff1, 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_staff1, 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_staff1, 'rep');

  -- bill1: vendor1, exact 10,250,000 IDR (freight 1*9,500,000 vs minimum 10,000,000 -> minimum wins; + surcharge 250,000).
  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vim-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, v_staff1, 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-vim-a-planned', v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-vim-a-assigned', v_staff1, 'rep');
  select * into v_assignment from app.assign_resource(v_shipment.id, 'vendor', v_vendor1, v_staff1, 'rep');
  v_cost := app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'IDR', null, v_staff1, 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor1, v_assignment.id, null, 'Ocean freight', 1, 'shipment', 9500000, 10000000, 250000, 'idem-vim-comp-1', v_staff1, 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, v_staff1, 'rep');
  v_cost := app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, v_staff1, 'rep');
  perform app.prepare_finance_vendor_bill_from_actual_cost(v_tenant1, v_cost.id, v_vendor1, 'VIM-BILL-001', '2026-06-01'::date, 30, null, null, v_staff1, 'staff');
  perform app.unassign_resource(v_shipment.id, 'vendor', 'bill1 fixture complete', v_staff1, 'rep');

  -- bill2: vendor1 again, SAME total (10,250,000 IDR, no minimum/surcharge this time) and a bill_date close to bill1's -- the near-duplicate-fingerprint fixture.
  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vim-a2', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'PRC-265 db-test: second shipment for the near-duplicate-fingerprint fixture', v_staff1, 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-vim-a2-planned', v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-vim-a2-assigned', v_staff1, 'rep');
  select * into v_assignment from app.assign_resource(v_shipment.id, 'vendor', v_vendor1, v_staff1, 'rep');
  v_cost := app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'IDR', null, v_staff1, 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor1, v_assignment.id, null, 'Ocean freight 2', 1, 'shipment', 10250000, null, 0, 'idem-vim-comp-2', v_staff1, 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, v_staff1, 'rep');
  v_cost := app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, v_staff1, 'rep');
  perform app.prepare_finance_vendor_bill_from_actual_cost(v_tenant1, v_cost.id, v_vendor1, 'VIM-BILL-002', '2026-06-05'::date, 30, null, null, v_staff1, 'staff');
  perform app.unassign_resource(v_shipment.id, 'vendor', 'bill2 fixture complete', v_staff1, 'rep');

  -- bill4: vendor1 again, USD currency, tiny amount -- sole purpose is the real
  -- po_currency_mismatch fixture below (po1, built next, is IDR).
  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vim-a4', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'PRC-265 db-test: third shipment for the po_currency_mismatch fixture', v_staff1, 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-vim-a4-planned', v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-vim-a4-assigned', v_staff1, 'rep');
  select * into v_assignment from app.assign_resource(v_shipment.id, 'vendor', v_vendor1, v_staff1, 'rep');
  v_cost := app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'USD', null, v_staff1, 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor1, v_assignment.id, null, 'Ocean freight USD', 1, 'shipment', 500, null, 0, 'idem-vim-comp-4', v_staff1, 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, v_staff1, 'rep');
  v_cost := app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, v_staff1, 'rep');
  perform app.prepare_finance_vendor_bill_from_actual_cost(v_tenant1, v_cost.id, v_vendor1, 'VIM-BILL-004', '2026-06-01'::date, 30, null, null, v_staff1, 'staff');
  perform app.unassign_resource(v_shipment.id, 'vendor', 'bill4 fixture complete', v_staff1, 'rep');

  -- bill3: vendor2, a DELIBERATE 20% variance (evidence 10,000,000 vs vendor-stated
  -- 12,000,000 supplied at match-case-create time below) -- the exception/map/
  -- exception-approval fixture, matched against a real issued PO (built next).
  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vim-b', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'PRC-265 db-test: fourth shipment for the po_three_way exception fixture', v_staff1, 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-vim-b-planned', v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-vim-b-assigned', v_staff1, 'rep');
  select * into v_assignment from app.assign_resource(v_shipment.id, 'vendor', v_vendor2, v_staff1, 'rep');
  v_cost := app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'IDR', null, v_staff1, 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor2, v_assignment.id, null, 'Ocean freight B', 10, 'ton', 1000000, null, 0, 'idem-vim-comp-3', v_staff1, 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, v_staff1, 'rep');
  v_cost := app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, v_staff1, 'rep');
  perform app.prepare_finance_vendor_bill_from_actual_cost(v_tenant1, v_cost.id, v_vendor2, 'VIM-BILL-003', '2026-06-10'::date, 30, null, null, v_staff1, 'staff');
  perform app.unassign_resource(v_shipment.id, 'vendor', 'bill3 fixture complete', v_staff1, 'rep');

  -- bill5: vendor2 again, USD currency, tiny amount -- the SAME vendor as the fixture
  -- PO (built next) but a different currency, so attaching that PO here isolates
  -- po_currency_mismatch from po_vendor_mismatch (bill4 above already covers the
  -- wrong-vendor case; this fixture covers the right-vendor-wrong-currency case).
  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-vim-b5', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'PRC-265 db-test: fifth shipment for the po_currency_mismatch (same-vendor) fixture', v_staff1, 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-vim-b5-planned', v_staff1, 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-vim-b5-assigned', v_staff1, 'rep');
  select * into v_assignment from app.assign_resource(v_shipment.id, 'vendor', v_vendor2, v_staff1, 'rep');
  v_cost := app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'USD', null, v_staff1, 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', v_vendor2, v_assignment.id, null, 'Ocean freight B USD', 1, 'shipment', 500, null, 0, 'idem-vim-comp-5', v_staff1, 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, v_staff1, 'rep');
  v_cost := app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, v_staff1, 'rep');
  perform app.prepare_finance_vendor_bill_from_actual_cost(v_tenant1, v_cost.id, v_vendor2, 'VIM-BILL-005', '2026-06-10'::date, 30, null, null, v_staff1, 'staff');
  perform app.unassign_resource(v_shipment.id, 'vendor', 'bill5 fixture complete', v_staff1, 'rep');
end $$;

\echo '>> setup: sourcing -> RFQ -> comparison -> issued PO for vendor2 (po_three_way evidence source)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_request app.sourcing_requests;
  v_candidate app.sourcing_candidates;
  v_vendor2 uuid;
  v_rfq app.rfqs;
  v_invitation app.rfq_invitations;
  v_comparison app.vendor_comparisons;
  v_offer app.vendor_comparison_offers;
  v_po app.purchase_orders;
begin
  select master_record_id into v_vendor2 from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vim Vendor Two';

  v_request := app.create_proactive_sourcing_request(
    v_tenant1, 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', 100, 5000, 5, 40, now() + interval '3 days', now() + interval '10 days',
    'IDR', 50000000, v_staff1, now() + interval '20 days', 'idem-vim-sourcing-1', v_staff1, 'staff'
  );
  v_request := app.submit_sourcing_request(v_request.id, v_staff1, 'staff', v_request.record_version);
  perform app.evaluate_sourcing_candidate_eligibility(v_request.id, v_staff1, 'staff');
  select * into v_candidate from app.sourcing_candidates where sourcing_request_id = v_request.id and vendor_master_id = v_vendor2;
  v_candidate := app.shortlist_sourcing_candidate(v_candidate.id, true, 'fit', v_staff1, 'staff', v_candidate.record_version);
  v_request := app.submit_sourcing_shortlist(v_request.id, v_staff1, 'staff', v_request.record_version);

  v_rfq := app.draft_rfq_from_sourcing(v_tenant1, v_request.id, v_staff1, 'idem-vim-rfq-1', v_staff1, 'staff');
  v_rfq := app.issue_rfq(v_rfq.id, now() + interval '5 days', v_rfq.record_version, v_staff1, 'staff');
  select * into v_invitation from app.rfq_invitations where rfq_id = v_rfq.id and vendor_master_id = v_vendor2;
  perform app.submit_rfq_response(v_invitation.id, 'IDR', 10000000, now() + interval '30 days', 10, '{}'::jsonb, 'offline', null, now(), true, null, null, 'idem-vim-resp-1', v_staff1, 'staff');
  v_rfq := app.close_rfq_for_comparison(v_rfq.id, v_rfq.record_version, v_staff1, 'staff');

  v_comparison := app.create_vendor_comparison(v_tenant1, v_rfq.id, 'IDR', null, null, null, null, 'idem-vim-cmp-1', v_staff1, 'staff');
  select * into v_offer from app.vendor_comparison_offers where comparison_id = v_comparison.id and vendor_master_id = v_vendor2;
  v_comparison := app.recommend_vendor_comparison_offer(v_comparison.id, v_offer.id, null, v_comparison.record_version, v_staff1, 'staff');
  v_comparison := app.submit_vendor_comparison_for_approval(v_comparison.id, v_offer.id, null, v_comparison.record_version, v_staff1, 'staff');

  v_po := app.draft_purchase_order_from_selection(v_tenant1, v_comparison.id, 'idem-vim-po-1', v_staff1, 'staff', null, 30, '2026-07-01', null, null, 'FOB Jakarta', 'vim PO fixture');
  v_po := app.submit_purchase_order_for_approval(v_po.id, v_po.record_version, v_staff1, 'staff');
  v_po := app.issue_purchase_order(v_po.id, v_po.record_version, v_staff1, 'staff');
  if v_po.status <> 'issued' or v_po.currency <> 'IDR' then
    raise exception 'assertion failed: expected an issued IDR purchase order, got status=% currency=%', v_po.status, v_po.currency;
  end if;
end $$;

\echo '>> create_vendor_bill_match_case: permission-denied (outsider, view-only), missing vendor-stated amount rejected, real create for bill1 (contract_two_way, zero variance) with no active policy -> overall_status=pending (no auto-clear); idempotency full-tuple replay (C-01) and mismatch'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000265105';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000265104';
  v_bill1_id uuid;
  v_line1 app.finance_vendor_bill_lines;
  v_case app.vendor_bill_match_cases;
  v_replay app.vendor_bill_match_cases;
  v_failed boolean;
begin
  select id into v_bill1_id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-001';
  select * into v_line1 from app.finance_vendor_bill_lines where bill_id = v_bill1_id order by line_number asc limit 1;

  begin
    perform app.create_vendor_bill_match_case(v_tenant1, v_bill1_id, null, false, false, jsonb_build_array(jsonb_build_object('billLineId', v_line1.id, 'vendorStatedAmount', v_line1.amount)), 'idem-vim-mc-outsider', v_outsider1, 'outsider');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority for outsider, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected outsider create to be denied'; end if;

  begin
    perform app.create_vendor_bill_match_case(v_tenant1, v_bill1_id, null, false, false, jsonb_build_array(jsonb_build_object('billLineId', v_line1.id, 'vendorStatedAmount', v_line1.amount)), 'idem-vim-mc-viewer', v_viewer1, 'viewer');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority for View-only viewer (lacks PRC:Edit), got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected view-only create to be denied'; end if;

  begin
    perform app.create_vendor_bill_match_case(v_tenant1, v_bill1_id, null, false, false, '[]'::jsonb, 'idem-vim-mc-nolines', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'vendor_stated_amount_required%' then raise exception 'assertion failed: expected vendor_stated_amount_required, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a create with no line inputs to be rejected'; end if;

  v_case := app.create_vendor_bill_match_case(
    v_tenant1, v_bill1_id, null, false, false,
    jsonb_build_array(jsonb_build_object('billLineId', v_line1.id, 'vendorStatedQuantity', 1, 'vendorStatedUom', 'shipment', 'vendorStatedRate', 9500000, 'vendorStatedAmount', v_line1.amount)),
    'idem-vim-mc-1', v_staff1, 'staff'
  );
  if v_case.match_mode <> 'contract_two_way' or v_case.overall_status <> 'pending' or v_case.readiness_status <> 'not_ready' or v_case.version_no <> 1 or not v_case.is_current then
    raise exception 'assertion failed: expected contract_two_way/pending/not_ready/v1/current with zero variance and no active policy, got %/%/%/v%/%', v_case.match_mode, v_case.overall_status, v_case.readiness_status, v_case.version_no, v_case.is_current;
  end if;
  if v_case.total_variance_amount <> 0 then
    raise exception 'assertion failed: expected zero total_variance_amount, got %', v_case.total_variance_amount;
  end if;

  -- C-01: full-tuple idempotency replay.
  v_replay := app.create_vendor_bill_match_case(
    v_tenant1, v_bill1_id, null, false, false,
    jsonb_build_array(jsonb_build_object('billLineId', v_line1.id, 'vendorStatedQuantity', 1, 'vendorStatedUom', 'shipment', 'vendorStatedRate', 9500000, 'vendorStatedAmount', v_line1.amount)),
    'idem-vim-mc-1', v_staff1, 'staff'
  );
  if v_replay.id <> v_case.id then raise exception 'assertion failed: expected the exact same replayed row'; end if;

  begin
    perform app.create_vendor_bill_match_case(v_tenant1, v_bill1_id, null, true, false, jsonb_build_array(jsonb_build_object('billLineId', v_line1.id, 'vendorStatedAmount', v_line1.amount)), 'idem-vim-mc-1', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'idempotency_key_conflict%' then raise exception 'assertion failed: expected idempotency_key_conflict, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a mismatched-tuple replay to raise idempotency_key_conflict'; end if;

  -- A second create for the SAME bill (a genuinely different idempotency key) must be
  -- refused -- app.re_evaluate_vendor_bill_match_case is the only way to re-run.
  begin
    perform app.create_vendor_bill_match_case(v_tenant1, v_bill1_id, null, false, false, jsonb_build_array(jsonb_build_object('billLineId', v_line1.id, 'vendorStatedAmount', v_line1.amount)), 'idem-vim-mc-1-dup', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'match_case_already_exists%' then raise exception 'assertion failed: expected match_case_already_exists, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a second create for the same bill to be refused'; end if;
end $$;

\echo '>> accept_vendor_bill_match_within_tolerance: real accept (no active policy, explicit human accept required) -> matched/ready_for_finance; readiness read RPC reflects it; PRC:View-cost masking on the case/line read RPCs'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000265104';
  v_bill1_id uuid;
  v_case app.vendor_bill_match_cases;
  v_masked app.vendor_bill_match_cases;
  v_readiness record;
begin
  select id into v_bill1_id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-001';
  select * into v_case from app.vendor_bill_match_cases where bill_id = v_bill1_id and is_current;

  v_case := app.accept_vendor_bill_match_within_tolerance(v_case.id, v_case.record_version, v_staff1, 'staff');
  if v_case.overall_status <> 'matched' or v_case.readiness_status <> 'ready_for_finance' then
    raise exception 'assertion failed: expected matched/ready_for_finance, got %/%', v_case.overall_status, v_case.readiness_status;
  end if;

  select * into v_readiness from app.get_vendor_bill_match_readiness(v_bill1_id, v_tenant1, v_staff1);
  if v_readiness.readiness_status <> 'ready_for_finance' or v_readiness.match_case_id <> v_case.id then
    raise exception 'assertion failed: expected get_vendor_bill_match_readiness to reflect ready_for_finance, got %', v_readiness.readiness_status;
  end if;

  -- View-only-no-cost caller: cost rollups are masked (null), status/readiness stay visible.
  select * into v_masked from app.get_vendor_bill_match_case(v_case.id, null, v_viewer1);
  if v_masked.total_vendor_stated_amount is not null or v_masked.total_evidence_amount is not null or v_masked.total_variance_amount is not null then
    raise exception 'assertion failed: expected cost rollups masked for a View-only-no-cost caller';
  end if;
  if v_masked.overall_status <> 'matched' then
    raise exception 'assertion failed: expected status to remain visible even when cost is masked';
  end if;
end $$;

\echo '>> tolerance policy: create draft (permission-denied for outsider), activate (permission-denied for staff1 who lacks PRC:Approve is false here since staff1 HAS Approve -- verifies self-approval is NOT blocked here, matching app.publish_vendor_kpi_definition''s own disclosed precedent), auto_clear_enabled=true, generous tolerances'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_outsider1 uuid := '00000000-0000-0000-0000-000000265105';
  v_policy app.vendor_bill_match_tolerance_policies;
  v_failed boolean;
begin
  begin
    perform app.create_vendor_bill_match_tolerance_policy_draft(v_tenant1, 'Outsider policy', 5, 5, 5, 1000, true, 30, null, 'idem-vim-policy-outsider', v_outsider1, 'outsider');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'insufficient_authority%' then raise exception 'assertion failed: expected insufficient_authority, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected outsider tolerance-policy create to be denied'; end if;

  v_policy := app.create_vendor_bill_match_tolerance_policy_draft(v_tenant1, 'Standard policy', 5, 5, 5, 1000, true, 30, 'generous, auto-clear on', 'idem-vim-policy-1', v_staff1, 'staff');
  if v_policy.status <> 'draft' or v_policy.version_no <> 1 then
    raise exception 'assertion failed: expected draft v1, got %/v%', v_policy.status, v_policy.version_no;
  end if;

  -- Same actor both drafts AND activates -- deliberate, disclosed, matches
  -- app.publish_vendor_kpi_definition''s own precedent (self-approval not blocked here).
  v_policy := app.activate_vendor_bill_match_tolerance_policy(v_policy.id, v_policy.record_version, v_staff1, 'staff');
  if v_policy.status <> 'active' then
    raise exception 'assertion failed: expected active, got %', v_policy.status;
  end if;

  if (select count(*) from app.vendor_bill_match_tolerance_policies where tenant_id = v_tenant1 and status = 'active') <> 1 then
    raise exception 'assertion failed: expected exactly one active policy';
  end if;
end $$;

\echo '>> bill3 (po_three_way, vendor2): 20% variance -> overall_status=exception; map_vendor_bill_match_line attaches PO-line quantity evidence and rate-version evidence while still exception; request/decide exception approval -- self-approval blocked, then approved by a distinct actor -> matched/ready_for_finance'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000265103';
  v_bill3_id uuid;
  v_po_id uuid;
  v_po_line_id uuid;
  v_line3 app.finance_vendor_bill_lines;
  v_case app.vendor_bill_match_cases;
  v_match_line app.vendor_bill_match_lines;
  v_approval app.vendor_bill_match_exception_approvals;
  v_failed boolean;
begin
  select id into v_bill3_id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-003';
  select * into v_line3 from app.finance_vendor_bill_lines where bill_id = v_bill3_id order by line_number asc limit 1;
  select id into v_po_id from app.purchase_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vim-po-1';
  select id into v_po_line_id from app.purchase_order_lines where purchase_order_id = v_po_id order by line_no asc limit 1;

  v_case := app.create_vendor_bill_match_case(
    v_tenant1, v_bill3_id, v_po_id, false, false,
    jsonb_build_array(jsonb_build_object('billLineId', v_line3.id, 'vendorStatedQuantity', 10, 'vendorStatedUom', 'ton', 'vendorStatedRate', 1200000, 'vendorStatedAmount', 12000000)),
    'idem-vim-mc-3', v_staff1, 'staff'
  );
  if v_case.match_mode <> 'po_three_way' or v_case.overall_status <> 'exception' or v_case.readiness_status <> 'not_ready' then
    raise exception 'assertion failed: expected po_three_way/exception/not_ready for a 20%% variance, got %/%/%', v_case.match_mode, v_case.overall_status, v_case.readiness_status;
  end if;

  select * into v_match_line from app.vendor_bill_match_lines where match_case_id = v_case.id and bill_line_id = v_line3.id;
  if v_match_line.line_status <> 'variance_exception' then
    raise exception 'assertion failed: expected variance_exception on the line, got %', v_match_line.line_status;
  end if;

  if v_po_line_id is null then
    raise exception 'assertion failed: expected a real purchase_order_lines row (auto-derived from the sourcing request''s own cargo dimensions) to exist for the fixture PO';
  end if;
  v_match_line := app.map_vendor_bill_match_line(v_match_line.id, v_case.record_version, v_po_line_id, null, v_staff1, 'staff');
  if v_match_line.po_line_id <> v_po_line_id or v_match_line.po_line_quantity_variance_pct is null then
    raise exception 'assertion failed: expected po_line_id mapped and po_line_quantity_variance_pct computed (real PO-line quantity/UOM evidence, quantity=100kg vs vendor-stated 10 ton)';
  end if;
  if not v_match_line.po_line_uom_mismatch then
    raise exception 'assertion failed: expected po_line_uom_mismatch=true (kg vs ton)';
  end if;

  -- map_vendor_bill_match_line re-rolled (and touch-bumped) the case row -- re-fetch
  -- before using its record_version again.
  select * into v_case from app.vendor_bill_match_cases where id = v_case.id;
  v_approval := app.request_vendor_bill_match_exception_approval(v_case.id, v_case.record_version, 'genuine rate discrepancy, vendor confirmed by email', v_staff1, 'staff');

  -- C-18 self-approval blocked: the requester may not also decide.
  begin
    perform app.decide_vendor_bill_match_exception_approval(v_approval.id, v_approval.record_version, 'approved', 'self-approval attempt', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'self_approval_not_allowed%' then raise exception 'assertion failed: expected self_approval_not_allowed, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected requester self-decide to be blocked'; end if;

  v_approval := app.decide_vendor_bill_match_exception_approval(v_approval.id, v_approval.record_version, 'approved', 'confirmed with vendor, rate change was legitimate', v_approver1, 'approver');
  if v_approval.status <> 'approved' then
    raise exception 'assertion failed: expected approved, got %', v_approval.status;
  end if;

  select * into v_case from app.vendor_bill_match_cases where id = v_case.id;
  if v_case.overall_status <> 'matched' or v_case.readiness_status <> 'ready_for_finance' then
    raise exception 'assertion failed: expected matched/ready_for_finance after exception approval, got %/%', v_case.overall_status, v_case.readiness_status;
  end if;
end $$;

\echo '>> bill2 (near-duplicate of bill1: same vendor/currency/amount, close bill_date): is_duplicate_flagged, forced exception even though numerically within tolerance; exception approval REJECTED (genuine duplicate) -> blocked'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000265103';
  v_bill2_id uuid;
  v_bill1_case_id uuid;
  v_line2 app.finance_vendor_bill_lines;
  v_case app.vendor_bill_match_cases;
  v_approval app.vendor_bill_match_exception_approvals;
begin
  select id into v_bill2_id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-002';
  select * into v_line2 from app.finance_vendor_bill_lines where bill_id = v_bill2_id order by line_number asc limit 1;

  v_case := app.create_vendor_bill_match_case(
    v_tenant1, v_bill2_id, null, false, false,
    jsonb_build_array(jsonb_build_object('billLineId', v_line2.id, 'vendorStatedQuantity', 1, 'vendorStatedUom', 'shipment', 'vendorStatedRate', 10250000, 'vendorStatedAmount', v_line2.amount)),
    'idem-vim-mc-2', v_staff1, 'staff'
  );
  if not v_case.is_duplicate_flagged then
    raise exception 'assertion failed: expected bill2 to be flagged as a probable duplicate of bill1 (same vendor/currency/amount, close bill_date)';
  end if;
  if v_case.overall_status <> 'exception' then
    raise exception 'assertion failed: expected exception even though every line is numerically within tolerance, got %', v_case.overall_status;
  end if;

  select id into v_bill1_case_id from app.vendor_bill_match_cases where bill_id = (select id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-001') and is_current;
  if v_case.duplicate_of_case_id <> v_bill1_case_id then
    raise exception 'assertion failed: expected duplicate_of_case_id to point at bill1''s own current match case';
  end if;

  v_approval := app.request_vendor_bill_match_exception_approval(v_case.id, v_case.record_version, 'reviewing possible duplicate', v_staff1, 'staff');
  v_approval := app.decide_vendor_bill_match_exception_approval(v_approval.id, v_approval.record_version, 'rejected', 'confirmed genuine duplicate submission, do not clear', v_approver1, 'approver');
  if v_approval.status <> 'rejected' then
    raise exception 'assertion failed: expected rejected, got %', v_approval.status;
  end if;

  select * into v_case from app.vendor_bill_match_cases where id = v_case.id;
  if v_case.overall_status <> 'blocked' or v_case.readiness_status <> 'blocked' then
    raise exception 'assertion failed: expected blocked/blocked after a rejected duplicate exception, got %/%', v_case.overall_status, v_case.readiness_status;
  end if;
end $$;

\echo '>> PO vendor mismatch and PO currency mismatch (taxonomy C-22) are both real, independent, reachable hard blocks at create time, never a silent conversion'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_bill4_id uuid;
  v_bill5_id uuid;
  v_po_id uuid;
  v_line4 app.finance_vendor_bill_lines;
  v_line5 app.finance_vendor_bill_lines;
  v_failed boolean;
begin
  select id into v_bill4_id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-004';
  select * into v_line4 from app.finance_vendor_bill_lines where bill_id = v_bill4_id order by line_number asc limit 1;
  select id into v_bill5_id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-005';
  select * into v_line5 from app.finance_vendor_bill_lines where bill_id = v_bill5_id order by line_number asc limit 1;
  select id into v_po_id from app.purchase_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-vim-po-1';

  -- bill4 is vendor1's own USD bill; the fixture PO belongs to vendor2 -- a wrong-vendor
  -- attach, checked (and rejected) before currency is even considered.
  begin
    perform app.create_vendor_bill_match_case(v_tenant1, v_bill4_id, v_po_id, false, false, jsonb_build_array(jsonb_build_object('billLineId', v_line4.id, 'vendorStatedAmount', v_line4.amount)), 'idem-vim-mc-4', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'po_vendor_mismatch%' then raise exception 'assertion failed: expected po_vendor_mismatch, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected a wrong-vendor PO to be rejected'; end if;

  -- bill5 is vendor2's own USD bill -- the SAME vendor as the fixture PO, isolating the
  -- currency check on its own (the vendor check now passes, so currency is what fires).
  begin
    perform app.create_vendor_bill_match_case(v_tenant1, v_bill5_id, v_po_id, false, false, jsonb_build_array(jsonb_build_object('billLineId', v_line5.id, 'vendorStatedAmount', v_line5.amount)), 'idem-vim-mc-5', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'po_currency_mismatch%' then raise exception 'assertion failed: expected po_currency_mismatch, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected an IDR PO attached to a same-vendor USD bill to be rejected'; end if;
end $$;

\echo '>> dispute: raise against bill1''s already-matched case -> disputed/not_ready; respond; self-approval blocked (raiser cannot resolve); resolved (rejected) by a distinct actor -> case returns to pending -> re-accept -> matched'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_approver1 uuid := '00000000-0000-0000-0000-000000265103';
  v_bill1_id uuid;
  v_case app.vendor_bill_match_cases;
  v_dispute app.vendor_bill_match_disputes;
  v_masked_dispute app.vendor_bill_match_disputes;
  v_viewer1 uuid := '00000000-0000-0000-0000-000000265104';
  v_failed boolean;
begin
  select id into v_bill1_id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-001';
  select * into v_case from app.vendor_bill_match_cases where bill_id = v_bill1_id and is_current;

  v_dispute := app.raise_vendor_bill_match_dispute(v_case.id, null, 'vendor claims a different rate applied', 500000, v_staff1, 'staff');

  select * into v_case from app.vendor_bill_match_cases where id = v_case.id;
  if v_case.overall_status <> 'disputed' or v_case.readiness_status <> 'not_ready' then
    raise exception 'assertion failed: expected disputed/not_ready, got %/%', v_case.overall_status, v_case.readiness_status;
  end if;

  select * into v_masked_dispute from app.list_vendor_bill_match_disputes(v_case.id, v_viewer1) limit 1;
  if v_masked_dispute.disputed_amount is not null then
    raise exception 'assertion failed: expected disputed_amount masked for a View-only-no-cost caller';
  end if;

  v_dispute := app.record_vendor_bill_match_dispute_response(v_dispute.id, v_dispute.record_version, 'vendor confirms the invoice figure was correct, no adjustment needed', null, v_staff1, 'staff');

  begin
    perform app.resolve_vendor_bill_match_dispute(v_dispute.id, v_dispute.record_version, 'rejected', 'self-resolve attempt', v_staff1, 'staff');
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm not like 'self_approval_not_allowed%' then raise exception 'assertion failed: expected self_approval_not_allowed, got %', sqlerrm; end if;
  end;
  if not v_failed then raise exception 'assertion failed: expected the raiser to be blocked from resolving their own dispute'; end if;

  v_dispute := app.resolve_vendor_bill_match_dispute(v_dispute.id, v_dispute.record_version, 'rejected', 'reviewed, original match figures stand', v_approver1, 'approver');
  if v_dispute.status <> 'rejected' then
    raise exception 'assertion failed: expected rejected, got %', v_dispute.status;
  end if;

  select * into v_case from app.vendor_bill_match_cases where id = v_case.id;
  if v_case.overall_status <> 'pending' then
    raise exception 'assertion failed: expected the case to return to pending after dispute resolution, got %', v_case.overall_status;
  end if;

  v_case := app.accept_vendor_bill_match_within_tolerance(v_case.id, v_case.record_version, v_staff1, 'staff');
  if v_case.overall_status <> 'matched' then
    raise exception 'assertion failed: expected matched after re-accepting, got %', v_case.overall_status;
  end if;
end $$;

\echo '>> re_evaluate_vendor_bill_match_case: a new version is created, the prior version is no longer current, full lineage retained via list_vendor_bill_match_case_versions'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_bill1_id uuid;
  v_case app.vendor_bill_match_cases;
  v_line1 app.finance_vendor_bill_lines;
  v_new_case app.vendor_bill_match_cases;
begin
  select id into v_bill1_id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-001';
  select * into v_case from app.vendor_bill_match_cases where bill_id = v_bill1_id and is_current;
  select * into v_line1 from app.finance_vendor_bill_lines where bill_id = v_bill1_id order by line_number asc limit 1;

  v_new_case := app.re_evaluate_vendor_bill_match_case(
    v_case.id, v_case.record_version, null,
    jsonb_build_array(jsonb_build_object('billLineId', v_line1.id, 'vendorStatedQuantity', 1, 'vendorStatedUom', 'shipment', 'vendorStatedRate', 9500000, 'vendorStatedAmount', v_line1.amount)),
    v_staff1, 'staff'
  );
  if v_new_case.version_no <> v_case.version_no + 1 or not v_new_case.is_current then
    raise exception 'assertion failed: expected version_no % and is_current=true, got %/%', v_case.version_no + 1, v_new_case.version_no, v_new_case.is_current;
  end if;
  -- The duplicate-fingerprint check re-runs on every re-evaluation too, not just at
  -- create time: bill1 and bill2 share the same fingerprint, and bill2's own case is
  -- still is_current (its own overall_status of 'blocked' does not change that) -- so
  -- this new version is correctly re-flagged as a probable duplicate, exactly as a
  -- brand-new case for the same figures would be. Zero variance alone is NOT enough to
  -- auto-clear a flagged duplicate, matching bill2's own original create-time behavior.
  if not v_new_case.is_duplicate_flagged or v_new_case.overall_status <> 'exception' or v_new_case.readiness_status <> 'not_ready' then
    raise exception 'assertion failed: expected the re-evaluated version to be re-flagged as a probable duplicate of bill2 (exception/not_ready), got flagged=%/%/%', v_new_case.is_duplicate_flagged, v_new_case.overall_status, v_new_case.readiness_status;
  end if;

  -- Clear it the same way bill3''s own exception was cleared -- a real, distinct-actor
  -- exception approval, proving re-evaluated versions flow through the identical
  -- governance path as a freshly created case.
  declare
    v_approval2 app.vendor_bill_match_exception_approvals;
  begin
    v_approval2 := app.request_vendor_bill_match_exception_approval(v_new_case.id, v_new_case.record_version, 'reviewed: bill1 and bill2 are genuinely distinct invoices, false-positive duplicate', v_staff1, 'staff');
    v_approval2 := app.decide_vendor_bill_match_exception_approval(v_approval2.id, v_approval2.record_version, 'approved', 'confirmed not a duplicate after manual review', '00000000-0000-0000-0000-000000265103', 'approver');
    if v_approval2.status <> 'approved' then
      raise exception 'assertion failed: expected approved, got %', v_approval2.status;
    end if;
  end;

  select * into v_new_case from app.vendor_bill_match_cases where id = v_new_case.id;
  if v_new_case.overall_status <> 'matched' or v_new_case.readiness_status <> 'ready_for_finance' then
    raise exception 'assertion failed: expected matched/ready_for_finance after clearing the false-positive duplicate flag, got %/%', v_new_case.overall_status, v_new_case.readiness_status;
  end if;

  if (select is_current from app.vendor_bill_match_cases where id = v_case.id) then
    raise exception 'assertion failed: expected the prior version to no longer be current';
  end if;

  if (select count(*) from app.list_vendor_bill_match_case_versions(v_bill1_id, v_tenant1, v_staff1)) <> 2 then
    raise exception 'assertion failed: expected exactly 2 retained versions for bill1''s match case';
  end if;
end $$;

\echo '>> get_vendor_bill_match_readiness: an empty shape (never a raised error) for a bill with no match case yet'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_readiness record;
begin
  select * into v_readiness from app.get_vendor_bill_match_readiness(gen_random_uuid(), v_tenant1, v_staff1);
  if v_readiness.match_case_id is not null or v_readiness.readiness_status is not null then
    raise exception 'assertion failed: expected an empty readiness shape for a bill id with no match case';
  end if;
end $$;

\echo '>> get_vendor_bill_match_reconciliation_status: real aggregate counts by (overall_status, readiness_status), cost-masked total_variance_amount for a View-only-no-cost caller'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000265104';
  v_matched_row record;
  v_masked_row record;
begin
  select * into v_matched_row from app.get_vendor_bill_match_reconciliation_status(v_tenant1, v_staff1) where overall_status = 'matched' and readiness_status = 'ready_for_finance';
  if v_matched_row.case_count < 2 then
    raise exception 'assertion failed: expected at least 2 matched/ready_for_finance cases (bill1 and bill3), got %', v_matched_row.case_count;
  end if;
  if v_matched_row.total_variance_amount is null then
    raise exception 'assertion failed: expected a real (non-masked) total_variance_amount for a PRC:View-cost caller';
  end if;

  select * into v_masked_row from app.get_vendor_bill_match_reconciliation_status(v_tenant1, v_viewer1) where overall_status = 'matched' and readiness_status = 'ready_for_finance';
  if v_masked_row.total_variance_amount is not null then
    raise exception 'assertion failed: expected total_variance_amount masked for a View-only-no-cost caller';
  end if;
  if v_masked_row.case_count <> v_matched_row.case_count then
    raise exception 'assertion failed: expected the same case_count regardless of cost-view permission (only the amount is masked)';
  end if;
end $$;

\echo '>> cross-tenant isolation: vim2''s staff, holding zero membership in vim1, is denied on write RPCs with insufficient_authority and gets vendor_bill_match_case_not_found (never a real row disclosure) on read RPCs; raw RLS denies a direct select'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_t2_staff uuid := '00000000-0000-0000-0000-000000265202';
  v_bill1_id uuid;
  v_case_id uuid;
begin
  select id into v_bill1_id from app.finance_vendor_bills where tenant_id = v_tenant1 and vendor_reference = 'VIM-BILL-001';
  select id into v_case_id from app.vendor_bill_match_cases where bill_id = v_bill1_id and is_current;

  begin
    perform app.accept_vendor_bill_match_within_tolerance(v_case_id, 1, v_t2_staff, 'attacker');
    raise exception 'assertion failed: expected insufficient_authority for a vim2 actor acting on a vim1 match case';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_vendor_bill_match_case(v_case_id, null, v_t2_staff);
    raise exception 'assertion failed: expected vendor_bill_match_case_not_found (never a real row disclosure) for a vim2 actor reading a vim1 match case';
  exception
    when others then
      if sqlerrm not like 'vendor_bill_match_case_not_found%' then raise; end if;
  end;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000265202", "role": "authenticated"}', true);
  if exists (select 1 from app.vendor_bill_match_cases where id = v_case_id) then
    raise exception 'assertion failed: raw RLS leak -- vim2 staff directly selected a vim1 match case row';
  end if;
  if exists (select 1 from app.vendor_bill_match_lines where match_case_id = v_case_id) then
    raise exception 'assertion failed: raw RLS leak -- vim2 staff directly selected a vim1 match line row';
  end if;
  reset role;
end $$;

\echo '>> schema-privilege defense in depth: authenticated has NO column-level SELECT on any cost-shaped column (taxonomy C-11); anon holds zero EXECUTE on any new function (ERR-2026-004 regression guard); internal (leading-underscore) helpers carry no client grant'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.column_privileges
  where table_schema = 'app' and table_name = 'vendor_bill_match_cases' and grantee = 'authenticated'
    and column_name in ('total_vendor_stated_amount', 'total_evidence_amount', 'total_variance_amount', 'total_variance_pct');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated column grants on the four masked case rollup columns, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.column_privileges
  where table_schema = 'app' and table_name = 'vendor_bill_match_lines' and grantee = 'authenticated'
    and column_name in ('vendor_stated_rate', 'vendor_stated_amount', 'evidence_rate', 'evidence_amount', 'contracted_rate_amount', 'amount_variance_amount', 'amount_variance_pct', 'rate_variance_pct');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated column grants on the eight masked line columns, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.column_privileges
  where table_schema = 'app' and table_name = 'vendor_bill_match_disputes' and grantee = 'authenticated' and column_name = 'disputed_amount';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated column grant on disputed_amount, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.column_privileges
  where table_schema = 'app' and table_name = 'vendor_bill_match_exception_approvals' and grantee = 'authenticated' and column_name in ('variance_amount', 'variance_pct');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated column grants on variance_amount/variance_pct, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.column_privileges
  where table_schema = 'app' and table_name = 'vendor_bill_match_cases' and grantee = 'authenticated' and column_name = 'overall_status';
  if v_count <> 1 then
    raise exception 'assertion failed: expected authenticated to retain a direct SELECT grant on the non-cost overall_status column, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon' and routine_name like '%vendor_bill_match%';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on any vendor-bill-match function, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee in ('authenticated', 'anon')
    and (routine_name like '\_%' escape '\')
    and routine_name in (
      'touch_vendor_bill_match_tolerance_policies_row', 'touch_vendor_bill_match_cases_row', 'touch_vendor_bill_match_lines_row',
      'touch_vendor_bill_match_disputes_row', 'touch_vendor_bill_match_exception_approvals_row', '_record_vendor_bill_match_event',
      'check_vendor_bill_match_authority', 'compute_vendor_bill_match_fingerprint', '_vendor_bill_match_pct_variance',
      '_score_vendor_bill_match_line', '_reroll_vendor_bill_match_case'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated/anon grants on any internal helper, found %', v_count;
  end if;
end $$;

\echo '>> invoice_accuracy KPI wiring (20260730760000): a real, computable score derived from app.vendor_bill_match_cases -- was PRC-264''s own permanent is_computable=false stub'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'vim1');
  v_staff1 uuid := '00000000-0000-0000-0000-000000265102';
  v_vendor1 uuid;
  v_definition app.vendor_kpi_definitions;
  v_metric app.vendor_kpi_metric_values;
  v_window_start timestamptz := now() - interval '1 hour';
  v_window_end timestamptz := now() + interval '1 hour';
begin
  select master_record_id into v_vendor1 from app.vendor_profiles where tenant_id = v_tenant1 and legal_name = 'PT Vim Vendor One';

  v_definition := app.create_vendor_kpi_definition_draft(
    v_tenant1, 'invoice_accuracy', 'Invoice accuracy', 'PRC-265 wiring test', 90, 1,
    90, 'gte', 10, 'percent', '{"excellent": 90, "good": 75, "watch": 60}'::jsonb, '{}'::jsonb, 2,
    true, null, 'idem-vim-kpi-def-1', v_staff1, 'staff'
  );
  if not v_definition.is_computable then
    raise exception 'assertion failed: expected the tenant to be able to publish invoice_accuracy with is_computable=true now that PRC-265 exists';
  end if;
  v_definition := app.publish_vendor_kpi_definition(v_definition.id, v_definition.record_version, v_staff1, 'staff');
  if v_definition.status <> 'published' then
    raise exception 'assertion failed: expected published, got %', v_definition.status;
  end if;

  for v_metric in select * from app.calculate_vendor_kpi_metrics(v_tenant1, v_vendor1, v_window_start, v_window_end, 'manual', 'idem-vim-kpi-calc-1', v_staff1, 'staff') loop
    if v_metric.kpi_code = 'invoice_accuracy' then
      if not v_metric.is_computable then
        raise exception 'assertion failed: expected invoice_accuracy to be genuinely computable against real match-case evidence (vendor1 has 2 decided cases: bill1 matched, bill2 blocked), got is_computable=false';
      end if;
      -- vendor1''s own decided cases: bill1 (matched, clean) + bill2 (blocked, was a
      -- confirmed duplicate) -- exactly one of two reached a clean match, so the real
      -- computed value must be 50, never the permanently-null PRC-264 stub value.
      if v_metric.computed_value <> 50 then
        raise exception 'assertion failed: expected computed_value=50 (1 of 2 decided vendor1 cases matched cleanly), got %', v_metric.computed_value;
      end if;
      if v_metric.sample_size <> 2 then
        raise exception 'assertion failed: expected sample_size=2, got %', v_metric.sample_size;
      end if;
    end if;
  end loop;

  if not found then
    raise exception 'assertion failed: expected at least one metric value row (invoice_accuracy) from calculate_vendor_kpi_metrics';
  end if;
end $$;

\echo '>> audit trail: every vendor-bill-match mutation recorded a real app.audit_logs event'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where action in (
    'create_vendor_bill_match_tolerance_policy_draft', 'activate_vendor_bill_match_tolerance_policy',
    'create_vendor_bill_match_case', 're_evaluate_vendor_bill_match_case', 'map_vendor_bill_match_line',
    'accept_vendor_bill_match_within_tolerance', 'raise_vendor_bill_match_dispute', 'record_vendor_bill_match_dispute_response',
    'resolve_vendor_bill_match_dispute', 'request_vendor_bill_match_exception_approval', 'decide_vendor_bill_match_exception_approval'
  );
  if v_count < 15 then
    raise exception 'assertion failed: expected at least 15 captured vendor-bill-match audit events, found %', v_count;
  end if;
end $$;

\echo 'ALL PRC-265 db-test assertions passed.'
