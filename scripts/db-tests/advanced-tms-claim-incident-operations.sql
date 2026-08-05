-- Real, executable test evidence for ATW-025 (CG-S10-ATW-025, Prompt 244 "Advanced
-- Claim and Incident Operations") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Follows scripts/db-tests/advanced-tms-warehouse-
-- billing-events.sql's own structural convention (read first, per this checkpoint's
-- own brief).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (claiminc1) with a tenant_admin, a full-authority supervisor (OPS Create/Edit/View/Override/Close/Assign + OPS:View cost + full COM -- owns Shipment A), an investigator (OPS Create/Edit/View only, no View cost/Override/Close -- owns Shipment B, doubling as the masking-test actor), a plain OPS Create/Edit/View rep (no Override/Close/Assign, never an owner -- proves RBAC-tier rejections that fail before any record-scope check), an OPS:View-only viewer (no Create either -- proves the earliest RBAC gate), a global Supreme Admin (the universal "different actor" for separation-of-duty/masking-comparison/cross-shipment-owner administrative actions -- ratified absolute authority per AGENTS.md), one warehouse (WH-CLAIM-1) with a rack, staging and dock location; a second isolated tenant (claiminc2) for cross-tenant checks. NOTE (disclosed design constraint): app.shipment_orders.org_unit_id is never populated by app.create_shipment_order_from_job (verified directly against its own INSERT statement) -- app.can_access_record can therefore only be satisfied by a shipment''s own literal owner_user_id or Supreme Admin, never org-unit sharing. Every actor below that must pass real record-scope on a specific shipment is therefore either that shipment''s own creator or Supreme Admin -- never a fabricated bypass.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_company2 uuid;
  v_supervisor_role uuid;
  v_supervisor_draft app.role_versions;
  v_investigator_role uuid;
  v_investigator_draft app.role_versions;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_rep2_role uuid;
  v_rep2_draft app.role_versions;
  v_warehouse app.warehouses;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000990001', 'admin@claiminc1.test'),
    ('00000000-0000-0000-0000-000000990002', 'supervisor@claiminc1.test'),
    ('00000000-0000-0000-0000-000000990004', 'investigator@claiminc1.test'),
    ('00000000-0000-0000-0000-000000990005', 'rep@claiminc1.test'),
    ('00000000-0000-0000-0000-000000990006', 'viewer@claiminc1.test'),
    ('00000000-0000-0000-0000-000000990007', 'supreme@claiminc1.test'),
    ('00000000-0000-0000-0000-000000990008', 'financeworker@claiminc1.test'),
    ('00000000-0000-0000-0000-000000991001', 'admin2@claiminc2.test'),
    ('00000000-0000-0000-0000-000000991002', 'rep2@claiminc2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000990007', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('claiminc1', 'Claim Incident Tenant One', 'idem-claiminc1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'claiminc1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CLAIMINC1-CO', 'Claim Incident Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CLAIMINC1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000990001', 'admin@claiminc1.test', 'Claim Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@claiminc1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000990001', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000990002', 'supervisor@claiminc1.test', 'Claim Supervisor', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supervisor@claiminc1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000990004', 'investigator@claiminc1.test', 'Claim Investigator', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'investigator@claiminc1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000990005', 'rep@claiminc1.test', 'Claim Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@claiminc1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000990006', 'viewer@claiminc1.test', 'Claim Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@claiminc1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000990008', 'financeworker@claiminc1.test', 'Finance Worker', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeworker@claiminc1.test'), 'active', 'onboarded', 'tester');

  -- Full-authority role: every tier this capability spans -- OPS Create/Edit/View/
  -- Override/Close/Assign/View cost, plus enough COM/FIN to run the CRM->Job Order
  -- pipeline used to build real Shipment Orders.
  v_supervisor_role := (app.create_role(v_tenant1, 'Claim Supervisor Role', 'full commercial + ops create/edit/view/override/close/assign/view cost', 'tester')).id;
  v_supervisor_draft := app.create_role_version(v_supervisor_role, 'tester');
  perform app.set_role_version_permissions(
    v_supervisor_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost', 'View selling price'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override', 'Close', 'Assign', 'View cost'))),
    'tester'
  );
  perform app.publish_role_version(v_supervisor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_supervisor_role and status = 'published'), '00000000-0000-0000-0000-000000990002', '00000000-0000-0000-0000-000000990001', 'tester');

  -- Investigator: OPS Create/Edit/View only (no Override/Close/View cost --
  -- CANNOT decide/close a claim, CANNOT see cost/reserve fields) -- the tier that
  -- matters for every claim/incident RPC this migration adds. Also granted COM
  -- Create/Edit/Approve/View (matching supervisor's own grant) SOLELY so it can
  -- run its own independent CRM->Job Order pipeline below to become a genuine
  -- Job-Order/Shipment owner in its own right (app.create_shipment_order_from_job
  -- record-scope-checks the Job Order too, verified directly) -- COM permissions
  -- are irrelevant to every claim/incident RPC itself, so this does not weaken
  -- any OPS-tier test.
  v_investigator_role := (app.create_role(v_tenant1, 'Claim Investigator Role', 'ops create/edit/view only, plus com for its own CRM pipeline', 'tester')).id;
  v_investigator_draft := app.create_role_version(v_investigator_role, 'tester');
  perform app.set_role_version_permissions(
    v_investigator_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost', 'View selling price'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_investigator_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_investigator_role and status = 'published'), '00000000-0000-0000-0000-000000990004', '00000000-0000-0000-0000-000000990001', 'tester');

  -- Plain rep: identical OPS grants to investigator (Create/Edit/View only) --
  -- used purely to prove Override/Close-tier rejections, never assigned as an
  -- exception owner.
  v_rep_role := (app.create_role(v_tenant1, 'Claim Rep Role', 'ops create/edit/view only', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(v_rep_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000990005', '00000000-0000-0000-0000-000000990001', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Claim Viewer Role', 'OPS:View only, no OPS:View cost', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000990006', '00000000-0000-0000-0000-000000990001', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-CLAIM-1', 'Claim Incident Warehouse 1', 'Jl. Claim Incident 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000990002', 'supervisor');
  declare
    v_rack app.warehouse_locations;
    v_stage app.warehouse_locations;
    v_dock app.warehouse_locations;
  begin
    v_rack := app.create_warehouse_location(v_warehouse.id, null, null, 'RACK-CLAIM-A', 'Claim Rack A', 'rack', 1, null, null, null, null, null, true, true, '00000000-0000-0000-0000-000000990002', 'supervisor');
    perform app.set_warehouse_location_status(v_rack.id, 'active', null, v_rack.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
    v_stage := app.create_warehouse_location(v_warehouse.id, null, null, 'STAGE-CLAIM-1', 'Claim Staging 1', 'staging', 2, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000990002', 'supervisor');
    perform app.set_warehouse_location_status(v_stage.id, 'active', null, v_stage.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
    v_dock := app.create_warehouse_location(v_warehouse.id, null, null, 'DOCK-CLAIM-1', 'Claim Dock 1', 'dock', 3, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000990002', 'supervisor');
    perform app.set_warehouse_location_status(v_dock.id, 'active', null, v_dock.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
  end;

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('claiminc2', 'Claim Incident Tenant Two', 'idem-claiminc2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'claiminc2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CLAIMINC2-CO', 'Claim Incident Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CLAIMINC2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000991001', 'admin2@claiminc2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@claiminc2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000991001', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000991002', 'rep2@claiminc2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@claiminc2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view/override/close/assign', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override', 'Close', 'Assign')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000991002', '00000000-0000-0000-0000-000000991001', 'tester');
end $$;

-- Test-fixture-only helpers (never part of the real migration) -- copied verbatim
-- from scripts/db-tests/advanced-tms-warehouse-billing-events.sql (ATW-022) and
-- dropped at the end of this file, exactly as that file drops its own.
create procedure pick_fully(p_line_id uuid, p_item_master_id uuid, p_qty numeric, p_rack_id uuid, p_stage_id uuid, p_idem_prefix text)
language plpgsql
as $proc$
declare
  v_t app.wms_pick_tasks;
begin
  v_t := app.generate_wms_pick_task(p_line_id, p_qty, null, p_rack_id, null, null, p_stage_id, p_idem_prefix || '-gen', '00000000-0000-0000-0000-000000990002', 'supervisor');
  v_t := app.claim_wms_pick_task(v_t.id, v_t.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
  perform app.confirm_wms_pick_task(v_t.id, p_qty, p_rack_id, p_item_master_id, null, null, p_stage_id, p_idem_prefix || '-conf', v_t.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
end;
$proc$;

create function pack_task_fully(p_outbound_order_id uuid, p_pick_task_id uuid, p_item_master_id uuid, p_qty numeric, p_idem_prefix text)
returns app.wms_packages
language plpgsql
as $fn$
declare
  v_packing_task app.wms_packing_tasks;
  v_pkg app.wms_packages;
begin
  v_packing_task := app.start_wms_packing_task(p_outbound_order_id, p_idem_prefix || '-task', '00000000-0000-0000-0000-000000990002', 'supervisor');
  v_pkg := app.create_wms_package(v_packing_task.id, null, 'carton', p_idem_prefix || '-pkg', '00000000-0000-0000-0000-000000990002', 'supervisor');
  v_pkg := app.add_wms_package_line(v_pkg.id, p_pick_task_id, p_qty, p_item_master_id, null, null, p_idem_prefix || '-line', v_pkg.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
  v_pkg := app.record_wms_package_measurements(v_pkg.id, 5, 'KG', null, null, null, null, v_pkg.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
  v_pkg := app.record_wms_package_qc(v_pkg.id, 'pass', null, v_pkg.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
  v_pkg := app.record_wms_package_seal(v_pkg.id, p_idem_prefix || '-seal', v_pkg.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
  v_pkg := app.confirm_wms_package(v_pkg.id, p_idem_prefix || '-confirm', v_pkg.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
  return v_pkg;
end;
$fn$;

\echo '>> build Account Alpha (via the full CRM->Job Order pipeline), a vendor master record, and two item masters (SKU-CLAIM-1 for the ledger-movement/receiving-discrepancy evidence axis, SKU-CLAIM-2 for the wms_outbound_shipment/package evidence axis)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CLAIMINC1-CO');
  v_actor uuid := '00000000-0000-0000-0000-000000990002';
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
  v_vendor app.master_records;
  v_actor2 uuid := '00000000-0000-0000-0000-000000990004';
  v_account2 app.accounts;
  v_job_order2 app.job_orders;
begin
  perform app.capture_lead(v_tenant1, 'manual', null, 'Claim Customer Alpha', 'Alice Claim', 'alice@claiminc241.test', '0811', v_actor, v_company, v_actor, 'tester');
  select * into v_lead from app.leads where email = 'alice@claiminc241.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_actor, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Claim Customer Alpha', 'CLAIMINC241A', '11.111.111.51-111.000',
    jsonb_build_object('line1', 'Jl. Claim Alpha 1', 'city', 'Jakarta', 'country', 'ID'), v_actor, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice Claim Ops', 'Ops Lead', 'alice@claiminc241.test', '0811', v_actor, v_company, v_actor, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_actor, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'CLAIMINC241 Alpha lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Makassar', 'target_ready_date', '2026-08-01'),
    v_actor, v_company, v_actor, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_actor, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-CLAIMINC241-A', 'Contoso Claim Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Makassar', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000990001', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000990001', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_actor, 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_actor, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_actor, 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, v_actor, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_actor, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'CLAIMINC241 Alpha lane', v_calc_id, 1, 15000000, 0, 0, v_actor, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_actor, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_actor, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice Claim Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_actor, 'tester');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_actor, 'tester');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_actor, 'tester');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_actor, 'tester');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-CLAIM-1', 'Contoso Claim Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000990001', 'admin');

  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-CLAIM-1', 'Claim Widget 1 (ledger movement)', null, 'PCS', false, false, false, v_actor, 'tester');
  perform app.create_item_master(v_tenant1, v_account.id, 'SKU-CLAIM-2', 'Claim Widget 2 (wms outbound shipment)', null, 'PCS', false, false, false, v_actor, 'tester');

  -- A SECOND, fully independent CRM->Job Order pipeline, run entirely by
  -- investigator (v_actor2). Required because app.create_shipment_order_from_job
  -- ALSO record-scope-checks the underlying Job Order (app.can_access_record
  -- against job_orders.owner_user_id, verified directly by hitting this exact
  -- insufficient_authority error against Job Order A) -- investigator needs to
  -- own its own Job Order, not merely the eventual Shipment, for Shipment B's
  -- own creation call to succeed.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Claim Customer Beta', 'Diana Claim', 'diana@claiminc241.test', '0813', v_actor2, v_company, v_actor2, 'tester');
  select * into v_lead from app.leads where email = 'diana@claiminc241.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_actor2, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Claim Customer Beta', 'CLAIMINC241B', '11.111.111.52-111.000',
    jsonb_build_object('line1', 'Jl. Claim Beta 1', 'city', 'Jakarta', 'country', 'ID'), v_actor2, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Diana Claim Ops', 'Ops Lead', 'diana@claiminc241.test', '0813', v_actor2, v_company, v_actor2, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_actor2, 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'CLAIMINC241 Beta lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    v_actor2, v_company, v_actor2, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_actor2, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-CLAIMINC241-B', 'Contoso Claim Line B', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000990001', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000990001', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_actor2, 'tester');
  perform app.calculate_margin(v_selection.id, 8000000, 'IDR', 0, v_actor2, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_actor2, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'CLAIMINC241 Beta lane', v_calc_id, 1, 8000000, 0, 0, v_actor2, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_actor2, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_actor2, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Diana Claim Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account2 from app.convert_quotation_to_account(v_quote.id, null, null, v_actor2, 'tester');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_actor2, 'tester');
  select * into v_job_order2 from app.prepare_job_order(v_handoff.id, v_actor2, 'tester');
  select * into v_job_order2 from app.confirm_job_order(v_job_order2.id, v_job_order2.record_version, v_actor2, 'tester');
end $$;

\echo '>> build Shipment A (multi-leg: 2 legs + stops + cargo allocation + a custody event, confirmed leg network, full transition planned->assigned->dispatched->in_transit->delivered) and Shipment B (simple, confirmed only -- no leg network, used for the inventory_movement/wms_outbound_shipment/delay/hold evidence axes)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.quotations q on q.id = jo.quotation_id join app.opportunities o on o.id = q.opportunity_id where o.tenant_id = v_tenant1 and o.name = 'CLAIMINC241 Alpha lane');
  v_job_order2_id uuid := (select jo.id from app.job_orders jo join app.quotations q on q.id = jo.quotation_id join app.opportunities o on o.id = q.opportunity_id where o.tenant_id = v_tenant1 and o.name = 'CLAIMINC241 Beta lane');
  v_actor uuid := '00000000-0000-0000-0000-000000990002';
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_vendor_id uuid := (select id from app.master_records where tenant_id = v_tenant1 and code = 'VEND-CLAIM-1');
  v_shipment_a app.shipment_orders;
  v_shipment_b app.shipment_orders;
  v_leg1 app.shipment_legs;
  v_leg2 app.shipment_legs;
begin
  select * into v_shipment_a from app.create_shipment_order_from_job(
    v_job_order_id, 'idem-claim-shipA', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Makassar',
    now() + interval '1 day', now() + interval '10 days', 100, 5000, 40, 100, 5000, 40, null, v_actor, 'supervisor'
  );
  select * into v_shipment_a from app.confirm_shipment_order(v_shipment_a.id, v_shipment_a.record_version, v_actor, 'supervisor');

  -- Multi-leg network.
  v_leg1 := app.add_shipment_leg(v_shipment_a.id, 'idem-claim-leg1', 1, 'land', v_vendor_id, now(), now() + interval '1 day', v_actor, 'supervisor');
  v_leg2 := app.add_shipment_leg(v_shipment_a.id, 'idem-claim-leg2', 2, 'sea', v_vendor_id, now() + interval '1 day', now() + interval '9 days', v_actor, 'supervisor');
  perform app.add_shipment_leg_stop(v_leg1.id, 1, 'pickup', 'Jakarta Warehouse', 'Jl. Rasuna Said 1', 106.8456, -6.2088, now(), v_actor, 'supervisor');
  perform app.add_shipment_leg_stop(v_leg1.id, 2, 'transfer', 'Surabaya Transfer Yard', null, null, null, now() + interval '1 day', v_actor, 'supervisor');
  perform app.add_shipment_leg_stop(v_leg2.id, 1, 'transfer', 'Surabaya Port', null, null, null, now() + interval '1 day', v_actor, 'supervisor');
  perform app.add_shipment_leg_stop(v_leg2.id, 2, 'delivery', 'Makassar Warehouse', null, null, null, now() + interval '10 days', v_actor, 'supervisor');
  perform app.allocate_shipment_leg_cargo(v_leg1.id, 60, 3000, 24, v_actor, 'supervisor');
  perform app.allocate_shipment_leg_cargo(v_leg2.id, 40, 2000, 16, v_actor, 'supervisor');
  perform app.record_shipment_leg_custody_event(
    v_leg1.id, 'custody_transfer', null,
    jsonb_build_object('party', 'carrier', 'name', 'Contoso Claim Trucking', 'master_record_id', v_vendor_id),
    now(), jsonb_build_object('note', 'initial pickup custody'), v_actor, 'supervisor'
  );
  select * into v_shipment_a from app.confirm_shipment_leg_network(v_shipment_a.id, (select record_version from app.shipment_orders where id = v_shipment_a.id), v_actor, 'supervisor');

  -- Full transition to delivered (needs a vendor resource assigned before dispatched).
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'planned', v_shipment_a.record_version, null, null, 'idem-claim-shipA-planned', v_actor, 'supervisor');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'assigned', v_shipment_a.record_version, null, null, 'idem-claim-shipA-assigned', v_actor, 'supervisor');
  perform app.assign_resource(v_shipment_a.id, 'vendor', v_vendor_id, v_actor, 'supervisor');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'dispatched', v_shipment_a.record_version, null, null, 'idem-claim-shipA-dispatched', v_actor, 'supervisor');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'in_transit', v_shipment_a.record_version, null, null, 'idem-claim-shipA-intransit', v_actor, 'supervisor');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'delivered', v_shipment_a.record_version, null, 'physical delivery confirmed', 'idem-claim-shipA-delivered', v_actor, 'supervisor');

  -- Shipment B: a simple, single-leg (legacy) shipment -- confirmed only, no
  -- delivery/epod needed (inventory_movement/wms_outbound_shipment evidence carries
  -- no shipment_order_id linkage at all -- see this migration's own header).
  -- Deliberately created by the INVESTIGATOR, from investigator's OWN job order
  -- (job_order2, Beta lane) -- app.create_shipment_order_from_job itself record-
  -- scope-checks the underlying Job Order too (verified directly by hitting
  -- insufficient_authority against Job Order A first), so investigator genuinely
  -- needs to own the Job Order feeding Shipment B, not merely the eventual
  -- shipment. app.can_access_record only ever passes for a record's own literal
  -- owner_user_id here (org_unit_id is never populated by either
  -- app.create_shipment_order_from_job or, transitively, the Job Order it reads,
  -- verified directly) -- never a fabricated bypass. investigator holds
  -- OPS:Create, so it may call both directly.
  select * into v_shipment_b from app.create_shipment_order_from_job(
    v_job_order2_id, 'idem-claim-shipB', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '5 days', null, null, null, null, null, null, null, v_investigator, 'investigator'
  );
  select * into v_shipment_b from app.confirm_shipment_order(v_shipment_b.id, v_shipment_b.record_version, v_investigator, 'investigator');
end $$;

\echo '>> register the claim_evidence document type; capture and complete a real ePOD on Shipment A (signature file uploaded and scanned clean by supervisor, Shipment A''s own owner, later reused as file evidence too); upload a second, DELIBERATELY UNSCANNED file against Shipment B by investigator, Shipment B''s own owner (the unsafe-file-evidence-link-rejection fixture)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_pod_draft app.config_versions;
  v_shipment_a_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-shipA');
  v_shipment_b_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-shipB');
  v_signature app.files;
  v_pending_file app.files;
  v_capture app.epod_captures;
begin
  perform app.register_document_type('claim_evidence', 'Claim/Incident Evidence', 'DOC', '00000000-0000-0000-0000-000000990007', 'supreme');
  v_pod_draft := app.create_config_draft('document:claim_evidence', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000990001', 'admin');
  perform app.set_config_items(v_pod_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000990001', 'admin');
  perform app.publish_document_type_definition(v_pod_draft.id, '00000000-0000-0000-0000-000000990001', now(), 'admin');

  -- Uploaded by supervisor -- the SAME actor who will later link it as claim
  -- evidence on case1 (Shipment A, owned by supervisor), so app.authorize_file_
  -- access's own uploaded_by_auth_user_id = actor short-circuit applies cleanly.
  select * into v_signature from app.initiate_file_upload(
    v_tenant1, 'claim_evidence', 'shipment_order', v_shipment_a_id, 'shipA-signature.jpg', 'image/jpeg', 20480, null, false, null, '{}'::uuid[], null, 'idem-claim-shipA-sig', '00000000-0000-0000-0000-000000990002', 'supervisor'
  );
  perform app.record_file_scan_result(v_signature.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000990002', 'supervisor');

  v_capture := app.start_epod_capture(v_tenant1, v_shipment_a_id, null, 'idem-claim-shipA-epod', '00000000-0000-0000-0000-000000990002', 'supervisor');
  v_capture := app.set_epod_evidence(
    v_capture.id, 'Budi Santoso', 'Warehouse Staff', v_signature.id, '{}'::uuid[],
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(119.4221, -5.1477)), now(), '00000000-0000-0000-0000-000000990002', 'supervisor'
  );
  v_capture := app.submit_epod_capture(v_capture.id, v_capture.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
  v_capture := app.review_epod_capture(v_capture.id, 'approved', null, v_capture.record_version, '00000000-0000-0000-0000-000000990002', 'supervisor');
  perform app.complete_epod_capture(v_capture.id, v_capture.record_version, (select record_version from app.shipment_orders where id = v_shipment_a_id), 'idem-claim-shipA-epod-complete', '00000000-0000-0000-0000-000000990002', 'supervisor');

  -- Deliberately left UNSCANNED (status stays 'pending') -- the unsafe-evidence
  -- fixture. Uploaded by investigator, Shipment B's own owner.
  select * into v_pending_file from app.initiate_file_upload(
    v_tenant1, 'claim_evidence', 'shipment_order', v_shipment_b_id, 'shipB-unscanned.jpg', 'image/jpeg', 20480, null, false, null, '{}'::uuid[], null, 'idem-claim-shipB-pending', '00000000-0000-0000-0000-000000990004', 'investigator'
  );
end $$;

\echo '>> build inventory_movement evidence (opening balance + a real adjustment movement representing a receiving discrepancy/damage-on-arrival) and wms_outbound_shipment evidence (confirmed outbound order, picked, packed, shipped) for Account Alpha at WH-CLAIM-1'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CLAIM-1');
  v_rack_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CLAIM-A');
  v_stage_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-CLAIM-1');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-CLAIM-1');
  v_actor uuid := '00000000-0000-0000-0000-000000990002';
  v_account_id uuid := (select owner_account_id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CLAIM-1');
  v_item1 app.item_masters;
  v_item2 app.item_masters;
  v_order app.wms_outbound_orders;
  v_line app.wms_outbound_order_lines;
  v_pick app.wms_pick_tasks;
  v_pkg app.wms_packages;
  v_shipment app.wms_outbound_shipments;
begin
  select * into v_item1 from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CLAIM-1';
  select * into v_item2 from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CLAIM-2';

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-claim-ob-1', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item1.id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 50)),
    v_actor, 'supervisor');
  -- The real "receiving discrepancy" evidence row: a governed adjustment (reason
  -- mandatory) recording 5 units found damaged during a stock count.
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'adjustment', 'manual', null, 'idem-claim-adj-1', 'stock count: 5 units found crushed/damaged',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item1.id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', -5)),
    v_actor, 'supervisor');

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-claim-ob-2', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_id, 'item_master_id', v_item2.id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 30)),
    v_actor, 'supervisor');

  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_id, 'customer order', 'idem-claim-outbound-1', current_date + 3, v_actor, 'supervisor');
  v_line := app.add_wms_outbound_order_line(v_order.id, v_item2.id, 'PCS', 10, null, v_actor, 'supervisor');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, v_actor, 'supervisor');

  call pick_fully(v_line.id, v_item2.id, 10, v_rack_id, v_stage_id, 'idem-claim-pick1');
  select * into v_pick from app.wms_pick_tasks where outbound_order_line_id = v_line.id;
  v_pkg := pack_task_fully(v_order.id, v_pick.id, v_item2.id, 10, 'idem-claim-pack1');

  v_shipment := app.create_wms_outbound_shipment(v_order.id, 'idem-claim-wms-shipment-1', v_actor, 'supervisor');
  perform app.add_package_to_shipment(v_shipment.id, v_pkg.id, 'idem-claim-add1', v_actor, 'supervisor');
  v_shipment := app.set_wms_shipment_dock_location(v_shipment.id, v_dock_id, v_shipment.record_version, v_actor, 'supervisor');
  v_shipment := app.load_wms_outbound_shipment(v_shipment.id, 'idem-claim-load-1', v_shipment.record_version, v_actor, 'supervisor');
  perform app.ship_confirm_wms_outbound_shipment(v_shipment.id, 'Claim Custody', 'delivered to carrier', false, null, 'idem-claim-ship-1', v_shipment.record_version, v_actor, 'supervisor');
end $$;

\echo '>> build a SECOND inventory_movement (adjustment) and wms_outbound_shipment, owned by Account Beta (Claim Customer Beta) at WH-CLAIM-1 -- case2 (below) is opened against Shipment B, Account Beta''s own shipment, so its own linked evidence must genuinely belong to Account Beta, never Account Alpha''s. Also the live fixture behind the cross-customer scope-mismatch negative test: Account Alpha''s own wms_outbound_shipment (idem-claim-wms-shipment-1, built above) must be REJECTED as evidence on case2 now that app.link_claim_evidence/app.add_claim_item validate wms_outbound_shipment.owner_account_id against the claim case''s own shipment order shipper_account_id (see migration header design note 3)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CLAIM-1');
  v_rack_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'RACK-CLAIM-A');
  v_stage_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'STAGE-CLAIM-1');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and code = 'DOCK-CLAIM-1');
  v_actor uuid := '00000000-0000-0000-0000-000000990002';
  -- Account Beta's own real id -- resolved via its own tax_id (set at
  -- app.convert_lead_to_prospect time for the "Claim Customer Beta" pipeline
  -- above), never a fabricated/guessed id.
  v_account2_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and tax_id = '11.111.111.52-111.000');
  v_item1b app.item_masters;
  v_order app.wms_outbound_orders;
  v_line app.wms_outbound_order_lines;
  v_pick app.wms_pick_tasks;
  v_pkg app.wms_packages;
  v_shipment app.wms_outbound_shipments;
begin
  if v_account2_id is null then
    raise exception 'assertion failed: expected Account Beta (tax_id 11.111.111.52-111.000) to already exist';
  end if;

  perform app.create_item_master(v_tenant1, v_account2_id, 'SKU-CLAIM-1B', 'Claim Widget 1B (Account Beta ledger movement / wms outbound shipment)', null, 'PCS', false, false, false, v_actor, 'tester');
  select * into v_item1b from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CLAIM-1B';

  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'opening_balance', 'opening_balance', null, 'idem-claim-ob-1b', null,
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account2_id, 'item_master_id', v_item1b.id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', 30)),
    v_actor, 'supervisor');
  -- The real "receiving discrepancy/shortage" evidence row for Account Beta.
  perform app.post_inventory_movement(v_tenant1, v_warehouse_id, 'adjustment', 'manual', null, 'idem-claim-adj-1b', 'stock count: 5 units found crushed/damaged (Account Beta, shortage)',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account2_id, 'item_master_id', v_item1b.id, 'location_id', v_rack_id, 'uom_code', 'PCS', 'signed_quantity', -5)),
    v_actor, 'supervisor');

  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account2_id, 'customer order (Account Beta)', 'idem-claim-outbound-1b', current_date + 3, v_actor, 'supervisor');
  v_line := app.add_wms_outbound_order_line(v_order.id, v_item1b.id, 'PCS', 10, null, v_actor, 'supervisor');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, v_actor, 'supervisor');

  call pick_fully(v_line.id, v_item1b.id, 10, v_rack_id, v_stage_id, 'idem-claim-pick1b');
  select * into v_pick from app.wms_pick_tasks where outbound_order_line_id = v_line.id;
  v_pkg := pack_task_fully(v_order.id, v_pick.id, v_item1b.id, 10, 'idem-claim-pack1b');

  v_shipment := app.create_wms_outbound_shipment(v_order.id, 'idem-claim-wms-shipment-1b', v_actor, 'supervisor');
  perform app.add_package_to_shipment(v_shipment.id, v_pkg.id, 'idem-claim-add1b', v_actor, 'supervisor');
  v_shipment := app.set_wms_shipment_dock_location(v_shipment.id, v_dock_id, v_shipment.record_version, v_actor, 'supervisor');
  v_shipment := app.load_wms_outbound_shipment(v_shipment.id, 'idem-claim-load-1b', v_shipment.record_version, v_actor, 'supervisor');
  perform app.ship_confirm_wms_outbound_shipment(v_shipment.id, 'Claim Custody Beta', 'delivered to carrier', false, null, 'idem-claim-ship-1b', v_shipment.record_version, v_actor, 'supervisor');
end $$;

\echo '>> report 5 real operational exceptions (damage/loss/delay/hold/incident) and assign an owner/investigator for the three that need one: exception1 for its own investigation finding below, AND exception2/exception5 for their own item/evidence management (app.add_claim_item/app.withdraw_claim_item/app.link_claim_evidence now require the acting identity to equal the underlying exception''s own owner_user_id, the SAME rule already enforced for app.record_claim_investigation_finding -- see migration header design note 4)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_shipment_a_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-shipA');
  v_shipment_b_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-shipB');
  v_actor uuid := '00000000-0000-0000-0000-000000990002';
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_exception1 app.operational_exceptions;
  v_exception2 app.operational_exceptions;
  v_exception3 app.operational_exceptions;
  v_exception4 app.operational_exceptions;
  v_exception5 app.operational_exceptions;
begin
  -- Exception1 lives on Shipment A (owned by supervisor) -- supervisor reports it
  -- and self-assigns as its own owner (the reused investigator role, exercised by
  -- the same actor who genuinely passes Shipment A's own record-scope).
  v_exception1 := app.report_exception(v_shipment_a_id, null, 'damage', 'high', 'Multiple cartons crushed in transit on the land leg', 'manual', null, v_actor, 'supervisor');
  perform app.assign_exception_owner(v_exception1.id, v_actor, null, v_actor, 'supervisor');

  -- Exceptions 2-5 live on Shipment B (owned by investigator) -- investigator
  -- reports them directly (holds OPS:Create and genuinely passes Shipment B's own
  -- record-scope as its creator). "shortage" (Prompt 244 §27's own test-data
  -- wording) is represented at the item level under this 'loss' exception (see
  -- migration header) -- exception2's own description names it directly too.
  v_exception2 := app.report_exception(v_shipment_b_id, null, 'loss', 'medium', 'Carton reported missing at destination (shortage)', 'manual', null, v_investigator, 'investigator');
  v_exception3 := app.report_exception(v_shipment_b_id, null, 'delay', 'low', 'Shipment delayed 2 days at customs', 'manual', null, v_investigator, 'investigator');
  v_exception4 := app.report_exception(v_shipment_b_id, null, 'hold', 'medium', 'Shipment placed on credit hold', 'manual', null, v_investigator, 'investigator');
  v_exception5 := app.report_exception(v_shipment_b_id, null, 'incident', 'high', 'Minor safety incident during handling', 'manual', null, v_investigator, 'investigator');

  if v_exception1.type <> 'damage' or v_exception2.type <> 'loss' or v_exception3.type <> 'delay' or v_exception4.type <> 'hold' or v_exception5.type <> 'incident' then
    raise exception 'assertion failed: unexpected exception types recorded';
  end if;

  -- exception2/exception5 formally assigned to investigator (990004) as their own
  -- owner -- BEFORE case2/case4 (below) ever add an item or link evidence. Assigned
  -- by Supreme Admin: investigator itself lacks OPS:Assign, and supervisor does not
  -- pass Shipment B's own record-scope (ratified absolute authority per AGENTS.md).
  perform app.assign_exception_owner(v_exception2.id, v_investigator, null, v_supreme, 'supreme');
  perform app.assign_exception_owner(v_exception5.id, v_investigator, null, v_supreme, 'supreme');
end $$;

\echo '>> app.open_claim_case: claimant validation (invalid claimant_type, identification_required for a non-internal/non-account claimant, invalid contact_snapshot key, claimant_account not found), viewer denied insufficient_authority, ineligible exception type (hold) rejected, then a real successful open on the damage exception (case1) plus idempotent duplicate-open proving no second row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_account_id uuid := (select owner_account_id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CLAIM-1');
  v_exception1_id uuid := (select id from app.operational_exceptions where tenant_id = v_tenant1 and type = 'damage');
  v_exception2_id uuid := (select id from app.operational_exceptions where tenant_id = v_tenant1 and type = 'loss');
  v_exception4_id uuid := (select id from app.operational_exceptions where tenant_id = v_tenant1 and type = 'hold');
  v_supervisor uuid := '00000000-0000-0000-0000-000000990002';
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_viewer uuid := '00000000-0000-0000-0000-000000990006';
  v_case1 app.claim_case_extensions;
  v_case1_retry app.claim_case_extensions;
  v_case_count integer;
begin
  -- exception2/exception4 both live on Shipment B (owned by investigator) --
  -- these validation-failure tests use investigator (the actor who genuinely
  -- passes Shipment B's own record-scope) so the failure is provably the
  -- claimant/eligibility validation itself, never an incidental record-scope
  -- rejection.
  begin
    perform app.open_claim_case(v_exception2_id, 'insurer', null, null, null, v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_invalid_claimant_type for an unrecognized claimant_type';
  exception
    when others then
      if sqlerrm not like 'claim_invalid_claimant_type%' then raise; end if;
  end;

  begin
    perform app.open_claim_case(v_exception2_id, 'third_party', null, null, null, v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_claimant_identification_required for a non-internal claimant with neither account nor label';
  exception
    when others then
      if sqlerrm not like 'claim_claimant_identification_required%' then raise; end if;
  end;

  begin
    perform app.open_claim_case(v_exception2_id, 'customer', v_account_id, null, jsonb_build_object('name', 'Alice', 'address', 'Jl. Sudirman 1'), v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_invalid_contact_snapshot for a non-minimized (address) key';
  exception
    when others then
      if sqlerrm not like 'claim_invalid_contact_snapshot%' then raise; end if;
  end;

  begin
    perform app.open_claim_case(v_exception2_id, 'customer', gen_random_uuid(), null, null, v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_claimant_account_not_found for a random claimant_account_id';
  exception
    when others then
      if sqlerrm not like 'claim_claimant_account_not_found%' then raise; end if;
  end;

  -- Fails at the earlier RBAC gate (lacks OPS:Create) regardless of shipment
  -- ownership -- viewer is never assigned any shipment.
  begin
    perform app.open_claim_case(v_exception2_id, 'customer', v_account_id, null, null, v_viewer, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a viewer (no OPS:Create) opening a claim case';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.open_claim_case(v_exception4_id, 'internal', null, null, null, v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_ineligible_exception_type for a hold-type exception';
  exception
    when others then
      if sqlerrm not like 'claim_ineligible_exception_type%' then raise; end if;
  end;

  select count(*) into v_case_count from app.operational_exceptions where id = v_exception4_id;
  if not exists (select 1 from app.claim_case_extensions where operational_exception_id = v_exception4_id) then
    null; -- expected: the rejected hold exception never got a claim_case_extensions row
  else
    raise exception 'assertion failed: a rejected open_claim_case attempt must never leave a row behind';
  end if;

  v_case1 := app.open_claim_case(v_exception1_id, 'customer', v_account_id, null, jsonb_build_object('name', 'Alice Claim', 'email', 'alice@claiminc241.test'), v_supervisor, 'supervisor');
  if v_case1.claim_stage <> 'intake' or v_case1.operational_exception_id <> v_exception1_id then
    raise exception 'assertion failed: expected a fresh intake-stage case1, got claim_stage=% operational_exception_id=%', v_case1.claim_stage, v_case1.operational_exception_id;
  end if;

  -- Idempotent duplicate-open: the EXACT same row, never a second one -- the real
  -- DB constraint (unique(operational_exception_id)) behind "no duplicate root or
  -- silent re-entry." A genuine replay (identical claimant_type/claimant_account_id/
  -- claimant_label/contact_snapshot) returns the existing row.
  v_case1_retry := app.open_claim_case(v_exception1_id, 'customer', v_account_id, null, jsonb_build_object('name', 'Alice Claim', 'email', 'alice@claiminc241.test'), v_supervisor, 'supervisor');
  if v_case1_retry.id <> v_case1.id then
    raise exception 'assertion failed: expected the duplicate open_claim_case attempt to return the SAME case id, got % vs %', v_case1_retry.id, v_case1.id;
  end if;
  select count(*) into v_case_count from app.claim_case_extensions where operational_exception_id = v_exception1_id;
  if v_case_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE claim_case_extensions row for exception1, got %', v_case_count;
  end if;

  -- A resubmission whose own content DIFFERS from the original open (here:
  -- claimant_label populated where the original had none) is a real conflict, not
  -- a silently discarded resubmission (mirrors app.create_label_printer, ATW-021).
  begin
    perform app.open_claim_case(v_exception1_id, 'customer', v_account_id, 'a materially different claimant_label', null, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected claim_case_open_conflict re-opening exception1 with different claimant details';
  exception
    when others then
      if sqlerrm not like 'claim_case_open_conflict%' then raise; end if;
  end;
  select count(*) into v_case_count from app.claim_case_extensions where operational_exception_id = v_exception1_id;
  if v_case_count <> 1 then
    raise exception 'assertion failed: a rejected mismatched re-open must never leave a second row behind, got %', v_case_count;
  end if;
  if (select claimant_label from app.claim_case_extensions where id = v_case1.id) is not null then
    raise exception 'assertion failed: a rejected mismatched re-open must never touch the existing row''s own claimant_label';
  end if;
end $$;

\echo '>> app.add_claim_item / app.withdraw_claim_item on case1: Supreme Admin (genuinely passes record-scope via the is_supreme_admin bypass, but is NOT exception1''s own assigned owner/investigator -- supervisor is) is rejected claim_not_investigator on both, live-demonstrating investigator-only evidence management now applies uniformly (see migration header design note 4); two real items (one linked to nothing but description, one linked to a real item_master), withdraw one with a reason, stale_version on a repeat withdrawal, validation (bad quantity, empty description, value/currency shape)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case1_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'damage');
  v_item2_master_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CLAIM-2');
  v_supervisor uuid := '00000000-0000-0000-0000-000000990002';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_item1 app.claim_items;
  v_item2 app.claim_items;
  v_withdrawn app.claim_items;
begin
  begin
    perform app.add_claim_item(v_case1_id, 'cargo_general', null, null, null, 1, 'PCS', null, null, 'not the assigned investigator', v_supreme, 'supreme');
    raise exception 'assertion failed: expected claim_not_investigator for Supreme Admin (not exception1''s own owner_user_id, even though Supreme Admin genuinely passes record-scope)';
  exception
    when others then
      if sqlerrm not like 'claim_not_investigator%' then raise; end if;
  end;

  begin
    perform app.add_claim_item(v_case1_id, 'cargo_general', null, null, null, 0, 'PCS', null, null, 'zero quantity', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected claim_invalid_declared_quantity for a zero declared_quantity';
  exception
    when others then
      if sqlerrm not like 'claim_invalid_declared_quantity%' then raise; end if;
  end;

  begin
    perform app.add_claim_item(v_case1_id, 'cargo_general', null, null, null, 1, 'PCS', 100, null, 'value without currency', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected claim_value_currency_shape_invalid when declared_value is set without currency';
  exception
    when others then
      if sqlerrm not like 'claim_value_currency_shape_invalid%' then raise; end if;
  end;

  v_item1 := app.add_claim_item(v_case1_id, 'cargo_general', null, null, null, 3, 'PCS', 900000, 'IDR', '3 cartons crushed, general cargo damage', v_supervisor, 'supervisor');
  v_item2 := app.add_claim_item(v_case1_id, 'inventory', null, null, v_item2_master_id, 1, 'PCS', 150000, 'IDR', 'duplicate line entered in error', v_supervisor, 'supervisor');

  if (select claim_stage from app.claim_case_extensions where id = v_case1_id) <> 'evidence_gathering' then
    raise exception 'assertion failed: expected claim_stage to advance to evidence_gathering after the first claim item';
  end if;

  begin
    perform app.withdraw_claim_item(v_item1.id, v_item1.record_version, 'not the assigned investigator', v_supreme, 'supreme');
    raise exception 'assertion failed: expected claim_not_investigator withdrawing an item as a non-investigator';
  exception
    when others then
      if sqlerrm not like 'claim_not_investigator%' then raise; end if;
  end;

  v_withdrawn := app.withdraw_claim_item(v_item2.id, v_item2.record_version, 'duplicate entry', v_supervisor, 'supervisor');
  if v_withdrawn.status <> 'withdrawn' or v_withdrawn.withdrawal_reason <> 'duplicate entry' then
    raise exception 'assertion failed: expected item2 to be withdrawn with its own reason preserved';
  end if;

  begin
    perform app.withdraw_claim_item(v_item2.id, v_item2.record_version, 'second attempt', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected invalid_transition withdrawing an already-withdrawn item';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> app.link_claim_evidence on case1: Supreme Admin (not exception1''s own assigned owner/investigator) is rejected claim_not_investigator; shipment_leg, shipment_leg_custody_event, epod_capture and file (the completed ePOD signature, reused directly) all link successfully and advance claim_stage; not-found and cross-shipment scope-mismatch are rejected; a genuine idempotent replay (identical note) returns the existing row, a MISMATCHED replay (different note) is rejected claim_evidence_link_conflict'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case1_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'damage');
  v_case2_id uuid;
  v_shipment_b_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-shipB');
  v_leg1_id uuid := (select id from app.shipment_legs where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-leg1');
  v_custody_id uuid := (select id from app.shipment_leg_custody_events where shipment_leg_id = v_leg1_id);
  v_epod_id uuid := (select id from app.epod_captures where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-shipA-epod');
  v_signature_file_id uuid := (select id from app.files where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-shipA-sig');
  v_supervisor uuid := '00000000-0000-0000-0000-000000990002';
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_link1 app.claim_evidence_links;
  v_link2 app.claim_evidence_links;
  v_link3 app.claim_evidence_links;
  v_link4 app.claim_evidence_links;
  v_account_id uuid := (select owner_account_id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CLAIM-1');
begin
  begin
    perform app.link_claim_evidence(v_case1_id, 'shipment_leg', v_leg1_id, 'not the assigned investigator', v_supreme, 'supreme');
    raise exception 'assertion failed: expected claim_not_investigator for Supreme Admin (not exception1''s own owner_user_id, even though Supreme Admin genuinely passes record-scope)';
  exception
    when others then
      if sqlerrm not like 'claim_not_investigator%' then raise; end if;
  end;

  -- case1 is on Shipment A (owned by supervisor) -- supervisor is the actor who
  -- genuinely passes record-scope here.
  v_link1 := app.link_claim_evidence(v_case1_id, 'shipment_leg', v_leg1_id, 'land leg carrying the crushed cartons', v_supervisor, 'supervisor');
  v_link2 := app.link_claim_evidence(v_case1_id, 'shipment_leg_custody_event', v_custody_id, 'custody transfer at pickup', v_supervisor, 'supervisor');
  v_link3 := app.link_claim_evidence(v_case1_id, 'epod_capture', v_epod_id, 'delivery confirmation', v_supervisor, 'supervisor');
  -- The SAME actor who uploaded the file also links it -- app.authorize_file_access
  -- short-circuits to granted (uploaded_by_auth_user_id = actor), proving the reuse
  -- path without a false-negative from its own separate org-unit-sharing gate.
  v_link4 := app.link_claim_evidence(v_case1_id, 'file', v_signature_file_id, 'delivery signature photo', v_supervisor, 'supervisor');

  if v_link1.evidence_type <> 'shipment_leg' or v_link4.evidence_type <> 'file' then
    raise exception 'assertion failed: unexpected evidence_type recorded';
  end if;

  begin
    perform app.link_claim_evidence(v_case1_id, 'inventory_movement', gen_random_uuid(), null, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected claim_evidence_not_found for a random evidence_id';
  exception
    when others then
      if sqlerrm not like 'claim_evidence_not_found%' then raise; end if;
  end;

  -- Idempotent duplicate link: the SAME (case, type, id) tuple AND the identical
  -- note returns the existing row unchanged.
  if (app.link_claim_evidence(v_case1_id, 'shipment_leg', v_leg1_id, 'land leg carrying the crushed cartons', v_supervisor, 'supervisor')).id <> v_link1.id then
    raise exception 'assertion failed: expected a genuine duplicate evidence link (identical note) to return the existing row';
  end if;

  -- The SAME (case, type, id) tuple with a DIFFERENT note is a real conflict, not a
  -- silently discarded resubmission (mirrors app.create_label_printer, ATW-021).
  begin
    perform app.link_claim_evidence(v_case1_id, 'shipment_leg', v_leg1_id, 'a materially different note than the original', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected claim_evidence_link_conflict re-linking the same evidence with a different note';
  exception
    when others then
      if sqlerrm not like 'claim_evidence_link_conflict%' then raise; end if;
  end;
  if (select note from app.claim_evidence_links where id = v_link1.id) <> 'land leg carrying the crushed cartons' then
    raise exception 'assertion failed: a rejected mismatched relink must never touch the existing row''s own note';
  end if;

  -- Open case2 (loss, Shipment B, owned by investigator) now, to prove
  -- cross-shipment scope mismatch: Shipment A's own leg does not belong to
  -- case2's own shipment order (Shipment B).
  v_case2_id := (app.open_claim_case(
    (select id from app.operational_exceptions where tenant_id = v_tenant1 and type = 'loss'),
    'carrier', null, 'Contoso Claim Trucking (carrier-filed claim)', jsonb_build_object('phone', '0812'),
    v_investigator, 'investigator'
  )).id;

  begin
    perform app.link_claim_evidence(v_case2_id, 'shipment_leg', v_leg1_id, null, v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_evidence_scope_mismatch linking Shipment A''s own leg onto case2 (scoped to Shipment B)';
  exception
    when others then
      if sqlerrm not like 'claim_evidence_scope_mismatch%' then raise; end if;
  end;

  if (select claim_stage from app.claim_case_extensions where id = v_case1_id) <> 'evidence_gathering' then
    raise exception 'assertion failed: expected case1 to remain at evidence_gathering (no finding recorded yet)';
  end if;
end $$;

\echo '>> app.record_claim_investigation_finding on case1: the assigned investigator (supervisor, self-assigned as exception1''s own owner_user_id) succeeds and advances claim_stage to investigating; a non-investigator (Supreme Admin -- genuinely passes record-scope via the is_supreme_admin bypass, but is NOT exception1''s own owner_user_id) is rejected claim_not_investigator; empty finding_text rejected; a SECOND finding proves evidence_sufficiency=insufficient is a real, distinct storable value too (not only sufficient)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case1_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'damage');
  v_supervisor uuid := '00000000-0000-0000-0000-000000990002';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_finding app.claim_investigation_findings;
  v_second_finding app.claim_investigation_findings;
begin
  begin
    perform app.record_claim_investigation_finding(v_case1_id, 'not the assigned investigator', 'pending', v_supreme, 'supreme');
    raise exception 'assertion failed: expected claim_not_investigator for Supreme Admin (not exception1''s own owner_user_id, even though Supreme Admin genuinely passes record-scope)';
  exception
    when others then
      if sqlerrm not like 'claim_not_investigator%' then raise; end if;
  end;

  begin
    perform app.record_claim_investigation_finding(v_case1_id, '', 'pending', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected claim_finding_text_required for empty finding_text';
  exception
    when others then
      if sqlerrm not like 'claim_finding_text_required%' then raise; end if;
  end;

  v_finding := app.record_claim_investigation_finding(v_case1_id, 'Custody log confirms cartons were intact at pickup and crushed by the time of the transfer-yard handoff -- carrier-side handling damage.', 'sufficient', v_supervisor, 'supervisor');
  if v_finding.evidence_sufficiency <> 'sufficient' then
    raise exception 'assertion failed: expected evidence_sufficiency=sufficient';
  end if;
  if (select claim_stage from app.claim_case_extensions where id = v_case1_id) <> 'investigating' then
    raise exception 'assertion failed: expected claim_stage to advance to investigating after the first finding';
  end if;

  -- A real second, append-only finding recording evidence_sufficiency=insufficient
  -- -- a genuinely distinct, real stored value (a request-for-more-evidence-like
  -- signal, see migration header design note 6b), never fabricated/only-ever-tested
  -- as 'sufficient'.
  v_second_finding := app.record_claim_investigation_finding(v_case1_id, 'Follow-up: carrier''s own manifest photos are lower resolution than expected -- requested higher-resolution originals before finalizing.', 'insufficient', v_supervisor, 'supervisor');
  if v_second_finding.evidence_sufficiency <> 'insufficient' or v_second_finding.id = v_finding.id then
    raise exception 'assertion failed: expected a genuinely SECOND, distinct finding row with evidence_sufficiency=insufficient';
  end if;
  if (select count(*) from app.claim_investigation_findings where claim_case_id = v_case1_id) <> 2 then
    raise exception 'assertion failed: expected exactly 2 append-only findings on case1';
  end if;
end $$;

\echo '>> app.propose_claim_responsibility / app.decide_claim_responsibility on case1: p_expected_version rejects a non-null value on a case with no current review yet, and a stale value on a re-propose (the live-reproduced lost-update fix); supervisor proposes (carrier, reserve 2,000,000 IDR); re-proposing while still proposed updates the SAME row in place; rep (lacks OPS:Override entirely) is rejected insufficient_authority; supervisor attempting to decide their OWN proposal is rejected self_approval_not_allowed (live-reproduced); Supreme Admin (a genuinely different, real decider -- ratified absolute authority per AGENTS.md) decides APPROVED; stale_version on a stale re-decide attempt'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case1_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'damage');
  v_supervisor uuid := '00000000-0000-0000-0000-000000990002';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_rep uuid := '00000000-0000-0000-0000-000000990005';
  v_review app.claim_responsibility_reviews;
  v_review_id uuid;
  v_reproposed app.claim_responsibility_reviews;
  v_decided app.claim_responsibility_reviews;
begin
  -- p_expected_version must be null when no current review exists yet.
  begin
    perform app.propose_claim_responsibility(v_case1_id, 'carrier', 1500000, 'IDR', 'wrong expected_version on first-ever proposal', 1, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected stale_version supplying a non-null expected_version when no current review exists yet';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_review := app.propose_claim_responsibility(v_case1_id, 'carrier', 1500000, 'IDR', 'Initial read: custody log points at carrier-side handling', null, v_supervisor, 'supervisor');
  v_review_id := v_review.id;
  if v_review.status <> 'proposed' or v_review.version_number <> 1 then
    raise exception 'assertion failed: expected a fresh version-1 proposed review';
  end if;
  if (select claim_stage from app.claim_case_extensions where id = v_case1_id) <> 'pending_decision' then
    raise exception 'assertion failed: expected claim_stage to advance to pending_decision after the first proposal';
  end if;

  -- The live-reproduced lost-update fix: re-proposing with a STALE expected_version
  -- is rejected rather than silently clobbering the row (see migration header
  -- design note 5). A concurrent second actor who read the same version-1 row
  -- would hit this exact rejection instead of silently destroying v_review's own
  -- content.
  begin
    perform app.propose_claim_responsibility(v_case1_id, 'carrier', 9999999, 'IDR', 'a concurrent racing proposal that must NOT silently win', v_review.record_version + 1, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected stale_version re-proposing with a wrong expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  if (select proposed_reserve_amount from app.claim_responsibility_reviews where id = v_review_id) <> 1500000 then
    raise exception 'assertion failed: a rejected stale re-propose must never touch the existing row''s own content';
  end if;

  -- Re-proposing while still 'proposed' updates the SAME row (no version churn).
  v_reproposed := app.propose_claim_responsibility(v_case1_id, 'carrier', 2000000, 'IDR', 'Revised reserve after full custody chain review', v_review.record_version, v_supervisor, 'supervisor');
  if v_reproposed.id <> v_review_id or v_reproposed.version_number <> 1 or v_reproposed.proposed_reserve_amount <> 2000000 then
    raise exception 'assertion failed: expected the SAME review row updated in place (id=% version=% reserve=%)', v_reproposed.id, v_reproposed.version_number, v_reproposed.proposed_reserve_amount;
  end if;

  -- A DIFFERENT failure mode from self-approval: rep genuinely lacks OPS:Override
  -- entirely (Create/Edit/View only) -- rejected at the earlier RBAC gate, never
  -- even reaching the self-approval business-rule check.
  begin
    perform app.decide_claim_responsibility(v_review_id, v_reproposed.record_version, 'approved', 'carrier', 2000000, 'IDR', 'rep attempting to decide', v_rep, 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- rep lacks OPS:Override entirely';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.decide_claim_responsibility(v_review_id, v_reproposed.record_version, 'approved', 'carrier', 2000000, 'IDR', 'approving my own proposal', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected self_approval_not_allowed -- supervisor proposed this review and attempted to also decide it';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  begin
    perform app.decide_claim_responsibility(v_review_id, v_reproposed.record_version + 1, 'approved', 'carrier', 2000000, 'IDR', 'stale attempt', v_supreme, 'supreme');
    raise exception 'assertion failed: expected stale_version for a wrong expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_decided := app.decide_claim_responsibility(v_review_id, v_reproposed.record_version, 'approved', 'carrier', 2000000, 'IDR', 'Approved as proposed -- carrier custody chain evidence sufficient', v_supreme, 'supreme');
  if v_decided.status <> 'approved' or v_decided.final_reserve_amount <> 2000000 or v_decided.decided_by_auth_user_id <> v_supreme then
    raise exception 'assertion failed: expected an approved decision with final_reserve_amount=2000000, got status=% amount=%', v_decided.status, v_decided.final_reserve_amount;
  end if;
  if (select claim_stage from app.claim_case_extensions where id = v_case1_id) <> 'decided' then
    raise exception 'assertion failed: expected claim_stage to advance to decided';
  end if;
end $$;

\echo '>> app.evaluate_claim_settlement_readiness on case1: not_ready with a real no_recovery_records_yet blocker (carrier responsibility, positive reserve, zero recovery rows yet); reevaluation_reason required on a second call; app.record_claim_recovery requires the decision to already exist, then a real recovery record advances claim_stage to recovering and a correction row references it; a re-evaluation is then ready'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case1_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'damage');
  v_case2_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'loss');
  v_supervisor uuid := '00000000-0000-0000-0000-000000990002';
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_eval1 app.claim_settlement_readiness_evaluations;
  v_eval2 app.claim_settlement_readiness_evaluations;
  v_recovery app.claim_recovery_records;
  v_correction app.claim_recovery_records;
begin
  v_eval1 := app.evaluate_claim_settlement_readiness(v_case1_id, null, v_supervisor, 'supervisor');
  if v_eval1.evaluated_status <> 'not_ready' then
    raise exception 'assertion failed: expected not_ready before any recovery record exists, got %', v_eval1.evaluated_status;
  end if;
  if not exists (select 1 from jsonb_array_elements(v_eval1.blockers) b where b ->> 'code' = 'no_recovery_records_yet') then
    raise exception 'assertion failed: expected a real no_recovery_records_yet blocker, got %', v_eval1.blockers;
  end if;

  begin
    perform app.evaluate_claim_settlement_readiness(v_case1_id, null, v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected claim_settlement_reevaluation_reason_required on a second evaluation with no reason';
  exception
    when others then
      if sqlerrm not like 'claim_settlement_reevaluation_reason_required%' then raise; end if;
  end;

  -- Targets case2 (loss, Shipment B, owned by investigator) -- already opened
  -- (see the link_claim_evidence section above) but not yet proposed/decided at
  -- this point in the file, the real precondition this negative test needs.
  begin
    perform app.record_claim_recovery(v_case2_id, 'carrier', 1, 'IDR', null, null, null, v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_recovery_requires_decision for a case with no responsibility decision yet';
  exception
    when others then
      if sqlerrm not like 'claim_recovery_requires_decision%' then raise; end if;
  end;

  v_recovery := app.record_claim_recovery(v_case1_id, 'carrier', 1800000, 'IDR', now(), 'CARRIER-REMIT-CLAIM-1', null, v_supervisor, 'supervisor');
  if v_recovery.recovered_amount <> 1800000 or v_recovery.corrects_recovery_id is not null then
    raise exception 'assertion failed: expected a fresh, non-correcting recovery record';
  end if;
  if (select claim_stage from app.claim_case_extensions where id = v_case1_id) <> 'recovering' then
    raise exception 'assertion failed: expected claim_stage to advance to recovering after the first recovery record';
  end if;

  -- A correction is a NEW append-only row, never an edit of the original.
  v_correction := app.record_claim_recovery(v_case1_id, 'carrier', 2000000, 'IDR', now(), 'CARRIER-REMIT-CLAIM-1-CORRECTED', v_recovery.id, v_supervisor, 'supervisor');
  if v_correction.corrects_recovery_id <> v_recovery.id then
    raise exception 'assertion failed: expected the correction to reference the original via corrects_recovery_id';
  end if;
  if (select recovered_amount from app.claim_recovery_records where id = v_recovery.id) <> 1800000 then
    raise exception 'assertion failed: a correction must never rewrite the original recovery record''s own amount';
  end if;

  v_eval2 := app.evaluate_claim_settlement_readiness(v_case1_id, 'recovery now recorded', v_supervisor, 'supervisor');
  if v_eval2.evaluated_status <> 'ready' or jsonb_array_length(v_eval2.blockers) <> 0 then
    raise exception 'assertion failed: expected ready with zero blockers once a recovery record exists, got status=% blockers=%', v_eval2.evaluated_status, v_eval2.blockers;
  end if;
  if v_eval2.supersedes_evaluation_id <> v_eval1.id or v_eval2.version_number <> v_eval1.version_number + 1 then
    raise exception 'assertion failed: expected the new evaluation to supersede the prior one';
  end if;
end $$;

\echo '>> app.handoff_claim_settlement_readiness on case1: idempotent on (tenant, case, idempotency_key); app.record_claim_finance_reconciliation_outcome records a reconciled outcome; app.close_claim_case succeeds via the finance_reconciled path and drives the underlying operational_exception through its own real resolve/close RPCs; app.reopen_claim_case then requires a reason and preserves closure history'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case1_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'damage');
  v_exception1_id uuid := (select id from app.operational_exceptions where tenant_id = v_tenant1 and type = 'damage');
  v_supervisor uuid := '00000000-0000-0000-0000-000000990002';
  v_financeworker uuid := '00000000-0000-0000-0000-000000990008';
  v_handoff1 app.claim_settlement_readiness_handoffs;
  v_handoff2 app.claim_settlement_readiness_handoffs;
  v_reconciled app.claim_settlement_readiness_handoffs;
  v_closed app.claim_case_extensions;
  v_case_before_close app.claim_case_extensions;
  v_exception_before_close app.operational_exceptions;
  v_reopened app.claim_case_extensions;
begin
  select * into v_case_before_close from app.claim_case_extensions where id = v_case1_id;
  select * into v_exception_before_close from app.operational_exceptions where id = v_exception1_id;

  v_handoff1 := app.handoff_claim_settlement_readiness(v_case1_id, 'idem-claim1-handoff-1', v_supervisor, 'supervisor');
  v_handoff2 := app.handoff_claim_settlement_readiness(v_case1_id, 'idem-claim1-handoff-1', v_supervisor, 'supervisor');
  if v_handoff2.id <> v_handoff1.id then
    raise exception 'assertion failed: expected the repeated handoff call (same idempotency_key) to return the SAME handoff row';
  end if;
  if (select claim_stage from app.claim_case_extensions where id = v_case1_id) <> 'finance_handoff' then
    raise exception 'assertion failed: expected claim_stage to advance to finance_handoff';
  end if;

  -- service_role-only Finance-worker callback (no authenticated grant at all --
  -- proven separately in the schema-privilege section below). Any real actor id
  -- may be passed as the audit actor; the RPC itself gates only on p_status/p_note.
  v_reconciled := app.record_claim_finance_reconciliation_outcome(v_handoff1.id, 'reconciled', 'Finance confirms carrier remittance received and matched', v_financeworker, 'finance-worker');
  if v_reconciled.reconciliation_status <> 'reconciled' then
    raise exception 'assertion failed: expected reconciliation_status=reconciled';
  end if;

  begin
    perform app.close_claim_case(v_case1_id, v_case_before_close.record_version - 1, v_exception_before_close.record_version, 'stale close attempt', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected stale_version for a wrong expected_version on close';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_closed := app.close_claim_case(v_case1_id, (select record_version from app.claim_case_extensions where id = v_case1_id), (select record_version from app.operational_exceptions where id = v_exception1_id), 'Claim reconciled with Finance -- carrier remittance received', v_supervisor, 'supervisor');
  if v_closed.claim_stage <> 'closed' or v_closed.closure_basis <> 'finance_reconciled' then
    raise exception 'assertion failed: expected claim_stage=closed closure_basis=finance_reconciled, got % / %', v_closed.claim_stage, v_closed.closure_basis;
  end if;
  if (select status from app.operational_exceptions where id = v_exception1_id) <> 'closed' then
    raise exception 'assertion failed: expected the underlying operational_exception to be driven to closed for real (via its own resolve_exception/close_exception RPCs)';
  end if;

  -- A closed case rejects further mutation (deferred from the add_claim_item section).
  begin
    perform app.add_claim_item(v_case1_id, 'cargo_general', null, null, null, 1, 'PCS', null, null, 'attempted after close', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected claim_case_closed adding an item to a closed case';
  exception
    when others then
      if sqlerrm not like 'claim_case_closed%' then raise; end if;
  end;

  begin
    perform app.reopen_claim_case(v_case1_id, v_closed.record_version, (select record_version from app.operational_exceptions where id = v_exception1_id), '', v_supervisor, 'supervisor');
    raise exception 'assertion failed: expected reason_required for an empty reopen reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  v_reopened := app.reopen_claim_case(v_case1_id, v_closed.record_version, (select record_version from app.operational_exceptions where id = v_exception1_id), 'Carrier disputes the remittance amount -- reopening for renegotiation', v_supervisor, 'supervisor');
  if v_reopened.claim_stage <> 'investigating' then
    raise exception 'assertion failed: expected claim_stage=investigating after reopen, got %', v_reopened.claim_stage;
  end if;
  -- Full history preserved -- closure_note/closure_basis/closed_at/closed_by are
  -- NEVER cleared by a reopen (this migration''s own explicit design).
  if v_reopened.closure_basis is distinct from 'finance_reconciled' or v_reopened.closure_note is null or v_reopened.closed_at is null or v_reopened.closed_by is null then
    raise exception 'assertion failed: expected the prior closure_basis/closure_note/closed_at/closed_by to remain populated as history after reopen';
  end if;
  if v_reopened.reopen_reason is null or v_reopened.reopened_by is null or v_reopened.reopened_at is null then
    raise exception 'assertion failed: expected reopen_reason/reopened_by/reopened_at to be recorded';
  end if;
  if (select status from app.operational_exceptions where id = v_exception1_id) <> 'reopened' then
    raise exception 'assertion failed: expected the underlying operational_exception to be driven to reopened for real (via app.reopen_exception)';
  end if;
end $$;

\echo '>> case2 (loss, Shipment B): item evidence linked to a real inventory_movement (receiving-discrepancy/shortage adjustment) and a real wms_outbound_shipment (package evidence), BOTH genuinely owned by Account Beta (Shipment B''s own customer); a DIFFERENT customer''s own wms_outbound_shipment (Account Alpha''s, built for Shipment A) is REJECTED claim_evidence_scope_mismatch on both app.link_claim_evidence and app.add_claim_item (live-closes the same-tenant/cross-customer gap -- see migration header design note 3); the unscanned file is rejected claim_evidence_file_unsafe; propose internal/decide DENIED; settlement readiness is not_ready (no_finalized_reserve); handoff is rejected claim_settlement_not_ready; closure succeeds directly via the no_handoff_required path'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case2_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'loss');
  v_exception2_id uuid := (select id from app.operational_exceptions where tenant_id = v_tenant1 and type = 'loss');
  v_movement_id uuid := (select id from app.inventory_movements where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-adj-1b');
  v_wms_shipment_id uuid := (select id from app.wms_outbound_shipments where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-wms-shipment-1b');
  -- Account Alpha's own wms_outbound_shipment (built for Shipment A, a DIFFERENT
  -- customer than case2/Shipment B's own Account Beta) -- the cross-customer
  -- negative-test fixture.
  v_other_account_wms_shipment_id uuid := (select id from app.wms_outbound_shipments where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-wms-shipment-1');
  v_pending_file_id uuid := (select id from app.files where tenant_id = v_tenant1 and idempotency_key = 'idem-claim-shipB-pending');
  v_item1b_master_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CLAIM-1B');
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_item app.claim_items;
  v_review app.claim_responsibility_reviews;
  v_decided app.claim_responsibility_reviews;
  v_eval app.claim_settlement_readiness_evaluations;
  v_closed app.claim_case_extensions;
begin
  begin
    perform app.link_claim_evidence(v_case2_id, 'wms_outbound_shipment', v_other_account_wms_shipment_id, 'wrong-customer attempt', v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_evidence_scope_mismatch linking Account Alpha''s own wms_outbound_shipment onto case2 (Account Beta''s own case)';
  exception
    when others then
      if sqlerrm not like 'claim_evidence_scope_mismatch%' then raise; end if;
  end;
  begin
    perform app.add_claim_item(v_case2_id, 'package', null, v_other_account_wms_shipment_id, null, 1, 'PCS', null, null, 'wrong-customer attempt', v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_evidence_scope_mismatch adding an item linked to Account Alpha''s own wms_outbound_shipment on case2 (Account Beta''s own case)';
  exception
    when others then
      if sqlerrm not like 'claim_evidence_scope_mismatch%' then raise; end if;
  end;
  if exists (select 1 from app.claim_evidence_links where claim_case_id = v_case2_id and evidence_id = v_other_account_wms_shipment_id) then
    raise exception 'assertion failed: a rejected cross-customer evidence link must never be persisted';
  end if;

  perform app.add_claim_item(v_case2_id, 'inventory', v_movement_id, null, null, 5, 'PCS', 250000, 'IDR', '5 units found damaged during count (receiving discrepancy/shortage)', v_investigator, 'investigator');
  v_item := app.add_claim_item(v_case2_id, 'package', null, v_wms_shipment_id, v_item1b_master_id, 10, 'PCS', 500000, 'IDR', 'entire outbound package reported missing', v_investigator, 'investigator');

  perform app.link_claim_evidence(v_case2_id, 'inventory_movement', v_movement_id, 'stock count adjustment evidencing the discrepancy', v_investigator, 'investigator');
  perform app.link_claim_evidence(v_case2_id, 'wms_outbound_shipment', v_wms_shipment_id, 'the package never arrived', v_investigator, 'investigator');

  begin
    perform app.link_claim_evidence(v_case2_id, 'file', v_pending_file_id, 'attempted before scan completed', v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_evidence_file_unsafe for a file whose malware_scan_status is still pending';
  exception
    when others then
      if sqlerrm not like 'claim_evidence_file_unsafe%' then raise; end if;
  end;

  -- Proposed WITH a real, non-null reserve (later denied) -- exercised so the
  -- field-masking section below has a genuine proposedReserveAmount to mask.
  v_review := app.propose_claim_responsibility(v_case2_id, 'internal', 300000, 'IDR', 'Investigation could not substantiate carrier/vendor fault -- likely a documentation error, not a real loss', null, v_investigator, 'investigator');
  -- Decided by Supreme Admin -- investigator (the proposer) lacks OPS:Override
  -- entirely, so a real decision here requires a genuinely different, real-
  -- authority actor; Supreme Admin is not the proposer either way.
  v_decided := app.decide_claim_responsibility(v_review.id, v_review.record_version, 'denied', null, null, null, 'Denied: package located in a misrouted bin during a follow-up count -- no real loss occurred', v_supreme, 'supreme');
  if v_decided.status <> 'denied' or v_decided.final_responsibility_party is not null or v_decided.final_reserve_amount is not null then
    raise exception 'assertion failed: expected a denied decision with no final party/amount, got status=% party=% amount=%', v_decided.status, v_decided.final_responsibility_party, v_decided.final_reserve_amount;
  end if;

  v_eval := app.evaluate_claim_settlement_readiness(v_case2_id, null, v_investigator, 'investigator');
  if v_eval.evaluated_status <> 'not_ready' or not exists (select 1 from jsonb_array_elements(v_eval.blockers) b where b ->> 'code' = 'no_finalized_reserve') then
    raise exception 'assertion failed: expected not_ready with a no_finalized_reserve blocker for a denied decision, got status=% blockers=%', v_eval.evaluated_status, v_eval.blockers;
  end if;

  begin
    perform app.handoff_claim_settlement_readiness(v_case2_id, 'idem-claim2-handoff-attempt', v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_settlement_not_ready for a denied-decision case';
  exception
    when others then
      if sqlerrm not like 'claim_settlement_not_ready%' then raise; end if;
  end;

  -- Closure succeeds directly -- no Finance handoff needed for a denied claim.
  -- Closed by Supreme Admin -- investigator lacks OPS:Close.
  v_closed := app.close_claim_case(v_case2_id, (select record_version from app.claim_case_extensions where id = v_case2_id), (select record_version from app.operational_exceptions where id = v_exception2_id), 'Denied and closed -- package located, no real loss', v_supreme, 'supreme');
  if v_closed.claim_stage <> 'closed' or v_closed.closure_basis <> 'no_handoff_required' then
    raise exception 'assertion failed: expected closure_basis=no_handoff_required for a denied claim with zero handoffs, got %', v_closed.closure_basis;
  end if;
end $$;

\echo '>> case3 (delay, Shipment B): proves delay is claim-eligible; app.evaluate_claim_settlement_readiness on a freshly opened case exercises BOTH no_claim_items and no_approved_responsibility_decision blockers together; a POSITIVE proposed reserve with zero items/evidence on file is rejected claim_evidence_required (Prompt 244 §23 "missing custody/quantity evidence" block); a genuinely ZERO reserve needs no evidence; amending to a POSITIVE final_reserve_amount is ALSO rejected claim_evidence_required (closes the propose-zero-then-amend bypass); decide APPROVED with a ZERO final_reserve_amount (distinct from a denied decision) also qualifies for the no_handoff_required closure path'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_exception3_id uuid := (select id from app.operational_exceptions where tenant_id = v_tenant1 and type = 'delay');
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_case3 app.claim_case_extensions;
  v_early_eval app.claim_settlement_readiness_evaluations;
  v_review app.claim_responsibility_reviews;
  v_reproposed app.claim_responsibility_reviews;
  v_decided app.claim_responsibility_reviews;
  v_closed app.claim_case_extensions;
begin
  v_case3 := app.open_claim_case(v_exception3_id, 'internal', null, null, null, v_investigator, 'investigator');

  -- Evaluated immediately after opening -- zero claim_items AND zero current
  -- responsibility review exist yet, so BOTH blockers fire together (neither is
  -- exercised anywhere else in this file).
  v_early_eval := app.evaluate_claim_settlement_readiness(v_case3.id, null, v_investigator, 'investigator');
  if v_early_eval.evaluated_status <> 'not_ready'
    or not exists (select 1 from jsonb_array_elements(v_early_eval.blockers) b where b ->> 'code' = 'no_claim_items')
    or not exists (select 1 from jsonb_array_elements(v_early_eval.blockers) b where b ->> 'code' = 'no_approved_responsibility_decision')
  then
    raise exception 'assertion failed: expected both no_claim_items and no_approved_responsibility_decision blockers on a freshly opened case, got %', v_early_eval.blockers;
  end if;

  -- No claim_items/claim_evidence_links exist yet for case3 -- a POSITIVE proposed
  -- reserve is rejected (Prompt 244 §23 "missing custody/quantity evidence" block;
  -- see migration header design note 5).
  begin
    perform app.propose_claim_responsibility(v_case3.id, 'internal', 500000, 'IDR', 'attempted positive reserve with no evidence on file', null, v_investigator, 'investigator');
    raise exception 'assertion failed: expected claim_evidence_required proposing a positive reserve with zero items/evidence on file';
  exception
    when others then
      if sqlerrm not like 'claim_evidence_required%' then raise; end if;
  end;

  -- A genuinely zero reserve needs no evidence -- a real, principled carve-out (see
  -- migration header): "no compensable loss expected" for a delay resolved with no
  -- quantifiable impact.
  v_review := app.propose_claim_responsibility(v_case3.id, 'internal', 0, 'IDR', 'Customs delay was outside anyone''s control -- no compensable loss expected', null, v_investigator, 'investigator');

  -- Re-proposing with a STALE expected_version is rejected too (not just the
  -- decide-time check) -- the live-reproduced lost-update fix.
  begin
    perform app.propose_claim_responsibility(v_case3.id, 'internal', 0, 'IDR', 'stale re-propose attempt', v_review.record_version + 1, v_investigator, 'investigator');
    raise exception 'assertion failed: expected stale_version re-proposing with a wrong expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_reproposed := app.propose_claim_responsibility(v_case3.id, 'internal', 0, 'IDR', 'Customs delay confirmed -- no compensable loss expected', v_review.record_version, v_investigator, 'investigator');
  if v_reproposed.id <> v_review.id or v_reproposed.proposed_rationale <> 'Customs delay confirmed -- no compensable loss expected' then
    raise exception 'assertion failed: expected the SAME review row updated in place with the correct expected_version';
  end if;

  -- Amending to a POSITIVE final_reserve_amount is ALSO rejected while zero
  -- items/evidence exist on file -- the decide-time half of the same gate, closing
  -- the "propose zero, then amend to a real number" bypass a propose-only gate
  -- would leave open.
  begin
    perform app.decide_claim_responsibility(v_reproposed.id, v_reproposed.record_version, 'amended', 'internal', 750000, 'IDR', 'attempted amend to a positive reserve with no evidence', v_supreme, 'supreme');
    raise exception 'assertion failed: expected claim_evidence_required amending to a positive final reserve with zero items/evidence on file';
  exception
    when others then
      if sqlerrm not like 'claim_evidence_required%' then raise; end if;
  end;

  v_decided := app.decide_claim_responsibility(v_reproposed.id, v_reproposed.record_version, 'approved', 'internal', 0, 'IDR', 'Approved with a zero reserve -- delay confirmed but caused no quantifiable loss', v_supreme, 'supreme');
  if v_decided.status <> 'approved' or v_decided.final_reserve_amount <> 0 then
    raise exception 'assertion failed: expected an approved decision with a real zero final_reserve_amount, got status=% amount=%', v_decided.status, v_decided.final_reserve_amount;
  end if;

  -- Closed by Supreme Admin -- investigator lacks OPS:Close.
  v_closed := app.close_claim_case(v_case3.id, (select record_version from app.claim_case_extensions where id = v_case3.id), (select record_version from app.operational_exceptions where id = v_exception3_id), 'Approved at zero reserve -- closed with no Finance handoff needed', v_supreme, 'supreme');
  if v_closed.closure_basis <> 'no_handoff_required' then
    raise exception 'assertion failed: expected closure_basis=no_handoff_required for a zero-reserve approved decision, got %', v_closed.closure_basis;
  end if;
end $$;

\echo '>> case4 (incident, Shipment B) -- Finance rejection then reconciliation path: approved decision with a real nonzero internal reserve (no recovery-record blocker, since final_responsibility_party=internal); first handoff is REJECTED by Finance; idempotent-same-outcome replay; a conflicting second outcome on the SAME handoff is rejected reconciliation_outcome_conflict; close is rejected claim_case_not_reconciled while only a rejected handoff exists; a SECOND handoff (fresh idempotency_key) is reconciled and closure then succeeds; also seeds a real item and a real (insurance) recovery record, reused by the field-masking section below'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_exception5_id uuid := (select id from app.operational_exceptions where tenant_id = v_tenant1 and type = 'incident');
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_financeworker uuid := '00000000-0000-0000-0000-000000990008';
  v_case4 app.claim_case_extensions;
  v_review app.claim_responsibility_reviews;
  v_decided app.claim_responsibility_reviews;
  v_eval app.claim_settlement_readiness_evaluations;
  v_handoff_a app.claim_settlement_readiness_handoffs;
  v_rejected app.claim_settlement_readiness_handoffs;
  v_rejected_replay app.claim_settlement_readiness_handoffs;
  v_handoff_b app.claim_settlement_readiness_handoffs;
  v_reconciled app.claim_settlement_readiness_handoffs;
  v_recovery app.claim_recovery_records;
  v_closed app.claim_case_extensions;
begin
  v_case4 := app.open_claim_case(v_exception5_id, 'vendor', null, 'Vendor X Packaging Supplies', null, v_investigator, 'investigator');
  perform app.add_claim_item(v_case4.id, 'cargo_general', null, null, null, 1, 'PCS', 500000, 'IDR', 'minor handling incident during transfer, packaging replaced', v_investigator, 'investigator');
  v_review := app.propose_claim_responsibility(v_case4.id, 'internal', 500000, 'IDR', 'Internal handling error during transfer -- no third party involved, no recovery expected', null, v_investigator, 'investigator');
  -- Decided by Supreme Admin -- investigator (the proposer) lacks OPS:Override.
  v_decided := app.decide_claim_responsibility(v_review.id, v_review.record_version, 'approved', 'internal', 500000, 'IDR', 'Approved: internal handling fault, reserve booked internally', v_supreme, 'supreme');

  v_eval := app.evaluate_claim_settlement_readiness(v_case4.id, null, v_investigator, 'investigator');
  if v_eval.evaluated_status <> 'ready' then
    raise exception 'assertion failed: expected ready (internal responsibility never requires a recovery record), got status=% blockers=%', v_eval.evaluated_status, v_eval.blockers;
  end if;

  -- A real recovery record -- company cargo insurance still pays out even for an
  -- internal-fault incident; seeded here purely as real masking-test data below.
  v_recovery := app.record_claim_recovery(v_case4.id, 'insurance', 400000, 'IDR', now(), 'CARGO-INSURANCE-CLAIM4', null, v_investigator, 'investigator');

  v_handoff_a := app.handoff_claim_settlement_readiness(v_case4.id, 'idem-claim4-handoff-a', v_investigator, 'investigator');
  v_rejected := app.record_claim_finance_reconciliation_outcome(v_handoff_a.id, 'rejected', 'Finance: reserve account code missing, cannot post', v_financeworker, 'finance-worker');
  if v_rejected.reconciliation_status <> 'rejected' then
    raise exception 'assertion failed: expected reconciliation_status=rejected';
  end if;

  -- Idempotent same-outcome replay.
  v_rejected_replay := app.record_claim_finance_reconciliation_outcome(v_handoff_a.id, 'rejected', 'Finance: reserve account code missing, cannot post', v_financeworker, 'finance-worker');
  if v_rejected_replay.id <> v_rejected.id or v_rejected_replay.reconciled_at <> v_rejected.reconciled_at then
    raise exception 'assertion failed: expected a same-outcome replay to return the identical, unchanged row';
  end if;

  begin
    perform app.record_claim_finance_reconciliation_outcome(v_handoff_a.id, 'reconciled', 'attempted flip after rejection', v_financeworker, 'finance-worker');
    raise exception 'assertion failed: expected reconciliation_outcome_conflict changing an already-rejected handoff to reconciled';
  exception
    when others then
      if sqlerrm not like 'reconciliation_outcome_conflict%' then raise; end if;
  end;

  -- Closed by Supreme Admin -- investigator lacks OPS:Close.
  begin
    perform app.close_claim_case(v_case4.id, (select record_version from app.claim_case_extensions where id = v_case4.id), (select record_version from app.operational_exceptions where id = v_exception5_id), 'attempted close after Finance rejection', v_supreme, 'supreme');
    raise exception 'assertion failed: expected claim_case_not_reconciled while only a rejected handoff exists and the decision carries a nonzero internal reserve';
  exception
    when others then
      if sqlerrm not like 'claim_case_not_reconciled%' then raise; end if;
  end;

  -- A fresh handoff attempt (new idempotency_key) against the SAME current
  -- evaluation succeeds, and this time Finance reconciles it.
  v_handoff_b := app.handoff_claim_settlement_readiness(v_case4.id, 'idem-claim4-handoff-b', v_investigator, 'investigator');
  if v_handoff_b.id = v_handoff_a.id then
    raise exception 'assertion failed: expected a genuinely new handoff row for a new idempotency_key';
  end if;
  v_reconciled := app.record_claim_finance_reconciliation_outcome(v_handoff_b.id, 'reconciled', 'Finance: reserve account code corrected, posted', v_financeworker, 'finance-worker');
  if v_reconciled.reconciliation_status <> 'reconciled' then
    raise exception 'assertion failed: expected the second handoff to be reconciled';
  end if;

  -- Closure now succeeds -- the MOST RECENT handoff (handoff_b) is reconciled,
  -- even though an earlier one (handoff_a) was rejected. Closed by Supreme Admin
  -- -- investigator lacks OPS:Close.
  v_closed := app.close_claim_case(v_case4.id, (select record_version from app.claim_case_extensions where id = v_case4.id), (select record_version from app.operational_exceptions where id = v_exception5_id), 'Closed -- reconciled on the second handoff attempt', v_supreme, 'supreme');
  if v_closed.claim_stage <> 'closed' or v_closed.closure_basis <> 'finance_reconciled' then
    raise exception 'assertion failed: expected closure via finance_reconciled once the LATEST handoff is reconciled, got %', v_closed.closure_basis;
  end if;
end $$;

\echo '>> cross-tenant isolation: tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority on every RPC against tenant1''s real claim records, and raw RLS denies a direct select'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_tenant2_rep uuid := '00000000-0000-0000-0000-000000991002';
  v_case1_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'damage');
  v_exception1_id uuid := (select id from app.operational_exceptions where tenant_id = v_tenant1 and type = 'damage');
begin
  begin
    perform app.get_claim_case(v_case1_id, v_tenant2_rep);
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor reading a tenant1 claim case';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.open_claim_case(v_exception1_id, 'internal', null, null, null, v_tenant2_rep, 'rep2');
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor opening a claim case against a tenant1 exception';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.add_claim_item(v_case1_id, 'cargo_general', null, null, null, 1, 'PCS', null, null, 'cross-tenant attempt', v_tenant2_rep, 'rep2');
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor adding an item to a tenant1 claim case';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.get_claim_settlement_readiness(v_case1_id, v_tenant2_rep);
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor reading a tenant1 claim case''s settlement readiness';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.list_claim_settlement_readiness_handoffs(v_case1_id, v_tenant2_rep);
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor listing a tenant1 claim case''s settlement readiness handoffs';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000991002", "role": "authenticated"}', true);
  if exists (select 1 from app.claim_case_extensions where id = v_case1_id) then
    raise exception 'assertion failed: raw RLS leak -- tenant2 rep directly selected a tenant1 claim case row';
  end if;
  reset role;
end $$;

\echo '>> bounded/cursor reads: app.list_claim_cases p_limit clamps and cursor-paginates (updated_at, id) across every case with no gap/duplicate; app.list_claim_items/app.list_claim_evidence/app.list_claim_recovery_records p_limit clamps'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_supervisor uuid := '00000000-0000-0000-0000-000000990002';
  -- list_claim_cases filters per-row by record-scope -- only Supreme Admin sees
  -- EVERY case across both Shipment A (supervisor) and Shipment B (investigator).
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_case1_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'damage');
  v_total_cases integer;
  v_rows app.claim_case_extensions[];
  v_page record;
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_seen_ids uuid[] := '{}';
  v_page_count integer;
  v_items app.claim_items[];
  v_evidence app.claim_evidence_links[];
  v_recoveries app.claim_recovery_records[];
begin
  select count(*) into v_total_cases from app.claim_case_extensions where tenant_id = v_tenant1;
  if v_total_cases < 4 then
    raise exception 'assertion failed: expected at least 4 claim cases for tenant1, got %', v_total_cases;
  end if;

  loop
    v_page_count := 0;
    for v_page in
      select * from app.list_claim_cases(v_tenant1, v_supreme, null, null, null, null, null, v_cursor_updated_at, v_cursor_id, 1)
    loop
      v_page_count := v_page_count + 1;
      if v_page.id = any(v_seen_ids) then
        raise exception 'assertion failed: cursor pagination revisited case %', v_page.id;
      end if;
      v_seen_ids := v_seen_ids || v_page.id;
      v_cursor_updated_at := v_page.updated_at;
      v_cursor_id := v_page.id;
    end loop;
    exit when v_page_count = 0;
    if v_page_count <> 1 then
      raise exception 'assertion failed: expected p_limit=1 to return exactly one row per page, got %', v_page_count;
    end if;
  end loop;

  if array_length(v_seen_ids, 1) <> v_total_cases then
    raise exception 'assertion failed: expected cursor pagination to walk exactly % cases, saw %', v_total_cases, array_length(v_seen_ids, 1);
  end if;

  begin
    perform app.list_claim_cases(v_tenant1, v_supreme, null, null, null, null, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor when p_cursor_id is supplied without p_cursor_updated_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;

  select array_agg(i) into v_items from app.list_claim_items(v_case1_id, v_supervisor, 1) i;
  if array_length(v_items, 1) <> 1 then
    raise exception 'assertion failed: expected p_limit=1 to return exactly 1 claim item, got %', array_length(v_items, 1);
  end if;

  select array_agg(e) into v_evidence from app.list_claim_evidence(v_case1_id, v_supervisor, 1) e;
  if array_length(v_evidence, 1) <> 1 then
    raise exception 'assertion failed: expected p_limit=1 to return exactly 1 evidence link, got %', array_length(v_evidence, 1);
  end if;

  select array_agg(r) into v_recoveries from app.list_claim_recovery_records(v_case1_id, v_supervisor, 500) r;
  if array_length(v_recoveries, 1) <> 2 then
    raise exception 'assertion failed: expected exactly 2 recovery records (original + correction) on case1, got %', array_length(v_recoveries, 1);
  end if;
end $$;

\echo '>> field masking on case4: investigator (OPS:View, no OPS:View cost -- and genuinely record-scope-eligible, since investigator owns Shipment B) sees nulled declared_value/currency on claim items, nulled reserve/currency/rationale/notes on the responsibility review, and nulled recovered_amount/currency on recovery records; Supreme Admin (bypasses both record-scope AND cost-masking) sees the real values'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case4_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'incident');
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_masked_item app.claim_items;
  v_real_item app.claim_items;
  v_masked_review app.claim_responsibility_reviews;
  v_real_review app.claim_responsibility_reviews;
  v_masked_recoveries app.claim_recovery_records[];
  v_real_recoveries app.claim_recovery_records[];
begin
  select * into v_masked_item from app.list_claim_items(v_case4_id, v_investigator, 50) limit 1;
  if v_masked_item.declared_value is not null or v_masked_item.currency is not null then
    raise exception 'assertion failed: expected declared_value/currency to be masked (null) for investigator lacking OPS:View cost';
  end if;
  select * into v_real_item from app.list_claim_items(v_case4_id, v_supreme, 50) limit 1;
  if v_real_item.declared_value is null then
    raise exception 'assertion failed: expected Supreme Admin to see the real declared_value';
  end if;

  v_masked_review := app.get_claim_responsibility_review(v_case4_id, v_investigator);
  if v_masked_review.final_reserve_amount is not null or v_masked_review.proposed_reserve_amount is not null or v_masked_review.decision_notes is not null then
    raise exception 'assertion failed: expected reserve amounts/decision_notes to be masked for investigator lacking OPS:View cost';
  end if;
  if v_masked_review.final_responsibility_party is null then
    raise exception 'assertion failed: expected final_responsibility_party (a non-financial field) to remain visible even when masked';
  end if;
  v_real_review := app.get_claim_responsibility_review(v_case4_id, v_supreme);
  if v_real_review.final_reserve_amount is null then
    raise exception 'assertion failed: expected Supreme Admin to see the real final_reserve_amount';
  end if;

  select array_agg(r) into v_masked_recoveries from app.list_claim_recovery_records(v_case4_id, v_investigator, 50) r;
  if v_masked_recoveries[1].recovered_amount is not null then
    raise exception 'assertion failed: expected recovered_amount to be masked for investigator lacking OPS:View cost';
  end if;
  select array_agg(r) into v_real_recoveries from app.list_claim_recovery_records(v_case4_id, v_supreme, 50) r;
  if v_real_recoveries[1].recovered_amount is null then
    raise exception 'assertion failed: expected Supreme Admin to see the real recovered_amount';
  end if;
end $$;

\echo '>> app.get_claim_settlement_readiness / app.list_claim_settlement_readiness_handoffs on case4 (added on adversarial review -- see migration header design note 7): the evaluation''s own evidence->>finalReserveAmount is masked (key absent) for investigator (OPS:View, no OPS:View cost) and real for Supreme Admin, mirroring app.mask_claim_responsibility_review_amounts for the identical dollar figure; non-financial evidence fields (currentReviewStatus, finalResponsibilityParty) remain visible either way; the two real handoffs are returned ordered by handoff_seq desc (most recent -- reconciled -- first)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case4_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'incident');
  v_investigator uuid := '00000000-0000-0000-0000-000000990004';
  v_supreme uuid := '00000000-0000-0000-0000-000000990007';
  v_masked_eval app.claim_settlement_readiness_evaluations;
  v_real_eval app.claim_settlement_readiness_evaluations;
  v_handoffs app.claim_settlement_readiness_handoffs[];
begin
  v_masked_eval := app.get_claim_settlement_readiness(v_case4_id, v_investigator);
  if v_masked_eval.evidence ? 'finalReserveAmount' then
    raise exception 'assertion failed: expected evidence.finalReserveAmount to be masked (key absent) for investigator lacking OPS:View cost, got %', v_masked_eval.evidence;
  end if;
  if v_masked_eval.evidence ->> 'finalResponsibilityParty' is distinct from 'internal' then
    raise exception 'assertion failed: expected the non-financial evidence.finalResponsibilityParty to remain visible even when masked, got %', v_masked_eval.evidence;
  end if;

  v_real_eval := app.get_claim_settlement_readiness(v_case4_id, v_supreme);
  if (v_real_eval.evidence ->> 'finalReserveAmount')::numeric <> 500000 then
    raise exception 'assertion failed: expected Supreme Admin to see the real evidence.finalReserveAmount=500000, got %', v_real_eval.evidence;
  end if;

  -- Deliberately NOT re-ordered client-side -- this is exactly what proves app.
  -- list_claim_settlement_readiness_handoffs' OWN "order by handoff_seq desc" works.
  select array_agg(h) into v_handoffs from app.list_claim_settlement_readiness_handoffs(v_case4_id, v_investigator, 50) h;
  if array_length(v_handoffs, 1) <> 2 then
    raise exception 'assertion failed: expected exactly 2 handoffs on case4 (one rejected, one reconciled), got %', array_length(v_handoffs, 1);
  end if;
  if v_handoffs[1].reconciliation_status <> 'reconciled' or v_handoffs[2].reconciliation_status <> 'rejected' then
    raise exception 'assertion failed: expected the LATEST handoff (by handoff_seq) first -- reconciled, then the earlier rejected one, got % then %', v_handoffs[1].reconciliation_status, v_handoffs[2].reconciliation_status;
  end if;
  if v_handoffs[1].handoff_seq <= v_handoffs[2].handoff_seq then
    raise exception 'assertion failed: expected a strictly increasing handoff_seq across the two real handoffs';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004 regression guard): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; app.record_claim_finance_reconciliation_outcome specifically has no authenticated EXECUTE grant at all'
do $$
declare
  v_has_priv boolean;
begin
  select has_table_privilege('anon', 'app.claim_case_extensions', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.claim_case_extensions'; end if;
  select has_table_privilege('anon', 'app.claim_items', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.claim_items'; end if;
  select has_table_privilege('anon', 'app.claim_responsibility_reviews', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.claim_responsibility_reviews'; end if;
  select has_table_privilege('anon', 'app.claim_settlement_readiness_handoffs', 'SELECT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold SELECT on app.claim_settlement_readiness_handoffs'; end if;

  select has_table_privilege('authenticated', 'app.claim_case_extensions', 'INSERT') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not hold direct INSERT on app.claim_case_extensions'; end if;
  select has_table_privilege('authenticated', 'app.claim_case_extensions', 'UPDATE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not hold direct UPDATE on app.claim_case_extensions'; end if;
  select has_table_privilege('authenticated', 'app.claim_recovery_records', 'DELETE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must not hold direct DELETE on app.claim_recovery_records'; end if;

  select has_function_privilege('anon', 'app.open_claim_case(uuid, text, uuid, text, jsonb, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.open_claim_case'; end if;
  select has_function_privilege('anon', 'app.close_claim_case(uuid, integer, integer, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.close_claim_case'; end if;

  select has_function_privilege('authenticated', 'app.record_claim_finance_reconciliation_outcome(uuid, text, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: authenticated must NOT hold EXECUTE on app.record_claim_finance_reconciliation_outcome (service_role only)'; end if;
  select has_function_privilege('anon', 'app.record_claim_finance_reconciliation_outcome(uuid, text, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must NOT hold EXECUTE on app.record_claim_finance_reconciliation_outcome'; end if;
  select has_function_privilege('service_role', 'app.record_claim_finance_reconciliation_outcome(uuid, text, text, uuid, text)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: service_role SHOULD hold EXECUTE on app.record_claim_finance_reconciliation_outcome'; end if;

  select has_function_privilege('authenticated', 'app.open_claim_case(uuid, text, uuid, text, jsonb, uuid, text)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on app.open_claim_case'; end if;

  -- p_expected_version fix (see migration header design note 5) -- the NEW
  -- 8-parameter signature must actually be the one granted, not a stale 7-param one.
  select has_function_privilege('authenticated', 'app.propose_claim_responsibility(uuid, text, numeric, text, text, integer, uuid, text)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on app.propose_claim_responsibility(..., p_expected_version integer, ...)'; end if;

  -- Added on adversarial review (see migration header design note 7).
  select has_function_privilege('authenticated', 'app.get_claim_settlement_readiness(uuid, uuid)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on app.get_claim_settlement_readiness'; end if;
  select has_function_privilege('anon', 'app.get_claim_settlement_readiness(uuid, uuid)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.get_claim_settlement_readiness'; end if;
  select has_function_privilege('authenticated', 'app.list_claim_settlement_readiness_handoffs(uuid, uuid, integer)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on app.list_claim_settlement_readiness_handoffs'; end if;
  select has_function_privilege('anon', 'app.list_claim_settlement_readiness_handoffs(uuid, uuid, integer)', 'EXECUTE') into v_has_priv;
  if v_has_priv then raise exception 'assertion failed: anon must not hold EXECUTE on app.list_claim_settlement_readiness_handoffs'; end if;

  if not exists (
    select 1 from pg_indexes where schemaname = 'app' and tablename = 'claim_case_extensions' and indexname = 'claim_case_extensions_operational_exception_unique'
  ) then
    raise exception 'assertion failed: expected a real unique index enforcing at most one claim case per operational exception';
  end if;
end $$;

\echo '>> every real lifecycle mutation self-captures a canonical app.audit_logs entry'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'claiminc1');
  v_case1_id uuid := (select cce.id from app.claim_case_extensions cce join app.operational_exceptions oe on oe.id = cce.operational_exception_id where oe.tenant_id = v_tenant1 and oe.type = 'damage');
begin
  if not exists (select 1 from app.audit_logs where action = 'open_claim_case' and resource_id = v_case1_id) then
    raise exception 'assertion failed: expected an open_claim_case audit entry';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'decide_claim_responsibility') then
    raise exception 'assertion failed: expected at least one decide_claim_responsibility audit entry';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'handoff_claim_settlement_readiness') then
    raise exception 'assertion failed: expected at least one handoff_claim_settlement_readiness audit entry';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'record_claim_finance_reconciliation_outcome') then
    raise exception 'assertion failed: expected at least one record_claim_finance_reconciliation_outcome audit entry';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'close_claim_case' and resource_id = v_case1_id) then
    raise exception 'assertion failed: expected a close_claim_case audit entry for case1';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'reopen_claim_case' and resource_id = v_case1_id) then
    raise exception 'assertion failed: expected a reopen_claim_case audit entry for case1';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'link_claim_evidence') then
    raise exception 'assertion failed: expected at least one link_claim_evidence audit entry';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'record_claim_investigation_finding') then
    raise exception 'assertion failed: expected at least one record_claim_investigation_finding audit entry';
  end if;
end $$;

drop function if exists pack_task_fully(uuid, uuid, uuid, numeric, text);
drop procedure if exists pick_fully(uuid, uuid, numeric, uuid, uuid, text);
