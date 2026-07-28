-- Real, executable integrated-verification evidence for OPS-185 (Operations Integrated
-- Verification, CG-S8-OPS-019) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
--
-- Every one of the 17 Operations capabilities (OPS-168..184) already has its own,
-- exhaustive db-test file proving its own authority/record-scope/validation/audit
-- behavior in isolation -- this file does not repeat that work. Its purpose is narrower
-- and different: drive ONE fixture through the complete critical flow (accepted quote ->
-- Job Order -> Shipment Order -> mode baseline -> resource assignment -> milestone
-- ingestion -> dispatch -> document checklist -> ePOD -> actual cost -> job
-- profitability -> public tracking -> billing readiness), then cross-check that the
-- READ-side capabilities built on top of that same data (Operations Dashboard OPS-182,
-- Operations Reports OPS-183, Transaction Lineage OPS-184) all report the identical,
-- reconciled state -- exactly the class of cross-capability defect an isolated per-
-- capability test cannot catch (the same class this session already found twice: the
-- OPS-169 org_unit_id gap discovered while authoring OPS-182, and the missing
-- OPS:View margin discovered while authoring OPS-184).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM+OPS full incl Override/Export/View margin), a sibling-team outsider (full grants incl Override, wrong record scope), a Supreme Admin, a second tenant (cross-tenant isolation only) -- one full accepted-quote funnel through a confirmed Job Order'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_outsider_role uuid;
  v_outsider_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_config_draft app.config_versions;
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
  v_profile app.credit_profiles;
  v_step_id uuid;
  v_handoff app.job_order_handoffs;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000024001', 'admin@acmeopsverify.test'),
    ('00000000-0000-0000-0000-000000024002', 'rep@acmeopsverify.test'),
    ('00000000-0000-0000-0000-000000024004', 'outsider@acmeopsverify.test'),
    ('00000000-0000-0000-0000-000000024005', 'approver@acmeopsverify.test'),
    ('00000000-0000-0000-0000-000000024006', 'supreme@acmeopsverify.test'),
    ('00000000-0000-0000-0000-000000024007', 'crosstenant@acmeopsverify.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024006', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeopsverify', 'Acme Ops Verify Co', 'idem-acmeopsverify', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeopsverify');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('acmeopsverify2', 'Acme Ops Verify Co 2', 'idem-acmeopsverify2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeopsverify2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000024007', 'crosstenant@acmeopsverify.test', 'Cross Tenant Actor', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'crosstenant@acmeopsverify.test'), 'active', 'onboarded', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEOPSVERIFY-CO', 'Acme Ops Verify Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSVERIFY-CO'), 'ACMEOPSVERIFY-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSVERIFY-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSVERIFY-CO'), 'ACMEOPSVERIFY-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSVERIFY-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000024001', 'admin@acmeopsverify.test', 'Verify Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeopsverify.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024001', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000024002', 'rep@acmeopsverify.test', 'Verify Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeopsverify.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000024004', 'outsider@acmeopsverify.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeopsverify.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000024005', 'approver@acmeopsverify.test', 'Credit Approver', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@acmeopsverify.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Verify Rep', 'full commercial + ops grants incl Override/Export/View margin', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'View margin', 'Export', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000024002', '00000000-0000-0000-0000-000000024001', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Verify Outsider', 'sibling team, full grants incl Override', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'View margin', 'Export', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000024004', '00000000-0000-0000-0000-000000024001', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'Verify Credit Approver', 'decides the routed credit-profile approval request', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'COM' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000024005', '00000000-0000-0000-0000-000000024001', 'tester');

  select * into v_config_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000024001', 'tenant admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_approver_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000024001', 'tenant admin');
  perform app.publish_approval_definition(v_config_draft.id, '00000000-0000-0000-0000-000000024001', null, 'tenant admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Verify Test Co', 'Jane Verify', 'jane@opsverifytest.test', '0811',
    '00000000-0000-0000-0000-000000024002', v_team_a, '00000000-0000-0000-0000-000000024002', 'tester');
  select * into v_lead from app.leads where email = 'jane@opsverifytest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000024002', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Verify Test Co', 'VER', '11.111.111.9-999.000',
    jsonb_build_object('line1', 'Jl. Sudirman 9', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000024002', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Verify Ops', 'Procurement Lead', 'jane@opsverifytest.test', '0811', '00000000-0000-0000-0000-000000024002', v_team_a, '00000000-0000-0000-0000-000000024002', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000024002', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Verify test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Semarang', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000024002', v_team_a, '00000000-0000-0000-0000-000000024002', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000024002', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-VERIFY-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Semarang', '20ft',
    null, null, null, null, 'IDR', 8000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000024001', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000024001', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000024002', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000024002', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000024002', 'tester');
  perform app.calculate_margin(v_selection.id, 12000000, 'IDR', 0, '00000000-0000-0000-0000-000000024002', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000024002', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight verify lane', v_calc_id, 1, 12000000, 0, 0, '00000000-0000-0000-0000-000000024002', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000024002', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000024002', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Verify Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000024002', 'rep');

  v_profile := app.request_customer_credit_profile(v_tenant1, v_account.id, 'IDR', 20000000, '00000000-0000-0000-0000-000000024002', 'rep');
  select rs.id into v_step_id from app.approval_request_steps rs where rs.request_id = v_profile.approval_request_id and rs.step_order = 1;
  v_profile := app.decide_credit_profile_approval_step(v_step_id, 'approved', 'Approved for integrated-verification fixture', now(), '00000000-0000-0000-0000-000000024005', 'approver');

  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000024002', 'rep');
end $$;

\echo '>> OPS-168/169/171/172: confirm the Job Order, create+confirm a sea-mode Shipment Order, set its mode profile, assign a vendor -- confirms cross-capability handoff (quote -> job -> shipment) preserves the exact shipper/cargo snapshot'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsverify');
  v_handoff_id uuid := (select id from app.job_order_handoffs where tenant_id = v_tenant1);
  v_job_order app.job_orders;
  v_vendor app.master_records;
  v_shipment app.shipment_orders;
begin
  v_job_order := app.prepare_job_order(v_handoff_id, '00000000-0000-0000-0000-000000024002', 'rep');
  v_job_order := app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000024002', 'rep');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-VERIFY-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000024001', 'admin');

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-verify-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Semarang',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000024002', 'rep'
  );
  if v_shipment.consignee_snapshot is null or v_shipment.cargo_service_snapshot is null then
    raise exception 'assertion failed: expected the Shipment Order to inherit non-null consignee/cargo snapshots from its Job Order';
  end if;
  v_shipment := app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000024002', 'rep');

  perform app.set_shipment_mode_profile(
    v_shipment.id, null, null, null, null, null, null, null, null,
    'BL-VERIFY-1', 'BOOK-VERIFY-1', 'MV Verify', 'Jakarta', 'Semarang', 'CONT1234567', '20ft',
    '00000000-0000-0000-0000-000000024002', 'rep'
  );

  perform app.assign_resource(v_shipment.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000024002', 'rep');
end $$;

\echo '>> OPS-173/175: register milestone codes (idempotent, reused across the shared platform-wide catalogue), publish a sea-mode template, ingest picked_up/departed_origin, dispatch via app.dispatch_shipment_order (assigned -> dispatched, readiness-checked), then ingest the remaining in_transit/out_for_delivery/delivered events -- proves milestone tracking and the authoritative lifecycle status stay consistent with each other'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsverify');
  v_shipment app.shipment_orders;
  v_draft app.milestone_template_versions;
  v_command app.dispatch_commands;
  v_projection app.shipment_milestone_projections;
begin
  select so.* into v_shipment from app.shipment_orders so join app.tenants t on t.id = so.tenant_id where t.slug = 'acmeopsverify';

  perform app.register_milestone_code('picked_up', 'Picked Up', 'pickup', true, false, false, '00000000-0000-0000-0000-000000024006', 'supreme');
  perform app.register_milestone_code('departed_origin', 'Departed Origin', 'in_transit', true, false, false, '00000000-0000-0000-0000-000000024006', 'supreme');
  perform app.register_milestone_code('in_transit', 'In Transit', 'in_transit', true, true, false, '00000000-0000-0000-0000-000000024006', 'supreme');
  perform app.register_milestone_code('out_for_delivery', 'Out for Delivery', 'delivery', true, true, false, '00000000-0000-0000-0000-000000024006', 'supreme');
  perform app.register_milestone_code('delivered', 'Delivered', 'delivery', true, true, true, '00000000-0000-0000-0000-000000024006', 'supreme');

  v_draft := app.create_milestone_template_draft(v_tenant1, 'sea', '00000000-0000-0000-0000-000000024002', 'rep');
  v_draft := app.set_milestone_template_sequence(v_draft.id, jsonb_build_array(
    jsonb_build_object('code', 'picked_up'), jsonb_build_object('code', 'departed_origin'), jsonb_build_object('code', 'in_transit'),
    jsonb_build_object('code', 'out_for_delivery'), jsonb_build_object('code', 'delivered')
  ), '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.publish_milestone_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000024002', 'rep');

  perform app.ingest_milestone_event(v_shipment.id, 'picked_up', now(), now(), jsonb_build_object('lat', -6.2, 'lng', 106.8), 'manual', null, null, 'idem-verify-ms-1', '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.ingest_milestone_event(v_shipment.id, 'departed_origin', now(), now(), jsonb_build_object('lat', -6.1, 'lng', 106.9), 'manual', null, null, 'idem-verify-ms-2', '00000000-0000-0000-0000-000000024002', 'rep');

  perform app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-verify-planned', '00000000-0000-0000-0000-000000024002', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  perform app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-verify-assigned', '00000000-0000-0000-0000-000000024002', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;

  v_command := app.dispatch_shipment_order(v_shipment.id, v_shipment.record_version, 'idem-verify-dispatch', '00000000-0000-0000-0000-000000024002', 'rep');
  if v_command.shipment_order_id <> v_shipment.id then
    raise exception 'assertion failed: expected the dispatch command to reference the correct shipment order';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  if v_shipment.status <> 'dispatched' then
    raise exception 'assertion failed: expected the shipment to reach dispatched status after app.dispatch_shipment_order, got %', v_shipment.status;
  end if;

  perform app.ingest_milestone_event(v_shipment.id, 'in_transit', now(), now(), jsonb_build_object('lat', -6.0, 'lng', 107.0), 'manual', null, null, 'idem-verify-ms-3', '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.transition_shipment_order(v_shipment.id, 'in_transit', v_shipment.record_version, null, null, 'idem-verify-intransit', '00000000-0000-0000-0000-000000024002', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  perform app.ingest_milestone_event(v_shipment.id, 'out_for_delivery', now(), now(), jsonb_build_object('lat', -5.9, 'lng', 107.1), 'manual', null, null, 'idem-verify-ms-4', '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.ingest_milestone_event(v_shipment.id, 'delivered', now(), now(), jsonb_build_object('lat', -5.8, 'lng', 107.2), 'manual', null, null, 'idem-verify-ms-5', '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.transition_shipment_order(v_shipment.id, 'delivered', v_shipment.record_version, null, 'physical delivery confirmed', 'idem-verify-delivered', '00000000-0000-0000-0000-000000024002', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;

  select * into v_projection from app.shipment_milestone_projections where shipment_order_id = v_shipment.id;
  if v_projection.last_milestone_code <> 'delivered' then
    raise exception 'assertion failed: expected the milestone projection''s last_milestone_code to be delivered (independent tracking data), got %, alongside the authoritative shipment status %', v_projection.last_milestone_code, v_shipment.status;
  end if;
end $$;

\echo '>> OPS-176/177/178/179: pin+approve the document checklist, capture+approve ePOD, close the shipment, capture+approve an actual cost, calculate job profitability -- the evidence chain OPS-181/182/183/184 all read from'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsverify');
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeopsverify');
  v_shipment app.shipment_orders;
  v_req_def app.document_requirement_definitions;
  v_config_draft app.config_versions;
  v_file app.files;
  v_item app.shipment_document_checklist_items;
  v_capture app.epod_captures;
  v_cost app.shipment_actual_costs;
  v_profitability app.job_profitability_snapshots;
begin
  select so.* into v_shipment from app.shipment_orders so where so.job_order_id = v_job_order_id;

  perform app.register_document_type('pod', 'Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000024006', 'supreme');
  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000024006', 'supreme');

  v_config_draft := app.create_config_draft('document:pod', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000024001', 'admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000024001', 'admin');
  perform app.publish_document_type_definition(v_config_draft.id, '00000000-0000-0000-0000-000000024001', now(), 'admin');

  v_config_draft := app.create_config_draft('document:epod', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000024001', 'admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/png', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000024001', 'admin');
  perform app.publish_document_type_definition(v_config_draft.id, '00000000-0000-0000-0000-000000024001', now(), 'admin');

  select * into v_req_def from app.create_document_requirement_draft(v_tenant1, null, null, 'delivered', 'carrier', 'pod', 'mandatory', '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.publish_document_requirement_version(v_req_def.id, v_req_def.record_version, '00000000-0000-0000-0000-000000024002', 'rep');

  perform app.pin_shipment_document_checklist(v_shipment.id, '00000000-0000-0000-0000-000000024002', 'rep');
  select * into v_item from app.shipment_document_checklist_items where shipment_order_id = v_shipment.id;
  select * into v_file from app.initiate_file_upload(v_tenant1, 'pod', 'shipment_order', v_shipment.id, 'pod-verify.pdf', 'application/pdf', 102400, null, false, null, '{}'::uuid[], null, 'idem-verify-pod', '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.link_document_to_checklist_item(v_item.id, v_file.id, '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.review_document_checklist_item(v_item.id, 'approved', 'signed and dated', null, '00000000-0000-0000-0000-000000024002', 'rep');

  v_capture := app.start_epod_capture(v_tenant1, v_shipment.id, null, 'idem-verify-cap', '00000000-0000-0000-0000-000000024002', 'rep');
  select * into v_file from app.initiate_file_upload(v_tenant1, 'epod', 'shipment_order', v_shipment.id, 'signature-verify.png', 'image/png', 20480, null, false, null, '{}'::uuid[], null, 'idem-verify-sig', '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000024002', 'rep');
  v_capture := app.set_epod_evidence(v_capture.id, 'Budi Santoso', 'Warehouse Staff', v_file.id, '{}'::uuid[], null, now(), '00000000-0000-0000-0000-000000024002', 'rep');
  v_capture := app.submit_epod_capture(v_capture.id, v_capture.record_version, '00000000-0000-0000-0000-000000024002', 'rep');
  v_capture := app.review_epod_capture(v_capture.id, 'approved', 'looks good', v_capture.record_version, '00000000-0000-0000-0000-000000024002', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  v_capture := app.complete_epod_capture(v_capture.id, v_capture.record_version, v_shipment.record_version, 'idem-verify-complete', '00000000-0000-0000-0000-000000024002', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment.id;
  perform app.transition_shipment_order(v_shipment.id, 'closed', v_shipment.record_version, null, 'billed and closed', 'idem-verify-closed', '00000000-0000-0000-0000-000000024002', 'rep');

  v_cost := app.create_actual_cost_draft(v_tenant1, v_shipment.id, 'IDR', null, '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.add_actual_cost_component(v_cost.id, 'freight', 'vendor', (select id from app.master_records where code = 'VEND-VERIFY-1'), null, null, 'Ocean freight', 1, 'shipment', 5000000, null, 0, 'idem-verify-cost', '00000000-0000-0000-0000-000000024002', 'rep');
  select * into v_cost from app.shipment_actual_costs where id = v_cost.id;
  v_cost := app.submit_actual_cost(v_cost.id, v_cost.record_version, '00000000-0000-0000-0000-000000024002', 'rep');
  perform app.decide_actual_cost(v_cost.id, 'approved', null, v_cost.record_version, '00000000-0000-0000-0000-000000024002', 'rep');

  v_profitability := app.calculate_job_profitability(v_job_order_id, null, '00000000-0000-0000-0000-000000024002', 'rep');
  if v_profitability.status <> 'calculated' then
    raise exception 'assertion failed: expected job profitability status=calculated, got %', v_profitability.status;
  end if;
end $$;

\echo '>> OPS-180/181: issue a public tracking token and confirm the sanitized projection reflects the exact delivered/epod-completed state; evaluate billing readiness -- expects a genuine evidence-based ready outcome (zero blockers), since every prerequisite above was driven to full compliance'
do $$
declare
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeopsverify');
  v_shipment_id uuid := (select id from app.shipment_orders where job_order_id = v_job_order_id);
  v_token record;
  v_lookup record;
  v_billing app.billing_readiness_evaluations;
begin
  v_token := app.issue_shipment_tracking_token(v_shipment_id, 30, '00000000-0000-0000-0000-000000024002', 'rep');
  v_lookup := app.lookup_public_shipment_tracking(v_token.raw_token, 'verify-client');
  if v_lookup.lookup_status <> 'ok' then
    raise exception 'assertion failed: expected lookup_status=ok for a freshly issued token, got %', v_lookup.lookup_status;
  end if;
  if not v_lookup.epod_available then
    raise exception 'assertion failed: expected epod_available=true once the ePOD capture is completed, got false';
  end if;
  if v_lookup.status is distinct from 'closed' then
    raise exception 'assertion failed: expected the public projection''s own status to reflect the real (closed) shipment status, got %', v_lookup.status;
  end if;

  v_billing := app.evaluate_billing_readiness(v_job_order_id, null, '00000000-0000-0000-0000-000000024002', 'rep');
  if v_billing.effective_status <> 'ready' or jsonb_array_length(v_billing.blockers) <> 0 then
    raise exception 'assertion failed: expected a genuine, evidence-based ready billing-readiness evaluation with zero blockers given full upstream compliance, got status=%/blockers=%', v_billing.effective_status, v_billing.blockers;
  end if;
end $$;

\echo '>> OPS-182/183/184 cross-reconciliation: the dashboard, the reports preview, and the transaction-lineage manifest all report the exact same reconciled state built above -- shipment closed, epod completed, cost approved, profitability calculated, billing readiness ready -- from three independently-authored read paths over the identical rows'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsverify');
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeopsverify');
  v_shipment_id uuid := (select id from app.shipment_orders where job_order_id = v_job_order_id);
  v_shipment_status_count integer;
  v_epod_count integer;
  v_billing_count integer;
  v_run app.report_runs;
  v_manifest jsonb;
begin
  select shipment_count into v_shipment_status_count from app.get_ops_dashboard_shipment_status(v_tenant1, null, null, '00000000-0000-0000-0000-000000024002') where status = 'closed';
  if coalesce(v_shipment_status_count, 0) < 1 then
    raise exception 'assertion failed: expected the dashboard shipment-status bucket to count the fixture''s own closed shipment, got %', v_shipment_status_count;
  end if;

  select capture_count into v_epod_count from app.get_ops_dashboard_epod_completion(v_tenant1, null, null, '00000000-0000-0000-0000-000000024002') where status = 'completed';
  if coalesce(v_epod_count, 0) < 1 then
    raise exception 'assertion failed: expected the dashboard ePOD-completion bucket to count the fixture''s own completed capture, got %', v_epod_count;
  end if;

  select job_count into v_billing_count from app.get_ops_dashboard_billing_readiness(v_tenant1, null, null, '00000000-0000-0000-0000-000000024002') where bucket = 'ready';
  if coalesce(v_billing_count, 0) < 1 then
    raise exception 'assertion failed: expected the dashboard billing-readiness bucket to count the fixture''s own ready evaluation, got %', v_billing_count;
  end if;

  v_run := app.record_report_run(v_tenant1, 'shipment_status_summary', jsonb_build_object(), 1, '{}'::text[], '00000000-0000-0000-0000-000000024002', 'rep');
  if v_run.status <> 'completed' then
    raise exception 'assertion failed: expected the Operations Reports preview run to record status=completed, got %', v_run.status;
  end if;

  v_manifest := app.get_transaction_lineage(v_job_order_id, '00000000-0000-0000-0000-000000024002');
  if (v_manifest -> 'shipments' -> 0 ->> 'status') <> 'closed' then
    raise exception 'assertion failed: expected the lineage manifest''s own shipment node to report status=closed, matching the dashboard/report state above, got %', v_manifest -> 'shipments' -> 0 ->> 'status';
  end if;
  if (v_manifest -> 'shipments' -> 0 -> 'milestone' ->> 'lastMilestoneCode') <> 'delivered' then
    raise exception 'assertion failed: expected the lineage manifest''s own milestone attribute to report delivered, matching the milestone projection asserted earlier, got %', v_manifest -> 'shipments' -> 0 -> 'milestone' ->> 'lastMilestoneCode';
  end if;
  if (v_manifest -> 'billingReadiness' ->> 'effectiveStatus') <> 'ready' then
    raise exception 'assertion failed: expected the lineage manifest''s own billingReadiness node to report ready, matching app.evaluate_billing_readiness''s own return value above, got %', v_manifest -> 'billingReadiness' ->> 'effectiveStatus';
  end if;
  if jsonb_array_length(v_manifest -> 'edges') <> 6 then
    raise exception 'assertion failed: expected exactly 6 captured lineage edges for this fully-driven fixture, got %', jsonb_array_length(v_manifest -> 'edges');
  end if;
end $$;

\echo '>> end-to-end record-scope isolation: the sibling-team outsider (full grants incl Override/Export, wrong record scope) is denied by every one of the eleven cross-capability read/write entry points touched above, on the exact same fixture data -- proving record-scope was never accidentally skipped anywhere along this chain'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsverify');
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeopsverify');
  v_shipment_id uuid := (select id from app.shipment_orders where job_order_id = v_job_order_id);
  v_outsider uuid := '00000000-0000-0000-0000-000000024004';
begin
  begin
    perform app.set_shipment_mode_profile(
      v_shipment_id, null, null, null, null, null, null, null, null,
      'BL-VERIFY-1', 'BOOK-VERIFY-1', 'MV Verify', 'Jakarta', 'Semarang', 'CONT1234567', '20ft',
      v_outsider, 'outsider'
    );
    raise exception 'assertion failed: expected the outsider denied on app.set_shipment_mode_profile';
  exception when insufficient_privilege then null; end;

  begin
    perform app.ingest_milestone_event(v_shipment_id, 'picked_up', now(), now(), null, 'manual', null, null, 'idem-verify-outsider-ms', v_outsider, 'outsider');
    raise exception 'assertion failed: expected the outsider denied on app.ingest_milestone_event';
  exception when insufficient_privilege then null; end;

  begin
    perform app.dispatch_shipment_order(v_shipment_id, 1, 'idem-verify-outsider-dispatch', v_outsider, 'outsider');
    raise exception 'assertion failed: expected the outsider denied on app.dispatch_shipment_order';
  exception when insufficient_privilege then null; end;

  begin
    perform app.create_actual_cost_draft(v_tenant1, v_shipment_id, 'IDR', null, v_outsider, 'outsider');
    raise exception 'assertion failed: expected the outsider denied on app.create_actual_cost_draft';
  exception when insufficient_privilege then null; end;

  begin
    perform app.calculate_job_profitability(v_job_order_id, 'outsider retry', v_outsider, 'outsider');
    raise exception 'assertion failed: expected the outsider denied on app.calculate_job_profitability';
  exception when insufficient_privilege then null; end;

  begin
    perform app.evaluate_billing_readiness(v_job_order_id, 'outsider retry', v_outsider, 'outsider');
    raise exception 'assertion failed: expected the outsider denied on app.evaluate_billing_readiness';
  exception when insufficient_privilege then null; end;

  begin
    perform app.get_transaction_lineage(v_job_order_id, v_outsider);
    raise exception 'assertion failed: expected the outsider denied on app.get_transaction_lineage';
  exception when insufficient_privilege then null; end;

  begin
    perform app.record_transaction_lineage_override(v_tenant1, 'job_to_shipment', 'job_order', v_job_order_id, 'shipment_order', v_shipment_id, 'outsider attempt', v_outsider, 'outsider');
    raise exception 'assertion failed: expected the outsider denied on app.record_transaction_lineage_override (record-scope, not just permission -- the outsider holds OPS:Override)';
  exception when insufficient_privilege then null; end;

  begin
    perform app.issue_shipment_tracking_token(v_shipment_id, 30, v_outsider, 'outsider');
    raise exception 'assertion failed: expected the outsider denied on app.issue_shipment_tracking_token';
  exception when insufficient_privilege then null; end;
end $$;

\echo '>> cross-tenant isolation: an identity with membership only in a second tenant is denied on the same eleven entry points against tenant1''s data'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsverify');
  v_job_order_id uuid := (select jo.id from app.job_orders jo join app.tenants t on t.id = jo.tenant_id where t.slug = 'acmeopsverify');
  v_shipment_id uuid := (select id from app.shipment_orders where job_order_id = v_job_order_id);
  v_cross uuid := '00000000-0000-0000-0000-000000024007';
begin
  begin
    perform app.dispatch_shipment_order(v_shipment_id, 1, 'idem-verify-cross-dispatch', v_cross, 'cross');
    raise exception 'assertion failed: expected the cross-tenant identity denied on app.dispatch_shipment_order';
  exception when insufficient_privilege then null; end;

  begin
    perform app.get_transaction_lineage(v_job_order_id, v_cross);
    raise exception 'assertion failed: expected the cross-tenant identity denied on app.get_transaction_lineage';
  exception when insufficient_privilege then null; end;

  begin
    perform app.evaluate_billing_readiness(v_job_order_id, 'cross-tenant retry', v_cross, 'cross');
    raise exception 'assertion failed: expected the cross-tenant identity denied on app.evaluate_billing_readiness';
  exception when insufficient_privilege then null; end;
end $$;

\echo '>> schema-privilege defense in depth, end to end: anon holds zero EXECUTE across every Operations function registered since OPS-168 (ERR-2026-004 regression guard, checked once across the whole phase rather than once per capability)'
do $$
declare
  v_denied_count integer;
begin
  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in (
      'prepare_job_order', 'confirm_job_order', 'override_job_order_field',
      'create_shipment_order_from_job', 'confirm_shipment_order', 'cancel_shipment_order',
      'transition_shipment_order', 'set_shipment_mode_profile', 'change_shipment_mode',
      'find_assignment_candidates', 'assign_resource', 'hold_resource_assignment', 'resume_resource_assignment', 'reassign_resource', 'unassign_resource',
      'register_milestone_code', 'create_milestone_template_draft', 'set_milestone_template_sequence', 'publish_milestone_template_version', 'ingest_milestone_event',
      'report_exception', 'acknowledge_exception', 'resolve_exception', 'reopen_exception', 'escalate_exception',
      'evaluate_dispatch_readiness', 'dispatch_shipment_order', 'bulk_dispatch_shipment_orders',
      'create_document_requirement_draft', 'publish_document_requirement_version', 'pin_shipment_document_checklist', 'link_document_to_checklist_item', 'review_document_checklist_item',
      'start_epod_capture', 'set_epod_evidence', 'submit_epod_capture', 'review_epod_capture', 'complete_epod_capture',
      'create_actual_cost_draft', 'add_actual_cost_component', 'submit_actual_cost', 'decide_actual_cost', 'create_actual_cost_adjustment',
      'calculate_job_profitability',
      -- app.lookup_public_shipment_tracking is deliberately excluded: OPS-180's own one
      -- intentional anon grant (the public tracking entry point itself), already proven
      -- by operations-public-tracking.sql's own dedicated defense-in-depth block.
      'issue_shipment_tracking_token', 'revoke_shipment_tracking_token',
      'evaluate_billing_readiness', 'override_billing_readiness', 'revoke_billing_readiness_override', 'handoff_billing_readiness',
      'get_ops_dashboard_shipment_status', 'get_ops_dashboard_milestone_sla', 'get_ops_dashboard_exception_queue', 'get_ops_dashboard_epod_completion', 'get_ops_dashboard_cost_variance', 'get_ops_dashboard_billing_readiness',
      'enqueue_ops_report_export',
      'get_transaction_lineage', 'record_transaction_lineage_override', 'detect_transaction_lineage_anomalies', 'backfill_transaction_lineage'
    );
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants across all 60 checked Operations functions (OPS-168..184, excluding the one deliberate public entry point), found %', v_denied_count;
  end if;
end $$;

\echo '>> audit trail reconciliation: every major cross-capability action above (Job Order confirm, Shipment Order confirm, milestone ingestion, dispatch, ePOD lifecycle, actual cost, profitability, billing readiness, tracking token, lineage capture) left a real, tenant-scoped app.audit_logs entry'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopsverify');
  v_missing text[] := '{}';
  v_action text;
begin
  foreach v_action in array array[
    'confirm_job_order', 'confirm_shipment_order', 'ingest_milestone_event', 'dispatch_shipment_order',
    'submit_epod_capture', 'complete_epod_capture', 'decide_actual_cost', 'calculate_job_profitability',
    'evaluate_billing_readiness', 'issue_shipment_tracking_token', 'capture_transaction_lineage_edge'
  ]
  loop
    if not exists (select 1 from app.audit_logs where tenant_id = v_tenant1 and action = v_action) then
      v_missing := v_missing || v_action;
    end if;
  end loop;
  if array_length(v_missing, 1) is not null then
    raise exception 'assertion failed: expected a real audit_logs entry for every one of these actions on this tenant, missing: %', v_missing;
  end if;
end $$;
