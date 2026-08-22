-- Intelligence, Automation and Enterprise Expansion: Enterprise Maps, GPS and
-- Telematics Integrations (IAE-015, CG-S14-IAE-015, Prompt 343). Second
-- prompt of the merged Batch 4 (`00_EXECUTION_INDEX.md` §5 revision, Prompts
-- 342-348).
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **"Additional approved GPS/telematics provider adapters" is CONFIRMED
--    ALREADY FULLY SUPPORTED by the existing Phase 5 architecture -- zero new
--    schema needed for it, a genuine finding, not a scope cut.** Verified by
--    direct read of `app.third_party_provider_connections`
--    (`20260729380000_create_advanced_tms_third_party_provider_adapter.sql`,
--    ATW-226E) before writing any code: `provider_code` carries NO CHECK
--    enum restricting it to a fixed list -- any tenant can already register
--    an arbitrary number of distinct provider codes via the already-generic
--    `app.register_third_party_provider_connection(tenant_id, provider_code,
--    integration_mode, ...)`. `app.tenant_tracking_source_policies.default_
--    source_priority`'s own CHECK (`<@ array['driver_mobile',
--    'direct_device', 'third_party_platform']`) already treats
--    `third_party_platform` as ONE source CLASS covering every registered
--    provider_code, not a per-provider entry -- no widening needed there
--    either. `ADR-0025` Part B's own ruling ("keeps its own existing inbound
--    GPS receiver as-is... no duplicate gateway") is honored by changing
--    NOTHING about ingestion.
-- 2. **Enterprise maps/geocoding/routing is the one genuinely new capability
--    this checkpoint delivers** -- confirmed absent repository-wide by direct
--    grep before writing any code (no `geocode`/`route_calculation` table or
--    function exists anywhere). Unlike GPS/telematics ingestion (inbound,
--    webhook-shaped, already solved), geocoding is a live, SYNCHRONOUS
--    outbound call (address in, coordinates out) -- structurally different
--    from every queued/retried delivery this session has built so far, so it
--    is NOT modeled as an `app.jobs` consumer. `app.geocode_requests` is the
--    real, bounded adapter interface (mirrors `app.notification_delivery_
--    attempts`/`app.webhook_delivery_attempts`'s own "real, bounded adapter
--    interface, never a fabricated call" pattern) -- an append-only
--    request/response evidence log, not a retry queue.
-- 3. **Provider credentials reuse `app.integration_connections`/`app.
--    integration_connection_credentials` (IAE-336) directly** -- one new
--    adapter seeded at migration-apply time: `maps_geocoding`, category
--    `'location'`.
-- 4. **Cost metering (`RPD-028`) reuses `app.compute_provider_billed_amount`
--    directly (IAE-014)** -- the one function that ever computes the +20%
--    markup; this checkpoint does not re-derive it.
-- 5. **Trigger authority is instance-level** (`app.check_maps_provider_
--    trigger_authority`: active tenant membership or Supreme), mirroring
--    `app.check_webhook_trigger_authority`/`app.check_notification_trigger_
--    authority`'s own identical "any active tenant member may cause an
--    instance-level action" shape exactly -- looking up an address is a
--    routine operational action, not a configuration one (`INTHUB:Configure`
--    still gates the underlying connection's own setup, via IAE-336's
--    already-built `app.create_integration_connection`, unchanged).
-- 6. **The real outbound HTTP client's own SSRF guard is reused
--    proactively** -- `lib/webhooks/ssrf-guard.server.ts`'s own
--    `checkWebhookDispatchUrlIsSafe`, the SAME reuse IAE-014 already applied,
--    now a THIRD real outbound HTTP client in this repository relying on it.
-- 7. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--    execute on all functions in schema app from public` before its final
--    grants.

-- ===========================================================================
-- app.geocode_requests (design decision 2) -- append-only request/response
-- evidence, never a retry queue (geocoding is synchronous, not retried via
-- app.jobs).
-- ===========================================================================

create table app.geocode_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  connection_id uuid not null references app.integration_connections (id),
  request_type text not null,
  query_payload jsonb not null,
  status text not null,
  result_payload jsonb,
  provider_unit_cost_amount numeric,
  currency text,
  billed_amount numeric,
  error_message text,
  requested_by_auth_user_id uuid references auth.users (id),
  requested_by text,
  created_at timestamptz not null default now(),
  constraint geocode_requests_request_type_check check (request_type in ('geocode', 'route')),
  constraint geocode_requests_status_check check (status in ('success', 'failed')),
  constraint geocode_requests_query_check check (app.validate_config_value(query_payload)),
  constraint geocode_requests_cost_check check (provider_unit_cost_amount is null or provider_unit_cost_amount >= 0)
);

comment on table app.geocode_requests is
  'IAE-015: append-only geocode/route request-response evidence -- the real, bounded adapter interface a live outbound maps-provider call reports its outcome to. Never a retry queue (geocoding is a synchronous call, unlike every app.jobs-backed delivery this session has otherwise built).';

create index geocode_requests_tenant_id_idx on app.geocode_requests (tenant_id, created_at desc);

-- ===========================================================================
-- Trigger authority (design decision 5)
-- ===========================================================================

create function app.check_maps_provider_trigger_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- ===========================================================================
-- app.get_maps_provider_dispatch_info -- the real outbound client's own
-- minimal read (never the raw credential; app.get_maps_provider_credential
-- is the separate, dedicated read for that, mirroring IAE-014's own
-- app.get_notification_provider_credential exactly).
-- ===========================================================================

create function app.get_maps_provider_dispatch_info(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (connection_id uuid, connection_status text, connection_config jsonb)
language plpgsql
stable
as $$
begin
  if not app.check_maps_provider_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select ic.id, ic.status, ic.config
  from app.integration_connections ic
  where ic.tenant_id = p_tenant_id and ic.adapter_code = 'maps_geocoding'
  order by (ic.environment = 'production') desc, ic.created_at desc
  limit 1;
end;
$$;

comment on function app.get_maps_provider_dispatch_info is
  'IAE-015: the real geocode/route client''s own minimal read -- resolves the tenant''s own active maps_geocoding connection. Deliberately never selects the raw credential.';

create function app.get_maps_provider_credential(p_connection_id uuid)
returns text
language sql
stable
as $$
  select credential_value from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

comment on function app.get_maps_provider_credential is
  'IAE-015: service_role-only, mirrors app.get_notification_provider_credential (IAE-014) exactly -- the real client''s own separate, dedicated credential read.';

-- ===========================================================================
-- app.record_geocode_request (design decisions 2, 4) -- the bounded adapter
-- interface a real outbound maps-provider call reports its outcome to.
-- ===========================================================================

create function app.record_geocode_request(
  p_tenant_id uuid,
  p_connection_id uuid,
  p_request_type text,
  p_query_payload jsonb,
  p_status text,
  p_result_payload jsonb,
  p_provider_unit_cost_amount numeric,
  p_currency text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.geocode_requests
language plpgsql
as $$
declare
  v_billed_amount numeric;
  v_row app.geocode_requests;
begin
  if not app.check_maps_provider_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_provider_unit_cost_amount is not null and p_provider_unit_cost_amount < 0 then
    raise exception 'geocode_invalid_cost_amount: provider_unit_cost_amount must not be negative' using errcode = 'check_violation';
  end if;

  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

  insert into app.geocode_requests (tenant_id, connection_id, request_type, query_payload, status, result_payload, provider_unit_cost_amount, currency, billed_amount, error_message, requested_by_auth_user_id, requested_by)
  values (p_tenant_id, p_connection_id, p_request_type, p_query_payload, p_status, p_result_payload, p_provider_unit_cost_amount, p_currency, v_billed_amount, p_error_message, p_actor_auth_user_id, p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_geocode_request',
    'app.geocode_requests', v_row.id, case when p_status = 'success' then 'success' else 'failure' end, p_error_message, null,
    jsonb_build_object('request_type', v_row.request_type, 'status', v_row.status)
  );

  return v_row;
end;
$$;

comment on function app.record_geocode_request is
  'IAE-015: the real outbound maps-provider client''s own bounded adapter interface. billed_amount is computed server-side via app.compute_provider_billed_amount (IAE-014, reused directly), never trusted from the caller.';

create function app.list_geocode_requests_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.geocode_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view geocode requests for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'geocode_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  return query select * from app.geocode_requests where tenant_id = p_tenant_id order by created_at desc limit p_limit;
end;
$$;

comment on function app.list_geocode_requests_for_tenant is
  'IAE-015: staff-only (reuses app.check_api_webhook_admin_authority, PLT-129 -- Supreme or the tenant''s own active tenant_admin) read of this tenant''s own geocode/route request log, including real metered cost. security definer, ATW-032-hardened from the first draft.';

-- ===========================================================================
-- Real adapter seed (design decision 3)
-- ===========================================================================

insert into app.integration_adapters (code, name, category, registered_by) values
  ('maps_geocoding', 'Enterprise Maps Geocoding and Routing', 'location', 'phase-09-foundation');

-- ===========================================================================
-- RLS
-- ===========================================================================

alter table app.geocode_requests enable row level security;

-- No direct authenticated grant -- the only read path is app.list_geocode_
-- requests_for_tenant (staff-only), the same posture app.notification_
-- delivery_attempts/app.webhook_delivery_attempts already established for a
-- table with no simple direct RLS predicate and a dedicated read function.

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select, insert on app.geocode_requests to service_role;
grant execute on function app.check_maps_provider_trigger_authority(uuid, uuid) to service_role;
grant execute on function app.get_maps_provider_dispatch_info(uuid, uuid) to service_role;
grant execute on function app.get_maps_provider_credential(uuid) to service_role;
grant execute on function app.record_geocode_request(uuid, uuid, text, jsonb, text, jsonb, numeric, text, text, uuid, text) to service_role;
grant execute on function app.list_geocode_requests_for_tenant(uuid, uuid, integer) to authenticated, service_role;
