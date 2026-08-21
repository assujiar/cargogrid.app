-- Real, executable test evidence for IAE-016 (Carrier, Port, Airport and
-- Customs Integrations, Prompt 344) -- run via `pnpm run db:test` against a
-- real, disposable Postgres database. Scoped to this checkpoint's own
-- additive migration (supabase/migrations/
-- 20260805030000_create_intelligence_carrier_port_airport_customs_integrations.sql).
-- Fresh, distinctive tenant fixture (iaecpac), fixture id range
-- 00000000-0000-0000-0000-000018xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaecpac with a real commercial->job-order pipeline producing one job order and THREE sea-mode shipment splits (two sharing a duplicate BL number for the ambiguous-match test, one with a unique BL number for the clean-match test), a carrier_status_api connection, and a second tenant (iaecpac2) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team_a uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000018000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000018000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000018000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000018000004';
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
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
  v_shipment_dup1 app.shipment_orders;
  v_shipment_dup2 app.shipment_orders;
  v_shipment_unique app.shipment_orders;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaecpac.test'),
    (v_rep1, 'rep@iaecpac.test'),
    (v_viewer1, 'viewer@iaecpac.test'),
    (v_admin2, 'admin@iaecpac2.test');

  perform app.provision_tenant('iaecpac', 'IaeCpac Co', 'idem-iaecpac', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaecpac');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaecpac2', 'IaeCpac Co 2', 'idem-iaecpac2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaecpac2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'IAECPAC-CO', 'IaeCpac Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'IAECPAC-CO');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaecpac.test', 'IaeCpac Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaecpac.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaecpac.test', 'IaeCpac Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaecpac.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaecpac.test', 'IaeCpac Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaecpac.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'CPAC Rep', 'full commercial + ops + inthub grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), v_rep1, v_admin1, 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'CPAC Ops Viewer', 'OPS:View only, no Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaecpac2.test', 'IaeCpac2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaecpac2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Cpac Test Co', 'Jane Cpac', 'jane@cpactest.test', '0811', v_rep1, v_team_a, v_rep1, 'tester');
  select * into v_lead from app.leads where email = 'jane@cpactest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_rep1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Cpac Test Co', 'CTC', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 2', 'city', 'Jakarta', 'country', 'ID'), v_rep1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Cpac Ops', 'Ops Lead', 'jane@cpactest.test', '0811', v_rep1, v_team_a, v_rep1, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_rep1, 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Cpac test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Singapore', 'target_ready_date', '2026-08-01'),
    v_rep1, v_team_a, v_rep1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_rep1, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-CPAC-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Singapore', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, v_admin1, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_rep1, 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_rep1, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_rep1, 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, v_rep1, 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_rep1, 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ops lane', v_calc_id, 1, 15000000, 0, 0, v_rep1, 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, v_rep1, 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_rep1, 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Cpac Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_rep1, 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_rep1, 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_rep1, 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_rep1, 'rep');

  select * into v_shipment_dup1 from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-cpac-dup1', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Singapore',
    null, null, null, null, null, null, null, null, 'split: dup1', v_rep1, 'rep'
  );
  select * into v_shipment_dup2 from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-cpac-dup2', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Singapore',
    null, null, null, null, null, null, null, null, 'split: dup2', v_rep1, 'rep'
  );
  select * into v_shipment_unique from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-cpac-unique', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Singapore',
    null, null, null, null, null, null, null, null, 'split: unique', v_rep1, 'rep'
  );

  perform app.set_shipment_mode_profile(v_shipment_dup1.id, null, null, null, null, null, null, null, null, 'BLDUP0001', 'BOOK-DUP-1', 'MV Contoso Star', 'IDJKT', 'SGSIN', null, null, v_rep1, 'rep');
  perform app.set_shipment_mode_profile(v_shipment_dup2.id, null, null, null, null, null, null, null, null, 'BLDUP0001', 'BOOK-DUP-2', 'MV Contoso Star', 'IDJKT', 'SGSIN', null, null, v_rep1, 'rep');
  perform app.set_shipment_mode_profile(v_shipment_unique.id, null, null, null, null, null, null, null, null, 'BLUNIQUE01', 'BOOK-UNIQUE', 'MV Contoso Star', 'IDJKT', 'SGSIN', 'CONTAINERTEST01', 'FCL', v_rep1, 'rep');

  perform app.create_integration_connection(v_tenant1, 'carrier_status_api', 'Primary Carrier Status Feed', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://carrier.iaecpac-provider.test/webhooks', 'pollUrl', 'https://carrier.iaecpac-provider.test/poll'), 'test-webhook-secret', v_rep1, 'rep');
end $$;

\echo '>> schema-privilege defense in depth: anon holds EXECUTE on exactly one new IAE-016 function (the ingestion entrypoint); every other new function holds zero anon EXECUTE'
do $$
declare
  v_fn text;
  v_anon_denied_functions text[] := array[
    'logistics_partner_adapter_codes', 'check_logistics_partner_trigger_authority', 'match_logistics_partner_event_to_shipment',
    'get_logistics_partner_dispatch_info', 'get_logistics_partner_credential', 'get_logistics_partner_connection_for_sync',
    'compute_logistics_partner_webhook_signature', 'verify_logistics_partner_webhook_signature',
    'trigger_logistics_partner_poll_sync', 'record_logistics_partner_sync_event', 'review_logistics_partner_event',
    'list_logistics_partner_events_for_tenant'
  ];
begin
  if not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'app' and routine_name = 'ingest_logistics_partner_webhook_event' and grantee = 'anon'
  ) then
    raise exception 'assertion failed: anon must hold EXECUTE on app.ingest_logistics_partner_webhook_event -- it is the sole provider-facing entrypoint';
  end if;

  foreach v_fn in array v_anon_denied_functions loop
    if exists (
      select 1 from information_schema.role_routine_grants
      where routine_schema = 'app' and routine_name = v_fn and grantee = 'anon'
    ) then
      raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_fn;
    end if;
  end loop;

  raise notice 'PASS: anon holds EXECUTE on exactly the one provider-facing ingestion entrypoint, nothing else';
end;
$$;

\echo '>> app.match_logistics_partner_event_to_shipment: 0 rows for an unknown reference, 1 row for the unique BL, 2 rows for the deliberately duplicated BL'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecpac');
  v_count integer;
begin
  select count(*) into v_count from app.match_logistics_partner_event_to_shipment(v_tenant1, 'NO-SUCH-REFERENCE');
  if v_count <> 0 then
    raise exception 'assertion failed: expected 0 matches for an unknown reference, got %', v_count;
  end if;

  select count(*) into v_count from app.match_logistics_partner_event_to_shipment(v_tenant1, 'BLUNIQUE01');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 match for the unique BL, got %', v_count;
  end if;

  select count(*) into v_count from app.match_logistics_partner_event_to_shipment(v_tenant1, 'BLDUP0001');
  if v_count <> 2 then
    raise exception 'assertion failed: expected 2 matches for the deliberately duplicated BL (two real shipments share an operator-entered reference), got %', v_count;
  end if;

  raise notice 'PASS: match_logistics_partner_event_to_shipment returns 0/1/2 rows correctly for unmatched/clean/ambiguous references';
end;
$$;

\echo '>> app.ingest_logistics_partner_webhook_event: a real HMAC-SHA256 signature over the exact payload bytes succeeds and correlates cleanly to the unique-BL shipment; a duplicate provider_event_id returns duplicate without a second row; a bad signature/malformed JSON/unknown event_type are all invalid; an ambiguous BL is ok but leaves shipment_order_id null'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecpac');
  v_shipment_unique_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-cpac-unique');
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'carrier_status_api');
  v_ts bigint := extract(epoch from now())::bigint;
  v_payload text;
  v_signature text;
  v_result record;
begin
  v_payload := jsonb_build_object('event_id', 'evt-clean-1', 'event_type', 'customs_clearance', 'external_reference', 'BLUNIQUE01', 'status', 'cleared')::text;
  v_signature := app.compute_logistics_partner_webhook_signature(v_connection_id, v_payload, v_ts);

  select * into v_result from app.ingest_logistics_partner_webhook_event(v_connection_id, 'client-key-1', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' or v_result.event_id is null then
    raise exception 'assertion failed: expected a real ok ingestion with a real event_id, got %', to_jsonb(v_result);
  end if;
  if (select shipment_order_id from app.logistics_partner_events where id = v_result.event_id) <> v_shipment_unique_id then
    raise exception 'assertion failed: expected the ingested event to correlate cleanly to the unique-BL shipment';
  end if;
  if (select match_status from app.logistics_partner_events where id = v_result.event_id) <> 'matched' then
    raise exception 'assertion failed: expected match_status = matched';
  end if;

  select * into v_result from app.ingest_logistics_partner_webhook_event(v_connection_id, 'client-key-1', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'duplicate' then
    raise exception 'assertion failed: expected a resubmitted provider_event_id to be reported as duplicate, got %', to_jsonb(v_result);
  end if;
  if (select count(*) from app.logistics_partner_events where provider_event_id = 'evt-clean-1') <> 1 then
    raise exception 'assertion failed: expected exactly one persisted row for a duplicate provider_event_id, never a second insert';
  end if;

  select * into v_result from app.ingest_logistics_partner_webhook_event(v_connection_id, 'client-key-1', v_payload, v_ts, 'deadbeef' || v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected a corrupted signature to be invalid, got %', to_jsonb(v_result);
  end if;

  select * into v_result from app.ingest_logistics_partner_webhook_event(v_connection_id, 'client-key-1', 'not-json-at-all', v_ts, app.compute_logistics_partner_webhook_signature(v_connection_id, 'not-json-at-all', v_ts));
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected malformed JSON to be invalid, got %', to_jsonb(v_result);
  end if;

  v_payload := jsonb_build_object('event_id', 'evt-bad-type', 'event_type', 'not_a_real_type', 'external_reference', 'BLUNIQUE01')::text;
  select * into v_result from app.ingest_logistics_partner_webhook_event(v_connection_id, 'client-key-1', v_payload, v_ts, app.compute_logistics_partner_webhook_signature(v_connection_id, v_payload, v_ts));
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected an unrecognized event_type to be invalid, got %', to_jsonb(v_result);
  end if;

  v_payload := jsonb_build_object('event_id', 'evt-ambiguous-1', 'event_type', 'status_update', 'external_reference', 'BLDUP0001')::text;
  select * into v_result from app.ingest_logistics_partner_webhook_event(v_connection_id, 'client-key-1', v_payload, v_ts, app.compute_logistics_partner_webhook_signature(v_connection_id, v_payload, v_ts));
  if v_result.ingest_status <> 'ok' then
    raise exception 'assertion failed: expected an ambiguous-BL event to still ingest as ok (recorded as evidence, just unresolved), got %', to_jsonb(v_result);
  end if;
  if (select match_status from app.logistics_partner_events where id = v_result.event_id) <> 'ambiguous' or (select shipment_order_id from app.logistics_partner_events where id = v_result.event_id) is not null then
    raise exception 'assertion failed: expected match_status = ambiguous with a null shipment_order_id (never guess which of two shipments a duplicated reference means)';
  end if;

  raise notice 'PASS: ingest_logistics_partner_webhook_event verifies a real HMAC-SHA256 signature end to end, dedupes atomically, rejects bad signature/malformed JSON/unknown event_type, and leaves an ambiguous match unresolved rather than guessing';
end;
$$;

\echo '>> app.ingest_logistics_partner_webhook_event: 10 invalid attempts within 15 minutes trigger rate_limited on the 11th, scoped per client_key'
do $$
declare
  v_connection_id uuid := (select id from app.integration_connections where adapter_code = 'carrier_status_api');
  v_ts bigint := extract(epoch from now())::bigint;
  v_result record;
  i integer;
begin
  for i in 1..10 loop
    select * into v_result from app.ingest_logistics_partner_webhook_event(v_connection_id, 'rate-limit-client', 'irrelevant', v_ts, 'wrong-signature-' || i);
    if v_result.ingest_status <> 'invalid' then
      raise exception 'assertion failed: expected attempt % to be invalid (bad signature), got %', i, to_jsonb(v_result);
    end if;
  end loop;

  select * into v_result from app.ingest_logistics_partner_webhook_event(v_connection_id, 'rate-limit-client', 'irrelevant', v_ts, 'wrong-signature-11');
  if v_result.ingest_status <> 'rate_limited' then
    raise exception 'assertion failed: expected the 11th consecutive invalid attempt from the same client_key to be rate_limited, got %', to_jsonb(v_result);
  end if;

  select * into v_result from app.ingest_logistics_partner_webhook_event(v_connection_id, 'a-different-client-key', 'irrelevant', v_ts, 'wrong-signature');
  if v_result.ingest_status = 'rate_limited' then
    raise exception 'assertion failed: rate limiting must be scoped per client_key, not global';
  end if;

  raise notice 'PASS: rate limiting triggers at the 10-invalid-attempt threshold, scoped per client_key';
end;
$$;

\echo '>> app.review_logistics_partner_event: OPS:Edit succeeds and never writes to app.shipment_orders; an OPS:View-only actor is denied; an invalid decision value is rejected'
do $$
declare
  v_rep1 uuid := '00000000-0000-0000-0000-000018000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000018000003';
  v_event_id uuid := (select id from app.logistics_partner_events where provider_event_id = 'evt-clean-1');
  v_shipment_record_version_before integer := (select record_version from app.shipment_orders where id = (select shipment_order_id from app.logistics_partner_events where id = v_event_id));
  v_event app.logistics_partner_events;
begin
  select * into v_event from app.review_logistics_partner_event(v_event_id, 'reviewed', 'confirmed against carrier portal', v_rep1, 'rep');
  if v_event.processing_status <> 'reviewed' or v_event.review_notes <> 'confirmed against carrier portal' or v_event.reviewed_by_auth_user_id <> v_rep1 then
    raise exception 'assertion failed: expected the event to record a real review decision, got %', to_jsonb(v_event);
  end if;
  if (select record_version from app.shipment_orders where id = v_event.shipment_order_id) <> v_shipment_record_version_before then
    raise exception 'assertion failed: reviewing an event must never write to app.shipment_orders (evidence-only by design)';
  end if;

  begin
    perform app.review_logistics_partner_event(v_event_id, 'dismissed', null, v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.review_logistics_partner_event(v_event_id, 'approved', null, v_rep1, 'rep');
    raise exception 'assertion failed: expected logistics_partner_event_invalid_decision for an unrecognized decision value';
  exception when check_violation then
    if sqlerrm !~ 'logistics_partner_event_invalid_decision' then raise; end if;
  end;

  raise notice 'PASS: review_logistics_partner_event is OPS:Edit-gated, evidence-only (never touches app.shipment_orders), and rejects an invalid decision';
end;
$$;

\echo '>> app.list_logistics_partner_events_for_tenant: OPS:View sees this tenant''s own real events, optionally filtered by shipment_order_id; a cross-tenant admin is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecpac');
  v_viewer1 uuid := '00000000-0000-0000-0000-000018000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000018000004';
  v_shipment_unique_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-cpac-unique');
  v_count integer;
begin
  select count(*) into v_count from app.list_logistics_partner_events_for_tenant(v_tenant1, v_viewer1);
  if v_count < 2 then
    raise exception 'assertion failed: expected at least 2 real events logged for this tenant (evt-clean-1 matched + evt-ambiguous-1 ambiguous -- every invalid/duplicate/rate_limited attempt above never inserted a row), got %', v_count;
  end if;

  select count(*) into v_count from app.list_logistics_partner_events_for_tenant(v_tenant1, v_viewer1, v_shipment_unique_id);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 event scoped to the unique-BL shipment, got %', v_count;
  end if;

  begin
    perform app.list_logistics_partner_events_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant admin';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_logistics_partner_events_for_tenant is OPS:View-gated, supports a shipment_order_id filter, and denies a cross-tenant admin';
end;
$$;

\echo '>> app.trigger_logistics_partner_poll_sync: enqueues a real app.jobs row (job_type=logistics_partner_sync); the first real caller of app.check_integration_connection_active blocks a disabled connection; a repeated trigger within the same minute is idempotent (same job_id, not a second job); a non-member is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecpac');
  v_rep1 uuid := '00000000-0000-0000-0000-000018000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000018000004';
  v_connection_id uuid := (select id from app.integration_connections where adapter_code = 'carrier_status_api');
  v_job1 app.jobs;
  v_job2 app.jobs;
begin
  select * into v_job1 from app.trigger_logistics_partner_poll_sync(v_tenant1, v_connection_id, v_rep1, 'rep');
  if v_job1.job_type <> 'logistics_partner_sync' or (v_job1.payload->>'connection_id')::uuid <> v_connection_id then
    raise exception 'assertion failed: expected a real logistics_partner_sync job carrying this connection_id, got %', to_jsonb(v_job1);
  end if;

  select * into v_job2 from app.trigger_logistics_partner_poll_sync(v_tenant1, v_connection_id, v_rep1, 'rep');
  if v_job2.job_id <> v_job1.job_id then
    raise exception 'assertion failed: expected a repeated trigger within the same minute to return the SAME job (idempotency key bucketed to the minute), got a second job %', v_job2.job_id;
  end if;

  perform app.set_integration_connection_status(v_connection_id, 'disabled', 'test: disable for poll-sync block assertion', v_rep1, 'rep');
  begin
    perform app.trigger_logistics_partner_poll_sync(v_tenant1, v_connection_id, v_rep1, 'rep');
    raise exception 'assertion failed: expected logistics_partner_connection_not_active for a disabled connection (app.check_integration_connection_active, its first real caller)';
  exception when check_violation then
    if sqlerrm !~ 'logistics_partner_connection_not_active' then raise; end if;
  end;
  perform app.set_integration_connection_status(v_connection_id, 'active', 'test: re-enable', v_rep1, 'rep');

  begin
    perform app.trigger_logistics_partner_poll_sync(v_tenant1, v_connection_id, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant identity with no membership in this tenant';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: trigger_logistics_partner_poll_sync enqueues a real job, is the first real caller of app.check_integration_connection_active (blocking a disabled connection), is minute-bucketed idempotent, and denies a non-member';
end;
$$;

\echo '>> app.record_logistics_partner_sync_event: the real poll worker''s own atomic write -- a repeated provider_event_id within the same connection returns the SAME row, never a second insert or a raised unique_violation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaecpac');
  v_rep1 uuid := '00000000-0000-0000-0000-000018000002';
  v_connection_id uuid := (select id from app.integration_connections where adapter_code = 'carrier_status_api');
  v_event1 app.logistics_partner_events;
  v_event2 app.logistics_partner_events;
begin
  v_event1 := app.record_logistics_partner_sync_event(v_tenant1, v_connection_id, 'evt-sync-1', 'milestone', 'BLUNIQUE01', jsonb_build_object('event_id', 'evt-sync-1', 'note', 'gate-in'), v_rep1, 'rep');
  if v_event1.match_status <> 'matched' then
    raise exception 'assertion failed: expected the poll-sync path to correlate against the same shipment_mode_profiles data the webhook path uses, got %', to_jsonb(v_event1);
  end if;

  v_event2 := app.record_logistics_partner_sync_event(v_tenant1, v_connection_id, 'evt-sync-1', 'milestone', 'BLUNIQUE01', jsonb_build_object('event_id', 'evt-sync-1', 'note', 'gate-in (resent)'), v_rep1, 'rep');
  if v_event2.id <> v_event1.id then
    raise exception 'assertion failed: expected a repeated provider_event_id to return the SAME row (atomic insert-on-conflict-do-nothing-returning), got a second row %', v_event2.id;
  end if;
  if (select count(*) from app.logistics_partner_events where provider_event_id = 'evt-sync-1') <> 1 then
    raise exception 'assertion failed: expected exactly one persisted row for a duplicate provider_event_id within the poll-sync path';
  end if;

  raise notice 'PASS: record_logistics_partner_sync_event is atomically dedup-safe and shares the same correlation logic as the webhook ingestion path';
end;
$$;

\echo '>> carrier-port-airport-customs-integrations.sql: ALL PASSED'
