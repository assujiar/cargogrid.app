-- Intelligence, Automation and Enterprise Expansion: Public API Platform (IAE-009,
-- CG-S14-IAE-009, Prompt 337). First prompt of Batch 3 (337-341), the API Ecosystem
-- track ADR-0025 Part A already scoped: extend `app.api_keys`/`app.webhook_*`
-- (PLT-129, `20260719150000_create_api_key_webhook_primitives.sql`) with the real REST
-- `/v1` surface and rate-limit enforcement Prompt 130 left `NOT_RUN`/`BLOCKED` -- never
-- a second, parallel key table.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **No new API-key table.** `app.api_keys` (PLT-129) already ships hash-only
--    storage, create-once-display, scope validation via `app.evaluate_permission()`
--    ("can only narrow, never widen"), overlap-window rotation and revoke. This
--    migration extends its CONSUMPTION (a real gateway, real rate-limit enforcement,
--    real version registry), never its shape. Customer-scoped (IAE-010)/vendor-scoped
--    (IAE-011) keys reuse this exact same row shape per ADR-0025 Part A -- narrower
--    scopes, not a new column or table.
-- 2. **Rate-limit enforcement (Prompt 130's own disclosed `NOT_RUN`), anchored on
--    `api_key_id`, never a caller-suppliable discriminator alone.**
--    `20260730550000_harden_numbering_continuity_custom_field_replay_and_rate_limits.sql`
--    (ISS-2026-034) already found and fixed the exact failure mode a naive
--    IP/`client_key`-only limiter has: `x-forwarded-for` is fully caller-controlled, so
--    a limiter keyed on it alone is trivially defeated by varying it per request. An
--    API key's own id is NOT caller-rotatable within a single credential's lifetime
--    (rotating it mints a genuinely new key, audited, authority-gated) -- the correct
--    non-rotatable discriminator for this capability. `app.check_and_increment_api_key_
--    rate_limit()` is a single atomic `insert ... on conflict do update` per
--    (api_key_id, minute-bucketed window) -- safe under real concurrency without an
--    explicit row lock, since Postgres's own upsert conflict resolution is atomic per
--    row; proven live with two genuinely concurrent OS processes hitting the same key.
--    A request that will BE rejected still increments the counter (the same "count the
--    attempt, not only the accepted ones" discipline `app.tracking_lookup_attempts` and
--    every other attempts-table in this repository already applies) -- otherwise a
--    caller could probe past the limit for free once already over it.
-- 3. **`app.api_versions`: a real, Supreme-registered version/deprecation registry**,
--    mirroring `app.webhook_event_types`'s own "registry, not enum" shape (global, not
--    tenant-scoped -- API version status is platform metadata, not tenant data).
--    Seeded with `'v1'` (`active`) in this migration, since versioning genuinely IS
--    this capability's own scope, unlike webhook event types (owned by IAE-012/Prompt
--    340 per ADR-0025 Part B). `app.set_api_version_status()` is the real, audited
--    deprecate/sunset transition Prompt 337's own business rule ("breaking changes
--    require version/deprecation plan") requires.
-- 4. **`app.authenticate_and_authorize_api_request()`: the one real gateway entrypoint**
--    a REST route handler calls per request -- composes `app.authenticate_api_key()` +
--    `app.api_key_has_scope()` (both PLT-129, unchanged) + the new rate-limit check +
--    a `created_by_auth_user_id` lookup, in that order. Returns an `outcome` string
--    (`ok`/`unauthenticated`/`forbidden_scope`/`rate_limited`) rather than raising for
--    every one of these four ROUTINE, expected-under-normal-operation outcomes --
--    mirroring `app.ingest_driver_mobile_report`/`app.ingest_third_party_provider_
--    webhook_event`'s own established "status string, not an exception, for an
--    expected reject case" convention (`app/api/tracking/driver-mobile/route.ts`,
--    `app/api/webhooks/third-party-gps/[connectionId]/route.ts`) -- a genuinely
--    exceptional condition (a malformed call to this function itself) still raises
--    normally. `service_role`-only: this function is the gateway's own internal
--    dispatch primitive, never callable by a live `authenticated` session.
-- 5. **Downstream actor identity for a request that dispatches into an EXISTING
--    domain RPC requiring a live human actor.** `app.resolve_gps_device_for_handshake`
--    (ATW-226E) established that a purpose-built, narrowly-scoped function may accept
--    a null actor for its OWN direct mutation -- but every REUSED domain RPC this
--    repository has built so far (`app.queue_webhook_delivery` included) requires a
--    real, non-null `p_actor_auth_user_id` and performs its OWN live authority
--    check against it (`evaluate_permission`/`has_active_tenant_membership`), by
--    design. This gateway therefore dispatches AS the presented key's own
--    `created_by_auth_user_id` (a real, accountable identity: the tenant admin who
--    issued the credential) with `actor_label = 'api_key:' || key_prefix` -- a
--    disclosed, deliberate choice with a genuine defense-in-depth property: if that
--    admin is later demoted or removed, the downstream RPC's own live authority
--    re-check starts failing the key's calls even before the key is explicitly
--    revoked, rather than trusting the key's own frozen `scopes` array forever.
-- 6. **`app.list_webhook_event_types()`/`app.list_api_logs_for_tenant()`: the two
--    small, additive read gaps PLT-129/PLT-130 each disclosed and left for a future
--    consumer.** PLT-129 never shipped a list function for its own broadly-readable
--    registry (only Supreme-only `register_webhook_event_type`); PLT-130's own header
--    states verbatim "no read/list function exists for `app.api_logs`... deferred to
--    whichever future capability builds the admin-observability surface." Both are
--    exactly what this capability's own developer console needs (event-type docs,
--    usage/audit log) -- filled here, not re-derived elsewhere. **Self-caught
--    correction, before commit:** the repository-wide `rbac-enforcement.sql` sweep
--    (ATW-032/ISS-2026-032) caught `app.list_api_logs_for_tenant` granted to
--    `authenticated` while taking `p_actor_auth_user_id` without first calling
--    `app.assert_actor_is_session_identity` -- any authenticated session could have
--    passed a colleague's UUID and read that tenant's own API request audit trail.
--    Fixed by adding the identical guard `app.list_api_keys_for_tenant`/`app.list_
--    webhook_endpoints_for_tenant` (PLT-129) already carry.
-- 7. **GraphQL: disclosed out of scope, not fabricated.** Confirmed via direct
--    repository search: zero GraphQL dependency (`package.json`), zero schema, zero
--    resolver, anywhere. `server/policies/graphql-complexity.ts` (ADR-0012) is a pure
--    complexity SCORER over a synthetic field tree, proven to work correctly, but has
--    no live GraphQL server behind it to wire into. PLT-130's own migration header
--    states this outright: "the actual `app/api/v1/**` route scaffold and the actual
--    schema-first GraphQL server are two SEPARATE, LATER atomic slices"
--    (`08_API_INTEGRATION_WORKSTREAM.md` §15, line 244). This capability builds the
--    REST `/v1` surface only; "REST and GraphQL must share authentication..." is
--    satisfied by building the shared contract (`server/contracts/api/api.ts`, already
--    built by PLT-130 and reused verbatim here) a future GraphQL resolver would also
--    consume, not by fabricating a GraphQL server this repository does not have.
-- 8. **No new job type, no async work of its own.** This capability's REST surface is
--    synchronous request/response only -- it enqueues nothing onto `app.jobs`. The
--    real outbound webhook delivery WORKER (which does need `app.jobs`) is IAE-012's
--    own scope (Prompt 340, ADR-0025 Part B), not this one's.
-- 9. **Resource allowlist, deliberately narrow at this checkpoint, disclosed rather
--    than padded.** This migration's own REST surface exposes exactly two read
--    resources (`GET /v1/status`, `GET /v1/webhook-event-types`) proving the full
--    gateway mechanics (auth/scope/rate-limit/version/audit) end to end against real,
--    already-built domain data -- deliberately NOT inventing a synthetic write
--    resource this capability does not itself own. IAE-010 (Customer API, Prompt 338)
--    and IAE-011 (Vendor API, Prompt 339) are where the actual idempotent
--    quote/booking/RFQ/capacity mutation resources this gateway's own idempotency-key
--    middleware exists to serve are built, reusing this migration's authentication/
--    rate-limit/versioning primitives directly rather than re-deriving them.
-- 10. Per `ERR-2026-004`: this migration carries its own explicit
--     `revoke execute on all functions in schema app from public;` before its final
--     grants.

-- ===========================================================================
-- Rate-limit enforcement (design decision 2)
-- ===========================================================================

create table app.api_key_rate_limit_windows (
  api_key_id uuid not null references app.api_keys (id),
  window_start timestamptz not null,
  request_count integer not null default 0,
  constraint api_key_rate_limit_windows_pk primary key (api_key_id, window_start),
  constraint api_key_rate_limit_windows_count_check check (request_count > 0)
);

comment on table app.api_key_rate_limit_windows is
  'IAE-009: one row per (api_key, minute-bucketed window), incremented atomically by app.check_and_increment_api_key_rate_limit(). Anchored on api_key_id (non-rotatable within a credential''s lifetime), never a caller-suppliable IP/client_key alone -- the ISS-2026-034 lesson. Zero authenticated grant: operational rate-limit evidence, not tenant-facing data (mirrors app.webhook_deliveries/app.webhook_delivery_attempts). No automatic purge -- bounded per-key-per-minute growth, the same accepted-and-undisclosed-otherwise shape every other attempts-table in this repository already has.';

-- Single atomic upsert -- correct under real concurrency without an explicit row lock,
-- since the unique (api_key_id, window_start) constraint's own conflict resolution is
-- atomic per row. A null rate_limit_per_minute (PLT-129's own "unlimited" convention)
-- short-circuits before ever touching the table, matching that column's own established
-- meaning.
create function app.check_and_increment_api_key_rate_limit(p_api_key_id uuid)
returns table (allowed boolean, limit_per_minute integer, remaining integer)
language plpgsql
as $$
declare
  v_limit integer;
  v_window timestamptz := date_trunc('minute', now());
  v_count integer;
begin
  select rate_limit_per_minute into v_limit from app.api_keys where id = p_api_key_id;

  if v_limit is null then
    return query select true, null::integer, null::integer;
    return;
  end if;

  insert into app.api_key_rate_limit_windows (api_key_id, window_start, request_count)
  values (p_api_key_id, v_window, 1)
  on conflict (api_key_id, window_start)
    do update set request_count = app.api_key_rate_limit_windows.request_count + 1
  returning request_count into v_count;

  return query select (v_count <= v_limit), v_limit, greatest(v_limit - v_count, 0);
end;
$$;

comment on function app.check_and_increment_api_key_rate_limit is
  'IAE-009: real, live enforcement of app.api_keys.rate_limit_per_minute (PLT-129''s own field, stored but never enforced until this checkpoint -- Prompt 130''s disclosed NOT_RUN). Every call -- accepted or rejected -- increments the current minute''s counter first, then compares; a null rate_limit_per_minute means unlimited (never touches the table). Live-proven safe under two genuinely concurrent OS processes racing the same api_key_id.';

-- ===========================================================================
-- API version registry (design decision 3)
-- ===========================================================================

create table app.api_versions (
  code text primary key,
  status text not null default 'active',
  sunset_at timestamptz,
  notes text,
  registered_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint api_versions_status_check check (status in ('active', 'deprecated', 'sunset')),
  constraint api_versions_sunset_check check (status <> 'sunset' or sunset_at is not null)
);

comment on table app.api_versions is
  'IAE-009: registry of public API versions (e.g. v1), mirroring app.webhook_event_types'' own "registry, not enum" shape -- global platform metadata, not tenant-scoped. active -> deprecated -> sunset is a real, audited, one-way lifecycle (app.set_api_version_status); a sunset version always carries a real sunset_at, never a bare status flip.';

create index api_versions_status_idx on app.api_versions (status);

create function app.touch_api_versions_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger api_versions_touch_row
  before update on app.api_versions
  for each row
  execute function app.touch_api_versions_row();

-- Idempotent by code, Supreme-only -- the identical shape app.register_webhook_event_type
-- already established.
create function app.register_api_version(
  p_code text,
  p_status text,
  p_sunset_at timestamptz,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.api_versions
language plpgsql
as $$
declare
  v_existing app.api_versions;
  v_version app.api_versions;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register an API version'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.api_versions where code = p_code;
  if found then
    return v_existing;
  end if;

  if p_status not in ('active', 'deprecated', 'sunset') then
    raise exception 'api_version_invalid_status: % is not one of active/deprecated/sunset', p_status
      using errcode = 'check_violation';
  end if;
  if p_status = 'sunset' and p_sunset_at is null then
    raise exception 'api_version_missing_sunset_at: a sunset version requires sunset_at'
      using errcode = 'check_violation';
  end if;

  insert into app.api_versions (code, status, sunset_at, notes, registered_by)
  values (p_code, p_status, p_sunset_at, p_notes, p_registered_by)
  returning * into v_version;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_api_version',
    'app.api_versions', null, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$$;

-- The real deprecate/sunset transition (Prompt 337's own "breaking changes require
-- version/deprecation plan" business rule) -- a distinct function from register, since
-- registering is create-or-return-existing while this is an explicit, audited state
-- change against an ALREADY-existing version.
create function app.set_api_version_status(
  p_code text,
  p_status text,
  p_sunset_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.api_versions
language plpgsql
as $$
declare
  v_version app.api_versions;
  v_updated app.api_versions;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may change an API version''s status'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.api_versions where code = p_code;
  if not found then
    raise exception 'api_version_not_found: no version %', p_code using errcode = 'no_data_found';
  end if;

  if p_status not in ('active', 'deprecated', 'sunset') then
    raise exception 'api_version_invalid_status: % is not one of active/deprecated/sunset', p_status
      using errcode = 'check_violation';
  end if;
  if p_status = 'sunset' and p_sunset_at is null then
    raise exception 'api_version_missing_sunset_at: a sunset version requires sunset_at'
      using errcode = 'check_violation';
  end if;

  update app.api_versions
  set status = p_status, sunset_at = case when p_status = 'sunset' then p_sunset_at else v_version.sunset_at end
  where code = p_code
  returning * into v_updated;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'set_api_version_status',
    'app.api_versions', null, 'success', null,
    jsonb_build_object('code', v_version.code, 'status', v_version.status),
    jsonb_build_object('code', v_updated.code, 'status', v_updated.status, 'sunset_at', v_updated.sunset_at)
  );

  return v_updated;
end;
$$;

create function app.list_api_versions()
returns setof app.api_versions
language sql
stable
as $$
  select * from app.api_versions order by code;
$$;

-- Seed the real, first version this repository's public API surface actually ships --
-- a raw insert (not through the gated RPC), the identical convention IAE-007's own
-- INTHUB module/permission seed used, since a migration body runs with full DDL/DML
-- rights, not through app-level RPC authority.
insert into app.api_versions (code, status, notes, registered_by)
values ('v1', 'active', 'Initial public API version (IAE-009, Prompt 337).', 'system');

-- ===========================================================================
-- Gateway entrypoint (design decisions 4, 5)
-- ===========================================================================

create function app.authenticate_and_authorize_api_request(
  p_raw_key text,
  p_required_scope text
)
returns table (
  outcome text, api_key_id uuid, tenant_id uuid, created_by_auth_user_id uuid,
  rate_limit_per_minute integer, rate_limit_remaining integer
)
language plpgsql
as $$
declare
  v_auth record;
  v_rate record;
begin
  begin
    select * into v_auth from app.authenticate_api_key(p_raw_key);
  exception when others then
    return query select 'unauthenticated'::text, null::uuid, null::uuid, null::uuid, null::integer, null::integer;
    return;
  end;

  if p_required_scope is not null and length(trim(p_required_scope)) > 0 and not app.api_key_has_scope(v_auth.api_key_id, p_required_scope) then
    return query select 'forbidden_scope'::text, v_auth.api_key_id, v_auth.tenant_id, null::uuid, v_auth.rate_limit_per_minute, null::integer;
    return;
  end if;

  select * into v_rate from app.check_and_increment_api_key_rate_limit(v_auth.api_key_id);
  if not v_rate.allowed then
    return query select 'rate_limited'::text, v_auth.api_key_id, v_auth.tenant_id, null::uuid, v_rate.limit_per_minute, v_rate.remaining;
    return;
  end if;

  return query
  select 'ok'::text, v_auth.api_key_id, v_auth.tenant_id, k.created_by_auth_user_id, v_rate.limit_per_minute, v_rate.remaining
  from app.api_keys k where k.id = v_auth.api_key_id;
end;
$$;

comment on function app.authenticate_and_authorize_api_request is
  'IAE-009: the one real REST /v1 gateway entrypoint -- composes app.authenticate_api_key() + app.api_key_has_scope() (both PLT-129, unchanged) + app.check_and_increment_api_key_rate_limit() (this migration), in that order, and looks up the key''s own created_by_auth_user_id for downstream actor-identity dispatch (design decision 5). Returns outcome in (ok, unauthenticated, forbidden_scope, rate_limited) rather than raising for any of these four routine, expected reject cases -- mirrors app.ingest_driver_mobile_report''s own established convention. p_required_scope may be null/blank for an endpoint that requires authentication but no specific scope (e.g. GET /v1/status). service_role-only: called exclusively from a REST route handler''s own service-role client, never a live authenticated session.';

-- ===========================================================================
-- Read gaps PLT-129/PLT-130 each disclosed and left open (design decision 6)
-- ===========================================================================

create function app.list_webhook_event_types()
returns setof app.webhook_event_types
language sql
stable
as $$
  select * from app.webhook_event_types order by code;
$$;

comment on function app.list_webhook_event_types is
  'IAE-009: the list function PLT-129 never shipped for its own broadly-readable registry (only Supreme-only app.register_webhook_event_type existed). No in-function authority check: mirrors app.webhook_event_types'' own RLS policy (select to authenticated using (true)) -- the registry itself carries no tenant-sensitive content, so it is readable both by a live authenticated tenant member (the developer console''s own event-type docs panel) and by the REST gateway on behalf of a scope-checked API key.';

create function app.list_api_logs_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 20,
  p_before timestamptz default null
)
returns setof app.api_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  -- ATW-032 (ISS-2026-032): app.check_api_webhook_admin_authority only asks whether the
  -- CLAIMED actor is allowed, never whether the calling session IS that actor -- caught
  -- live by the repository-wide rbac-enforcement.sql sweep before this migration was
  -- ever committed. Without this line any authenticated session could pass a colleague's
  -- (or a real tenant_admin's) UUID and read that tenant's own API request audit trail,
  -- the identical fix app.list_api_keys_for_tenant/app.list_webhook_endpoints_for_tenant
  -- (PLT-129, 20260730510000_harden_actor_identity_unchecked_authority_surface.sql)
  -- already applies.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view API logs for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.api_logs al
  where al.tenant_id = p_tenant_id and (p_before is null or al.created_at < p_before)
  order by al.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

comment on function app.list_api_logs_for_tenant is
  'IAE-009: the read function PLT-130''s own migration header explicitly deferred ("no read/list function exists for app.api_logs ... deferred to whichever future capability builds the admin-observability surface"). Cursor-paginated on created_at (p_before), capped at 100 rows per call. Authority mirrors app.list_api_keys_for_tenant (Supreme, or the target tenant''s own active tenant_admin); self-caught by the repository-wide rbac-enforcement.sql sweep before commit, this also calls app.assert_actor_is_session_identity first (ATW-032/ISS-2026-032) -- the claimed actor must genuinely be the calling session.';

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select, insert, update on app.api_key_rate_limit_windows to service_role;
grant execute on function app.check_and_increment_api_key_rate_limit(uuid) to service_role;

alter table app.api_versions enable row level security;

create policy api_versions_select_all on app.api_versions
for select to authenticated
using (true);

grant select on app.api_versions to authenticated, service_role;
grant insert, update on app.api_versions to service_role;

grant execute on function app.touch_api_versions_row() to service_role;
grant execute on function app.register_api_version(text, text, timestamptz, text, uuid, text) to service_role;
grant execute on function app.set_api_version_status(text, text, timestamptz, uuid, text) to service_role;
grant execute on function app.list_api_versions() to authenticated, service_role;

grant execute on function app.authenticate_and_authorize_api_request(text, text) to service_role;
grant execute on function app.list_webhook_event_types() to authenticated, service_role;
grant execute on function app.list_api_logs_for_tenant(uuid, uuid, integer, timestamptz) to authenticated, service_role;
