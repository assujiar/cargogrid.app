-- Real, executable test evidence for OPS-182 (Operations Dashboard, CG-S8-OPS-016) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (OPS full incl View cost), a sibling-team outsider (full grants incl View cost, wrong record scope), a global Supreme Admin, one confirmed Job Order, and two Shipment Orders exercising distinct status/delay/exception/ePOD/cost-variance combinations'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_outsider_role uuid;
  v_outsider_draft app.role_versions;
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
  v_vendor_a app.master_records;
  v_vendor_b app.master_records;
  v_shipment_a app.shipment_orders;
  v_shipment_b app.shipment_orders;
  v_cost_a app.shipment_actual_costs;
  v_cost_b app.shipment_actual_costs;
  v_capture_a app.epod_captures;
  v_capture_b app.epod_captures;
  v_config_draft app.config_versions;
  v_file app.files;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000023701', 'admin@acmeopsdash.test'),
    ('00000000-0000-0000-0000-000000023702', 'rep@acmeopsdash.test'),
    ('00000000-0000-0000-0000-000000023704', 'outsider@acmeopsdash.test'),
    ('00000000-0000-0000-0000-000000023705', 'supreme@acmeopsdash.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023705', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeopsdash', 'Acme Ops Dashboard Co', 'idem-acmeopsdash', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeopsdash');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEOPSDASH-CO', 'Acme Ops Dashboard Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSDASH-CO'), 'ACMEOPSDASH-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSDASH-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSDASH-CO'), 'ACMEOPSDASH-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSDASH-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023701', 'admin@acmeopsdash.test', 'Dashboard Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeopsdash.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023701', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023702', 'rep@acmeopsdash.test', 'Dashboard Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeopsdash.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023704', 'outsider@acmeopsdash.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeopsdash.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Dashboard Rep', 'full commercial + ops grants incl OPS:View cost', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000023702', '00000000-0000-0000-0000-000000023701', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Dashboard Outsider', 'sibling team, full grants incl OPS:View cost', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000023704', '00000000-0000-0000-0000-000000023701', 'tester');

  perform app.register_milestone_code('picked_up', 'Picked Up', 'pickup', true, false, false, '00000000-0000-0000-0000-000000023705', 'supreme');

  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000023705', 'supreme');
  v_config_draft := app.create_config_draft('document:epod', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023701', 'admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/png', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000023701', 'admin');
  perform app.publish_document_type_definition(v_config_draft.id, '00000000-0000-0000-0000-000000023701', now(), 'admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Dashboard Test Co', 'Jane Dash', 'jane@dashtest.test', '0811',
    '00000000-0000-0000-0000-000000023702', v_team_a, '00000000-0000-0000-0000-000000023702', 'tester');
  select * into v_lead from app.leads where email = 'jane@dashtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023702', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Dashboard Test Co', 'DSH', '11.111.111.7-777.000',
    jsonb_build_object('line1', 'Jl. Gatot Subroto 7', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023702', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Dash Ops', 'Procurement Lead', 'jane@dashtest.test', '0811', '00000000-0000-0000-0000-000000023702', v_team_a, '00000000-0000-0000-0000-000000023702', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023702', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Dashboard test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Medan', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023702', v_team_a, '00000000-0000-0000-0000-000000023702', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023702', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-DASH-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Medan', '20ft',
    null, null, null, null, 'IDR', 9000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023701', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000023701', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000023702', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000023702', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000023702', 'tester');
  perform app.calculate_margin(v_selection.id, 12000000, 'IDR', 0, '00000000-0000-0000-0000-000000023702', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023702', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight dashboard lane', v_calc_id, 1, 12000000, 0, 0, '00000000-0000-0000-0000-000000023702', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000023702', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000023702', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Dash Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000023702', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000023702', 'rep');

  select * into v_vendor_a from app.create_master_record('vendor', v_tenant1, 'VEND-DASH-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023701', 'admin');
  select * into v_vendor_b from app.create_master_record('vendor', v_tenant1, 'VEND-DASH-2', 'Fabrikam Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023701', 'admin');

  -- Shipment A: planned_delivery_at already in the past -> delayed once a
  -- (non-terminal) milestone event is ingested. Driven to delivered, an ePOD capture
  -- is started but left in draft, an actual cost is approved 30% over estimate, and
  -- one high-severity exception is reported and deliberately left open.
  select * into v_shipment_a from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-dash-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Medan',
    now() - interval '5 days', now() - interval '1 day', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000023702', 'rep'
  );
  v_shipment_a := app.confirm_shipment_order(v_shipment_a.id, v_shipment_a.record_version, '00000000-0000-0000-0000-000000023702', 'rep');
  perform app.ingest_milestone_event(v_shipment_a.id, 'picked_up', now() - interval '4 days', null, null, 'manual', null, null, 'idem-dash-a-picked-up', '00000000-0000-0000-0000-000000023702', 'rep');
  perform app.transition_shipment_order(v_shipment_a.id, 'planned', v_shipment_a.record_version, null, null, 'idem-dash-a-planned', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  perform app.transition_shipment_order(v_shipment_a.id, 'assigned', v_shipment_a.record_version, null, null, 'idem-dash-a-assigned', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  perform app.transition_shipment_order(v_shipment_a.id, 'dispatched', v_shipment_a.record_version, null, null, 'idem-dash-a-dispatched', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  perform app.transition_shipment_order(v_shipment_a.id, 'in_transit', v_shipment_a.record_version, null, null, 'idem-dash-a-intransit', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;
  perform app.transition_shipment_order(v_shipment_a.id, 'delivered', v_shipment_a.record_version, null, 'physical delivery confirmed', 'idem-dash-a-delivered', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_a from app.shipment_orders where id = v_shipment_a.id;

  v_capture_a := app.start_epod_capture(v_tenant1, v_shipment_a.id, null, 'idem-dash-a-cap', '00000000-0000-0000-0000-000000023702', 'rep');

  v_cost_a := app.create_actual_cost_draft(v_tenant1, v_shipment_a.id, 'IDR', 1000000, '00000000-0000-0000-0000-000000023702', 'rep');
  perform app.add_actual_cost_component(v_cost_a.id, 'freight', 'vendor', v_vendor_a.id, null, null, 'Ocean freight', 1, 'shipment', 1300000, null, 0, 'idem-dash-cost-a', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_cost_a from app.shipment_actual_costs where id = v_cost_a.id;
  v_cost_a := app.submit_actual_cost(v_cost_a.id, v_cost_a.record_version, '00000000-0000-0000-0000-000000023702', 'rep');
  perform app.decide_actual_cost(v_cost_a.id, 'approved', null, v_cost_a.record_version, '00000000-0000-0000-0000-000000023702', 'rep');

  perform app.report_exception(v_shipment_a.id, null, 'delay', 'high', 'held at customs, no ETA yet', 'manual', 'idem-dash-a-exc', '00000000-0000-0000-0000-000000023702', 'rep');

  -- Shipment B: planned_delivery_at still in the future -> on_time once a milestone
  -- event is ingested. Driven all the way through a completed ePOD capture, and an
  -- actual cost approved 30% under estimate.
  select * into v_shipment_b from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-dash-b', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Palembang',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: dashboard second fixture', '00000000-0000-0000-0000-000000023702', 'rep'
  );
  v_shipment_b := app.confirm_shipment_order(v_shipment_b.id, v_shipment_b.record_version, '00000000-0000-0000-0000-000000023702', 'rep');
  perform app.ingest_milestone_event(v_shipment_b.id, 'picked_up', now() - interval '1 hour', null, null, 'manual', null, null, 'idem-dash-b-picked-up', '00000000-0000-0000-0000-000000023702', 'rep');
  perform app.transition_shipment_order(v_shipment_b.id, 'planned', v_shipment_b.record_version, null, null, 'idem-dash-b-planned', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  perform app.transition_shipment_order(v_shipment_b.id, 'assigned', v_shipment_b.record_version, null, null, 'idem-dash-b-assigned', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  perform app.transition_shipment_order(v_shipment_b.id, 'dispatched', v_shipment_b.record_version, null, null, 'idem-dash-b-dispatched', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  perform app.transition_shipment_order(v_shipment_b.id, 'in_transit', v_shipment_b.record_version, null, null, 'idem-dash-b-intransit', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  perform app.transition_shipment_order(v_shipment_b.id, 'delivered', v_shipment_b.record_version, null, 'physical delivery confirmed', 'idem-dash-b-delivered', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;

  v_capture_b := app.start_epod_capture(v_tenant1, v_shipment_b.id, null, 'idem-dash-b-cap', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_file from app.initiate_file_upload(v_tenant1, 'epod', 'shipment_order', v_shipment_b.id, 'signature-b.png', 'image/png', 20480, null, false, null, '{}'::uuid[], null, 'idem-dash-b-sig', '00000000-0000-0000-0000-000000023702', 'rep');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023702', 'rep');
  v_capture_b := app.set_epod_evidence(v_capture_b.id, 'Siti Aminah', 'Warehouse Staff', v_file.id, '{}'::uuid[], null, now(), '00000000-0000-0000-0000-000000023702', 'rep');
  v_capture_b := app.submit_epod_capture(v_capture_b.id, v_capture_b.record_version, '00000000-0000-0000-0000-000000023702', 'rep');
  v_capture_b := app.review_epod_capture(v_capture_b.id, 'approved', 'looks good', v_capture_b.record_version, '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;
  v_capture_b := app.complete_epod_capture(v_capture_b.id, v_capture_b.record_version, v_shipment_b.record_version, 'idem-dash-b-complete', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_shipment_b from app.shipment_orders where id = v_shipment_b.id;

  v_cost_b := app.create_actual_cost_draft(v_tenant1, v_shipment_b.id, 'IDR', 1000000, '00000000-0000-0000-0000-000000023702', 'rep');
  perform app.add_actual_cost_component(v_cost_b.id, 'freight', 'vendor', v_vendor_b.id, null, null, 'Ocean freight', 1, 'shipment', 700000, null, 0, 'idem-dash-cost-b', '00000000-0000-0000-0000-000000023702', 'rep');
  select * into v_cost_b from app.shipment_actual_costs where id = v_cost_b.id;
  v_cost_b := app.submit_actual_cost(v_cost_b.id, v_cost_b.record_version, '00000000-0000-0000-0000-000000023702', 'rep');
  perform app.decide_actual_cost(v_cost_b.id, 'approved', null, v_cost_b.record_version, '00000000-0000-0000-0000-000000023702', 'rep');

  perform app.evaluate_billing_readiness(v_job_order.id, null, '00000000-0000-0000-0000-000000023702', 'rep');
end $$;

\echo '>> app.get_ops_dashboard_shipment_status: exactly one delivered (shipment_a) and one epod (shipment_b); authority/record-scope -- the sibling outsider sees zero rows despite full grants'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsdash');
  v_delivered bigint;
  v_epod bigint;
  v_outsider_count integer;
begin
  select shipment_count into v_delivered from app.get_ops_dashboard_shipment_status(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where status = 'delivered';
  select shipment_count into v_epod from app.get_ops_dashboard_shipment_status(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where status = 'epod';
  if coalesce(v_delivered, 0) <> 1 or coalesce(v_epod, 0) <> 1 then
    raise exception 'assertion failed: expected exactly 1 delivered and 1 epod shipment, got %/%', v_delivered, v_epod;
  end if;

  select count(*) into v_outsider_count from app.get_ops_dashboard_shipment_status(v_tenant1, null, null, '00000000-0000-0000-0000-000000023704');
  if v_outsider_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero shipment_status rows despite full grants, got %', v_outsider_count;
  end if;
end $$;

\echo '>> app.get_ops_dashboard_milestone_sla: shipment_a is delayed (planned_delivery_at already passed), shipment_b is on_time'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsdash');
  v_delayed bigint;
  v_on_time bigint;
begin
  select shipment_count into v_delayed from app.get_ops_dashboard_milestone_sla(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where bucket = 'delayed';
  select shipment_count into v_on_time from app.get_ops_dashboard_milestone_sla(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where bucket = 'on_time';
  if coalesce(v_delayed, 0) <> 1 or coalesce(v_on_time, 0) <> 1 then
    raise exception 'assertion failed: expected exactly 1 delayed and 1 on_time shipment, got %/%', v_delayed, v_on_time;
  end if;
end $$;

\echo '>> app.get_ops_dashboard_exception_queue: exactly one open high-severity exception (shipment_a)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsdash');
  v_high bigint;
begin
  select exception_count into v_high from app.get_ops_dashboard_exception_queue(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where severity = 'high';
  if coalesce(v_high, 0) <> 1 then
    raise exception 'assertion failed: expected exactly 1 open high-severity exception, got %', v_high;
  end if;
end $$;

\echo '>> app.get_ops_dashboard_epod_completion: one draft (shipment_a) and one completed (shipment_b) capture'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsdash');
  v_draft bigint;
  v_completed bigint;
begin
  select capture_count into v_draft from app.get_ops_dashboard_epod_completion(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where status = 'draft';
  select capture_count into v_completed from app.get_ops_dashboard_epod_completion(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where status = 'completed';
  if coalesce(v_draft, 0) <> 1 or coalesce(v_completed, 0) <> 1 then
    raise exception 'assertion failed: expected exactly 1 draft and 1 completed ePOD capture, got %/%', v_draft, v_completed;
  end if;
end $$;

\echo '>> app.get_ops_dashboard_cost_variance: shipment_a is 30%% over budget, shipment_b is 30%% under budget; masked entirely (variance_masked=true, avg_variance_pct=null) once rep''s own role is downgraded to drop OPS:View cost -- rep still owns every row (record-scope unaffected), only the masking gate changes'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsdash');
  v_rep_role_id uuid := (select id from app.roles where tenant_id = v_tenant1 and name = 'Dashboard Rep');
  v_downgrade_draft app.role_versions;
  v_over_count bigint;
  v_over_pct numeric;
  v_under_count bigint;
  v_under_pct numeric;
  v_masked boolean;
  v_masked_pct numeric;
  v_masked_count integer;
begin
  select shipment_count, avg_variance_pct into v_over_count, v_over_pct from app.get_ops_dashboard_cost_variance(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where bucket = 'over_budget';
  select shipment_count, avg_variance_pct into v_under_count, v_under_pct from app.get_ops_dashboard_cost_variance(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where bucket = 'under_budget';
  if coalesce(v_over_count, 0) <> 1 or v_over_pct <> 30.00 then
    raise exception 'assertion failed: expected exactly 1 shipment 30%% over budget, got count=%/pct=%', v_over_count, v_over_pct;
  end if;
  if coalesce(v_under_count, 0) <> 1 or v_under_pct <> -30.00 then
    raise exception 'assertion failed: expected exactly 1 shipment 30%% under budget, got count=%/pct=%', v_under_count, v_under_pct;
  end if;

  -- app.evaluate_permission always joins to each role's *currently published*
  -- version, so publishing a new one for the same role (never reassigning rep to a
  -- different role) takes effect immediately -- the same "role permissions changed
  -- after the fact" scenario a real tenant admin could trigger at any time. rep
  -- remains the owner_user_id of every row above (stamped once, at creation, never
  -- revisited), so app.can_access_record still admits them.
  v_downgrade_draft := app.create_role_version(v_rep_role_id, 'tester');
  perform app.set_role_version_permissions(
    v_downgrade_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_downgrade_draft.id, now(), 'tester');

  select count(*) into v_masked_count from app.get_ops_dashboard_cost_variance(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702');
  select bool_and(variance_masked), max(avg_variance_pct) into v_masked, v_masked_pct from app.get_ops_dashboard_cost_variance(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702');
  if v_masked_count <> 2 or not v_masked or v_masked_pct is not null then
    raise exception 'assertion failed: expected rep (now downgraded) to still see 2 rows, all variance_masked=true and avg_variance_pct=null, got count=%/masked=%/pct=%', v_masked_count, v_masked, v_masked_pct;
  end if;
end $$;

\echo '>> app.get_ops_dashboard_billing_readiness: exactly one not_ready Job Order (billing_profile_missing, shipment/document/exception blockers still outstanding); schema-privilege defense in depth (anon holds zero EXECUTE on all 6 new functions)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsdash');
  v_not_ready bigint;
  v_denied_count integer;
begin
  select job_count into v_not_ready from app.get_ops_dashboard_billing_readiness(v_tenant1, null, null, '00000000-0000-0000-0000-000000023702') where bucket = 'not_ready';
  if coalesce(v_not_ready, 0) <> 1 then
    raise exception 'assertion failed: expected exactly 1 not_ready Job Order, got %', v_not_ready;
  end if;

  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in ('get_ops_dashboard_shipment_status', 'get_ops_dashboard_milestone_sla', 'get_ops_dashboard_exception_queue', 'get_ops_dashboard_epod_completion', 'get_ops_dashboard_cost_variance', 'get_ops_dashboard_billing_readiness')
    and grantee = 'anon';
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants on the 6 new OPS-182 functions, found %', v_denied_count;
  end if;
end $$;
