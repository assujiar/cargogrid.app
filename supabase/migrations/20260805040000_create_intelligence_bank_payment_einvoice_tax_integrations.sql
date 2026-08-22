-- Intelligence, Automation and Enterprise Expansion: Bank, Payment Gateway,
-- E-Invoice and Tax Integrations (IAE-017, CG-S14-IAE-017, Prompt 345).
-- Fourth prompt of the merged Batch 4 (`00_EXECUTION_INDEX.md` §5 revision,
-- Prompts 342-348).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Case-by-case adapters, no generic provider abstraction (RPD-038).**
--    Four distinct adapter codes seeded (`bank_feed_api`, `payment_gateway`,
--    `einvoice_provider`, `tax_authority_api`), reusing `app.integration_
--    connections`/`app.integration_connection_credentials` (IAE-336)
--    directly -- the same stronger-isolation pattern IAE-014/015/016
--    already established.
-- 2. **Provider data can never autonomously post journals, payments, tax or
--    legal status (business rule).** Every new function in this migration
--    is `FIN:Edit` at most (ingestion, evidence-recording, staging) -- NOT
--    ONE new function is `FIN:Approve`. The existing, UNMODIFIED
--    `FIN:Approve`-gated posting/activation surface (`app.issue_finance_
--    invoice`, `app.approve_finance_tax_rule`, `app.match_finance_bank_
--    transaction`) remains the only path to a legal/posting effect, and a
--    human always calls it separately, citing this checkpoint's own
--    evidence row id.
-- 3. **The bank-feed gap FIN-211's own migration header explicitly
--    disclosed ("no live bank-API adapter is built here... a caller-
--    supplied, already-parsed batch of lines") is this checkpoint's real
--    deliverable for "bank".** `app.import_finance_bank_statement`
--    (FIN-211) is reused completely UNMODIFIED -- this checkpoint adds a
--    real poller (`lib/finance-integrations/process-finance-bank-feed-
--    sync-job.server.ts`, the fifth real outbound HTTP client in this
--    repository) that fetches a real batch of statement lines and calls
--    that existing RPC with them, inheriting its own idempotency/dedup
--    machinery (`finance_bank_transactions_dedup_unique`,
--    `finance_bank_statement_batches_unique`) entirely for free. Zero new
--    schema for bank-side storage.
-- 4. **A brand-new dedicated job type, `finance_bank_feed_sync`** -- not a
--    reuse of `recurring_billing` (a currently-dormant, zero-producer,
--    zero-consumer job type per direct grep) despite it being technically
--    free, because the name itself already names a DIFFERENT future
--    capability (AR/subscription recurring billing) and reusing it here
--    would be a semantic collision risk, not merely a payload-shape one
--    (contrast IAE-016's own `logistics_partner_sync`, which avoided
--    `integration_sync` because that one has a REAL producer with an
--    unrelated payload shape -- a different, stronger reason, but the same
--    "don't force an unrelated future consumer to disambiguate" instinct
--    applies here too). Widened in the same three-place lockstep IAE-016
--    established: `app.jobs_job_type_check`, `app.generic_job_types()`,
--    `GENERIC_JOB_TYPES` (`server/contracts/background-job/background-
--    job.ts`), and `IMPORT_EXPORT_JOB_TYPES` (`server/contracts/import-
--    export/import-export.ts`).
-- 5. **Payment gateway inbound webhook mirrors IAE-016's own receiver shape
--    exactly** (raw-text body, `x-webhook-timestamp`/`x-webhook-signature`
--    headers, HMAC-SHA256 over `"<timestamp>.<rawPayload>"`, 5-minute
--    replay tolerance, per-`client_key` rate limiting, a single
--    `anon`-granted ingestion RPC using the atomic insert-on-conflict-do-
--    nothing-returning dedup pattern from the first draft, never the
--    two-step exists-check-then-insert form). `app.finance_payment_
--    gateway_events` is evidence-only, best-effort correlated to an
--    existing, UNMODIFIED `app.finance_bank_transactions` row via its own
--    `reference` column -- a human confirms an actual match through the
--    existing `app.match_finance_bank_transaction` (`FIN:Edit`) themselves,
--    citing the event id; this migration never calls that function.
-- 6. **E-invoice submission and tax-authority-rate lookup share ONE
--    evidence table, `app.finance_provider_call_evidence`** (a `call_type`
--    discriminator, not a generic "call any provider" RPC -- each call
--    type keeps its OWN dedicated, separately-validated write function,
--    `app.record_einvoice_submission_attempt` and `app.record_tax_
--    authority_lookup`, preserving RPD-038's case-by-case mandate at the
--    RPC layer even though the storage shape is shared, the same pattern
--    `app.notification_delivery_attempts`/`app.geocode_requests` already
--    established for superficially similar "bounded adapter interface"
--    tables). E-invoice submission requires an ALREADY-`issued` `app.
--    finance_invoices` row (via the existing, unmodified `app.issue_
--    finance_invoice`) and never mutates that invoice's own status --
--    submission tracking is a parallel compliance record. A tax-authority
--    lookup's own evidence row id is meant to be cited in a human's
--    `evidence_note`/`evidence_reference_file_id` when they separately,
--    manually approve a `app.finance_tax_rule_versions` row through the
--    existing, unmodified, evidence-CHECK-enforced `app.approve_finance_
--    tax_rule` (RPD-016) -- never an automatic trigger from this
--    migration's own code.
-- 7. **Trigger authority for the bank-feed sync and payment-gateway/
--    einvoice/tax-lookup evidence actions is `FIN:Edit`, a deliberate
--    DIVERGENCE from IAE-014/015/016's own "any active tenant member"
--    instance-level trigger-authority shape.** Justified by the existing
--    Finance-domain convention itself: `app.import_finance_bank_statement`
--    (the exact adjacent action this checkpoint's poller calls) is already
--    `FIN:Edit`-gated, not merely membership-gated -- consistency with an
--    established sibling capability's own authority line takes precedence
--    over cross-domain uniformity here.
-- 8. **Cost metering (`RPD-028`) reuses `app.compute_provider_billed_amount`
--    directly (IAE-014)** -- confirmed by that function's own comment as
--    covering prompts 343-346, and by RPD-028's own text generalizing
--    "third-party services" beyond its named AI/OCR/messaging/maps
--    examples.
-- 9. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--    execute on all functions in schema app from public` before its final
--    grants.

-- ===========================================================================
-- Adapter code registry helper (design decision 1)
-- ===========================================================================

create function app.finance_provider_adapter_codes()
returns text[]
language sql
immutable
as $$
  select array['bank_feed_api', 'payment_gateway', 'einvoice_provider', 'tax_authority_api']::text[];
$$;

-- ===========================================================================
-- Trigger authority (design decision 7) -- FIN:Edit, not instance-level.
-- ===========================================================================

create function app.check_finance_provider_trigger_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'Edit')).allowed;
$$;

comment on function app.check_finance_provider_trigger_authority is
  'IAE-017: FIN:Edit, a deliberate divergence from IAE-014/015/016''s own "any active tenant member" instance-level shape -- consistent with app.import_finance_bank_statement (FIN-211), the exact adjacent action this checkpoint composes with, which is already FIN:Edit-gated.';

-- ===========================================================================
-- Real client reads (mirrors app.get_logistics_partner_dispatch_info /
-- app.get_logistics_partner_credential / app.get_logistics_partner_
-- connection_for_sync exactly).
-- ===========================================================================

create function app.get_finance_provider_dispatch_info(p_tenant_id uuid, p_actor_auth_user_id uuid, p_adapter_code text)
returns table (connection_id uuid, connection_status text, connection_config jsonb)
language plpgsql
stable
as $$
begin
  if not app.check_finance_provider_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_adapter_code = any (app.finance_provider_adapter_codes())) then
    raise exception 'finance_provider_invalid_adapter_code: % is not a recognized bank/payment/e-invoice/tax adapter', p_adapter_code
      using errcode = 'check_violation';
  end if;

  return query
  select ic.id, ic.status, ic.config
  from app.integration_connections ic
  where ic.tenant_id = p_tenant_id and ic.adapter_code = p_adapter_code
  order by (ic.environment = 'production') desc, ic.created_at desc
  limit 1;
end;
$$;

create function app.get_finance_provider_credential(p_connection_id uuid)
returns text
language sql
stable
as $$
  select credential_value from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

comment on function app.get_finance_provider_credential is
  'IAE-017: service_role-only, mirrors app.get_logistics_partner_credential (IAE-016) exactly.';

create function app.get_finance_provider_connection_for_sync(p_connection_id uuid)
returns table (tenant_id uuid, adapter_code text, connection_status text, connection_config jsonb)
language sql
stable
as $$
  select ic.tenant_id, ic.adapter_code, ic.status, ic.config
  from app.integration_connections ic
  where ic.id = p_connection_id;
$$;

comment on function app.get_finance_provider_connection_for_sync is
  'IAE-017: the real bank-feed poll worker''s own actor-authority-free read (trigger authority was already checked once, at app.trigger_finance_bank_feed_sync time) -- mirrors app.get_logistics_partner_connection_for_sync (IAE-016) exactly.';

-- ===========================================================================
-- Bank-feed poll/sync (design decisions 3, 4, 7) -- reuses app.import_
-- finance_bank_statement (FIN-211) completely unmodified.
-- ===========================================================================

create function app.trigger_finance_bank_feed_sync(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_bank_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_conn app.integration_connections;
  v_account app.finance_bank_accounts;
begin
  if not app.check_finance_provider_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_conn from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id;
  if not found or v_conn.adapter_code <> 'bank_feed_api' then
    raise exception 'finance_provider_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if not app.check_integration_connection_active(p_connection_id) then
    raise exception 'finance_provider_connection_not_active: connection % is not active', p_connection_id using errcode = 'check_violation';
  end if;

  select * into v_account from app.finance_bank_accounts where id = p_bank_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_cash_bank_account_not_found: %', p_bank_account_id using errcode = 'no_data_found';
  end if;

  return app.enqueue_job(
    p_tenant_id, 'finance_bank_feed_sync', jsonb_build_object('connection_id', p_connection_id, 'bank_account_id', p_bank_account_id),
    0, 'finance-bank-feed-sync:' || p_bank_account_id::text || ':' || to_char(date_trunc('minute', now()), 'YYYYMMDDHH24MI'),
    3, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.trigger_finance_bank_feed_sync is
  'IAE-017: the real second caller of app.check_integration_connection_active (IAE-336), after app.trigger_logistics_partner_poll_sync (IAE-016). Idempotency key is bucketed to the current minute, mirroring IAE-016''s own poll-trigger.';

-- ===========================================================================
-- Payment gateway inbound webhook (design decisions 5, 7)
-- ===========================================================================

create table app.finance_payment_gateway_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  connection_id uuid not null references app.integration_connections (id),
  provider_event_id text not null,
  event_type text not null,
  external_reference text,
  bank_transaction_id uuid references app.finance_bank_transactions (id),
  match_status text not null default 'unmatched',
  raw_payload jsonb not null,
  processing_status text not null default 'received',
  review_notes text,
  reviewed_by_auth_user_id uuid references auth.users (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint finance_payment_gateway_events_event_type_check check (event_type in ('payment_confirmed', 'payment_failed', 'refund_issued', 'chargeback')),
  constraint finance_payment_gateway_events_match_status_check check (match_status in ('matched', 'unmatched', 'ambiguous')),
  constraint finance_payment_gateway_events_processing_status_check check (processing_status in ('received', 'reviewed', 'dismissed')),
  constraint finance_payment_gateway_events_payload_check check (app.validate_config_value(raw_payload))
);

comment on table app.finance_payment_gateway_events is
  'IAE-017: append-only inbound payment-gateway event evidence, mirrors app.logistics_partner_events (IAE-016) exactly in shape. Never writes to app.finance_bank_transactions directly -- a matched event is reviewed (app.review_finance_payment_gateway_event) and a human separately confirms the match through the existing app.match_finance_bank_transaction (FIN:Edit), citing this row''s own id.';

create unique index finance_payment_gateway_events_connection_event_unique on app.finance_payment_gateway_events (connection_id, provider_event_id);
create index finance_payment_gateway_events_tenant_idx on app.finance_payment_gateway_events (tenant_id, created_at desc);
create index finance_payment_gateway_events_bank_transaction_idx on app.finance_payment_gateway_events (bank_transaction_id) where bank_transaction_id is not null;

create table app.finance_payment_gateway_ingestion_attempts (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid references app.integration_connections (id),
  client_key text not null,
  result text not null,
  reason text,
  raw_payload jsonb,
  occurred_at timestamptz not null default now(),
  constraint finance_payment_gateway_ingestion_attempts_result_check check (result in ('success', 'invalid', 'rate_limited', 'duplicate'))
);

create index finance_payment_gateway_ingestion_attempts_client_key_idx on app.finance_payment_gateway_ingestion_attempts (client_key, occurred_at desc);
create index finance_payment_gateway_ingestion_attempts_connection_idx on app.finance_payment_gateway_ingestion_attempts (connection_id, occurred_at desc);

create function app.match_finance_payment_gateway_event_to_transaction(p_tenant_id uuid, p_external_reference text)
returns table (bank_transaction_id uuid, match_count integer)
language sql
stable
as $$
  select bt.id, count(*)::integer
  from app.finance_bank_transactions bt
  where bt.tenant_id = p_tenant_id
    and bt.match_status = 'unmatched'
    and p_external_reference is not null
    and bt.reference = p_external_reference
  group by bt.id;
$$;

comment on function app.match_finance_payment_gateway_event_to_transaction is
  'IAE-017: best-effort correlation of an inbound external_reference against this tenant''s own UNMATCHED app.finance_bank_transactions.reference values (FIN-211, plain text, no uniqueness constraint) -- 0 rows means unmatched, 1 row means a clean match, >1 rows means ambiguous.';

create function app.compute_finance_payment_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint)
returns text
language plpgsql
stable
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_secret text;
begin
  select credential_value into v_secret from app.integration_connection_credentials where connection_id = p_connection_id;
  if v_secret is null then
    return null;
  end if;
  return encode(hmac(p_timestamp::text || '.' || p_payload, v_secret, 'sha256'), 'hex');
end;
$$;

create function app.verify_finance_payment_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint, p_signature text)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_expected text;
begin
  if p_timestamp is null or abs(extract(epoch from now()) - p_timestamp) > 300 then
    return false;
  end if;
  if p_signature is null or length(trim(p_signature)) = 0 then
    return false;
  end if;
  v_expected := app.compute_finance_payment_webhook_signature(p_connection_id, p_payload, p_timestamp);
  if v_expected is null then
    return false;
  end if;
  return v_expected = p_signature;
end;
$$;

comment on function app.verify_finance_payment_webhook_signature is
  'IAE-017: fails closed to false for every failure mode -- never raises, mirrors app.verify_logistics_partner_webhook_signature (IAE-016) exactly.';

create function app.ingest_finance_payment_gateway_webhook_event(
  p_connection_id uuid,
  p_client_key text,
  p_raw_payload text,
  p_timestamp bigint,
  p_signature text
)
returns table (ingest_status text, event_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_conn app.integration_connections;
  v_payload jsonb;
  v_provider_event_id text;
  v_event_type text;
  v_external_reference text;
  v_match_count integer := 0;
  v_bank_transaction_id uuid := null;
  v_match_status text := 'unmatched';
  v_row app.finance_payment_gateway_events;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'finance_payment_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.finance_payment_gateway_ingestion_attempts
  where client_key = p_client_key and result = 'invalid' and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'rate_limited', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  select * into v_conn from app.integration_connections where id = p_connection_id;
  if not found or v_conn.status <> 'active' or v_conn.adapter_code <> 'payment_gateway' then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (v_conn.id, p_client_key, 'invalid', 'connection_not_active');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  if not app.verify_finance_payment_webhook_signature(p_connection_id, p_raw_payload, p_timestamp, p_signature) then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'signature_verification_failed');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  begin
    v_payload := p_raw_payload::jsonb;
  exception
    when others then
      insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'malformed_json');
      return query select 'invalid'::text, null::uuid;
      return;
  end;

  v_provider_event_id := v_payload ->> 'event_id';
  v_event_type := v_payload ->> 'event_type';
  v_external_reference := v_payload ->> 'external_reference';

  if v_provider_event_id is null or v_event_type not in ('payment_confirmed', 'payment_failed', 'refund_issued', 'chargeback') then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'schema_validation_failed', v_payload);
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  select count(*) into v_match_count from app.match_finance_payment_gateway_event_to_transaction(v_conn.tenant_id, v_external_reference);
  if v_match_count = 1 then
    select m.bank_transaction_id into v_bank_transaction_id from app.match_finance_payment_gateway_event_to_transaction(v_conn.tenant_id, v_external_reference) m;
    v_match_status := 'matched';
  elsif v_match_count > 1 then
    v_match_status := 'ambiguous';
  end if;

  insert into app.finance_payment_gateway_events (
    tenant_id, connection_id, provider_event_id, event_type, external_reference, bank_transaction_id, match_status, raw_payload
  ) values (
    v_conn.tenant_id, v_conn.id, v_provider_event_id, v_event_type, v_external_reference, v_bank_transaction_id, v_match_status, v_payload
  )
  on conflict (connection_id, provider_event_id) do nothing
  returning * into v_row;

  if v_row.id is null then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'duplicate', 'provider_event_id_already_ingested');
    return query select 'duplicate'::text, null::uuid;
    return;
  end if;

  insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result) values (p_connection_id, p_client_key, 'success');

  return query select 'ok'::text, v_row.id;
end;
$$;

comment on function app.ingest_finance_payment_gateway_webhook_event is
  'IAE-017: the sole anon-granted entrypoint for inbound payment-gateway events. Atomic insert-on-conflict-do-nothing-returning dedup (never a two-step exists-check), mirrors app.ingest_logistics_partner_webhook_event (IAE-016) exactly. Never raises for a caller-facing failure mode.';

create function app.review_finance_payment_gateway_event(
  p_event_id uuid,
  p_decision text,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_payment_gateway_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_event app.finance_payment_gateway_events;
  v_row app.finance_payment_gateway_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_decision not in ('reviewed', 'dismissed') then
    raise exception 'finance_payment_event_invalid_decision: % is not one of reviewed/dismissed', p_decision using errcode = 'check_violation';
  end if;

  select * into v_event from app.finance_payment_gateway_events where id = p_event_id;
  if not found then
    raise exception 'finance_payment_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  if not app.check_finance_provider_trigger_authority(v_event.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.finance_payment_gateway_events
  set processing_status = p_decision, review_notes = p_notes, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_event_id
  returning * into v_row;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_finance_payment_gateway_event',
    'app.finance_payment_gateway_events', v_row.id, 'success', null, to_jsonb(v_event), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.review_finance_payment_gateway_event is
  'IAE-017: FIN:Edit-gated, evidence-only -- never writes to app.finance_bank_transactions. A real match confirmation is a separate, human-driven call to the existing app.match_finance_bank_transaction (FIN:Edit).';

create function app.list_finance_payment_gateway_events_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_bank_transaction_id uuid default null,
  p_limit integer default 50
)
returns setof app.finance_payment_gateway_events
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'View')).allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'finance_payment_event_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select * from app.finance_payment_gateway_events
  where tenant_id = p_tenant_id and (p_bank_transaction_id is null or bank_transaction_id = p_bank_transaction_id)
  order by created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- E-invoice submission and tax-authority lookup shared evidence (design
-- decision 6)
-- ===========================================================================

create table app.finance_provider_call_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  connection_id uuid not null references app.integration_connections (id),
  call_type text not null,
  finance_invoice_id uuid references app.finance_invoices (id),
  tax_code text,
  as_of_date date,
  request_payload jsonb not null,
  status text not null,
  response_payload jsonb,
  provider_unit_cost_amount numeric,
  currency text,
  billed_amount numeric,
  error_message text,
  requested_by_auth_user_id uuid references auth.users (id),
  requested_by text,
  created_at timestamptz not null default now(),
  constraint finance_provider_call_evidence_call_type_check check (call_type in ('einvoice_submission', 'tax_authority_lookup')),
  constraint finance_provider_call_evidence_status_check check (status in ('success', 'failed')),
  constraint finance_provider_call_evidence_request_check check (app.validate_config_value(request_payload)),
  constraint finance_provider_call_evidence_cost_check check (provider_unit_cost_amount is null or provider_unit_cost_amount >= 0),
  constraint finance_provider_call_evidence_einvoice_shape_check check (
    (call_type = 'einvoice_submission' and finance_invoice_id is not null and tax_code is null and as_of_date is null)
    or (call_type = 'tax_authority_lookup' and finance_invoice_id is null and tax_code is not null and as_of_date is not null)
  )
);

comment on table app.finance_provider_call_evidence is
  'IAE-017: a shared, bounded adapter-interface evidence log for two distinct call types (einvoice_submission, tax_authority_lookup), mirrors app.geocode_requests'' own "real, bounded adapter interface" pattern. Each call_type is written by its OWN dedicated RPC, never a generic "record any provider call" entrypoint -- preserves RPD-038''s case-by-case mandate. Never mutates app.finance_invoices or app.finance_tax_rule_versions -- a tax-authority lookup''s own id is meant to be cited as human-supplied evidence when separately, manually approving a tax rule via the existing app.approve_finance_tax_rule.';

create index finance_provider_call_evidence_tenant_idx on app.finance_provider_call_evidence (tenant_id, created_at desc);
create index finance_provider_call_evidence_invoice_idx on app.finance_provider_call_evidence (finance_invoice_id) where finance_invoice_id is not null;

create function app.record_einvoice_submission_attempt(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_finance_invoice_id uuid,
  p_status text,
  p_request_payload jsonb,
  p_response_payload jsonb,
  p_provider_unit_cost_amount numeric,
  p_currency text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_provider_call_evidence
language plpgsql
as $$
declare
  v_invoice app.finance_invoices;
  v_billed_amount numeric;
  v_row app.finance_provider_call_evidence;
begin
  if not app.check_finance_provider_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_invoice from app.finance_invoices where id = p_finance_invoice_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_invoice_not_found: %', p_finance_invoice_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status <> 'issued' then
    raise exception 'finance_einvoice_invoice_not_issued: invoice % is % not issued -- an e-invoice may only be submitted for an already-issued invoice', p_finance_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  if p_status not in ('success', 'failed') then
    raise exception 'finance_provider_call_invalid_status: % is not one of success/failed', p_status using errcode = 'check_violation';
  end if;
  if p_provider_unit_cost_amount is not null and p_provider_unit_cost_amount < 0 then
    raise exception 'finance_provider_call_invalid_cost_amount: provider_unit_cost_amount must not be negative' using errcode = 'check_violation';
  end if;

  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

  insert into app.finance_provider_call_evidence (
    tenant_id, connection_id, call_type, finance_invoice_id, request_payload, status, response_payload,
    provider_unit_cost_amount, currency, billed_amount, error_message, requested_by_auth_user_id, requested_by
  ) values (
    p_tenant_id, p_connection_id, 'einvoice_submission', p_finance_invoice_id, p_request_payload, p_status, p_response_payload,
    p_provider_unit_cost_amount, p_currency, v_billed_amount, p_error_message, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_einvoice_submission_attempt',
    'app.finance_provider_call_evidence', v_row.id, case when p_status = 'success' then 'success' else 'failure' end, p_error_message, null,
    jsonb_build_object('finance_invoice_id', p_finance_invoice_id, 'status', p_status)
  );

  return v_row;
end;
$$;

comment on function app.record_einvoice_submission_attempt is
  'IAE-017: never mutates app.finance_invoices.status -- e-invoice submission is a parallel compliance tracking record, requiring an already-issued invoice. billed_amount computed server-side via app.compute_provider_billed_amount (RPD-028).';

create function app.record_tax_authority_lookup(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_tax_code text,
  p_as_of_date date,
  p_status text,
  p_request_payload jsonb,
  p_response_payload jsonb,
  p_provider_unit_cost_amount numeric,
  p_currency text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_provider_call_evidence
language plpgsql
as $$
declare
  v_billed_amount numeric;
  v_row app.finance_provider_call_evidence;
begin
  if not app.check_finance_provider_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('success', 'failed') then
    raise exception 'finance_provider_call_invalid_status: % is not one of success/failed', p_status using errcode = 'check_violation';
  end if;
  if p_provider_unit_cost_amount is not null and p_provider_unit_cost_amount < 0 then
    raise exception 'finance_provider_call_invalid_cost_amount: provider_unit_cost_amount must not be negative' using errcode = 'check_violation';
  end if;
  if p_tax_code is null or length(trim(p_tax_code)) = 0 then
    raise exception 'finance_tax_lookup_code_required: a tax_code is required' using errcode = 'check_violation';
  end if;
  if p_as_of_date is null then
    raise exception 'finance_tax_lookup_as_of_date_required: an as_of_date is required' using errcode = 'check_violation';
  end if;

  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

  insert into app.finance_provider_call_evidence (
    tenant_id, connection_id, call_type, tax_code, as_of_date, request_payload, status, response_payload,
    provider_unit_cost_amount, currency, billed_amount, error_message, requested_by_auth_user_id, requested_by
  ) values (
    p_tenant_id, p_connection_id, 'tax_authority_lookup', p_tax_code, p_as_of_date, p_request_payload, p_status, p_response_payload,
    p_provider_unit_cost_amount, p_currency, v_billed_amount, p_error_message, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_tax_authority_lookup',
    'app.finance_provider_call_evidence', v_row.id, case when p_status = 'success' then 'success' else 'failure' end, p_error_message, null,
    jsonb_build_object('tax_code', p_tax_code, 'as_of_date', p_as_of_date, 'status', p_status)
  );

  return v_row;
end;
$$;

comment on function app.record_tax_authority_lookup is
  'IAE-017 (RPD-016): never mutates app.finance_tax_rule_versions -- this row''s own id is meant to be cited as human-supplied evidence when a Finance user separately, manually approves a tax rule through the existing, evidence-CHECK-enforced app.approve_finance_tax_rule. Never an automatic activation trigger.';

create function app.list_finance_provider_call_evidence_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_call_type text default null,
  p_limit integer default 50
)
returns setof app.finance_provider_call_evidence
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'View')).allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_call_type is not null and p_call_type not in ('einvoice_submission', 'tax_authority_lookup') then
    raise exception 'finance_provider_call_evidence_invalid_call_type: % is not one of einvoice_submission/tax_authority_lookup', p_call_type
      using errcode = 'check_violation';
  end if;
  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'finance_provider_call_evidence_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select * from app.finance_provider_call_evidence
  where tenant_id = p_tenant_id and (p_call_type is null or call_type = p_call_type)
  order by created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- Real adapter seed (design decision 1)
-- ===========================================================================

insert into app.integration_adapters (code, name, category, registered_by) values
  ('bank_feed_api', 'Bank Statement/Transaction Feed API', 'financial', 'phase-09-foundation'),
  ('payment_gateway', 'Payment Gateway Webhook/Reconciliation', 'financial', 'phase-09-foundation'),
  ('einvoice_provider', 'E-Invoice Submission Provider', 'financial', 'phase-09-foundation'),
  ('tax_authority_api', 'Tax Authority Rate/Rule Lookup API', 'financial', 'phase-09-foundation');

-- ===========================================================================
-- app.jobs job_type widening (design decision 4) -- current full list
-- (verified against 20260805030000's own the most recent `drop constraint
-- jobs_job_type_check`) carried forward verbatim, plus this checkpoint's
-- own one new value.
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'IAE-017: widened to add ''finance_bank_feed_sync'' -- a brand-new dedicated job type, deliberately not a reuse of the dormant ''recurring_billing'' (a semantic collision risk: that name already denotes a different future capability). Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync'
  ]::text[];
$$;

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.finance_payment_gateway_events enable row level security;
alter table app.finance_payment_gateway_ingestion_attempts enable row level security;
alter table app.finance_provider_call_evidence enable row level security;

-- No direct authenticated grant on any of the three tables -- the only read
-- paths are app.list_finance_payment_gateway_events_for_tenant (FIN:View)
-- and app.list_finance_provider_call_evidence_for_tenant (FIN:View),
-- mirroring app.geocode_requests/app.logistics_partner_events's own posture.

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select, insert, update on app.finance_payment_gateway_events to service_role;
grant select, insert on app.finance_payment_gateway_ingestion_attempts to service_role;
grant select, insert on app.finance_provider_call_evidence to service_role;

grant execute on function app.finance_provider_adapter_codes() to authenticated, service_role;
grant execute on function app.check_finance_provider_trigger_authority(uuid, uuid) to service_role;
grant execute on function app.get_finance_provider_dispatch_info(uuid, uuid, text) to service_role;
grant execute on function app.get_finance_provider_credential(uuid) to service_role;
grant execute on function app.get_finance_provider_connection_for_sync(uuid) to service_role;
grant execute on function app.trigger_finance_bank_feed_sync(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.match_finance_payment_gateway_event_to_transaction(uuid, text) to service_role;
grant execute on function app.compute_finance_payment_webhook_signature(uuid, text, bigint) to service_role;
grant execute on function app.verify_finance_payment_webhook_signature(uuid, text, bigint, text) to service_role;
grant execute on function app.ingest_finance_payment_gateway_webhook_event(uuid, text, text, bigint, text) to anon, service_role;
grant execute on function app.review_finance_payment_gateway_event(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_payment_gateway_events_for_tenant(uuid, uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.record_einvoice_submission_attempt(uuid, uuid, uuid, text, jsonb, jsonb, numeric, text, text, uuid, text) to service_role;
grant execute on function app.record_tax_authority_lookup(uuid, uuid, text, date, text, jsonb, jsonb, numeric, text, text, uuid, text) to service_role;
grant execute on function app.list_finance_provider_call_evidence_for_tenant(uuid, uuid, text, integer) to authenticated, service_role;
