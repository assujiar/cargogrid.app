-- Real, executable test evidence for OPS-175 (Basic Dispatch, CG-S8-OPS-009)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM full + OPS full), a restricted actor (OPS:View only), a sibling-team outsider, an active vendor master record, one confirmed Job Order, and four Shipment Orders driven to assigned (ready/no-assignment/blocked-exception/no-schedule), plus a fifth left in draft as a not-found probe target'
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
  v_vendor_blocked app.master_records;
  v_vendor_bulkready app.master_records;
  v_vendor_noschedule app.master_records;
  v_shipment_ready app.shipment_orders;
  v_shipment_noassign app.shipment_orders;
  v_shipment_blocked app.shipment_orders;
  v_shipment_noschedule app.shipment_orders;
  v_shipment_bulkready app.shipment_orders;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009830', 'admin@acmedispatch.test'),
    ('00000000-0000-0000-0000-000000009831', 'repa@acmedispatch.test'),
    ('00000000-0000-0000-0000-000000009832', 'viewer@acmedispatch.test'),
    ('00000000-0000-0000-0000-000000009833', 'outsider@acmedispatch.test');

  perform app.provision_tenant('acmedispatch', 'Acme Dispatch Co', 'idem-acmedispatch', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmedispatch');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEDISPATCH-CO', 'Acme Dispatch Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDISPATCH-CO'), 'ACMEDISPATCH-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDISPATCH-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDISPATCH-CO'), 'ACMEDISPATCH-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDISPATCH-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009830', 'admin@acmedispatch.test', 'Dispatch Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmedispatch.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009830', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009831', 'repa@acmedispatch.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmedispatch.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009832', 'viewer@acmedispatch.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmedispatch.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009833', 'outsider@acmedispatch.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmedispatch.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Dispatch Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000009831', '00000000-0000-0000-0000-000000009830', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Dispatch Ops Viewer', 'OPS:View only, no Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000009832', '00000000-0000-0000-0000-000000009832', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Dispatch Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000009833', '00000000-0000-0000-0000-000000009830', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Dispatch Test Co', 'Jane Dispatch', 'jane@dispatchtest.test', '0811',
    '00000000-0000-0000-0000-000000009831', v_team_a, '00000000-0000-0000-0000-000000009831', 'tester');
  select * into v_lead from app.leads where email = 'jane@dispatchtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009831', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Dispatch Test Co', 'DTC', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009831', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Dispatch Ops', 'Procurement Lead', 'jane@dispatchtest.test', '0811', '00000000-0000-0000-0000-000000009831', v_team_a, '00000000-0000-0000-0000-000000009831', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009831', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Dispatch test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009831', v_team_a, '00000000-0000-0000-0000-000000009831', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009831', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-DISPATCH-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009830', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009830', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009831', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009831', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009831', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009831', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009831', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ops lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009831', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009831', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009831', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Dispatch Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000009831', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000009831', 'rep');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-DISPATCH-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009830', 'admin');
  select * into v_vendor_blocked from app.create_master_record('vendor', v_tenant1, 'VEND-DISPATCH-2', 'Fabrikam Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009830', 'admin');
  select * into v_vendor_bulkready from app.create_master_record('vendor', v_tenant1, 'VEND-DISPATCH-3', 'Northwind Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009830', 'admin');
  select * into v_vendor_noschedule from app.create_master_record('vendor', v_tenant1, 'VEND-DISPATCH-4', 'Adventure Works Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000009830', 'admin');

  -- Ready: confirmed -> planned -> assigned, a real active vendor assignment, planned_pickup_at set, no exception.
  select * into v_shipment_ready from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-dispatch-ready', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000009831', 'rep'
  );
  select * into v_shipment_ready from app.confirm_shipment_order(v_shipment_ready.id, v_shipment_ready.record_version, '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_ready from app.transition_shipment_order(v_shipment_ready.id, 'planned', v_shipment_ready.record_version, null, null, 'idem-dispatch-ready-planned', '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_ready from app.transition_shipment_order(v_shipment_ready.id, 'assigned', v_shipment_ready.record_version, null, null, 'idem-dispatch-ready-assigned', '00000000-0000-0000-0000-000000009831', 'rep');
  perform app.assign_resource(v_shipment_ready.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000009831', 'rep');

  -- No active assignment: same path, but never assigned a resource.
  select * into v_shipment_noassign from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-dispatch-noassign', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: noassign fixture', '00000000-0000-0000-0000-000000009831', 'rep'
  );
  select * into v_shipment_noassign from app.confirm_shipment_order(v_shipment_noassign.id, v_shipment_noassign.record_version, '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_noassign from app.transition_shipment_order(v_shipment_noassign.id, 'planned', v_shipment_noassign.record_version, null, null, 'idem-dispatch-noassign-planned', '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_noassign from app.transition_shipment_order(v_shipment_noassign.id, 'assigned', v_shipment_noassign.record_version, null, null, 'idem-dispatch-noassign-assigned', '00000000-0000-0000-0000-000000009831', 'rep');

  -- Blocked by an open exception: has a real active assignment, but an open exception exists.
  select * into v_shipment_blocked from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-dispatch-blocked', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Semarang',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: blocked fixture', '00000000-0000-0000-0000-000000009831', 'rep'
  );
  select * into v_shipment_blocked from app.confirm_shipment_order(v_shipment_blocked.id, v_shipment_blocked.record_version, '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_blocked from app.transition_shipment_order(v_shipment_blocked.id, 'planned', v_shipment_blocked.record_version, null, null, 'idem-dispatch-blocked-planned', '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_blocked from app.transition_shipment_order(v_shipment_blocked.id, 'assigned', v_shipment_blocked.record_version, null, null, 'idem-dispatch-blocked-assigned', '00000000-0000-0000-0000-000000009831', 'rep');
  perform app.assign_resource(v_shipment_blocked.id, 'vendor', v_vendor_blocked.id, '00000000-0000-0000-0000-000000009831', 'rep');
  perform app.report_exception(v_shipment_blocked.id, null, 'delay', 'medium', 'Carrier reports a delay', 'manual', null, '00000000-0000-0000-0000-000000009831', 'rep');

  -- Missing schedule: a real active assignment, but no planned_pickup_at set.
  select * into v_shipment_noschedule from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-dispatch-noschedule', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Bogor',
    null, null, null, null, null, null, null, null, 'split: noschedule fixture', '00000000-0000-0000-0000-000000009831', 'rep'
  );
  select * into v_shipment_noschedule from app.confirm_shipment_order(v_shipment_noschedule.id, v_shipment_noschedule.record_version, '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_noschedule from app.transition_shipment_order(v_shipment_noschedule.id, 'planned', v_shipment_noschedule.record_version, null, null, 'idem-dispatch-noschedule-planned', '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_noschedule from app.transition_shipment_order(v_shipment_noschedule.id, 'assigned', v_shipment_noschedule.record_version, null, null, 'idem-dispatch-noschedule-assigned', '00000000-0000-0000-0000-000000009831', 'rep');
  perform app.assign_resource(v_shipment_noschedule.id, 'vendor', v_vendor_noschedule.id, '00000000-0000-0000-0000-000000009831', 'rep');

  -- A second, independently-fully-ready fixture reserved for the bulk-dispatch test's
  -- own real success case -- the single-dispatch test above already consumes
  -- idem-dispatch-ready's own "ready" state by dispatching it, so bulk needs its own.
  select * into v_shipment_bulkready from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-dispatch-bulkready', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Cirebon',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: bulkready fixture', '00000000-0000-0000-0000-000000009831', 'rep'
  );
  select * into v_shipment_bulkready from app.confirm_shipment_order(v_shipment_bulkready.id, v_shipment_bulkready.record_version, '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_bulkready from app.transition_shipment_order(v_shipment_bulkready.id, 'planned', v_shipment_bulkready.record_version, null, null, 'idem-dispatch-bulkready-planned', '00000000-0000-0000-0000-000000009831', 'rep');
  select * into v_shipment_bulkready from app.transition_shipment_order(v_shipment_bulkready.id, 'assigned', v_shipment_bulkready.record_version, null, null, 'idem-dispatch-bulkready-assigned', '00000000-0000-0000-0000-000000009831', 'rep');
  perform app.assign_resource(v_shipment_bulkready.id, 'vendor', v_vendor_bulkready.id, '00000000-0000-0000-0000-000000009831', 'rep');
end $$;

\echo '>> app.evaluate_dispatch_readiness / app.get_dispatch_readiness: is_ready=true with zero blockers for the fully-ready shipment; each other fixture reports its own exact single blocker; authority-gated (viewer holds OPS:View, so allowed; record-scope enforced separately)'
do $$
declare
  v_ready record;
  v_noassign record;
  v_blocked record;
  v_noschedule record;
begin
  select * into v_ready from app.get_dispatch_readiness((select id from app.shipment_orders where idempotency_key = 'idem-dispatch-ready'), '00000000-0000-0000-0000-000000009831');
  if not v_ready.is_ready or jsonb_array_length(v_ready.blockers) <> 0 then
    raise exception 'assertion failed: expected the ready fixture to have is_ready=true and zero blockers, got %/%', v_ready.is_ready, v_ready.blockers;
  end if;

  select * into v_noassign from app.get_dispatch_readiness((select id from app.shipment_orders where idempotency_key = 'idem-dispatch-noassign'), '00000000-0000-0000-0000-000000009831');
  if v_noassign.is_ready or (v_noassign.blockers -> 0 ->> 'code') <> 'no_active_assignment' then
    raise exception 'assertion failed: expected the noassign fixture blocked by no_active_assignment, got %/%', v_noassign.is_ready, v_noassign.blockers;
  end if;

  select * into v_blocked from app.get_dispatch_readiness((select id from app.shipment_orders where idempotency_key = 'idem-dispatch-blocked'), '00000000-0000-0000-0000-000000009831');
  if v_blocked.is_ready or (v_blocked.blockers -> 0 ->> 'code') <> 'blocking_exception' then
    raise exception 'assertion failed: expected the blocked fixture blocked by blocking_exception, got %/%', v_blocked.is_ready, v_blocked.blockers;
  end if;

  select * into v_noschedule from app.get_dispatch_readiness((select id from app.shipment_orders where idempotency_key = 'idem-dispatch-noschedule'), '00000000-0000-0000-0000-000000009831');
  if v_noschedule.is_ready or (v_noschedule.blockers -> 0 ->> 'code') <> 'missing_schedule' then
    raise exception 'assertion failed: expected the noschedule fixture blocked by missing_schedule, got %/%', v_noschedule.is_ready, v_noschedule.blockers;
  end if;
end $$;

\echo '>> app.dispatch_ready_queue: lists exactly the four assigned fixtures, is_ready/blockers matching app.get_dispatch_readiness exactly'
do $$
declare
  v_count integer;
  v_ready_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009831", "role": "authenticated"}';

  select count(*) into v_count from app.dispatch_ready_queue
  where idempotency_key in ('idem-dispatch-ready', 'idem-dispatch-noassign', 'idem-dispatch-blocked', 'idem-dispatch-noschedule');
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 assigned fixtures in the ready queue, found %', v_count;
  end if;

  select count(*) into v_ready_count from app.dispatch_ready_queue where idempotency_key = 'idem-dispatch-ready' and is_ready;
  if v_ready_count <> 1 then
    raise exception 'assertion failed: expected the ready fixture to appear in the queue with is_ready=true';
  end if;
  reset role;
end $$;

\echo '>> app.dispatch_shipment_order: authority-gated (OPS:View-only denied OPS:Edit); dispatch_not_ready for each blocked fixture; a valid dispatch on the ready fixture succeeds exactly once, transitions the shipment to dispatched, and records a real readiness_snapshot; idempotent retry on the same idempotency_key returns the same command row'
do $$
declare
  v_shipment_ready_id uuid;
  v_shipment_noassign_id uuid;
  v_command1 app.dispatch_commands;
  v_command2 app.dispatch_commands;
  v_shipment app.shipment_orders;
begin
  select id into v_shipment_ready_id from app.shipment_orders where idempotency_key = 'idem-dispatch-ready';
  select id into v_shipment_noassign_id from app.shipment_orders where idempotency_key = 'idem-dispatch-noassign';
  select * into v_shipment from app.shipment_orders where id = v_shipment_ready_id;

  begin
    perform app.dispatch_shipment_order(v_shipment_ready_id, v_shipment.record_version, 'idem-disp-viewer', '00000000-0000-0000-0000-000000009832', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    select * into v_shipment from app.shipment_orders where id = v_shipment_noassign_id;
    perform app.dispatch_shipment_order(v_shipment_noassign_id, v_shipment.record_version, 'idem-disp-noassign', '00000000-0000-0000-0000-000000009831', 'rep');
    raise exception 'assertion failed: expected dispatch_not_ready for the noassign fixture';
  exception
    when others then
      if sqlerrm not like 'dispatch_not_ready%' then
        raise;
      end if;
  end;

  select * into v_shipment from app.shipment_orders where id = v_shipment_ready_id;
  select * into v_command1 from app.dispatch_shipment_order(v_shipment_ready_id, v_shipment.record_version, 'idem-disp-ready-1', '00000000-0000-0000-0000-000000009831', 'rep');
  if (v_command1.readiness_snapshot ->> 'is_ready')::boolean is not true then
    raise exception 'assertion failed: expected a real is_ready=true readiness_snapshot on the recorded dispatch command';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_shipment_ready_id;
  if v_shipment.status <> 'dispatched' then
    raise exception 'assertion failed: expected the ready fixture to become dispatched, found %', v_shipment.status;
  end if;

  select * into v_command2 from app.dispatch_shipment_order(v_shipment_ready_id, v_shipment.record_version, 'idem-disp-ready-1', '00000000-0000-0000-0000-000000009831', 'rep');
  if v_command2.id <> v_command1.id then
    raise exception 'assertion failed: expected the idempotent retry to return the same dispatch command row, not a new one';
  end if;
  if (select count(*) from app.dispatch_commands where shipment_order_id = v_shipment_ready_id) <> 1 then
    raise exception 'assertion failed: expected exactly one dispatch command row after the retry';
  end if;
end $$;

\echo '>> app.bulk_dispatch_shipment_orders: bounded at 50; a mixed batch returns one explicit result row per id -- success for a genuinely-ready fixture, failure for the not-ready blocked/noschedule fixtures, and shipment_order_not_found for a non-existent id -- one failure never aborts the others'
do $$
declare
  v_shipment_bulkready_id uuid;
  v_shipment_blocked_id uuid;
  v_shipment_noschedule_id uuid;
  v_missing_id uuid := '00000000-0000-0000-0000-000000009999';
  v_row_count integer;
begin
  select id into v_shipment_bulkready_id from app.shipment_orders where idempotency_key = 'idem-dispatch-bulkready';
  select id into v_shipment_blocked_id from app.shipment_orders where idempotency_key = 'idem-dispatch-blocked';
  select id into v_shipment_noschedule_id from app.shipment_orders where idempotency_key = 'idem-dispatch-noschedule';

  begin
    perform app.bulk_dispatch_shipment_orders(array_fill(v_shipment_bulkready_id, array[51]), 'idem-bulk-toolarge', '00000000-0000-0000-0000-000000009831', 'rep');
    raise exception 'assertion failed: expected bulk_too_large for a 51-item batch';
  exception
    when others then
      if sqlerrm not like 'bulk_too_large%' then
        raise;
      end if;
  end;

  create temp table tmp_bulk_dispatch_result on commit drop as
  select * from app.bulk_dispatch_shipment_orders(
    array[v_shipment_bulkready_id, v_shipment_blocked_id, v_shipment_noschedule_id, v_missing_id],
    'idem-bulk-mixed', '00000000-0000-0000-0000-000000009831', 'rep'
  );

  select count(*) into v_row_count from tmp_bulk_dispatch_result;
  if v_row_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 result rows for a 4-item batch, found %', v_row_count;
  end if;

  if not exists (select 1 from tmp_bulk_dispatch_result where shipment_order_id = v_shipment_bulkready_id and success) then
    raise exception 'assertion failed: expected the genuinely-ready fixture to succeed in the bulk batch';
  end if;
  if exists (select 1 from tmp_bulk_dispatch_result where shipment_order_id = v_shipment_blocked_id and success) then
    raise exception 'assertion failed: expected the blocked fixture to fail in the bulk batch';
  end if;
  if exists (select 1 from tmp_bulk_dispatch_result where shipment_order_id = v_shipment_noschedule_id and success) then
    raise exception 'assertion failed: expected the noschedule fixture to fail in the bulk batch';
  end if;
  if not exists (select 1 from tmp_bulk_dispatch_result where shipment_order_id = v_missing_id and error_code = 'shipment_order_not_found') then
    raise exception 'assertion failed: expected shipment_order_not_found for the missing id';
  end if;

  if (select status from app.shipment_orders where id = v_shipment_bulkready_id) <> 'dispatched' then
    raise exception 'assertion failed: expected the genuinely-ready fixture to actually become dispatched after the bulk call';
  end if;
end $$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) cannot read readiness or dispatch despite holding full OPS grants'
do $$
declare
  v_shipment_ready_id uuid;
begin
  select id into v_shipment_ready_id from app.shipment_orders where idempotency_key = 'idem-dispatch-blocked';

  begin
    perform app.get_dispatch_readiness(v_shipment_ready_id, '00000000-0000-0000-0000-000000009833');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied read access by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.dispatch_shipment_order(v_shipment_ready_id, 1, 'idem-disp-outsider', '00000000-0000-0000-0000-000000009833', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> cross-tenant isolation: app.dispatch_shipment_order/app.get_dispatch_readiness fail closed for an identity with no membership in the shipment''s own tenant'
do $$
declare
  v_tenant2 uuid;
  v_shipment_id uuid;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000009834', 'admin2@acmedispatch2.test');
  perform app.provision_tenant('acmedispatch2', 'Acme Dispatch Co 2', 'idem-acmedispatch2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmedispatch2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009834', 'admin2@acmedispatch2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmedispatch2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009834', 'tenant_admin', v_tenant2, null, 'tester');

  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-dispatch-blocked';

  begin
    perform app.get_dispatch_readiness(v_shipment_id, '00000000-0000-0000-0000-000000009834');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:View in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.dispatch_shipment_order(v_shipment_id, 1, 'idem-disp-tenant2', '00000000-0000-0000-0000-000000009834', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Edit in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 4 new Basic Dispatch functions (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in ('evaluate_dispatch_readiness', 'get_dispatch_readiness', 'dispatch_shipment_order', 'bulk_dispatch_shipment_orders');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 4 new Basic Dispatch functions, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: dispatch_shipment_order recorded exactly 2 success events (the single ready dispatch + the bulk-ready dispatch) and zero failure events -- a dispatch_not_ready/insufficient_authority raise unwinds to the caller''s own exception block, which rolls back any insert made before the raise, so blockers are only ever surfaced in the raised exception message itself, never a persisted audit row'
do $$
declare
  v_tenant1 uuid;
  v_success_count integer;
  v_failure_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedispatch');

  select count(*) into v_success_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.dispatch_commands' and action = 'dispatch_shipment_order' and result = 'success';
  if v_success_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 successful dispatch_shipment_order audit events, found %', v_success_count;
  end if;

  select count(*) into v_failure_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.dispatch_commands' and action = 'dispatch_shipment_order' and result = 'failure';
  if v_failure_count <> 0 then
    raise exception 'assertion failed: expected zero persisted failure dispatch_shipment_order audit events (a raised exception always rolls back any insert made before it), found %', v_failure_count;
  end if;
end $$;
