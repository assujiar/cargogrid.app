-- Real, executable test evidence for ATW-020 (CG-S10-ATW-020, Prompt 239 Cycle Count
-- and Inventory Adjustment) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (cyclecnt1) with a tenant_admin, a supervisor (OPS Create/Edit/View/Override), a second supervisor (for the self-approval-blocked axis), two plain counters (OPS Edit/View), an OPS:View-only viewer, a global Supreme Admin, two owner accounts (Alpha, Beta) via the full CRM->Job Order pipeline, a customer_user-layer actor scoped to Account Alpha only, one warehouse (WH-CC-1) with three racks; a second isolated tenant (cyclecnt2) for cross-tenant checks'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_company2 uuid;
  v_supervisor_role uuid;
  v_supervisor_draft app.role_versions;
  v_counter_role uuid;
  v_counter_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_rep2_role uuid;
  v_rep2_draft app.role_versions;
  v_rule app.margin_rule_versions;
  v_warehouse app.warehouses;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000200301', 'admin@cyclecnt1.test'),
    ('00000000-0000-0000-0000-000000200302', 'supervisor@cyclecnt1.test'),
    ('00000000-0000-0000-0000-000000200303', 'counter1@cyclecnt1.test'),
    ('00000000-0000-0000-0000-000000200304', 'counter2@cyclecnt1.test'),
    ('00000000-0000-0000-0000-000000200305', 'viewer@cyclecnt1.test'),
    ('00000000-0000-0000-0000-000000200306', 'supreme@cyclecnt1.test'),
    ('00000000-0000-0000-0000-000000200307', 'customer-alpha@cyclecnt1.test'),
    ('00000000-0000-0000-0000-000000200308', 'admin2@cyclecnt2.test'),
    ('00000000-0000-0000-0000-000000200309', 'rep2@cyclecnt2.test'),
    ('00000000-0000-0000-0000-000000200310', 'supervisor2@cyclecnt1.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000200306', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cyclecnt1', 'Cycle Count Tenant One', 'idem-cyclecnt1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cyclecnt1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CYCLECNT1-CO', 'Cycle Count Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CYCLECNT1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200301', 'admin@cyclecnt1.test', 'CC Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@cyclecnt1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000200301', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200302', 'supervisor@cyclecnt1.test', 'CC Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@cyclecnt1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200310', 'supervisor2@cyclecnt1.test', 'CC Supervisor Two', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor2@cyclecnt1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200303', 'counter1@cyclecnt1.test', 'CC Counter One', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'counter1@cyclecnt1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200304', 'counter2@cyclecnt1.test', 'CC Counter Two', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'counter2@cyclecnt1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200305', 'viewer@cyclecnt1.test', 'CC Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@cyclecnt1.test'), 'active', 'onboarded', 'tester');

  -- Supervisor role: full OPS Create/Edit/View/Override, plus enough COM to run the
  -- CRM->Job Order pipeline that creates Account Alpha/Beta (mirrors ATW-019's own rep
  -- role trio, extended with Override).
  v_supervisor_role := (app.create_role(v_tenant1, 'CC Supervisor Role', 'full commercial + ops create/edit/view/override', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000200302', '00000000-0000-0000-0000-000000200301', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000200310', '00000000-0000-0000-0000-000000200301', 'tester');

  -- Counter role: OPS Edit + View only -- can submit observations/be assigned, but
  -- structurally CANNOT approve/reject/cancel a variance (no OPS:Override) and CANNOT
  -- see snapshot_expected_quantity/variance_quantity/variance_pct (blind-count
  -- redaction, design note 6).
  v_counter_role := (app.create_role(v_tenant1, 'CC Counter Role', 'ops edit/view only', 'tester')).id;
  v_counter_draft := app.create_role_version(v_counter_role, 'tester');
  perform app.set_role_version_permissions(v_counter_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_counter_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_counter_role and status = 'published'), '00000000-0000-0000-0000-000000200303', '00000000-0000-0000-0000-000000200301', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_counter_role and status = 'published'), '00000000-0000-0000-0000-000000200304', '00000000-0000-0000-0000-000000200301', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'CC Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000200305', '00000000-0000-0000-0000-000000200301', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-CC-1', 'Cycle Count Warehouse 1', 'Jl. Cycle Count 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000200302', 'supervisor');
  declare
    v_rack_a app.warehouse_locations;
    v_rack_b app.warehouse_locations;
    v_rack_race app.warehouse_locations;
  begin
    v_rack_a := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-CC-A', 'Cycle Count Rack A', 'rack', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000200302', 'supervisor');
    perform app.set_warehouse_location_status(v_rack_a.id, 'active', null, v_rack_a.record_version, '00000000-0000-0000-0000-000000200302', 'supervisor');
    v_rack_b := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-CC-B', 'Cycle Count Rack B', 'rack', 2, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000200302', 'supervisor');
    perform app.set_warehouse_location_status(v_rack_b.id, 'active', null, v_rack_b.record_version, '00000000-0000-0000-0000-000000200302', 'supervisor');
    v_rack_race := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-CC-RACE', 'Cycle Count Rack Race', 'rack', 3, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000200302', 'supervisor');
    perform app.set_warehouse_location_status(v_rack_race.id, 'active', null, v_rack_race.record_version, '00000000-0000-0000-0000-000000200302', 'supervisor');
  end;

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('cyclecnt2', 'Cycle Count Tenant Two', 'idem-cyclecnt2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cyclecnt2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CYCLECNT2-CO', 'Cycle Count Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CYCLECNT2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000200308', 'admin2@cyclecnt2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@cyclecnt2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000200308', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000200309', 'rep2@cyclecnt2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@cyclecnt2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view/override', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000200309', '00000000-0000-0000-0000-000000200308', 'tester');
end $$;

-- Test-fixture-only helper (never part of the real migration): builds a real owner
-- app.accounts row via the full CRM->Job Order pipeline in one call, so the fixture
-- below does not repeat the same dozen-call sequence per owner account.
create function create_cc_owner_account(p_tenant_id uuid, p_company uuid, p_label text, p_email text, p_npwp_suffix text)
returns app.accounts
language plpgsql
as $fn$
declare
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_actor uuid := '00000000-0000-0000-0000-000000200302';
begin
  perform app.capture_lead(p_tenant_id, 'manual', null, p_label, p_label || ' Contact', p_email, '0811', v_actor, p_company, v_actor, 'supervisor');
  select * into v_lead from app.leads where email = p_email;
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_actor, 'supervisor');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, p_label, p_npwp_suffix, '11.111.111.' || p_npwp_suffix || '.000',
    jsonb_build_object('line1', 'Jl. ' || p_label, 'city', 'Jakarta', 'country', 'ID'),
    v_actor, 'supervisor');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(p_tenant_id, p_label || ' Ops', 'Ops Lead', p_email, '0811', v_actor, p_company, v_actor, 'supervisor');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_actor, 'supervisor');
  select * into v_opportunity from app.create_opportunity(
    p_tenant_id, v_prospect.id, p_label || ' lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    v_actor, p_company, v_actor, 'supervisor'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_actor, 'supervisor');
  -- app.create_rate_version/app.approve_rate_version check tenant_admin/Supreme Admin
  -- authority directly (not RBAC) -- the admin identity, not the supervisor, is
  -- required here (mirrors ATW-019's own fixture precedent).
  select * into v_rate from app.create_rate_version(
    p_tenant_id, 'VENDOR-CC-' || p_npwp_suffix, 'Contoso CC Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000200301', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000200301', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_actor, 'supervisor');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, v_actor, 'supervisor');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(p_tenant_id, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_actor, 'supervisor');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', p_label || ' lane', v_calc_id, 1, 6000000, 0, 0, v_actor, 'supervisor');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_actor, 'supervisor');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_actor, 'supervisor');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', p_label || ' Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_actor, 'supervisor');
  return v_account;
end;
$fn$;

\echo '>> build Account Alpha/Beta (Alpha via the full CRM pipeline, one published margin rule reused for both), items, and opening-balance movements for every scenario dimension'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CYCLECNT1-CO');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_actor uuid := '00000000-0000-0000-0000-000000200302';
  v_account_alpha app.accounts;
  v_account_beta app.accounts;
  v_rule app.margin_rule_versions;
  v_item app.item_masters;
begin
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_actor, 'supervisor');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_actor, 'supervisor');

  v_account_alpha := create_cc_owner_account(v_tenant1, v_company, 'CC Customer Alpha', 'alpha@cyclecnt239.test', '31');
  v_account_beta := create_cc_owner_account(v_tenant1, v_company, 'CC Customer Beta', 'beta@cyclecnt239.test', '32');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000200307', 'customer-alpha@cyclecnt1.test', 'Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@cyclecnt1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000200307', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = (select id from app.roles where tenant_id = v_tenant1 and name = 'CC Viewer Role') and status = 'published'), '00000000-0000-0000-0000-000000200307', v_actor, 'tester');

  -- One item per test dimension -- every one owned by Alpha unless noted.
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A1', 'CC Widget A1 (zero variance)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A2', 'CC Widget A2 (positive variance)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A3', 'CC Widget A3 (negative variance)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A4', 'CC Widget A4 (zero expected, zero observed)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A5', 'CC Widget A5 (recount flow)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A6', 'CC Widget A6 (self-approval allowed)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A7', 'CC Widget A7 (self-approval blocked)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A8', 'CC Widget A8 (stale snapshot)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A9', 'CC Widget A9 (scan mismatch)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-LOT', 'CC Widget Lot (lot mismatch)', null, 'PCS', true, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-SERIAL', 'CC Widget Serial (serial mismatch)', null, 'PCS', false, true, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-RACE', 'CC Widget Race (concurrency)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-CC-BETA', 'CC Widget Beta (cross-owner)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  -- Findings-review regression fixtures (adversarial-review fixes, no source prompt
  -- change -- see scenarios 11-15 below).
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-A10', 'CC Widget A10 (self-disclosure)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-THRESH-IN', 'CC Widget Thresh In (within materiality tolerance)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-THRESH-OUT', 'CC Widget Thresh Out (beyond materiality tolerance)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-IDEM-A', 'CC Widget Idem A (approve idempotency collision)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-IDEM-B', 'CC Widget Idem B (approve idempotency collision)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-OBSIDEM-P', 'CC Widget Obsidem P (observation idempotency collision)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-OBSIDEM-Q', 'CC Widget Obsidem Q (observation idempotency collision)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-RESV', 'CC Widget Resv (reservation record_version)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  -- ISS-2026-213 regression fixtures (Track B Batch 7) -- dedicated items, never reused
  -- from SKU-CC-A6/A7 above: SKU-CC-A6 already gets a real, successful approval in
  -- scenario 6 below (its own balance is no longer the fixture's original value
  -- afterward) and is also read again later in this file via a bare scalar subquery
  -- expecting exactly one scope item to exist for it -- either of these two new
  -- regression blocks creating a SECOND scope item for SKU-CC-A6 would break one or the
  -- other. Two dedicated items, one per regression (approve-path/reject-path), so
  -- neither collides with the other's own still-active (unresolved pending_review)
  -- scope item either -- freeze_cycle_count_scope refuses a second active count against
  -- a balance already in one.
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-ISS213-APPROVE', 'CC Widget ISS-2026-213 (null-actor approve regression)', null, 'PCS', false, false, false, v_actor, 'supervisor');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CC-ISS213-REJECT', 'CC Widget ISS-2026-213 (null-actor reject regression)', null, 'PCS', false, false, false, v_actor, 'supervisor');

  -- Opening balances (movement_type=opening_balance, already an allowed source_type
  -- pre-widen). Every balance dimension lands on RACK-CC-A unless noted.
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a1', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A1'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 100)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a2', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A2'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 50)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a3', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A3'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 80)),
    v_actor, 'supervisor');
  -- A4: net to a real, existing zero-on-hand balance row (design note 9 -- freeze only
  -- snapshots an EXISTING balance row, including a zero one).
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a4', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A4'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 5)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'adjustment', 'manual', null, 'idem-cc-ob-a4-zero', 'net to zero for fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A4'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', -5)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a5', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A5'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 20)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a6', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A6'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a7', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A7'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 30)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a8', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A8'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 40)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a9', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A9'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 25)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-lot', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-LOT'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 15, 'lot_number', 'LOT-001')),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-serial', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-SERIAL'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 1, 'serial_number', 'SER-001')),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-race', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-RACE'), 'location_id', (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-RACE'), 'uom_code', 'PCS', 'signed_quantity', 10)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-beta', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-BETA'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 60)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-iss213-approve', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-ISS213-APPROVE'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-iss213-reject', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-ISS213-REJECT'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 10)),
    v_actor, 'supervisor');

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-a10', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A10'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 40)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-thresh-in', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-THRESH-IN'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 200)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-thresh-out', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-THRESH-OUT'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 200)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-idem-a', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-IDEM-A'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 50)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-idem-b', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-IDEM-B'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 50)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-obsidem-p', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-OBSIDEM-P'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 30)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-obsidem-q', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-OBSIDEM-Q'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 20)),
    v_actor, 'supervisor');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-resv', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-RESV'), 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 100)),
    v_actor, 'supervisor');
end $$;

\echo '>> RBAC guard: a plain OPS:View-only viewer cannot create a cycle count plan'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
begin
  begin
    perform app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 5, true, null, null, null, null, 'idem-cc-plan-viewer-denied', '00000000-0000-0000-0000-000000200305', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a plain OPS:View-only viewer creating a plan';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> scenario 1: full lifecycle, zero variance -- create plan, freeze scope (real pre-existing balance), assign, blind count with zero variance -> no_variance_closed, no ledger movement posted; then close the plan'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
  v_movement_count integer;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 5, true, null, null, v_item_id, null, 'idem-cc-plan-1', v_supervisor, 'supervisor');
  if v_plan.status <> 'draft' then
    raise exception 'assertion failed: expected a freshly created plan to be draft';
  end if;

  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;
  if v_item.snapshot_expected_quantity <> 100 then
    raise exception 'assertion failed: expected S1 snapshot_expected_quantity=100, got %', v_item.snapshot_expected_quantity;
  end if;
  if v_item.status <> 'pending' then
    raise exception 'assertion failed: expected S1 status=pending after freeze, got %', v_item.status;
  end if;

  -- Note: redaction is computed from the RPC's own CALLING actor, not the assignee --
  -- here the actor is v_supervisor (a real OPS:Override supervisor assigning the item),
  -- so this response correctly stays unredacted. The self-assign case (a plain
  -- OPS:Edit-only counter acting as BOTH actor and assignee) is exercised separately in
  -- scenario 11 below, where redaction correctly DOES apply.
  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');

  v_item := app.record_cycle_count_observation(v_item.id, 100, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a1', v_item.record_version, v_counter1, 'counter1');
  if v_item.status <> 'no_variance_closed' then
    raise exception 'assertion failed: expected S1 status=no_variance_closed, got %', v_item.status;
  end if;
  -- Findings review (HIGH #1/#3): the counter's own submission response must never
  -- reveal the true expected quantity or variance, even though status stays visible.
  if v_item.variance_quantity is not null or v_item.snapshot_expected_quantity is not null then
    raise exception 'assertion failed: expected record_cycle_count_observation to redact variance_quantity/snapshot_expected_quantity for a plain OPS:Edit-only counter''s own response, got variance_quantity=% snapshot_expected_quantity=%', v_item.variance_quantity, v_item.snapshot_expected_quantity;
  end if;
  -- The real value is still correctly zero -- confirmed via a supervisor's own read,
  -- never the blind counter's own response.
  if (app.get_cycle_count_scope_item(v_item.id, v_supervisor)).variance_quantity <> 0 then
    raise exception 'assertion failed: expected S1''s real variance_quantity=0 (visible to a supervisor)';
  end if;

  select count(*) into v_movement_count from app.inventory_movements where source_type = 'cycle_count' and source_id = v_item.id;
  if v_movement_count <> 0 then
    raise exception 'assertion failed: expected zero ledger movements posted for a no-variance count, got %', v_movement_count;
  end if;

  perform app.close_cycle_count_plan(v_plan.id, (select record_version from app.cycle_count_plans where id = v_plan.id), v_supervisor, 'supervisor');
  if (select status from app.cycle_count_plans where id = v_plan.id) <> 'closed' then
    raise exception 'assertion failed: expected plan 1 to close with its only scope item no_variance_closed';
  end if;
end $$;

\echo '>> scenario 2: positive variance within the recount threshold -- pending_review -> approve -> exactly one adjustment movement, balance updated to the observed quantity'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A2');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
  v_balance app.inventory_balances;
  v_movement_count integer;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-2', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');
  v_item := app.record_cycle_count_observation(v_item.id, 53, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a2', v_item.record_version, v_counter1, 'counter1');
  if v_item.status <> 'pending_review' then
    raise exception 'assertion failed: expected S2 status=pending_review (6%% variance within a 20%% recount threshold), got %', v_item.status;
  end if;
  -- Findings review (HIGH #1/#3): the counter's own submission response is blind-
  -- redacted -- the real variance is confirmed separately via a supervisor's own read.
  if v_item.variance_quantity is not null then
    raise exception 'assertion failed: expected record_cycle_count_observation to redact variance_quantity for a plain OPS:Edit-only counter''s own response, got %', v_item.variance_quantity;
  end if;
  if (app.get_cycle_count_scope_item(v_item.id, v_supervisor)).variance_quantity <> 3 then
    raise exception 'assertion failed: expected S2''s real variance_quantity=3 (visible to a supervisor)';
  end if;

  v_item := app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'confirmed positive variance', 'idem-cc-approve-a2', v_supervisor, 'supervisor');
  if v_item.status <> 'adjusted' then
    raise exception 'assertion failed: expected S2 status=adjusted, got %', v_item.status;
  end if;

  select count(*) into v_movement_count from app.inventory_movements where source_type = 'cycle_count' and source_id = v_item.id;
  if v_movement_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE cycle_count adjustment movement for S2, got %', v_movement_count;
  end if;

  select * into v_balance from app.inventory_balances where id = v_item.snapshot_balance_id;
  if v_balance.on_hand <> 53 then
    raise exception 'assertion failed: expected balance on_hand=53 after approval, got %', v_balance.on_hand;
  end if;

  -- Cannot double-approve: a same-item retry (even with a fresh idempotency key)
  -- returns the identical row unchanged and never re-posts a second movement.
  perform app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'confirmed positive variance', 'idem-cc-approve-a2-retry', v_supervisor, 'supervisor');
  select count(*) into v_movement_count from app.inventory_movements where source_type = 'cycle_count' and source_id = v_item.id;
  if v_movement_count <> 1 then
    raise exception 'assertion failed: expected still exactly ONE cycle_count adjustment movement after a same-item approve retry, got %', v_movement_count;
  end if;
end $$;

\echo '>> scenario 3: negative variance within the recount threshold -- pending_review -> approve -> exactly one adjustment movement with a negative signed_quantity, balance decremented'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A3');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
  v_balance app.inventory_balances;
  v_line app.inventory_movement_lines;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-3', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');
  v_item := app.record_cycle_count_observation(v_item.id, 75, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a3', v_item.record_version, v_counter1, 'counter1');
  -- Findings review (HIGH #1/#3): the counter's own submission response redacts
  -- variance_quantity to null -- the real value is confirmed separately below.
  if v_item.status <> 'pending_review' or v_item.variance_quantity is not null then
    raise exception 'assertion failed: expected S3 status=pending_review and a redacted (null) variance_quantity on the counter''s own response, got status=% variance=%', v_item.status, v_item.variance_quantity;
  end if;
  if (app.get_cycle_count_scope_item(v_item.id, v_supervisor)).variance_quantity <> -5 then
    raise exception 'assertion failed: expected S3''s real variance_quantity=-5 (visible to a supervisor)';
  end if;

  v_item := app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'confirmed negative variance', 'idem-cc-approve-a3', v_supervisor, 'supervisor');

  select l.* into v_line from app.inventory_movement_lines l join app.inventory_movements m on m.id = l.movement_id where m.source_type = 'cycle_count' and m.source_id = v_item.id;
  if v_line.signed_quantity <> -5 then
    raise exception 'assertion failed: expected the adjustment movement line signed_quantity=-5, got %', v_line.signed_quantity;
  end if;

  select * into v_balance from app.inventory_balances where id = v_item.snapshot_balance_id;
  if v_balance.on_hand <> 75 then
    raise exception 'assertion failed: expected balance on_hand=75 after approval, got %', v_balance.on_hand;
  end if;
end $$;

\echo '>> scenario 4: zero expected quantity, zero observed quantity -- explicit zero is a real count, not a skip; resolves directly to no_variance_closed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A4');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-4', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;
  if v_item.snapshot_expected_quantity <> 0 then
    raise exception 'assertion failed: expected S4 snapshot_expected_quantity=0 (a real, existing zero-on-hand balance row), got %', v_item.snapshot_expected_quantity;
  end if;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');
  v_item := app.record_cycle_count_observation(v_item.id, 0, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a4', v_item.record_version, v_counter1, 'counter1');
  if v_item.last_observed_quantity <> 0 then
    raise exception 'assertion failed: expected S4 last_observed_quantity=0 (explicit zero, never null/missing), got %', v_item.last_observed_quantity;
  end if;
  if v_item.status <> 'no_variance_closed' then
    raise exception 'assertion failed: expected S4 status=no_variance_closed, got %', v_item.status;
  end if;
end $$;

\echo '>> scenario 5: recount flow -- explicit zero observed on the first attempt (100%% variance) escalates to recount_required; reassign to a different counter; second observation resolves to pending_review, never a second recount_required; supervisor rejects it back to recount_required (mandatory reason); attempting to close the plan while unresolved fails naming the exact count'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A5');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_counter2 uuid := '00000000-0000-0000-0000-000000200304';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-5', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');
  v_item := app.record_cycle_count_observation(v_item.id, 0, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a5-1', v_item.record_version, v_counter1, 'counter1');
  if v_item.status <> 'recount_required' then
    raise exception 'assertion failed: expected S5 status=recount_required after a 100%% first-attempt variance beyond the 20%% threshold, got %', v_item.status;
  end if;
  if v_item.count_attempt_number <> 1 then
    raise exception 'assertion failed: expected S5 count_attempt_number=1, got %', v_item.count_attempt_number;
  end if;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter2, 'counter2', v_item.record_version, v_supervisor, 'supervisor');
  if v_item.assigned_to_auth_user_id <> v_counter2 then
    raise exception 'assertion failed: expected S5 reassigned to counter2';
  end if;

  v_item := app.record_cycle_count_observation(v_item.id, 18, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a5-2', v_item.record_version, v_counter2, 'counter2');
  if v_item.status <> 'pending_review' then
    raise exception 'assertion failed: expected S5 status=pending_review on the 2nd attempt (never a second recount_required), got %', v_item.status;
  end if;
  if v_item.count_attempt_number <> 2 then
    raise exception 'assertion failed: expected S5 count_attempt_number=2, got %', v_item.count_attempt_number;
  end if;

  begin
    perform app.reject_cycle_count_variance(v_item.id, v_item.record_version, null, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected invalid_reason for a reject with no reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_item := app.reject_cycle_count_variance(v_item.id, v_item.record_version, 'variance looks like a location error, recount', v_supervisor, 'supervisor');
  if v_item.status <> 'recount_required' then
    raise exception 'assertion failed: expected S5 status=recount_required after reject, got %', v_item.status;
  end if;
  if v_item.reviewed_by_auth_user_id is not null or v_item.reviewed_at is not null or v_item.review_reason is not null then
    raise exception 'assertion failed: expected reviewed_by/reviewed_at/review_reason to remain null after a reject (reserved for a real adjusted resolution)';
  end if;

  -- Cannot close the plan while this scope item is still unresolved.
  begin
    perform app.close_cycle_count_plan(v_plan.id, (select record_version from app.cycle_count_plans where id = v_plan.id), v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected plan_has_unresolved_scope_items';
  exception
    when others then
      if sqlerrm not like 'plan_has_unresolved_scope_items%' then raise; end if;
      if sqlerrm not like '%1 unresolved%' then
        raise exception 'assertion failed: expected the error to name exactly 1 unresolved scope item, got: %', sqlerrm;
      end if;
  end;
end $$;

\echo '>> scenario 6: self-approval is ALLOWED when requires_separate_approver=false -- the same identity (supervisor) both counts and approves'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A6');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, false, null, null, v_item_id, null, 'idem-cc-plan-6', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_supervisor, 'supervisor', v_item.record_version, v_supervisor, 'supervisor');
  v_item := app.record_cycle_count_observation(v_item.id, 11, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a6', v_item.record_version, v_supervisor, 'supervisor');
  if v_item.status <> 'pending_review' then
    raise exception 'assertion failed: expected S6 status=pending_review, got %', v_item.status;
  end if;

  -- Same identity (supervisor) that submitted the count also approves it -- allowed
  -- because this plan's own requires_separate_approver is false.
  v_item := app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'self-approved, policy allows it', 'idem-cc-approve-a6', v_supervisor, 'supervisor');
  if v_item.status <> 'adjusted' then
    raise exception 'assertion failed: expected S6 status=adjusted (self-approval allowed under requires_separate_approver=false), got %', v_item.status;
  end if;
end $$;

\echo '>> scenario 7: self-approval is BLOCKED when requires_separate_approver=true -- the same identity (supervisor2) that submitted the count cannot approve its own variance; a different supervisor can'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A7');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_supervisor2 uuid := '00000000-0000-0000-0000-000000200310';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-7', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_supervisor2, 'supervisor2', v_item.record_version, v_supervisor, 'supervisor');
  v_item := app.record_cycle_count_observation(v_item.id, 33, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a7', v_item.record_version, v_supervisor2, 'supervisor2');

  begin
    perform app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'self-approving, should be blocked', 'idem-cc-approve-a7-self', v_supervisor2, 'supervisor2');
    raise exception 'assertion failed: expected self_approval_not_allowed';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  -- Scope item was NOT mutated by the rejected self-approval attempt.
  if (select status from app.cycle_count_scope_items where id = v_item.id) <> 'pending_review' then
    raise exception 'assertion failed: expected S7 to remain pending_review after a rejected self-approval attempt';
  end if;

  v_item := app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'approved by a separate supervisor', 'idem-cc-approve-a7', v_supervisor, 'supervisor');
  if v_item.status <> 'adjusted' then
    raise exception 'assertion failed: expected S7 status=adjusted once approved by a genuinely separate supervisor, got %', v_item.status;
  end if;
end $$;

\echo '>> ISS-2026-213 regression: app.approve_cycle_count_variance''s self_approval_not_allowed check now denies (fails closed) a NULL counted_by_auth_user_id on the most recent observation rather than the silent pass-through a bare `=` comparison against a nullable column previously produced -- structurally unreachable via any live caller today (app.record_cycle_count_observation always writes a real, non-null counter), forced directly here to prove the comparison itself, in isolation, is now deterministic'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-ISS213-APPROVE');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-213-approve', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_supervisor, 'supervisor', v_item.record_version, v_supervisor, 'supervisor');
  -- Dedicated fixture item (opening balance 10, never touched by any other scenario in
  -- this file). 11 against a balance of 10 is a 10% variance -- above this plan's own 0%
  -- variance_threshold_pct (so it is not auto-closed as immaterial) but within its 20%
  -- recount_threshold_pct (so a FIRST attempt lands directly on pending_review, not
  -- recount_required) -- the state this regression needs to reach app.approve_cycle_
  -- count_variance's own self-approval check at all.
  v_item := app.record_cycle_count_observation(v_item.id, 11, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-213-approve', v_item.record_version, v_supervisor, 'supervisor');
  if v_item.status <> 'pending_review' then
    raise exception 'test setup assumption violated: expected pending_review after a genuine variance count, got %', v_item.status;
  end if;

  -- Force the nullable actor column directly -- no live caller can leave it null (a real
  -- observation always writes a real, non-null counter). Does not touch
  -- cycle_count_scope_items, so v_item.record_version is unaffected.
  update app.cycle_count_observations set counted_by_auth_user_id = null where scope_item_id = v_item.id;

  begin
    perform app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'attempting approval over a null-actor observation', 'idem-cc-approve-213-nullactor', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected self_approval_not_allowed for a NULL counted_by_auth_user_id (ISS-2026-213 fail-open regression)';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;
end $$;

\echo '>> ISS-2026-213 regression: app.reject_cycle_count_variance''s identical self_approval_not_allowed check, same nullable counted_by_auth_user_id, same fail-closed fix'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-ISS213-REJECT');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-213-reject', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_supervisor, 'supervisor', v_item.record_version, v_supervisor, 'supervisor');
  -- Dedicated fixture item (opening balance 10, never touched by any other scenario in
  -- this file, and distinct from the approve-path regression's own item above so neither
  -- block's still-active pending_review scope item blocks the other's freeze). Same 10%
  -- variance shape as the approve-path regression.
  v_item := app.record_cycle_count_observation(v_item.id, 11, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-213-reject', v_item.record_version, v_supervisor, 'supervisor');
  if v_item.status <> 'pending_review' then
    raise exception 'test setup assumption violated: expected pending_review after a genuine variance count, got %', v_item.status;
  end if;

  update app.cycle_count_observations set counted_by_auth_user_id = null where scope_item_id = v_item.id;

  begin
    perform app.reject_cycle_count_variance(v_item.id, v_item.record_version, 'attempting rejection over a null-actor observation', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected self_approval_not_allowed for a NULL counted_by_auth_user_id (ISS-2026-213 fail-open regression)';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;
end $$;

\echo '>> scenario 8: balance_changed_since_snapshot -- an unrelated real movement posted against the same balance between freeze and approval must reject the approval'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A8');
  v_account_alpha_id uuid := (select owner_account_id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A8');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-8', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;

  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');
  v_item := app.record_cycle_count_observation(v_item.id, 45, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a8', v_item.record_version, v_counter1, 'counter1');
  if v_item.status <> 'pending_review' then
    raise exception 'assertion failed: expected S8 status=pending_review, got %', v_item.status;
  end if;

  -- A real, unrelated movement posts against the identical balance dimension after
  -- freeze but before approval -- the snapshot is now stale.
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'adjustment', 'manual', null, 'idem-cc-a8-unrelated', 'unrelated correction between freeze and approval',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha_id, 'item_master_id', v_item_id, 'location_id', v_rack_a_id, 'uom_code', 'PCS', 'signed_quantity', 2)),
    v_supervisor, 'supervisor');

  begin
    perform app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'attempting to approve a stale snapshot', 'idem-cc-approve-a8', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected balance_changed_since_snapshot';
  exception
    when others then
      if sqlerrm not like 'balance_changed_since_snapshot%' then raise; end if;
  end;

  if (select status from app.cycle_count_scope_items where id = v_item.id) <> 'pending_review' then
    raise exception 'assertion failed: expected S8 to remain pending_review after a rejected stale-snapshot approval attempt';
  end if;
end $$;

\echo '>> scenario 9: scan mismatch rejections (location/item), not_scope_item_claimant, then a successful count and its exact idempotent replay'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_rack_b_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-B');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A9');
  v_wrong_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_counter2 uuid := '00000000-0000-0000-0000-000000200304';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
  v_obs_count integer;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-9', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;
  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');

  begin
    perform app.record_cycle_count_observation(v_item.id, 25, 'PCS', v_rack_b_id, v_item_id, null, null, 'idem-cc-obs-a9-loc', v_item.record_version, v_counter1, 'counter1');
    raise exception 'assertion failed: expected location_mismatch';
  exception
    when others then
      if sqlerrm not like 'location_mismatch%' then raise; end if;
  end;

  begin
    perform app.record_cycle_count_observation(v_item.id, 25, 'PCS', v_rack_a_id, v_wrong_item_id, null, null, 'idem-cc-obs-a9-item', v_item.record_version, v_counter1, 'counter1');
    raise exception 'assertion failed: expected item_mismatch';
  exception
    when others then
      if sqlerrm not like 'item_mismatch%' then raise; end if;
  end;

  begin
    perform app.record_cycle_count_observation(v_item.id, 25, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a9-claimant', v_item.record_version, v_counter2, 'counter2');
    raise exception 'assertion failed: expected not_scope_item_claimant';
  exception
    when others then
      if sqlerrm not like 'not_scope_item_claimant%' then raise; end if;
  end;

  -- None of the three rejected attempts mutated the scope item at all.
  select * into v_item from app.cycle_count_scope_items where id = v_item.id;
  if v_item.status <> 'assigned' or v_item.count_attempt_number <> 0 then
    raise exception 'assertion failed: expected S9 untouched by every rejected attempt (status=assigned, count_attempt_number=0), got status=% count_attempt_number=%', v_item.status, v_item.count_attempt_number;
  end if;

  v_item := app.record_cycle_count_observation(v_item.id, 25, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a9-ok', v_item.record_version, v_counter1, 'counter1');
  if v_item.status <> 'no_variance_closed' or v_item.count_attempt_number <> 1 then
    raise exception 'assertion failed: expected S9 status=no_variance_closed, count_attempt_number=1 after the correct scan, got status=% count_attempt_number=%', v_item.status, v_item.count_attempt_number;
  end if;

  -- Idempotent replay: the identical idempotency key never creates a second
  -- observation row nor double-decrements/re-mutates anything.
  perform app.record_cycle_count_observation(v_item.id, 25, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a9-ok', v_item.record_version, v_counter1, 'counter1');
  select count(*) into v_obs_count from app.cycle_count_observations where scope_item_id = v_item.id;
  if v_obs_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE observation row after a same-idempotency-key replay, got %', v_obs_count;
  end if;
  if (select count_attempt_number from app.cycle_count_scope_items where id = v_item.id) <> 1 then
    raise exception 'assertion failed: expected count_attempt_number to remain 1 after the idempotent replay';
  end if;
end $$;

\echo '>> scenario 10: lot mismatch and serial mismatch rejections on lot-/serial-controlled items'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_lot_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-LOT');
  v_serial_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-SERIAL');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan_lot app.cycle_count_plans;
  v_plan_serial app.cycle_count_plans;
  v_item_lot app.cycle_count_scope_items;
  v_item_serial app.cycle_count_scope_items;
begin
  v_plan_lot := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_lot_item_id, null, 'idem-cc-plan-lot', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan_lot.id, v_plan_lot.record_version, v_supervisor, 'supervisor');
  select * into v_item_lot from app.cycle_count_scope_items where plan_id = v_plan_lot.id and item_master_id = v_lot_item_id;
  if v_item_lot.lot_number <> 'LOT-001' then
    raise exception 'assertion failed: expected the lot scope item to snapshot lot_number=LOT-001, got %', v_item_lot.lot_number;
  end if;
  v_item_lot := app.assign_cycle_count_scope_item(v_item_lot.id, v_counter1, 'counter1', v_item_lot.record_version, v_supervisor, 'supervisor');

  begin
    perform app.record_cycle_count_observation(v_item_lot.id, 15, 'PCS', v_rack_a_id, v_lot_item_id, 'LOT-999', null, 'idem-cc-obs-lot-wrong', v_item_lot.record_version, v_counter1, 'counter1');
    raise exception 'assertion failed: expected lot_mismatch';
  exception
    when others then
      if sqlerrm not like 'lot_mismatch%' then raise; end if;
  end;

  v_item_lot := app.record_cycle_count_observation(v_item_lot.id, 15, 'PCS', v_rack_a_id, v_lot_item_id, 'LOT-001', null, 'idem-cc-obs-lot-ok', v_item_lot.record_version, v_counter1, 'counter1');
  if v_item_lot.status <> 'no_variance_closed' then
    raise exception 'assertion failed: expected the lot scope item to resolve no_variance_closed with a correctly scanned lot, got %', v_item_lot.status;
  end if;

  v_plan_serial := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_serial_item_id, null, 'idem-cc-plan-serial', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan_serial.id, v_plan_serial.record_version, v_supervisor, 'supervisor');
  select * into v_item_serial from app.cycle_count_scope_items where plan_id = v_plan_serial.id and item_master_id = v_serial_item_id;
  if v_item_serial.serial_number <> 'SER-001' then
    raise exception 'assertion failed: expected the serial scope item to snapshot serial_number=SER-001, got %', v_item_serial.serial_number;
  end if;
  v_item_serial := app.assign_cycle_count_scope_item(v_item_serial.id, v_counter1, 'counter1', v_item_serial.record_version, v_supervisor, 'supervisor');

  begin
    perform app.record_cycle_count_observation(v_item_serial.id, 1, 'PCS', v_rack_a_id, v_serial_item_id, null, 'SER-999', 'idem-cc-obs-serial-wrong', v_item_serial.record_version, v_counter1, 'counter1');
    raise exception 'assertion failed: expected serial_mismatch';
  exception
    when others then
      if sqlerrm not like 'serial_mismatch%' then raise; end if;
  end;

  v_item_serial := app.record_cycle_count_observation(v_item_serial.id, 1, 'PCS', v_rack_a_id, v_serial_item_id, null, 'SER-001', 'idem-cc-obs-serial-ok', v_item_serial.record_version, v_counter1, 'counter1');
  if v_item_serial.status <> 'no_variance_closed' then
    raise exception 'assertion failed: expected the serial scope item to resolve no_variance_closed with a correctly scanned serial, got %', v_item_serial.status;
  end if;
end $$;

-- Scenarios 11-15 below are regression coverage added by this session's adversarial
-- findings review (no source prompt change) -- each directly reproduces one of the
-- confirmed findings' own live repro steps, then proves the fix.

\echo '>> scenario 11 (findings review HIGH #1/#3): a plain OPS:Edit-only counter who self-freezes, self-assigns, AND submits their own blind count never sees the true expected quantity/variance in any of those three mutation responses -- only a supervisor''s own read does'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A10');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan app.cycle_count_plans;
  v_frozen app.cycle_count_scope_items;
  v_item app.cycle_count_scope_items;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-a10', v_supervisor, 'supervisor');

  -- Self-freeze: counter1 holds only OPS:Edit/View (no Override), yet freeze itself
  -- only requires OPS:Edit -- exactly finding #3's "mass disclosure via self-freeze"
  -- repro. The returned row(s) must already be redacted.
  select * into v_frozen from app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_counter1, 'counter1 (self-freezing)');
  if v_frozen.snapshot_expected_quantity is not null or v_frozen.variance_quantity is not null or v_frozen.variance_pct is not null or v_frozen.snapshot_record_version is not null then
    raise exception 'assertion failed: expected freeze_cycle_count_scope to redact snapshot_expected_quantity/variance_quantity/variance_pct/snapshot_record_version for a self-freezing OPS:Edit-only counter, got %/%/%/%',
      v_frozen.snapshot_expected_quantity, v_frozen.variance_quantity, v_frozen.variance_pct, v_frozen.snapshot_record_version;
  end if;

  -- Self-assign: finding #1's "self-assign leak, before any count" repro.
  v_item := app.assign_cycle_count_scope_item(v_frozen.id, v_counter1, 'counter1', v_frozen.record_version, v_counter1, 'counter1 (self-assigning)');
  if v_item.snapshot_expected_quantity is not null or v_item.variance_quantity is not null then
    raise exception 'assertion failed: expected assign_cycle_count_scope_item to redact snapshot_expected_quantity/variance_quantity for a self-assigning OPS:Edit-only counter, got % / %', v_item.snapshot_expected_quantity, v_item.variance_quantity;
  end if;

  -- Blind count: finding #1's core repro -- the RPC a counter must call to submit
  -- their own count must never hand back the true expected quantity/variance in the
  -- same response, even for a deliberately wrong guess.
  v_item := app.record_cycle_count_observation(v_item.id, 10, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a10', v_item.record_version, v_counter1, 'counter1');
  if v_item.snapshot_expected_quantity is not null or v_item.variance_quantity is not null or v_item.variance_pct is not null or v_item.snapshot_record_version is not null then
    raise exception 'assertion failed: expected record_cycle_count_observation to redact all four blind-count fields for the submitting OPS:Edit-only counter, got %/%/%/%',
      v_item.snapshot_expected_quantity, v_item.variance_quantity, v_item.variance_pct, v_item.snapshot_record_version;
  end if;

  -- The real numbers exist and are correct -- just never visible to the counter.
  v_item := app.get_cycle_count_scope_item(v_item.id, v_supervisor);
  if v_item.snapshot_expected_quantity <> 40 or v_item.variance_quantity <> -30 then
    raise exception 'assertion failed: expected the real snapshot_expected_quantity=40/variance_quantity=-30 (visible to a supervisor), got % / %', v_item.snapshot_expected_quantity, v_item.variance_quantity;
  end if;

  -- Idempotent-replay short-circuit is also redacted for the same counter (both
  -- return-early paths inside record_cycle_count_observation).
  v_item := app.record_cycle_count_observation(v_item.id, 10, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-a10', v_item.record_version, v_counter1, 'counter1');
  if v_item.snapshot_expected_quantity is not null or v_item.variance_quantity is not null then
    raise exception 'assertion failed: expected the idempotent-replay response to remain redacted for the same OPS:Edit-only counter';
  end if;
end $$;

\echo '>> scenario 12 (findings review MEDIUM #2): variance_threshold_pct is a real, enforced materiality tolerance -- a nonzero variance at or below it auto-closes (no_variance_closed, no ledger movement); a variance beyond it still follows the normal pending_review/approve path'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_in_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-THRESH-IN');
  v_item_out_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-THRESH-OUT');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan_in app.cycle_count_plans;
  v_plan_out app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
  v_movement_count integer;
begin
  -- variance_threshold_pct=5 (materiality tolerance), recount_threshold_pct=50 (kept
  -- generous so this scenario isolates the variance-threshold question, not the
  -- recount-threshold one).
  v_plan_in := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 5, 50, true, null, null, v_item_in_id, null, 'idem-cc-plan-thresh-in', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan_in.id, v_plan_in.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan_in.id and item_master_id = v_item_in_id;
  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');

  -- 200 expected, 197 observed -- a real, nonzero 3-unit/1.5%% variance, deeply within
  -- the configured 5%% tolerance.
  v_item := app.record_cycle_count_observation(v_item.id, 197, 'PCS', v_rack_a_id, v_item_in_id, null, null, 'idem-cc-obs-thresh-in', v_item.record_version, v_counter1, 'counter1');
  if v_item.status <> 'no_variance_closed' then
    raise exception 'assertion failed: expected a variance within variance_threshold_pct to auto-resolve no_variance_closed (materiality tolerance), got %', v_item.status;
  end if;
  if (app.get_cycle_count_scope_item(v_item.id, v_supervisor)).variance_quantity <> -3 then
    raise exception 'assertion failed: expected the real, nonzero variance_quantity=-3 to still be recorded on the row even though the item auto-closed';
  end if;
  select count(*) into v_movement_count from app.inventory_movements where source_type = 'cycle_count' and source_id = v_item.id;
  if v_movement_count <> 0 then
    raise exception 'assertion failed: expected zero ledger movements for a within-tolerance variance (never posted, never reviewed), got %', v_movement_count;
  end if;
  -- The plan can close immediately since its only scope item is already resolved.
  perform app.close_cycle_count_plan(v_plan_in.id, (select record_version from app.cycle_count_plans where id = v_plan_in.id), v_supervisor, 'supervisor');

  -- Comparison item: same 5%% tolerance, but a 20-unit/10%% variance that exceeds it --
  -- must still follow the normal pending_review -> approve path, proving
  -- variance_threshold_pct did not silently swallow every variance.
  v_plan_out := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 5, 50, true, null, null, v_item_out_id, null, 'idem-cc-plan-thresh-out', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan_out.id, v_plan_out.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan_out.id and item_master_id = v_item_out_id;
  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');
  v_item := app.record_cycle_count_observation(v_item.id, 180, 'PCS', v_rack_a_id, v_item_out_id, null, null, 'idem-cc-obs-thresh-out', v_item.record_version, v_counter1, 'counter1');
  if v_item.status <> 'pending_review' then
    raise exception 'assertion failed: expected a variance beyond variance_threshold_pct (but within recount_threshold_pct) to still resolve pending_review, got %', v_item.status;
  end if;

  v_item := app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'confirmed variance beyond materiality tolerance', 'idem-cc-approve-thresh-out', v_supervisor, 'supervisor');
  if v_item.status <> 'adjusted' then
    raise exception 'assertion failed: expected the beyond-tolerance item to reach adjusted via the normal approve path, got %', v_item.status;
  end if;
  select count(*) into v_movement_count from app.inventory_movements where source_type = 'cycle_count' and source_id = v_item.id;
  if v_movement_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE ledger movement for the beyond-tolerance, approved item, got %', v_movement_count;
  end if;
end $$;

\echo '>> scenario 13 (findings review HIGH #4): reusing an approval idempotency key across two DIFFERENT scope items is rejected idempotency_key_conflict -- never silently marks the second item adjusted using the first item''s own movement'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_a_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-IDEM-A');
  v_item_b_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-IDEM-B');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan_a app.cycle_count_plans;
  v_plan_b app.cycle_count_plans;
  v_item_a app.cycle_count_scope_items;
  v_item_b app.cycle_count_scope_items;
  v_movement_a_id uuid;
begin
  v_plan_a := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_a_id, null, 'idem-cc-plan-idem-a', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan_a.id, v_plan_a.record_version, v_supervisor, 'supervisor');
  select * into v_item_a from app.cycle_count_scope_items where plan_id = v_plan_a.id and item_master_id = v_item_a_id;
  v_item_a := app.assign_cycle_count_scope_item(v_item_a.id, v_counter1, 'counter1', v_item_a.record_version, v_supervisor, 'supervisor');
  v_item_a := app.record_cycle_count_observation(v_item_a.id, 48, 'PCS', v_rack_a_id, v_item_a_id, null, null, 'idem-cc-obs-idem-a', v_item_a.record_version, v_counter1, 'counter1');

  v_plan_b := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_b_id, null, 'idem-cc-plan-idem-b', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan_b.id, v_plan_b.record_version, v_supervisor, 'supervisor');
  select * into v_item_b from app.cycle_count_scope_items where plan_id = v_plan_b.id and item_master_id = v_item_b_id;
  v_item_b := app.assign_cycle_count_scope_item(v_item_b.id, v_counter1, 'counter1', v_item_b.record_version, v_supervisor, 'supervisor');
  v_item_b := app.record_cycle_count_observation(v_item_b.id, 41, 'PCS', v_rack_a_id, v_item_b_id, null, null, 'idem-cc-obs-idem-b', v_item_b.record_version, v_counter1, 'counter1');

  -- Item A approves normally with a real key.
  v_item_a := app.approve_cycle_count_variance(v_item_a.id, v_item_a.record_version, 'approve A', 'idem-cc-COLLIDING-KEY', v_supervisor, 'supervisor');
  if v_item_a.status <> 'adjusted' or v_item_a.adjustment_movement_id is null then
    raise exception 'assertion failed: expected item A to approve normally and reach adjusted';
  end if;
  v_movement_a_id := v_item_a.adjustment_movement_id;

  -- Item B reuses the IDENTICAL idempotency key -- must be rejected, never silently
  -- attach item A's own movement to item B.
  begin
    perform app.approve_cycle_count_variance(v_item_b.id, v_item_b.record_version, 'approve B', 'idem-cc-COLLIDING-KEY', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected idempotency_key_conflict for a key reused across two different scope items'' own approvals';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- Item B was NOT mutated by the rejected collision attempt -- still pending_review,
  -- no adjustment_movement_id, its own real variance never posted.
  select * into v_item_b from app.cycle_count_scope_items where id = v_item_b.id;
  if v_item_b.status <> 'pending_review' or v_item_b.adjustment_movement_id is not null then
    raise exception 'assertion failed: expected item B to remain pending_review with no adjustment_movement_id after the rejected idempotency-key-collision approval, got status=% adjustment_movement_id=%', v_item_b.status, v_item_b.adjustment_movement_id;
  end if;
  if exists (select 1 from app.inventory_movements where source_type = 'cycle_count' and source_id = v_item_b.id) then
    raise exception 'assertion failed: expected zero ledger movements attributed to item B after the rejected collision attempt';
  end if;

  -- Item B approves cleanly with its own, distinct idempotency key, posting its own,
  -- distinct movement -- never item A's.
  v_item_b := app.approve_cycle_count_variance(v_item_b.id, v_item_b.record_version, 'approve B, real key', 'idem-cc-approve-idem-b-real', v_supervisor, 'supervisor');
  if v_item_b.status <> 'adjusted' or v_item_b.adjustment_movement_id is null or v_item_b.adjustment_movement_id = v_movement_a_id then
    raise exception 'assertion failed: expected item B to approve with its own real, distinct movement (never item A''s), got adjustment_movement_id=% (item A''s was %)', v_item_b.adjustment_movement_id, v_movement_a_id;
  end if;
end $$;

\echo '>> scenario 14 (findings review MEDIUM #5): reusing an observation idempotency key across two DIFFERENT scope items is rejected idempotency_key_conflict -- never silently drops the second item''s real observation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_p_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-OBSIDEM-P');
  v_item_q_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-OBSIDEM-Q');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan_p app.cycle_count_plans;
  v_plan_q app.cycle_count_plans;
  v_item_p app.cycle_count_scope_items;
  v_item_q app.cycle_count_scope_items;
begin
  v_plan_p := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_p_id, null, 'idem-cc-plan-obsidem-p', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan_p.id, v_plan_p.record_version, v_supervisor, 'supervisor');
  select * into v_item_p from app.cycle_count_scope_items where plan_id = v_plan_p.id and item_master_id = v_item_p_id;
  v_item_p := app.assign_cycle_count_scope_item(v_item_p.id, v_counter1, 'counter1', v_item_p.record_version, v_supervisor, 'supervisor');

  v_plan_q := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_q_id, null, 'idem-cc-plan-obsidem-q', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan_q.id, v_plan_q.record_version, v_supervisor, 'supervisor');
  select * into v_item_q from app.cycle_count_scope_items where plan_id = v_plan_q.id and item_master_id = v_item_q_id;
  v_item_q := app.assign_cycle_count_scope_item(v_item_q.id, v_counter1, 'counter1', v_item_q.record_version, v_supervisor, 'supervisor');

  -- P counts normally with the shared key.
  v_item_p := app.record_cycle_count_observation(v_item_p.id, 30, 'PCS', v_rack_a_id, v_item_p_id, null, null, 'idem-cc-OBS-COLLIDE-KEY', v_item_p.record_version, v_counter1, 'counter1');
  if v_item_p.status <> 'no_variance_closed' or v_item_p.count_attempt_number <> 1 then
    raise exception 'assertion failed: expected P to resolve no_variance_closed, count_attempt_number=1, got status=% count_attempt_number=%', v_item_p.status, v_item_p.count_attempt_number;
  end if;

  -- Q reuses the IDENTICAL key -- must be rejected, never silently no-op on Q.
  begin
    perform app.record_cycle_count_observation(v_item_q.id, 15, 'PCS', v_rack_a_id, v_item_q_id, null, null, 'idem-cc-OBS-COLLIDE-KEY', v_item_q.record_version, v_counter1, 'counter1');
    raise exception 'assertion failed: expected idempotency_key_conflict for a key reused across two different scope items'' own observations';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- Q was NOT silently marked counted -- still assigned, zero attempts, exactly as
  -- finding #5 found it.
  select * into v_item_q from app.cycle_count_scope_items where id = v_item_q.id;
  if v_item_q.status <> 'assigned' or v_item_q.count_attempt_number <> 0 then
    raise exception 'assertion failed: expected Q to remain assigned/count_attempt_number=0 after the rejected idempotency-key-collision observation, got status=% count_attempt_number=%', v_item_q.status, v_item_q.count_attempt_number;
  end if;

  -- Q counts cleanly with its own, distinct idempotency key (observed=20=expected, a
  -- real zero variance, to keep this scenario's own assertion independent of the
  -- recount-threshold question already covered by scenario 5).
  v_item_q := app.record_cycle_count_observation(v_item_q.id, 20, 'PCS', v_rack_a_id, v_item_q_id, null, null, 'idem-cc-obs-obsidem-q-real', v_item_q.record_version, v_counter1, 'counter1');
  if v_item_q.status <> 'no_variance_closed' or v_item_q.count_attempt_number <> 1 then
    raise exception 'assertion failed: expected Q to resolve no_variance_closed, count_attempt_number=1 once counted with its own real key, got status=% count_attempt_number=%', v_item_q.status, v_item_q.count_attempt_number;
  end if;
end $$;

\echo '>> scenario 15 (findings review MEDIUM #6): a real reservation placed against the identical balance between count and approval now bumps record_version (harden migration 20260730280000) and is correctly caught by balance_changed_since_snapshot -- an intervening reservation is no longer invisible to approval'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_a_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A');
  v_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-RESV');
  v_owner_account_id uuid := (select owner_account_id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-RESV');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_plan app.cycle_count_plans;
  v_item app.cycle_count_scope_items;
  v_balance_before app.inventory_balances;
  v_balance_after_reserve app.inventory_balances;
  v_balance_after_release app.inventory_balances;
  v_reservation app.inventory_reservations;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-resv', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;
  v_item := app.assign_cycle_count_scope_item(v_item.id, v_counter1, 'counter1', v_item.record_version, v_supervisor, 'supervisor');
  -- 100 expected, 95 observed -- a real -5 variance, within the 20%% recount threshold.
  v_item := app.record_cycle_count_observation(v_item.id, 95, 'PCS', v_rack_a_id, v_item_id, null, null, 'idem-cc-obs-resv', v_item.record_version, v_counter1, 'counter1');

  select * into v_balance_before from app.inventory_balances where id = v_item.snapshot_balance_id;

  -- A real, legitimate concurrent reservation lands against the identical balance
  -- dimension between count and approval (e.g. a new sales order reserving stock) --
  -- exactly finding #6's own repro.
  v_reservation := app.reserve_inventory(
    v_tenant1, v_warehouse_id, v_owner_account_id, v_item_id, v_rack_a_id, null, null, 10, 'manual', null, 'idem-cc-resv-reserve', v_supervisor, 'supervisor'
  );

  select * into v_balance_after_reserve from app.inventory_balances where id = v_item.snapshot_balance_id;
  if v_balance_after_reserve.reserved <> 10 then
    raise exception 'assertion failed: expected reserved=10 after app.reserve_inventory, got %', v_balance_after_reserve.reserved;
  end if;
  -- The direct, root-cause assertion: app.reserve_inventory''s own reserved-quantity
  -- UPDATE now bumps record_version (harden migration 20260730280000) -- previously
  -- unchanged and completely invisible to any optimistic-concurrency check.
  if v_balance_after_reserve.record_version <= v_balance_before.record_version then
    raise exception 'assertion failed: expected app.reserve_inventory to bump app.inventory_balances.record_version (% -> expected greater), got %', v_balance_before.record_version, v_balance_after_reserve.record_version;
  end if;

  -- Approval against the item's own pre-reservation p_expected_version must now be
  -- rejected balance_changed_since_snapshot -- previously silently succeeded.
  begin
    perform app.approve_cycle_count_variance(v_item.id, v_item.record_version, 'attempting to approve despite an intervening reservation', 'idem-cc-approve-resv', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected balance_changed_since_snapshot after an intervening reservation change';
  exception
    when others then
      if sqlerrm not like 'balance_changed_since_snapshot%' then raise; end if;
  end;

  if (select status from app.cycle_count_scope_items where id = v_item.id) <> 'pending_review' then
    raise exception 'assertion failed: expected the scope item to remain pending_review after the rejected stale-snapshot approval attempt';
  end if;

  -- app.release_inventory_reservation''s own reserved-quantity UPDATE bumps
  -- record_version a second, independent time (same harden migration).
  perform app.release_inventory_reservation(v_reservation.id, 'test cleanup', v_supervisor, 'supervisor');
  select * into v_balance_after_release from app.inventory_balances where id = v_item.snapshot_balance_id;
  if v_balance_after_release.reserved <> 0 then
    raise exception 'assertion failed: expected reserved=0 after app.release_inventory_reservation, got %', v_balance_after_release.reserved;
  end if;
  if v_balance_after_release.record_version <= v_balance_after_reserve.record_version then
    raise exception 'assertion failed: expected app.release_inventory_reservation to also bump app.inventory_balances.record_version (% -> expected greater), got %', v_balance_after_reserve.record_version, v_balance_after_release.record_version;
  end if;
end $$;

\echo '>> REAL two-process concurrent freeze race (Prompt 239 section 13''s own reservation/activity conflict requirement): two draft plans, both scoped to the identical single-balance dimension (RACK-CC-RACE / SKU-CC-RACE), each attempt app.freeze_cycle_count_scope concurrently -- exactly one must claim the balance as a live scope item; the other must fail cleanly (or remain draft with zero scope items); the balance is never double-counted as in-flight across two plans simultaneously'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_race_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-RACE');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_plan_a app.cycle_count_plans;
  v_plan_b app.cycle_count_plans;
begin
  v_plan_a := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_race_item_id, null, 'idem-cc-plan-race-a', v_supervisor, 'supervisor');
  v_plan_b := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_race_item_id, null, 'idem-cc-plan-race-b', v_supervisor, 'supervisor');
end $$;

select id as race_plan_a_id, record_version as race_plan_a_version from app.cycle_count_plans where idempotency_key = 'idem-cc-plan-race-a' \gset
select id as race_plan_b_id, record_version as race_plan_b_version from app.cycle_count_plans where idempotency_key = 'idem-cc-plan-race-b' \gset
select current_database() as pg_test_db \gset

\set race_sql_a 'select app.freeze_cycle_count_scope(''' :race_plan_a_id ''', ' :race_plan_a_version ', ''00000000-0000-0000-0000-000000200302'', ''supervisor'');'
\set race_sql_b 'select app.freeze_cycle_count_scope(''' :race_plan_b_id ''', ' :race_plan_b_version ', ''00000000-0000-0000-0000-000000200302'', ''supervisor'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-cycle-count-race-a.out
\setenv RACE_OUT_B /tmp/cargogrid-cycle-count-race-b.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_race_item_id uuid := (select id from app.item_masters where tenant_id = (select id from app.tenants where slug = 'cyclecnt1') and code = 'SKU-CC-RACE');
  v_balance_id uuid;
  v_live_scope_item_count integer;
  v_active_plan_count integer;
begin
  select id into v_balance_id from app.inventory_balances where item_master_id = v_race_item_id and status = 'on_hand';

  select count(*) into v_live_scope_item_count from app.cycle_count_scope_items
    where snapshot_balance_id = v_balance_id and status not in ('adjusted', 'no_variance_closed', 'cancelled');
  if v_live_scope_item_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE live scope item claiming the race balance across both plans (never zero, never two), got % -- see /tmp/cargogrid-cycle-count-race-a.out and -b.out for both real process outcomes', v_live_scope_item_count;
  end if;

  select count(*) into v_active_plan_count from app.cycle_count_plans where idempotency_key in ('idem-cc-plan-race-a', 'idem-cc-plan-race-b') and status = 'active';
  if v_active_plan_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE of the two racing plans to have successfully frozen (status=active), got %', v_active_plan_count;
  end if;

  raise notice 'concurrent freeze race proof: exactly 1 live scope item claims the shared balance, exactly 1 of 2 racing plans reached active -- the partial unique index + FOR UPDATE row lock (design note 3) correctly serialized two real, independent psql processes';
end $$;

\echo '>> empty freeze is a valid, non-error outcome: a plan scoped to a location with no balance at all freezes to zero scope items and can close immediately'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_rack_b_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-B');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_plan app.cycle_count_plans;
  v_scope_item_count integer;
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'spot', 0, 20, true, null, v_rack_b_id, null, null, 'idem-cc-plan-empty', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');

  select count(*) into v_scope_item_count from app.cycle_count_scope_items where plan_id = v_plan.id;
  if v_scope_item_count <> 0 then
    raise exception 'assertion failed: expected zero scope items for an empty-location freeze, got %', v_scope_item_count;
  end if;
  if (select status from app.cycle_count_plans where id = v_plan.id) <> 'active' then
    raise exception 'assertion failed: expected the plan to be active even after an empty freeze';
  end if;

  perform app.close_cycle_count_plan(v_plan.id, (select record_version from app.cycle_count_plans where id = v_plan.id), v_supervisor, 'supervisor');
  if (select status from app.cycle_count_plans where id = v_plan.id) <> 'closed' then
    raise exception 'assertion failed: expected an empty plan to close immediately';
  end if;

  -- Re-freezing an already-frozen (active) plan is rejected.
  begin
    perform app.freeze_cycle_count_scope(v_plan.id, (select record_version from app.cycle_count_plans where id = v_plan.id), v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected freeze_already_done -- closed is not draft';
  exception
    when others then
      if sqlerrm not like 'freeze_already_done%' then raise; end if;
  end;
end $$;

\echo '>> cannot cancel an already-adjusted scope item; cancel_cycle_count_plan cancels every unresolved item while leaving resolved ones untouched'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_scope_item_a2_id uuid := (select s.id from app.cycle_count_scope_items s join app.item_masters m on m.id = s.item_master_id where m.code = 'SKU-CC-A2' and s.tenant_id = v_tenant1);
begin
  begin
    perform app.cancel_cycle_count_scope_item(v_scope_item_a2_id, 'oops, changed my mind', (select record_version from app.cycle_count_scope_items where id = v_scope_item_a2_id), v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected scope_item_already_resolved for an already-adjusted item';
  exception
    when others then
      if sqlerrm not like 'scope_item_already_resolved%' then raise; end if;
  end;
end $$;

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_item_id uuid;
  v_plan app.cycle_count_plans;
  v_scope_item app.cycle_count_scope_items;
begin
  perform app.create_item_master(v_tenant1, (select owner_account_id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-A1'), 'SKU-CC-CANCELPLAN', 'CC Widget Cancel Plan', null, 'PCS', false, false, false, v_supervisor, 'supervisor');
  v_item_id := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-CANCELPLAN');
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-cc-ob-cancelplan', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', (select owner_account_id from app.item_masters where id = v_item_id), 'item_master_id', v_item_id, 'location_id', (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CC-A'), 'uom_code', 'PCS', 'signed_quantity', 9)),
    v_supervisor, 'supervisor');

  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, v_item_id, null, 'idem-cc-plan-cancel', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select * into v_scope_item from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_item_id;

  begin
    perform app.cancel_cycle_count_plan(v_plan.id, null, v_plan.record_version, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected invalid_reason for a plan cancel with no reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  perform app.cancel_cycle_count_plan(v_plan.id, 'test cleanup', (select record_version from app.cycle_count_plans where id = v_plan.id), v_supervisor, 'supervisor');
  if (select status from app.cycle_count_plans where id = v_plan.id) <> 'cancelled' then
    raise exception 'assertion failed: expected the plan to be cancelled';
  end if;
  if (select status from app.cycle_count_scope_items where id = v_scope_item.id) <> 'cancelled' then
    raise exception 'assertion failed: expected the plan''s own unresolved scope item to also be cancelled';
  end if;

  -- The already-adjusted S2 scope item (a different plan entirely) is never touched by
  -- any of the cancel operations above.
  if (select s.status from app.cycle_count_scope_items s join app.item_masters m on m.id = s.item_master_id where m.code = 'SKU-CC-A2' and s.tenant_id = v_tenant1) <> 'adjusted' then
    raise exception 'assertion failed: expected S2 (a different plan) to remain adjusted, untouched by an unrelated plan cancellation';
  end if;
end $$;

\echo '>> blind-count redaction: a plain OPS:Edit-only counter reading an adjusted scope item sees snapshot_expected_quantity/variance_quantity/variance_pct/snapshot_record_version all null; an OPS:Override supervisor sees the real values -- server-side, no caller-supplied parameter can defeat it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_counter1 uuid := '00000000-0000-0000-0000-000000200303';
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_scope_item_a2_id uuid := (select s.id from app.cycle_count_scope_items s join app.item_masters m on m.id = s.item_master_id where m.code = 'SKU-CC-A2' and s.tenant_id = v_tenant1);
  v_blind app.cycle_count_scope_items;
  v_visible app.cycle_count_scope_items;
begin
  v_blind := app.get_cycle_count_scope_item(v_scope_item_a2_id, v_counter1);
  if v_blind.snapshot_expected_quantity is not null or v_blind.variance_quantity is not null or v_blind.variance_pct is not null or v_blind.snapshot_record_version is not null then
    raise exception 'assertion failed: expected a plain OPS:Edit-only counter to see all four blind-redacted fields as null';
  end if;
  -- Every other field remains real and visible even for the blind counter.
  if v_blind.status <> 'adjusted' or v_blind.uom_code <> 'PCS' then
    raise exception 'assertion failed: expected non-redacted fields to still be visible to a blind counter';
  end if;

  v_visible := app.get_cycle_count_scope_item(v_scope_item_a2_id, v_supervisor);
  if v_visible.snapshot_expected_quantity <> 50 or v_visible.variance_quantity <> 3 then
    raise exception 'assertion failed: expected an OPS:Override supervisor to see the real snapshot_expected_quantity=50/variance_quantity=3, got % / %', v_visible.snapshot_expected_quantity, v_visible.variance_quantity;
  end if;

  -- The identical rule applies to the list read, row by row.
  if exists (
    select 1 from app.list_cycle_count_scope_items(v_tenant1, v_counter1, null, 'adjusted', null, 200) s
    where s.id = v_scope_item_a2_id and s.snapshot_expected_quantity is not null
  ) then
    raise exception 'assertion failed: expected list_cycle_count_scope_items to redact snapshot_expected_quantity for a blind counter too';
  end if;
end $$;

\echo '>> bounded/filtered reads: p_limit is capped server-side at 200 even when a caller requests more; an explicit low p_limit truncates a real multi-row result'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_plan_rows app.cycle_count_plans[];
  v_scope_item_rows app.cycle_count_scope_items[];
begin
  select array_agg(p) into v_plan_rows from app.list_cycle_count_plans(v_tenant1, v_supervisor, null, null, 500) p;
  if array_length(v_plan_rows, 1) > 200 then
    raise exception 'assertion failed: expected the hard cap of 200 rows to apply even when p_limit=500, got %', array_length(v_plan_rows, 1);
  end if;

  select array_agg(s) into v_scope_item_rows from app.list_cycle_count_scope_items(v_tenant1, v_supervisor, null, null, null, 1) s;
  if array_length(v_scope_item_rows, 1) <> 1 then
    raise exception 'assertion failed: expected p_limit=1 to truncate a real multi-row scope-item result to exactly 1 row, got %', array_length(v_scope_item_rows, 1);
  end if;
end $$;

\echo '>> cross-owner isolation: a customer_user-layer actor scoped to owner Alpha cannot read or act on a scope item owned by Beta, at both the RPC level and raw-RLS level'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000200302';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000200307';
  v_beta_item_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CC-BETA');
  v_beta_account_id uuid := (select owner_account_id from app.item_masters where id = v_beta_item_id);
  v_alpha_scope_item_id uuid := (select s.id from app.cycle_count_scope_items s join app.item_masters m on m.id = s.item_master_id where m.code = 'SKU-CC-A6' and s.tenant_id = v_tenant1);
  v_plan app.cycle_count_plans;
  v_beta_scope_item_id uuid;
  v_rows app.cycle_count_scope_items[];
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'full', 0, 20, true, null, null, null, v_beta_account_id, 'idem-cc-plan-beta', v_supervisor, 'supervisor');
  perform app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, v_supervisor, 'supervisor');
  select id into v_beta_scope_item_id from app.cycle_count_scope_items where plan_id = v_plan.id and item_master_id = v_beta_item_id;
  if v_beta_scope_item_id is null then
    raise exception 'assertion failed: expected a Beta-owned scope item to have been frozen';
  end if;

  -- RPC level.
  begin
    perform app.get_cycle_count_scope_item(v_beta_scope_item_id, v_customer_alpha);
    raise exception 'assertion failed: expected insufficient_authority for customer_alpha reading a Beta-owned scope item';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- customer_alpha CAN read their own (Alpha-owned) scope item.
  perform app.get_cycle_count_scope_item(v_alpha_scope_item_id, v_customer_alpha);

  select array_agg(s) into v_rows from app.list_cycle_count_scope_items(v_tenant1, v_customer_alpha, null, null, null, 200) s;
  if exists (select 1 from unnest(v_rows) r where r.id = v_beta_scope_item_id) then
    raise exception 'assertion failed: expected an unfiltered list for customer_alpha to never include Beta''s own scope item';
  end if;
  if not exists (select 1 from unnest(v_rows) r where r.id = v_alpha_scope_item_id) then
    raise exception 'assertion failed: expected an unfiltered list for customer_alpha to include Alpha''s own scope item';
  end if;

  -- Raw RLS level -- bypassing every RPC entirely.
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000200307", "role": "authenticated"}', true);

  if exists (select 1 from app.cycle_count_scope_items where id = v_beta_scope_item_id) then
    raise exception 'assertion failed: raw RLS leak -- customer_alpha directly selected a Beta-owned scope item row';
  end if;
  if not exists (select 1 from app.cycle_count_scope_items where id = v_alpha_scope_item_id) then
    raise exception 'assertion failed: expected RLS to still permit customer_alpha to directly select Alpha''s own scope item row';
  end if;

  reset role;
end $$;

\echo '>> cross-tenant isolation: tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority on every RPC against tenant1''s real records, and raw RLS denies a direct select'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cyclecnt1');
  v_tenant2_rep uuid := '00000000-0000-0000-0000-000000200309';
  v_plan_id uuid := (select id from app.cycle_count_plans where tenant_id = v_tenant1 and idempotency_key = 'idem-cc-plan-2');
  v_scope_item_id uuid := (select s.id from app.cycle_count_scope_items s join app.item_masters m on m.id = s.item_master_id where m.code = 'SKU-CC-A2' and s.tenant_id = v_tenant1);
begin
  begin
    perform app.get_cycle_count_plan(v_plan_id, v_tenant2_rep);
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor reading a tenant1 plan';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_cycle_count_scope_item(v_scope_item_id, v_tenant2_rep);
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor reading a tenant1 scope item';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    -- Reuses a REAL, already-consumed tenant1 idempotency key -- must still be
    -- rejected on authority grounds, never silently short-circuited into tenant1's
    -- real data (idempotent-replay-after-authority regression, bug class a).
    perform app.create_cycle_count_plan(v_tenant1, (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CC-1'), 'full', 0, 20, true, null, null, null, null, 'idem-cc-plan-2', v_tenant2_rep, 'rep2');
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor creating a plan under tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000200309", "role": "authenticated"}', true);

  if exists (select 1 from app.cycle_count_plans where id = v_plan_id) then
    raise exception 'assertion failed: raw RLS leak -- tenant2 rep directly selected a tenant1 plan row';
  end if;

  reset role;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004 regression guard): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly; no RPC carries a PUBLIC execute grant'
do $$
declare
  v_has_priv boolean;
begin
  select has_table_privilege('anon', 'app.cycle_count_plans', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.cycle_count_plans'; end if;
  select has_table_privilege('anon', 'app.cycle_count_scope_items', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.cycle_count_scope_items'; end if;
  select has_table_privilege('anon', 'app.cycle_count_observations', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.cycle_count_observations'; end if;

  select has_function_privilege('anon', 'app.create_cycle_count_plan(uuid, uuid, text, numeric, numeric, boolean, uuid, uuid, uuid, uuid, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.create_cycle_count_plan'; end if;
  select has_function_privilege('anon', 'app.approve_cycle_count_variance(uuid, integer, text, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.approve_cycle_count_variance'; end if;
  select has_function_privilege('anon', 'app.freeze_cycle_count_scope(uuid, integer, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.freeze_cycle_count_scope'; end if;
  select has_function_privilege('anon', 'app.next_cycle_count_plan_number(uuid)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.next_cycle_count_plan_number'; end if;

  select has_table_privilege('authenticated', 'app.cycle_count_plans', 'SELECT') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated must hold RLS-scoped SELECT on app.cycle_count_plans'; end if;
  select has_table_privilege('authenticated', 'app.cycle_count_scope_items', 'INSERT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT hold direct INSERT on app.cycle_count_scope_items -- writes only via SECURITY DEFINER RPCs'; end if;
  select has_table_privilege('authenticated', 'app.cycle_count_observations', 'UPDATE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT hold direct UPDATE on app.cycle_count_observations (append-only)'; end if;

  select has_function_privilege('authenticated', 'app.create_cycle_count_plan(uuid, uuid, text, numeric, numeric, boolean, uuid, uuid, uuid, uuid, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated must hold EXECUTE on app.create_cycle_count_plan'; end if;
  select has_function_privilege('authenticated', 'app.next_cycle_count_plan_number(uuid)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT hold EXECUTE on the internal-only app.next_cycle_count_plan_number counter helper'; end if;

  select has_table_privilege('service_role', 'app.cycle_count_plans', 'INSERT') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: service_role must hold direct INSERT on app.cycle_count_plans'; end if;
  select has_function_privilege('service_role', 'app.next_cycle_count_plan_number(uuid)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: service_role must hold EXECUTE on app.next_cycle_count_plan_number'; end if;
end $$;

\echo '>> ATW-020 db-test suite: ALL assertions passed'
select 'ALL ATW-020 db-test assertions passed' as result;
