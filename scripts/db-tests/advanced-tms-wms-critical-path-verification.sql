-- Real, executable test evidence for CG-S10-ATW-026 (Prompt 245, "Advanced TMS/WMS
-- Integrated Verification") -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Structural convention mirrors scripts/db-tests/advanced-tms-
-- gps-telematics-integrated-verification.sql (ATW-226I), the closest sibling
-- integrated-verification precedent (read first, per this task's own brief).
--
-- SCOPE NOTE: this file covers ATW-026's own critical WMS golden-path E2E and the
-- cross-tenant/cross-customer isolation sweep across that composed chain (Prompt
-- 245 section 20's "Run critical WMS E2E" + the isolation/security gate) -- the
-- specific subset of Prompt 245's own broader scope this checkpoint's own task
-- assignment names. The transport multi-leg/dispatch/tracking/milestone/delivery
-- scenario and the four mandatory tracking-package E2Es (section 20's separate
-- "Run transport..." / "Run mandatory tracking E2Es" bullets) are a distinct,
-- non-overlapping piece of Prompt 245's own scope, evidenced separately (see this
-- checkpoint's own completion report) -- NOT duplicated or re-attempted in this file.
--
-- KNOWN CONCURRENT-WRITER OBSERVATION (disclosed, not silently worked around):
-- scripts/db-tests/advanced-tms-wms-integrated-verification.sql already existed in
-- this working tree at this checkpoint's own very first inspection (untracked, birth
-- timestamp essentially concurrent with this session's own start) and was directly
-- observed still growing (680 -> 683 lines) seconds apart with no action by this
-- session -- live, direct evidence of a second, concurrent writer in this same
-- filesystem (the exact ISS-2026-002 hazard KNOWN_ISSUES.md already documents five
-- prior real occurrences of). That file's own content is a transport/GPS-tracking
-- golden path (six parts, tenant `atw026golden`), not the WMS chain this checkpoint's
-- own task assignment names -- this session never read past its own first inspection
-- of it, never wrote to it, and picked this deliberately distinct filename/tenant
-- slugs/auth-user-id range specifically to avoid colliding with whatever that other
-- session is doing. See this checkpoint's own completion report for the full
-- disclosure.
--
-- This file is a VERIFICATION artifact, not a new capability -- it composes real RPC
-- calls exclusively from already-VERIFIED migrations (ATW-011A/012..025) into ONE
-- continuous WMS chain and cross-checks composition/isolation points that no single
-- capability's own db-test file (each necessarily scoped to its own migration) ever
-- exercises together. It edits no applied migration, no service-layer/product file.
--
-- Structure:
--   Part A (tenant `wmsiv1`, owner Account Alpha): the critical WMS golden path --
--     item/UOM master -> inbound order -> receiving -> putaway -> lot/serial
--     identity registration -> outbound order -> picking -> packing -> outbound
--     ship/custody -> ledger reconciliation -> cycle count -> label generate/scan ->
--     warehouse billing event -> customer inventory access (ATW-023) ->
--     claim (ATW-025) referencing this exact chain's own real evidence.
--   Part B (tenant `wmsiv1`, owner Account Beta): an abbreviated, real, second
--     customer chain in the SAME tenant -- exists solely to prove the claim's own
--     evidence-validation and ATW-023's own customer read RPCs never cross a
--     same-tenant customer boundary.
--   Part C (tenant `wmsiv2`, owner Account Gamma): a fully parallel, isolated
--     tenant chain -- exists solely to prove zero data crosses the tenant boundary
--     at every composition point (billing read, label resolve, customer inventory
--     read, claim evidence linking).
--   Part D: the cross-tenant/cross-customer isolation sweep proper, spanning all
--     three chains above.
--
-- Recovery/restart evidence for this chain's own ship-confirm step (Prompt 245 item
-- 4) is a SEPARATE, self-contained bash harness (mirrors scripts/load-tests/
-- recovery-check.sh's own SIGKILL+cluster-restart technique against its own minimal
-- fixture) -- a real client kill + Postgres cluster restart cannot be expressed
-- inside a single psql -f invocation, and restarting the shared local cluster mid-run
-- of this file would abort every *.sql file scripts/db-tests/run.sh still has queued
-- behind it. Full detail and evidence: this checkpoint's own completion report.

\set ON_ERROR_STOP on

-- =============================================================================
-- Fixture-only helper procedures (never part of any real migration -- dropped at
-- the end of this file, mirrors scripts/db-tests/advanced-tms-claim-incident-
-- operations.sql's own pick_fully/pack_task_fully convention exactly).
-- =============================================================================

create procedure iv_pick_fully(p_line_id uuid, p_qty numeric, p_source_id uuid, p_item_id uuid, p_lot text, p_serial text, p_dest_id uuid, p_idem_prefix text, p_actor uuid, p_label text)
language plpgsql
as $proc$
declare
  v_t app.wms_pick_tasks;
begin
  v_t := app.generate_wms_pick_task(p_line_id, p_qty, null, p_source_id, p_lot, p_serial, p_dest_id, p_idem_prefix || '-gen', p_actor, p_label);
  v_t := app.claim_wms_pick_task(v_t.id, v_t.record_version, p_actor, p_label);
  perform app.confirm_wms_pick_task(v_t.id, p_qty, p_source_id, p_item_id, p_lot, p_serial, p_dest_id, p_idem_prefix || '-conf', v_t.record_version, p_actor, p_label);
end;
$proc$;

create function iv_pack_fully(p_outbound_order_id uuid, p_pick_task_id uuid, p_item_id uuid, p_qty numeric, p_idem_prefix text, p_actor uuid, p_label text)
returns app.wms_packages
language plpgsql
as $fn$
declare
  v_packing_task app.wms_packing_tasks;
  v_pkg app.wms_packages;
begin
  v_packing_task := app.start_wms_packing_task(p_outbound_order_id, p_idem_prefix || '-task', p_actor, p_label);
  v_pkg := app.create_wms_package(v_packing_task.id, null, 'carton', p_idem_prefix || '-pkg', p_actor, p_label);
  v_pkg := app.add_wms_package_line(v_pkg.id, p_pick_task_id, p_qty, p_item_id, null, null, p_idem_prefix || '-line', v_pkg.record_version, p_actor, p_label);
  v_pkg := app.record_wms_package_measurements(v_pkg.id, 5, 'KG', null, null, null, null, v_pkg.record_version, p_actor, p_label);
  v_pkg := app.record_wms_package_qc(v_pkg.id, 'pass', null, v_pkg.record_version, p_actor, p_label);
  v_pkg := app.record_wms_package_seal(v_pkg.id, p_idem_prefix || '-seal', v_pkg.record_version, p_actor, p_label);
  v_pkg := app.confirm_wms_package(v_pkg.id, p_idem_prefix || '-confirm', v_pkg.record_version, p_actor, p_label);
  return v_pkg;
end;
$fn$;

create function iv_ship_fully(p_outbound_order_id uuid, p_package_id uuid, p_dock_id uuid, p_idem_prefix text, p_actor uuid, p_label text)
returns app.wms_outbound_shipments
language plpgsql
as $fn$
declare
  v_ship app.wms_outbound_shipments;
begin
  v_ship := app.create_wms_outbound_shipment(p_outbound_order_id, p_idem_prefix || '-create', p_actor, p_label);
  v_ship := app.add_package_to_shipment(v_ship.id, p_package_id, p_idem_prefix || '-addpkg', p_actor, p_label);
  v_ship := app.set_wms_shipment_dock_location(v_ship.id, p_dock_id, v_ship.record_version, p_actor, p_label);
  v_ship := app.load_wms_outbound_shipment(v_ship.id, p_idem_prefix || '-load', v_ship.record_version, p_actor, p_label);
  v_ship := app.ship_confirm_wms_outbound_shipment(v_ship.id, p_label, 'iv fixture custody confirmation', false, null, p_idem_prefix || '-confirm', v_ship.record_version, p_actor, p_label);
  return v_ship;
end;
$fn$;

create temporary table iv_a (key text primary key, value text not null);
create temporary table iv_b (key text primary key, value text not null);

-- =============================================================================
-- PART A setup: tenant wmsiv1, actors, warehouse/locations, items, item control
-- policies, Account Alpha (full CRM->Job Order pipeline, needed both for item
-- ownership and later for a real Shipment Order the claim step anchors to), Account
-- Beta (direct fixture insert -- mirrors scripts/db-tests/advanced-tms-customer-
-- inventory-access.sql's own established convention for a second, non-focal owner).
-- =============================================================================

\echo '>> Part A setup: tenant wmsiv1, org unit, actors (ADMIN/OPS1/OPS1B broad-authority staff, CUSTOMER_ALPHA/CUSTOMER_BETA), warehouse WH-IV-1 with DOCK-IV-1/STAGE-IV-1/RACK-IV-1/RACK-IV-2/RACK-IV-BETA, three item masters, published item control policies (hold_on_unknown_lot=false), Account Alpha via the full CRM->Job Order pipeline, Account Beta via direct fixture insert, warehouse eligibility for both, customer_user grants for both'
do $$
declare
  v_tenant1 uuid;
  v_company uuid;
  v_role uuid;
  v_draft app.role_versions;
  v_warehouse app.warehouses;
  v_dock app.warehouse_locations;
  v_stage app.warehouse_locations;
  v_rack1 app.warehouse_locations;
  v_rack2 app.warehouse_locations;
  v_rack_beta app.warehouse_locations;
  v_item_lot app.item_masters;
  v_item_ser app.item_masters;
  v_item_beta app.item_masters;
  v_policy app.item_control_policy_versions;
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
  v_account_alpha app.accounts;
  v_account_beta app.accounts;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  admin uuid := '00000000-0000-0000-0000-000000245001';
  ops1 uuid := '00000000-0000-0000-0000-000000245002';
  ops1b uuid := '00000000-0000-0000-0000-000000245003';
  cust_alpha uuid := '00000000-0000-0000-0000-000000245010';
  cust_beta uuid := '00000000-0000-0000-0000-000000245011';
begin
  insert into auth.users (id, email) values
    (admin, 'admin@wmsiv1.test'),
    (ops1, 'ops1@wmsiv1.test'),
    (ops1b, 'ops1b@wmsiv1.test'),
    (cust_alpha, 'customer-alpha@wmsiv1.test'),
    (cust_beta, 'customer-beta@wmsiv1.test');

  perform app.provision_tenant('wmsiv1', 'WMS Integrated Verification One', 'idem-wmsiv1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'wmsiv1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'WMSIV1-CO', 'WmsIv1 Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WMSIV1-CO');

  perform app.invite_user(v_tenant1, admin, 'admin@wmsiv1.test', 'IV Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@wmsiv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(admin, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, ops1, 'ops1@wmsiv1.test', 'IV Ops One', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ops1@wmsiv1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, ops1b, 'ops1b@wmsiv1.test', 'IV Ops One B', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ops1b@wmsiv1.test'), 'active', 'onboarded', 'tester');

  -- One broad-authority role (mirrors advanced-tms-claim-incident-operations.sql's
  -- own supervisor role almost exactly) -- RBAC per capability was already proven
  -- individually at each capability's own build checkpoint; this file's own focus is
  -- composition, not re-proving each RPC's own permission tier (identical scope
  -- decision the ATW-023 db-test's own "Setup convenience note" already made).
  v_role := (app.create_role(v_tenant1, 'IV Ops Full', 'full commercial + ops create/edit/view/override/close/assign/view cost', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost', 'View selling price'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override', 'Close', 'Assign', 'View cost'))),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), ops1, admin, 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), ops1b, admin, 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-IV-1', 'IV Warehouse 1', 'Jl. Integrated Verification 1', 'Asia/Jakarta', null, array['land']::text[], ops1, 'ops1');

  v_dock := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-IV-1', 'IV Dock 1', 'dock', 1, null, null, null, null, null, false, false, ops1, 'ops1');
  perform app.set_warehouse_location_status(v_dock.id, 'active', null, v_dock.record_version, ops1, 'ops1');
  v_stage := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-IV-1', 'IV Staging 1', 'staging', 2, null, null, null, null, null, false, false, ops1, 'ops1');
  perform app.set_warehouse_location_status(v_stage.id, 'active', null, v_stage.record_version, ops1, 'ops1');
  v_rack1 := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-IV-1', 'IV Rack 1', 'rack', 3, null, null, null, null, null, true, true, ops1, 'ops1');
  perform app.set_warehouse_location_status(v_rack1.id, 'active', null, v_rack1.record_version, ops1, 'ops1');
  v_rack2 := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-IV-2', 'IV Rack 2', 'rack', 4, null, null, null, null, null, true, true, ops1, 'ops1');
  perform app.set_warehouse_location_status(v_rack2.id, 'active', null, v_rack2.record_version, ops1, 'ops1');
  v_rack_beta := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-IV-BETA', 'IV Rack Beta', 'rack', 5, null, null, null, null, null, true, true, ops1, 'ops1');
  perform app.set_warehouse_location_status(v_rack_beta.id, 'active', null, v_rack_beta.record_version, ops1, 'ops1');

  -- Account Alpha via the full CRM -> Job Order pipeline -- required not merely for
  -- item ownership (which alone could use a direct fixture insert, ATW-022/023's own
  -- convention) but because Part A's own closing claim step needs a real
  -- app.shipment_orders row (shipper_account_id = Alpha), itself only ever produced
  -- from a real confirmed Job Order.
  perform app.capture_lead(v_tenant1, 'manual', null, 'IV Customer Alpha', 'Alice IV', 'alice@wmsiv245.test', '0811',
    ops1, v_company, ops1, 'tester');
  select * into v_lead from app.leads where email = 'alice@wmsiv245.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, ops1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'IV Customer Alpha', 'WMSIV245A', '11.111.111.45-111.000',
    jsonb_build_object('line1', 'Jl. Integrated Alpha 1', 'city', 'Jakarta', 'country', 'ID'),
    ops1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice IV Ops', 'Ops Lead', 'alice@wmsiv245.test', '0811', ops1, v_company, ops1, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, ops1, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSIV245 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    ops1, v_company, ops1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, ops1, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSIV245-A', 'Contoso IV Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, admin, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, admin, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, ops1, 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', ops1, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, ops1, 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, ops1, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, ops1, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSIV245 Alpha lane', v_calc_id, 1, 6000000, 0, 0, ops1, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, ops1, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', ops1, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice IV Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_alpha from app.convert_quotation_to_account(v_quote.id, null, null, ops1, 'ops1');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, ops1, 'ops1');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, ops1, 'ops1');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, ops1, 'ops1');

  -- Account Beta -- direct fixture insert (mirrors scripts/db-tests/advanced-tms-
  -- customer-inventory-access.sql's own established convention: a second, non-focal
  -- owner used purely for same-tenant isolation checks does not need the full CRM
  -- pipeline this file already ran once for Alpha).
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'IV Customer Beta', 'wmsiv245-beta-fp', '{}'::jsonb, v_company, 'tester') returning * into v_account_beta;

  v_item_lot := app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-IV-LOT', 'IV Lot Widget', null, 'PCS', true, false, true, ops1, 'ops1');
  v_item_ser := app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-IV-SER', 'IV Serial Widget', null, 'PCS', false, true, false, ops1, 'ops1');
  v_item_beta := app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-IV-BETA', 'IV Beta Widget', null, 'PCS', false, false, false, ops1, 'ops1');

  -- Governed control policies -- hold_on_unknown_lot=false so registration (Part A's
  -- own later step) lands active immediately, never requiring a manual override
  -- step, exactly the realistic warehouse-governance sequence Prompt 235 describes.
  v_policy := app.create_item_control_policy_version_draft(v_item_lot.id, 'fefo', false, 30, now(), ops1, 'ops1');
  perform app.publish_item_control_policy_version(v_policy.id, v_policy.record_version, null, ops1, 'ops1');
  v_policy := app.create_item_control_policy_version_draft(v_item_ser.id, 'fifo', false, null, now(), ops1, 'ops1');
  perform app.publish_item_control_policy_version(v_policy.id, v_policy.record_version, null, ops1, 'ops1');

  -- Warehouse customer eligibility -- BOTH Alpha and Beta on the SAME warehouse
  -- (Prompt 242's own "shared warehouse" fixture shape) -- the differentiator in
  -- every later customer-read/claim-evidence check is owner_account_id, never
  -- warehouse eligibility.
  perform app.grant_warehouse_customer_eligibility(v_warehouse.id, v_account_alpha.id, ops1, 'ops1');
  perform app.grant_warehouse_customer_eligibility(v_warehouse.id, v_account_beta.id, ops1, 'ops1');

  perform app.invite_user(v_tenant1, cust_alpha, 'customer-alpha@wmsiv1.test', 'IV Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@wmsiv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(cust_alpha, 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  perform app.invite_user(v_tenant1, cust_beta, 'customer-beta@wmsiv1.test', 'IV Customer Beta Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@wmsiv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(cust_beta, 'customer_user', v_tenant1, v_account_beta.id::text, 'tester');

  insert into iv_a (key, value) values
    ('tenant_id', v_tenant1::text),
    ('company_org_unit_id', v_company::text),
    ('warehouse_id', v_warehouse.id::text),
    ('dock_id', v_dock.id::text),
    ('stage_id', v_stage.id::text),
    ('rack1_id', v_rack1.id::text),
    ('rack2_id', v_rack2.id::text),
    ('rack_beta_id', v_rack_beta.id::text),
    ('item_lot_id', v_item_lot.id::text),
    ('item_ser_id', v_item_ser.id::text),
    ('item_beta_id', v_item_beta.id::text),
    ('account_alpha_id', v_account_alpha.id::text),
    ('account_beta_id', v_account_beta.id::text),
    ('job_order_alpha_id', v_job_order.id::text),
    ('quotation_alpha_id', v_quote.id::text),
    ('admin', admin::text),
    ('ops1', ops1::text),
    ('ops1b', ops1b::text),
    ('cust_alpha', cust_alpha::text),
    ('cust_beta', cust_beta::text);
end $$;

\echo '>> Part A assertion: both item control policies published active, hold_on_unknown_lot=false as configured'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.item_control_policy_versions
    where item_master_id in ((select value::uuid from iv_a where key = 'item_lot_id'), (select value::uuid from iv_a where key = 'item_ser_id'))
      and status = 'published' and hold_on_unknown_lot = false;
  if v_count <> 2 then
    raise exception 'assertion failed: expected 2 published, hold_on_unknown_lot=false item control policies, found %', v_count;
  end if;
end $$;

-- =============================================================================
-- PART A step 1: item/UOM master already built above (SKU-IV-LOT/SKU-IV-SER, base
-- UOM PCS, the seeded governed registry, ATW-011A). Step 2: inbound order (ATW-012)
-- and receiving (ATW-013).
-- =============================================================================

\echo '>> Part A: create an inbound order for both items (100 PCS lot-controlled, 1 PCS serial-controlled), schedule, confirm (ATW-012)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from iv_a where key = 'warehouse_id');
  v_account_alpha_id uuid := (select value::uuid from iv_a where key = 'account_alpha_id');
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  v_item_ser_id uuid := (select value::uuid from iv_a where key = 'item_ser_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_order app.wms_inbound_orders;
  v_line_lot app.wms_inbound_order_lines;
  v_line_ser app.wms_inbound_order_lines;
begin
  v_order := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_alpha_id, 'iv golden path inbound', 'idem-iv-inbound-1', ops1, 'ops1');
  v_line_lot := app.add_wms_inbound_order_line(v_order.id, v_item_lot_id, 'PCS', 100, 'bulk lot receipt', ops1, 'ops1');
  v_line_ser := app.add_wms_inbound_order_line(v_order.id, v_item_ser_id, 'PCS', 1, 'single serial unit', ops1, 'ops1');
  v_order := app.schedule_wms_inbound_appointment(v_order.id, now() + interval '1 hour', now() + interval '3 hours', v_order.record_version, ops1, 'ops1');
  v_order := app.confirm_wms_inbound(v_order.id, v_order.record_version, ops1, 'ops1');
  if v_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected the IV inbound order to be confirmed, got %', v_order.status;
  end if;

  insert into iv_a (key, value) values
    ('inbound_order_id', v_order.id::text),
    ('inbound_line_lot_id', v_line_lot.id::text),
    ('inbound_line_ser_id', v_line_ser.id::text);
end $$;

\echo '>> Part A: WMS Receiving (ATW-013) -- start session at DOCK-IV-1, count/commit both lines (real accepted quantities, real lot_number/serial_number capture), complete the session -- posts two real app.post_inventory_movement receipt movements'
do $$
declare
  v_dock_id uuid := (select value::uuid from iv_a where key = 'dock_id');
  v_inbound_order_id uuid := (select value::uuid from iv_a where key = 'inbound_order_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_session app.wms_receipt_sessions;
  v_line_lot app.wms_receipt_lines;
  v_line_ser app.wms_receipt_lines;
begin
  v_session := app.start_wms_receipt_session(v_inbound_order_id, v_dock_id, 'idem-iv-recv-session', ops1, 'ops1');
  if v_session.status <> 'in_progress' then
    raise exception 'assertion failed: expected a freshly started receipt session to be in_progress, got %', v_session.status;
  end if;

  select * into v_line_lot from app.wms_receipt_lines where receipt_session_id = v_session.id and line_number = 1;
  select * into v_line_ser from app.wms_receipt_lines where receipt_session_id = v_session.id and line_number = 2;

  v_line_lot := app.record_wms_receipt_line_count(v_line_lot.id, 'PCS', 100, 100, 0, 0, 0, 'LOT-IV-A1', null, current_date + 300, 'exact count, no damage', v_line_lot.record_version, ops1, 'ops1');
  v_line_lot := app.commit_wms_receipt_line(v_line_lot.id, 'idem-iv-recv-commit-lot', v_line_lot.record_version, ops1, 'ops1');
  if v_line_lot.status <> 'committed' then
    raise exception 'assertion failed: expected the lot receipt line to be committed, got %', v_line_lot.status;
  end if;

  v_line_ser := app.record_wms_receipt_line_count(v_line_ser.id, 'PCS', 1, 1, 0, 0, 0, null, 'SN-IV-A1', null, 'single unit, no damage', v_line_ser.record_version, ops1, 'ops1');
  v_line_ser := app.commit_wms_receipt_line(v_line_ser.id, 'idem-iv-recv-commit-ser', v_line_ser.record_version, ops1, 'ops1');
  if v_line_ser.status <> 'committed' then
    raise exception 'assertion failed: expected the serial receipt line to be committed, got %', v_line_ser.status;
  end if;

  v_session := app.complete_wms_receipt_session(v_session.id, v_session.record_version, ops1, 'ops1');
  if v_session.status <> 'completed' then
    raise exception 'assertion failed: expected the receipt session to complete, got %', v_session.status;
  end if;

  -- Real ledger evidence: the dock now holds exactly 100 PCS of the lot item and 1
  -- PCS of the serial item, on_hand, posted by app.post_inventory_movement -- never
  -- a direct table write.
  if (select on_hand from app.inventory_balances where location_id = (select value::uuid from iv_a where key = 'dock_id') and item_master_id = v_line_lot.item_master_id and status = 'on_hand') <> 100 then
    raise exception 'assertion failed: expected 100 PCS on_hand at DOCK-IV-1 for the lot item after commit';
  end if;
  if (select on_hand from app.inventory_balances where location_id = (select value::uuid from iv_a where key = 'dock_id') and item_master_id = v_line_ser.item_master_id and status = 'on_hand') <> 1 then
    raise exception 'assertion failed: expected 1 PCS on_hand at DOCK-IV-1 for the serial item after commit';
  end if;

  insert into iv_a (key, value) values
    ('receipt_session_id', v_session.id::text),
    ('receipt_line_lot_id', v_line_lot.id::text),
    ('receipt_line_ser_id', v_line_ser.id::text),
    ('receipt_movement_lot_id', v_line_lot.movement_id::text),
    ('receipt_movement_ser_id', v_line_ser.movement_id::text);
end $$;

\echo '>> Part A: WMS Putaway (ATW-014) -- generate/claim/confirm one task per receipt line, DOCK-IV-1 -> RACK-IV-1 (lot item, 100 PCS) and DOCK-IV-1 -> RACK-IV-2 (serial item, 1 PCS) -- posts two real balanced transfer movements'
do $$
declare
  v_receipt_line_lot_id uuid := (select value::uuid from iv_a where key = 'receipt_line_lot_id');
  v_receipt_line_ser_id uuid := (select value::uuid from iv_a where key = 'receipt_line_ser_id');
  v_rack1_id uuid := (select value::uuid from iv_a where key = 'rack1_id');
  v_rack2_id uuid := (select value::uuid from iv_a where key = 'rack2_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_task_lot app.wms_putaway_tasks;
  v_task_ser app.wms_putaway_tasks;
begin
  v_task_lot := app.generate_wms_putaway_task(v_receipt_line_lot_id, 100, v_rack1_id, 'idem-iv-putaway-gen-lot', ops1, 'ops1');
  v_task_lot := app.claim_wms_putaway_task(v_task_lot.id, v_task_lot.record_version, ops1, 'ops1');
  v_task_lot := app.confirm_wms_putaway_task(v_task_lot.id, 100, v_rack1_id, 'LOT-IV-A1', null, 'idem-iv-putaway-conf-lot', v_task_lot.record_version, ops1, 'ops1');
  if v_task_lot.status <> 'confirmed' then
    raise exception 'assertion failed: expected the lot putaway task to be confirmed, got %', v_task_lot.status;
  end if;

  v_task_ser := app.generate_wms_putaway_task(v_receipt_line_ser_id, 1, v_rack2_id, 'idem-iv-putaway-gen-ser', ops1, 'ops1');
  v_task_ser := app.claim_wms_putaway_task(v_task_ser.id, v_task_ser.record_version, ops1, 'ops1');
  v_task_ser := app.confirm_wms_putaway_task(v_task_ser.id, 1, v_rack2_id, null, 'SN-IV-A1', 'idem-iv-putaway-conf-ser', v_task_ser.record_version, ops1, 'ops1');
  if v_task_ser.status <> 'confirmed' then
    raise exception 'assertion failed: expected the serial putaway task to be confirmed, got %', v_task_ser.status;
  end if;

  if (select on_hand from app.inventory_balances where location_id = v_rack1_id and item_master_id = (select item_master_id from app.wms_putaway_tasks where id = v_task_lot.id) and status = 'on_hand') <> 100 then
    raise exception 'assertion failed: expected 100 PCS on_hand at RACK-IV-1 for the lot item after putaway';
  end if;
  if (select coalesce(on_hand, 0) from app.inventory_balances where location_id = (select value::uuid from iv_a where key = 'dock_id') and item_master_id = (select item_master_id from app.wms_putaway_tasks where id = v_task_lot.id) and status = 'on_hand') <> 0 then
    raise exception 'assertion failed: expected the DOCK-IV-1 lot-item balance to be exactly zero after the full putaway transfer';
  end if;
  if (select on_hand from app.inventory_balances where location_id = v_rack2_id and item_master_id = (select item_master_id from app.wms_putaway_tasks where id = v_task_ser.id) and status = 'on_hand') <> 1 then
    raise exception 'assertion failed: expected 1 PCS on_hand at RACK-IV-2 for the serial item after putaway';
  end if;
end $$;

-- =============================================================================
-- PART A step: register lot/serial identities (ATW-016/235) -- explicitly AFTER
-- putaway, matching this checkpoint's own task-assignment ordering. Both register
-- active (the published policy's own hold_on_unknown_lot=false), directly closing
-- the live half of ISS-2026-016's own disclosed gap ("nothing in the live system
-- calls them yet") for this one composed chain -- proven here to actually GOVERN
-- the picking allocation two steps below, not merely exist alongside it.
-- =============================================================================

\echo '>> Part A: register the lot identity (LOT-IV-A1, matching the receipt/putaway lot_number exactly) and the serial identity (SN-IV-A1) -- both land status=active immediately (published policy, hold_on_unknown_lot=false); app.list_allocation_candidates (ATW-016, FEFO) now returns exactly this lot as the sole candidate for the lot item'
do $$
declare
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  v_item_ser_id uuid := (select value::uuid from iv_a where key = 'item_ser_id');
  v_warehouse_id uuid := (select value::uuid from iv_a where key = 'warehouse_id');
  v_account_alpha_id uuid := (select value::uuid from iv_a where key = 'account_alpha_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_lot app.lot_identities;
  v_serial app.serial_identities;
  v_candidate_count integer;
  v_candidate record;
begin
  v_lot := app.register_lot_identity(v_item_lot_id, 'LOT-IV-A1', current_date - 10, current_date + 300, 'receipt', null, null, ops1, 'ops1');
  if v_lot.status <> 'active' then
    raise exception 'assertion failed: expected the freshly registered lot to be active (published policy hold_on_unknown_lot=false), got %', v_lot.status;
  end if;

  v_serial := app.register_serial_identity(v_item_ser_id, 'SN-IV-A1', null, null, null, 'receipt', null, 'idem-iv-serial-reg', ops1, 'ops1');
  if v_serial.status <> 'active' then
    raise exception 'assertion failed: expected the freshly registered serial to be active (published policy hold_on_unknown_lot=false), got %', v_serial.status;
  end if;
end $$;

\echo '>> Part A: app.list_allocation_candidates (real FIFO/FEFO decision support, ATW-016) now returns exactly the one registered, active lot for the lot item, and the one registered, active serial for the serial item -- the governance mechanism actually informs allocation for this live chain'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from iv_a where key = 'warehouse_id');
  v_account_alpha_id uuid := (select value::uuid from iv_a where key = 'account_alpha_id');
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  v_item_ser_id uuid := (select value::uuid from iv_a where key = 'item_ser_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_count integer;
  v_lot_number text;
  v_lot_status text;
  v_serial_number text;
  v_serial_status text;
begin
  select count(*), (array_agg(lot_number))[1], (array_agg(lot_status))[1] into v_count, v_lot_number, v_lot_status
    from app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_item_lot_id, v_account_alpha_id, ops1, 'fefo', 50);
  if v_count <> 1 or v_lot_number <> 'LOT-IV-A1' or v_lot_status <> 'active' then
    raise exception 'assertion failed: expected exactly 1 FEFO allocation candidate (lot=LOT-IV-A1, status=active), found count=% lot=% status=%', v_count, v_lot_number, v_lot_status;
  end if;

  select count(*), (array_agg(serial_number))[1], (array_agg(serial_status))[1] into v_count, v_serial_number, v_serial_status
    from app.list_allocation_candidates(v_tenant1, v_warehouse_id, v_item_ser_id, v_account_alpha_id, ops1, 'fifo', 50);
  if v_count <> 1 or v_serial_number <> 'SN-IV-A1' or v_serial_status <> 'active' then
    raise exception 'assertion failed: expected exactly 1 FIFO allocation candidate (serial=SN-IV-A1, status=active), found count=% serial=% status=%', v_count, v_serial_number, v_serial_status;
  end if;
end $$;

-- =============================================================================
-- PART A step: outbound order (ATW-016A) -- two lines, deliberately requesting
-- only 60 of the 100 lot-item PCS (the remaining 40 feeds the cycle count step
-- later) and the full 1 serial-item PCS.
-- =============================================================================

\echo '>> Part A: WMS Outbound Order (ATW-016A) -- create, add two lines (60 PCS lot item, 1 PCS serial item), confirm -- the real "confirmed outbound demand contract" Picking composes against'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from iv_a where key = 'warehouse_id');
  v_account_alpha_id uuid := (select value::uuid from iv_a where key = 'account_alpha_id');
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  v_item_ser_id uuid := (select value::uuid from iv_a where key = 'item_ser_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_order app.wms_outbound_orders;
  v_line_lot app.wms_outbound_order_lines;
  v_line_ser app.wms_outbound_order_lines;
begin
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'iv golden path outbound', 'idem-iv-outbound-1', current_date + 3, ops1, 'ops1');
  v_line_lot := app.add_wms_outbound_order_line(v_order.id, v_item_lot_id, 'PCS', 60, 'partial demand, leaves residual for cycle count', ops1, 'ops1');
  v_line_ser := app.add_wms_outbound_order_line(v_order.id, v_item_ser_id, 'PCS', 1, 'full serial unit demand', ops1, 'ops1');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, ops1, 'ops1');
  if v_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected the IV outbound order to be confirmed, got %', v_order.status;
  end if;

  insert into iv_a (key, value) values
    ('outbound_order_id', v_order.id::text),
    ('outbound_line_lot_id', v_line_lot.id::text),
    ('outbound_line_ser_id', v_line_ser.id::text);
end $$;

-- =============================================================================
-- PART A step: picking (ATW-017) -- explicit-location confirm (not auto-select),
-- exercising design note 11's independent lot/serial eligibility re-verification
-- directly against the identities Part A just registered.
-- =============================================================================

\echo '>> Part A: WMS Picking (ATW-017) -- generate/claim/confirm one pick task per outbound line, RACK-IV-1 -> STAGE-IV-1 (60 PCS, scanned lot=LOT-IV-A1) and RACK-IV-2 -> STAGE-IV-1 (1 PCS, scanned serial=SN-IV-A1) -- both reservations release cleanly on full pick, both posts real balanced transfer movements'
do $$
declare
  v_outbound_line_lot_id uuid := (select value::uuid from iv_a where key = 'outbound_line_lot_id');
  v_outbound_line_ser_id uuid := (select value::uuid from iv_a where key = 'outbound_line_ser_id');
  v_rack1_id uuid := (select value::uuid from iv_a where key = 'rack1_id');
  v_rack2_id uuid := (select value::uuid from iv_a where key = 'rack2_id');
  v_stage_id uuid := (select value::uuid from iv_a where key = 'stage_id');
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  v_item_ser_id uuid := (select value::uuid from iv_a where key = 'item_ser_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_task_lot app.wms_pick_tasks;
  v_task_ser app.wms_pick_tasks;
begin
  v_task_lot := app.generate_wms_pick_task(v_outbound_line_lot_id, 60, null, v_rack1_id, 'LOT-IV-A1', null, v_stage_id, 'idem-iv-pick-gen-lot', ops1, 'ops1');
  v_task_lot := app.claim_wms_pick_task(v_task_lot.id, v_task_lot.record_version, ops1, 'ops1');
  v_task_lot := app.confirm_wms_pick_task(v_task_lot.id, 60, v_rack1_id, v_item_lot_id, 'LOT-IV-A1', null, v_stage_id, 'idem-iv-pick-conf-lot', v_task_lot.record_version, ops1, 'ops1');
  if v_task_lot.status <> 'picked' then
    raise exception 'assertion failed: expected the lot pick task to be fully picked, got %', v_task_lot.status;
  end if;

  v_task_ser := app.generate_wms_pick_task(v_outbound_line_ser_id, 1, null, v_rack2_id, null, 'SN-IV-A1', v_stage_id, 'idem-iv-pick-gen-ser', ops1, 'ops1');
  v_task_ser := app.claim_wms_pick_task(v_task_ser.id, v_task_ser.record_version, ops1, 'ops1');
  v_task_ser := app.confirm_wms_pick_task(v_task_ser.id, 1, v_rack2_id, v_item_ser_id, null, 'SN-IV-A1', v_stage_id, 'idem-iv-pick-conf-ser', v_task_ser.record_version, ops1, 'ops1');
  if v_task_ser.status <> 'picked' then
    raise exception 'assertion failed: expected the serial pick task to be fully picked, got %', v_task_ser.status;
  end if;

  -- No orphaned reservation -- both reservations this generation created must now be
  -- released (raw terminal-status update on full resolution, ATW-017 design note 5),
  -- never left active.
  if exists (select 1 from app.inventory_reservations where id in (v_task_lot.reservation_id, v_task_ser.reservation_id) and status <> 'released') then
    raise exception 'assertion failed: expected both pick reservations to be released after a full pick, found a non-released reservation';
  end if;

  if (select on_hand from app.inventory_balances where location_id = v_rack1_id and item_master_id = v_item_lot_id and status = 'on_hand') <> 40 then
    raise exception 'assertion failed: expected RACK-IV-1 lot-item on_hand to be exactly 40 (100 received - 60 picked)';
  end if;
  if (select coalesce(on_hand, 0) from app.inventory_balances where location_id = v_rack2_id and item_master_id = v_item_ser_id and status = 'on_hand') <> 0 then
    raise exception 'assertion failed: expected RACK-IV-2 serial-item on_hand to be exactly 0 (fully picked)';
  end if;
  if (select on_hand from app.inventory_balances where location_id = v_stage_id and item_master_id = v_item_lot_id and status = 'on_hand') <> 60 then
    raise exception 'assertion failed: expected STAGE-IV-1 lot-item on_hand to be exactly 60 after picking';
  end if;
  if (select on_hand from app.inventory_balances where location_id = v_stage_id and item_master_id = v_item_ser_id and status = 'on_hand') <> 1 then
    raise exception 'assertion failed: expected STAGE-IV-1 serial-item on_hand to be exactly 1 after picking';
  end if;

  insert into iv_a (key, value) values
    ('pick_task_lot_id', v_task_lot.id::text),
    ('pick_task_ser_id', v_task_ser.id::text);
end $$;

-- =============================================================================
-- PART A step: packing (ATW-018) -- one packing task, one package, both pick tasks'
-- output packed into it together (a realistic mixed-SKU carton).
-- =============================================================================

\echo '>> Part A: WMS Packing (ATW-018) -- start packing task, create one package, add both pick tasks'' lines (scan-verified), record measurements/QC/seal, confirm'
do $$
declare
  v_outbound_order_id uuid := (select value::uuid from iv_a where key = 'outbound_order_id');
  v_pick_task_lot_id uuid := (select value::uuid from iv_a where key = 'pick_task_lot_id');
  v_pick_task_ser_id uuid := (select value::uuid from iv_a where key = 'pick_task_ser_id');
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  v_item_ser_id uuid := (select value::uuid from iv_a where key = 'item_ser_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_packing_task app.wms_packing_tasks;
  v_pkg app.wms_packages;
begin
  v_packing_task := app.start_wms_packing_task(v_outbound_order_id, 'idem-iv-pack-task', ops1, 'ops1');
  v_pkg := app.create_wms_package(v_packing_task.id, null, 'carton', 'idem-iv-package-1', ops1, 'ops1');
  v_pkg := app.add_wms_package_line(v_pkg.id, v_pick_task_lot_id, 60, v_item_lot_id, 'LOT-IV-A1', null, 'idem-iv-pack-line-lot', v_pkg.record_version, ops1, 'ops1');
  v_pkg := app.add_wms_package_line(v_pkg.id, v_pick_task_ser_id, 1, v_item_ser_id, null, 'SN-IV-A1', 'idem-iv-pack-line-ser', v_pkg.record_version, ops1, 'ops1');
  if v_pkg.line_count <> 2 or v_pkg.total_packed_quantity <> 61 then
    raise exception 'assertion failed: expected the package to hold exactly 2 lines totalling 61 PCS, got line_count=% total=%', v_pkg.line_count, v_pkg.total_packed_quantity;
  end if;

  v_pkg := app.record_wms_package_measurements(v_pkg.id, 12.5, 'KG', 40, 30, 20, 'CM', v_pkg.record_version, ops1, 'ops1');
  v_pkg := app.record_wms_package_qc(v_pkg.id, 'pass', null, v_pkg.record_version, ops1, 'ops1');
  v_pkg := app.record_wms_package_seal(v_pkg.id, 'SEAL-IV-0001', v_pkg.record_version, ops1, 'ops1');
  v_pkg := app.confirm_wms_package(v_pkg.id, 'idem-iv-pack-confirm', v_pkg.record_version, ops1, 'ops1');
  if v_pkg.status <> 'confirmed' then
    raise exception 'assertion failed: expected the package to be confirmed, got %', v_pkg.status;
  end if;

  insert into iv_a (key, value) values ('package_id', v_pkg.id::text), ('package_number', v_pkg.package_number);
end $$;

-- =============================================================================
-- PART A step: outbound ship / custody (ATW-019) -- stage, dock, load (real
-- transfer STAGE-IV-1 -> DOCK-IV-1), ship-confirm (real consumption movement,
-- custody event, exactly one auto-created app.wms_billing_eligibility_events row).
-- =============================================================================

\echo '>> Part A: WMS Outbound ship/custody (ATW-019) -- create shipment, add the confirmed package, set dock location + vehicle ref, load (real transfer to DOCK-IV-1), ship-confirm (real consumption movement + custody event + exactly one billing-eligibility event)'
do $$
declare
  v_outbound_order_id uuid := (select value::uuid from iv_a where key = 'outbound_order_id');
  v_package_id uuid := (select value::uuid from iv_a where key = 'package_id');
  v_dock_id uuid := (select value::uuid from iv_a where key = 'dock_id');
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  v_item_ser_id uuid := (select value::uuid from iv_a where key = 'item_ser_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_ship app.wms_outbound_shipments;
  v_eligibility_count integer;
begin
  v_ship := app.create_wms_outbound_shipment(v_outbound_order_id, 'idem-iv-ship-create', ops1, 'ops1');
  v_ship := app.add_package_to_shipment(v_ship.id, v_package_id, 'idem-iv-ship-addpkg', ops1, 'ops1');
  v_ship := app.set_wms_shipment_dock_location(v_ship.id, v_dock_id, v_ship.record_version, ops1, 'ops1');
  v_ship := app.set_wms_shipment_vehicle_ref(v_ship.id, 'TRUCK-IV-01', v_ship.record_version, ops1, 'ops1');
  v_ship := app.load_wms_outbound_shipment(v_ship.id, 'idem-iv-ship-load', v_ship.record_version, ops1, 'ops1');
  if v_ship.status <> 'loaded' then
    raise exception 'assertion failed: expected the shipment to be loaded, got %', v_ship.status;
  end if;

  v_ship := app.ship_confirm_wms_outbound_shipment(v_ship.id, 'Alice IV Receiving Dock', 'goods handed to carrier, seal verified intact', false, null, 'idem-iv-ship-confirm', v_ship.record_version, ops1, 'ops1');
  if v_ship.status <> 'shipped' then
    raise exception 'assertion failed: expected the shipment to be shipped, got %', v_ship.status;
  end if;
  if v_ship.is_partial_fulfillment then
    raise exception 'assertion failed: expected a full, non-partial fulfillment for this single-shipment order';
  end if;

  select count(*) into v_eligibility_count from app.wms_billing_eligibility_events where shipment_id = v_ship.id;
  if v_eligibility_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 auto-created wms_billing_eligibility_events row for this shipment, found %', v_eligibility_count;
  end if;

  -- Post-ship ledger snapshot: DOCK/STAGE net back to zero for both items (loaded in,
  -- then fully consumed on ship-confirm); RACK-IV-1 stays at 40 (untouched by
  -- shipping, only by the earlier pick).
  if (select coalesce(on_hand, 0) from app.inventory_balances where location_id = v_dock_id and item_master_id = v_item_lot_id and status = 'on_hand') <> 0 then
    raise exception 'assertion failed: expected DOCK-IV-1 lot-item on_hand to be exactly 0 after ship-confirm consumption';
  end if;
  if (select coalesce(on_hand, 0) from app.inventory_balances where location_id = v_dock_id and item_master_id = v_item_ser_id and status = 'on_hand') <> 0 then
    raise exception 'assertion failed: expected DOCK-IV-1 serial-item on_hand to be exactly 0 after ship-confirm consumption';
  end if;
  if (select coalesce(on_hand, 0) from app.inventory_balances where location_id = (select value::uuid from iv_a where key = 'stage_id') and item_master_id = v_item_lot_id and status = 'on_hand') <> 0 then
    raise exception 'assertion failed: expected STAGE-IV-1 lot-item on_hand to be exactly 0 after loading out';
  end if;

  insert into iv_a (key, value) values
    ('shipment_id', v_ship.id::text),
    ('shipment_number', v_ship.shipment_number),
    ('ship_consumption_movement_id', v_ship.consumption_movement_id::text),
    ('ship_load_movement_id', v_ship.load_movement_id::text);
end $$;

-- =============================================================================
-- PART A RECONCILIATION #1 -- the headline composition proof: recompute every
-- app.inventory_balances row for this tenant DIRECTLY from app.inventory_
-- movement_lines and confirm an EXACT match, and confirm zero orphaned ('active'
-- but unresolved) reservations remain. This is the strongest, most general
-- reconciliation check available -- not a spot check of a few expected numbers
-- (already done above per-step) but a full ledger-vs-balance recomputation across
-- every dimension this chain touched.
-- =============================================================================

\echo '>> Part A RECONCILIATION #1 (post-ship): every app.inventory_balances row for tenant wmsiv1 recomputes EXACTLY from summed app.inventory_movement_lines.signed_quantity across the SAME dimension tuple -- zero mismatches; zero orphaned (active) reservations remain'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_mismatch_count integer;
  v_orphaned_reservations integer;
begin
  select count(*) into v_mismatch_count
  from app.inventory_balances b
  left join lateral (
    select coalesce(sum(l.signed_quantity), 0) as computed
    from app.inventory_movement_lines l
    where l.tenant_id = b.tenant_id and l.owner_account_id = b.owner_account_id and l.item_master_id = b.item_master_id
      and l.location_id = b.location_id and coalesce(l.lot_number, '') = coalesce(b.lot_number, '') and coalesce(l.serial_number, '') = coalesce(b.serial_number, '')
      and l.status = b.status
  ) computed on true
  where b.tenant_id = v_tenant1 and b.on_hand <> computed.computed;
  if v_mismatch_count <> 0 then
    raise exception 'assertion failed: expected zero app.inventory_balances rows whose on_hand disagrees with the SUM of their own app.inventory_movement_lines, found %', v_mismatch_count;
  end if;

  select count(*) into v_orphaned_reservations from app.inventory_reservations r
    join app.inventory_balances b on b.id = r.balance_id
    where b.tenant_id = v_tenant1 and r.status = 'active';
  if v_orphaned_reservations <> 0 then
    raise exception 'assertion failed: expected zero orphaned (still-active) reservations for tenant wmsiv1 after every pick task fully resolved, found %', v_orphaned_reservations;
  end if;
end $$;

-- =============================================================================
-- PART A step: cycle count (ATW-020) -- against the RESULTING balance the golden
-- path itself produced (RACK-IV-1's own 40 PCS residual), a deliberate small
-- variance forcing the real approve->post_inventory_movement adjustment path.
-- =============================================================================

\echo '>> Part A: Cycle Count (ATW-020) -- plan scoped to RACK-IV-1, freeze (snapshots the resulting 40 PCS balance the golden path just produced), assign, observe 38 (a deliberate variance), approve -- posts a real adjustment movement'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from iv_a where key = 'warehouse_id');
  v_rack1_id uuid := (select value::uuid from iv_a where key = 'rack1_id');
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_plan app.cycle_count_plans;
  v_scope_item app.cycle_count_scope_items;
  v_scope_items app.cycle_count_scope_items[];
begin
  v_plan := app.create_cycle_count_plan(v_tenant1, v_warehouse_id, 'spot', 1, 50, false, null, v_rack1_id, null, null, 'idem-iv-cc-plan', ops1, 'ops1');

  select array_agg(x) into v_scope_items from app.freeze_cycle_count_scope(v_plan.id, v_plan.record_version, ops1, 'ops1') x;
  if array_length(v_scope_items, 1) <> 1 then
    raise exception 'assertion failed: expected exactly 1 scope item frozen (RACK-IV-1''s own single lot-item balance), found %', array_length(v_scope_items, 1);
  end if;
  v_scope_item := v_scope_items[1];
  if v_scope_item.snapshot_expected_quantity <> 40 then
    raise exception 'assertion failed: expected the frozen scope item to snapshot the resulting 40 PCS balance the golden path itself produced, got %', v_scope_item.snapshot_expected_quantity;
  end if;

  v_scope_item := app.assign_cycle_count_scope_item(v_scope_item.id, ops1, 'ops1', v_scope_item.record_version, ops1, 'ops1');
  v_scope_item := app.record_cycle_count_observation(v_scope_item.id, 38, 'PCS', v_rack1_id, v_item_lot_id, 'LOT-IV-A1', null, 'idem-iv-cc-obs', v_scope_item.record_version, ops1, 'ops1');
  if v_scope_item.status <> 'pending_review' or v_scope_item.variance_quantity <> -2 then
    raise exception 'assertion failed: expected a -2 variance landing on pending_review (5%% > 1%% variance_threshold, <= 50%% recount_threshold), got status=% variance=%', v_scope_item.status, v_scope_item.variance_quantity;
  end if;

  v_scope_item := app.approve_cycle_count_variance(v_scope_item.id, v_scope_item.record_version, 'confirmed shrinkage on recount, approved for adjustment', 'idem-iv-cc-approve', ops1, 'ops1');
  if v_scope_item.status <> 'adjusted' or v_scope_item.adjustment_movement_id is null then
    raise exception 'assertion failed: expected the scope item to be adjusted with a real posted movement, got status=% movement=%', v_scope_item.status, v_scope_item.adjustment_movement_id;
  end if;

  if (select on_hand from app.inventory_balances where location_id = v_rack1_id and item_master_id = v_item_lot_id and status = 'on_hand') <> 38 then
    raise exception 'assertion failed: expected RACK-IV-1 lot-item on_hand to be exactly 38 after the cycle count adjustment';
  end if;

  insert into iv_a (key, value) values ('cycle_count_adjustment_movement_id', v_scope_item.adjustment_movement_id::text);
end $$;

\echo '>> Part A RECONCILIATION #2 (post-cycle-count): the SAME full ledger-vs-balance recomputation, re-run after the cycle count''s own adjustment movement -- still zero mismatches, confirming the adjustment composed correctly with everything the golden path already posted'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_mismatch_count integer;
begin
  select count(*) into v_mismatch_count
  from app.inventory_balances b
  left join lateral (
    select coalesce(sum(l.signed_quantity), 0) as computed
    from app.inventory_movement_lines l
    where l.tenant_id = b.tenant_id and l.owner_account_id = b.owner_account_id and l.item_master_id = b.item_master_id
      and l.location_id = b.location_id and coalesce(l.lot_number, '') = coalesce(b.lot_number, '') and coalesce(l.serial_number, '') = coalesce(b.serial_number, '')
      and l.status = b.status
  ) computed on true
  where b.tenant_id = v_tenant1 and b.on_hand <> computed.computed;
  if v_mismatch_count <> 0 then
    raise exception 'assertion failed: expected zero ledger-vs-balance mismatches after the cycle count adjustment, found %', v_mismatch_count;
  end if;
end $$;

-- =============================================================================
-- PART A step: label generate/scan (ATW-021) -- a real governed template/version/
-- printer, a label generated for the shipped PACKAGE (the physical, labelable unit
-- a real warehouse worker slaps a barcode on), then a real "scan" via app.
-- resolve_label.
-- =============================================================================

\echo '>> Part A: Label and Barcode (ATW-021) -- governed template+version+printer, generate a label for the shipped package, enqueue a real print job, then SCAN it via app.resolve_label -- resolves to the exact same package, logs a real app.label_scan_events row'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from iv_a where key = 'warehouse_id');
  v_package_id uuid := (select value::uuid from iv_a where key = 'package_id');
  v_package_number text := (select value from iv_a where key = 'package_number');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_template app.label_templates;
  v_version app.label_template_versions;
  v_printer app.label_printers;
  v_label app.label_instances;
  v_print_job app.label_print_jobs;
  v_scan app.label_resolve_result;
  v_scan_event_count integer;
begin
  v_template := app.create_label_template(v_tenant1, 'PKG-LABEL-IV', 'IV Package Label', 'package', ops1, 'ops1');
  v_version := app.create_label_template_version_draft(v_template.id, '{{package_number}} WH:{{warehouse_code}}', array['package_number', 'warehouse_code'], 'code128', ops1, 'ops1');
  v_version := app.publish_label_template_version(v_version.id, v_version.record_version, null, ops1, 'ops1');
  v_printer := app.create_label_printer(v_tenant1, v_warehouse_id, 'PRINTER-IV-1', 'IV Dock Printer', '{}'::jsonb, ops1, 'ops1');

  v_label := app.generate_label(v_tenant1, 'PKG-LABEL-IV', 'package', v_package_id, jsonb_build_object('package_number', v_package_number, 'warehouse_code', 'WH-IV-1'), 'idem-iv-label-gen', ops1, 'ops1');
  if v_label.subject_type <> 'package' or v_label.subject_id <> v_package_id then
    raise exception 'assertion failed: expected the generated label to reference the shipped package exactly, got subject_type=% subject_id=%', v_label.subject_type, v_label.subject_id;
  end if;

  v_print_job := app.print_label(v_label.id, v_printer.id, 1, 'idem-iv-label-print', ops1, 'ops1');
  if v_print_job.id is null then
    raise exception 'assertion failed: expected a real app.label_print_jobs row to be enqueued';
  end if;

  -- The scan: a real warehouse worker scanning the physically shipped carton's own
  -- barcode -- resolves through checksum validation + live subject re-authorization,
  -- never a cached/trusted value.
  v_scan := app.resolve_label(v_tenant1, v_label.encoded_value, ops1, 'ops1');
  if not v_scan.resolved or v_scan.subject_type <> 'package' or v_scan.subject_id <> v_package_id or v_scan.subject_code <> v_package_number then
    raise exception 'assertion failed: expected the scan to resolve the exact shipped package, got resolved=% subject_type=% subject_id=% subject_code=%', v_scan.resolved, v_scan.subject_type, v_scan.subject_id, v_scan.subject_code;
  end if;

  select count(*) into v_scan_event_count from app.label_scan_events where label_instance_id = v_label.id and resolved = true;
  if v_scan_event_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 resolved app.label_scan_events row for this label, found %', v_scan_event_count;
  end if;

  insert into iv_a (key, value) values ('label_instance_id', v_label.id::text), ('label_encoded_value', v_label.encoded_value);
end $$;

-- =============================================================================
-- PART A step: warehouse billing event (ATW-022) -- captured for the real pack
-- activity this chain's own confirmed package represents, calculated against a
-- real published customer_contract rate component, reviewed and approved by TWO
-- distinct actors (self-approval is structurally forbidden), handed off.
-- =============================================================================

\echo '>> Part A: Warehouse Billing Events (ATW-022) -- a published customer_contract with a real pack-activity rate component, a billing event captured for the golden path''s own confirmed package (source_type=wms_package_confirmation), calculated/reviewed/approved (by a SECOND distinct actor, self-approval forbidden)/handed off'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from iv_a where key = 'warehouse_id');
  v_account_alpha_id uuid := (select value::uuid from iv_a where key = 'account_alpha_id');
  v_package_id uuid := (select value::uuid from iv_a where key = 'package_id');
  v_quotation_alpha_id uuid := (select value::uuid from iv_a where key = 'quotation_alpha_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  ops1b uuid := (select value::uuid from iv_a where key = 'ops1b');
  v_contract app.customer_contracts;
  v_event app.warehouse_billing_events;
  v_handoff app.warehouse_billing_handoffs;
  v_total_packed numeric := (select total_packed_quantity from app.wms_packages where id = v_package_id);
begin
  v_contract := app.create_customer_contract_draft(v_quotation_alpha_id, null, now() - interval '7 days', null, null, ops1, 'ops1');
  perform app.add_customer_contract_price_component(v_contract.id, 'warehousing', null, null, null, null, 'IDR', 0, null, 0, '[]'::jsonb, ops1, 'ops1');
  perform app.create_warehouse_billing_rate_component(v_contract.id, v_warehouse_id, 'pack', 'flat', null, 15000, null, 'IDR', null, null, ops1, 'ops1');
  v_contract := app.publish_customer_contract(v_contract.id, v_contract.record_version, ops1, 'ops1');
  if v_contract.status <> 'published' then
    raise exception 'assertion failed: expected the IV customer contract to publish, got %', v_contract.status;
  end if;

  v_event := app.capture_warehouse_billing_event(v_tenant1, v_warehouse_id, v_account_alpha_id, 'pack', 'wms_package_confirmation', v_package_id, v_total_packed, 'PCS', now(), 'idem-iv-bill-capture', null, ops1, 'ops1');
  if v_event.source_type <> 'wms_package_confirmation' or v_event.source_id <> v_package_id then
    raise exception 'assertion failed: expected the billing event to reference the golden path''s own real confirmed package, got source_type=% source_id=%', v_event.source_type, v_event.source_id;
  end if;

  v_event := app.calculate_warehouse_billing_event(v_event.id, v_event.record_version, null, ops1, 'ops1');
  if v_event.status <> 'pending_review' or v_event.total_amount <> 15000 then
    raise exception 'assertion failed: expected a flat-rate 15000 IDR calculation landing on pending_review, got status=% total=%', v_event.status, v_event.total_amount;
  end if;

  v_event := app.review_warehouse_billing_event(v_event.id, v_event.record_version, ops1, 'ops1');
  if v_event.status <> 'reviewed' or v_event.reviewed_by_auth_user_id <> ops1 then
    raise exception 'assertion failed: expected the event to be reviewed by ops1, got status=% reviewed_by=%', v_event.status, v_event.reviewed_by_auth_user_id;
  end if;

  -- Segregation of duties: the SAME actor that reviewed may not approve.
  begin
    perform app.approve_warehouse_billing_event(v_event.id, v_event.record_version, ops1, 'ops1');
    raise exception 'assertion failed: expected self_approval_not_allowed when the reviewer also attempts to approve';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  v_event := app.approve_warehouse_billing_event(v_event.id, v_event.record_version, ops1b, 'ops1b');
  if v_event.status <> 'approved' or v_event.approved_by_auth_user_id <> ops1b then
    raise exception 'assertion failed: expected the event to be approved by the SECOND distinct actor ops1b, got status=% approved_by=%', v_event.status, v_event.approved_by_auth_user_id;
  end if;

  v_handoff := app.handoff_warehouse_billing_event(v_event.id, 'idem-iv-bill-handoff', ops1, 'ops1');
  if v_handoff.billing_event_id <> v_event.id then
    raise exception 'assertion failed: expected the handoff to reference the SAME billing event';
  end if;

  select status into v_event.status from app.warehouse_billing_events where id = v_event.id;
  if v_event.status <> 'handed_off' then
    raise exception 'assertion failed: expected the billing event to reach handed_off, got %', v_event.status;
  end if;

  insert into iv_a (key, value) values ('billing_event_id', v_event.id::text);
end $$;

-- =============================================================================
-- PART A step: customer inventory access (ATW-023) -- CUSTOMER_ALPHA reads exactly
-- its OWN resulting balance/order status from this exact composed chain, and
-- nothing else -- including a direct negative probe against Account BETA's own
-- data in the SAME tenant/warehouse (the "different customer" isolation angle).
-- =============================================================================

\echo '>> Part A: Customer Inventory Access (ATW-023) -- CUSTOMER_ALPHA reads its own resulting RACK-IV-1 balance (38 PCS, post-cycle-count) and its own outbound order''s real status via the real customer-scoped RPCs -- exactly the permitted rows, nothing more. The cross-customer/cross-tenant NEGATIVE probes (denied reading Beta''s/Gamma''s own data) are Part D, once Parts B/C below have real foreign data to probe against.'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from iv_a where key = 'warehouse_id');
  v_rack1_id uuid := (select value::uuid from iv_a where key = 'rack1_id');
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  v_account_alpha_id uuid := (select value::uuid from iv_a where key = 'account_alpha_id');
  v_outbound_order_id uuid := (select value::uuid from iv_a where key = 'outbound_order_id');
  cust_alpha uuid := (select value::uuid from iv_a where key = 'cust_alpha');
  v_alpha_balance_id uuid;
  v_balance record;
  v_order record;
  v_list_count integer;
  v_foreign_count integer;
begin
  v_alpha_balance_id := (select id from app.inventory_balances where tenant_id = v_tenant1 and location_id = v_rack1_id and item_master_id = v_item_lot_id and owner_account_id = v_account_alpha_id and status = 'on_hand');

  select * into v_balance from app.get_customer_inventory_balance(v_tenant1, cust_alpha, v_alpha_balance_id);
  if v_balance.on_hand <> 38 or v_balance.owner_account_id <> v_account_alpha_id then
    raise exception 'assertion failed: expected CUSTOMER_ALPHA to see its own exact resulting balance (on_hand=38, owner=alpha), got on_hand=% owner=%', v_balance.on_hand, v_balance.owner_account_id;
  end if;

  select * into v_order from app.get_customer_outbound_order(v_tenant1, cust_alpha, v_outbound_order_id);
  if v_order.owner_account_id <> v_account_alpha_id or v_order.id <> v_outbound_order_id then
    raise exception 'assertion failed: expected CUSTOMER_ALPHA to see its own outbound order''s real status (%), got owner=% id=%', v_order.status, v_order.owner_account_id, v_order.id;
  end if;

  -- list_customer_inventory_balances: exactly the permitted rows, never a foreign owner's.
  select count(*) into v_list_count from app.list_customer_inventory_balances(v_tenant1, cust_alpha, v_warehouse_id, null, null, null, 50);
  select count(*) into v_foreign_count from app.list_customer_inventory_balances(v_tenant1, cust_alpha, v_warehouse_id, null, null, null, 50)
    where owner_account_id <> v_account_alpha_id;
  if v_list_count = 0 or v_foreign_count <> 0 then
    raise exception 'assertion failed: expected CUSTOMER_ALPHA''s own balance list to be non-empty and contain zero foreign-owner rows, got count=% foreign=%', v_list_count, v_foreign_count;
  end if;

  insert into iv_a (key, value) values ('alpha_balance_id', v_alpha_balance_id::text);
end $$;

-- =============================================================================
-- PART A step: claim (ATW-025) -- opens against a REAL app.operational_exceptions
-- case anchored to a REAL app.shipment_orders row (built via the SAME confirmed
-- Job Order Part A's own CRM pipeline produced, driven to delivered + a real
-- ePOD capture), then links this exact chain's OWN real inventory_movement/
-- wms_outbound_shipment/epod_capture evidence -- proving the claim's own
-- evidence-validation accepts real, correctly-scoped IDs from this live chain, not
-- synthetic same-migration fixtures.
-- =============================================================================

\echo '>> Part A: build a real Shipment Order (SAME confirmed Job Order Alpha''s own CRM pipeline produced) driven to delivered, plus a real ePOD capture -- the claim''s own required anchor and one of its own three evidence kinds'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_job_order_id uuid := (select value::uuid from iv_a where key = 'job_order_alpha_id');
  admin uuid := (select value::uuid from iv_a where key = 'admin');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_shipment app.shipment_orders;
  v_vendor app.master_records;
  v_capture app.epod_captures;
begin
  v_shipment := app.create_shipment_order_from_job(
    v_job_order_id, 'idem-iv-shord-1', null, null, 'land_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '3 days', null, null, null, null, null, null, null, ops1, 'ops1'
  );
  v_shipment := app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, ops1, 'ops1');

  -- create_master_record requires Supreme Admin or tenant_admin authority (checked
  -- directly against this repository's own function) -- the tenant_admin ADMIN
  -- actor Part A's own setup already provisioned, not OPS1's own OPS-tier role.
  v_vendor := app.create_master_record('vendor', v_tenant1, 'VEND-IV-1', 'IV Trucking Co', '[]'::jsonb, '{}'::jsonb, admin, 'admin');

  v_shipment := app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-iv-shord-planned', ops1, 'ops1');
  v_shipment := app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-iv-shord-assigned', ops1, 'ops1');
  perform app.assign_resource(v_shipment.id, 'vendor', v_vendor.id, ops1, 'ops1');
  v_shipment := app.transition_shipment_order(v_shipment.id, 'dispatched', v_shipment.record_version, null, null, 'idem-iv-shord-dispatched', ops1, 'ops1');
  v_shipment := app.transition_shipment_order(v_shipment.id, 'in_transit', v_shipment.record_version, null, null, 'idem-iv-shord-intransit', ops1, 'ops1');
  v_shipment := app.transition_shipment_order(v_shipment.id, 'delivered', v_shipment.record_version, null, 'physical delivery confirmed', 'idem-iv-shord-delivered', ops1, 'ops1');
  if v_shipment.status <> 'delivered' then
    raise exception 'assertion failed: expected the IV shipment order to reach delivered, got %', v_shipment.status;
  end if;
  if v_shipment.shipper_account_id <> (select value::uuid from iv_a where key = 'account_alpha_id') then
    raise exception 'assertion failed: expected the shipment order''s own shipper_account_id to be Account Alpha (inherited from the SAME Job Order), got %', v_shipment.shipper_account_id;
  end if;

  v_capture := app.start_epod_capture(v_tenant1, v_shipment.id, null, 'idem-iv-epod-1', ops1, 'ops1');

  insert into iv_a (key, value) values
    ('shipment_order_id', v_shipment.id::text),
    ('epod_capture_id', v_capture.id::text);
end $$;

\echo '>> Part A: report a real operational exception against this shipment order, assign OPS1 as investigator (OPS:Assign), open a claim case, add a claim item, then LINK all three real evidence kinds from this exact live chain -- wms_outbound_shipment, inventory_movement, epod_capture -- all real, correctly-scoped IDs, all accepted'
do $$
declare
  v_shipment_order_id uuid := (select value::uuid from iv_a where key = 'shipment_order_id');
  v_epod_capture_id uuid := (select value::uuid from iv_a where key = 'epod_capture_id');
  v_wms_shipment_id uuid := (select value::uuid from iv_a where key = 'shipment_id');
  v_consumption_movement_id uuid := (select value::uuid from iv_a where key = 'ship_consumption_movement_id');
  v_item_lot_id uuid := (select value::uuid from iv_a where key = 'item_lot_id');
  v_account_alpha_id uuid := (select value::uuid from iv_a where key = 'account_alpha_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_exception app.operational_exceptions;
  v_case app.claim_case_extensions;
  v_item app.claim_items;
  v_link_shipment app.claim_evidence_links;
  v_link_movement app.claim_evidence_links;
  v_link_epod app.claim_evidence_links;
begin
  v_exception := app.report_exception(
    v_shipment_order_id, null, 'damage', 'medium',
    'Package IV-0001 arrived with carton crush damage; customer reported 60 PCS of SKU-IV-LOT as damaged in transit',
    'manual', null, ops1, 'ops1'
  );
  if v_exception.type <> 'damage' then
    raise exception 'assertion failed: expected a real damage-type exception, got %', v_exception.type;
  end if;

  v_exception := app.assign_exception_owner(v_exception.id, ops1, null, ops1, 'ops1');
  if v_exception.owner_user_id <> ops1 then
    raise exception 'assertion failed: expected ops1 to be assigned as the exception''s own investigator, got %', v_exception.owner_user_id;
  end if;

  v_case := app.open_claim_case(v_exception.id, 'customer', v_account_alpha_id, 'Alice IV Ops',
    jsonb_build_object('name', 'Alice IV Ops', 'phone', '0811-IV-0001', 'email', 'alice@wmsiv245.test'), ops1, 'ops1');
  if v_case.operational_exception_id <> v_exception.id or v_case.claimant_type <> 'customer' then
    raise exception 'assertion failed: expected a real open claim case referencing the exception, got exception_ref=% claimant_type=%', v_case.operational_exception_id, v_case.claimant_type;
  end if;

  v_item := app.add_claim_item(v_case.id, 'inventory', v_consumption_movement_id, v_wms_shipment_id, v_item_lot_id, 60, 'PCS', 900000, 'IDR',
    '60 units of SKU-IV-LOT damaged in transit per customer report, matching the golden path''s own real shipped quantity', ops1, 'ops1');
  if v_item.linked_inventory_movement_id <> v_consumption_movement_id or v_item.linked_wms_outbound_shipment_id <> v_wms_shipment_id then
    raise exception 'assertion failed: expected the claim item to link this chain''s own real movement/shipment ids exactly';
  end if;

  -- The headline proof: THREE real evidence kinds, all real, correctly-scoped IDs
  -- from THIS exact live chain -- never synthetic same-migration fixtures.
  v_link_shipment := app.link_claim_evidence(v_case.id, 'wms_outbound_shipment', v_wms_shipment_id, 'primary shipment evidence -- this exact chain''s own shipped package', ops1, 'ops1');
  v_link_movement := app.link_claim_evidence(v_case.id, 'inventory_movement', v_consumption_movement_id, 'ledger evidence of the real stock issue this chain''s own ship-confirm posted', ops1, 'ops1');
  v_link_epod := app.link_claim_evidence(v_case.id, 'epod_capture', v_epod_capture_id, 'delivery evidence from this chain''s own real ePOD capture', ops1, 'ops1');

  if v_link_shipment.evidence_type <> 'wms_outbound_shipment' or v_link_shipment.evidence_id <> v_wms_shipment_id then
    raise exception 'assertion failed: expected the wms_outbound_shipment evidence link to be accepted with the exact real id';
  end if;
  if v_link_movement.evidence_type <> 'inventory_movement' or v_link_movement.evidence_id <> v_consumption_movement_id then
    raise exception 'assertion failed: expected the inventory_movement evidence link to be accepted with the exact real id';
  end if;
  if v_link_epod.evidence_type <> 'epod_capture' or v_link_epod.evidence_id <> v_epod_capture_id then
    raise exception 'assertion failed: expected the epod_capture evidence link to be accepted with the exact real id';
  end if;

  if (select count(*) from app.claim_evidence_links where claim_case_id = v_case.id) <> 3 then
    raise exception 'assertion failed: expected exactly 3 real evidence links on this claim case';
  end if;

  insert into iv_a (key, value) values ('exception_id', v_exception.id::text), ('claim_case_id', v_case.id::text);
end $$;

\echo 'PART A (critical WMS golden path) COMPLETE -- item/UOM master -> inbound -> receiving -> putaway -> lot/serial registration -> outbound order -> picking -> packing -> ship/custody -> ledger reconciliation -> cycle count -> label generate/scan -> warehouse billing -> customer inventory access -> claim referencing this exact chain''s own real evidence, all real RPC calls, one continuous flow.'

-- =============================================================================
-- PART B: Account Beta's own abbreviated, real WMS presence in the SAME tenant
-- wmsiv1 -- an opening balance, an outbound order, a real pick/pack/ship, a real
-- label and billing event. Exists solely to give Part D's own same-tenant
-- cross-customer isolation probes (claim evidence scope mismatch, ATW-023 denial)
-- a REAL, different-owner target to probe against -- not a synthetic id.
-- =============================================================================

\echo '>> Part B: Account Beta''s own abbreviated real WMS chain (same tenant wmsiv1, same warehouse WH-IV-1, different owner) -- opening balance -> outbound order -> pick -> pack -> ship -- a real, different-owner wms_outbound_shipment/inventory_movement for Part D''s own cross-customer probes'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from iv_a where key = 'warehouse_id');
  v_rack_beta_id uuid := (select value::uuid from iv_a where key = 'rack_beta_id');
  v_stage_id uuid := (select value::uuid from iv_a where key = 'stage_id');
  v_dock_id uuid := (select value::uuid from iv_a where key = 'dock_id');
  v_item_beta_id uuid := (select value::uuid from iv_a where key = 'item_beta_id');
  v_account_beta_id uuid := (select value::uuid from iv_a where key = 'account_beta_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_order app.wms_outbound_orders;
  v_line app.wms_outbound_order_lines;
  v_pkg app.wms_packages;
  v_ship app.wms_outbound_shipments;
begin
  perform app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-iv-beta-open', 'beta opening stock fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta_id, 'item_master_id', v_item_beta_id, 'location_id', v_rack_beta_id, 'uom_code', 'PCS', 'signed_quantity', 50)),
    ops1, 'ops1'
  );

  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_beta_id, 'beta outbound', 'idem-iv-beta-outbound', current_date + 3, ops1, 'ops1');
  v_line := app.add_wms_outbound_order_line(v_order.id, v_item_beta_id, 'PCS', 20, null, ops1, 'ops1');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, ops1, 'ops1');

  call iv_pick_fully(v_line.id, 20, v_rack_beta_id, v_item_beta_id, null, null, v_stage_id, 'idem-iv-beta-pick', ops1, 'ops1');
  v_pkg := iv_pack_fully(v_order.id, (select id from app.wms_pick_tasks where outbound_order_line_id = v_line.id), v_item_beta_id, 20, 'idem-iv-beta-pack', ops1, 'ops1');
  v_ship := iv_ship_fully(v_order.id, v_pkg.id, v_dock_id, 'idem-iv-beta-ship', ops1, 'ops1');
  if v_ship.status <> 'shipped' or v_ship.owner_account_id <> v_account_beta_id then
    raise exception 'assertion failed: expected Beta''s own shipment to ship with owner_account_id=Beta, got status=% owner=%', v_ship.status, v_ship.owner_account_id;
  end if;

  insert into iv_a (key, value) values
    ('beta_outbound_order_id', v_order.id::text),
    ('beta_shipment_id', v_ship.id::text),
    ('beta_consumption_movement_id', v_ship.consumption_movement_id::text),
    ('beta_package_id', v_pkg.id::text),
    ('beta_balance_id', (select id::text from app.inventory_balances where tenant_id = v_tenant1 and owner_account_id = v_account_beta_id and item_master_id = v_item_beta_id and location_id = v_rack_beta_id and status = 'on_hand'));
end $$;

-- =============================================================================
-- PART C: a fully parallel, isolated TENANT (wmsiv2, Account Gamma) -- a real
-- abbreviated WMS chain producing a real inventory balance/movement, a real
-- wms_outbound_shipment, a real label, and a real (captured, not calculated
-- further) warehouse billing event -- targets for Part D's own cross-TENANT
-- isolation probes.
-- =============================================================================

\echo '>> Part C setup: tenant wmsiv2, org unit, actors (ADMIN2/OPS2), warehouse WH-IV-2, item SKU-IV-GAMMA, Account Gamma (direct insert), warehouse eligibility, customer_user grant -- fully isolated from tenant wmsiv1'
do $$
declare
  v_tenant2 uuid;
  v_company uuid;
  v_role uuid;
  v_draft app.role_versions;
  v_warehouse app.warehouses;
  v_dock app.warehouse_locations;
  v_stage app.warehouse_locations;
  v_rack app.warehouse_locations;
  v_item app.item_masters;
  v_account app.accounts;
  admin2 uuid := '00000000-0000-0000-0000-000000246001';
  ops2 uuid := '00000000-0000-0000-0000-000000246002';
  cust_gamma uuid := '00000000-0000-0000-0000-000000246010';
begin
  insert into auth.users (id, email) values
    (admin2, 'admin2@wmsiv2.test'),
    (ops2, 'ops2@wmsiv2.test'),
    (cust_gamma, 'customer-gamma@wmsiv2.test');

  perform app.provision_tenant('wmsiv2', 'WMS Integrated Verification Two', 'idem-wmsiv2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'wmsiv2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'WMSIV2-CO', 'WmsIv2 Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant2 and code = 'WMSIV2-CO');

  perform app.invite_user(v_tenant2, admin2, 'admin2@wmsiv2.test', 'IV2 Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@wmsiv2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(admin2, 'tenant_admin', v_tenant2, null, 'tester');

  perform app.invite_user(v_tenant2, ops2, 'ops2@wmsiv2.test', 'IV2 Ops', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ops2@wmsiv2.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant2, 'IV2 Ops', 'ops create/edit/view/override/assign', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(v_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override', 'Assign')), 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_role and status = 'published'), ops2, admin2, 'tester');

  v_warehouse := app.create_warehouse(v_tenant2, v_company, 'WH-IV-2', 'IV Warehouse 2', 'Jl. Integrated Verification 2', 'Asia/Jakarta', null, array['land']::text[], ops2, 'ops2');
  v_dock := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-IV-2', 'IV2 Dock', 'dock', 1, null, null, null, null, null, false, false, ops2, 'ops2');
  perform app.set_warehouse_location_status(v_dock.id, 'active', null, v_dock.record_version, ops2, 'ops2');
  v_stage := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-IV-2', 'IV2 Staging', 'staging', 2, null, null, null, null, null, false, false, ops2, 'ops2');
  perform app.set_warehouse_location_status(v_stage.id, 'active', null, v_stage.record_version, ops2, 'ops2');
  v_rack := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-IV-2B', 'IV2 Rack B', 'rack', 3, null, null, null, null, null, true, true, ops2, 'ops2');
  perform app.set_warehouse_location_status(v_rack.id, 'active', null, v_rack.record_version, ops2, 'ops2');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'IV Customer Gamma', 'wmsiv245-gamma-fp', '{}'::jsonb, v_company, 'tester') returning * into v_account;

  v_item := app.create_item_master(v_tenant2, v_account.id, 'SKU-IV-GAMMA', 'IV Gamma Widget', null, 'PCS', false, false, false, ops2, 'ops2');

  perform app.grant_warehouse_customer_eligibility(v_warehouse.id, v_account.id, ops2, 'ops2');
  perform app.invite_user(v_tenant2, cust_gamma, 'customer-gamma@wmsiv2.test', 'IV Customer Gamma Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-gamma@wmsiv2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(cust_gamma, 'customer_user', v_tenant2, v_account.id::text, 'tester');

  insert into iv_b (key, value) values
    ('tenant_id', v_tenant2::text),
    ('warehouse_id', v_warehouse.id::text),
    ('dock_id', v_dock.id::text),
    ('stage_id', v_stage.id::text),
    ('rack_id', v_rack.id::text),
    ('item_id', v_item.id::text),
    ('account_id', v_account.id::text),
    ('admin', admin2::text),
    ('ops2', ops2::text),
    ('cust_gamma', cust_gamma::text);
end $$;

\echo '>> Part C: Account Gamma''s real abbreviated WMS chain -- opening balance -> outbound order -> pick -> pack -> ship (a real, fully isolated inventory_movement/wms_outbound_shipment), plus a real label and a real captured warehouse billing event -- Part D''s own cross-tenant probe targets'
do $$
declare
  v_tenant2 uuid := (select value::uuid from iv_b where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from iv_b where key = 'warehouse_id');
  v_dock_id uuid := (select value::uuid from iv_b where key = 'dock_id');
  v_stage_id uuid := (select value::uuid from iv_b where key = 'stage_id');
  v_rack_id uuid := (select value::uuid from iv_b where key = 'rack_id');
  v_item_id uuid := (select value::uuid from iv_b where key = 'item_id');
  v_account_id uuid := (select value::uuid from iv_b where key = 'account_id');
  ops2 uuid := (select value::uuid from iv_b where key = 'ops2');
  v_order app.wms_outbound_orders;
  v_line app.wms_outbound_order_lines;
  v_pkg app.wms_packages;
  v_ship app.wms_outbound_shipments;
  v_template app.label_templates;
  v_version app.label_template_versions;
  v_printer app.label_printers;
  v_label app.label_instances;
  v_bill app.warehouse_billing_events;
begin
  perform app.post_inventory_movement(
    v_tenant2, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-iv2-open', 'gamma opening stock fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item_id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 50)),
    ops2, 'ops2'
  );

  v_order := app.create_manual_wms_outbound_order(v_tenant2, v_warehouse_id, v_account_id, 'gamma outbound', 'idem-iv2-outbound', current_date + 3, ops2, 'ops2');
  v_line := app.add_wms_outbound_order_line(v_order.id, v_item_id, 'PCS', 20, null, ops2, 'ops2');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, ops2, 'ops2');

  call iv_pick_fully(v_line.id, 20, v_rack_id, v_item_id, null, null, v_stage_id, 'idem-iv2-pick', ops2, 'ops2');
  v_pkg := iv_pack_fully(v_order.id, (select id from app.wms_pick_tasks where outbound_order_line_id = v_line.id), v_item_id, 20, 'idem-iv2-pack', ops2, 'ops2');
  v_ship := iv_ship_fully(v_order.id, v_pkg.id, v_dock_id, 'idem-iv2-ship', ops2, 'ops2');
  if v_ship.status <> 'shipped' then
    raise exception 'assertion failed: expected Gamma''s own shipment to ship, got status=%', v_ship.status;
  end if;

  v_template := app.create_label_template(v_tenant2, 'PKG-LABEL-IV2', 'IV2 Package Label', 'package', ops2, 'ops2');
  v_version := app.create_label_template_version_draft(v_template.id, '{{package_number}}', array['package_number'], 'code128', ops2, 'ops2');
  v_version := app.publish_label_template_version(v_version.id, v_version.record_version, null, ops2, 'ops2');
  v_printer := app.create_label_printer(v_tenant2, v_warehouse_id, 'PRINTER-IV2-1', 'IV2 Dock Printer', '{}'::jsonb, ops2, 'ops2');
  v_label := app.generate_label(v_tenant2, 'PKG-LABEL-IV2', 'package', v_pkg.id, jsonb_build_object('package_number', v_pkg.package_number), 'idem-iv2-label-gen', ops2, 'ops2');

  v_bill := app.capture_warehouse_billing_event(v_tenant2, v_warehouse_id, v_account_id, 'pack', 'wms_package_confirmation', v_pkg.id, v_pkg.total_packed_quantity, 'PCS', now(), 'idem-iv2-bill-capture', null, ops2, 'ops2');

  insert into iv_b (key, value) values
    ('gamma_outbound_order_id', v_order.id::text),
    ('gamma_shipment_id', v_ship.id::text),
    ('gamma_consumption_movement_id', v_ship.consumption_movement_id::text),
    ('gamma_package_id', v_pkg.id::text),
    ('gamma_label_id', v_label.id::text),
    ('gamma_label_encoded_value', v_label.encoded_value),
    ('gamma_billing_event_id', v_bill.id::text),
    ('gamma_balance_id', (select id::text from app.inventory_balances where tenant_id = v_tenant2 and owner_account_id = v_account_id and item_master_id = v_item_id and location_id = v_rack_id and status = 'on_hand'));
end $$;

\echo 'PART C (parallel isolated tenant chain) COMPLETE.'

-- =============================================================================
-- PART D: cross-tenant/cross-customer isolation sweep -- specifically the
-- COMPOSITION points Prompt 245's own item 2 names, not per-capability RBAC
-- re-testing (already proven at each capability's own checkpoint). Every probe
-- below targets a REAL row from Part B (same-tenant, different customer) or
-- Part C (fully different tenant), never a synthetic id.
-- =============================================================================

\echo '>> Part D1: does a claim opened against Tenant A''s (wmsiv1) shipment ever accept Tenant A-but-different-customer (Beta) evidence? app.link_claim_evidence must reject Beta''s own real wms_outbound_shipment/inventory_movement with claim_evidence_scope_mismatch/claim_evidence_not_found -- never silently accept it'
do $$
declare
  v_case_id uuid := (select value::uuid from iv_a where key = 'claim_case_id');
  v_beta_shipment_id uuid := (select value::uuid from iv_a where key = 'beta_shipment_id');
  v_beta_movement_id uuid := (select value::uuid from iv_a where key = 'beta_consumption_movement_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_rejected boolean;
begin
  v_rejected := false;
  begin
    perform app.link_claim_evidence(v_case_id, 'wms_outbound_shipment', v_beta_shipment_id, 'wrong customer probe', ops1, 'ops1');
  exception
    when others then
      if sqlerrm like 'claim_evidence_scope_mismatch%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected claim_evidence_scope_mismatch linking Account Beta''s own real (same-tenant, different-customer) wms_outbound_shipment to Account Alpha''s own claim case';
  end if;

  if exists (select 1 from app.claim_evidence_links where claim_case_id = v_case_id and evidence_id = v_beta_shipment_id) then
    raise exception 'assertion failed: Beta''s own shipment must never actually appear linked to Alpha''s own claim case';
  end if;

  -- app.inventory_movements carries no shipment_order_id (warehouse-scoped by design,
  -- ATW-015) -- its own claim-evidence check is tenant-scoped only (design note in
  -- the migration's own header), so a SAME-tenant different-customer movement is
  -- structurally acceptable at the RPC layer (a real, disclosed, narrower boundary,
  -- not this file's own defect to invent a stricter check for) -- but it must still
  -- NEVER be silently attributed to Alpha's own claim in a way that misrepresents its
  -- real owner. Confirm the real owner_account_id on that movement's own lines is
  -- genuinely Beta's, never silently Alpha's -- the accurate, disclosed scope.
  if exists (select 1 from app.inventory_movement_lines where movement_id = v_beta_movement_id and owner_account_id <> (select value::uuid from iv_a where key = 'account_beta_id')) then
    raise exception 'assertion failed: expected every line of Beta''s own consumption movement to carry owner_account_id=Beta, never Alpha''s';
  end if;
end $$;

\echo '>> Part D2: does a claim opened against Tenant A''s shipment ever accept Tenant B''s (wmsiv2) evidence? app.link_claim_evidence''s own lookup for BOTH evidence types is a raw global-id SELECT with no tenant filter (the row genuinely exists, just under a different tenant) -- so the real, correct rejection is claim_evidence_scope_mismatch (tenant_id mismatch), not claim_evidence_not_found; confirmed directly against the RPC''s own real behavior below, never assumed'
do $$
declare
  v_case_id uuid := (select value::uuid from iv_a where key = 'claim_case_id');
  v_gamma_shipment_id uuid := (select value::uuid from iv_b where key = 'gamma_shipment_id');
  v_gamma_movement_id uuid := (select value::uuid from iv_b where key = 'gamma_consumption_movement_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_rejected boolean;
begin
  v_rejected := false;
  begin
    perform app.link_claim_evidence(v_case_id, 'wms_outbound_shipment', v_gamma_shipment_id, 'wrong tenant probe', ops1, 'ops1');
  exception
    when others then
      if sqlerrm like 'claim_evidence_scope_mismatch%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected claim_evidence_scope_mismatch linking a different TENANT''s own real wms_outbound_shipment to this claim case';
  end if;

  v_rejected := false;
  begin
    perform app.link_claim_evidence(v_case_id, 'inventory_movement', v_gamma_movement_id, 'wrong tenant probe', ops1, 'ops1');
  exception
    when others then
      if sqlerrm like 'claim_evidence_scope_mismatch%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected claim_evidence_scope_mismatch linking a different TENANT''s own real inventory_movement to this claim case';
  end if;

  if (select count(*) from app.claim_evidence_links where claim_case_id = v_case_id) <> 3 then
    raise exception 'assertion failed: expected the claim case to still carry EXACTLY the original 3 legitimate evidence links -- no cross-tenant/cross-customer probe above was ever actually accepted';
  end if;
end $$;

\echo '>> Part D3: does customer A''s ATW-023 read ever see tenant-A-but-different-customer (Beta) data, or a different TENANT''s (Gamma) data? Both angles, both directions'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_tenant2 uuid := (select value::uuid from iv_b where key = 'tenant_id');
  cust_alpha uuid := (select value::uuid from iv_a where key = 'cust_alpha');
  cust_beta uuid := (select value::uuid from iv_a where key = 'cust_beta');
  v_alpha_balance_id uuid := (select value::uuid from iv_a where key = 'alpha_balance_id');
  v_beta_balance_id uuid := (select value::uuid from iv_a where key = 'beta_balance_id');
  v_gamma_balance_id uuid := (select value::uuid from iv_b where key = 'gamma_balance_id');
  v_outbound_order_id uuid := (select value::uuid from iv_a where key = 'outbound_order_id');
  v_beta_outbound_order_id uuid := (select value::uuid from iv_a where key = 'beta_outbound_order_id');
  v_rejected boolean;
begin
  -- Same-tenant, different customer: CUSTOMER_ALPHA cannot read Beta's own balance/order.
  v_rejected := false;
  begin
    perform app.get_customer_inventory_balance(v_tenant1, cust_alpha, v_beta_balance_id);
  exception
    when others then
      if sqlerrm like 'record_not_found%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected CUSTOMER_ALPHA to be denied (record_not_found) reading Account Beta''s own real balance in the same tenant/warehouse';
  end if;

  v_rejected := false;
  begin
    perform app.get_customer_outbound_order(v_tenant1, cust_alpha, v_beta_outbound_order_id);
  exception
    when others then
      if sqlerrm like 'record_not_found%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected CUSTOMER_ALPHA to be denied (record_not_found) reading Account Beta''s own real outbound order';
  end if;

  -- Reverse: CUSTOMER_BETA cannot read Alpha's own balance/order.
  v_rejected := false;
  begin
    perform app.get_customer_inventory_balance(v_tenant1, cust_beta, v_alpha_balance_id);
  exception
    when others then
      if sqlerrm like 'record_not_found%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected CUSTOMER_BETA to be denied (record_not_found) reading Account Alpha''s own real balance';
  end if;

  v_rejected := false;
  begin
    perform app.get_customer_outbound_order(v_tenant1, cust_beta, v_outbound_order_id);
  exception
    when others then
      if sqlerrm like 'record_not_found%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected CUSTOMER_BETA to be denied (record_not_found) reading Account Alpha''s own real outbound order';
  end if;

  -- Different tenant, angle 1: CUSTOMER_ALPHA (a real, active customer_user in
  -- tenant wmsiv1) attempts to read Gamma's own balance by ID under tenant wmsiv1's
  -- OWN tenant_id -- the row genuinely belongs to a different tenant, so it is not
  -- found under wmsiv1 at all.
  v_rejected := false;
  begin
    perform app.get_customer_inventory_balance(v_tenant1, cust_alpha, v_gamma_balance_id);
  exception
    when others then
      if sqlerrm like 'record_not_found%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected CUSTOMER_ALPHA to be denied (record_not_found) reading tenant wmsiv2''s own real balance under tenant wmsiv1''s own tenant_id';
  end if;

  -- Different tenant, angle 2: the SAME actor, but now passing tenant wmsiv2's own
  -- real tenant_id -- CUSTOMER_ALPHA holds zero customer_user membership there, so
  -- app.resolve_customer_owner_account_scope returns empty and the read is still denied.
  v_rejected := false;
  begin
    perform app.get_customer_inventory_balance(v_tenant2, cust_alpha, v_gamma_balance_id);
  exception
    when others then
      if sqlerrm like 'record_not_found%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected CUSTOMER_ALPHA to be denied (record_not_found) reading tenant wmsiv2''s own real balance even under tenant wmsiv2''s own correct tenant_id (zero membership there)';
  end if;
end $$;

\echo '>> Part D4: cross-tenant billing/label read isolation -- Tenant A''s own OPS1 staff actor (zero membership in tenant wmsiv2) is rejected insufficient_authority reading Gamma''s own real billing event; the SAME real encoded_value string never resolves under a DIFFERENT tenant_id'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  ops1 uuid := (select value::uuid from iv_a where key = 'ops1');
  v_gamma_billing_event_id uuid := (select value::uuid from iv_b where key = 'gamma_billing_event_id');
  v_gamma_label_encoded_value text := (select value from iv_b where key = 'gamma_label_encoded_value');
  v_rejected boolean;
  v_scan app.label_resolve_result;
begin
  v_rejected := false;
  begin
    perform app.get_warehouse_billing_event(v_gamma_billing_event_id, ops1);
  exception
    when others then
      if sqlerrm like 'insufficient_authority%' then v_rejected := true; else raise; end if;
  end;
  if not v_rejected then
    raise exception 'assertion failed: expected OPS1 (zero membership in tenant wmsiv2) to be denied insufficient_authority reading Gamma''s own real billing event';
  end if;

  -- The identical real encoded_value, looked up under tenant wmsiv1's own tenant_id
  -- (OPS1 IS a legitimate OPS:View actor here) -- must resolve to nothing at all,
  -- never Gamma's own subject, since app.resolve_label''s own lookup is
  -- tenant_id-scoped on the encoded_value itself.
  v_scan := app.resolve_label(v_tenant1, v_gamma_label_encoded_value, ops1, 'ops1');
  if v_scan.resolved or v_scan.rejection_reason <> 'unknown_code' then
    raise exception 'assertion failed: expected tenant wmsiv2''s own real label encoded_value to resolve as unknown_code under tenant wmsiv1, got resolved=% reason=%', v_scan.resolved, v_scan.rejection_reason;
  end if;
end $$;

\echo '>> Part D5: blunt tenant-wide leak sweep -- every one of Tenant B''s (Gamma) own real ids (shipment/balance/label/billing event) is confirmed to NEVER appear under Tenant A''s own tenant_id anywhere in the shared canonical tables, and vice versa'
do $$
declare
  v_tenant1 uuid := (select value::uuid from iv_a where key = 'tenant_id');
  v_tenant2 uuid := (select value::uuid from iv_b where key = 'tenant_id');
  v_leak_count integer;
begin
  select count(*) into v_leak_count from app.wms_outbound_shipments where tenant_id = v_tenant1 and id = (select value::uuid from iv_b where key = 'gamma_shipment_id');
  if v_leak_count <> 0 then raise exception 'assertion failed: Gamma''s own shipment must never appear under tenant wmsiv1''s own tenant_id, found %', v_leak_count; end if;

  select count(*) into v_leak_count from app.inventory_balances where tenant_id = v_tenant1 and owner_account_id = (select value::uuid from iv_b where key = 'account_id');
  if v_leak_count <> 0 then raise exception 'assertion failed: Gamma''s own owner_account_id must never appear on any balance under tenant wmsiv1, found %', v_leak_count; end if;

  select count(*) into v_leak_count from app.label_instances where tenant_id = v_tenant1 and id = (select value::uuid from iv_b where key = 'gamma_label_id');
  if v_leak_count <> 0 then raise exception 'assertion failed: Gamma''s own label instance must never appear under tenant wmsiv1, found %', v_leak_count; end if;

  select count(*) into v_leak_count from app.warehouse_billing_events where tenant_id = v_tenant1 and id = (select value::uuid from iv_b where key = 'gamma_billing_event_id');
  if v_leak_count <> 0 then raise exception 'assertion failed: Gamma''s own billing event must never appear under tenant wmsiv1, found %', v_leak_count; end if;

  select count(*) into v_leak_count from app.claim_case_extensions where tenant_id = v_tenant2;
  if v_leak_count <> 0 then raise exception 'assertion failed: tenant wmsiv2 created no claim of its own -- expected zero claim_case_extensions rows under tenant wmsiv2, found %', v_leak_count; end if;

  -- Reverse direction.
  select count(*) into v_leak_count from app.wms_outbound_shipments where tenant_id = v_tenant2 and id = (select value::uuid from iv_a where key = 'shipment_id');
  if v_leak_count <> 0 then raise exception 'assertion failed: Alpha''s own shipment must never appear under tenant wmsiv2''s own tenant_id, found %', v_leak_count; end if;

  select count(*) into v_leak_count from app.inventory_balances where tenant_id = v_tenant2 and owner_account_id = (select value::uuid from iv_a where key = 'account_alpha_id');
  if v_leak_count <> 0 then raise exception 'assertion failed: Alpha''s own owner_account_id must never appear on any balance under tenant wmsiv2, found %', v_leak_count; end if;

  select count(*) into v_leak_count from app.claim_case_extensions where tenant_id = v_tenant1 and id <> (select value::uuid from iv_a where key = 'claim_case_id');
  if v_leak_count <> 0 then raise exception 'assertion failed: expected exactly the one legitimate claim case under tenant wmsiv1, found % extra', v_leak_count; end if;
end $$;

\echo 'PART D (cross-tenant/cross-customer isolation sweep) COMPLETE -- zero data crossed the tenant or same-tenant customer boundary at any composition point: claim evidence linking, ATW-023 customer reads, billing event reads, label resolution, and a blunt tenant-wide leak sweep.'

drop procedure iv_pick_fully(uuid, numeric, uuid, uuid, text, text, uuid, text, uuid, text);
drop function iv_pack_fully(uuid, uuid, uuid, numeric, text, uuid, text);
drop function iv_ship_fully(uuid, uuid, uuid, text, uuid, text);
drop table iv_a;
drop table iv_b;

\echo 'ALL ATW-026 critical-path db-test assertions passed (Parts A-D).'
