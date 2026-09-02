-- Real, executable test evidence for OPS-169 (Shipment Order, CG-S8-OPS-003) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin (Supreme/tenant_admin-gated rate authority only), a rep (COM:Create/Edit/Approve/View + OPS:Create/Edit), an OPS-viewer-only actor (OPS:View, no Create), a sibling-team outsider (full grants, different team), and two Job Orders (one confirmed, one left in draft) descending from two independent lead->prospect->contact->opportunity->costing->rate->margin->quotation->acceptance->account->job-order-handoff pipelines'
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
  v_job_order_confirmed app.job_orders;
  v_job_order_draft app.job_orders;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009970', 'admin@acmeshp.test'),
    ('00000000-0000-0000-0000-000000009971', 'repa@acmeshp.test'),
    ('00000000-0000-0000-0000-000000009972', 'viewer@acmeshp.test'),
    ('00000000-0000-0000-0000-000000009973', 'outsider@acmeshp.test');

  perform app.provision_tenant('acmeshp', 'Acme Shipping Co', 'idem-acmeshp', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeshp');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMESHP-CO', 'Acme Shipping Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMESHP-CO'), 'ACMESHP-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMESHP-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMESHP-CO'), 'ACMESHP-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMESHP-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009970', 'admin@acmeshp.test', 'Shp Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeshp.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009970', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009971', 'repa@acmeshp.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeshp.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009972', 'viewer@acmeshp.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmeshp.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009973', 'outsider@acmeshp.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeshp.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Shp Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  -- Granter is the bootstrap tenant-admin (9970), never 9971 itself -- this role
  -- carries the protected 'View cost' permission, and app.assign_role's own
  -- self_escalation guard blocks an actor from granting themselves a role version
  -- carrying a protected permission (the same fix OPS-168's own db-test needed).
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000009971', '00000000-0000-0000-0000-000000009970', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Shp Ops Viewer', 'OPS:View only, no Create', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000009972', '00000000-0000-0000-0000-000000009972', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Shp Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000009973', '00000000-0000-0000-0000-000000009971', 'tester');

  -- Pipeline 1 -> a Job Order this file confirms (the "confirmed" fixture).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Shp Test Co', 'Jane Shp', 'jane@shptest.test', '0811',
    '00000000-0000-0000-0000-000000009971', v_team_a, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_lead from app.leads where email = 'jane@shptest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Shp Test Co', 'STC', '77.777.777.7-777.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Ship Ops', 'Procurement Lead', 'jane@shptest.test', '0811', '00000000-0000-0000-0000-000000009971', v_team_a, '00000000-0000-0000-0000-000000009971', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009971', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Shp test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009971', v_team_a, '00000000-0000-0000-0000-000000009971', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-SHP-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009970', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009970', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009971', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009971', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009971', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009971', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009971', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ops lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009971', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Ship Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009971', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000009971', 'rep');

  select * into v_job_order_confirmed from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000009971', 'rep');
  select * into v_job_order_confirmed from app.confirm_job_order(v_job_order_confirmed.id, v_job_order_confirmed.record_version, '00000000-0000-0000-0000-000000009971', 'rep');

  -- Pipeline 2 -> a second, independent Job Order this file deliberately leaves in
  -- draft (the job_order_not_confirmed exception-flow fixture).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Shp Draft Co', 'Bob Shp', 'bob@shpdraft.test', '0822',
    '00000000-0000-0000-0000-000000009971', v_team_a, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_lead from app.leads where email = 'bob@shpdraft.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Shp Draft Co', 'SDC', '88.888.888.8-888.000',
    jsonb_build_object('line1', 'Jl. Thamrin 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Bob Ship Ops', 'Procurement Lead', 'bob@shpdraft.test', '0822', '00000000-0000-0000-0000-000000009971', v_team_a, '00000000-0000-0000-0000-000000009971', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009971', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Shp draft lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Bali', 'target_ready_date', '2026-08-15'),
    '00000000-0000-0000-0000-000000009971', v_team_a, '00000000-0000-0000-0000-000000009971', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-SHP-2', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Bali', '20ft',
    null, null, null, null, 'IDR', 8000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009970', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009970', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009971', 'tester');

  perform app.calculate_margin(v_selection.id, 12000000, 'IDR', 0, '00000000-0000-0000-0000-000000009971', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009971', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight draft lane', v_calc_id, 1, 12000000, 0, 0, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009971', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009971', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Bob Ship Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009971', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000009971', 'rep');
  select * into v_job_order_draft from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000009971', 'rep');
  -- Deliberately never confirmed.
end $$;

\echo '>> app.get_job_shipment_allocation_balance: null basis/remaining before any Shipment Order exists for a Job Order'
do $$
declare
  v_job_order_id uuid;
  v_balance record;
begin
  select id into v_job_order_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeshp') and status = 'confirmed';

  select * into v_balance from app.get_job_shipment_allocation_balance(v_job_order_id, '00000000-0000-0000-0000-000000009971');
  if v_balance.basis_quantity is not null or v_balance.remaining_quantity is not null then
    raise exception 'assertion failed: expected a null basis/remaining before any Shipment Order exists';
  end if;
  if v_balance.allocated_quantity <> 0 then
    raise exception 'assertion failed: expected allocated_quantity 0';
  end if;
end $$;

\echo '>> app.create_shipment_order_from_job: authority-gated (an actor without OPS:Create is denied); requires a confirmed Job Order (job_order_not_confirmed for the draft fixture); creates a real Shipment Order with shipper/cargo inherited verbatim; idempotent on (tenant_id, job_order_id, idempotency_key)'
do $$
declare
  v_job_order_confirmed_id uuid;
  v_job_order_draft_id uuid;
  v_shipment1 app.shipment_orders;
  v_shipment_retry app.shipment_orders;
  v_job_order app.job_orders;
begin
  select id into v_job_order_confirmed_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeshp') and status = 'confirmed';
  select id into v_job_order_draft_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeshp') and status = 'draft';

  begin
    perform app.create_shipment_order_from_job(
      v_job_order_confirmed_id, 'idem-shp-viewer-attempt', '{"legal_name":"Shp Test Co"}'::jsonb, null,
      'ocean_freight', 'sea', 'Jakarta', 'Surabaya', now() + interval '2 days', now() + interval '5 days',
      10, 1000, 20, 15, 1500, 30, null, '00000000-0000-0000-0000-000000009972', 'viewer'
    );
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.create_shipment_order_from_job(
      v_job_order_draft_id, 'idem-shp-draft-attempt', '{"legal_name":"Shp Draft Co"}'::jsonb, null,
      'ocean_freight', 'sea', 'Jakarta', 'Bali', now() + interval '2 days', now() + interval '5 days',
      5, 500, 10, 5, 500, 10, null, '00000000-0000-0000-0000-000000009971', 'rep'
    );
    raise exception 'assertion failed: expected job_order_not_confirmed for the still-draft Job Order';
  exception
    when others then
      if sqlerrm not like 'job_order_not_confirmed%' then
        raise;
      end if;
  end;

  select * into v_job_order from app.job_orders where id = v_job_order_confirmed_id;
  select * into v_shipment1 from app.create_shipment_order_from_job(
    v_job_order_confirmed_id, 'idem-shp-first', null, '{"contact_name":"Warehouse Gate 3"}'::jsonb,
    'ocean_freight', 'sea', 'Jakarta', 'Surabaya', now() + interval '2 days', now() + interval '5 days',
    10, 1000, 20, 15, 1500, 30, null, '00000000-0000-0000-0000-000000009971', 'rep'
  );
  if v_shipment1.status <> 'draft' then
    raise exception 'assertion failed: expected a new Shipment Order in draft status';
  end if;
  if v_shipment1.shipper_account_id <> v_job_order.account_id then
    raise exception 'assertion failed: expected shipper_account_id inherited verbatim from the Job Order';
  end if;
  if v_shipment1.cargo_service_snapshot <> v_job_order.cargo_service_snapshot then
    raise exception 'assertion failed: expected cargo_service_snapshot inherited verbatim from the Job Order';
  end if;
  if v_shipment1.consignee_snapshot <> v_job_order.customer_snapshot then
    raise exception 'assertion failed: expected consignee_snapshot to default to the Job Order''s own customer_snapshot when not explicitly supplied';
  end if;
  if v_shipment1.basis_quantity <> 15 then
    raise exception 'assertion failed: expected the first Shipment Order to declare basis_quantity 15';
  end if;

  select * into v_shipment_retry from app.create_shipment_order_from_job(
    v_job_order_confirmed_id, 'idem-shp-first', null, '{"contact_name":"Warehouse Gate 3"}'::jsonb,
    'ocean_freight', 'sea', 'Jakarta', 'Surabaya', now() + interval '2 days', now() + interval '5 days',
    10, 1000, 20, 15, 1500, 30, null, '00000000-0000-0000-0000-000000009971', 'rep'
  );
  if v_shipment_retry.id <> v_shipment1.id then
    raise exception 'assertion failed: expected the identical retry-idempotency-key call to return the same row';
  end if;
  if (select count(*) from app.shipment_orders where job_order_id = v_job_order_confirmed_id) <> 1 then
    raise exception 'assertion failed: expected exactly one Shipment Order row after the idempotent retry';
  end if;
end $$;

\echo '>> app.create_shipment_order_from_job: a second Shipment Order against the same Job Order requires a non-empty split_reason, and is allocation-balance-checked (over_allocation blocked, a valid split succeeds and is reflected in app.get_job_shipment_allocation_balance)'
do $$
declare
  v_job_order_id uuid;
  v_shipment2 app.shipment_orders;
  v_balance record;
begin
  select id into v_job_order_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeshp') and status = 'confirmed';

  begin
    perform app.create_shipment_order_from_job(
      v_job_order_id, 'idem-shp-split-no-reason', null, null,
      'ocean_freight', 'sea', 'Jakarta', 'Surabaya', now() + interval '3 days', now() + interval '6 days',
      2, 200, 4, null, null, null, null, '00000000-0000-0000-0000-000000009971', 'rep'
    );
    raise exception 'assertion failed: expected split_reason_required for a second Shipment Order with no reason';
  exception
    when others then
      if sqlerrm not like 'split_reason_required%' then
        raise;
      end if;
  end;

  begin
    perform app.create_shipment_order_from_job(
      v_job_order_id, 'idem-shp-split-over-allocate', null, null,
      'ocean_freight', 'sea', 'Jakarta', 'Surabaya', now() + interval '3 days', now() + interval '6 days',
      6, 200, 4, null, null, null, 'partial cargo ready earlier, splitting the remainder', '00000000-0000-0000-0000-000000009971', 'rep'
    );
    raise exception 'assertion failed: expected over_allocation for a quantity exceeding the remaining basis';
  exception
    when others then
      if sqlerrm not like 'over_allocation%' then
        raise;
      end if;
  end;

  select * into v_shipment2 from app.create_shipment_order_from_job(
    v_job_order_id, 'idem-shp-split-valid', null, null,
    'ocean_freight', 'sea', 'Jakarta', 'Surabaya', now() + interval '3 days', now() + interval '6 days',
    3, 300, 6, null, null, null, 'partial cargo ready earlier, splitting the remainder', '00000000-0000-0000-0000-000000009971', 'rep'
  );
  if v_shipment2.split_reason is null then
    raise exception 'assertion failed: expected split_reason recorded on the split Shipment Order';
  end if;
  if v_shipment2.basis_quantity is not null then
    raise exception 'assertion failed: expected the split Shipment Order''s own basis_quantity to stay null -- only the first row declares the basis';
  end if;

  select * into v_balance from app.get_job_shipment_allocation_balance(v_job_order_id, '00000000-0000-0000-0000-000000009971');
  if v_balance.basis_quantity <> 15 or v_balance.allocated_quantity <> 13 or v_balance.remaining_quantity <> 2 then
    raise exception 'assertion failed: expected basis 15 / allocated 13 / remaining 2 after the split, got basis=% allocated=% remaining=%', v_balance.basis_quantity, v_balance.allocated_quantity, v_balance.remaining_quantity;
  end if;
end $$;

\echo '>> app.confirm_shipment_order: optimistic concurrency (stale version rejected), draft -> confirmed, and a second confirm attempt is rejected (invalid_transition)'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-shp-first';

  begin
    perform app.confirm_shipment_order(v_shipment.id, v_shipment.record_version + 99, '00000000-0000-0000-0000-000000009971', 'rep');
    raise exception 'assertion failed: expected stale_version to be rejected';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then
        raise;
      end if;
  end;

  select * into v_shipment from app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000009971', 'rep');
  if v_shipment.status <> 'confirmed' then
    raise exception 'assertion failed: expected draft -> confirmed';
  end if;

  begin
    perform app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000009971', 'rep');
    raise exception 'assertion failed: expected a second confirm to be rejected as invalid_transition';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;
end $$;

\echo '>> app.cancel_shipment_order: mandatory reason enforced; a valid cancel moves status to cancelled and releases its own allocation from app.get_job_shipment_allocation_balance'
do $$
declare
  v_shipment app.shipment_orders;
  v_job_order_id uuid;
  v_balance_before record;
  v_balance_after record;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-shp-split-valid';
  v_job_order_id := v_shipment.job_order_id;

  select * into v_balance_before from app.get_job_shipment_allocation_balance(v_job_order_id, '00000000-0000-0000-0000-000000009971');

  begin
    perform app.cancel_shipment_order(v_shipment.id, v_shipment.record_version, '', '00000000-0000-0000-0000-000000009971', 'rep');
    raise exception 'assertion failed: expected cancel_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'cancel_reason_required%' then
        raise;
      end if;
  end;

  select * into v_shipment from app.cancel_shipment_order(v_shipment.id, v_shipment.record_version, 'customer cancelled the split leg', '00000000-0000-0000-0000-000000009971', 'rep');
  if v_shipment.status <> 'cancelled' then
    raise exception 'assertion failed: expected confirmed/draft -> cancelled';
  end if;

  select * into v_balance_after from app.get_job_shipment_allocation_balance(v_job_order_id, '00000000-0000-0000-0000-000000009971');
  if v_balance_after.allocated_quantity <> v_balance_before.allocated_quantity - 3 then
    raise exception 'assertion failed: expected the cancelled Shipment Order''s own 3-unit allocation released from the running total';
  end if;
end $$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) cannot access the Shipment Order via app.confirm_shipment_order/app.cancel_shipment_order despite holding full OPS/COM permissions'
do $$
declare
  v_job_order_id uuid;
  v_shipment app.shipment_orders;
begin
  select id into v_job_order_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeshp') and status = 'confirmed';

  -- A fresh draft-status split (idem-shp-first is now confirmed, idem-shp-split-valid
  -- is now cancelled -- neither is in draft anymore, so a real record-scope denial
  -- needs its own still-draft fixture).
  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order_id, 'idem-shp-record-scope', null, null,
    'ocean_freight', 'sea', 'Jakarta', 'Surabaya', now() + interval '3 days', now() + interval '6 days',
    1, 100, 2, null, null, null, 'record-scope test fixture', '00000000-0000-0000-0000-000000009971', 'rep'
  );

  begin
    perform app.confirm_shipment_order(v_shipment.id, v_shipment.record_version, '00000000-0000-0000-0000-000000009973', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.cancel_shipment_order(v_shipment.id, v_shipment.record_version, 'outsider attempt', '00000000-0000-0000-0000-000000009973', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> cross-tenant isolation: app.get_job_shipment_allocation_balance/app.create_shipment_order_from_job fail closed for an identity with no membership in the Job Order''s own tenant -- ISS-2026-146 fix: app.create_shipment_order_from_job (a bare-id lookup) now raises a generic job_order_not_found for this zero-membership caller, never a tenant_id-disclosing insufficient_authority; app.get_job_shipment_allocation_balance (not part of this fix) is unaffected'
do $$
declare
  v_tenant2 uuid;
  v_job_order_id uuid;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000009974', 'admin2@acmeshp2.test');
  perform app.provision_tenant('acmeshp2', 'Acme Shipping Co 2', 'idem-acmeshp2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeshp2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009974', 'admin2@acmeshp2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmeshp2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009974', 'tenant_admin', v_tenant2, null, 'tester');

  select id into v_job_order_id from app.job_orders where tenant_id = (select id from app.tenants where slug = 'acmeshp') and status = 'confirmed';

  begin
    perform app.get_job_shipment_allocation_balance(v_job_order_id, '00000000-0000-0000-0000-000000009974');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no membership in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    -- ISS-2026-146: admin2 has ZERO app.principal_memberships row in tenant1 at all
    -- (granted tenant_admin only in tenant2 above) -- before the fix this raised
    -- insufficient_authority with tenant1's real tenant_id embedded in the message;
    -- now it raises the identical generic job_order_not_found a nonexistent job
    -- order id would.
    perform app.create_shipment_order_from_job(
      v_job_order_id, 'idem-shp-cross-tenant', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
      null, null, null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000009974', 'tenant2-admin'
    );
    raise exception 'assertion failed: expected job_order_not_found for tenant 2''s admin (zero relationship to tenant1) on app.create_shipment_order_from_job, the call unexpectedly succeeded';
  exception
    when others then
      if sqlerrm not like 'job_order_not_found%' then
        raise;
      end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any new Shipment Order function (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in ('next_shipment_number', 'get_job_shipment_allocation_balance', 'create_shipment_order_from_job', 'confirm_shipment_order', 'cancel_shipment_order');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 5 new Shipment Order functions, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: create (x3, first + split + record-scope fixture)/confirm/cancel each recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeshp');
  select count(*) into v_count
  from app.audit_logs
  where tenant_id = v_tenant1
    and resource_type = 'app.shipment_orders'
    and action in ('create_shipment_order_from_job', 'confirm_shipment_order', 'cancel_shipment_order');
  if v_count <> 5 then
    raise exception 'assertion failed: expected exactly 5 audit events (3 real creates, 1 confirm, 1 cancel -- idempotent retry is a no-op), found %', v_count;
  end if;
end $$;
