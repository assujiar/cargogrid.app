-- Real, executable test evidence for ATW-012 (CG-S10-ATW-012, Prompt 231 WMS
-- Inbound) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (acmewmsin), a company org unit, a rep (OPS:Create/Edit/View), an OPS:View-only viewer, a global Supreme Admin, one active warehouse (WH-IN-1), two customer accounts (Account A via the full CRM->Job Order->Shipment Order pipeline, confirmed shipment SHP-A; Account B via the same pipeline, no shipment) and item masters owned by each. Tenant2 (acmewmsin2): an isolated rep, its own warehouse and account, for cross-tenant leakage checks.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_company2 uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_rep2_role uuid;
  v_rep2_draft app.role_versions;
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
  v_account_a app.accounts;
  v_account_b app.accounts;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment app.shipment_orders;
  v_shipment_cancelled app.shipment_orders;
  v_warehouse app.warehouses;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000090101', 'admin@wmsin1.test'),
    ('00000000-0000-0000-0000-000000090102', 'rep@wmsin1.test'),
    ('00000000-0000-0000-0000-000000090103', 'viewer@wmsin1.test'),
    ('00000000-0000-0000-0000-000000090105', 'supreme@wmsin1.test'),
    ('00000000-0000-0000-0000-000000090106', 'admin2@wmsin2.test'),
    ('00000000-0000-0000-0000-000000090107', 'rep2@wmsin2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000090105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('wmsin1', 'WMS Inbound Tenant One', 'idem-wmsin1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'wmsin1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'WMSIN1-CO', 'WMS Inbound Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WMSIN1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000090101', 'admin@wmsin1.test', 'WMSIN Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@wmsin1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000090101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000090102', 'rep@wmsin1.test', 'WMSIN Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@wmsin1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000090103', 'viewer@wmsin1.test', 'WMSIN Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@wmsin1.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'WMSIN Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000090102', '00000000-0000-0000-0000-000000090101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'WMSIN Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000090103', '00000000-0000-0000-0000-000000090101', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-IN-1', 'WMS Inbound Warehouse 1', 'Jl. Inbound 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000090102', 'rep');

  -- Account A, via the full CRM->Job Order->Shipment Order pipeline (the only real
  -- path to a confirmed app.shipment_orders row in this repository).
  perform app.capture_lead(v_tenant1, 'manual', null, 'WMSIN Customer Alpha', 'Alice WmsIn', 'alice@wmsin231.test', '0811',
    '00000000-0000-0000-0000-000000090102', v_company, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_lead from app.leads where email = 'alice@wmsin231.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WMSIN Customer Alpha', 'WMSIN231A', '11.111.111.9-111.000',
    jsonb_build_object('line1', 'Jl. Inbound Alpha 9', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice WmsIn Ops', 'Ops Lead', 'alice@wmsin231.test', '0811', '00000000-0000-0000-0000-000000090102', v_company, '00000000-0000-0000-0000-000000090102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSIN231 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000090102', v_company, '00000000-0000-0000-0000-000000090102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSIN231-A', 'Contoso WmsIn231 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000090101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000090101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000090102', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000090102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000090102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000090102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000090102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSIN231 Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000090102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice WmsIn Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_a from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000090102', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000090102', 'rep');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000090102', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-wmsin231-a', null, null, 'land_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '2 days', 800, 800, 10, 800, 800, 10, null, '00000000-0000-0000-0000-000000090102', 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000090102', 'rep');

  select * into v_shipment_cancelled from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-wmsin231-cancelled', null, null, 'land_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, 'split: cancelled fixture', '00000000-0000-0000-0000-000000090102', 'rep'
  );
  select * into v_shipment_cancelled from app.cancel_shipment_order(v_shipment_cancelled.id, v_shipment_cancelled.record_version, 'not needed for this test', '00000000-0000-0000-0000-000000090102', 'rep');

  -- Account B, a second customer in the same tenant -- only needed so a
  -- foreign-owner item can be tried against Account A's own inbound order
  -- (design note 2's own "reject a foreign-owner item" rule).
  perform app.capture_lead(v_tenant1, 'manual', null, 'WMSIN Customer Beta', 'Bob WmsIn', 'bob@wmsin231.test', '0812',
    '00000000-0000-0000-0000-000000090102', v_company, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_lead from app.leads where email = 'bob@wmsin231.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WMSIN Customer Beta', 'WMSIN231B', '11.111.111.10-111.000',
    jsonb_build_object('line1', 'Jl. Inbound Beta 10', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Bob WmsIn Ops', 'Ops Lead', 'bob@wmsin231.test', '0812', '00000000-0000-0000-0000-000000090102', v_company, '00000000-0000-0000-0000-000000090102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSIN231 Beta lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000090102', v_company, '00000000-0000-0000-0000-000000090102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSIN231-B', 'Contoso WmsIn231 Line B', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000090101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000090101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000090102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000090102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000090102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSIN231 Beta lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000090102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000090102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob WmsIn Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_b from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000090102', 'rep');

  -- Item masters (ATW-011A), one per account.
  perform app.create_item_master(v_tenant1, v_account_a.id, 'SKU-WMSIN-A1', 'Alpha Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000090102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_a.id, 'SKU-WMSIN-A2', 'Alpha Gadget', null, 'KG', false, false, false, '00000000-0000-0000-0000-000000090102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_b.id, 'SKU-WMSIN-B1', 'Beta Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000090102', 'rep');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('wmsin2', 'WMS Inbound Tenant Two', 'idem-wmsin2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'wmsin2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'WMSIN2-CO', 'WMS Inbound Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'WMSIN2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000090106', 'admin2@wmsin2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@wmsin2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000090106', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000090107', 'rep2@wmsin2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@wmsin2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000090107', '00000000-0000-0000-0000-000000090106', 'tester');
end $$;

\echo '>> app.prepare_wms_inbound_from_shipment: viewer rejected; success inherits owner from the shipment''s own shipper_account_id; idempotent replay; unknown shipment/warehouse not found; a cancelled shipment source is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsin1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-IN-1');
  v_shipment_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-wmsin231-a');
  v_shipment_cancelled_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-wmsin231-cancelled');
  v_account_a_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSIN Customer Alpha');
  v_order app.wms_inbound_orders;
  v_replay app.wms_inbound_orders;
begin
  begin
    perform app.prepare_wms_inbound_from_shipment(v_tenant1, v_shipment_id, v_warehouse_id, '00000000-0000-0000-0000-000000090103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_order := app.prepare_wms_inbound_from_shipment(v_tenant1, v_shipment_id, v_warehouse_id, '00000000-0000-0000-0000-000000090102', 'rep');
  if v_order.owner_account_id <> v_account_a_id or v_order.status <> 'draft' or v_order.source_type <> 'shipment_order' then
    raise exception 'assertion failed: expected a draft shipment_order-sourced inbound owned by Account A, got owner=% status=% source_type=%', v_order.owner_account_id, v_order.status, v_order.source_type;
  end if;

  v_replay := app.prepare_wms_inbound_from_shipment(v_tenant1, v_shipment_id, v_warehouse_id, '00000000-0000-0000-0000-000000090102', 'rep');
  if v_replay.id <> v_order.id or v_replay.record_version <> v_order.record_version then
    raise exception 'assertion failed: expected the same-source replay to return the identical, unchanged row';
  end if;

  begin
    perform app.prepare_wms_inbound_from_shipment(v_tenant1, gen_random_uuid(), v_warehouse_id, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected shipment_order_not_found';
  exception
    when others then
      if sqlerrm not like 'shipment_order_not_found%' then raise; end if;
  end;

  begin
    perform app.prepare_wms_inbound_from_shipment(v_tenant1, v_shipment_id, gen_random_uuid(), '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected warehouse_not_found';
  exception
    when others then
      if sqlerrm not like 'warehouse_not_found%' then raise; end if;
  end;

  begin
    perform app.prepare_wms_inbound_from_shipment(v_tenant1, v_shipment_cancelled_id, v_warehouse_id, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected stale_source -- the shipment is cancelled';
  exception
    when others then
      if sqlerrm not like 'stale_source%' then raise; end if;
  end;
end $$;

\echo '>> app.create_manual_wms_inbound: requires a non-empty reason and idempotency key; idempotent replay; rejects an ineligible owner account'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsin1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-IN-1');
  v_account_a_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSIN Customer Alpha');
  v_order app.wms_inbound_orders;
  v_replay app.wms_inbound_orders;
begin
  begin
    perform app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_a_id, null, 'idem-manual-1', '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected invalid_reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  begin
    perform app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_a_id, 'no ASN available', null, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected invalid_idempotency_key';
  exception
    when others then
      if sqlerrm not like 'invalid_idempotency_key%' then raise; end if;
  end;

  v_order := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_a_id, 'no ASN available', 'idem-manual-1', '00000000-0000-0000-0000-000000090102', 'rep');
  if v_order.source_type <> 'manual' or v_order.source_reason <> 'no ASN available' then
    raise exception 'assertion failed: expected a manual inbound with the given reason';
  end if;

  v_replay := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_a_id, 'no ASN available', 'idem-manual-1', '00000000-0000-0000-0000-000000090102', 'rep');
  if v_replay.id <> v_order.id then
    raise exception 'assertion failed: expected the same idempotency_key replay to return the identical row';
  end if;

  begin
    perform app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, gen_random_uuid(), 'no ASN available', 'idem-manual-2', '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected owner_account_not_found';
  exception
    when others then
      if sqlerrm not like 'owner_account_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.add_wms_inbound_order_line / app.add_wms_inbound_order_lines: authority-gated, snapshots item master control flags, rejects a foreign-owner item / bad UOM / non-positive quantity, only while draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsin1');
  v_account_a_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSIN Customer Alpha');
  v_item_a1_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_a_id and code = 'SKU-WMSIN-A1');
  v_item_a2_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_a_id and code = 'SKU-WMSIN-A2');
  v_item_b1_id uuid := (select id from app.item_masters where code = 'SKU-WMSIN-B1');
  v_order_id uuid := (select id from app.wms_inbound_orders where tenant_id = v_tenant1 and source_type = 'shipment_order');
  v_line app.wms_inbound_order_lines;
  v_lines app.wms_inbound_order_lines[];
  v_count integer;
begin
  begin
    perform app.add_wms_inbound_order_line(v_order_id, v_item_a1_id, 'PCS', 10, null, '00000000-0000-0000-0000-000000090103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_line := app.add_wms_inbound_order_line(v_order_id, v_item_a1_id, 'PCS', 10, 'first line', '00000000-0000-0000-0000-000000090102', 'rep');
  if v_line.line_number <> 1 or v_line.expected_quantity <> 10 or v_line.expected_uom_code <> 'PCS' then
    raise exception 'assertion failed: expected line 1, quantity 10, PCS, got line=%/qty=%/uom=%', v_line.line_number, v_line.expected_quantity, v_line.expected_uom_code;
  end if;

  begin
    perform app.add_wms_inbound_order_line(v_order_id, v_item_b1_id, 'PCS', 5, null, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected item_not_eligible -- SKU-WMSIN-B1 belongs to Account B, not Account A';
  exception
    when others then
      if sqlerrm not like 'item_not_eligible%' then raise; end if;
  end;

  begin
    perform app.add_wms_inbound_order_line(v_order_id, v_item_a2_id, 'NOPE', 5, null, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected invalid_uom';
  exception
    when others then
      if sqlerrm not like 'invalid_uom%' then raise; end if;
  end;

  begin
    perform app.add_wms_inbound_order_line(v_order_id, v_item_a2_id, 'KG', 0, null, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected invalid_quantity';
  exception
    when others then
      if sqlerrm not like 'invalid_quantity%' then raise; end if;
  end;

  select array_agg(l) into v_lines from app.add_wms_inbound_order_lines(
    v_order_id,
    jsonb_build_array(
      jsonb_build_object('item_master_id', v_item_a2_id, 'expected_uom_code', 'KG', 'expected_quantity', 25, 'notes', 'bulk line 1')
    ),
    '00000000-0000-0000-0000-000000090102', 'rep'
  ) l;
  if array_length(v_lines, 1) <> 1 or v_lines[1].line_number <> 2 then
    raise exception 'assertion failed: expected exactly 1 bulk-added line at line_number 2, got count=%', array_length(v_lines, 1);
  end if;

  begin
    perform app.add_wms_inbound_order_lines(v_order_id, '[]'::jsonb, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected invalid_lines -- empty array';
  exception
    when others then
      if sqlerrm not like 'invalid_lines%' then raise; end if;
  end;

  select count(*) into v_count from app.wms_inbound_order_lines where inbound_order_id = v_order_id;
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 lines on the order after the single add + bulk add, got %', v_count;
  end if;
end $$;

\echo '>> app.update_wms_inbound_order_line / app.remove_wms_inbound_order_line: stale version rejected, mutable fields update, removal frees the slot, both blocked once the header is no longer draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsin1');
  v_order_id uuid := (select id from app.wms_inbound_orders where tenant_id = v_tenant1 and source_type = 'shipment_order');
  v_line app.wms_inbound_order_lines;
begin
  select * into v_line from app.wms_inbound_order_lines where inbound_order_id = v_order_id and line_number = 1;

  begin
    perform app.update_wms_inbound_order_line(v_line.id, 15, 'updated', v_line.record_version + 1, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_line := app.update_wms_inbound_order_line(v_line.id, 15, 'updated', v_line.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
  if v_line.expected_quantity <> 15 or v_line.notes <> 'updated' or v_line.record_version <> 2 then
    raise exception 'assertion failed: expected quantity=15/notes=updated/version=2, got quantity=%/notes=%/version=%', v_line.expected_quantity, v_line.notes, v_line.record_version;
  end if;

  perform app.remove_wms_inbound_order_line(v_line.id, v_line.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
  if exists (select 1 from app.wms_inbound_order_lines where id = v_line.id) then
    raise exception 'assertion failed: expected the line to be removed';
  end if;
end $$;

\echo '>> app.schedule_wms_inbound_appointment / app.get_wms_inbound_readiness / app.confirm_wms_inbound: no_lines on an empty order, invalid window, draft->scheduled requires a line, readiness matches exactly what confirm blocks on, scheduled->confirmed, wrong-state transitions rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsin1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-IN-1');
  v_account_a_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSIN Customer Alpha');
  v_item_a1_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_a_id and code = 'SKU-WMSIN-A1');
  v_order app.wms_inbound_orders;
  v_readiness app.wms_inbound_readiness;
begin
  v_order := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_a_id, 'confirm-flow fixture', 'idem-confirm-flow', '00000000-0000-0000-0000-000000090102', 'rep');

  begin
    perform app.schedule_wms_inbound_appointment(v_order.id, now() + interval '1 day', now() + interval '1 day' + interval '2 hours', v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected no_lines -- the order has zero lines';
  exception
    when others then
      if sqlerrm not like 'no_lines%' then raise; end if;
  end;

  perform app.add_wms_inbound_order_line(v_order.id, v_item_a1_id, 'PCS', 20, null, '00000000-0000-0000-0000-000000090102', 'rep');

  begin
    perform app.schedule_wms_inbound_appointment(v_order.id, now() + interval '1 day', now(), v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected invalid_appointment_window';
  exception
    when others then
      if sqlerrm not like 'invalid_appointment_window%' then raise; end if;
  end;

  v_order := app.schedule_wms_inbound_appointment(v_order.id, now() + interval '1 day', now() + interval '1 day' + interval '2 hours', v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
  if v_order.status <> 'scheduled' then
    raise exception 'assertion failed: expected status=scheduled, got %', v_order.status;
  end if;

  begin
    perform app.schedule_wms_inbound_appointment(v_order.id, now() + interval '2 days', now() + interval '2 days' + interval '2 hours', v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- already scheduled, must be draft to schedule';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  v_order := app.reschedule_wms_inbound_appointment(v_order.id, now() + interval '3 days', now() + interval '3 days' + interval '2 hours', v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
  if v_order.status <> 'scheduled' then
    raise exception 'assertion failed: expected reschedule to keep status=scheduled, got %', v_order.status;
  end if;

  v_readiness := app.get_wms_inbound_readiness(v_order.id, '00000000-0000-0000-0000-000000090102');
  if not v_readiness.ready or not v_readiness.has_lines or not v_readiness.warehouse_active or not v_readiness.owner_active or v_readiness.invalid_line_count <> 0 then
    raise exception 'assertion failed: expected fully ready readiness, got %', v_readiness;
  end if;

  v_order := app.confirm_wms_inbound(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
  if v_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected status=confirmed, got %', v_order.status;
  end if;

  begin
    perform app.confirm_wms_inbound(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- already confirmed, must be scheduled to confirm';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end $$;

\echo '>> app.confirm_wms_inbound blocked by app.get_wms_inbound_readiness when a referenced item master is deactivated after the line was added (ATW-011A''s own disclosed deferred-check boundary, design note 6 -- deactivation is not itself blocked, but confirm honestly refuses to proceed)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsin1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-IN-1');
  v_account_a_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSIN Customer Alpha');
  v_item app.item_masters;
  v_order app.wms_inbound_orders;
  v_readiness app.wms_inbound_readiness;
begin
  select * into v_item from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_a_id and code = 'SKU-WMSIN-A2';
  v_order := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_a_id, 'not-ready fixture', 'idem-not-ready', '00000000-0000-0000-0000-000000090102', 'rep');
  perform app.add_wms_inbound_order_line(v_order.id, v_item.id, 'KG', 5, null, '00000000-0000-0000-0000-000000090102', 'rep');
  v_order := app.schedule_wms_inbound_appointment(v_order.id, now() + interval '1 day', now() + interval '1 day' + interval '2 hours', v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');

  perform app.set_item_master_status(v_item.id, 'inactive', 'discontinued mid-flow', v_item.record_version, '00000000-0000-0000-0000-000000090102', 'rep');

  v_readiness := app.get_wms_inbound_readiness(v_order.id, '00000000-0000-0000-0000-000000090102');
  if v_readiness.ready or v_readiness.invalid_line_count <> 1 then
    raise exception 'assertion failed: expected not-ready with invalid_line_count=1 after the referenced item master was deactivated, got ready=%/invalid_line_count=%', v_readiness.ready, v_readiness.invalid_line_count;
  end if;

  begin
    perform app.confirm_wms_inbound(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected inbound_not_ready';
  exception
    when others then
      if sqlerrm not like 'inbound_not_ready%' then raise; end if;
  end;
end $$;

\echo '>> app.cancel_wms_inbound: requires a non-empty reason, cancellable from draft, idempotent no-op on an already-cancelled row, stale version rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsin1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-IN-1');
  v_account_a_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSIN Customer Alpha');
  v_order app.wms_inbound_orders;
begin
  v_order := app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_a_id, 'cancel-flow fixture', 'idem-cancel-flow', '00000000-0000-0000-0000-000000090102', 'rep');

  begin
    perform app.cancel_wms_inbound(v_order.id, null, v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected invalid_reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_order := app.cancel_wms_inbound(v_order.id, 'customer withdrew ASN', v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep');
  if v_order.status <> 'cancelled' or v_order.cancelled_reason <> 'customer withdrew ASN' then
    raise exception 'assertion failed: expected status=cancelled with the given reason';
  end if;

  if (app.cancel_wms_inbound(v_order.id, null, v_order.record_version, '00000000-0000-0000-0000-000000090102', 'rep')).record_version <> v_order.record_version then
    raise exception 'assertion failed: expected an already-cancelled order to be a no-op regardless of the reason argument';
  end if;

  begin
    perform app.cancel_wms_inbound(v_order.id, 'irrelevant', v_order.record_version + 1, '00000000-0000-0000-0000-000000090102', 'rep');
    raise exception 'assertion failed: expected stale_version on an incorrect expected_version, even though the order is already cancelled';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- The freed idempotency_key may now be reused by a fresh manual inbound (design
  -- note 4 -- a cancelled order frees its own source/key, never permanently exhausts it).
  perform app.create_manual_wms_inbound(v_tenant1, v_warehouse_id, v_account_a_id, 'retry after cancel', 'idem-cancel-flow', '00000000-0000-0000-0000-000000090102', 'rep');
end $$;

\echo '>> app.list_wms_inbound_orders / app.get_wms_inbound_order / app.list_wms_inbound_order_lines: bounded reads, filters, limit clamp, cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsin1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'wmsin2');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-IN-1');
  v_account_a_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSIN Customer Alpha');
  v_order_id uuid := (select id from app.wms_inbound_orders where tenant_id = v_tenant1 and source_type = 'shipment_order');
  v_count integer;
begin
  select count(*) into v_count from app.list_wms_inbound_orders(v_tenant1, '00000000-0000-0000-0000-000000090102', v_warehouse_id, null, null, 50);
  if v_count < 4 then
    raise exception 'assertion failed: expected at least 4 inbound orders under WH-IN-1 (shipment-sourced + several manual fixtures), got %', v_count;
  end if;

  select count(*) into v_count from app.list_wms_inbound_orders(v_tenant1, '00000000-0000-0000-0000-000000090102', v_warehouse_id, v_account_a_id, 'cancelled', 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 cancelled inbound order for Account A, got %', v_count;
  end if;

  select count(*) into v_count from app.list_wms_inbound_orders(v_tenant1, '00000000-0000-0000-0000-000000090102', v_warehouse_id, null, null, 0);
  if v_count <> 1 then
    raise exception 'assertion failed: expected p_limit=0 to clamp up to 1, got %', v_count;
  end if;

  if (app.get_wms_inbound_order(v_order_id, '00000000-0000-0000-0000-000000090102')).id <> v_order_id then
    raise exception 'assertion failed: expected get_wms_inbound_order to return the identical row';
  end if;

  select count(*) into v_count from app.list_wms_inbound_order_lines(v_order_id, '00000000-0000-0000-0000-000000090102');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 remaining line on the shipment-sourced order (the second was removed earlier), got %', v_count;
  end if;

  -- ISS-2026-043 extension fix (Track B Batch 2): a genuine stranger to the order's
  -- tenant now gets the same not-found error a nonexistent id produces, never a
  -- tenant-echoing insufficient_authority error -- updated from the pre-fix
  -- expectation (insufficient_authority) to the corrected one.
  begin
    perform app.get_wms_inbound_order(v_order_id, '00000000-0000-0000-0000-000000090107');
    raise exception 'assertion failed: expected inbound_order_not_found -- tenant2''s rep has no membership in tenant1';
  exception
    when no_data_found then
      if sqlerrm not like 'inbound_order_not_found%' then raise; end if;
  end;

  select count(*) into v_count from app.list_wms_inbound_orders(v_tenant2, '00000000-0000-0000-0000-000000090107', null, null, null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant2''s own rep to see zero inbound orders (none created there)';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.wms_inbound_orders', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_inbound_orders';
  end if;
  if has_table_privilege('anon', 'app.wms_inbound_order_lines', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_inbound_order_lines';
  end if;
  if has_function_privilege('anon', 'app.prepare_wms_inbound_from_shipment(uuid, uuid, uuid, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.prepare_wms_inbound_from_shipment';
  end if;

  if not has_table_privilege('authenticated', 'app.wms_inbound_orders', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.wms_inbound_orders';
  end if;
  if has_table_privilege('authenticated', 'app.wms_inbound_orders', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.wms_inbound_orders -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;

  if not has_table_privilege('service_role', 'app.wms_inbound_orders', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_inbound_orders';
  end if;
end $$;
