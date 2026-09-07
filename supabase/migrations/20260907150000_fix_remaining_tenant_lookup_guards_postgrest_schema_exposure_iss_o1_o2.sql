-- CG-AUDIT-2026-09-02 Ø1 remediation (remaining tenant-lookup guards) + Ø2 (customer
-- portal RLS lockout), closed together since they share one root cause and one fix.
--
-- Ø1: three more `findTenantBySlug` call sites still run `supabase.from("tenants")...`
-- against a schema (`app`) PostgREST never exposes, exactly the defect
-- 20260906090000 already fixed for `lib/portal/tenant-admin-guard-deps.server.ts`:
--   - lib/portal/customer-ticket-guard-deps.server.ts (customer support-ticket portal
--     entry -- admits ONLY customer_user, HRT-287)
--   - lib/portal/customer-portal-guard-deps.server.ts (the customer portal's own front
--     door, CPL-300 -- admits ONLY customer_user)
--   - lib/auth/register-login-session-deps.server.ts (post-sign-in session tracking,
--     ISS-2026-264 -- fires from the one shared app/(public)/login/ route for EVERY
--     layer, tenant-admin and customer_user alike)
--
-- Ø2: `app.resolve_tenant_by_slug_for_actor` (20260906090000's own fix) cannot be
-- reused for any of the three call sites above -- it deliberately mirrors app.tenants'
-- own `tenants_select_own_tenant` RLS policy, `has_active_tenant_membership(id) AND NOT
-- actor_holds_customer_user_layer(id)`, which is exactly right for the tenant-ADMIN
-- guard it was built for but is the audit's own independently-confirmed Ø2 lockout for
-- every one of these three: two guards admit ONLY customer_user (the AND NOT clause is
-- false for every real caller, always, by construction -- the exact Ø2 mechanism, just
-- reached through this RPC instead of a raw table read), and the login-session tracker
-- needs BOTH layers.
--
-- Fix: one new resolver, app.resolve_tenant_by_slug_for_member, identical to app.
-- resolve_tenant_by_slug_for_actor except it omits the customer-layer exclusion --
-- 20260730560000's own migration proved, in a disposable database, that a customer_user
-- principal already satisfies has_active_tenant_membership (it is the tenant-ADMIN
-- guard's own additional "AND NOT actor_holds_customer_user_layer" line that excludes
-- them, not has_active_tenant_membership itself), so admitting "any active member,
-- either layer" is exactly has_active_tenant_membership alone. Being SECURITY DEFINER,
-- it resolves app.tenants itself rather than through PostgREST's own RLS-bound
-- authenticated role, so app.tenants' own tenants_select_own_tenant policy (Ø2's own
-- root cause for a direct table read) never applies to it -- the same mechanism
-- 20260906090000's own resolver already relies on for the tenant-admin case.
--
-- Per the standing convention (this Supabase project's own platform bootstrap carries
-- `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON
-- FUNCTIONS TO anon, authenticated, service_role`), the public wrapper below explicitly
-- revokes from `anon, authenticated, service_role, public` before granting back exactly
-- the roles this function needs -- mirroring 20260906090000 exactly.

create function app.resolve_tenant_by_slug_for_member(p_slug text, p_actor_auth_user_id uuid)
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
  then
    return;
  end if;

  return query select v_tenant.id, v_tenant.slug, v_tenant.canonical_status;
end;
$function$;

comment on function app.resolve_tenant_by_slug_for_member(text, uuid) is
  'CG-AUDIT-2026-09-02 Ø1+Ø2: resolves a tenant by slug for any actor holding an active membership in it, REGARDLESS of principal layer -- unlike app.resolve_tenant_by_slug_for_actor (tenant-admin guard only, deliberately excludes customer_user), this one admits customer_user too, since app.has_active_tenant_membership alone is already layer-agnostic (20260730560000 proved a customer_user principal satisfies it). Used by lib/portal/customer-ticket-guard-deps.server.ts and lib/portal/customer-portal-guard-deps.server.ts (both admit ONLY customer_user downstream, via their own actor_holds_customer_user_layer check) and lib/auth/register-login-session-deps.server.ts (fires for every layer from the one shared login route). Returns no row for a nonexistent slug or a non-member alike -- no tenant-enumeration signal, the same posture app.resolve_tenant_by_slug_for_actor/app.resolve_tenant_by_domain already established.';

-- Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer
-- pass-through to app.resolve_tenant_by_slug_for_member with an identical grant set,
-- never a reimplementation. See RGL-BLK-002-OPTION2-REMEDIATION.md.
create function public.resolve_tenant_by_slug_for_member(p_slug text, p_actor_auth_user_id uuid)
returns table(id uuid, slug text, canonical_status text)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.resolve_tenant_by_slug_for_member(p_slug, p_actor_auth_user_id);
$wrap$;

comment on function public.resolve_tenant_by_slug_for_member(text, uuid) is
  'CG-AUDIT-2026-09-02 Ø1+Ø2 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.resolve_tenant_by_slug_for_member with an identical grant set, never a reimplementation.';

revoke execute on function app.resolve_tenant_by_slug_for_member(text, uuid) from public;
grant execute on function app.resolve_tenant_by_slug_for_member(text, uuid) to service_role;
grant execute on function app.resolve_tenant_by_slug_for_member(text, uuid) to authenticated;

revoke execute on function public.resolve_tenant_by_slug_for_member(text, uuid) from anon, authenticated, service_role, public;
grant execute on function public.resolve_tenant_by_slug_for_member(text, uuid) to service_role;
grant execute on function public.resolve_tenant_by_slug_for_member(text, uuid) to authenticated;
