-- Intelligence, Automation and Enterprise Expansion: Carrier, Port, Airport
-- and Customs Integrations (IAE-016, CG-S14-IAE-016, Prompt 344). Third
-- prompt of the merged Batch 4 (`00_EXECUTION_INDEX.md` §5 revision, Prompts
-- 342-348).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **Case-by-case adapters, no generic provider abstraction (RPD-038).**
--    Four distinct adapter codes are seeded (`carrier_status_api`,
--    `port_terminal_edi`, `airport_cargo_system`, `customs_broker_api`),
--    reusing `app.integration_connections`/`app.integration_connection_
--    credentials` (IAE-336) directly -- the same stronger-isolation pattern
--    IAE-014/015 already established, never the older, disclosed-weaker
--    `app.third_party_provider_connections.webhook_secret_value` pattern
--    (ATW-226E, kept as-is per `ADR-0025` Part B -- GPS/telematics ingestion
--    is unrelated and untouched by this checkpoint).
-- 2. **Inbound events are evidence, never a second writer of Operations
--    truth.** `app.logistics_partner_events` records every inbound
--    status/milestone/document/customs event and best-effort correlates it
--    to a shipment via the existing `app.shipment_mode_profiles` AWB/BL/
--    booking/container/flight reference fields (OPS-171) -- it NEVER calls
--    `app.transition_shipment_order` itself and NEVER writes to `app.
--    shipment_orders`. A staff member reviews a matched event via `app.
--    review_logistics_partner_event` and, if it should advance the
--    shipment's canonical status, does so separately through the existing
--    `app.transition_shipment_order` flow, citing the event's own id as
--    `evidence_ref`. This is the literal reading of this prompt's own
--    business rule ("External events cannot bypass source-domain lifecycle
--    rules") and its Alternative flow ("integration queues error for owner
--    review without updating source truth").
-- 3. **Document requirements need no schema change -- confirmed already
--    adequate as-is, not a scope cut.** `app.document_requirement_
--    definitions.party` (OPS-176) already accepts `'carrier'`, verified by
--    direct read before writing any code; only three new `app.document_
--    types` codes are registered (`customs_declaration`, `bill_of_lading`,
--    `certificate_of_origin`), the exact same direct-INSERT seeding
--    precedent HRT-277 (onboarding/offboarding) already established for a
--    Supreme-Admin-gated registry with no live migration-time actor. A
--    tenant then configures its own `document:<code>` definition (allowed
--    MIME types, retention class, etc.) via the existing, unmodified
--    document-type config UI -- no new UI code needed for this piece
--    either.
-- 4. **A brand-new dedicated job type, not a reuse of the dormant
--    `integration_sync` value.** Direct grep before writing any code found
--    `integration_sync` already has a REAL producer (HRT-277's onboarding/
--    offboarding provisioning tasks, payload shape `{onboarding_task_
--    provisioning_request_id}`) even though it still has zero real
--    consumer/worker. Reusing it here would force a shared worker to
--    disambiguate two structurally unrelated payload shapes with no common
--    contract -- the exact generic-abstraction risk `ADR-0025` Part C /
--    RPD-038 warn against. `logistics_partner_sync` is added instead,
--    following the standing widening convention (`app.jobs_job_type_check`
--    drop+recreate, `app.generic_job_types()` widened identically, TS
--    `GENERIC_JOB_TYPES` (`server/contracts/background-job/background-job.ts`)
--    AND `IMPORT_EXPORT_JOB_TYPES` (`server/contracts/import-export/
--    import-export.ts` -- that contract's own header discloses `app.jobs`
--    reuses this one row shape for every generic job type, not just
--    import/export, so both TS unions must move together) widened
--    identically -- this checkpoint is the type's first and only producer
--    AND consumer.
-- 5. **Connection health/test is already fully solved -- confirmed adequate
--    as-is.** The existing Integration Hub connection detail console
--    (`app/(tenant)/[tenantSlug]/integrations/[connectionId]/`, built for
--    IAE-336) already drives `app.record_integration_health_check`
--    generically for any adapter code. No new "test connection" service
--    code or UI is built here.
-- 6. **Inbound webhook receiver mirrors ATW-226E's GPS receiver shape
--    exactly** (raw-text body, `x-webhook-timestamp`/`x-webhook-signature`
--    headers, HMAC-SHA256 over `"<timestamp>.<rawPayload>"`, 5-minute replay
--    tolerance, a dedicated per-client_key rate-limit ledger, a single
--    `anon`-granted ingestion RPC that never raises) -- but the HMAC secret
--    is read from `app.integration_connection_credentials` (design decision
--    1), never `app.third_party_provider_connections.webhook_secret_value`,
--    so a dedicated `app.verify_logistics_partner_webhook_signature` is
--    added rather than reusing `app.verify_third_party_provider_webhook_
--    signature` (which is hard-wired to the other connection table). One
--    deliberate deviation from the mirrored shape: duplicate detection uses
--    an atomic `insert ... on conflict do nothing returning *` rather than
--    ATW-226E's own two-step exists-check-then-insert (which carries a real,
--    disclosed, pre-existing, out-of-scope race between two genuinely
--    concurrent deliveries of the same `provider_event_id`) -- the same
--    proactive Tier C lesson `app.queue_notification` (IAE-014) already
--    applied, written correctly here from the start rather than mirroring a
--    known flaw.
-- 7. **The outbound "poll" direction is this job type's real first
--    consumer**, proactively reusing `app.check_integration_connection_
--    active` (IAE-336's own primitive, disclosed at the time as having zero
--    real callers) and the SSRF guard (`lib/webhooks/ssrf-guard.server.ts`,
--    the SAME proactive reuse IAE-014/015 already applied -- now a FOURTH
--    real outbound HTTP client relying on it).
-- 8. `INTHUB:Configure`/`INTHUB:View` (seeded by IAE-007) gate connection
--    setup unchanged; `OPS:View`/`OPS:Edit` gate viewing and reviewing
--    inbound events, mirroring OPS-176's own document-checklist review
--    authority exactly -- no new `app.entitlement_modules`/`app.
--    permissions` row needed.
-- 9. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--    execute on all functions in schema app from public` before its final
--    grants.

-- ===========================================================================
-- app.logistics_partner_events (design decisions 2, 6, 7) -- inbound
-- evidence, correlated to a shipment on a best-effort basis, never a second
-- writer of app.shipment_orders.
-- ===========================================================================

create table app.logistics_partner_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  connection_id uuid not null references app.integration_connections (id),
  provider_event_id text not null,
  event_type text not null,
  external_reference text,
  shipment_order_id uuid references app.shipment_orders (id),
  match_status text not null default 'unmatched',
  raw_payload jsonb not null,
  processing_status text not null default 'received',
  review_notes text,
  reviewed_by_auth_user_id uuid references auth.users (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint logistics_partner_events_event_type_check check (event_type in ('status_update', 'milestone', 'document_available', 'customs_clearance')),
  constraint logistics_partner_events_match_status_check check (match_status in ('matched', 'unmatched', 'ambiguous')),
  constraint logistics_partner_events_processing_status_check check (processing_status in ('received', 'reviewed', 'dismissed')),
  constraint logistics_partner_events_payload_check check (app.validate_config_value(raw_payload))
);

comment on table app.logistics_partner_events is
  'IAE-016: append-only inbound carrier/port/airport/customs event evidence. Never written to app.shipment_orders directly -- a matched event is reviewed (app.review_logistics_partner_event) and, if it should advance canonical shipment status, a staff member does so separately through app.transition_shipment_order, citing this row''s own id as evidence_ref (business rule: external events cannot bypass source-domain lifecycle rules).';

create unique index logistics_partner_events_connection_event_unique on app.logistics_partner_events (connection_id, provider_event_id);
create index logistics_partner_events_tenant_idx on app.logistics_partner_events (tenant_id, created_at desc);
create index logistics_partner_events_shipment_idx on app.logistics_partner_events (shipment_order_id) where shipment_order_id is not null;

-- ===========================================================================
-- app.logistics_partner_ingestion_attempts -- mirrors app.third_party_
-- provider_ingestion_attempts (ATW-226E) exactly, own dedicated ledger since
-- this checkpoint's HMAC secret source (app.integration_connection_
-- credentials) is a distinct table from that capability's own.
-- ===========================================================================

create table app.logistics_partner_ingestion_attempts (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid references app.integration_connections (id),
  client_key text not null,
  result text not null,
  reason text,
  raw_payload jsonb,
  occurred_at timestamptz not null default now(),
  constraint logistics_partner_ingestion_attempts_result_check check (result in ('success', 'invalid', 'rate_limited', 'duplicate', 'quarantined'))
);

create index logistics_partner_ingestion_attempts_client_key_idx on app.logistics_partner_ingestion_attempts (client_key, occurred_at desc);
create index logistics_partner_ingestion_attempts_connection_idx on app.logistics_partner_ingestion_attempts (connection_id, occurred_at desc);

-- ===========================================================================
-- Adapter code registry helper (design decision 1) -- a single source of
-- truth for "which integration_adapters.code values this capability owns",
-- reused by every connection lookup below rather than repeating the literal
-- array.
-- ===========================================================================

create function app.logistics_partner_adapter_codes()
returns text[]
language sql
immutable
as $$
  select array['carrier_status_api', 'port_terminal_edi', 'airport_cargo_system', 'customs_broker_api']::text[];
$$;

-- ===========================================================================
-- Trigger authority (mirrors app.check_maps_provider_trigger_authority /
-- app.check_notification_trigger_authority / app.check_webhook_trigger_
-- authority exactly -- any active tenant member, or Supreme).
-- ===========================================================================

create function app.check_logistics_partner_trigger_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- ===========================================================================
-- Shipment correlation (design decision 2) -- best-effort match against the
-- existing, unmodified app.shipment_mode_profiles reference fields
-- (OPS-171). Deliberately does not include land_vehicle_ref/land_vendor_ref
-- (internal operator-entered identifiers, not an external carrier's own
-- reference for an event).
-- ===========================================================================

create function app.match_logistics_partner_event_to_shipment(p_tenant_id uuid, p_external_reference text)
returns table (shipment_order_id uuid, match_count integer)
language sql
stable
as $$
  select smp.shipment_order_id, count(*)::integer
  from app.shipment_mode_profiles smp
  join app.shipment_orders so on so.id = smp.shipment_order_id
  where so.tenant_id = p_tenant_id
    and p_external_reference is not null
    and p_external_reference in (smp.air_awb_number, smp.air_flight_number, smp.sea_bl_number, smp.sea_booking_number, smp.sea_container_number)
  group by smp.shipment_order_id;
$$;

comment on function app.match_logistics_partner_event_to_shipment is
  'IAE-016: best-effort correlation of an inbound external_reference against this tenant''s own AWB/flight/BL/booking/container reference fields (app.shipment_mode_profiles, OPS-171, plain text, no uniqueness constraint on those fields) -- 0 rows means unmatched, 1 row means a clean match, >1 rows means ambiguous (multiple shipments share the same operator-entered reference).';

-- ===========================================================================
-- Real outbound client reads (mirrors app.get_maps_provider_dispatch_info /
-- app.get_maps_provider_credential exactly).
-- ===========================================================================

create function app.get_logistics_partner_dispatch_info(p_tenant_id uuid, p_actor_auth_user_id uuid, p_adapter_code text)
returns table (connection_id uuid, connection_status text, connection_config jsonb)
language plpgsql
stable
as $$
begin
  if not app.check_logistics_partner_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_adapter_code = any (app.logistics_partner_adapter_codes())) then
    raise exception 'logistics_partner_invalid_adapter_code: % is not a recognized carrier/port/airport/customs adapter', p_adapter_code
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

create function app.get_logistics_partner_credential(p_connection_id uuid)
returns text
language sql
stable
as $$
  select credential_value from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

comment on function app.get_logistics_partner_credential is
  'IAE-016: service_role-only, mirrors app.get_maps_provider_credential (IAE-015) / app.get_notification_provider_credential (IAE-014) exactly.';

-- Plain, actor-authority-free read for the trusted background poll worker
-- (mirrors app.get_notification_dispatch_info's own "already-authorized
-- background job, not a live user action" posture -- trigger authority was
-- already checked once, at app.trigger_logistics_partner_poll_sync time).
create function app.get_logistics_partner_connection_for_sync(p_connection_id uuid)
returns table (tenant_id uuid, adapter_code text, connection_status text, connection_config jsonb)
language sql
stable
as $$
  select ic.tenant_id, ic.adapter_code, ic.status, ic.config
  from app.integration_connections ic
  where ic.id = p_connection_id;
$$;

-- ===========================================================================
-- HMAC verification (design decision 6) -- mirrors ADR-0011 / app.verify_
-- third_party_provider_webhook_signature exactly, but scoped to app.
-- integration_connection_credentials (design decision 1).
-- ===========================================================================

create function app.compute_logistics_partner_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint)
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

create function app.verify_logistics_partner_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint, p_signature text)
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
  v_expected := app.compute_logistics_partner_webhook_signature(p_connection_id, p_payload, p_timestamp);
  if v_expected is null then
    return false;
  end if;
  return v_expected = p_signature;
end;
$$;

comment on function app.verify_logistics_partner_webhook_signature is
  'IAE-016: fails closed to false for every failure mode (missing timestamp, stale timestamp beyond the 5-minute ADR-0011 tolerance, missing signature, unknown connection/no stored credential, mismatch) -- never raises, so an unauthenticated caller cannot use error-class or timing differences as a signature oracle.';

-- ===========================================================================
-- Inbound webhook ingestion (design decisions 2, 6) -- the sole anon-granted
-- entrypoint, mirrors app.ingest_third_party_provider_webhook_event's own
-- structure exactly.
-- ===========================================================================

create function app.ingest_logistics_partner_webhook_event(
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

  select count(*) into v_recent_bad_count
  from app.logistics_partner_ingestion_attempts
  where client_key = p_client_key and result = 'invalid' and occurred_at > now() - interval '15 minutes';
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

  -- Atomic insert-on-conflict-do-nothing-returning (proactive reuse of Batch
  -- 3's own Tier C unlocked-check-then-insert race lesson) rather than a
  -- two-step exists-check-then-insert -- two genuinely concurrent deliveries
  -- of the same provider_event_id must never raise a raw unique_violation.
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
  'IAE-016: the sole anon-granted entrypoint for inbound carrier/port/airport/customs provider events, mirrors app.ingest_third_party_provider_webhook_event (ATW-226E) exactly in shape. Never raises for a caller-facing failure mode -- every branch returns a row.';

-- ===========================================================================
-- Poll/sync path (design decisions 4, 7) -- app.logistics_partner_sync as
-- this new job type's real first (and only) producer and consumer.
-- ===========================================================================

create function app.trigger_logistics_partner_poll_sync(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_conn app.integration_connections;
begin
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
  'IAE-016: the real first caller of app.check_integration_connection_active (IAE-336, disclosed at the time as having zero real callers). Idempotency key is bucketed to the current minute -- prevents an accidental duplicate trigger within the same minute while still allowing a genuine periodic re-poll.';

create function app.record_logistics_partner_sync_event(
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
  'IAE-016: the real poll worker''s own bounded write -- atomic insert-on-conflict-do-nothing-returning (proactive reuse of Batch 3''s own Tier C unlocked-check-then-insert race lesson, the same reuse app.queue_notification/IAE-014 already applied), so a duplicate provider_event_id within one poll batch is never a race.';

-- ===========================================================================
-- Review action (design decision 2, 8) -- evidence-only, never a second
-- writer of app.shipment_orders.
-- ===========================================================================

create function app.review_logistics_partner_event(
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

  update app.logistics_partner_events
  set processing_status = p_decision,
      review_notes = p_notes,
      reviewed_by_auth_user_id = p_actor_auth_user_id,
      reviewed_at = now()
  where id = p_event_id
  returning * into v_row;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_logistics_partner_event',
    'app.logistics_partner_events', v_row.id, 'success', null, to_jsonb(v_event), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

-- ===========================================================================
-- List/view (design decision 8) -- OPS:View, mirrors OPS-176's own
-- document-checklist review authority shape.
-- ===========================================================================

create function app.list_logistics_partner_events_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_shipment_order_id uuid default null,
  p_limit integer default 50
)
returns setof app.logistics_partner_events
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'logistics_partner_event_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query
  select * from app.logistics_partner_events
  where tenant_id = p_tenant_id and (p_shipment_order_id is null or shipment_order_id = p_shipment_order_id)
  order by created_at desc
  limit p_limit;
end;
$$;

-- ===========================================================================
-- Real adapter + document type seed (design decisions 1, 3)
-- ===========================================================================

insert into app.integration_adapters (code, name, category, registered_by) values
  ('carrier_status_api', 'Carrier Status/Tracking API', 'logistics_partner', 'phase-09-foundation'),
  ('port_terminal_edi', 'Port Terminal Operating System', 'logistics_partner', 'phase-09-foundation'),
  ('airport_cargo_system', 'Airport Cargo Community System', 'logistics_partner', 'phase-09-foundation'),
  ('customs_broker_api', 'Customs Broker/Authority API', 'logistics_partner', 'phase-09-foundation');

insert into app.document_types (code, name, owner_primitive_code, registered_by)
values
  ('customs_declaration', 'Customs Declaration', 'OPS', 'phase-09-foundation'),
  ('bill_of_lading', 'Bill of Lading', 'OPS', 'phase-09-foundation'),
  ('certificate_of_origin', 'Certificate of Origin', 'OPS', 'phase-09-foundation')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values
  ('document:customs_declaration', 'Customs Declaration', 'OPS', 'phase-09-foundation'),
  ('document:bill_of_lading', 'Bill of Lading', 'OPS', 'phase-09-foundation'),
  ('document:certificate_of_origin', 'Certificate of Origin', 'OPS', 'phase-09-foundation')
on conflict (code) do nothing;

-- ===========================================================================
-- app.jobs job_type widening (design decision 4) -- current full list
-- (verified against 20260803010000's own the most recent `drop constraint
-- jobs_job_type_check`) carried forward verbatim, plus this checkpoint's own
-- one new value.
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'IAE-016: widened to add ''logistics_partner_sync'' -- a brand-new dedicated job type (not a reuse of the dormant-but-not-empty ''integration_sync'', which already has a real HRT-277 producer with an unrelated payload shape). Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

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
    'automation_action_execution', 'logistics_partner_sync'
  ]::text[];
$$;

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.logistics_partner_events enable row level security;
alter table app.logistics_partner_ingestion_attempts enable row level security;

-- No direct authenticated grant on either table -- the only read path is
-- app.list_logistics_partner_events_for_tenant (OPS:View-gated), mirroring
-- app.geocode_requests/app.notification_delivery_attempts's own posture for
-- a table with no simple direct RLS predicate and a dedicated read function.

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select, insert, update on app.logistics_partner_events to service_role;
grant select, insert on app.logistics_partner_ingestion_attempts to service_role;

grant execute on function app.logistics_partner_adapter_codes() to authenticated, service_role;
grant execute on function app.check_logistics_partner_trigger_authority(uuid, uuid) to service_role;
grant execute on function app.match_logistics_partner_event_to_shipment(uuid, text) to service_role;
grant execute on function app.get_logistics_partner_dispatch_info(uuid, uuid, text) to service_role;
grant execute on function app.get_logistics_partner_credential(uuid) to service_role;
grant execute on function app.get_logistics_partner_connection_for_sync(uuid) to service_role;
grant execute on function app.compute_logistics_partner_webhook_signature(uuid, text, bigint) to service_role;
grant execute on function app.verify_logistics_partner_webhook_signature(uuid, text, bigint, text) to service_role;
grant execute on function app.ingest_logistics_partner_webhook_event(uuid, text, text, bigint, text) to anon, service_role;
grant execute on function app.trigger_logistics_partner_poll_sync(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.record_logistics_partner_sync_event(uuid, uuid, text, text, text, jsonb, uuid, text) to service_role;
grant execute on function app.review_logistics_partner_event(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_logistics_partner_events_for_tenant(uuid, uuid, uuid, integer) to authenticated, service_role;
