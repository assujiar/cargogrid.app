-- Intelligence, Automation and Enterprise Expansion: merged Batch 4 Tier C
-- review fix pass (IAE-014..019, Prompts 342-347). Four parallel adversarial
-- lenses (spec-compliance; security/RLS/tenant, live-tested; correctness/
-- concurrency, live-tested; cross-prompt integration) ran against all six
-- independently-built capabilities. This migration fixes every Critical/
-- High finding plus the cheap, low-blast-radius Medium/Low findings that sit
-- in files already being touched. Findings judged out of this bounded pass's
-- own scope (missing UI/features named by the spec-compliance lens, a
-- pre-existing time-of-day-dependent HRIS db-test flake, a pre-existing
-- background-job-framework lost-update, credential-getter tenant/adapter
-- scoping) are disclosed, not fixed here -- see the batch's own Tier C
-- closure record (`docs/build-log/phase-09/00_EXECUTION_INDEX.md` §14).
--
-- Fixes, by capability:
--
-- IAE-014 (Email/WhatsApp/SMS):
--  1. app.record_notification_delivery_attempt: locks the notification row
--     first (`for update`), closing an unlocked read-then-insert race on
--     `attempt_number` (live-reproduced: 2/8 concurrent callers got a raw
--     23505 with a real provider cost silently lost); adds a terminal-state
--     guard (`skipped`/`sent` may never receive a further delivery attempt --
--     live-reproduced: a consent-opted-out `skipped` notification could be
--     flipped to `sent` and billed).
--  2. app.set_notification_contact_address: now requires the target identity
--     hold active membership in `p_tenant_id` (live-reproduced: an actor
--     could plant a cross-tenant contact address for a tenant they are not
--     yet a member of).
--  3. app.notification_contact_addresses' own RLS SELECT policy now requires
--     active tenant membership on read too, and adds a tenant_admin/support-
--     grant read term (live-reproduced: an owner saw their own rows across
--     EVERY tenant regardless of membership; a tenant_admin, who already had
--     WRITE authority over these rows, had zero READ path).
--
-- IAE-016 (Carrier/Port/Airport/Customs) and IAE-017 (Bank/Payment/E-Invoice/
-- Tax) share three fix classes:
--  4. Both inbound webhook rate limiters now scope the bad-attempt counter by
--     `connection_id` (not `client_key` alone) and serialize the check with
--     `pg_advisory_xact_lock` (live-reproduced: an attacker spoofing
--     `X-Forwarded-For` could throttle a DIFFERENT tenant's genuine payment/
--     customs webhook deliveries sharing the same attacker-chosen client_key,
--     and could blow through the 10-attempt/15-minute budget 3.6x under
--     concurrency since the check was an unlocked count-then-act).
--  5. app.trigger_logistics_partner_poll_sync / app.trigger_finance_bank_
--     feed_sync (and IAE-018's app.trigger_external_sync, IAE-019's app.
--     request_ai_governed_action below) are now SECURITY DEFINER + assert
--     the caller's own session identity -- live-reproduced: all four were
--     granted to `authenticated` but were plain SECURITY INVOKER calling a
--     `service_role`-only authority helper, so the app's own RLS-scoped
--     client got `permission denied` on the single most direct, documented
--     entry point of four separate capabilities. Adding the identity assert
--     alongside SECURITY DEFINER (never one without the other) is what makes
--     this safe -- every sibling SECURITY DEFINER function in these same
--     migrations already does both together.
--  6. app.record_logistics_partner_sync_event / app.record_einvoice_
--     submission_attempt / app.record_tax_authority_lookup / (IAE-018's app.
--     record_external_sync_snapshot, IAE-019's app.request_ai_governed_action
--     below) now cross-check that `p_connection_id` actually belongs to
--     `p_tenant_id` before writing evidence against it (live-reproduced: all
--     five accepted a connection id from ANY tenant with no cross-check --
--     not live-exploitable today since every real caller already resolves a
--     tenant-scoped connection id first, but a real structural gap this pass
--     closes at zero blast radius since none of these signatures change).
--  7. IAE-016's app.review_logistics_partner_event / IAE-017's app.review_
--     finance_payment_gateway_event / IAE-018's app.review_external_sync_
--     conflict now refuse to re-decide an already-decided row (live-
--     reproduced: two concurrent reviewers could both be told they
--     succeeded, with the second decision silently overwriting the first --
--     a lost update with no optimistic-concurrency token at all).
--
-- IAE-017 additionally:
--  8. app.trigger_finance_bank_feed_sync's own idempotency key now includes
--     `p_connection_id` (live-reproduced: keying on `bank_account_id` alone
--     let a second `bank_feed_api` connection on the same account silently
--     collide onto the FIRST connection's own job within the same minute --
--     a genuine wrong-provider/wrong-credential poll routing bug, not merely
--     a duplicate-suppression nicety).
--
-- IAE-018 additionally:
--  9. app.list_external_sync_records_for_tenant's `p_entity_type => null`
--     path now resolves HRS:View/FIN:View into two separate per-row filter
--     terms instead of one OR-gated top-level check (live-reproduced: a
--     FIN-only actor with ZERO HRS permission read full employee PII,
--     including the internal `app.employees` values baked into `field_diffs`,
--     by passing `p_entity_type => null`).
--
-- IAE-019 (AI Governance Provider Boundary) -- the most severe findings in
-- this batch, since this checkpoint is the governance FOUNDATION every later
-- AI-assisted capability (Prompt 348+) will build on:
--  10. app.assert_ai_prompt_payload_has_no_secret_shaped_keys is now
--      recursive (objects AND arrays) and no longer raises a raw Postgres
--      22023 on a non-object top-level payload (live-reproduced: a nested
--      `{"employee":{"salary":...,"bank_account_number":...}}` prompt
--      payload passed the guard entirely; a JSON-array output_payload -- an
--      utterly ordinary LLM/OCR response shape -- permanently stranded a
--      request at `pending` with no way to ever record its real outcome).
--  11. A NEW app.redact_ai_output_payload_secret_shaped_values recursively
--      REDACTS (never rejects) a secret-shaped key found in output_payload
--      before it is stored -- output is provider-controlled, untrusted
--      content (live-reproduced: an ordinary, legitimate AI response
--      containing a plausible top-level key like `token`/`bank`/`payroll`
--      made app.record_ai_governed_request_outcome RAISE, permanently
--      losing the real HTTP outcome, model version, confidence and metered
--      cost this checkpoint exists to guarantee). prompt_payload keeps the
--      REJECTING guard -- it is caller-authored, so a secret-shaped key
--      there is a real bug worth surfacing, not silently masking.
--  12. app.record_ai_governed_request_outcome's pending-only transition is
--      now the ATOMIC `UPDATE ... WHERE status = 'pending'` step itself, not
--      a separate SELECT-then-UPDATE -- THE SINGLE MOST SEVERE FINDING OF
--      THIS REVIEW, live-reproduced with 6 genuinely concurrent callers on
--      ONE pending request: all 6 won, zero were rejected, and a human-
--      APPROVED AI output was silently destroyed and replaced by a later
--      straggler's own outcome (output_payload wiped, billed_amount
--      corrupted) while approval_status stayed 'approved', now pointing at
--      nothing.
--  13. app.request_ai_output_approval's "only once" guard now catches the
--      `unique_violation` app.request_approval's own unlocked check-then-
--      insert can still raise under concurrency, translating it into the
--      same clean, named `ai_governed_request_approval_already_requested`
--      error rather than a raw 23505 naming an internal constraint.
--  14. app.ai_governed_requests gains a real CHECK pairing
--      correlation_record_type/correlation_record_id -- a half-set reference
--      (one column null, the other not) is unresolvable and was silently
--      accepted before.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke
-- execute on all functions in schema app from public` before its final
-- grant (only the one brand-new function needs a fresh grant -- `create or
-- replace function` preserves every existing grant on every function whose
-- signature is unchanged, which is every fix below).

-- ===========================================================================
-- IAE-014: record_notification_delivery_attempt (fix 1) -- locks the
-- notification row first, closing the attempt_number race, and adds a
-- terminal-state guard.
-- ===========================================================================

create or replace function app.record_notification_delivery_attempt(
  p_notification_id uuid,
  p_status text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_provider_unit_cost_amount numeric default null,
  p_currency text default null
)
returns app.notification_delivery_attempts
language plpgsql
as $$
declare
  v_notification app.notifications;
  v_next_attempt integer;
  v_attempt app.notification_delivery_attempts;
  v_billed_amount numeric;
begin
  -- Tier C fix: FOR UPDATE serializes concurrent attempt-recording calls for
  -- THIS notification only (a narrow, per-row lock) -- attempt_number
  -- computation below is now safe from the race that previously let two
  -- concurrent callers both compute the same "next" number and hit a raw
  -- unique_violation, silently losing whichever attempt's real provider
  -- cost lost the race.
  select * into v_notification from app.notifications where id = p_notification_id for update;
  if not found then
    raise exception 'notification_not_found: no notification %', p_notification_id
      using errcode = 'no_data_found';
  end if;
  if not app.check_notification_trigger_authority(v_notification.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_notification.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_status not in ('success', 'failed') then
    raise exception 'notification_invalid_attempt_status: status % must be success or failed', p_status
      using errcode = 'check_violation';
  end if;
  -- Tier C fix: a notification that was never queued for delivery (skipped:
  -- consent opted out) or already delivered (sent) must never receive a
  -- further attempt -- live-reproduced: a skipped notification could be
  -- flipped to sent and billed for a delivery that never should have
  -- happened; a terminal sent could be flipped back to failed indefinitely.
  -- 'failed' is deliberately NOT terminal here -- the job queue's own retry
  -- loop legitimately calls this again for a subsequent attempt.
  if v_notification.status in ('skipped', 'sent') then
    raise exception 'notification_delivery_attempt_already_terminal: notification % is % -- no further delivery attempts may be recorded', p_notification_id, v_notification.status
      using errcode = 'check_violation';
  end if;
  if p_provider_unit_cost_amount is not null and p_provider_unit_cost_amount < 0 then
    raise exception 'notification_invalid_cost_amount: provider_unit_cost_amount must not be negative' using errcode = 'check_violation';
  end if;

  select coalesce(max(attempt_number), 0) + 1 into v_next_attempt from app.notification_delivery_attempts where notification_id = p_notification_id;
  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

  insert into app.notification_delivery_attempts (notification_id, attempt_number, status, error_message, provider_unit_cost_amount, currency, billed_amount)
  values (p_notification_id, v_next_attempt, p_status, p_error_message, p_provider_unit_cost_amount, p_currency, v_billed_amount)
  returning * into v_attempt;

  update app.notifications set status = case when p_status = 'success' then 'sent' else 'failed' end where id = p_notification_id;

  perform app.capture_audit_event(
    v_notification.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_notification_delivery_attempt',
    'app.notification_delivery_attempts', v_attempt.id, case when p_status = 'success' then 'success' else 'failure' end, p_error_message, null, to_jsonb(v_attempt)
  );

  return v_attempt;
end;
$$;

comment on function app.record_notification_delivery_attempt is
  'PLT-127, extended by IAE-014, hardened by the merged Batch 4 Tier C review: FOR UPDATE-locks the notification row before computing attempt_number (closes a live-reproduced unlocked read-then-insert race), and refuses a further attempt on a skipped/sent (terminal) notification.';

-- ===========================================================================
-- IAE-014: set_notification_contact_address (fix 2) -- requires the target
-- identity hold active membership in p_tenant_id.
-- ===========================================================================

create or replace function app.set_notification_contact_address(
  p_tenant_id uuid,
  p_auth_user_id uuid,
  p_channel text,
  p_address text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.notification_contact_addresses
language plpgsql
as $$
declare
  v_existing app.notification_contact_addresses;
  v_row app.notification_contact_addresses;
begin
  if p_actor_auth_user_id <> p_auth_user_id and not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % may not set a contact address on behalf of %', p_actor_auth_user_id, p_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix: live-reproduced -- without this, a self-service actor could
  -- plant a contact address row for a tenant they are not (yet, or no
  -- longer) an active member of; the planted row then becomes a live
  -- delivery target the moment that identity gains membership.
  if not app.has_active_tenant_membership(p_tenant_id, p_auth_user_id) then
    raise exception 'notification_contact_recipient_unauthorized: identity % is not an active member of tenant % -- refusing to set a contact address', p_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_channel not in ('whatsapp', 'sms') then
    raise exception 'notification_contact_invalid_channel: % is not one of whatsapp/sms', p_channel
      using errcode = 'check_violation';
  end if;
  if coalesce(length(trim(p_address)), 0) = 0 then
    raise exception 'notification_contact_missing_address: a non-empty address is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.notification_contact_addresses where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and channel = p_channel;

  insert into app.notification_contact_addresses (tenant_id, auth_user_id, channel, address)
  values (p_tenant_id, p_auth_user_id, p_channel, p_address)
  on conflict (tenant_id, auth_user_id, channel)
  do update set address = excluded.address, verified_at = null
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_notification_contact_address',
    'app.notification_contact_addresses', v_row.id, 'success', null,
    case when v_existing.id is null then null else jsonb_build_object('channel', v_existing.channel) end,
    jsonb_build_object('channel', v_row.channel)
  );

  return v_row;
end;
$$;

comment on function app.set_notification_contact_address is
  'IAE-014, hardened by the merged Batch 4 Tier C review: now requires the target identity hold active membership in p_tenant_id (closes a live-reproduced cross-tenant self-service planting path). Self-service by default; a tenant''s own support-grant authority may set it on a user''s behalf. Re-setting the address clears verified_at -- no verification flow exists yet (disclosed).';

-- ===========================================================================
-- IAE-014: notification_contact_addresses RLS (fix 3) -- read authority now
-- matches write authority, and is scoped to active tenant membership.
-- ===========================================================================

drop policy notification_contact_addresses_select_own on app.notification_contact_addresses;

create policy notification_contact_addresses_select_own on app.notification_contact_addresses
  for select to authenticated
  using (
    (auth_user_id = (select auth.uid()) and app.has_active_tenant_membership(tenant_id, (select auth.uid())) and not app.actor_holds_customer_user_layer(tenant_id, (select auth.uid())))
    or app.is_support_grant_authority((select auth.uid()), tenant_id)
    or app.is_supreme_admin()
  );

comment on policy notification_contact_addresses_select_own on app.notification_contact_addresses is
  'IAE-014, hardened by the merged Batch 4 Tier C review: an owner sees their own row only within a tenant they currently, actively belong to (live-reproduced: previously visible across every tenant regardless of membership) AND is not a customer_user-layer principal (ATW-032/ISS-2026-010''s own repository-wide "portal fails closed by default" gate -- a bare tenant-membership predicate must always exclude the customer portal layer); a tenant''s own support-grant authority (already able to WRITE these rows via app.set_notification_contact_address) can now also READ them.';

-- ===========================================================================
-- IAE-016 / IAE-017: shared webhook rate-limiter fix (fix 4) -- scoped by
-- connection_id, serialized with an advisory lock.
-- ===========================================================================

create or replace function app.ingest_logistics_partner_webhook_event(
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
  v_shipment_order_id uuid := null;
  v_match_status text := 'unmatched';
  v_row app.logistics_partner_events;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'logistics_partner_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  -- Tier C fix: serialize the check-then-act for THIS (connection, client)
  -- pair -- live-reproduced without the lock, 40 concurrent bad-signature
  -- deliveries blew through the documented 10-per-15-minute budget (36
  -- admitted). Scoping the count by connection_id (not client_key alone)
  -- closes the live-reproduced cross-tenant blast radius: an attacker
  -- spoofing X-Forwarded-For to match a genuine provider's own client_key
  -- could previously throttle a DIFFERENT tenant's connection entirely.
  perform pg_advisory_xact_lock(hashtext('logistics_partner_rate:' || p_connection_id::text || ':' || p_client_key)::bigint);

  select count(*) into v_recent_bad_count
  from app.logistics_partner_ingestion_attempts
  where connection_id = p_connection_id and client_key = p_client_key and result = 'invalid' and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'rate_limited', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  select * into v_conn from app.integration_connections where id = p_connection_id;
  if not found or v_conn.status <> 'active' or not (v_conn.adapter_code = any (app.logistics_partner_adapter_codes())) then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (v_conn.id, p_client_key, 'invalid', 'connection_not_active');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  if not app.verify_logistics_partner_webhook_signature(p_connection_id, p_raw_payload, p_timestamp, p_signature) then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'signature_verification_failed');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  begin
    v_payload := p_raw_payload::jsonb;
  exception
    when others then
      insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'malformed_json');
      return query select 'invalid'::text, null::uuid;
      return;
  end;

  v_provider_event_id := v_payload ->> 'event_id';
  v_event_type := v_payload ->> 'event_type';
  v_external_reference := v_payload ->> 'external_reference';

  if v_provider_event_id is null or v_event_type not in ('status_update', 'milestone', 'document_available', 'customs_clearance') then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'schema_validation_failed', v_payload);
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  select count(*) into v_match_count from app.match_logistics_partner_event_to_shipment(v_conn.tenant_id, v_external_reference);
  if v_match_count = 1 then
    select m.shipment_order_id into v_shipment_order_id from app.match_logistics_partner_event_to_shipment(v_conn.tenant_id, v_external_reference) m;
    v_match_status := 'matched';
  elsif v_match_count > 1 then
    v_match_status := 'ambiguous';
  end if;

  insert into app.logistics_partner_events (
    tenant_id, connection_id, provider_event_id, event_type, external_reference, shipment_order_id, match_status, raw_payload
  ) values (
    v_conn.tenant_id, v_conn.id, v_provider_event_id, v_event_type, v_external_reference, v_shipment_order_id, v_match_status, v_payload
  )
  on conflict (connection_id, provider_event_id) do nothing
  returning * into v_row;

  if v_row.id is null then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'duplicate', 'provider_event_id_already_ingested');
    return query select 'duplicate'::text, null::uuid;
    return;
  end if;

  insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result) values (p_connection_id, p_client_key, 'success');

  return query select 'ok'::text, v_row.id;
end;
$$;

comment on function app.ingest_logistics_partner_webhook_event is
  'IAE-016, hardened by the merged Batch 4 Tier C review: the rate-limit counter is now scoped by connection_id (not client_key alone) and serialized with an advisory lock, closing a live-reproduced cross-tenant webhook-DoS and a concurrent budget-blow-through. Still the sole anon-granted entrypoint; never raises for a caller-facing failure mode -- every branch returns a row.';

create or replace function app.ingest_finance_payment_gateway_webhook_event(
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

  -- Tier C fix: identical shape to app.ingest_logistics_partner_webhook_
  -- event's own fix -- see that function's own comment for the live
  -- reproduction this closes.
  perform pg_advisory_xact_lock(hashtext('finance_payment_gateway_rate:' || p_connection_id::text || ':' || p_client_key)::bigint);

  select count(*) into v_recent_bad_count
  from app.finance_payment_gateway_ingestion_attempts
  where connection_id = p_connection_id and client_key = p_client_key and result = 'invalid' and occurred_at > now() - interval '15 minutes';
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
  'IAE-017, hardened by the merged Batch 4 Tier C review: the rate-limit counter is now scoped by connection_id (not client_key alone) and serialized with an advisory lock, mirroring app.ingest_logistics_partner_webhook_event''s own fix exactly. Still the sole anon-granted entrypoint; never raises for a caller-facing failure mode.';

-- ===========================================================================
-- IAE-016: trigger_logistics_partner_poll_sync (fix 5) -- SECURITY DEFINER +
-- session-identity assertion, the actual entry point authenticated needs.
-- ===========================================================================

create or replace function app.trigger_logistics_partner_poll_sync(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_conn app.integration_connections;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_logistics_partner_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_conn from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id;
  if not found or not (v_conn.adapter_code = any (app.logistics_partner_adapter_codes())) then
    raise exception 'logistics_partner_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  if not app.check_integration_connection_active(p_connection_id) then
    raise exception 'logistics_partner_connection_not_active: connection % is not active' , p_connection_id using errcode = 'check_violation';
  end if;

  return app.enqueue_job(
    p_tenant_id, 'logistics_partner_sync', jsonb_build_object('connection_id', p_connection_id, 'adapter_code', v_conn.adapter_code),
    0, 'logistics-partner-sync:' || p_connection_id::text || ':' || to_char(date_trunc('minute', now()), 'YYYYMMDDHH24MI'),
    3, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.trigger_logistics_partner_poll_sync is
  'IAE-016, hardened by the merged Batch 4 Tier C review: now SECURITY DEFINER with an app.assert_actor_is_session_identity call -- live-reproduced that this function, though granted to authenticated, was unreachable through the app''s own RLS-scoped client (SECURITY INVOKER calling a service_role-only authority helper). Idempotency key is bucketed to the current minute.';

-- ===========================================================================
-- IAE-016: record_logistics_partner_sync_event (fix 6) -- connection/tenant
-- cross-check.
-- ===========================================================================

create or replace function app.record_logistics_partner_sync_event(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_provider_event_id text,
  p_event_type text,
  p_external_reference text,
  p_raw_payload jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.logistics_partner_events
language plpgsql
as $$
declare
  v_match_count integer := 0;
  v_shipment_order_id uuid := null;
  v_match_status text := 'unmatched';
  v_row app.logistics_partner_events;
begin
  if not app.check_logistics_partner_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix: p_connection_id must actually belong to p_tenant_id --
  -- live-reproduced that any tenant's own connection id was previously
  -- accepted into a different tenant's event row (not exploitable through
  -- the shipped poll worker, which always resolves both from the same
  -- trigger-built payload, but a real structural gap worth closing).
  if not exists (select 1 from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id) then
    raise exception 'logistics_partner_connection_tenant_mismatch: connection % does not belong to tenant %', p_connection_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if p_event_type not in ('status_update', 'milestone', 'document_available', 'customs_clearance') then
    raise exception 'logistics_partner_event_invalid_type: % is not a recognized event_type', p_event_type using errcode = 'check_violation';
  end if;

  if not app.validate_config_value(coalesce(p_raw_payload, '{}'::jsonb)) then
    raise exception 'logistics_partner_event_unsafe_payload: raw_payload failed structural validation' using errcode = 'check_violation';
  end if;

  select count(*) into v_match_count from app.match_logistics_partner_event_to_shipment(p_tenant_id, p_external_reference);
  if v_match_count = 1 then
    select m.shipment_order_id into v_shipment_order_id from app.match_logistics_partner_event_to_shipment(p_tenant_id, p_external_reference) m;
    v_match_status := 'matched';
  elsif v_match_count > 1 then
    v_match_status := 'ambiguous';
  end if;

  insert into app.logistics_partner_events (
    tenant_id, connection_id, provider_event_id, event_type, external_reference, shipment_order_id, match_status, raw_payload
  ) values (
    p_tenant_id, p_connection_id, p_provider_event_id, p_event_type, p_external_reference, v_shipment_order_id, v_match_status, p_raw_payload
  )
  on conflict (connection_id, provider_event_id) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_row from app.logistics_partner_events where connection_id = p_connection_id and provider_event_id = p_provider_event_id;
    return v_row;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_logistics_partner_sync_event',
    'app.logistics_partner_events', v_row.id, 'success', null, null, jsonb_build_object('event_type', v_row.event_type, 'match_status', v_row.match_status)
  );

  return v_row;
end;
$$;

comment on function app.record_logistics_partner_sync_event is
  'IAE-016, hardened by the merged Batch 4 Tier C review: now cross-checks p_connection_id belongs to p_tenant_id before writing. The real poll worker''s own bounded write -- atomic insert-on-conflict-do-nothing-returning.';

-- ===========================================================================
-- IAE-016: review_logistics_partner_event (fix 7) -- terminal-state guard.
-- ===========================================================================

create or replace function app.review_logistics_partner_event(
  p_event_id uuid,
  p_decision text,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.logistics_partner_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_event app.logistics_partner_events;
  v_decision app.rbac_decision;
  v_row app.logistics_partner_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_decision not in ('reviewed', 'dismissed') then
    raise exception 'logistics_partner_event_invalid_decision: % is not one of reviewed/dismissed', p_decision using errcode = 'check_violation';
  end if;

  select * into v_event from app.logistics_partner_events where id = p_event_id;
  if not found then
    raise exception 'logistics_partner_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix: only a not-yet-decided ('received') event may be decided --
  -- live-reproduced that two concurrent reviewers could both be told they
  -- succeeded, with the second decision silently overwriting the first (a
  -- lost update, no optimistic-concurrency token existed at all).
  update app.logistics_partner_events
  set processing_status = p_decision,
      review_notes = p_notes,
      reviewed_by_auth_user_id = p_actor_auth_user_id,
      reviewed_at = now()
  where id = p_event_id and processing_status = 'received'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'logistics_partner_event_already_reviewed: event % has already been decided (%)', p_event_id, v_event.processing_status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_logistics_partner_event',
    'app.logistics_partner_events', v_row.id, 'success', null, to_jsonb(v_event), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.review_logistics_partner_event is
  'IAE-016, hardened by the merged Batch 4 Tier C review: only a not-yet-decided (received) event may be decided -- closes a live-reproduced lost-update race between two concurrent reviewers. OPS:Edit-gated, evidence-only, never a second writer of app.shipment_orders.';

-- ===========================================================================
-- IAE-017: trigger_finance_bank_feed_sync (fixes 5, 8) -- SECURITY DEFINER +
-- session-identity assertion, and the idempotency key now includes
-- connection_id.
-- ===========================================================================

create or replace function app.trigger_finance_bank_feed_sync(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_bank_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_conn app.integration_connections;
  v_account app.finance_bank_accounts;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

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

  -- Tier C fix: the idempotency key now includes p_connection_id -- live-
  -- reproduced that keying on bank_account_id alone let a SECOND bank_
  -- feed_api connection on the same account (e.g. a provider migration, or
  -- production + sandbox) silently collide onto the FIRST connection's own
  -- job within the same minute, routing a poll to the wrong provider
  -- endpoint and credential.
  return app.enqueue_job(
    p_tenant_id, 'finance_bank_feed_sync', jsonb_build_object('connection_id', p_connection_id, 'bank_account_id', p_bank_account_id),
    0, 'finance-bank-feed-sync:' || p_connection_id::text || ':' || p_bank_account_id::text || ':' || to_char(date_trunc('minute', now()), 'YYYYMMDDHH24MI'),
    3, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.trigger_finance_bank_feed_sync is
  'IAE-017, hardened by the merged Batch 4 Tier C review: now SECURITY DEFINER with an app.assert_actor_is_session_identity call (closes the same authenticated-unreachable defect as app.trigger_logistics_partner_poll_sync), and the idempotency key now includes connection_id (closes a live-reproduced wrong-connection poll-routing bug when a tenant has more than one bank_feed_api connection on the same account).';

-- ===========================================================================
-- IAE-017: review_finance_payment_gateway_event (fix 7) -- terminal-state
-- guard.
-- ===========================================================================

create or replace function app.review_finance_payment_gateway_event(
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

  -- Tier C fix: mirrors app.review_logistics_partner_event's own fix
  -- exactly -- only a not-yet-decided ('received') event may be decided.
  update app.finance_payment_gateway_events
  set processing_status = p_decision, review_notes = p_notes, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_event_id and processing_status = 'received'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'finance_payment_event_already_reviewed: event % has already been decided (%)', p_event_id, v_event.processing_status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_finance_payment_gateway_event',
    'app.finance_payment_gateway_events', v_row.id, 'success', null, to_jsonb(v_event), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.review_finance_payment_gateway_event is
  'IAE-017, hardened by the merged Batch 4 Tier C review: only a not-yet-decided (received) event may be decided, mirroring app.review_logistics_partner_event''s own fix exactly. FIN:Edit-gated, evidence-only.';

-- ===========================================================================
-- IAE-017: record_einvoice_submission_attempt / record_tax_authority_lookup
-- (fix 6) -- connection/tenant cross-check.
-- ===========================================================================

create or replace function app.record_einvoice_submission_attempt(
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

  -- Tier C fix: p_connection_id must actually belong to p_tenant_id and be
  -- an einvoice_provider connection -- mirrors app.record_logistics_
  -- partner_sync_event's own fix.
  if not exists (select 1 from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id and adapter_code = 'einvoice_provider') then
    raise exception 'finance_provider_connection_tenant_mismatch: connection % is not a % einvoice_provider connection', p_connection_id, p_tenant_id using errcode = 'no_data_found';
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
  'IAE-017, hardened by the merged Batch 4 Tier C review: now cross-checks p_connection_id belongs to p_tenant_id and is an einvoice_provider connection. Never mutates app.finance_invoices.status -- e-invoice submission is a parallel compliance tracking record, requiring an already-issued invoice.';

create or replace function app.record_tax_authority_lookup(
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

  -- Tier C fix: mirrors app.record_einvoice_submission_attempt's own fix --
  -- live-reproduced that a tenant's payment_gateway connection was
  -- previously accepted for a tax lookup with no adapter cross-check.
  if not exists (select 1 from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id and adapter_code = 'tax_authority_api') then
    raise exception 'finance_provider_connection_tenant_mismatch: connection % is not a % tax_authority_api connection', p_connection_id, p_tenant_id using errcode = 'no_data_found';
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
  'IAE-017 (RPD-016), hardened by the merged Batch 4 Tier C review: now cross-checks p_connection_id belongs to p_tenant_id and is a tax_authority_api connection. Never mutates app.finance_tax_rule_versions.';

-- ===========================================================================
-- IAE-018: trigger_external_sync (fix 5) -- SECURITY DEFINER + session-
-- identity assertion.
-- ===========================================================================

create or replace function app.trigger_external_sync(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_entity_type text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_conn app.integration_connections;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_external_sync_entity_authority('Edit', p_entity_type, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks entity-appropriate Edit authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_conn from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id;
  if not found or not (v_conn.adapter_code = any (app.external_sync_adapter_codes())) then
    raise exception 'external_sync_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if not app.check_integration_connection_active(p_connection_id) then
    raise exception 'external_sync_connection_not_active: connection % is not active', p_connection_id using errcode = 'check_violation';
  end if;

  if (app.get_external_sync_entity_mapping(p_tenant_id, v_conn.adapter_code, p_entity_type)).id is null then
    raise exception 'external_sync_mapping_not_configured: no active ownership-direction mapping for adapter % / entity_type %', v_conn.adapter_code, p_entity_type
      using errcode = 'check_violation';
  end if;

  return app.enqueue_job(
    p_tenant_id, 'external_sync', jsonb_build_object('connection_id', p_connection_id, 'adapter_code', v_conn.adapter_code, 'entity_type', p_entity_type),
    0, 'external-sync:' || p_connection_id::text || ':' || p_entity_type || ':' || to_char(date_trunc('minute', now()), 'YYYYMMDDHH24MI'),
    3, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.trigger_external_sync is
  'IAE-018, hardened by the merged Batch 4 Tier C review: now SECURITY DEFINER with an app.assert_actor_is_session_identity call, closing the same authenticated-unreachable defect as app.trigger_logistics_partner_poll_sync/app.trigger_finance_bank_feed_sync. Refuses to enqueue without an active ownership-direction mapping.';

-- ===========================================================================
-- IAE-018: record_external_sync_snapshot (fix 6) -- connection/tenant
-- cross-check.
-- ===========================================================================

create or replace function app.record_external_sync_snapshot(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_adapter_code text,
  p_entity_type text,
  p_external_entity_id text,
  p_raw_payload jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.external_sync_records
language plpgsql
as $$
declare
  v_mapping app.external_sync_entity_mappings;
  v_link app.external_sync_entity_links;
  v_current jsonb;
  v_field text;
  v_internal_value jsonb;
  v_external_value jsonb;
  v_diffs jsonb := '{}'::jsonb;
  v_conflict_status text := 'no_conflict';
  v_row app.external_sync_records;
begin
  if not app.check_external_sync_entity_authority('Edit', p_entity_type, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks entity-appropriate Edit authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix: p_connection_id must actually belong to p_tenant_id and be
  -- adapter p_adapter_code -- mirrors app.record_logistics_partner_sync_
  -- event's own fix; also live-reproduced that p_adapter_code was never
  -- cross-checked against the connection's own real adapter_code.
  if not exists (select 1 from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id and adapter_code = p_adapter_code) then
    raise exception 'external_sync_connection_tenant_mismatch: connection % is not a % % connection', p_connection_id, p_tenant_id, p_adapter_code using errcode = 'no_data_found';
  end if;

  v_mapping := app.get_external_sync_entity_mapping(p_tenant_id, p_adapter_code, p_entity_type);
  if v_mapping.id is null then
    raise exception 'external_sync_mapping_not_configured: no active ownership-direction mapping for adapter % / entity_type %', p_adapter_code, p_entity_type
      using errcode = 'check_violation';
  end if;

  select * into v_link from app.external_sync_entity_links
  where tenant_id = p_tenant_id and adapter_code = p_adapter_code and entity_type = p_entity_type and external_entity_id = p_external_entity_id;

  if found then
    if p_entity_type = 'employee' then
      select jsonb_build_object('fullName', e.full_name, 'workEmail', e.work_email, 'employmentType', e.employment_type, 'positionTitle', e.position_title, 'hireDate', e.hire_date)
      into v_current from app.employees e where e.master_record_id = v_link.internal_record_id;
    elsif p_entity_type = 'gl_account' then
      select jsonb_build_object('code', a.code, 'name', a.name, 'accountType', a.account_type, 'normalBalance', a.normal_balance, 'status', a.status)
      into v_current from app.finance_accounts a where a.id = v_link.internal_record_id;
    end if;

    if v_current is not null then
      for v_field in select jsonb_object_keys(v_current) loop
        v_internal_value := v_current -> v_field;
        v_external_value := p_raw_payload -> v_field;
        if v_external_value is not null and v_external_value is distinct from v_internal_value then
          v_diffs := v_diffs || jsonb_build_object(v_field, jsonb_build_object('internal', v_internal_value, 'external', v_external_value));
        end if;
      end loop;
    end if;

    if v_diffs <> '{}'::jsonb then
      if v_mapping.ownership_direction in ('cargogrid_source', 'bidirectional') then
        v_conflict_status := 'conflicts_detected';
      end if;
    end if;

    insert into app.external_sync_records (tenant_id, connection_id, entity_type, external_entity_id, internal_record_id, match_status, raw_payload, field_diffs, conflict_status)
    values (p_tenant_id, p_connection_id, p_entity_type, p_external_entity_id, v_link.internal_record_id, 'matched', p_raw_payload, nullif(v_diffs, '{}'::jsonb), v_conflict_status)
    returning * into v_row;
  else
    insert into app.external_sync_records (tenant_id, connection_id, entity_type, external_entity_id, internal_record_id, match_status, raw_payload, field_diffs, conflict_status)
    values (p_tenant_id, p_connection_id, p_entity_type, p_external_entity_id, null, 'unmatched', p_raw_payload, null, 'no_conflict')
    returning * into v_row;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_external_sync_snapshot',
    'app.external_sync_records', v_row.id, 'success', null, null,
    jsonb_build_object('entity_type', v_row.entity_type, 'match_status', v_row.match_status, 'conflict_status', v_row.conflict_status)
  );

  return v_row;
end;
$$;

comment on function app.record_external_sync_snapshot is
  'IAE-018, hardened by the merged Batch 4 Tier C review: now cross-checks p_connection_id belongs to p_tenant_id and is a p_adapter_code connection. NEVER writes to app.employees/app.finance_accounts -- read-only comparison only.';

-- ===========================================================================
-- IAE-018: review_external_sync_conflict (fix 7) -- terminal-state guard.
-- ===========================================================================

create or replace function app.review_external_sync_conflict(
  p_record_id uuid,
  p_decision text,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.external_sync_records
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.external_sync_records;
  v_row app.external_sync_records;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_decision not in ('reviewed', 'dismissed') then
    raise exception 'external_sync_invalid_decision: % is not one of reviewed/dismissed', p_decision using errcode = 'check_violation';
  end if;

  select * into v_record from app.external_sync_records where id = p_record_id;
  if not found then
    raise exception 'external_sync_record_not_found: %', p_record_id using errcode = 'no_data_found';
  end if;

  if not app.check_external_sync_entity_authority('Edit', v_record.entity_type, v_record.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks entity-appropriate Edit authority for tenant %', p_actor_auth_user_id, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Tier C fix: only a record still awaiting review (no_conflict or
  -- conflicts_detected -- a no_conflict record CAN still be explicitly
  -- reviewed/acknowledged) may be decided; reviewed/dismissed is terminal.
  -- Mirrors app.review_logistics_partner_event's own fix.
  update app.external_sync_records
  set conflict_status = p_decision, review_notes = p_notes, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_at = now()
  where id = p_record_id and conflict_status in ('no_conflict', 'conflicts_detected')
  returning * into v_row;

  if v_row.id is null then
    raise exception 'external_sync_record_already_reviewed: record % has already been decided (%)', p_record_id, v_record.conflict_status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_external_sync_conflict',
    'app.external_sync_records', v_row.id, 'success', null, to_jsonb(v_record), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.review_external_sync_conflict is
  'IAE-018, hardened by the merged Batch 4 Tier C review: only a not-yet-decided record (no_conflict or conflicts_detected) may be decided -- closes a live-reproduced lost-update race between two concurrent reviewers, mirroring app.review_logistics_partner_event''s own fix.';

-- ===========================================================================
-- IAE-018: list_external_sync_records_for_tenant (fix 9) -- per-row filter
-- instead of a top-level OR-gate.
-- ===========================================================================

create or replace function app.list_external_sync_records_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_entity_type text default null,
  p_conflict_status text default null,
  p_limit integer default 50
)
returns setof app.external_sync_records
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_has_hrs_view boolean;
  v_has_fin_view boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_has_hrs_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View')).allowed;
  v_has_fin_view := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'View')).allowed;

  if p_entity_type = 'employee' and not v_has_hrs_view then
    raise exception 'insufficient_authority: identity % lacks HRS:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_entity_type = 'gl_account' and not v_has_fin_view then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_entity_type is null and not (v_has_hrs_view or v_has_fin_view) then
    raise exception 'insufficient_authority: identity % lacks HRS:View or FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_conflict_status is not null and p_conflict_status not in ('no_conflict', 'conflicts_detected', 'reviewed', 'dismissed') then
    raise exception 'external_sync_invalid_conflict_status: % is not a recognized conflict_status', p_conflict_status using errcode = 'check_violation';
  end if;
  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'external_sync_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  -- Tier C fix: live-reproduced that a FIN-only actor (zero HRS permission)
  -- calling with p_entity_type => null read full employee rows -- including
  -- internal app.employees values baked into field_diffs -- because the
  -- authority check above was an OR-gate but the row filter below had no
  -- per-row entity_type/module term at all. Each row is now filtered by its
  -- OWN entity_type's own real module authority, never a blanket pass once
  -- ANY one module's View is held.
  return query
  select * from app.external_sync_records
  where tenant_id = p_tenant_id
    and ((entity_type = 'employee' and v_has_hrs_view) or (entity_type = 'gl_account' and v_has_fin_view))
    and (p_entity_type is null or entity_type = p_entity_type)
    and (p_conflict_status is null or conflict_status = p_conflict_status)
  order by created_at desc
  limit p_limit;
end;
$$;

comment on function app.list_external_sync_records_for_tenant is
  'IAE-018, hardened by the merged Batch 4 Tier C review: each row is now filtered by its OWN entity_type''s own real module authority (HRS:View for employee rows, FIN:View for gl_account rows) -- closes a live-reproduced cross-module PII read (a FIN-only actor could read full employee data by passing p_entity_type => null).';

-- ===========================================================================
-- IAE-019: assert_ai_prompt_payload_has_no_secret_shaped_keys (fix 10) --
-- now recursive (objects and arrays), and no longer errors on a non-object
-- top-level payload.
-- ===========================================================================

create or replace function app.assert_ai_prompt_payload_has_no_secret_shaped_keys(p_payload jsonb)
returns void
language plpgsql
immutable
as $$
declare
  v_key text;
  v_value jsonb;
  v_element jsonb;
begin
  if p_payload is null then
    return;
  end if;

  if jsonb_typeof(p_payload) = 'object' then
    for v_key, v_value in select * from jsonb_each(p_payload) loop
      if v_key ~* '(secret|password|token|api_key|authorization|cookie|ssn|npwp|bank|account_number|salary|payroll)' then
        raise exception 'ai_governed_request_secret_shaped_key: prompt_payload key "%" looks credential/PII-shaped -- redact or rename before submitting', v_key
          using errcode = 'check_violation';
      end if;
      perform app.assert_ai_prompt_payload_has_no_secret_shaped_keys(v_value);
    end loop;
  elsif jsonb_typeof(p_payload) = 'array' then
    for v_element in select * from jsonb_array_elements(p_payload) loop
      perform app.assert_ai_prompt_payload_has_no_secret_shaped_keys(v_element);
    end loop;
  end if;
  -- A scalar (string/number/boolean) has no key of its own -- nothing to check.
end;
$$;

comment on function app.assert_ai_prompt_payload_has_no_secret_shaped_keys is
  'IAE-019 (design decision 4), hardened by the merged Batch 4 Tier C review: now RECURSES into nested objects and arrays (live-reproduced: a nested {"employee":{"bank_account_number":...}} previously passed entirely undetected), and no longer raises a raw Postgres error on a non-object top-level payload (live-reproduced: a JSON-array output_payload -- an ordinary LLM/OCR response shape -- permanently stranded a request at pending). Still a structural backstop only -- mirrors app.redact_audit_payload''s own key-name regex, but REJECTS rather than silently redacts (a prompt payload is caller-authored; a secret-shaped key here is a real bug worth surfacing). Never a content-aware scrubber.';

-- ===========================================================================
-- IAE-019: redact_ai_output_payload_secret_shaped_values (fix 11, NEW) --
-- output is provider-controlled, untrusted content; redact rather than
-- reject-and-strand the governance write itself.
-- ===========================================================================

create function app.redact_ai_output_payload_secret_shaped_values(p_payload jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_key text;
  v_value jsonb;
  v_element jsonb;
  v_result jsonb;
begin
  if p_payload is null then
    return null;
  end if;

  if jsonb_typeof(p_payload) = 'object' then
    v_result := '{}'::jsonb;
    for v_key, v_value in select * from jsonb_each(p_payload) loop
      if v_key ~* '(secret|password|token|api_key|authorization|cookie|ssn|npwp|bank|account_number|salary|payroll)' then
        v_result := v_result || jsonb_build_object(v_key, '[REDACTED]'::text);
      else
        v_result := v_result || jsonb_build_object(v_key, app.redact_ai_output_payload_secret_shaped_values(v_value));
      end if;
    end loop;
    return v_result;
  elsif jsonb_typeof(p_payload) = 'array' then
    v_result := '[]'::jsonb;
    for v_element in select * from jsonb_array_elements(p_payload) loop
      v_result := v_result || jsonb_build_array(app.redact_ai_output_payload_secret_shaped_values(v_element));
    end loop;
    return v_result;
  else
    return p_payload;
  end if;
end;
$$;

comment on function app.redact_ai_output_payload_secret_shaped_values is
  'IAE-019, added by the merged Batch 4 Tier C review fix pass: recursively REDACTS (never rejects) a secret-shaped key''s own value in output_payload before app.record_ai_governed_request_outcome stores it. output_payload is provider-controlled, untrusted content -- rejecting it (the posture prompt_payload correctly keeps, since that side is caller-authored) would let an ordinary, legitimate AI response permanently strand a governed request at pending with its real HTTP outcome, model version, confidence and metered cost all lost. Mirrors the same key-name regex app.assert_ai_prompt_payload_has_no_secret_shaped_keys uses.';

-- ===========================================================================
-- IAE-019: request_ai_governed_action (fixes 5, 6) -- SECURITY DEFINER +
-- session-identity assertion, and connection/tenant cross-check.
-- ===========================================================================

create or replace function app.request_ai_governed_action(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_feature_code text,
  p_correlation_record_type text,
  p_correlation_record_id uuid,
  p_prompt_payload jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ai_governed_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.ai_governed_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_ai_governance_authority('Create', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_feature_code is null or length(trim(p_feature_code)) = 0 then
    raise exception 'ai_governed_request_feature_code_required: a feature_code is required' using errcode = 'check_violation';
  end if;

  -- Tier C fix: p_connection_id must actually belong to p_tenant_id.
  if not exists (select 1 from app.integration_connections where id = p_connection_id and tenant_id = p_tenant_id) then
    raise exception 'ai_governed_request_connection_tenant_mismatch: connection % does not belong to tenant %', p_connection_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  perform app.assert_ai_prompt_payload_has_no_secret_shaped_keys(p_prompt_payload);

  insert into app.ai_governed_requests (
    tenant_id, connection_id, feature_code, correlation_record_type, correlation_record_id,
    prompt_payload, status, requested_by_auth_user_id, requested_by
  ) values (
    p_tenant_id, p_connection_id, p_feature_code, p_correlation_record_type, p_correlation_record_id,
    p_prompt_payload, 'pending', p_actor_auth_user_id, p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_ai_governed_action',
    'app.ai_governed_requests', v_row.id, 'success', null, null,
    jsonb_build_object('feature_code', v_row.feature_code, 'correlation_record_type', v_row.correlation_record_type)
  );

  return v_row;
end;
$$;

comment on function app.request_ai_governed_action is
  'IAE-019, hardened by the merged Batch 4 Tier C review: now SECURITY DEFINER with an app.assert_actor_is_session_identity call -- live-reproduced that this function, though granted to authenticated, was unreachable through the app''s own RLS-scoped client. Also now cross-checks p_connection_id belongs to p_tenant_id. The entry point every AI-assisted capability (Prompt 348+) calls to register a real, governed AI request BEFORE dispatching it. Never writes to any table outside this migration''s own schema (design decision 2).';

-- ===========================================================================
-- IAE-019: record_ai_governed_request_outcome (fixes 11, 12) -- THE atomic
-- pending-only transition, and redacts (not rejects) output_payload.
-- ===========================================================================

create or replace function app.record_ai_governed_request_outcome(
  p_request_id uuid,
  p_status text,
  p_output_payload jsonb,
  p_confidence_label text,
  p_model_version text,
  p_provider_unit_cost_amount numeric,
  p_currency text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ai_governed_requests
language plpgsql
as $$
declare
  v_request app.ai_governed_requests;
  v_billed_amount numeric;
  v_row app.ai_governed_requests;
  v_current_status text;
begin
  select * into v_request from app.ai_governed_requests where id = p_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_governance_authority('Create', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('succeeded', 'failed') then
    raise exception 'ai_governed_request_invalid_status: % is not one of succeeded/failed', p_status using errcode = 'check_violation';
  end if;
  if p_provider_unit_cost_amount is not null and p_provider_unit_cost_amount < 0 then
    raise exception 'ai_governed_request_invalid_cost_amount: provider_unit_cost_amount must not be negative' using errcode = 'check_violation';
  end if;

  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

  -- Tier C fix (THE Critical finding of this review): the pending-only
  -- transition must be the ATOMIC step itself -- live-reproduced with 6
  -- genuinely concurrent callers on ONE pending request under the prior
  -- SELECT-then-UPDATE shape: all 6 won, zero were rejected, silently
  -- destroying a human-APPROVED AI output (output_payload wiped,
  -- billed_amount corrupted) while approval_status stayed 'approved',
  -- pointing at nothing. WHERE status = 'pending' here is what actually
  -- prevents a double-transition; a losing concurrent caller now hits
  -- v_row.id is null below and gets the same named error, never a silent
  -- overwrite. output_payload is redacted (never rejected) -- it is
  -- provider-controlled, untrusted content; rejecting it here would strand
  -- the request permanently (see app.redact_ai_output_payload_secret_
  -- shaped_values''s own comment).
  update app.ai_governed_requests
  set status = p_status, output_payload = app.redact_ai_output_payload_secret_shaped_values(p_output_payload), confidence_label = p_confidence_label, model_version = p_model_version,
      provider_unit_cost_amount = p_provider_unit_cost_amount, currency = p_currency, billed_amount = v_billed_amount,
      error_message = p_error_message, completed_at = now()
  where id = p_request_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    select status into v_current_status from app.ai_governed_requests where id = p_request_id;
    raise exception 'ai_governed_request_not_pending: request % is % not pending', p_request_id, v_current_status using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_ai_governed_request_outcome',
    'app.ai_governed_requests', v_row.id, case when p_status = 'succeeded' then 'success' else 'failure' end, p_error_message, null,
    jsonb_build_object('status', v_row.status, 'confidence_label', v_row.confidence_label)
  );

  return v_row;
end;
$$;

comment on function app.record_ai_governed_request_outcome is
  'IAE-019, hardened by the merged Batch 4 Tier C review (the single most severe finding of this review): the pending-only transition is now the atomic UPDATE ... WHERE status = ''pending'' step itself, closing a live-reproduced race where every concurrent caller could win and silently destroy a human-approved AI output. output_payload is now redacted (app.redact_ai_output_payload_secret_shaped_values), never rejected -- it is untrusted provider content, and rejecting it would permanently strand the request. billed_amount computed server-side via app.compute_provider_billed_amount (RPD-028), never trusted from the caller.';

-- ===========================================================================
-- IAE-019: request_ai_output_approval (fix 13) -- catches the unique_
-- violation app.request_approval's own unlocked check-then-insert can still
-- raise under concurrency.
-- ===========================================================================

create or replace function app.request_ai_output_approval(
  p_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.approval_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.ai_governed_requests;
  v_approval_version_id uuid;
  v_approval_request app.approval_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.ai_governed_requests where id = p_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_governance_authority('Create', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status <> 'succeeded' then
    raise exception 'ai_governed_request_not_succeeded: request % is % not succeeded -- only a real, completed output may be sent for approval', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  if v_request.approval_request_id is not null then
    raise exception 'ai_governed_request_approval_already_requested: request % already has an approval request', p_request_id using errcode = 'check_violation';
  end if;

  select cv.id into v_approval_version_id
  from app.config_objects co
  join app.config_versions cv on cv.config_object_id = co.id and cv.status = 'published'
  where co.config_type_code = 'approval:ai_output_acceptance' and co.tenant_id = v_request.tenant_id and co.scope_level = 'tenant';

  if v_approval_version_id is null then
    raise exception 'ai_output_acceptance_approval_not_configured: tenant % has not published an approval:ai_output_acceptance definition yet', v_request.tenant_id
      using errcode = 'check_violation';
  end if;

  -- Tier C fix: app.request_approval's own idempotency guard (PLT-123) is
  -- itself an unlocked check-then-insert -- two concurrent callers here can
  -- both pass the approval_request_id is not null check above, then race
  -- into app.request_approval, where the loser hits a raw unique_violation
  -- on approval_requests_tenant_idempotency_unique. Translate that into the
  -- same clean, named error the sequential (non-racing) path already
  -- raises above, rather than a raw 23505 naming an internal constraint.
  begin
    select * into v_approval_request from app.request_approval(
      v_approval_version_id, v_request.tenant_id, 'ai_governed_output', v_request.id,
      'ai-output-acceptance-' || v_request.id, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      raise exception 'ai_governed_request_approval_already_requested: request % already has an approval request', p_request_id using errcode = 'check_violation';
  end;

  update app.ai_governed_requests set approval_request_id = v_approval_request.id where id = p_request_id;

  return v_approval_request;
end;
$$;

comment on function app.request_ai_output_approval is
  'IAE-019, hardened by the merged Batch 4 Tier C review: now catches the unique_violation app.request_approval''s own unlocked check-then-insert can raise under concurrency, translating it into the same clean, named ai_governed_request_approval_already_requested error. A domain-scoped SECURITY DEFINER proxy to app.request_approval (PLT-123, service_role-only), mirrors app.request_automation_rule_publish_approval (IAE-007) exactly.';

-- ===========================================================================
-- IAE-019: decide_ai_output_approval -- comment-only correction (the code
-- itself was already correct).
-- ===========================================================================

comment on function app.decide_ai_output_approval is
  'IAE-019: a domain-scoped SECURITY DEFINER proxy to app.decide_approval_step (PLT-123, service_role-only), mirrors app.decide_automation_rule_publish_approval (IAE-007) exactly. Folds a step that does not belong to an ai_governed_output request into ai_output_approval_wrong_domain (a check_violation, corrected comment -- the merged Batch 4 Tier C review found this comment previously, inaccurately, described the shape as "not-found-shaped"), never a tenant-id-disclosing insufficient_authority. Layers AI:Approve on top of the generic engine''s own step-level eligibility check.';

-- ===========================================================================
-- IAE-019: ai_governed_requests correlation pairing CHECK (fix 14).
-- ===========================================================================

alter table app.ai_governed_requests add constraint ai_governed_requests_correlation_pairing_check
  check ((correlation_record_type is null) = (correlation_record_id is null));

comment on constraint ai_governed_requests_correlation_pairing_check on app.ai_governed_requests is
  'Merged Batch 4 Tier C review: closes a live-reproduced malformed half-reference -- correlation_record_type/correlation_record_id must both be null or both be set. A type with no id is unresolvable; an id with no type is silently unreachable through app.ai_governed_requests'' own correlation index.';

-- ===========================================================================
-- Grants -- only the one brand-new function needs a fresh grant; every
-- CREATE OR REPLACE above preserves its function's existing grants
-- unchanged since no signature changed.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.redact_ai_output_payload_secret_shaped_values(jsonb) to service_role;
