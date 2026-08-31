-- Closes `ISS-2026-147` item 2, and records that item 1 was already closed by work that never
-- updated the entry.
--
-- ITEM 1, RE-DERIVED RATHER THAN ASSUMED STILL TRUE
--
--   The entry says "zero test coverage for the 9 `/api/v1` REST route handlers". That is no
--   longer the case. There are 9 route handlers under `app/api/v1/` and 9 matching test files
--   under `tests/api/v1/`, one per handler, each independently confirmed to correspond:
--   customer-bookings, customer-bookings-submit, customer-shipment-tracking, status,
--   vendor-assignment-accept, vendor-assignment-decline, vendor-rfq-view, vendor-rfq-response,
--   webhook-event-types. Item 1 is closed on evidence, not on a claim.
--
-- ITEM 2 -- THE FILTER `IAE-013` CLAIMED AND NEVER BUILT
--
--   `IAE-013`'s own migration comment claimed per-connector execution-log filtering. The
--   2026-08-28 re-verification sharpened the finding correctly: this was never merely
--   "under-evidenced", the capability did not exist. Neither `app.list_api_logs_for_tenant`
--   nor `app.list_webhook_deliveries_for_tenant` accepted any connector-identifying filter, so
--   a tenant admin running several integrations could not isolate one integration's history at
--   all -- every row of every connector, interleaved, in one tenant-wide list.
--
--   No security exposure was ever involved and none is created here: every row was, and remains,
--   correctly tenant-scoped. This is a missing capability, and the fix is one optional predicate
--   on each function.
--
-- WHY DROP + CREATE RATHER THAN `CREATE OR REPLACE`
--
--   `CREATE OR REPLACE FUNCTION` cannot append a parameter. Even a defaulted one produces a
--   SECOND, distinct overload alongside the original, which makes every pre-existing call site
--   genuinely ambiguous -- the defect `ISS-2026-260` found the hard way and `ISS-2026-269`'s fix
--   pass established the convention for. Both functions, and both `public.*` wrappers, are
--   therefore dropped at their exact old signatures and recreated. Every existing caller keeps
--   working unchanged, because the new parameter is trailing and defaults to null.

-- ===========================================================================
-- app.list_api_logs_for_tenant -- filter by the API key that made the request
-- ===========================================================================
--
-- api_key_id is the connector discriminator for the REST/GraphQL surface: an integration
-- authenticates with its own key, so "this connector's execution history" is exactly "the log
-- rows carrying this key". A null p_api_key_id keeps the existing tenant-wide behaviour, so the
-- filter is opt-in and nothing that reads this function today changes shape.

drop function public.list_api_logs_for_tenant(uuid, uuid, integer, timestamptz);
drop function app.list_api_logs_for_tenant(uuid, uuid, integer, timestamptz);

create function app.list_api_logs_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 20,
  p_before timestamptz default null,
  p_api_key_id uuid default null
)
returns setof app.api_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  -- ATW-032 (ISS-2026-032): app.check_api_webhook_admin_authority only asks whether the
  -- CLAIMED actor is allowed, never whether the calling session IS that actor. Preserved
  -- byte-for-byte from the pre-drop body -- the authority chain is not what changed here.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view API logs for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Validated, not silently ignored: a key id belonging to a DIFFERENT tenant would otherwise
  -- return an empty list, which is a usable oracle -- "empty" would mean "that key is not
  -- mine", and a caller could walk key ids to learn which exist elsewhere. Raising the same
  -- not-found for a nonexistent key and for another tenant's key discloses neither.
  if p_api_key_id is not null
     and not exists (select 1 from app.api_keys k where k.id = p_api_key_id and k.tenant_id = p_tenant_id)
  then
    raise exception 'api_key_not_found: % is not an API key of tenant %', p_api_key_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  return query
  select * from app.api_logs al
  where al.tenant_id = p_tenant_id
    and (p_before is null or al.created_at < p_before)
    and (p_api_key_id is null or al.api_key_id = p_api_key_id)
  order by al.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

comment on function app.list_api_logs_for_tenant is
  'IAE-009: the read function PLT-130''s own migration header explicitly deferred ("no read/list function exists for app.api_logs ... deferred to whichever future capability builds the admin-observability surface"). Cursor-paginated on created_at (p_before), capped at 100 rows per call. Authority mirrors app.list_api_keys_for_tenant (Supreme, or the target tenant''s own active tenant_admin); self-caught by the repository-wide rbac-enforcement.sql sweep before commit, this also calls app.assert_actor_is_session_identity first (ATW-032/ISS-2026-032) -- the claimed actor must genuinely be the calling session. ISS-2026-147 item 2 (20260831070000): p_api_key_id is the per-connector filter IAE-013''s own comment claimed and never built -- optional and trailing, so every pre-existing caller is unaffected. A key id that is not this tenant''s own raises api_key_not_found rather than returning an empty list, so the filter cannot be used as an existence oracle for another tenant''s keys.';

revoke execute on function app.list_api_logs_for_tenant(uuid, uuid, integer, timestamptz, uuid) from public;
grant execute on function app.list_api_logs_for_tenant(uuid, uuid, integer, timestamptz, uuid) to authenticated, service_role;

create function public.list_api_logs_for_tenant(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer default 20,
  p_before timestamptz default null, p_api_key_id uuid default null
)
returns setof app.api_logs
language sql
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_api_logs_for_tenant(p_tenant_id, p_actor_auth_user_id, p_limit, p_before, p_api_key_id);
$wrap$;

comment on function public.list_api_logs_for_tenant(uuid, uuid, integer, timestamptz, uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_api_logs_for_tenant with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- `from anon, ... , public`, not `from public` alone. `revoke ... from public` removes only the
-- PUBLIC pseudo-role; Supabase's ALTER DEFAULT PRIVILEGES grants `anon` EXECUTE explicitly at
-- CREATE time in schema public, and an explicit grant survives a PUBLIC revoke. That is exactly
-- how ISS-2026-309 shipped two anon-executable SECURITY DEFINER wrappers, and it is what
-- public-api-wrapper-regression.sql caught here on the first run of this migration.
revoke execute on function public.list_api_logs_for_tenant(uuid, uuid, integer, timestamptz, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_api_logs_for_tenant(uuid, uuid, integer, timestamptz, uuid) to authenticated, service_role;

-- ===========================================================================
-- app.list_webhook_deliveries_for_tenant -- filter by endpoint
-- ===========================================================================
--
-- The webhook half's connector discriminator is the endpoint: one integration, one endpoint URL.
-- Same shape, same reasoning, same not-found rule.

drop function public.list_webhook_deliveries_for_tenant(uuid, uuid, text, integer);
drop function app.list_webhook_deliveries_for_tenant(uuid, uuid, text, integer);

create function app.list_webhook_deliveries_for_tenant(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text,
  p_limit integer default 50,
  p_webhook_endpoint_id uuid default null
)
returns table (
  id uuid, webhook_endpoint_id uuid, endpoint_url text, event_type_code text,
  status text, attempts integer, max_attempts integer, next_attempt_at timestamptz,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view webhook deliveries for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_limit is null or p_limit <= 0 or p_limit > 200 then
    raise exception 'webhook_invalid_limit: limit must be between 1 and 200' using errcode = 'check_violation';
  end if;

  if p_status is not null and not (p_status = any (array['pending', 'delivered', 'dead_letter'])) then
    raise exception 'webhook_invalid_status_filter: % is not one of pending/delivered/dead_letter', p_status
      using errcode = 'check_violation';
  end if;

  if p_webhook_endpoint_id is not null
     and not exists (select 1 from app.webhook_endpoints e where e.id = p_webhook_endpoint_id and e.tenant_id = p_tenant_id)
  then
    raise exception 'webhook_endpoint_not_found: % is not a webhook endpoint of tenant %', p_webhook_endpoint_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  return query
  select d.id, d.webhook_endpoint_id, e.url, d.event_type_code, d.status, d.attempts, d.max_attempts, d.next_attempt_at, d.created_at, d.updated_at
  from app.webhook_deliveries d
  join app.webhook_endpoints e on e.id = d.webhook_endpoint_id
  where d.tenant_id = p_tenant_id
    and (p_status is null or d.status = p_status)
    and (p_webhook_endpoint_id is null or d.webhook_endpoint_id = p_webhook_endpoint_id)
  order by d.created_at desc
  limit p_limit;
end;
$$;

comment on function app.list_webhook_deliveries_for_tenant is
  'IAE-012: staff-only delivery-log/DLQ read, joined with the endpoint''s own url. security definer, calls app.assert_actor_is_session_identity first (ATW-032 discipline, applied proactively). ISS-2026-147 item 2 (20260831070000): p_webhook_endpoint_id is the per-connector filter -- optional and trailing, so every pre-existing caller is unaffected. An endpoint id that is not this tenant''s own raises webhook_endpoint_not_found rather than returning an empty list, so the filter cannot be used as an existence oracle for another tenant''s endpoints.';

revoke execute on function app.list_webhook_deliveries_for_tenant(uuid, uuid, text, integer, uuid) from public;
grant execute on function app.list_webhook_deliveries_for_tenant(uuid, uuid, text, integer, uuid) to authenticated, service_role;

create function public.list_webhook_deliveries_for_tenant(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text,
  p_limit integer default 50, p_webhook_endpoint_id uuid default null
)
returns table (
  id uuid, webhook_endpoint_id uuid, endpoint_url text, event_type_code text,
  status text, attempts integer, max_attempts integer, next_attempt_at timestamptz,
  created_at timestamptz, updated_at timestamptz
)
language sql
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_webhook_deliveries_for_tenant(p_tenant_id, p_actor_auth_user_id, p_status, p_limit, p_webhook_endpoint_id);
$wrap$;

comment on function public.list_webhook_deliveries_for_tenant(uuid, uuid, text, integer, uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_webhook_deliveries_for_tenant with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.list_webhook_deliveries_for_tenant(uuid, uuid, text, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_webhook_deliveries_for_tenant(uuid, uuid, text, integer, uuid) to authenticated, service_role;
