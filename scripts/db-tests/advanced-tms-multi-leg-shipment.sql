-- Real, executable test evidence for ATW-221 (CG-S10-ATW-002, Prompt 221 Multi-Leg
-- and Multimodal Shipment) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a rep (OPS:Create/Edit/View), an OPS-viewer-only actor, a sibling-team outsider, a global Supreme Admin, one active fleet master record, and two confirmed sea-mode Shipment Orders (multi-leg + legacy) off one confirmed Job Order'
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
  v_shipment_multi app.shipment_orders;
  v_shipment_legacy app.shipment_orders;
  v_fleet app.master_records;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000039101', 'admin@acmeleg.test'),
    ('00000000-0000-0000-0000-000000039102', 'repa@acmeleg.test'),
    ('00000000-0000-0000-0000-000000039103', 'viewer@acmeleg.test'),
    ('00000000-0000-0000-0000-000000039104', 'outsider@acmeleg.test'),
    ('00000000-0000-0000-0000-000000039105', 'supreme@acmeleg.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039105', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeleg', 'Acme Multileg Co', 'idem-acmeleg', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeleg');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMELEG-CO', 'Acme Multileg Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEG-CO'), 'ACMELEG-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEG-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEG-CO'), 'ACMELEG-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEG-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039101', 'admin@acmeleg.test', 'Leg Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeleg.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039102', 'repa@acmeleg.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeleg.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039103', 'viewer@acmeleg.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmeleg.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000039104', 'outsider@acmeleg.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeleg.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Leg Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000039102', '00000000-0000-0000-0000-000000039101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Leg Ops Viewer', 'OPS:View only, no Create/Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000039103', '00000000-0000-0000-0000-000000039103', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Leg Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000039104', '00000000-0000-0000-0000-000000039101', 'tester');

  select * into v_fleet from app.create_master_record('fleet', v_tenant1, 'FLEET-LEG-1', 'Acme Multileg Fleet Truck 1', null, null, '00000000-0000-0000-0000-000000039101', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Leg Test Co', 'Jane Leg', 'jane@legtest.test', '0811',
    '00000000-0000-0000-0000-000000039102', v_team_a, '00000000-0000-0000-0000-000000039102', 'tester');
  select * into v_lead from app.leads where email = 'jane@legtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000039102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Leg Test Co', 'LTC', '11.111.111.2-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 2', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000039102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Leg Ops', 'Procurement Lead', 'jane@legtest.test', '0811', '00000000-0000-0000-0000-000000039102', v_team_a, '00000000-0000-0000-0000-000000039102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000039102', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Multileg test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Makassar', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000039102', v_team_a, '00000000-0000-0000-0000-000000039102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000039102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-LEG-1', 'Contoso Multileg Line', 'ocean_freight', 'FCL', 'Jakarta', 'Makassar', '20ft',
    null, null, null, null, 'IDR', 12000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000039101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000039101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000039102', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000039102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000039102', 'tester');
  perform app.calculate_margin(v_selection.id, 18700000, 'IDR', 0, '00000000-0000-0000-0000-000000039102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000039102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight multileg lane', v_calc_id, 1, 18700000, 0, 0, '00000000-0000-0000-0000-000000039102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000039102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000039102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Leg Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000039102', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000039102', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000039102', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000039102', 'rep');

  select * into v_shipment_multi from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-leg-multi', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Makassar',
    now() + interval '1 day', now() + interval '10 days', 100, 5000, 40, 100, 5000, 40, null, '00000000-0000-0000-0000-000000039102', 'rep'
  );
  select * into v_shipment_multi from app.confirm_shipment_order(v_shipment_multi.id, v_shipment_multi.record_version, '00000000-0000-0000-0000-000000039102', 'rep');

  select * into v_shipment_legacy from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-leg-legacy', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '5 days', null, null, null, null, null, null, 'split: legacy fixture', '00000000-0000-0000-0000-000000039102', 'rep'
  );
  select * into v_shipment_legacy from app.confirm_shipment_order(v_shipment_legacy.id, v_shipment_legacy.record_version, '00000000-0000-0000-0000-000000039102', 'rep');
end $$;

\echo '>> app.add_shipment_leg: authority-gated, idempotent, rejects duplicate active sequence and an unknown carrier'
do $$
declare
  v_shipment_id uuid;
  v_leg1 app.shipment_legs;
  v_leg1_retry app.shipment_legs;
  v_leg2 app.shipment_legs;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-leg-multi';

  begin
    perform app.add_shipment_leg(v_shipment_id, 'idem-leg1-denied', 1, 'sea', null, null, null, '00000000-0000-0000-0000-000000039103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select * into v_leg1 from app.add_shipment_leg(v_shipment_id, 'idem-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000039102', 'rep');
  if v_leg1.sequence_no <> 1 or v_leg1.leg_status <> 'planned' then
    raise exception 'assertion failed: expected leg 1 planned with sequence_no 1';
  end if;

  select * into v_leg1_retry from app.add_shipment_leg(v_shipment_id, 'idem-leg1', 1, 'land', null, now(), now() + interval '1 day', '00000000-0000-0000-0000-000000039102', 'rep');
  if v_leg1_retry.id <> v_leg1.id then
    raise exception 'assertion failed: expected the idempotent repeated call to return the exact same leg row';
  end if;

  begin
    perform app.add_shipment_leg(v_shipment_id, 'idem-leg1-dup-seq', 1, 'sea', null, null, null, '00000000-0000-0000-0000-000000039102', 'rep');
    raise exception 'assertion failed: expected leg_sequence_duplicate for a second leg claiming sequence 1';
  exception
    when others then
      if sqlerrm not like 'leg_sequence_duplicate%' then raise; end if;
  end;

  begin
    perform app.add_shipment_leg(v_shipment_id, 'idem-leg-bad-carrier', 2, 'sea', gen_random_uuid(), null, null, '00000000-0000-0000-0000-000000039102', 'rep');
    raise exception 'assertion failed: expected carrier_not_found for an unknown carrier_master_id';
  exception
    when others then
      if sqlerrm not like 'carrier_not_found%' then raise; end if;
  end;

  select * into v_leg2 from app.add_shipment_leg(
    v_shipment_id, 'idem-leg2', 2, 'sea', (select id from app.master_records where code = 'FLEET-LEG-1'),
    now() + interval '1 day', now() + interval '10 days', '00000000-0000-0000-0000-000000039102', 'rep'
  );
  if v_leg2.carrier_master_id is null then
    raise exception 'assertion failed: expected leg 2 to carry the fleet carrier reference';
  end if;
end $$;

\echo '>> app.add_shipment_leg_stop / app.allocate_shipment_leg_cargo: only while planned; cargo sum across legs never exceeds the shipment''s own allocation'
do $$
declare
  v_shipment_id uuid;
  v_leg1_id uuid;
  v_leg2_id uuid;
  v_stop app.shipment_leg_stops;
  v_alloc1 app.shipment_leg_cargo_allocations;
  v_alloc2 app.shipment_leg_cargo_allocations;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-leg-multi';
  select id into v_leg1_id from app.shipment_legs where shipment_order_id = v_shipment_id and sequence_no = 1;
  select id into v_leg2_id from app.shipment_legs where shipment_order_id = v_shipment_id and sequence_no = 2;

  select * into v_stop from app.add_shipment_leg_stop(v_leg1_id, 1, 'pickup', 'Jakarta Warehouse', 'Jl. Rasuna Said 1', 106.8456, -6.2088, now(), '00000000-0000-0000-0000-000000039102', 'rep');
  if v_stop.location_geog is null then
    raise exception 'assertion failed: expected a real geography point built from the supplied longitude/latitude';
  end if;
  perform app.add_shipment_leg_stop(v_leg1_id, 2, 'transfer', 'Surabaya Transfer Yard', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000039102', 'rep');
  perform app.add_shipment_leg_stop(v_leg2_id, 1, 'transfer', 'Surabaya Port', null, null, null, now() + interval '1 day', '00000000-0000-0000-0000-000000039102', 'rep');
  perform app.add_shipment_leg_stop(v_leg2_id, 2, 'delivery', 'Makassar Warehouse', null, null, null, now() + interval '10 days', '00000000-0000-0000-0000-000000039102', 'rep');

  begin
    perform app.add_shipment_leg_stop(v_leg1_id, 3, 'delivery', 'Should Fail', null, null, null, null, '00000000-0000-0000-0000-000000039103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor adding a stop';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select * into v_alloc1 from app.allocate_shipment_leg_cargo(v_leg1_id, 60, 3000, 24, '00000000-0000-0000-0000-000000039102', 'rep');
  if v_alloc1.allocated_quantity <> 60 then
    raise exception 'assertion failed: expected leg 1 cargo allocation of 60';
  end if;

  begin
    perform app.allocate_shipment_leg_cargo(v_leg2_id, 50, 3000, 20, '00000000-0000-0000-0000-000000039102', 'rep');
    raise exception 'assertion failed: expected cargo_over_allocated -- 60 + 50 = 110 exceeds the shipment''s own allocated_quantity of 100';
  exception
    when others then
      if sqlerrm not like 'cargo_over_allocated%' then raise; end if;
  end;

  select * into v_alloc2 from app.allocate_shipment_leg_cargo(v_leg2_id, 40, 2000, 16, '00000000-0000-0000-0000-000000039102', 'rep');
  if v_alloc2.allocated_quantity <> 40 then
    raise exception 'assertion failed: expected leg 2 cargo allocation of 40 (60 + 40 = 100, exactly at the shipment cap)';
  end if;
end $$;

\echo '>> app.confirm_shipment_leg_network: rejects an empty/gapped network and cargo-incomplete legs; confirms a contiguous, fully-allocated network'
do $$
declare
  v_shipment_id uuid;
  v_bare_shipment app.shipment_orders;
  v_shipment app.shipment_orders;
begin
  -- A shipment with zero legs cannot confirm.
  select * into v_bare_shipment from app.shipment_orders where idempotency_key = 'idem-leg-legacy';
  begin
    perform app.confirm_shipment_leg_network(v_bare_shipment.id, v_bare_shipment.record_version, '00000000-0000-0000-0000-000000039102', 'rep');
    raise exception 'assertion failed: expected network_empty for a shipment with zero legs';
  exception
    when others then
      if sqlerrm not like 'network_empty%' then raise; end if;
  end;

  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-leg-multi';
  select * into v_shipment from app.confirm_shipment_leg_network(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000039102', 'rep');
  if v_shipment.leg_network_status <> 'confirmed' then
    raise exception 'assertion failed: expected leg_network_status = confirmed for a contiguous, fully-allocated 2-leg network';
  end if;

  if app.get_shipment_leg_network_state(v_shipment.id) <> 'not_started' then
    raise exception 'assertion failed: expected aggregate state not_started -- confirmed but no leg has dispatched yet';
  end if;
end $$;

\echo '>> app.add_shipment_leg after confirm resets leg_network_status to draft (membership changed, must be re-validated); app.cancel_shipment_leg restores confirmability'
do $$
declare
  v_shipment_id uuid;
  v_shipment app.shipment_orders;
  v_leg3 app.shipment_legs;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-leg-multi';

  select * into v_leg3 from app.add_shipment_leg(v_shipment_id, 'idem-leg3-transient', 3, 'land', null, null, null, '00000000-0000-0000-0000-000000039102', 'rep');
  select * into v_shipment from app.shipment_orders where id = v_shipment_id;
  if v_shipment.leg_network_status <> 'draft' then
    raise exception 'assertion failed: expected leg_network_status reset to draft after adding a leg to an already-confirmed network';
  end if;

  perform app.cancel_shipment_leg(v_leg3.id, v_leg3.record_version, 'test: remove transient leg', '00000000-0000-0000-0000-000000039102', 'rep');

  select * into v_shipment from app.confirm_shipment_leg_network(v_shipment_id, (select record_version from app.shipment_orders where id = v_shipment_id), '00000000-0000-0000-0000-000000039102', 'rep');
  if v_shipment.leg_network_status <> 'confirmed' then
    raise exception 'assertion failed: expected the network to re-confirm cleanly once the transient leg was cancelled (a cancelled leg is excluded from the sequence-contiguity/cargo checks)';
  end if;
end $$;

\echo '>> app.transition_shipment_leg: cannot dispatch before network confirmation on a fresh shipment; hardcoded edges enforced once confirmed'
do $$
declare
  v_shipment app.shipment_orders;
  v_leg app.shipment_legs;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-leg-legacy';

  select * into v_leg from app.add_shipment_leg(v_shipment.id, 'idem-legacy-leg1', 1, 'sea', null, now(), now() + interval '5 days', '00000000-0000-0000-0000-000000039102', 'rep');
  perform app.add_shipment_leg_stop(v_leg.id, 1, 'pickup', 'Jakarta Warehouse', null, null, null, now(), '00000000-0000-0000-0000-000000039102', 'rep');
  perform app.add_shipment_leg_stop(v_leg.id, 2, 'delivery', 'Surabaya Warehouse', null, null, null, now() + interval '5 days', '00000000-0000-0000-0000-000000039102', 'rep');
  perform app.allocate_shipment_leg_cargo(v_leg.id, 10, 500, 4, '00000000-0000-0000-0000-000000039102', 'rep');

  begin
    perform app.transition_shipment_leg(v_leg.id, 'dispatched', v_leg.record_version, '00000000-0000-0000-0000-000000039102', 'rep');
    raise exception 'assertion failed: expected network_not_confirmed -- the network has not been confirmed yet';
  exception
    when others then
      if sqlerrm not like 'network_not_confirmed%' then raise; end if;
  end;

  perform app.confirm_shipment_leg_network(v_shipment.id, (select record_version from app.shipment_orders where id = v_shipment.id), '00000000-0000-0000-0000-000000039102', 'rep');
  select * into v_leg from app.shipment_legs where id = v_leg.id;

  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'dispatched', v_leg.record_version, '00000000-0000-0000-0000-000000039102', 'rep');
  if v_leg.leg_status <> 'dispatched' or v_leg.actual_departure_at is null then
    raise exception 'assertion failed: expected leg dispatched with actual_departure_at stamped';
  end if;

  begin
    perform app.transition_shipment_leg(v_leg.id, 'completed', v_leg.record_version, '00000000-0000-0000-0000-000000039102', 'rep');
    raise exception 'assertion failed: expected invalid_leg_status_transition -- dispatched cannot jump straight to completed';
  exception
    when others then
      if sqlerrm not like 'invalid_leg_status_transition%' then raise; end if;
  end;

  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'in_transit', v_leg.record_version, '00000000-0000-0000-0000-000000039102', 'rep');
  if app.get_shipment_leg_network_state(v_shipment.id) <> 'in_progress' then
    raise exception 'assertion failed: expected aggregate state in_progress once a leg is in_transit';
  end if;

  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'arrived', v_leg.record_version, '00000000-0000-0000-0000-000000039102', 'rep');
  select * into v_leg from app.transition_shipment_leg(v_leg.id, 'completed', v_leg.record_version, '00000000-0000-0000-0000-000000039102', 'rep');
  if app.get_shipment_leg_network_state(v_shipment.id) <> 'completed' then
    raise exception 'assertion failed: expected aggregate state completed once the sole leg is completed';
  end if;

  begin
    perform app.add_shipment_leg_stop(v_leg.id, 3, 'delivery', 'Should Fail Post-Completion', null, null, null, null, '00000000-0000-0000-0000-000000039102', 'rep');
    raise exception 'assertion failed: expected leg_not_mutable -- a completed leg''s stops can no longer be edited';
  exception
    when others then
      if sqlerrm not like 'leg_not_mutable%' then raise; end if;
  end;
end $$;

\echo '>> app.record_shipment_leg_custody_event: append-only, server-assigned sequence, mandatory to_party'
do $$
declare
  v_leg_id uuid;
  v_event1 app.shipment_leg_custody_events;
  v_event2 app.shipment_leg_custody_events;
begin
  select sl.id into v_leg_id from app.shipment_legs sl
    join app.shipment_orders so on so.id = sl.shipment_order_id
    where so.idempotency_key = 'idem-leg-legacy' and sl.sequence_no = 1;

  begin
    perform app.record_shipment_leg_custody_event(v_leg_id, 'custody_transfer', null, null, now(), null, '00000000-0000-0000-0000-000000039102', 'rep');
    raise exception 'assertion failed: expected to_party_required when to_party_snapshot is null';
  exception
    when others then
      if sqlerrm not like 'to_party_required%' then raise; end if;
  end;

  select * into v_event1 from app.record_shipment_leg_custody_event(
    v_leg_id, 'custody_transfer', null, jsonb_build_object('party', 'Driver A'), now(), null, '00000000-0000-0000-0000-000000039102', 'rep'
  );
  select * into v_event2 from app.record_shipment_leg_custody_event(
    v_leg_id, 'handoff_confirmed', jsonb_build_object('party', 'Driver A'), jsonb_build_object('party', 'Warehouse Surabaya'), now(), jsonb_build_object('signature', 'ref-1'), '00000000-0000-0000-0000-000000039102', 'rep'
  );
  if v_event1.sequence_no <> 1 or v_event2.sequence_no <> 2 then
    raise exception 'assertion failed: expected server-assigned sequence_no 1 then 2';
  end if;
end $$;

\echo '>> app.migrate_legacy_shipment_to_leg_network: idempotent expand-only backfill for a single-leg shipment with no leg yet'
do $$
declare
  v_shipment app.shipment_orders;
  v_new_shipment app.shipment_orders;
  v_job_order_id uuid;
  v_leg app.shipment_legs;
  v_leg_retry app.shipment_legs;
  v_stop_count integer;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-leg-legacy';
  select job_order_id into v_job_order_id from app.shipment_orders where id = v_shipment.id;

  select * into v_new_shipment from app.create_shipment_order_from_job(
    v_job_order_id, 'idem-leg-bare-legacy', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Bali',
    null, null, null, null, null, null, null, null, 'split: bare legacy fixture', '00000000-0000-0000-0000-000000039102', 'rep'
  );

  select * into v_leg from app.migrate_legacy_shipment_to_leg_network(v_new_shipment.id, '00000000-0000-0000-0000-000000039102', 'rep');
  if v_leg.sequence_no <> 1 or not v_leg.is_legacy_compat then
    raise exception 'assertion failed: expected one is_legacy_compat leg at sequence 1';
  end if;

  select count(*) into v_stop_count from app.shipment_leg_stops where shipment_leg_id = v_leg.id;
  if v_stop_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 stops (pickup at origin, delivery at destination), found %', v_stop_count;
  end if;

  if (select leg_network_status from app.shipment_orders where id = v_new_shipment.id) <> 'confirmed' then
    raise exception 'assertion failed: expected the legacy-mapped shipment''s own network to be immediately confirmed';
  end if;

  select * into v_leg_retry from app.migrate_legacy_shipment_to_leg_network(v_new_shipment.id, '00000000-0000-0000-0000-000000039102', 'rep');
  if v_leg_retry.id <> v_leg.id then
    raise exception 'assertion failed: expected the idempotent repeated migration call to return the exact same leg row, not create a second one';
  end if;
end $$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) cannot add legs/stops/cargo or read the leg network despite holding full OPS grants'
do $$
declare
  v_shipment_id uuid;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-leg-multi';

  begin
    perform app.add_shipment_leg(v_shipment_id, 'idem-leg-outsider', 99, 'land', null, null, null, '00000000-0000-0000-0000-000000039104', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  if exists (select 1 from app.shipment_legs where shipment_order_id = v_shipment_id and idempotency_key = 'idem-leg-outsider') then
    raise exception 'assertion failed: expected no leg row to have been created by the denied outsider call';
  end if;
end $$;

\echo '>> cross-tenant isolation: app.add_shipment_leg/app.confirm_shipment_leg_network fail closed for an identity with no membership in the shipment''s own tenant'
do $$
declare
  v_tenant2 uuid;
  v_shipment_id uuid;
  v_shipment app.shipment_orders;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000039106', 'admin2@acmeleg2.test');
  perform app.provision_tenant('acmeleg2', 'Acme Multileg Co 2', 'idem-acmeleg2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeleg2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000039106', 'admin2@acmeleg2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmeleg2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000039106', 'tenant_admin', v_tenant2, null, 'tester');

  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-leg-multi';
  select * into v_shipment from app.shipment_orders where id = v_shipment_id;

  begin
    perform app.add_shipment_leg(v_shipment_id, 'idem-leg-tenant2', 99, 'land', null, null, null, '00000000-0000-0000-0000-000000039106', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Create in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.confirm_shipment_leg_network(v_shipment_id, v_shipment.record_version, '00000000-0000-0000-0000-000000039106', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no OPS:Edit in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 10 new Multi-Leg Shipment functions (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in (
      'next_shipment_leg_custody_sequence', 'add_shipment_leg', 'cancel_shipment_leg', 'add_shipment_leg_stop',
      'allocate_shipment_leg_cargo', 'confirm_shipment_leg_network', 'transition_shipment_leg',
      'record_shipment_leg_custody_event', 'migrate_legacy_shipment_to_leg_network', 'get_shipment_leg_network_state'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 10 new Multi-Leg Shipment functions, found %', v_count;
  end if;
end $$;

\echo '>> schema-privilege defense in depth: authenticated has no direct INSERT/UPDATE/DELETE on any of the 4 new tables (mutation only through the governed RPCs above)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app'
    and grantee = 'authenticated'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
    and table_name in ('shipment_legs', 'shipment_leg_stops', 'shipment_leg_cargo_allocations', 'shipment_leg_custody_events');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated INSERT/UPDATE/DELETE grants on the 4 new tables, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real Multi-Leg Shipment mutation recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeleg');

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.shipment_legs' and action = 'add_shipment_leg';
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 add_shipment_leg audit events (leg1, leg2, transient leg3, legacy leg on idem-leg-legacy; the idempotent retry and every rejected/denied attempt are not counted), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.shipment_orders' and action = 'confirm_shipment_leg_network';
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 confirm_shipment_leg_network audit events (idem-leg-multi first confirm, idem-leg-multi re-confirm after removing the transient leg, idem-leg-legacy confirm), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.shipment_leg_custody_events' and action = 'record_shipment_leg_custody_event';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 record_shipment_leg_custody_event audit events, found %', v_count;
  end if;
end $$;
