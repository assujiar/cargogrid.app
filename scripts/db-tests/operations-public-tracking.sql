-- Real, executable test evidence for OPS-180 (Basic Public and Customer Tracking,
-- CG-S8-OPS-014) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (OPS full), a sibling-team outsider, a Supreme Admin, 3 registered customer-visible/internal milestone codes, one confirmed Job Order, and two confirmed Shipment Orders (in_transit with a customer-visible milestone plus an internal-only one; epod-completed)'
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
  v_vendor app.master_records;
  v_vendor_b app.master_records;
  v_shipment_a app.shipment_orders;
  v_shipment_b app.shipment_orders;
  v_capture app.epod_captures;
  v_signature app.files;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000023501', 'admin@acmetrack.test'),
    ('00000000-0000-0000-0000-000000023502', 'repa@acmetrack.test'),
    ('00000000-0000-0000-0000-000000023504', 'outsider@acmetrack.test'),
    ('00000000-0000-0000-0000-000000023506', 'supreme@acmetrack.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023506', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmetrack', 'Acme Track Co', 'idem-acmetrack', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmetrack');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMETRACK-CO', 'Acme Track Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMETRACK-CO'), 'ACMETRACK-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMETRACK-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMETRACK-CO'), 'ACMETRACK-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMETRACK-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023501', 'admin@acmetrack.test', 'Track Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmetrack.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023501', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023502', 'repa@acmetrack.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmetrack.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023504', 'outsider@acmetrack.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmetrack.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Track Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000023502', '00000000-0000-0000-0000-000000023501', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Track Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000023504', '00000000-0000-0000-0000-000000023501', 'tester');

  perform app.register_milestone_code('picked_up', 'Picked Up', 'pickup', true, false, false, '00000000-0000-0000-0000-000000023506', 'supreme');
  perform app.register_milestone_code('customs_hold', 'Customs Hold', 'exception', false, false, false, '00000000-0000-0000-0000-000000023506', 'supreme');
  perform app.register_milestone_code('delivered', 'Delivered', 'delivery', true, false, true, '00000000-0000-0000-0000-000000023506', 'supreme');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Track Test Co', 'Jane Track', 'jane@tracktest.test', '0811',
    '00000000-0000-0000-0000-000000023502', v_team_a, '00000000-0000-0000-0000-000000023502', 'tester');
  select * into v_lead from app.leads where email = 'jane@tracktest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023502', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Track Test Co', 'TRK', '11.111.111.6-666.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 6', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023502', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Track Ops', 'Procurement Lead', 'jane@tracktest.test', '0811', '00000000-0000-0000-0000-000000023502', v_team_a, '00000000-0000-0000-0000-000000023502', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023502', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Track test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023502', v_team_a, '00000000-0000-0000-0000-000000023502', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023502', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-TRACK-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023501', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000023501', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000023502', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000023502', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000023502', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000023502', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023502', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight track lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000023502', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000023502', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000023502', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Track Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000023502', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000023502', 'rep');

  select * into v_vendor from app.create_master_record('vendor', v_tenant1, 'VEND-TRACK-1', 'Contoso Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023501', 'admin');
  select * into v_vendor_b from app.create_master_record('vendor', v_tenant1, 'VEND-TRACK-2', 'Fabrikam Trucking', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000023501', 'admin');

  -- Shipment A: in_transit, one customer-visible milestone (picked_up), one internal-only (customs_hold).
  select * into v_shipment_a from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-track-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() - interval '2 days', now() + interval '5 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000023502', 'rep'
  );
  select * into v_shipment_a from app.confirm_shipment_order(v_shipment_a.id, v_shipment_a.record_version, '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'planned', v_shipment_a.record_version, null, null, 'idem-track-a-planned', '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'assigned', v_shipment_a.record_version, null, null, 'idem-track-a-assigned', '00000000-0000-0000-0000-000000023502', 'rep');
  perform app.assign_resource(v_shipment_a.id, 'vendor', v_vendor.id, '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'dispatched', v_shipment_a.record_version, null, null, 'idem-track-a-dispatched', '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_a from app.transition_shipment_order(v_shipment_a.id, 'in_transit', v_shipment_a.record_version, null, null, 'idem-track-a-intransit', '00000000-0000-0000-0000-000000023502', 'rep');
  perform app.ingest_milestone_event(v_shipment_a.id, 'picked_up', now() - interval '1 day', null, null, 'manual', null, null, 'idem-track-a-picked-up', '00000000-0000-0000-0000-000000023502', 'rep');
  perform app.ingest_milestone_event(v_shipment_a.id, 'customs_hold', now() - interval '12 hours', null, null, 'manual', null, null, 'idem-track-a-customs', '00000000-0000-0000-0000-000000023502', 'rep');

  -- Shipment B: delivered, then epod once the ePOD capture completes (OPS-177's own wrapper transition).
  select * into v_shipment_b from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-track-b', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Bandung',
    now() - interval '3 days', now() - interval '1 hours', null, null, null, null, null, null, 'split: track second fixture', '00000000-0000-0000-0000-000000023502', 'rep'
  );
  select * into v_shipment_b from app.confirm_shipment_order(v_shipment_b.id, v_shipment_b.record_version, '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'planned', v_shipment_b.record_version, null, null, 'idem-track-b-planned', '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'assigned', v_shipment_b.record_version, null, null, 'idem-track-b-assigned', '00000000-0000-0000-0000-000000023502', 'rep');
  perform app.assign_resource(v_shipment_b.id, 'vendor', v_vendor_b.id, '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'dispatched', v_shipment_b.record_version, null, null, 'idem-track-b-dispatched', '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'in_transit', v_shipment_b.record_version, null, null, 'idem-track-b-intransit', '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_b from app.transition_shipment_order(v_shipment_b.id, 'delivered', v_shipment_b.record_version, null, 'physical delivery confirmed', 'idem-track-b-delivered', '00000000-0000-0000-0000-000000023502', 'rep');

  perform app.register_document_type('epod', 'Electronic Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000023506', 'supreme');
  declare
    v_pod_draft app.config_versions;
  begin
    v_pod_draft := app.create_config_draft('document:epod', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023501', 'admin');
    perform app.set_config_items(v_pod_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('image/jpeg')),
      jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
      jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
      jsonb_build_object('key', 'default_classification', 'value', 'internal'),
      jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
    ), '00000000-0000-0000-0000-000000023501', 'admin');
    perform app.publish_document_type_definition(v_pod_draft.id, '00000000-0000-0000-0000-000000023501', now(), 'admin');
  end;

  v_capture := app.start_epod_capture(v_tenant1, v_shipment_b.id, null, 'idem-track-b-cap', '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_signature from app.initiate_file_upload(
    v_tenant1, 'epod', 'shipment_order', v_shipment_b.id, 'signature-track-b.jpg', 'image/jpeg', 20480, null, false, null, '{}'::uuid[], null, 'idem-track-b-sig', '00000000-0000-0000-0000-000000023502', 'rep'
  );
  perform app.record_file_scan_result(v_signature.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023502', 'rep');
  v_capture := app.set_epod_evidence(v_capture.id, 'Budi Santoso', 'Warehouse Staff', v_signature.id, '{}'::uuid[], null, now(), '00000000-0000-0000-0000-000000023502', 'rep');
  v_capture := app.submit_epod_capture(v_capture.id, v_capture.record_version, '00000000-0000-0000-0000-000000023502', 'rep');
  v_capture := app.review_epod_capture(v_capture.id, 'approved', 'looks good', v_capture.record_version, '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_shipment_b from app.shipment_orders so where so.id = v_shipment_b.id;
  perform app.complete_epod_capture(v_capture.id, v_capture.record_version, v_shipment_b.record_version, 'idem-track-b-complete', '00000000-0000-0000-0000-000000023502', 'rep');
end $$;

\echo '>> app.issue_shipment_tracking_token: authority/record-scope gated, revokes the prior active token when reissued (at most one active at a time); app.revoke_shipment_tracking_token: reason required'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-track-a');
  v_issue1 record;
  v_issue2 record;
  v_prior app.shipment_tracking_tokens;
begin
  begin
    perform app.issue_shipment_tracking_token(v_shipment_a_id, 30, '00000000-0000-0000-0000-000000023504', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope despite full OPS grants';
  exception
    when insufficient_privilege then null;
  end;

  select * into v_issue1 from app.issue_shipment_tracking_token(v_shipment_a_id, 30, '00000000-0000-0000-0000-000000023502', 'rep');
  if v_issue1.raw_token is null or length(v_issue1.raw_token) < 32 then
    raise exception 'assertion failed: expected a real, non-trivial raw_token';
  end if;

  select * into v_issue2 from app.issue_shipment_tracking_token(v_shipment_a_id, 30, '00000000-0000-0000-0000-000000023502', 'rep');
  if v_issue1.token_id = v_issue2.token_id then
    raise exception 'assertion failed: expected reissuance to create a brand-new token row';
  end if;
  select * into v_prior from app.shipment_tracking_tokens where id = v_issue1.token_id;
  if v_prior.status <> 'revoked' then
    raise exception 'assertion failed: expected the prior token to be revoked once a new one is issued';
  end if;

  begin
    perform app.revoke_shipment_tracking_token(v_shipment_a_id, null, '00000000-0000-0000-0000-000000023502', 'rep');
    raise exception 'assertion failed: expected tracking_revoke_reason_required with no reason';
  exception
    when check_violation then
      if sqlerrm !~ 'tracking_revoke_reason_required' then raise; end if;
  end;
end $$;

\echo '>> app.lookup_public_shipment_tracking: sanitized projection excludes internal-only milestones/location/vendor/cost; wrong/expired/revoked token returns lookup_status=not_found; empty token returns lookup_status=invalid; epod_available reflects the real completed-capture state; rate limiting blocks a client_key after repeated failures -- every outcome is a normal returned row, never a raised exception, so the attempt log always actually commits'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-track-a');
  v_shipment_b_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-track-b');
  v_issue_a record;
  v_issue_b record;
  v_result_a record;
  v_result_b record;
  v_result record;
  v_i integer;
begin
  select * into v_issue_a from app.issue_shipment_tracking_token(v_shipment_a_id, 30, '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_issue_b from app.issue_shipment_tracking_token(v_shipment_b_id, 30, '00000000-0000-0000-0000-000000023502', 'rep');

  select * into v_result_a from app.lookup_public_shipment_tracking(v_issue_a.raw_token, 'client-track-a');
  if v_result_a.lookup_status <> 'ok' or v_result_a.status <> 'in_transit' or v_result_a.epod_available then
    raise exception 'assertion failed: expected shipment_a lookup_status=ok/status=in_transit/epod_available=false, got %/%/%', v_result_a.lookup_status, v_result_a.status, v_result_a.epod_available;
  end if;
  if jsonb_array_length(v_result_a.milestones) <> 1 or (v_result_a.milestones -> 0 ->> 'code') <> 'picked_up' then
    raise exception 'assertion failed: expected exactly 1 customer-visible milestone (picked_up), excluding the internal-only customs_hold, got %', v_result_a.milestones;
  end if;

  select * into v_result_b from app.lookup_public_shipment_tracking(v_issue_b.raw_token, 'client-track-b');
  if v_result_b.lookup_status <> 'ok' or v_result_b.status <> 'epod' or not v_result_b.epod_available then
    raise exception 'assertion failed: expected shipment_b lookup_status=ok/status=epod (delivered -> epod via OPS-177''s own completion wrapper)/epod_available=true, got %/%/%', v_result_b.lookup_status, v_result_b.status, v_result_b.epod_available;
  end if;

  select * into v_result from app.lookup_public_shipment_tracking('not-a-real-token', 'client-track-badtoken');
  if v_result.lookup_status <> 'not_found' or v_result.shipment_number is not null then
    raise exception 'assertion failed: expected lookup_status=not_found and every other field null for an unknown token, got %/%', v_result.lookup_status, v_result.shipment_number;
  end if;

  select * into v_result from app.lookup_public_shipment_tracking(null, 'client-track-empty');
  if v_result.lookup_status <> 'invalid' then
    raise exception 'assertion failed: expected lookup_status=invalid for a null token, got %', v_result.lookup_status;
  end if;

  perform app.revoke_shipment_tracking_token(v_shipment_a_id, 'testing revoked-token lookup', '00000000-0000-0000-0000-000000023502', 'rep');
  select * into v_result from app.lookup_public_shipment_tracking(v_issue_a.raw_token, 'client-track-revoked');
  if v_result.lookup_status <> 'not_found' then
    raise exception 'assertion failed: expected lookup_status=not_found for a revoked token, got %', v_result.lookup_status;
  end if;

  -- Rate limiting: 10 failed lookups for the same client_key exhausts the window; the 11th returns lookup_status=rate_limited.
  for v_i in 1..10 loop
    perform app.lookup_public_shipment_tracking('still-not-a-real-token', 'client-track-ratelimit');
  end loop;
  select * into v_result from app.lookup_public_shipment_tracking('still-not-a-real-token', 'client-track-ratelimit');
  if v_result.lookup_status <> 'rate_limited' then
    raise exception 'assertion failed: expected lookup_status=rate_limited after 10 failed lookups from the same client_key, got %', v_result.lookup_status;
  end if;

  if (select count(*) from app.tracking_lookup_attempts where client_key = 'client-track-ratelimit') <> 11 then
    raise exception 'assertion failed: expected exactly 11 persisted attempt rows for client-track-ratelimit (10 not_found + 1 rate_limited), got %', (select count(*) from app.tracking_lookup_attempts where client_key = 'client-track-ratelimit');
  end if;
end $$;

\echo '>> RLS: record-scope isolation on app.shipment_tracking_tokens; cross-tenant isolation; schema-privilege defense in depth (anon holds EXECUTE only on the one deliberate public function, zero on the other two, and zero direct table access anywhere in this migration)'
do $$
declare
  v_shipment_b_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-track-b');
  v_count integer;
  v_public_grant_count integer;
  v_denied_count integer;
  v_table_denied_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023502", "role": "authenticated"}';
  select count(*) into v_count from app.shipment_tracking_tokens where shipment_order_id = v_shipment_b_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owning rep to see exactly 1 tracking token for shipment_b via RLS, got %', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023504", "role": "authenticated"}';
  select count(*) into v_count from app.shipment_tracking_tokens where shipment_order_id = v_shipment_b_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero tracking tokens for shipment_b via RLS, got %', v_count;
  end if;
  reset role;

  select count(*) into v_public_grant_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and routine_name = 'lookup_public_shipment_tracking' and grantee = 'anon';
  if v_public_grant_count <> 1 then
    raise exception 'assertion failed: expected anon to hold exactly 1 EXECUTE grant, on lookup_public_shipment_tracking specifically, found %', v_public_grant_count;
  end if;

  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app' and routine_name in ('issue_shipment_tracking_token', 'revoke_shipment_tracking_token') and grantee = 'anon';
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants on the 2 management functions, found %', v_denied_count;
  end if;

  select count(*) into v_table_denied_count
  from information_schema.table_privileges
  where table_schema = 'app' and table_name in ('shipment_tracking_tokens', 'tracking_lookup_attempts') and grantee = 'anon';
  if v_table_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero direct table grants anywhere in this migration, found %', v_table_denied_count;
  end if;
end $$;

\echo '>> audit trail: every token issuance/revocation self-captures a canonical app.audit_logs entry'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where action in ('issue_shipment_tracking_token', 'revoke_shipment_tracking_token');
  if v_count < 4 then
    raise exception 'assertion failed: expected at least 4 persisted OPS-180 audit events, found %', v_count;
  end if;
end $$;
