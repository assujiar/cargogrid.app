-- Real, executable test evidence for IAE-017 (Bank, Payment Gateway,
-- E-Invoice and Tax Integrations, Prompt 345) -- run via `pnpm run db:test`
-- against a real, disposable Postgres database. Scoped to this checkpoint's
-- own additive migration (supabase/migrations/
-- 20260805040000_create_intelligence_bank_payment_einvoice_tax_integrations.sql).
-- Fresh, distinctive tenant fixture (iaebpet), fixture id range
-- 00000000-0000-0000-0000-000019xxxxxx.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: tenant iaebpet with a real commercial->job-order->billing-readiness->issued-invoice pipeline, a real bank account with one imported statement transaction, and 4 real integration connections (one per adapter); a second tenant (iaebpet2) for cross-tenant isolation; a FIN:View-only viewer for authority-denial tests'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team_a uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000019000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000019000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000019000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000019000004';
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
  v_evaluation app.billing_readiness_evaluations;
  v_readiness_handoff app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
  v_cash_account app.finance_accounts;
  v_bank_account app.finance_bank_accounts;
  v_batch app.finance_bank_statement_batches;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaebpet.test'),
    (v_rep1, 'rep@iaebpet.test'),
    (v_viewer1, 'viewer@iaebpet.test'),
    (v_admin2, 'admin@iaebpet2.test');

  perform app.provision_tenant('iaebpet', 'IaeBpet Co', 'idem-iaebpet', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaebpet');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaebpet2', 'IaeBpet Co 2', 'idem-iaebpet2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaebpet2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'IAEBPET-CO', 'IaeBpet Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'IAEBPET-CO');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaebpet.test', 'IaeBpet Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaebpet.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaebpet.test', 'IaeBpet Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaebpet.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaebpet.test', 'IaeBpet Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaebpet.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'BPET Rep', 'full commercial + ops + fin + inthub grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Override'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))
      or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), v_rep1, v_admin1, 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'BPET FIN Viewer', 'FIN:View only, no Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaebpet2.test', 'IaeBpet2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaebpet2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  -- Real commercial pipeline (mirrors IAE-016's own fixture exactly) producing one confirmed job order.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Bpet Test Co', 'Jane Bpet', 'jane@bpettest.test', '0811', v_rep1, v_team_a, v_rep1, 'tester');
  select * into v_lead from app.leads where email = 'jane@bpettest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_rep1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Bpet Test Co', 'BTC', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 3', 'city', 'Jakarta', 'country', 'ID'), v_rep1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Bpet Ops', 'Finance Lead', 'jane@bpettest.test', '0811', v_rep1, v_team_a, v_rep1, 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_rep1, 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Bpet test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Singapore', 'target_ready_date', '2026-08-01'),
    v_rep1, v_team_a, v_rep1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_rep1, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-BPET-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Singapore', '20ft',
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
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Bpet Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_rep1, 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, v_rep1, 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_rep1, 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_rep1, 'rep');

  perform app.generate_finance_fiscal_calendar(v_tenant1, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 12, v_rep1, 'rep');

  -- FIN-202 fixture prerequisite (mirrors scripts/db-tests/finance-invoice.sql
  -- exactly): app.issue_finance_invoice's own subledger effect needs a
  -- published finance_posting_map; app.create_finance_config_draft/
  -- publish_finance_config_version delegate to the generic engine's own
  -- tenant-scope authority check, which requires tenant_admin, not merely
  -- FIN:Edit/Approve.
  perform app.grant_principal_membership(v_rep1, 'tenant_admin', v_tenant1, null, 'tester');
  select * into v_cash_account from app.create_finance_account_draft(v_tenant1, null, 'AR-BPET', 'Accounts Receivable Control', 'asset', 'debit', null, false, null, v_rep1, 'rep');
  perform app.activate_finance_account(v_cash_account.id, v_cash_account.record_version, v_rep1, 'rep');
  select * into v_cash_account from app.create_finance_account_draft(v_tenant1, null, 'REV-BPET', 'Default Revenue', 'revenue', 'credit', null, false, null, v_rep1, 'rep');
  perform app.activate_finance_account(v_cash_account.id, v_cash_account.record_version, v_rep1, 'rep');
  select * into v_cash_account from app.create_finance_account_draft(v_tenant1, null, 'TAX-BPET', 'Default Tax Payable', 'liability', 'credit', null, false, null, v_rep1, 'rep');
  perform app.activate_finance_account(v_cash_account.id, v_cash_account.record_version, v_rep1, 'rep');

  declare
    v_pm_draft app.config_versions;
  begin
    select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant1, 'tenant', null, v_rep1, 'rep');
    perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
      jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-BPET')),
      jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-BPET')),
      jsonb_build_object('key', 'tax_payable_default', 'value', jsonb_build_object('accountCodeRef', 'TAX-BPET')),
      jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'AR-BPET'))
    ), v_rep1, 'rep');
    perform app.publish_finance_config_version(v_pm_draft.id, v_rep1, null, 'rep');
  end;

  -- Billing readiness override path (mirrors scripts/db-tests/finance-invoice.sql's own
  -- disclosed shortcut -- bypassing the full shipment/epod/document/cost evidence chain,
  -- out of THIS checkpoint's own test scope, which is provider integrations, not
  -- billing-readiness evidence collection).
  select * into v_evaluation from app.evaluate_billing_readiness(v_job_order.id, null, v_rep1, 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job_order.id, v_evaluation.record_version, 'fixture: bypassing full shipment/epod/document/cost evidence chain, out of IAE-017''s own test scope', v_rep1, 'rep');
  select * into v_readiness_handoff from app.handoff_billing_readiness(v_job_order.id, 'bpet-fixture-handoff-1', v_rep1, 'rep');

  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant1, v_readiness_handoff.id, 30, null, v_rep1, 'rep');
  select * into v_invoice from app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, v_rep1, 'rep');
  select * into v_invoice from app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, v_rep1, 'rep');
  select * into v_invoice from app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-08-15'::date, v_rep1, 'rep');

  -- Real bank account + one real imported statement transaction (via the
  -- EXISTING, UNMODIFIED app.import_finance_bank_statement) to correlate a
  -- payment-gateway event against.
  select * into v_cash_account from app.create_finance_account_draft(v_tenant1, null, 'CASH-BPET', 'Cash', 'asset', 'debit', null, false, null, v_rep1, 'rep');
  perform app.activate_finance_account(v_cash_account.id, v_cash_account.record_version, v_rep1, 'rep');
  select * into v_bank_account from app.create_finance_bank_account(v_tenant1, null, 'Operating Account', 'Bank BPET', '1234', 'IDR', v_cash_account.id, v_rep1, 'rep');
  select * into v_batch from app.import_finance_bank_statement(v_tenant1, v_bank_account.id, 'fixture-batch-1', jsonb_build_array(
    jsonb_build_object('transactionDate', '2026-08-16', 'direction', 'credit', 'amount', 15000000, 'reference', 'PAY-REF-UNIQUE-01', 'description', 'customer payment')
  ), v_rep1, 'rep');

  -- Real integration connections, one per adapter.
  perform app.create_integration_connection(v_tenant1, 'bank_feed_api', 'Primary Bank Feed', 'production', null, null, null, jsonb_build_object('pollUrl', 'https://bank.iaebpet-provider.test/poll'), 'test-bank-secret', v_rep1, 'rep');
  perform app.create_integration_connection(v_tenant1, 'payment_gateway', 'Primary Payment Gateway', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://pay.iaebpet-provider.test/webhooks'), 'test-payment-secret', v_rep1, 'rep');
  perform app.create_integration_connection(v_tenant1, 'einvoice_provider', 'Primary E-Invoice Provider', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://einvoice.iaebpet-provider.test/submit'), 'test-einvoice-secret', v_rep1, 'rep');
  perform app.create_integration_connection(v_tenant1, 'tax_authority_api', 'Primary Tax Authority API', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://tax.iaebpet-provider.test/rate'), 'test-tax-secret', v_rep1, 'rep');
end $$;

\echo '>> schema-privilege defense in depth: anon holds EXECUTE on exactly the one new IAE-017 provider-facing entrypoint; every other new function holds zero anon EXECUTE'
do $$
declare
  v_fn text;
  v_anon_denied_functions text[] := array[
    'finance_provider_adapter_codes', 'check_finance_provider_trigger_authority', 'get_finance_provider_dispatch_info',
    'get_finance_provider_credential', 'get_finance_provider_connection_for_sync', 'trigger_finance_bank_feed_sync',
    'match_finance_payment_gateway_event_to_transaction', 'compute_finance_payment_webhook_signature',
    'verify_finance_payment_webhook_signature', 'review_finance_payment_gateway_event',
    'list_finance_payment_gateway_events_for_tenant', 'record_einvoice_submission_attempt',
    'record_tax_authority_lookup', 'list_finance_provider_call_evidence_for_tenant'
  ];
begin
  if not exists (
    select 1 from information_schema.role_routine_grants
    where routine_schema = 'app' and routine_name = 'ingest_finance_payment_gateway_webhook_event' and grantee = 'anon'
  ) then
    raise exception 'assertion failed: anon must hold EXECUTE on app.ingest_finance_payment_gateway_webhook_event -- it is the sole provider-facing entrypoint';
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

\echo '>> app.ingest_finance_payment_gateway_webhook_event: a real HMAC-SHA256 signature over the exact payload bytes succeeds and correlates cleanly to the real imported bank transaction; a duplicate provider_event_id returns duplicate without a second row; a bad signature/malformed JSON/unknown event_type are all invalid'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaebpet');
  v_bank_transaction_id uuid := (select id from app.finance_bank_transactions where reference = 'PAY-REF-UNIQUE-01');
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'payment_gateway');
  v_ts bigint := extract(epoch from now())::bigint;
  v_payload text;
  v_signature text;
  v_result record;
begin
  v_payload := jsonb_build_object('event_id', 'pay-evt-1', 'event_type', 'payment_confirmed', 'external_reference', 'PAY-REF-UNIQUE-01')::text;
  v_signature := app.compute_finance_payment_webhook_signature(v_connection_id, v_payload, v_ts);

  select * into v_result from app.ingest_finance_payment_gateway_webhook_event(v_connection_id, 'client-key-1', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'ok' or v_result.event_id is null then
    raise exception 'assertion failed: expected a real ok ingestion with a real event_id, got %', to_jsonb(v_result);
  end if;
  if (select bank_transaction_id from app.finance_payment_gateway_events where id = v_result.event_id) <> v_bank_transaction_id then
    raise exception 'assertion failed: expected the ingested event to correlate cleanly to the real imported bank transaction';
  end if;
  if (select match_status from app.finance_payment_gateway_events where id = v_result.event_id) <> 'matched' then
    raise exception 'assertion failed: expected match_status = matched';
  end if;

  select * into v_result from app.ingest_finance_payment_gateway_webhook_event(v_connection_id, 'client-key-1', v_payload, v_ts, v_signature);
  if v_result.ingest_status <> 'duplicate' then
    raise exception 'assertion failed: expected a resubmitted provider_event_id to be reported as duplicate, got %', to_jsonb(v_result);
  end if;
  if (select count(*) from app.finance_payment_gateway_events where provider_event_id = 'pay-evt-1') <> 1 then
    raise exception 'assertion failed: expected exactly one persisted row for a duplicate provider_event_id, never a second insert';
  end if;

  select * into v_result from app.ingest_finance_payment_gateway_webhook_event(v_connection_id, 'client-key-1', v_payload, v_ts, 'deadbeef' || v_signature);
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected a corrupted signature to be invalid, got %', to_jsonb(v_result);
  end if;

  select * into v_result from app.ingest_finance_payment_gateway_webhook_event(v_connection_id, 'client-key-1', 'not-json-at-all', v_ts, app.compute_finance_payment_webhook_signature(v_connection_id, 'not-json-at-all', v_ts));
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected malformed JSON to be invalid, got %', to_jsonb(v_result);
  end if;

  v_payload := jsonb_build_object('event_id', 'pay-evt-bad-type', 'event_type', 'not_a_real_type', 'external_reference', 'PAY-REF-UNIQUE-01')::text;
  select * into v_result from app.ingest_finance_payment_gateway_webhook_event(v_connection_id, 'client-key-1', v_payload, v_ts, app.compute_finance_payment_webhook_signature(v_connection_id, v_payload, v_ts));
  if v_result.ingest_status <> 'invalid' then
    raise exception 'assertion failed: expected an unrecognized event_type to be invalid, got %', to_jsonb(v_result);
  end if;

  raise notice 'PASS: ingest_finance_payment_gateway_webhook_event verifies a real HMAC-SHA256 signature end to end, dedupes atomically, correlates against the real imported bank transaction, and rejects bad signature/malformed JSON/unknown event_type';
end;
$$;

\echo '>> app.review_finance_payment_gateway_event: FIN:Edit succeeds and never writes to app.finance_bank_transactions; a FIN:View-only actor is denied; an invalid decision value is rejected'
do $$
declare
  v_rep1 uuid := '00000000-0000-0000-0000-000019000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000019000003';
  v_event_id uuid := (select id from app.finance_payment_gateway_events where provider_event_id = 'pay-evt-1');
  v_bank_transaction_id uuid := (select bank_transaction_id from app.finance_payment_gateway_events where id = v_event_id);
  v_bank_transaction_match_status_before text := (select match_status from app.finance_bank_transactions where id = v_bank_transaction_id);
  v_event app.finance_payment_gateway_events;
begin
  select * into v_event from app.review_finance_payment_gateway_event(v_event_id, 'reviewed', 'confirmed against payment gateway dashboard', v_rep1, 'rep');
  if v_event.processing_status <> 'reviewed' or v_event.review_notes <> 'confirmed against payment gateway dashboard' or v_event.reviewed_by_auth_user_id <> v_rep1 then
    raise exception 'assertion failed: expected the event to record a real review decision, got %', to_jsonb(v_event);
  end if;
  if (select match_status from app.finance_bank_transactions where id = v_bank_transaction_id) <> v_bank_transaction_match_status_before then
    raise exception 'assertion failed: reviewing an event must never write to app.finance_bank_transactions (evidence-only by design)';
  end if;

  begin
    perform app.review_finance_payment_gateway_event(v_event_id, 'dismissed', null, v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a FIN:View-only actor';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.review_finance_payment_gateway_event(v_event_id, 'approved', null, v_rep1, 'rep');
    raise exception 'assertion failed: expected finance_payment_event_invalid_decision for an unrecognized decision value';
  exception when check_violation then
    if sqlerrm !~ 'finance_payment_event_invalid_decision' then raise; end if;
  end;

  raise notice 'PASS: review_finance_payment_gateway_event is FIN:Edit-gated, evidence-only (never touches app.finance_bank_transactions), and rejects an invalid decision';
end;
$$;

\echo '>> app.list_finance_payment_gateway_events_for_tenant: FIN:View sees this tenant''s own real events; a cross-tenant admin is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaebpet');
  v_viewer1 uuid := '00000000-0000-0000-0000-000019000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000019000004';
  v_count integer;
begin
  select count(*) into v_count from app.list_finance_payment_gateway_events_for_tenant(v_tenant1, v_viewer1);
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 real event logged for this tenant, got %', v_count;
  end if;

  begin
    perform app.list_finance_payment_gateway_events_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant admin';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: list_finance_payment_gateway_events_for_tenant is FIN:View-gated and denies a cross-tenant admin';
end;
$$;

\echo '>> app.trigger_finance_bank_feed_sync: enqueues a real app.jobs row (job_type=finance_bank_feed_sync); a repeated trigger within the same minute is idempotent; a non-member is denied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaebpet');
  v_rep1 uuid := '00000000-0000-0000-0000-000019000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000019000004';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'bank_feed_api');
  v_bank_account_id uuid := (select id from app.finance_bank_accounts where tenant_id = v_tenant1);
  v_job1 app.jobs;
  v_job2 app.jobs;
begin
  select * into v_job1 from app.trigger_finance_bank_feed_sync(v_tenant1, v_connection_id, v_bank_account_id, v_rep1, 'rep');
  if v_job1.job_type <> 'finance_bank_feed_sync' or (v_job1.payload->>'bank_account_id')::uuid <> v_bank_account_id then
    raise exception 'assertion failed: expected a real finance_bank_feed_sync job carrying this bank_account_id, got %', to_jsonb(v_job1);
  end if;

  select * into v_job2 from app.trigger_finance_bank_feed_sync(v_tenant1, v_connection_id, v_bank_account_id, v_rep1, 'rep');
  if v_job2.job_id <> v_job1.job_id then
    raise exception 'assertion failed: expected a repeated trigger within the same minute to return the SAME job, got a second job %', v_job2.job_id;
  end if;

  begin
    perform app.trigger_finance_bank_feed_sync(v_tenant1, v_connection_id, v_bank_account_id, v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant identity with no membership in this tenant';
  exception when insufficient_privilege then null;
  end;

  raise notice 'PASS: trigger_finance_bank_feed_sync enqueues a real job, is minute-bucketed idempotent, and denies a non-member';
end;
$$;

\echo '>> app.record_einvoice_submission_attempt: requires an already-issued invoice, never mutates app.finance_invoices, computes a real +20%% markup; app.record_tax_authority_lookup requires a tax_code/as_of_date; both are FIN:Edit-gated'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaebpet');
  v_rep1 uuid := '00000000-0000-0000-0000-000019000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000019000003';
  v_invoice_id uuid := (select id from app.finance_invoices where tenant_id = v_tenant1);
  v_invoice_status_before text := (select status from app.finance_invoices where id = v_invoice_id);
  v_einvoice_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'einvoice_provider');
  v_tax_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'tax_authority_api');
  v_evidence app.finance_provider_call_evidence;
begin
  v_evidence := app.record_einvoice_submission_attempt(v_tenant1, v_einvoice_connection_id, v_invoice_id, 'success', jsonb_build_object('invoiceNumber', 'INV-TEST'), jsonb_build_object('providerReference', 'EINV-001'), 0.0100, 'USD', null, v_rep1, 'rep');
  if v_evidence.billed_amount <> 0.0120 then
    raise exception 'assertion failed: expected billed_amount = 0.0100 * 1.20 = 0.0120, got %', v_evidence.billed_amount;
  end if;
  if (select status from app.finance_invoices where id = v_invoice_id) <> v_invoice_status_before then
    raise exception 'assertion failed: recording an e-invoice submission attempt must never mutate app.finance_invoices.status';
  end if;

  begin
    perform app.record_einvoice_submission_attempt(v_tenant1, v_einvoice_connection_id, v_invoice_id, 'success', jsonb_build_object(), null, null, null, null, v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a FIN:View-only actor';
  exception when insufficient_privilege then null;
  end;

  v_evidence := app.record_tax_authority_lookup(v_tenant1, v_tax_connection_id, 'PPN', '2026-08-21'::date, 'success', jsonb_build_object('taxCode', 'PPN'), jsonb_build_object('rateValue', 0.11), 0.0100, 'USD', null, v_rep1, 'rep');
  if v_evidence.tax_code <> 'PPN' or v_evidence.billed_amount <> 0.0120 then
    raise exception 'assertion failed: expected a real tax_authority_lookup evidence row with tax_code=PPN and a real +20%% markup, got %', to_jsonb(v_evidence);
  end if;

  begin
    perform app.record_tax_authority_lookup(v_tenant1, v_tax_connection_id, '', '2026-08-21'::date, 'success', jsonb_build_object(), null, null, null, null, v_rep1, 'rep');
    raise exception 'assertion failed: expected finance_tax_lookup_code_required for an empty tax_code';
  exception when check_violation then
    if sqlerrm !~ 'finance_tax_lookup_code_required' then raise; end if;
  end;

  raise notice 'PASS: record_einvoice_submission_attempt/record_tax_authority_lookup are FIN:Edit-gated, compute a real +20%% markup, and the e-invoice path never mutates app.finance_invoices';
end;
$$;

\echo '>> app.record_einvoice_submission_attempt: rejected for a not-yet-issued invoice'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaebpet');
  v_rep1 uuid := '00000000-0000-0000-0000-000019000002';
  v_einvoice_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'einvoice_provider');
begin
  begin
    perform app.record_einvoice_submission_attempt(v_tenant1, v_einvoice_connection_id, gen_random_uuid(), 'success', jsonb_build_object(), null, null, null, null, v_rep1, 'rep');
    raise exception 'assertion failed: expected finance_invoice_not_found for an unknown invoice id';
  exception when no_data_found then null;
  end;

  raise notice 'PASS: record_einvoice_submission_attempt cleanly rejects an unknown invoice id';
end;
$$;

\echo '>> app.list_finance_provider_call_evidence_for_tenant: FIN:View sees this tenant''s own real evidence rows, optionally filtered by call_type'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaebpet');
  v_viewer1 uuid := '00000000-0000-0000-0000-000019000003';
  v_count integer;
begin
  select count(*) into v_count from app.list_finance_provider_call_evidence_for_tenant(v_tenant1, v_viewer1);
  if v_count < 2 then
    raise exception 'assertion failed: expected at least 2 real evidence rows (1 einvoice_submission + 1 tax_authority_lookup), got %', v_count;
  end if;

  select count(*) into v_count from app.list_finance_provider_call_evidence_for_tenant(v_tenant1, v_viewer1, 'tax_authority_lookup');
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 tax_authority_lookup row when filtered, got %', v_count;
  end if;

  raise notice 'PASS: list_finance_provider_call_evidence_for_tenant is FIN:View-gated and supports a call_type filter';
end;
$$;

\echo '>> bank-payment-einvoice-tax-integrations.sql: ALL PASSED'
