-- ISS-2026-270 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- no safe import/registration path exists for migration-seeded reference tables
-- (app.finance_currencies, app.uoms): a raw insert collision raises an unclassified
-- duplicate-key error, and a multi-row batch insert with one colliding row rolls back
-- the ENTIRE batch, including genuinely-new rows in the same statement. Live-reproduced:
-- re-seeding IDR/USD/GBP-new lost the genuinely-new GBP row entirely when USD collided.
-- Confirmed live: zero writer RPCs exist anywhere for either table -- every reference is
-- a read-only validation lookup; the only way any row has ever entered either table is
-- the original bare INSERT in each table's own creation migration.
--
-- Fixed: one governed, idempotent RPC per table, mirroring this repository's own
-- already-established "return the existing row if found, insert only if genuinely new"
-- pattern (app.invite_user, app.provision_tenant, app.grant_principal_membership) rather
-- than the entry's own cited `INSERT ... ON CONFLICT DO NOTHING` alternative -- DO NOTHING
-- would silently accept a same-code row with DIFFERENT name/precision/category values,
-- masking a real data conflict; returning the existing row lets a caller compare it
-- against what it tried to insert and decide for itself, exactly like every other
-- idempotent registration RPC in this codebase already does. Both tables are global,
-- platform-wide reference data (not tenant-scoped) with no prior writer RPC at all, so
-- Supreme Admin is the conservative, consistent authority level -- the same convention
-- already used for the other platform-wide registry this codebase has
-- (app.register_analytics_view, IAE-005).
create function app.import_reference_currency(
  p_code text,
  p_name text,
  p_minor_unit_precision integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_currencies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.finance_currencies;
  v_row app.finance_currencies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may import a reference currency' using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.finance_currencies where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.finance_currencies (code, name, minor_unit_precision)
  values (p_code, p_name, p_minor_unit_precision)
  returning * into v_row;

  perform app.capture_audit_event(null, p_actor_auth_user_id, p_actor_label, 'import_reference_currency', 'app.finance_currencies', null, 'success', null, null, to_jsonb(v_row), gen_random_uuid());

  return v_row;
end;
$$;

comment on function app.import_reference_currency is 'ISS-2026-270: a safe, idempotent import path for app.finance_currencies -- a real migration/import script calls this per row instead of a raw INSERT, so a collision on an already-seeded code returns the existing row (for the caller to compare and decide) rather than raising an unclassified duplicate-key error that rolls back an entire multi-row batch, including genuinely-new rows in the same statement. Supreme Admin only -- this is global, platform-wide reference data with no prior writer RPC at all.';

create function app.import_reference_uom(
  p_code text,
  p_name text,
  p_unit_category text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.uoms
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.uoms;
  v_row app.uoms;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may import a reference UOM' using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.uoms where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.uoms (code, name, unit_category)
  values (p_code, p_name, p_unit_category)
  returning * into v_row;

  perform app.capture_audit_event(null, p_actor_auth_user_id, p_actor_label, 'import_reference_uom', 'app.uoms', null, 'success', null, null, to_jsonb(v_row), gen_random_uuid());

  return v_row;
end;
$$;

comment on function app.import_reference_uom is 'ISS-2026-270: a safe, idempotent import path for app.uoms -- mirrors app.import_reference_currency verbatim (both tables share the identical shape and the identical gap). Supreme Admin only.';

revoke execute on all functions in schema app from public;
grant execute on function app.import_reference_currency(text, text, integer, uuid, text) to service_role;
grant execute on function app.import_reference_uom(text, text, text, uuid, text) to service_role;

-- Option 2 wrapper (RGL-394): app is not exposed to PostgREST directly -- every
-- externally-callable app.* function needs a matching public.* wrapper, enforced by
-- scripts/db-tests/public-api-wrapper-regression.sql's own zero-tolerance guard.
create function public.import_reference_currency(p_code text, p_name text, p_minor_unit_precision integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_currencies
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.import_reference_currency(p_code, p_name, p_minor_unit_precision, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.import_reference_currency(p_code text, p_name text, p_minor_unit_precision integer, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.import_reference_currency with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- 20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql's own amended
-- convention (Finding 2 there): Supabase's own platform-level default privilege
-- grants EXECUTE on every new public-schema function to anon/authenticated/service_role
-- automatically at CREATE time -- `revoke ... from public` alone (the PUBLIC
-- pseudo-role) never touches that. Must revoke from the named roles explicitly.
revoke execute on function public.import_reference_currency(p_code text, p_name text, p_minor_unit_precision integer, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.import_reference_currency(p_code text, p_name text, p_minor_unit_precision integer, p_actor_auth_user_id uuid, p_actor_label text) to service_role;

create function public.import_reference_uom(p_code text, p_name text, p_unit_category text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.uoms
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.import_reference_uom(p_code, p_name, p_unit_category, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.import_reference_uom(p_code text, p_name text, p_unit_category text, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.import_reference_uom with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.import_reference_uom(p_code text, p_name text, p_unit_category text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.import_reference_uom(p_code text, p_name text, p_unit_category text, p_actor_auth_user_id uuid, p_actor_label text) to service_role;
