-- Real, executable test evidence for ATW-016A (CG-S10-ATW-016A, inserted -- WMS
-- Outbound Order, the "outbound order/demand creation and confirmation" slice
-- extracted from Prompt 238) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (wmsout1), a company org unit, a rep (OPS:Create/Edit/View), an OPS:View-only viewer, a global Supreme Admin, one active warehouse (WH-OUT-1), two customer accounts (Account Alpha and Account Beta, each via the full CRM->Job Order->Shipment Order pipeline) with a confirmed shipment each plus a draft (unconfirmed) shipment and a second confirmed shipment for Alpha, item masters owned by each account, and a customer_user-layer actor scoped to Account Alpha only (mirrors advanced-tms-lot-batch-serial-expiry.sql''s own cross-owner pattern). Tenant2 (wmsout2): an isolated rep, its own warehouse and account, for cross-tenant leakage checks.'
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
  v_account_alpha app.accounts;
  v_account_beta app.accounts;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment app.shipment_orders;
  v_shipment_draft app.shipment_orders;
  v_shipment_confirm2 app.shipment_orders;
  v_shipment_beta app.shipment_orders;
  v_warehouse app.warehouses;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000170101', 'admin@wmsout1.test'),
    ('00000000-0000-0000-0000-000000170102', 'rep@wmsout1.test'),
    ('00000000-0000-0000-0000-000000170103', 'viewer@wmsout1.test'),
    ('00000000-0000-0000-0000-000000170105', 'supreme@wmsout1.test'),
    ('00000000-0000-0000-0000-000000170106', 'admin2@wmsout2.test'),
    ('00000000-0000-0000-0000-000000170107', 'rep2@wmsout2.test'),
    ('00000000-0000-0000-0000-000000170108', 'customer-alpha@wmsout1.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000170105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('wmsout1', 'WMS Outbound Order Tenant One', 'idem-wmsout1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'wmsout1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'WMSOUT1-CO', 'WMS Outbound Order Tenant One Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'WMSOUT1-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000170101', 'admin@wmsout1.test', 'WMSOUT Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@wmsout1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000170101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000170102', 'rep@wmsout1.test', 'WMSOUT Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@wmsout1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000170103', 'viewer@wmsout1.test', 'WMSOUT Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@wmsout1.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'WMSOUT Rep Role', 'full commercial + ops create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000170102', '00000000-0000-0000-0000-000000170101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'WMSOUT Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000170103', '00000000-0000-0000-0000-000000170101', 'tester');

  v_warehouse := app.create_warehouse(v_tenant1, v_company, 'WH-OUT-1', 'WMS Outbound Order Warehouse 1', 'Jl. Outbound 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000170102', 'rep');

  -- Account Alpha, via the full CRM->Job Order->Shipment Order pipeline (the only real
  -- path to a confirmed app.shipment_orders row in this repository).
  perform app.capture_lead(v_tenant1, 'manual', null, 'WMSOUT Customer Alpha', 'Alice WmsOut', 'alice@wmsout238.test', '0811',
    '00000000-0000-0000-0000-000000170102', v_company, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_lead from app.leads where email = 'alice@wmsout238.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WMSOUT Customer Alpha', 'WMSOUT238A', '11.111.111.21-111.000',
    jsonb_build_object('line1', 'Jl. Outbound Alpha 9', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Alice WmsOut Ops', 'Ops Lead', 'alice@wmsout238.test', '0811', '00000000-0000-0000-0000-000000170102', v_company, '00000000-0000-0000-0000-000000170102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSOUT238 Alpha lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000170102', v_company, '00000000-0000-0000-0000-000000170102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSOUT238-A', 'Contoso WmsOut238 Line', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000170101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000170101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000170102', 'tester');
  v_rule := app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000170102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000170102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000170102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000170102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSOUT238 Alpha lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000170102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Alice WmsOut Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_alpha from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000170102', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000170102', 'rep');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000170102', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-wmsout238-a-confirmed', null, null, 'land_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '2 days', 300, 300, 4, 800, 800, 10, null, '00000000-0000-0000-0000-000000170102', 'rep'
  );
  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000170102', 'rep');

  select * into v_shipment_draft from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-wmsout238-a-draft', null, null, 'land_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, 'split: draft fixture', '00000000-0000-0000-0000-000000170102', 'rep'
  );

  select * into v_shipment_confirm2 from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-wmsout238-a-confirmed2', null, null, 'land_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '2 days', 200, 200, 3, null, null, null, 'split: second confirmed fixture', '00000000-0000-0000-0000-000000170102', 'rep'
  );
  select * into v_shipment_confirm2 from app.confirm_shipment_order(v_shipment_confirm2.id, v_shipment_confirm2.record_version, '00000000-0000-0000-0000-000000170102', 'rep');

  -- Account Beta, a second owner account in the SAME tenant -- needed for the
  -- foreign-owner item rejection AND the cross-owner read-scoping assertions below.
  perform app.capture_lead(v_tenant1, 'manual', null, 'WMSOUT Customer Beta', 'Bob WmsOut', 'bob@wmsout238.test', '0812',
    '00000000-0000-0000-0000-000000170102', v_company, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_lead from app.leads where email = 'bob@wmsout238.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'WMSOUT Customer Beta', 'WMSOUT238B', '11.111.111.22-111.000',
    jsonb_build_object('line1', 'Jl. Outbound Beta 10', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;
  select * into v_contact from app.create_contact(v_tenant1, 'Bob WmsOut Ops', 'Ops Lead', 'bob@wmsout238.test', '0812', '00000000-0000-0000-0000-000000170102', v_company, '00000000-0000-0000-0000-000000170102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'WMSOUT238 Beta lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000170102', v_company, '00000000-0000-0000-0000-000000170102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-WMSOUT238-B', 'Contoso WmsOut238 Line B', 'land_freight', 'FTL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000170101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000170101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000170102', 'tester');
  perform app.calculate_margin(v_selection.id, 6000000, 'IDR', 0, '00000000-0000-0000-0000-000000170102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000170102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'WMSOUT238 Beta lane', v_calc_id, 1, 6000000, 0, 0, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000170102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000170102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob WmsOut Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account_beta from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000170102', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000170102', 'rep');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000170102', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
  select * into v_shipment_beta from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-wmsout238-beta-confirmed', null, null, 'land_freight', 'land', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '2 days', 400, 400, 8, 400, 400, 8, null, '00000000-0000-0000-0000-000000170102', 'rep'
  );
  select * into v_shipment_beta from app.confirm_shipment_order(v_shipment_beta.id, v_shipment_beta.record_version, '00000000-0000-0000-0000-000000170102', 'rep');

  -- Item masters (ATW-011A), one/two per account.
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-WMSOUT-A1', 'Alpha Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000170102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-WMSOUT-A2', 'Alpha Gadget', null, 'KG', false, false, false, '00000000-0000-0000-0000-000000170102', 'rep');
  perform app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-WMSOUT-B1', 'Beta Widget', null, 'PCS', false, false, false, '00000000-0000-0000-0000-000000170102', 'rep');

  -- The customer_user-layer actor is invited with a NULL org_unit_id -- the ONLY path
  -- by which it can ever pass app.can_access_record's row filter is real org-unit
  -- membership it does not have here, so app.actor_can_view_owner_scoped_row's own
  -- customer_account_ref match (ATW-016 design note 6b) is the real, sole gate tested
  -- below -- never incidental org-unit sharing. Granted the OPS:View-only role so the
  -- tenant-wide RBAC layer passes and the owner-scope layer is what is really exercised.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000170108', 'customer-alpha@wmsout1.test', 'Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@wmsout1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000170108', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000170108', '00000000-0000-0000-0000-000000170101', 'tester');

  -- Tenant2: fully isolated -- exists only to prove cross-tenant scope safety.
  perform app.provision_tenant('wmsout2', 'WMS Outbound Order Tenant Two', 'idem-wmsout2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'wmsout2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'WMSOUT2-CO', 'WMS Outbound Order Tenant Two Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'WMSOUT2-CO');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000170106', 'admin2@wmsout2.test', 'Tenant2 Admin', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@wmsout2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000170106', 'tenant_admin', v_tenant2, null, 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000170107', 'rep2@wmsout2.test', 'Tenant2 Rep', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@wmsout2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'ops create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000170107', '00000000-0000-0000-0000-000000170106', 'tester');
end $$;

\echo '>> app.prepare_wms_outbound_from_shipment: viewer rejected; success inherits owner from the shipment''s own shipper_account_id; idempotent replay; unknown shipment/warehouse not found; a non-confirmed (draft) shipment source is rejected source_not_confirmed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_shipment_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-wmsout238-a-confirmed');
  v_shipment_draft_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-wmsout238-a-draft');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_order app.wms_outbound_orders;
  v_replay app.wms_outbound_orders;
begin
  begin
    perform app.prepare_wms_outbound_from_shipment(v_tenant1, v_shipment_id, v_warehouse_id, '00000000-0000-0000-0000-000000170103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.prepare_wms_outbound_from_shipment(v_tenant1, v_shipment_draft_id, v_warehouse_id, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected source_not_confirmed -- the shipment is still draft';
  exception
    when others then
      if sqlerrm not like 'source_not_confirmed%' then raise; end if;
  end;

  v_order := app.prepare_wms_outbound_from_shipment(v_tenant1, v_shipment_id, v_warehouse_id, '00000000-0000-0000-0000-000000170102', 'rep');
  if v_order.owner_account_id <> v_account_alpha_id or v_order.status <> 'draft' or v_order.source_type <> 'shipment_order' then
    raise exception 'assertion failed: expected a draft shipment_order-sourced outbound order owned by Account Alpha, got owner=% status=% source_type=%', v_order.owner_account_id, v_order.status, v_order.source_type;
  end if;

  v_replay := app.prepare_wms_outbound_from_shipment(v_tenant1, v_shipment_id, v_warehouse_id, '00000000-0000-0000-0000-000000170102', 'rep');
  if v_replay.id <> v_order.id or v_replay.record_version <> v_order.record_version then
    raise exception 'assertion failed: expected the same-source replay to return the identical, unchanged row';
  end if;

  begin
    perform app.prepare_wms_outbound_from_shipment(v_tenant1, gen_random_uuid(), v_warehouse_id, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected shipment_order_not_found';
  exception
    when others then
      if sqlerrm not like 'shipment_order_not_found%' then raise; end if;
  end;

  begin
    perform app.prepare_wms_outbound_from_shipment(v_tenant1, v_shipment_id, gen_random_uuid(), '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected warehouse_not_found';
  exception
    when others then
      if sqlerrm not like 'warehouse_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.wms_outbound_orders_source_shipment_unique: the real partial unique index rejects a second non-cancelled row for the same (tenant_id, source_shipment_order_id) structurally, even bypassing the RPC layer entirely -- design note 4'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_shipment_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-wmsout238-a-confirmed');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
begin
  begin
    insert into app.wms_outbound_orders (tenant_id, warehouse_id, owner_account_id, outbound_number, source_type, source_shipment_order_id, created_by)
    values (v_tenant1, v_warehouse_id, v_account_alpha_id, 'WMSOUT-DIRECT-TEST', 'shipment_order', v_shipment_id, 'direct-insert-test');
    raise exception 'assertion failed: expected unique_violation -- a non-cancelled outbound order for this shipment already exists';
  exception
    when unique_violation then null;
  end;
end $$;

\echo '>> app.create_manual_wms_outbound_order: requires a non-empty reason and idempotency key; idempotent replay; rejects an ineligible owner account; accepts an optional requested_ship_date'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_order app.wms_outbound_orders;
  v_replay app.wms_outbound_orders;
begin
  begin
    perform app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, null, 'idem-manual-1', null, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected invalid_reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  begin
    perform app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'no shipment order yet', null, null, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected invalid_idempotency_key';
  exception
    when others then
      if sqlerrm not like 'invalid_idempotency_key%' then raise; end if;
  end;

  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'no shipment order yet', 'idem-manual-1', '2026-08-15', '00000000-0000-0000-0000-000000170102', 'rep');
  if v_order.source_type <> 'manual' or v_order.source_reason <> 'no shipment order yet' or v_order.requested_ship_date::text <> '2026-08-15' then
    raise exception 'assertion failed: expected a manual outbound order with the given reason and requested_ship_date, got reason=%/date=%', v_order.source_reason, v_order.requested_ship_date;
  end if;

  v_replay := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'no shipment order yet', 'idem-manual-1', '2026-08-15', '00000000-0000-0000-0000-000000170102', 'rep');
  if v_replay.id <> v_order.id then
    raise exception 'assertion failed: expected the same idempotency_key replay to return the identical row';
  end if;

  begin
    perform app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, gen_random_uuid(), 'no shipment order yet', 'idem-manual-2', null, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected owner_account_not_found';
  exception
    when others then
      if sqlerrm not like 'owner_account_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.add_wms_outbound_order_line / app.add_wms_outbound_order_lines: authority-gated, snapshots item master control flags, rejects a foreign-owner item / bad UOM / non-positive quantity, only while draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_item_a1_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_alpha_id and code = 'SKU-WMSOUT-A1');
  v_item_a2_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_alpha_id and code = 'SKU-WMSOUT-A2');
  v_item_b1_id uuid := (select id from app.item_masters where code = 'SKU-WMSOUT-B1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and source_type = 'shipment_order');
  v_line app.wms_outbound_order_lines;
  v_lines app.wms_outbound_order_lines[];
  v_count integer;
begin
  begin
    perform app.add_wms_outbound_order_line(v_order_id, v_item_a1_id, 'PCS', 10, null, '00000000-0000-0000-0000-000000170103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_line := app.add_wms_outbound_order_line(v_order_id, v_item_a1_id, 'PCS', 10, 'first line', '00000000-0000-0000-0000-000000170102', 'rep');
  if v_line.line_number <> 1 or v_line.requested_quantity <> 10 or v_line.requested_uom_code <> 'PCS' then
    raise exception 'assertion failed: expected line 1, quantity 10, PCS, got line=%/qty=%/uom=%', v_line.line_number, v_line.requested_quantity, v_line.requested_uom_code;
  end if;

  begin
    perform app.add_wms_outbound_order_line(v_order_id, v_item_b1_id, 'PCS', 5, null, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected item_not_eligible -- SKU-WMSOUT-B1 belongs to Account Beta, not Account Alpha';
  exception
    when others then
      if sqlerrm not like 'item_not_eligible%' then raise; end if;
  end;

  begin
    perform app.add_wms_outbound_order_line(v_order_id, v_item_a2_id, 'NOPE', 5, null, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected invalid_uom';
  exception
    when others then
      if sqlerrm not like 'invalid_uom%' then raise; end if;
  end;

  begin
    perform app.add_wms_outbound_order_line(v_order_id, v_item_a2_id, 'KG', 0, null, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected invalid_quantity';
  exception
    when others then
      if sqlerrm not like 'invalid_quantity%' then raise; end if;
  end;

  select array_agg(l) into v_lines from app.add_wms_outbound_order_lines(
    v_order_id,
    jsonb_build_array(
      jsonb_build_object('item_master_id', v_item_a2_id, 'requested_uom_code', 'KG', 'requested_quantity', 25, 'notes', 'bulk line 1')
    ),
    '00000000-0000-0000-0000-000000170102', 'rep'
  ) l;
  if array_length(v_lines, 1) <> 1 or v_lines[1].line_number <> 2 then
    raise exception 'assertion failed: expected exactly 1 bulk-added line at line_number 2, got count=%', array_length(v_lines, 1);
  end if;

  begin
    perform app.add_wms_outbound_order_lines(v_order_id, '[]'::jsonb, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected invalid_lines -- empty array';
  exception
    when others then
      if sqlerrm not like 'invalid_lines%' then raise; end if;
  end;

  select count(*) into v_count from app.wms_outbound_order_lines where outbound_order_id = v_order_id;
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 lines on the order after the single add + bulk add, got %', v_count;
  end if;
end $$;

\echo '>> app.update_wms_outbound_order_line / app.remove_wms_outbound_order_line: stale version rejected, mutable fields update, removal frees the slot'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and source_type = 'shipment_order');
  v_line app.wms_outbound_order_lines;
begin
  select * into v_line from app.wms_outbound_order_lines where outbound_order_id = v_order_id and line_number = 1;

  begin
    perform app.update_wms_outbound_order_line(v_line.id, 15, 'updated', v_line.record_version + 1, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  v_line := app.update_wms_outbound_order_line(v_line.id, 15, 'updated', v_line.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
  if v_line.requested_quantity <> 15 or v_line.notes <> 'updated' or v_line.record_version <> 2 then
    raise exception 'assertion failed: expected quantity=15/notes=updated/version=2, got quantity=%/notes=%/version=%', v_line.requested_quantity, v_line.notes, v_line.record_version;
  end if;

  perform app.remove_wms_outbound_order_line(v_line.id, v_line.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
  if exists (select 1 from app.wms_outbound_order_lines where id = v_line.id) then
    raise exception 'assertion failed: expected the line to be removed';
  end if;
end $$;

\echo '>> app.get_wms_outbound_readiness / app.confirm_wms_outbound_order: an empty order is not ready (outbound_not_ready); draft->confirmed once a valid line exists; wrong-state re-confirm rejected invalid_transition; add/update/remove all rejected outbound_not_draft once confirmed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_item_a1_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_alpha_id and code = 'SKU-WMSOUT-A1');
  v_order app.wms_outbound_orders;
  v_line app.wms_outbound_order_lines;
  v_readiness app.wms_outbound_readiness;
begin
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'confirm-flow fixture', 'idem-confirm-flow', null, '00000000-0000-0000-0000-000000170102', 'rep');

  v_readiness := app.get_wms_outbound_readiness(v_order.id, '00000000-0000-0000-0000-000000170102');
  if v_readiness.ready or v_readiness.has_lines then
    raise exception 'assertion failed: expected not-ready with has_lines=false on a fresh empty order';
  end if;

  begin
    perform app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected outbound_not_ready -- the order has zero lines';
  exception
    when others then
      if sqlerrm not like 'outbound_not_ready%' then raise; end if;
  end;

  v_line := app.add_wms_outbound_order_line(v_order.id, v_item_a1_id, 'PCS', 20, null, '00000000-0000-0000-0000-000000170102', 'rep');

  v_readiness := app.get_wms_outbound_readiness(v_order.id, '00000000-0000-0000-0000-000000170102');
  if not v_readiness.ready or not v_readiness.has_lines or not v_readiness.warehouse_active or not v_readiness.owner_active or not v_readiness.source_shipment_valid or v_readiness.invalid_line_count <> 0 then
    raise exception 'assertion failed: expected fully ready readiness, got %', v_readiness;
  end if;

  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
  if v_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected status=confirmed, got %', v_order.status;
  end if;

  begin
    perform app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- already confirmed, must be draft to confirm';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  begin
    perform app.add_wms_outbound_order_line(v_order.id, v_item_a1_id, 'PCS', 1, null, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected outbound_not_draft -- the order is confirmed';
  exception
    when others then
      if sqlerrm not like 'outbound_not_draft%' then raise; end if;
  end;

  begin
    perform app.update_wms_outbound_order_line(v_line.id, 99, null, v_line.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected outbound_not_draft -- the order is confirmed';
  exception
    when others then
      if sqlerrm not like 'outbound_not_draft%' then raise; end if;
  end;

  begin
    perform app.remove_wms_outbound_order_line(v_line.id, v_line.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected outbound_not_draft -- the order is confirmed';
  exception
    when others then
      if sqlerrm not like 'outbound_not_draft%' then raise; end if;
  end;
end $$;

\echo '>> app.confirm_wms_outbound_order blocked by app.get_wms_outbound_readiness when a referenced item master is deactivated after the line was added (mirrors ATW-012''s own deferred-check boundary)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_item app.item_masters;
  v_order app.wms_outbound_orders;
  v_readiness app.wms_outbound_readiness;
begin
  select * into v_item from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_alpha_id and code = 'SKU-WMSOUT-A2';
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'not-ready fixture', 'idem-not-ready', null, '00000000-0000-0000-0000-000000170102', 'rep');
  perform app.add_wms_outbound_order_line(v_order.id, v_item.id, 'KG', 5, null, '00000000-0000-0000-0000-000000170102', 'rep');

  perform app.set_item_master_status(v_item.id, 'inactive', 'discontinued mid-flow', v_item.record_version, '00000000-0000-0000-0000-000000170102', 'rep');

  v_readiness := app.get_wms_outbound_readiness(v_order.id, '00000000-0000-0000-0000-000000170102');
  if v_readiness.ready or v_readiness.invalid_line_count <> 1 then
    raise exception 'assertion failed: expected not-ready with invalid_line_count=1 after the referenced item master was deactivated, got ready=%/invalid_line_count=%', v_readiness.ready, v_readiness.invalid_line_count;
  end if;

  begin
    perform app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected outbound_not_ready';
  exception
    when others then
      if sqlerrm not like 'outbound_not_ready%' then raise; end if;
  end;
end $$;

\echo '>> design note 7 (genuinely new vs. ATW-012): app.confirm_wms_outbound_order re-checks that a shipment-order-sourced order''s own source shipment order is STILL confirmed at confirm time, not merely at prepare time -- cancelling the source shipment after the line was added flips source_shipment_valid to false and blocks confirm'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_item_a1_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_alpha_id and code = 'SKU-WMSOUT-A1');
  v_shipment_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-wmsout238-a-confirmed2');
  v_shipment app.shipment_orders;
  v_order app.wms_outbound_orders;
  v_readiness app.wms_outbound_readiness;
begin
  v_order := app.prepare_wms_outbound_from_shipment(v_tenant1, v_shipment_id, v_warehouse_id, '00000000-0000-0000-0000-000000170102', 'rep');
  perform app.add_wms_outbound_order_line(v_order.id, v_item_a1_id, 'PCS', 3, null, '00000000-0000-0000-0000-000000170102', 'rep');

  v_readiness := app.get_wms_outbound_readiness(v_order.id, '00000000-0000-0000-0000-000000170102');
  if not v_readiness.ready or not v_readiness.source_shipment_valid then
    raise exception 'assertion failed: expected ready=true/source_shipment_valid=true before the source shipment is cancelled';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_shipment_id;
  perform app.cancel_shipment_order(v_shipment.id, v_shipment.record_version, 'test cancellation after outbound order prepared', '00000000-0000-0000-0000-000000170102', 'rep');

  v_readiness := app.get_wms_outbound_readiness(v_order.id, '00000000-0000-0000-0000-000000170102');
  if v_readiness.ready or v_readiness.source_shipment_valid then
    raise exception 'assertion failed: expected ready=false/source_shipment_valid=false once the source shipment order is cancelled, got ready=%/source_shipment_valid=%', v_readiness.ready, v_readiness.source_shipment_valid;
  end if;

  begin
    perform app.confirm_wms_outbound_order(v_order.id, v_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected outbound_not_ready -- the source shipment order is no longer confirmed';
  exception
    when others then
      if sqlerrm not like 'outbound_not_ready%' then raise; end if;
  end;
end $$;

\echo '>> app.cancel_wms_outbound_order: requires a non-empty reason, cancellable from draft, idempotent no-op on an already-cancelled row, stale version rejected, freed idempotency_key/source reusable'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_order app.wms_outbound_orders;
begin
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'cancel-flow fixture', 'idem-cancel-flow', null, '00000000-0000-0000-0000-000000170102', 'rep');

  begin
    perform app.cancel_wms_outbound_order(v_order.id, null, v_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected invalid_reason';
  exception
    when others then
      if sqlerrm not like 'invalid_reason%' then raise; end if;
  end;

  v_order := app.cancel_wms_outbound_order(v_order.id, 'customer withdrew demand', v_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep');
  if v_order.status <> 'cancelled' or v_order.cancelled_reason <> 'customer withdrew demand' then
    raise exception 'assertion failed: expected status=cancelled with the given reason';
  end if;

  if (app.cancel_wms_outbound_order(v_order.id, null, v_order.record_version, '00000000-0000-0000-0000-000000170102', 'rep')).record_version <> v_order.record_version then
    raise exception 'assertion failed: expected an already-cancelled order to be a no-op regardless of the reason argument';
  end if;

  begin
    perform app.cancel_wms_outbound_order(v_order.id, 'irrelevant', v_order.record_version + 1, '00000000-0000-0000-0000-000000170102', 'rep');
    raise exception 'assertion failed: expected stale_version on an incorrect expected_version, even though the order is already cancelled';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- The freed idempotency_key may now be reused by a fresh manual outbound order
  -- (design note 4 -- a cancelled order frees its own source/key, never permanently
  -- exhausts it).
  perform app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'retry after cancel', 'idem-cancel-flow', null, '00000000-0000-0000-0000-000000170102', 'rep');
end $$;

\echo '>> RBAC-before-short-circuit regression: tenant2''s rep, who holds zero membership in tenant1, is rejected insufficient_authority attempting the identical idempotent-replay/no-op-cancel/foreign-owner-item RPC calls against tenant1''s real already-existing data -- never handed live business data off any short-circuit'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_shipment_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-wmsout238-a-confirmed');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_cancelled_order app.wms_outbound_orders;
begin
  select * into v_cancelled_order from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-cancel-flow' and status = 'cancelled';

  begin
    perform app.prepare_wms_outbound_from_shipment(v_tenant1, v_shipment_id, v_warehouse_id, '00000000-0000-0000-0000-000000170107', 'rep2');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep has no membership in tenant1, even though this exact (tenant_id, source_shipment_order_id) already has a real non-cancelled outbound order (the idempotent short-circuit itself)';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.create_manual_wms_outbound_order(v_tenant1, v_warehouse_id, v_account_alpha_id, 'retry after cancel', 'idem-cancel-flow', null, '00000000-0000-0000-0000-000000170107', 'rep2');
    raise exception 'assertion failed: expected insufficient_authority on the identical idempotency_key replay attempted by tenant2''s own rep';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.cancel_wms_outbound_order(v_cancelled_order.id, null, v_cancelled_order.record_version, '00000000-0000-0000-0000-000000170107', 'rep2');
    raise exception 'assertion failed: expected insufficient_authority on the identical already-cancelled no-op replay attempted by tenant2''s own rep';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> app.list_wms_outbound_orders / app.get_wms_outbound_order / app.list_wms_outbound_order_lines: bounded reads, filters, limit clamp, cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'wmsout2');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and source_type = 'shipment_order' and source_shipment_order_id = (select id from app.shipment_orders where idempotency_key = 'idem-wmsout238-a-confirmed'));
  v_count integer;
begin
  select count(*) into v_count from app.list_wms_outbound_orders(v_tenant1, '00000000-0000-0000-0000-000000170102', v_warehouse_id, null, null, 50);
  if v_count < 4 then
    raise exception 'assertion failed: expected at least 4 outbound orders under WH-OUT-1 (shipment-sourced + several manual fixtures), got %', v_count;
  end if;

  select count(*) into v_count from app.list_wms_outbound_orders(v_tenant1, '00000000-0000-0000-0000-000000170102', v_warehouse_id, v_account_alpha_id, 'cancelled', 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 cancelled outbound order for Account Alpha, got %', v_count;
  end if;

  select count(*) into v_count from app.list_wms_outbound_orders(v_tenant1, '00000000-0000-0000-0000-000000170102', v_warehouse_id, null, null, 0);
  if v_count <> 1 then
    raise exception 'assertion failed: expected p_limit=0 to clamp up to 1, got %', v_count;
  end if;

  if (app.get_wms_outbound_order(v_order_id, '00000000-0000-0000-0000-000000170102')).id <> v_order_id then
    raise exception 'assertion failed: expected get_wms_outbound_order to return the identical row';
  end if;

  select count(*) into v_count from app.list_wms_outbound_order_lines(v_order_id, '00000000-0000-0000-0000-000000170102');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 remaining line on the shipment-sourced order (the second was removed earlier), got %', v_count;
  end if;

  begin
    perform app.get_wms_outbound_order(v_order_id, '00000000-0000-0000-0000-000000170107');
    raise exception 'assertion failed: expected insufficient_authority -- tenant2''s rep has no membership in tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select count(*) into v_count from app.list_wms_outbound_orders(v_tenant2, '00000000-0000-0000-0000-000000170107', null, null, null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected tenant2''s own rep to see zero outbound orders (none created there)';
  end if;
end $$;

\echo '>> owner-account read scoping (ATW-016 design note 6b/10): the Alpha-scoped customer_user actor CAN read Owner Alpha''s own order/lines/readiness through every owner-scoped read RPC, and CANNOT read Owner Beta''s -- either a hard insufficient_authority rejection (single-row reads) or a silent zero-row result (list reads), never Beta''s real data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'wmsout1');
  v_warehouse_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-OUT-1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000170108';
  v_account_alpha_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Alpha');
  v_account_beta_id uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'WMSOUT Customer Beta');
  v_item_beta_id uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-WMSOUT-B1');
  v_shipment_beta_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-wmsout238-beta-confirmed');
  v_alpha_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and source_type = 'shipment_order' and source_shipment_order_id = (select id from app.shipment_orders where idempotency_key = 'idem-wmsout238-a-confirmed'));
  v_beta_order app.wms_outbound_orders;
  v_count integer;
begin
  -- Build a real Owner-Beta outbound order for the negative assertions below.
  v_beta_order := app.prepare_wms_outbound_from_shipment(v_tenant1, v_shipment_beta_id, v_warehouse_id, '00000000-0000-0000-0000-000000170102', 'rep');
  perform app.add_wms_outbound_order_line(v_beta_order.id, v_item_beta_id, 'PCS', 4, null, '00000000-0000-0000-0000-000000170102', 'rep');

  -- 1/4: app.get_wms_outbound_order -- own owner succeeds, other owner rejected.
  if (app.get_wms_outbound_order(v_alpha_order_id, v_customer_alpha)).id <> v_alpha_order_id then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor to read Owner Alpha''s own outbound order';
  end if;
  begin
    perform app.get_wms_outbound_order(v_beta_order.id, v_customer_alpha);
    raise exception 'assertion failed: expected insufficient_authority -- the Alpha-scoped customer actor must not read Owner Beta''s outbound order';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- 2/4: app.list_wms_outbound_orders -- Beta's row silently excluded, Alpha's included.
  select count(*) into v_count from app.list_wms_outbound_orders(v_tenant1, v_customer_alpha, null, null, null, 200) v where v.id = v_alpha_order_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor''s list to include Owner Alpha''s own outbound order';
  end if;
  select count(*) into v_count from app.list_wms_outbound_orders(v_tenant1, v_customer_alpha, null, null, null, 200) v where v.id = v_beta_order.id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor''s list to exclude Owner Beta''s outbound order, got % rows', v_count;
  end if;

  -- 3/4: app.list_wms_outbound_order_lines -- own owner succeeds, other owner rejected
  -- (list_wms_outbound_order_lines delegates its own gate to get_wms_outbound_order).
  select count(*) into v_count from app.list_wms_outbound_order_lines(v_alpha_order_id, v_customer_alpha);
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor to read Owner Alpha''s own outbound order lines';
  end if;
  begin
    perform app.list_wms_outbound_order_lines(v_beta_order.id, v_customer_alpha);
    raise exception 'assertion failed: expected insufficient_authority -- the Alpha-scoped customer actor must not read Owner Beta''s outbound order lines';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- 4/4: app.get_wms_outbound_readiness -- own owner succeeds, other owner rejected.
  if not (app.get_wms_outbound_readiness(v_alpha_order_id, v_customer_alpha)).has_lines then
    raise exception 'assertion failed: expected the Alpha-scoped customer actor to read Owner Alpha''s own readiness';
  end if;
  begin
    perform app.get_wms_outbound_readiness(v_beta_order.id, v_customer_alpha);
    raise exception 'assertion failed: expected insufficient_authority -- the Alpha-scoped customer actor must not read Owner Beta''s readiness';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Sanity: owner_account_id values really do differ (the assertions above are real).
  if v_account_alpha_id = v_account_beta_id then
    raise exception 'assertion failed: fixture error -- Alpha and Beta owner accounts must be distinct';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.wms_outbound_orders', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_outbound_orders';
  end if;
  if has_table_privilege('anon', 'app.wms_outbound_order_lines', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.wms_outbound_order_lines';
  end if;
  if has_function_privilege('anon', 'app.prepare_wms_outbound_from_shipment(uuid, uuid, uuid, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.prepare_wms_outbound_from_shipment';
  end if;
  if has_function_privilege('anon', 'app.confirm_wms_outbound_order(uuid, integer, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.confirm_wms_outbound_order';
  end if;

  if not has_table_privilege('authenticated', 'app.wms_outbound_orders', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.wms_outbound_orders';
  end if;
  if has_table_privilege('authenticated', 'app.wms_outbound_orders', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.wms_outbound_orders -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;

  if not has_table_privilege('service_role', 'app.wms_outbound_orders', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access to app.wms_outbound_orders';
  end if;
end $$;
