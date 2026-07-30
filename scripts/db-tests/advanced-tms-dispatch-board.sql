-- Real, executable test evidence for ATW-222 (CG-S10-ATW-003, Prompt 222 Advanced
-- Dispatch Board with Tracking Health) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a rep (OPS:Create/Edit/View/Assign), a sibling-team outsider, a global Supreme Admin, one confirmed Job Order, and three Shipment Orders (assigned/dispatched/in_transit) via the real Commercial pipeline'
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
  v_shipment_assigned app.shipment_orders;
  v_shipment_dispatched app.shipment_orders;
  v_shipment_transit app.shipment_orders;
  v_vendor_1 app.master_records;
  v_vendor_2 app.master_records;
  v_vendor_3 app.master_records;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000039111', 'admin@acmeboard.test'),
    ('00000000-0000-0000-0000-000000039112', 'repa@acmeboard.test'),
    ('00000000-0000-0000-0000-000000039113', 'outsider@acmeboard.test'),
    ('00000000-0000-0000-0000-000000039114', 'supreme@acmeboard.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039114', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeboard', 'Acme Board Co', 'idem-acmeboard', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeboard');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEBOARD-CO', 'Acme Board Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEBOARD-CO'), 'ACMEBOARD-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEBOARD-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEBOARD-CO'), 'ACMEBOARD-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEBOARD-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039111', 'admin@acmeboard.test', 'Board Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeboard.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039111', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039112', 'repa@acmeboard.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeboard.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039113', 'outsider@acmeboard.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeboard.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Board Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000039112', '00000000-0000-0000-0000-000000039111', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Board Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000039113', '00000000-0000-0000-0000-000000039111', 'tester');

  select * into v_vendor_1 from app.create_master_record('vendor', v_tenant1, 'VEND-BOARD-1', 'Acme Board Vendor 1', null, null, '00000000-0000-0000-0000-000000039111', 'tester');
  select * into v_vendor_2 from app.create_master_record('vendor', v_tenant1, 'VEND-BOARD-2', 'Acme Board Vendor 2', null, null, '00000000-0000-0000-0000-000000039111', 'tester');
  select * into v_vendor_3 from app.create_master_record('vendor', v_tenant1, 'VEND-BOARD-3', 'Acme Board Vendor 3', null, null, '00000000-0000-0000-0000-000000039111', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Board Test Co', 'Jane Board', 'jane@boardtest.test', '0811',
    '00000000-0000-0000-0000-000000039112', v_team_a, '00000000-0000-0000-0000-000000039112', 'tester');
  select * into v_lead from app.leads where email = 'jane@boardtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000039112', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Board Test Co', 'BTC', '11.111.111.3-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 3', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000039112', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Board Ops', 'Procurement Lead', 'jane@boardtest.test', '0811', '00000000-0000-0000-0000-000000039112', v_team_a, '00000000-0000-0000-0000-000000039112', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000039112', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Board test lane',
    jsonb_build_object('service_type', 'land_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000039112', v_team_a, '00000000-0000-0000-0000-000000039112', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000039112', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-BOARD-1', 'Contoso Board Line', 'land_freight', 'FTL', 'Jakarta', 'Bandung', 'truck',
    null, null, null, null, 'IDR', 5000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000039111', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000039111', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000039112', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000039112', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000039112', 'tester');
  perform app.calculate_margin(v_selection.id, 6500000, 'IDR', 0, '00000000-0000-0000-0000-000000039112', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000039112', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Land freight board lane', v_calc_id, 1, 6500000, 0, 0, '00000000-0000-0000-0000-000000039112', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000039112', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000039112', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Board Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000039112', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000039112', 'rep');

  -- Shipment 1: assigned, ready to dispatch.
  select * into v_shipment_assigned from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-board-assigned', null, null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000039112', 'rep'
  );
  select * into v_shipment_assigned from app.confirm_shipment_order(v_shipment_assigned.id, v_shipment_assigned.record_version, '00000000-0000-0000-0000-000000039112', 'rep');
  perform app.transition_shipment_order(v_shipment_assigned.id, 'planned', v_shipment_assigned.record_version, null, null, 'idem-board-plan-1', '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_shipment_assigned from app.shipment_orders where id = v_shipment_assigned.id;
  perform app.assign_resource(v_shipment_assigned.id, 'vendor', v_vendor_1.id, '00000000-0000-0000-0000-000000039112', 'rep');
  perform app.transition_shipment_order(v_shipment_assigned.id, 'assigned', v_shipment_assigned.record_version, null, null, 'idem-board-assign-1', '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_shipment_assigned from app.shipment_orders where id = v_shipment_assigned.id;

  -- Shipment 2: dispatched.
  select * into v_shipment_dispatched from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-board-dispatched', null, null, 'land_freight', 'land', 'Jakarta', 'Bogor',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, 'split: dispatched fixture', '00000000-0000-0000-0000-000000039112', 'rep'
  );
  select * into v_shipment_dispatched from app.confirm_shipment_order(v_shipment_dispatched.id, v_shipment_dispatched.record_version, '00000000-0000-0000-0000-000000039112', 'rep');
  perform app.transition_shipment_order(v_shipment_dispatched.id, 'planned', v_shipment_dispatched.record_version, null, null, 'idem-board-plan-2', '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_shipment_dispatched from app.shipment_orders where id = v_shipment_dispatched.id;
  perform app.assign_resource(v_shipment_dispatched.id, 'vendor', v_vendor_2.id, '00000000-0000-0000-0000-000000039112', 'rep');
  perform app.transition_shipment_order(v_shipment_dispatched.id, 'assigned', v_shipment_dispatched.record_version, null, null, 'idem-board-assign-2', '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_shipment_dispatched from app.shipment_orders where id = v_shipment_dispatched.id;
  perform app.dispatch_shipment_order(v_shipment_dispatched.id, v_shipment_dispatched.record_version, 'idem-board-dispatch-2', '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_shipment_dispatched from app.shipment_orders where id = v_shipment_dispatched.id;

  -- Shipment 3: in_transit.
  select * into v_shipment_transit from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-board-transit', null, null, 'land_freight', 'land', 'Jakarta', 'Cirebon',
    now() + interval '1 day', now() + interval '2 days', null, null, null, null, null, null, 'split: transit fixture', '00000000-0000-0000-0000-000000039112', 'rep'
  );
  select * into v_shipment_transit from app.confirm_shipment_order(v_shipment_transit.id, v_shipment_transit.record_version, '00000000-0000-0000-0000-000000039112', 'rep');
  perform app.transition_shipment_order(v_shipment_transit.id, 'planned', v_shipment_transit.record_version, null, null, 'idem-board-plan-3', '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_shipment_transit from app.shipment_orders where id = v_shipment_transit.id;
  perform app.assign_resource(v_shipment_transit.id, 'vendor', v_vendor_3.id, '00000000-0000-0000-0000-000000039112', 'rep');
  perform app.transition_shipment_order(v_shipment_transit.id, 'assigned', v_shipment_transit.record_version, null, null, 'idem-board-assign-3', '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_shipment_transit from app.shipment_orders where id = v_shipment_transit.id;
  perform app.dispatch_shipment_order(v_shipment_transit.id, v_shipment_transit.record_version, 'idem-board-dispatch-3', '00000000-0000-0000-0000-000000039112', 'rep');
  select * into v_shipment_transit from app.shipment_orders where id = v_shipment_transit.id;
  perform app.transition_shipment_order(v_shipment_transit.id, 'in_transit', v_shipment_transit.record_version, null, null, 'idem-board-transit-3', '00000000-0000-0000-0000-000000039112', 'rep');
end $$;

\echo '>> app.is_shipment_tracking_entitled: always false (disclosed stub, ATW-226A not yet built)'
do $$
declare
  v_tenant1 uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeboard');
  if app.is_shipment_tracking_entitled(v_tenant1) is not false then
    raise exception 'assertion failed: expected app.is_shipment_tracking_entitled to always report false until ATW-226A ships';
  end if;
end $$;

\echo '>> app.dispatch_board_queue: shows assigned/dispatched/in_transit (not draft/confirmed/planned), honest not_tracked/unknown/false tracking projection, is_ready only meaningful for the assigned row'
do $$
declare
  v_assigned record;
  v_dispatched record;
  v_transit record;
  v_row_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000039112", "role": "authenticated"}';

  select * into v_assigned from app.dispatch_board_queue where idempotency_key = 'idem-board-assigned';
  select * into v_dispatched from app.dispatch_board_queue where idempotency_key = 'idem-board-dispatched';
  select * into v_transit from app.dispatch_board_queue where idempotency_key = 'idem-board-transit';

  if v_assigned.id is null or v_dispatched.id is null or v_transit.id is null then
    raise exception 'assertion failed: expected all three (assigned/dispatched/in_transit) shipments to appear in the board';
  end if;

  if v_assigned.is_ready is not true then
    raise exception 'assertion failed: expected the assigned shipment to be ready (active vendor assignment, no exception, scheduled)';
  end if;
  if v_dispatched.is_ready is not null or v_transit.is_ready is not null then
    raise exception 'assertion failed: expected is_ready to be null once a shipment has moved past assigned (readiness is meaningless there)';
  end if;

  if v_assigned.has_active_assignment is not true or v_dispatched.has_active_assignment is not true or v_transit.has_active_assignment is not true then
    raise exception 'assertion failed: expected has_active_assignment true for all three (each has a current active vendor assignment)';
  end if;

  if v_assigned.tracking_status <> 'not_tracked' or v_dispatched.tracking_status <> 'not_tracked' or v_transit.tracking_status <> 'not_tracked' then
    raise exception 'assertion failed: expected tracking_status = not_tracked for every row -- no telemetry source exists yet, never a fabricated tracked state';
  end if;
  if v_assigned.freshness_status <> 'unknown' then
    raise exception 'assertion failed: expected freshness_status = unknown when no tracking_health row exists';
  end if;
  if v_assigned.fallback_active is not false then
    raise exception 'assertion failed: expected fallback_active = false when no tracking_health row exists';
  end if;
  if v_assigned.tracking_entitled is not false then
    raise exception 'assertion failed: expected tracking_entitled = false (disclosed stub)';
  end if;
  if v_assigned.tracking_exception_count <> 0 then
    raise exception 'assertion failed: expected tracking_exception_count = 0 when no tracking_health row exists';
  end if;
  if v_assigned.authoritative_source_type is not null or v_assigned.last_position_at is not null or v_assigned.accuracy_meters is not null then
    raise exception 'assertion failed: expected authoritative_source_type/last_position_at/accuracy_meters all null -- no real telemetry source exists';
  end if;

  select count(*) into v_row_count from app.dispatch_board_queue where idempotency_key in ('idem-board-assigned', 'idem-board-dispatched', 'idem-board-transit') and false;
  if v_row_count <> 0 then
    raise exception 'assertion failed: sanity check (should never match)';
  end if;
  reset role;
end $$;

\echo '>> app.shipment_tracking_health: a real row, once present, is honestly reflected by the board (not silently ignored)'
do $$
declare
  v_shipment_id uuid;
  v_tenant1 uuid;
  v_tracking_status text;
  v_fallback_active boolean;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeboard');
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-board-assigned';

  insert into app.shipment_tracking_health (tenant_id, shipment_order_id, tracking_status, authoritative_source_type, last_position_at, freshness_status, accuracy_meters, fallback_active, tracking_exception_count)
  values (v_tenant1, v_shipment_id, 'stale', 'driver_mobile', now() - interval '2 hours', 'stale', 50, true, 2);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000039112", "role": "authenticated"}';

  select tracking_status, fallback_active into v_tracking_status, v_fallback_active from app.dispatch_board_queue where idempotency_key = 'idem-board-assigned';
  reset role;

  if v_tracking_status <> 'stale' then
    raise exception 'assertion failed: expected the board to reflect a real shipment_tracking_health row once one exists, not silently default it';
  end if;
  if v_fallback_active is not true then
    raise exception 'assertion failed: expected fallback_active = true to be reflected honestly';
  end if;
end $$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) sees zero board rows despite holding full OPS grants'
do $$
declare
  v_row_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000039113", "role": "authenticated"}';
  select count(*) into v_row_count from app.dispatch_board_queue where idempotency_key in ('idem-board-assigned', 'idem-board-dispatched', 'idem-board-transit');
  reset role;
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero board rows via RLS, found %', v_row_count;
  end if;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on app.is_shipment_tracking_entitled; authenticated has no direct INSERT/UPDATE/DELETE on app.shipment_tracking_health'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and grantee = 'anon' and routine_name = 'is_shipment_tracking_entitled';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on app.is_shipment_tracking_entitled, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app' and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
    and table_name = 'shipment_tracking_health';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grants on app.shipment_tracking_health, found %', v_count;
  end if;
end $$;
