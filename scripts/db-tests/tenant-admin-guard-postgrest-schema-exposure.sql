-- CG-AUDIT-2026-09-02 Ø1 remediation, tenant-admin-guard scope. Real, executable evidence
-- for `app.resolve_tenant_by_slug_for_actor` and its `public.*` Option-2 wrapper
-- (20260906090000), the replacement for `lib/portal/tenant-admin-guard-deps.server.ts`'s
-- former `supabase.from("tenants")...` lookup, which targeted schema `app` -- a schema
-- never exposed to PostgREST (see supabase/config.toml's `schemas = ["public",
-- "graphql_public"]`) and so could never actually resolve over a real Supabase connection.
--
-- Asserts: (1) a genuine active tenant_admin member resolves the tenant; (2) a nonexistent
-- slug and (3) a non-member both return zero rows, indistinguishably, preserving the guard's
-- documented anti-tenant-enumeration contract; (4) a customer_user-layer member is excluded,
-- mirroring `app.tenants`'s own `tenants_select_own_tenant` RLS predicate exactly (see
-- 20260730560000); (5) a session may not resolve on behalf of another identity
-- (`app.assert_actor_is_session_identity`); (6) the real session identity succeeds through
-- the `public.*` wrapper exactly as `lib/portal/tenant-admin-guard-deps.server.ts` calls it;
-- (7) `anon` retains no EXECUTE grant on the public wrapper, per the standing convention
-- `20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql` established (a new
-- `public.*` wrapper must explicitly revoke from `anon, authenticated, service_role, public`
-- before granting back exactly the roles needed -- revoking from PUBLIC alone leaves this
-- Supabase project's own platform-level default-privilege grant to `anon` in place).

\set ON_ERROR_STOP on

\echo '>> setup: an active tenant with a tenant_admin member, a customer_user-layer member, and an unrelated stranger'
do $$
declare
  v_tenant uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000099701', 'tadmin-resolvfix@example.test'),
    ('00000000-0000-0000-0000-000000099702', 'custlayer-resolvfix@example.test'),
    ('00000000-0000-0000-0000-000000099703', 'stranger-resolvfix@example.test');

  perform app.provision_tenant('resolvfix', 'ResolveFix Co', 'idem-resolvfix', 'tester');
  v_tenant := (select id from app.tenants where slug = 'resolvfix');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000099701', 'tadmin-resolvfix@example.test', 'T Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tadmin-resolvfix@example.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant, '00000000-0000-0000-0000-000000099702', 'custlayer-resolvfix@example.test', 'Cust Layer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'custlayer-resolvfix@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000099702', 'customer_user', v_tenant, 'CUST-RESOLVFIX-0001', 'tester');
end;
$$;

\echo '>> case 1: a genuine active tenant_admin member resolves the tenant'
do $$
declare v_row record;
begin
  select * into v_row from app.resolve_tenant_by_slug_for_actor('resolvfix', '00000000-0000-0000-0000-000000099701');
  if v_row.id is null or v_row.slug <> 'resolvfix' or v_row.canonical_status <> 'active' then
    raise exception 'assertion failed: expected the tenant_admin to resolve resolvfix as active, got %', v_row;
  end if;
end;
$$;

\echo '>> case 2: a nonexistent slug returns zero rows'
do $$
declare v_count integer;
begin
  select count(*) into v_count from app.resolve_tenant_by_slug_for_actor('resolvfix-does-not-exist', '00000000-0000-0000-0000-000000099701');
  if v_count <> 0 then
    raise exception 'assertion failed: expected 0 rows for a nonexistent slug, got %', v_count;
  end if;
end;
$$;

\echo '>> case 3: a non-member resolving a real slug returns zero rows -- indistinguishable from case 2, no tenant-enumeration signal'
do $$
declare v_count integer;
begin
  select count(*) into v_count from app.resolve_tenant_by_slug_for_actor('resolvfix', '00000000-0000-0000-0000-000000099703');
  if v_count <> 0 then
    raise exception 'assertion failed: expected 0 rows for a non-member, got %', v_count;
  end if;
end;
$$;

\echo '>> case 4: a customer_user-layer member is excluded, mirroring tenants_select_own_tenant RLS'
do $$
declare v_count integer;
begin
  select count(*) into v_count from app.resolve_tenant_by_slug_for_actor('resolvfix', '00000000-0000-0000-0000-000000099702');
  if v_count <> 0 then
    raise exception 'assertion failed: expected 0 rows for a customer_user-layer member, got %', v_count;
  end if;
end;
$$;

\echo '>> case 5: an authenticated session may not resolve a tenant on behalf of another identity'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000099703", "role": "authenticated"}';
  begin
    perform * from public.resolve_tenant_by_slug_for_actor('resolvfix', '00000000-0000-0000-0000-000000099701');
    raise exception 'assertion failed: expected actor_identity_mismatch to be raised';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then
        raise exception 'assertion failed: expected actor_identity_mismatch, got: %', sqlerrm;
      end if;
  end;
  reset role;
end;
$$;

\echo '>> case 6: the real session identity resolves correctly through the public.* wrapper, the exact path the app calls'
do $$
declare v_row record;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000099701", "role": "authenticated"}';
  select * into v_row from public.resolve_tenant_by_slug_for_actor('resolvfix', '00000000-0000-0000-0000-000000099701');
  reset role;
  if v_row.id is null or v_row.slug <> 'resolvfix' then
    raise exception 'assertion failed: expected the tenant_admin to resolve resolvfix via the public wrapper, got %', v_row;
  end if;
end;
$$;

\echo '>> case 7: anon has no execute grant on the public wrapper (platform default-privilege leak, closed per 20260826010000''s standing convention)'
do $$
begin
  set local role anon;
  begin
    perform * from public.resolve_tenant_by_slug_for_actor('resolvfix', '00000000-0000-0000-0000-000000099701');
    raise exception 'assertion failed: anon must not be able to call public.resolve_tenant_by_slug_for_actor';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

\echo 'ALL tenant-admin-guard-postgrest-schema-exposure db-test assertions passed.'
