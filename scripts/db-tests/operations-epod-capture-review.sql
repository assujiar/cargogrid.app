-- Real, executable test evidence for OPS-177 (ePOD Capture and Review, CG-S8-OPS-011)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a Supreme Admin, a rep (OPS full), a restricted actor (OPS:View only), a sibling-team outsider, one confirmed Job Order, and two Shipment Orders driven to delivered plus one left at confirmed (not-delivered probe)'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
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
  v_vendor app.master_records;
  v_vendor_b app.master_records;
  v_shipment_a app.shipment_orders;
  v_shipment_b app.shipment_orders;
  v_shipment_notdelivered app.shipment_orders;
  v_pod_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000023201', 'admin@acmeepod.test'),
    ('00000000-0000-0000-0000-000000023202', 'repa@acmeepod.test'),
    ('00000000-0000-0000-0000-000000023203', 'viewer@acmeepod.test'),
    ('00000000-0000-0000-0000-000000023204', 'outsider@acmeepod.test'),
    ('00000000-0000-0000-0000-000000023206', 'supreme@acmeepod.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023206', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeepod', 'Acme Epod Co', 'idem-acmeepod', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeepod');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEEPOD-CO', 'Acme Epod Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEEPOD-CO'), 'ACMEEPOD-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEEPOD-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEEPOD-CO'), 'ACMEEPOD-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEEPOD-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023201', 'admin@acmeepod.test', 'Epod Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeepod.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023201', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023202', 'repa@acmeepod.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeepod.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023203', 'viewer@acmeepod.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmeepod.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023204', 'outsider@acmeepod.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeepod.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Epod Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000023202', '00000000-0000-0000-0000-000000023201', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Epod Ops Viewer', 'OPS:View only, no Edit/Create', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000023203', '00000000-0000-0000-0000-000000023203', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Epod Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000023204', '00000000-0000-0000-0000-000000023201', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Epod Test Co', 'Jane Epod', 'jane@epodtest.test', '0811',
    '00000000-0000-0000-0000-000000023202', v_team_a, '00000000-0000-0000-0000-000000023202', 'tester');
  select * into v_lead from app.leads where email = 'jane@epodtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023202', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Epod Test Co', 'ETC', '11.111.111.3-333.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 3', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023202', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Epod Ops', 'Procurement Lead', 'jane@epodtest.test', '0811', '00000000-0000-0000-0000-000000023202', v_team_a, '00000000-0000-0000-0000-000000023202', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023202', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Epod test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023202', v_team_a, '00000000-0000-0000-0000-000000023202', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023202', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-EPOD-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023201', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000023201', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000023202', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000023202', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000023202', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000023202', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023202', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight epod lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000023202', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000023202', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000023202', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Epod Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000023202', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000023202', 'rep');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-EPOD-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023201', 'admin');
  select * into v_vendor_b from app.create_master_record('vendor', v_tenant1, 'VEND-EPOD-2', 'Fabrikam Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023201', 'admin');

  select * into v_shipment_a from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-epod-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() - interval '2 days', now() - interval '1 hours', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000023202', 'rep'
  );
  select * into v_shipment_a from app.confirm_shipment_order(v_shipment_a.id, v_shipment_a.record_version, '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'planned', v_shipment_a.record_version, null, null, 'idem-epod-a-planned', '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'assigned', v_shipment_a.record_version, null, null, 'idem-epod-a-assigned', '00000000-0000-0000-0000-000000023202', 'rep');
  perform app.assign_resource(v_shipment_a.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'dispatched', v_shipment_a.record_version, null, null, 'idem-epod-a-dispatched', '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'in_transit', v_shipment_a.record_version, null, null, 'idem-epod-a-intransit', '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'delivered', v_shipment_a.record_version, null, 'physical delivery confirmed', 'idem-epod-a-delivered', '00000000-0000-0000-0000-000000023202', 'rep');

  select * into v_shipment_b from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-epod-b', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Bandung',
    now() - interval '2 days', now() - interval '1 hours', null, null, null, null, null, null, 'split: epod second fixture', '00000000-0000-0000-0000-000000023202', 'rep'
  );
  select * into v_shipment_b from app.confirm_shipment_order(v_shipment_b.id, v_shipment_b.record_version, '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'planned', v_shipment_b.record_version, null, null, 'idem-epod-b-planned', '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'assigned', v_shipment_b.record_version, null, null, 'idem-epod-b-assigned', '00000000-0000-0000-0000-000000023202', 'rep');
  perform app.assign_resource(v_shipment_b.id, 'vendor', v_vendor_b.id, '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'dispatched', v_shipment_b.record_version, null, null, 'idem-epod-b-dispatched', '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'in_transit', v_shipment_b.record_version, null, null, 'idem-epod-b-intransit', '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'delivered', v_shipment_b.record_version, null, 'physical delivery confirmed', 'idem-epod-b-delivered', '00000000-0000-0000-0000-000000023202', 'rep');

  select * into v_shipment_notdelivered from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-epod-notdelivered', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Cirebon',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: epod notdelivered fixture', '00000000-0000-0000-0000-000000023202', 'rep'
  );
  select * into v_shipment_notdelivered from app.confirm_shipment_order(v_shipment_notdelivered.id, v_shipment_notdelivered.record_version, '00000000-0000-0000-0000-000000023202', 'rep');

  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000023206', 'supreme');
  v_pod_draft := app.create_config_draft('document:epod', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023201', 'admin');
  perform app.set_config_items(v_pod_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000023201', 'admin');
  perform app.publish_document_type_definition(v_pod_draft.id, '00000000-0000-0000-0000-000000023201', now(), 'admin');
end $$;

\echo '>> app.start_epod_capture: authority/record-scope gated, requires status=delivered, idempotent'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-epod-a');
  v_shipment_notdelivered_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-epod-notdelivered');
  v_capture1 app.epod_captures;
  v_capture2 app.epod_captures;
begin
  begin
    perform app.start_epod_capture((select tenant_id from app.shipment_orders where id = v_shipment_a_id), v_shipment_a_id, null, 'idem-epod-a-cap', '00000000-0000-0000-0000-000000023203', 'viewer');
    raise exception 'assertion failed: expected OPS:View-only viewer to be denied OPS:Create';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.start_epod_capture((select tenant_id from app.shipment_orders where id = v_shipment_notdelivered_id), v_shipment_notdelivered_id, null, 'idem-epod-notdelivered-cap', '00000000-0000-0000-0000-000000023202', 'rep');
    raise exception 'assertion failed: expected epod_shipment_not_delivered for a non-delivered shipment';
  exception
    when check_violation then
      if sqlerrm !~ 'epod_shipment_not_delivered' then raise; end if;
  end;

  v_capture1 := app.start_epod_capture((select tenant_id from app.shipment_orders where id = v_shipment_a_id), v_shipment_a_id, null, 'idem-epod-a-cap', '00000000-0000-0000-0000-000000023202', 'rep');
  v_capture2 := app.start_epod_capture((select tenant_id from app.shipment_orders where id = v_shipment_a_id), v_shipment_a_id, null, 'idem-epod-a-cap', '00000000-0000-0000-0000-000000023202', 'rep');
  if v_capture1.id <> v_capture2.id then
    raise exception 'assertion failed: expected repeated start with the same idempotency_key to be idempotent';
  end if;
  if v_capture1.status <> 'draft' or v_capture1.version_number <> 1 then
    raise exception 'assertion failed: expected a fresh draft at version 1';
  end if;
end $$;

\echo '>> app.set_epod_evidence / app.submit_epod_capture: file tenant/record mismatch rejected, missing receiver/evidence rejected, unsafe (unscanned) evidence rejected, geolocation validated via PLT-134''s own convention, then a clean submission succeeds'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-epod-a');
  v_tenant1 uuid := (select tenant_id from app.shipment_orders where id = v_shipment_a_id);
  v_capture app.epod_captures;
  v_signature app.files;
  v_wrong_record_file app.files;
  v_updated app.epod_captures;
begin
  select * into v_capture from app.epod_captures where shipment_order_id = v_shipment_a_id;

  select * into v_signature from app.initiate_file_upload(
    v_tenant1, 'epod', 'shipment_order', v_shipment_a_id, 'signature-a.png', 'image/jpeg', 20480, null, false, null, '{}'::uuid[], null, 'idem-epod-a-sig', '00000000-0000-0000-0000-000000023202', 'rep'
  );

  select * into v_wrong_record_file from app.initiate_file_upload(
    v_tenant1, 'epod', 'shipment_order', (select id from app.shipment_orders where idempotency_key = 'idem-epod-b'), 'signature-b.png', 'image/jpeg', 20480, null, false, null, '{}'::uuid[], null, 'idem-epod-b-sig', '00000000-0000-0000-0000-000000023202', 'rep'
  );

  begin
    perform app.set_epod_evidence(v_capture.id, 'Budi Santoso', 'Warehouse Staff', v_wrong_record_file.id, '{}'::uuid[], null, now(), '00000000-0000-0000-0000-000000023202', 'rep');
    raise exception 'assertion failed: expected epod_evidence_file_mismatch for a signature belonging to a different shipment';
  exception
    when check_violation then
      if sqlerrm !~ 'epod_evidence_file_mismatch' then raise; end if;
  end;

  begin
    perform app.set_epod_evidence(v_capture.id, 'Budi Santoso', 'Warehouse Staff', null, '{}'::uuid[], jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(200, 10)), now(), '00000000-0000-0000-0000-000000023202', 'rep');
    raise exception 'assertion failed: expected spatial_coordinate_out_of_range for an out-of-range longitude';
  exception
    when check_violation then
      if sqlerrm !~ 'spatial_coordinate_out_of_range' then raise; end if;
  end;

  begin
    perform app.submit_epod_capture(v_capture.id, v_capture.record_version, '00000000-0000-0000-0000-000000023202', 'rep');
    raise exception 'assertion failed: expected epod_missing_receiver before any evidence is set';
  exception
    when check_violation then
      if sqlerrm !~ 'epod_missing_receiver' then raise; end if;
  end;

  select * into v_updated from app.set_epod_evidence(
    v_capture.id, 'Budi Santoso', 'Warehouse Staff', v_signature.id, '{}'::uuid[],
    jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.845599, -6.208763)), now(), '00000000-0000-0000-0000-000000023202', 'rep'
  );
  if v_updated.receiver_name <> 'Budi Santoso' or v_updated.delivery_geog is null then
    raise exception 'assertion failed: expected evidence to be set including a valid geography point';
  end if;

  begin
    perform app.submit_epod_capture(v_updated.id, v_updated.record_version, '00000000-0000-0000-0000-000000023202', 'rep');
    raise exception 'assertion failed: expected epod_unsafe_evidence while the signature file is still pending scan';
  exception
    when check_violation then
      if sqlerrm !~ 'epod_unsafe_evidence' then raise; end if;
  end;

  perform app.record_file_scan_result(v_signature.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023202', 'rep');
  select * into v_updated from app.epod_captures where id = v_capture.id;
  v_updated := app.submit_epod_capture(v_updated.id, v_updated.record_version, '00000000-0000-0000-0000-000000023202', 'rep');
  if v_updated.status <> 'submitted' then
    raise exception 'assertion failed: expected the capture to submit once evidence is complete and clean-scanned';
  end if;
end $$;

\echo '>> app.review_epod_capture / app.revise_epod_capture / app.complete_epod_capture: revision preserves full history as a new version, approval + completion transitions the shipment to epod via the existing generic transition, completed evidence is immutable'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-epod-a');
  v_capture app.epod_captures;
  v_reviewed app.epod_captures;
  v_revised app.epod_captures;
  v_signature app.files;
  v_approved app.epod_captures;
  v_completed app.epod_captures;
  v_shipment app.shipment_orders;
  v_history_count integer;
begin
  select * into v_capture from app.epod_captures where shipment_order_id = v_shipment_a_id and is_latest_version;

  begin
    perform app.review_epod_capture(v_capture.id, 'revision_requested', null, v_capture.record_version, '00000000-0000-0000-0000-000000023202', 'rep');
    raise exception 'assertion failed: expected epod_revision_reason_required with no notes';
  exception
    when check_violation then
      if sqlerrm !~ 'epod_revision_reason_required' then raise; end if;
  end;

  v_reviewed := app.review_epod_capture(v_capture.id, 'revision_requested', 'signature is illegible, please recapture', v_capture.record_version, '00000000-0000-0000-0000-000000023202', 'rep');
  if v_reviewed.status <> 'revision_requested' then
    raise exception 'assertion failed: expected revision_requested status';
  end if;

  v_revised := app.revise_epod_capture(v_reviewed.id, '00000000-0000-0000-0000-000000023202', 'rep');
  if v_revised.version_number <> 2 or v_revised.version_group_id <> v_reviewed.version_group_id or v_revised.status <> 'draft' then
    raise exception 'assertion failed: expected a new version 2 draft in the same version group';
  end if;
  select * into v_reviewed from app.epod_captures where id = v_reviewed.id;
  if v_reviewed.is_latest_version or v_reviewed.review_notes is null then
    raise exception 'assertion failed: expected the prior rejected version to remain, no longer latest, with its own review_notes intact (full history preserved)';
  end if;

  select * into v_signature from app.initiate_file_upload(
    v_revised.tenant_id, 'epod', 'shipment_order', v_shipment_a_id, 'signature-a-v2.png', 'image/jpeg', 20480, null, false, null, '{}'::uuid[], null, 'idem-epod-a-sig-v2', '00000000-0000-0000-0000-000000023202', 'rep'
  );
  perform app.record_file_scan_result(v_signature.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023202', 'rep');
  v_revised := app.set_epod_evidence(v_revised.id, 'Budi Santoso', 'Warehouse Staff', v_signature.id, '{}'::uuid[], null, now(), '00000000-0000-0000-0000-000000023202', 'rep');
  v_revised := app.submit_epod_capture(v_revised.id, v_revised.record_version, '00000000-0000-0000-0000-000000023202', 'rep');
  v_approved := app.review_epod_capture(v_revised.id, 'approved', 'looks good', v_revised.record_version, '00000000-0000-0000-0000-000000023202', 'rep');

  select * into v_shipment from app.shipment_orders so where so.id = v_shipment_a_id;
  v_completed := app.complete_epod_capture(v_approved.id, v_approved.record_version, v_shipment.record_version, 'idem-epod-a-complete', '00000000-0000-0000-0000-000000023202', 'rep');
  if v_completed.status <> 'completed' then
    raise exception 'assertion failed: expected the capture to complete';
  end if;

  select * into v_shipment from app.shipment_orders so where so.id = v_shipment_a_id;
  if v_shipment.status <> 'epod' then
    raise exception 'assertion failed: expected the shipment to transition to epod via the existing generic transition, got %', v_shipment.status;
  end if;

  begin
    perform app.set_epod_evidence(v_completed.id, 'Someone Else', null, null, '{}'::uuid[], null, now(), '00000000-0000-0000-0000-000000023202', 'rep');
    raise exception 'assertion failed: expected completed evidence to be immutable';
  exception
    when check_violation then
      if sqlerrm !~ 'invalid_transition' then raise; end if;
  end;

  select count(*) into v_history_count from app.epod_captures where version_group_id = v_completed.version_group_id;
  if v_history_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 preserved versions in this capture''s own lineage, found %', v_history_count;
  end if;
end $$;

\echo '>> RLS: record-scope isolation on app.epod_captures; cross-tenant isolation; schema-privilege defense in depth (anon holds zero EXECUTE on all 7 new functions)'
do $$
declare
  v_shipment_b_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-epod-b');
  v_count integer;
  v_denied_count integer;
begin
  perform app.start_epod_capture((select tenant_id from app.shipment_orders where id = v_shipment_b_id), v_shipment_b_id, null, 'idem-epod-b-cap', '00000000-0000-0000-0000-000000023202', 'rep');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023202", "role": "authenticated"}';
  select count(*) into v_count from app.epod_captures where shipment_order_id = v_shipment_b_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owning rep to see exactly 1 ePOD capture for shipment_b via RLS, got %', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023204", "role": "authenticated"}';
  select count(*) into v_count from app.epod_captures where shipment_order_id = v_shipment_b_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero ePOD captures for shipment_b via RLS, got %', v_count;
  end if;
  reset role;

  begin
    perform app.start_epod_capture((select tenant_id from app.shipment_orders where id = v_shipment_b_id), v_shipment_b_id, null, 'idem-epod-b-cap-outsider', '00000000-0000-0000-0000-000000023204', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied starting a capture despite full OPS grants (record scope)';
  exception
    when insufficient_privilege then null;
  end;

  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in (
      'start_epod_capture', 'set_epod_evidence', 'submit_epod_capture', 'review_epod_capture',
      'revise_epod_capture', 'complete_epod_capture', 'get_epod_capture_history'
    )
    and grantee = 'anon';
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants on the 7 new OPS-177 functions, found %', v_denied_count;
  end if;
end $$;

\echo '>> audit trail: every mutation self-captures a canonical app.audit_logs entry'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs
  where action in ('start_epod_capture', 'set_epod_evidence', 'submit_epod_capture', 'review_epod_capture', 'revise_epod_capture', 'complete_epod_capture');
  if v_count < 6 then
    raise exception 'assertion failed: expected at least 6 persisted OPS-177 audit events, found %', v_count;
  end if;
end $$;
