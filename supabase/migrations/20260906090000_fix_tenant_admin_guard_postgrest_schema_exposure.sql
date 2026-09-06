-- CG-AUDIT-2026-09-02 Ø1 remediation (tenant-admin-guard scope only).
--
-- The independent launch-readiness audit (docs/audit/2026-09-02-independent-launch-readiness-audit.md
-- §4 Ø) found that `supabase/config.toml` only ever exposed `public`/`graphql_public` to
-- PostgREST, while every application table lives in schema `app`. Every `.from("<table>")`
-- call the app makes therefore targets a schema PostgREST cannot see and fails at runtime.
--
-- `lib/portal/tenant-admin-guard-deps.server.ts`'s `findTenantBySlug` is one such call
-- (`supabase.from("tenants")...`). This migration adds the Option-2 wrapper pair for it,
-- following the same pattern already established by
-- `20260826000000_create_public_api_data_wrappers.sql` (a thin `public.*` SECURITY DEFINER
-- pass-through to a real `app.*` SECURITY DEFINER function) rather than exposing schema
-- `app` directly, which the audit and the repo's own RGL-BLK-002 remediation both reject.
--
-- The new resolver deliberately mirrors -- rather than reimplements -- the `app.tenants`
-- RLS policy `tenants_select_own_tenant` (`app.has_active_tenant_membership(id) AND NOT
-- app.actor_holds_customer_user_layer(id)`, see 20260730560000), and preserves the guard's
-- documented anti-tenant-enumeration contract (`lib/portal/tenant-admin-guard.ts`): "does
-- not exist" and "caller is not an active, non-customer-layer member" collapse to the same
-- empty result, exactly as `app.resolve_tenant_by_domain` already does for the analogous
-- domain-routing lookup. Because the actor id is caller-supplied, the function also asserts
-- session identity (`app.assert_actor_is_session_identity`) up front to close the
-- impersonation class the audit verified closed everywhere else.
--
-- Per the standing convention `20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql`
-- amended (Finding 2 there: this Supabase project's own platform bootstrap carries `ALTER
-- DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon,
-- authenticated, service_role`, so every `create function public.*` silently picks up an
-- EXECUTE grant to anon and authenticated at creation time, and `revoke ... from public`
-- alone never removes a role-specific grant a default-privilege rule already attached by
-- name) -- the public wrapper below explicitly revokes from `anon, authenticated,
-- service_role, public` before granting back exactly the roles this function needs.
--
-- `scripts/db-tests/public-api-wrapper-regression.sql`'s own exhaustive grant-parity check
-- requires every `public.*` wrapper's grant set to exactly match its `app.*` counterpart's
-- (zero-tolerance widening or narrowing) -- both functions below are therefore granted the
-- identical role set (`service_role`, `authenticated`), never `anon`.

create function app.resolve_tenant_by_slug_for_actor(p_slug text, p_actor_auth_user_id uuid)
returns table(id uuid, slug text, canonical_status text)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $function$
declare
  v_tenant app.tenants;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_tenant from app.tenants t where t.slug = p_slug;
  if not found
     or not app.has_active_tenant_membership(v_tenant.id, p_actor_auth_user_id)
     or app.actor_holds_customer_user_layer(v_tenant.id, p_actor_auth_user_id)
  then
    return;
  end if;

  return query select v_tenant.id, v_tenant.slug, v_tenant.canonical_status;
end;
$function$;

comment on function app.resolve_tenant_by_slug_for_actor(text, uuid) is
  'CG-AUDIT-2026-09-02 Ø1: resolves a tenant by slug for the tenant-admin portal entry guard (lib/portal/tenant-admin-guard.ts), mirroring app.tenants'' own tenants_select_own_tenant RLS predicate exactly. Returns no row for a nonexistent slug, a non-member, or a customer_user-layer member alike -- the caller must not be able to distinguish these cases (no tenant-enumeration signal), the same posture app.resolve_tenant_by_domain already established.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.resolve_tenant_by_slug_for_actor with an identical grant set, never a
-- reimplementation. See RGL-BLK-002-OPTION2-REMEDIATION.md.
create function public.resolve_tenant_by_slug_for_actor(p_slug text, p_actor_auth_user_id uuid)
returns table(id uuid, slug text, canonical_status text)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.resolve_tenant_by_slug_for_actor(p_slug, p_actor_auth_user_id);
$wrap$;

comment on function public.resolve_tenant_by_slug_for_actor(text, uuid) is
  'CG-AUDIT-2026-09-02 Ø1 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.resolve_tenant_by_slug_for_actor with an identical grant set, never a reimplementation.';

revoke execute on function app.resolve_tenant_by_slug_for_actor(text, uuid) from public;
grant execute on function app.resolve_tenant_by_slug_for_actor(text, uuid) to service_role;
grant execute on function app.resolve_tenant_by_slug_for_actor(text, uuid) to authenticated;

revoke execute on function public.resolve_tenant_by_slug_for_actor(text, uuid) from anon, authenticated, service_role, public;
grant execute on function public.resolve_tenant_by_slug_for_actor(text, uuid) to service_role;
grant execute on function public.resolve_tenant_by_slug_for_actor(text, uuid) to authenticated;
