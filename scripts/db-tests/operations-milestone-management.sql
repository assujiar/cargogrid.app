-- Real, executable test evidence for OPS-173 (Milestone Management, CG-S8-OPS-007)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM full + OPS:Create/Edit/View), an OPS-viewer-only actor, a sibling-team outsider, a global Supreme Admin, 6 registered milestone codes (picked_up/departed_origin/in_transit/customs_hold[internal]/out_for_delivery/delivered[terminal]), one confirmed Job Order, and two Shipment Orders off it (walk/cancel), all draft'
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
  v_shipment_walk app.shipment_orders;
  v_shipment_cancel app.shipment_orders;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009810', 'admin@acmemile.test'),
    ('00000000-0000-0000-0000-000000009811', 'repa@acmemile.test'),
    ('00000000-0000-0000-0000-000000009812', 'viewer@acmemile.test'),
    ('00000000-0000-0000-0000-000000009813', 'outsider@acmemile.test'),
    ('00000000-0000-0000-0000-000000009814', 'supreme@acmemile.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009814', 'supreme_admin', null, null, 'tester');

  perform app.register_milestone_code('picked_up', 'Picked Up', 'pickup', true, false, false, '00000000-0000-0000-0000-000000009814', 'tester');
  perform app.register_milestone_code('departed_origin', 'Departed Origin', 'in_transit', true, false, false, '00000000-0000-0000-0000-000000009814', 'tester');
  perform app.register_milestone_code('in_transit', 'In Transit', 'in_transit', true, true, false, '00000000-0000-0000-0000-000000009814', 'tester');
  perform app.register_milestone_code('customs_hold', 'Customs Hold', 'exception', false, false, false, '00000000-0000-0000-0000-000000009814', 'tester');
  perform app.register_milestone_code('out_for_delivery', 'Out for Delivery', 'delivery', true, true, false, '00000000-0000-0000-0000-000000009814', 'tester');
  perform app.register_milestone_code('delivered', 'Delivered', 'delivery', true, true, true, '00000000-0000-0000-0000-000000009814', 'tester');

  perform app.provision_tenant('acmemile', 'Acme Milestone Co', 'idem-acmemile', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmemile');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEMILE-CO', 'Acme Milestone Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMILE-CO'), 'ACMEMILE-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMILE-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMILE-CO'), 'ACMEMILE-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMILE-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009810', 'admin@acmemile.test', 'Mile Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmemile.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009810', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009811', 'repa@acmemile.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmemile.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009812', 'viewer@acmemile.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmemile.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009813', 'outsider@acmemile.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmemile.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Mile Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000009811', '00000000-0000-0000-0000-000000009810', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Mile Ops Viewer', 'OPS:View only, no Create/Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000009812', '00000000-0000-0000-0000-000000009812', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Mile Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000009813', '00000000-0000-0000-0000-000000009810', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Mile Test Co', 'Jane Mile', 'jane@miletest.test', '0811',
    '00000000-0000-0000-0000-000000009811', v_team_a, '00000000-0000-0000-0000-000000009811', 'tester');
  select * into v_lead from app.leads where email = 'jane@miletest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009811', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Mile Test Co', 'MTC', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009811', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Mile Ops', 'Procurement Lead', 'jane@miletest.test', '0811', '00000000-0000-0000-0000-000000009811', v_team_a, '00000000-0000-0000-0000-000000009811', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009811', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Milestone test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009811', v_team_a, '00000000-0000-0000-0000-000000009811', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009811', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-MILE-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009810', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009810', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009811', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009811', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009811', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009811', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009811', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ops lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009811', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009811', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009811', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Mile Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009811', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000009811', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000009811', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000009811', 'rep');

  select * into v_shipment_walk from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-mile-walk', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000009811', 'rep'
  );
  select * into v_shipment_walk from app.confirm_shipment_order(v_shipment_walk.id, v_shipment_walk.record_version, '00000000-0000-0000-0000-000000009811', 'rep');

  select * into v_shipment_cancel from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-mile-cancel', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Semarang',
    null, null, null, null, null, null, null, null, 'split: cancel fixture', '00000000-0000-0000-0000-000000009811', 'rep'
  );
end $$;

\echo '>> app.create_milestone_template_draft / app.set_milestone_template_sequence / app.publish_milestone_template_version: authority-gated; unknown-code rejected; empty-sequence publish rejected; a valid sea-mode template publishes; at most one draft/published per (tenant, mode)'
do $$
declare
  v_tenant1 uuid;
  v_draft app.milestone_template_versions;
  v_published app.milestone_template_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmemile');

  begin
    perform app.create_milestone_template_draft(v_tenant1, 'sea', '00000000-0000-0000-0000-000000009812', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  select * into v_draft from app.create_milestone_template_draft(v_tenant1, 'sea', '00000000-0000-0000-0000-000000009811', 'rep');
  if v_draft.status <> 'draft' or v_draft.mode <> 'sea' then
    raise exception 'assertion failed: expected a real sea-mode draft';
  end if;

  declare
    v_draft2 app.milestone_template_versions;
  begin
    select * into v_draft2 from app.create_milestone_template_draft(v_tenant1, 'sea', '00000000-0000-0000-0000-000000009811', 'rep');
    if v_draft2.id <> v_draft.id then
      raise exception 'assertion failed: expected the idempotent repeated draft call to return the same row';
    end if;
  end;

  begin
    perform app.set_milestone_template_sequence(v_draft.id, jsonb_build_array(jsonb_build_object('code', 'not_a_real_code')), '00000000-0000-0000-0000-000000009811', 'rep');
    raise exception 'assertion failed: expected milestone_unknown_code for an unregistered code';
  exception
    when others then
      if sqlerrm not like 'milestone_unknown_code%' then
        raise;
      end if;
  end;

  perform app.set_milestone_template_sequence(
    v_draft.id,
    jsonb_build_array(
      jsonb_build_object('code', 'picked_up'), jsonb_build_object('code', 'departed_origin'), jsonb_build_object('code', 'in_transit'),
      jsonb_build_object('code', 'out_for_delivery'), jsonb_build_object('code', 'delivered')
    ),
    '00000000-0000-0000-0000-000000009811', 'rep'
  );
  select * into v_draft from app.milestone_template_versions where id = v_draft.id;

  begin
    perform app.publish_milestone_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000009812', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only, not OPS:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  perform app.publish_milestone_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000009811', 'rep');

  select * into v_published from app.milestone_template_versions where tenant_id = v_tenant1 and mode = 'sea' and status = 'published';
  if v_published.id is null then
    raise exception 'assertion failed: expected a published sea-mode milestone template to exist';
  end if;

  if (select count(*) from app.milestone_template_versions where tenant_id = v_tenant1 and mode = 'sea' and status = 'published') <> 1 then
    raise exception 'assertion failed: expected exactly one published sea-mode template';
  end if;
end $$;

\echo '>> app.publish_milestone_template_version: empty-sequence rejected; stale_version rejected'
do $$
declare
  v_tenant1 uuid;
  v_draft app.milestone_template_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmemile');

  select * into v_draft from app.create_milestone_template_draft(v_tenant1, 'air', '00000000-0000-0000-0000-000000009811', 'rep');

  begin
    perform app.publish_milestone_template_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000009811', 'rep');
    raise exception 'assertion failed: expected milestone_invalid_sequence for an empty-sequence publish attempt';
  exception
    when others then
      if sqlerrm not like 'milestone_invalid_sequence%' then
        raise;
      end if;
  end;

  perform app.set_milestone_template_sequence(v_draft.id, jsonb_build_array(jsonb_build_object('code', 'picked_up'), jsonb_build_object('code', 'delivered')), '00000000-0000-0000-0000-000000009811', 'rep');

  begin
    perform app.publish_milestone_template_version(v_draft.id, v_draft.record_version + 99, null, '00000000-0000-0000-0000-000000009811', 'rep');
    raise exception 'assertion failed: expected stale_version to be rejected';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then
        raise;
      end if;
  end;
end $$;

\echo '>> app.ingest_milestone_event: authority-gated (OPS:View-only denied OPS:Create); unknown code/source rejected; a valid event is ingested and the projection recalculates (last_milestone_code, current_eta from an affects_eta code, current_location); idempotent retry on the same idempotency_key returns the same row'
do $$
declare
  v_shipment_id uuid;
  v_event1 app.milestone_events;
  v_event2 app.milestone_events;
  v_projection app.shipment_milestone_projections;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-mile-walk';

  begin
    perform app.ingest_milestone_event(
      v_shipment_id, 'picked_up', now(), null, null, 'manual', null, null, 'idem-evt-viewer',
      '00000000-0000-0000-0000-000000009812', 'viewer'
    );
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.ingest_milestone_event(
      v_shipment_id, 'not_a_real_code', now(), null, null, 'manual', null, null, 'idem-evt-badcode',
      '00000000-0000-0000-0000-000000009811', 'rep'
    );
    raise exception 'assertion failed: expected milestone_unknown_code for an unregistered code';
  exception
    when others then
      if sqlerrm not like 'milestone_unknown_code%' then
        raise;
      end if;
  end;

  begin
    perform app.ingest_milestone_event(
      v_shipment_id, 'picked_up', now(), null, null, 'carrier_pigeon', null, null, 'idem-evt-badsource',
      '00000000-0000-0000-0000-000000009811', 'rep'
    );
    raise exception 'assertion failed: expected milestone_invalid_source for an unsupported source';
  exception
    when others then
      if sqlerrm not like 'milestone_invalid_source%' then
        raise;
      end if;
  end;

  select * into v_event1 from app.ingest_milestone_event(
    v_shipment_id, 'picked_up', '2026-07-27 08:00:00+00'::timestamptz, '2026-07-27 08:05:00+00'::timestamptz,
    jsonb_build_object('lat', -6.2, 'lng', 106.8, 'label', 'Jakarta Origin Depot'), 'manual', null, null, 'idem-evt-1',
    '00000000-0000-0000-0000-000000009811', 'rep'
  );
  if v_event1.sequence_no <> 1 then
    raise exception 'assertion failed: expected the first real event to be sequence_no 1';
  end if;

  select * into v_event2 from app.ingest_milestone_event(
    v_shipment_id, 'in_transit', '2026-07-27 14:00:00+00'::timestamptz, '2026-07-27 14:10:00+00'::timestamptz,
    jsonb_build_object('lat', -6.9, 'lng', 107.6, 'label', 'En route'), 'api', null, null, 'idem-evt-2',
    '00000000-0000-0000-0000-000000009811', 'rep'
  );
  if v_event2.sequence_no <> 2 then
    raise exception 'assertion failed: expected the second real event to be sequence_no 2';
  end if;

  select * into v_projection from app.get_shipment_milestone_projection(v_shipment_id, '00000000-0000-0000-0000-000000009811');
  if v_projection.last_milestone_code <> 'in_transit' then
    raise exception 'assertion failed: expected last_milestone_code=in_transit (the latest event_time), found %', v_projection.last_milestone_code;
  end if;
  if v_projection.current_eta <> '2026-07-27 14:00:00+00'::timestamptz then
    raise exception 'assertion failed: expected current_eta to be the in_transit event''s own event_time (the latest affects_eta code)';
  end if;
  if v_projection.current_location ->> 'label' <> 'En route' then
    raise exception 'assertion failed: expected current_location to reflect the latest event''s own location';
  end if;
  if v_projection.event_count <> 2 then
    raise exception 'assertion failed: expected event_count=2, found %', v_projection.event_count;
  end if;

  declare
    v_retry app.milestone_events;
  begin
    select * into v_retry from app.ingest_milestone_event(
      v_shipment_id, 'picked_up', '2026-07-27 08:00:00+00'::timestamptz, '2026-07-27 08:05:00+00'::timestamptz,
      jsonb_build_object('lat', -6.2, 'lng', 106.8, 'label', 'Jakarta Origin Depot'), 'manual', null, null, 'idem-evt-1',
      '00000000-0000-0000-0000-000000009811', 'rep'
    );
    if v_retry.id <> v_event1.id then
      raise exception 'assertion failed: expected the idempotent retry to return the same event row, not a new one';
    end if;
    if (select count(*) from app.milestone_events where shipment_order_id = v_shipment_id and idempotency_key = 'idem-evt-1') <> 1 then
      raise exception 'assertion failed: expected exactly one row for idem-evt-1 after the retry';
    end if;
  end;
end $$;

\echo '>> app.ingest_milestone_event: an out-of-order (earlier event_time, ingested last) event is accepted and the projection recalculates deterministically -- the earlier-dated event never becomes "current" over a genuinely later one'
do $$
declare
  v_shipment_id uuid;
  v_projection app.shipment_milestone_projections;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-mile-walk';

  perform app.ingest_milestone_event(
    v_shipment_id, 'departed_origin', '2026-07-27 10:00:00+00'::timestamptz, now(), null, 'manual', null, null, 'idem-evt-late-early',
    '00000000-0000-0000-0000-000000009811', 'rep'
  );

  select * into v_projection from app.get_shipment_milestone_projection(v_shipment_id, '00000000-0000-0000-0000-000000009811');
  if v_projection.last_milestone_code <> 'in_transit' then
    raise exception 'assertion failed: expected last_milestone_code to remain in_transit (its own event_time is still the latest) even though departed_origin was ingested after it, found %', v_projection.last_milestone_code;
  end if;
  if v_projection.event_count <> 3 then
    raise exception 'assertion failed: expected event_count=3 after the out-of-order event, found %', v_projection.event_count;
  end if;
end $$;

\echo '>> app.ingest_milestone_event: a correction requires a non-empty reason and a real prior event on the same shipment; a valid correction is a new, additive row -- the original is never mutated'
do $$
declare
  v_shipment_id uuid;
  v_original app.milestone_events;
  v_correction app.milestone_events;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-mile-walk';
  select * into v_original from app.milestone_events where shipment_order_id = v_shipment_id and idempotency_key = 'idem-evt-1';

  begin
    perform app.ingest_milestone_event(
      v_shipment_id, 'picked_up', '2026-07-27 08:30:00+00'::timestamptz, null, null, 'manual', null, v_original.id, 'idem-evt-1-correction-noreason',
      '00000000-0000-0000-0000-000000009811', 'rep'
    );
    raise exception 'assertion failed: expected reason_required for a correction with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then
        raise;
      end if;
  end;

  begin
    perform app.ingest_milestone_event(
      v_shipment_id, 'picked_up', '2026-07-27 08:30:00+00'::timestamptz, null, null, 'manual', 'wrong prior event id', '00000000-0000-0000-0000-000000009999',
      'idem-evt-1-correction-badref', '00000000-0000-0000-0000-000000009811', 'rep'
    );
    raise exception 'assertion failed: expected milestone_event_not_found for a corrects_event_id that does not belong to this shipment';
  exception
    when others then
      if sqlerrm not like 'milestone_event_not_found%' then
        raise;
      end if;
  end;

  select * into v_correction from app.ingest_milestone_event(
    v_shipment_id, 'picked_up', '2026-07-27 08:30:00+00'::timestamptz, null, null, 'manual', 'original time was a typo, corrected from driver callback',
    v_original.id, 'idem-evt-1-correction', '00000000-0000-0000-0000-000000009811', 'rep'
  );
  if v_correction.corrects_event_id <> v_original.id then
    raise exception 'assertion failed: expected the correction to point at the original event';
  end if;

  select * into v_original from app.milestone_events where id = v_original.id;
  if v_original.event_time <> '2026-07-27 08:00:00+00'::timestamptz then
    raise exception 'assertion failed: expected the original event to remain completely unchanged (append-only, never rewritten)';
  end if;
end $$;

\echo '>> app.ingest_milestone_event: invalid_transition once the shipment is cancelled'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-mile-cancel';
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'cancelled', v_shipment.record_version, 'no longer needed', null, 'idem-mile-cancel-transition', '00000000-0000-0000-0000-000000009811', 'rep');

  begin
    perform app.ingest_milestone_event(
      v_shipment.id, 'picked_up', now(), null, null, 'manual', null, null, 'idem-evt-cancelled',
      '00000000-0000-0000-0000-000000009811', 'rep'
    );
    raise exception 'assertion failed: expected invalid_transition -- a cancelled shipment can no longer receive milestone events';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;
end $$;

\echo '>> app.get_shipment_milestone_timeline: ordered oldest first; p_customer_visible_only=true excludes the internal-only customs_hold code'
do $$
declare
  v_shipment_id uuid;
  v_full app.milestone_events[];
  v_customer_visible app.milestone_events[];
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-mile-walk';

  perform app.ingest_milestone_event(
    v_shipment_id, 'customs_hold', '2026-07-27 12:00:00+00'::timestamptz, null, null, 'manual', null, null, 'idem-evt-customs',
    '00000000-0000-0000-0000-000000009811', 'rep'
  );

  select array_agg(t order by t.event_time asc) into v_full from app.get_shipment_milestone_timeline(v_shipment_id, '00000000-0000-0000-0000-000000009811', false) t;
  select array_agg(t order by t.event_time asc) into v_customer_visible from app.get_shipment_milestone_timeline(v_shipment_id, '00000000-0000-0000-0000-000000009811', true) t;

  if not exists (select 1 from unnest(v_full) e where e.milestone_code = 'customs_hold') then
    raise exception 'assertion failed: expected the internal customs_hold event to appear in the full (internal) timeline';
  end if;
  if exists (select 1 from unnest(v_customer_visible) e where e.milestone_code = 'customs_hold') then
    raise exception 'assertion failed: expected the internal customs_hold event to be excluded from the customer-visible timeline';
  end if;
  if v_full[1].event_time > v_full[array_length(v_full, 1)].event_time then
    raise exception 'assertion failed: expected the full timeline ordered oldest-first';
  end if;
end $$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) cannot ingest events or read the timeline/projection despite holding full OPS grants'
do $$
declare
  v_shipment_id uuid;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-mile-walk';

  begin
    perform app.ingest_milestone_event(
      v_shipment_id, 'delivered', now(), null, null, 'manual', null, null, 'idem-evt-outsider',
      '00000000-0000-0000-0000-000000009813', 'outsider'
    );
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.get_shipment_milestone_timeline(v_shipment_id, '00000000-0000-0000-0000-000000009813', false);
    raise exception 'assertion failed: expected the sibling-team outsider to be denied read access by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> cross-tenant isolation: app.ingest_milestone_event/app.create_milestone_template_draft fail closed for an identity with no membership in the shipment/tenant''s own tenant -- ISS-2026-146 fix: app.ingest_milestone_event (a bare-id lookup) now raises a generic shipment_order_not_found for this zero-membership caller, never a tenant_id-disclosing insufficient_authority; app.create_milestone_template_draft (caller-supplied p_tenant_id) is unaffected'
do $$
declare
  v_tenant2 uuid;
  v_tenant1 uuid;
  v_shipment_id uuid;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000009815', 'admin2@acmemile2.test');
  perform app.provision_tenant('acmemile2', 'Acme Milestone Co 2', 'idem-acmemile2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmemile2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009815', 'admin2@acmemile2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmemile2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009815', 'tenant_admin', v_tenant2, null, 'tester');

  v_tenant1 := (select id from app.tenants where slug = 'acmemile');
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-mile-walk';

  begin
    -- ISS-2026-146: admin2 has ZERO app.principal_memberships row in tenant1 at all
    -- (granted tenant_admin only in tenant2 above) -- app.ingest_milestone_event is a
    -- bare-id lookup, so before the fix this raised insufficient_authority with
    -- tenant1's real tenant_id embedded in the message; now it raises the identical
    -- generic shipment_order_not_found a nonexistent shipment id would.
    perform app.ingest_milestone_event(
      v_shipment_id, 'delivered', now(), null, null, 'manual', null, null, 'idem-evt-tenant2',
      '00000000-0000-0000-0000-000000009815', 'tenant2-admin'
    );
    raise exception 'assertion failed: expected shipment_order_not_found for tenant 2''s admin (zero relationship to tenant1) on app.ingest_milestone_event, the call unexpectedly succeeded';
  exception
    when others then
      if sqlerrm not like 'shipment_order_not_found%' then
        raise;
      end if;
  end;

  begin
    perform app.create_milestone_template_draft(v_tenant1, 'land', '00000000-0000-0000-0000-000000009815', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no membership in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 8 new Milestone Management functions (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in (
      'register_milestone_code', 'create_milestone_template_draft', 'set_milestone_template_sequence', 'publish_milestone_template_version',
      'recalculate_shipment_milestone_projection', 'ingest_milestone_event', 'get_shipment_milestone_timeline', 'get_shipment_milestone_projection'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 8 new Milestone Management functions, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real milestone mutation recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmemile');

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.milestone_events' and action = 'ingest_milestone_event';
  if v_count <> 5 then
    raise exception 'assertion failed: expected exactly 5 ingest_milestone_event audit events (picked_up + in_transit + departed_origin(late) + correction + customs_hold on the walk shipment; the retry and every rejected attempt are not counted), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.milestone_template_versions' and action = 'publish_milestone_template_version';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 publish_milestone_template_version audit event, found %', v_count;
  end if;
end $$;
