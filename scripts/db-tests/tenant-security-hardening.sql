-- Real, executable evidence for PLT-138 (Tenant/Security/Platform Hardening,
-- CG-S6-PLT-035). Closes the single finding PLT-137's own integrated verification
-- recorded (docs/build-log/phase-01/PLT-137.md §5, item 1): app.resolve_access_context's
-- own migration comment described only the p_tenant_id-omitted branch. The root-cause
-- repair (20260722130000_harden_resolve_access_context_documentation.sql) is a purely
-- additive `comment on function` -- zero behavioral/schema/privilege change. This file
-- is this checkpoint's own regression evidence (Prompt 138 §28: "finding-specific
-- negative/regression" test), independent of PLT-137's own scenario 3 which first
-- found the underlying behavior.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a global Supreme Admin with no per-tenant identity link to either'
do $$
declare
  v_tenant_a uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000022001', 'tenantadminhard-a@example.test'),
    ('00000000-0000-0000-0000-000000022003', 'supremehard@example.test');

  perform app.provision_tenant('acmehard', 'Acme Hardening Co', 'idem-acmehard', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmehard');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000022001', 'tenantadminhard-a@example.test', 'Tenant Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminhard-a@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000022001', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000022003', 'supreme_admin', null, null, 'tester');
end;
$$;

\echo '>> regression evidence 1 (was PLT-137''s finding, re-confirmed as this checkpoint''s own independent evidence): a tenant-qualified app.resolve_access_context call for a global-only Supreme Admin fails closed with inactive_identity_link, not a silent resolution -- unchanged behavior, this repair never touched the function body'
do $$
begin
  begin
    perform app.resolve_access_context('00000000-0000-0000-0000-000000022003', (select id from app.tenants where slug = 'acmehard'));
    raise exception 'assertion failed: expected a Supreme Admin with no tenant_user_identities row for tenant A to fail closed on a tenant-qualified call';
  exception
    when no_data_found then
      null;
  end;

  -- The p_tenant_id-omitted branch is unaffected -- Supreme Admin still resolves directly.
  if (app.resolve_access_context('00000000-0000-0000-0000-000000022003')).layer <> 'supreme_admin' then
    raise exception 'assertion failed: expected Supreme Admin to still resolve correctly with p_tenant_id omitted after this checkpoint''s comment-only repair';
  end if;
end;
$$;

\echo '>> repair evidence 2 (before this checkpoint, this assertion would have failed -- no comment existed at all): app.resolve_access_context now carries a non-null, accurate function comment describing both branches'
do $$
declare
  v_comment text;
begin
  select obj_description('app.resolve_access_context(uuid, uuid, text)'::regprocedure) into v_comment;

  if v_comment is null then
    raise exception 'assertion failed: expected app.resolve_access_context to carry a non-null comment after PLT-138''s repair migration';
  end if;

  if v_comment not like '%p_tenant_id omitted%' or v_comment not like '%p_tenant_id supplied%' then
    raise exception 'assertion failed: expected the comment to explicitly describe both the omitted and supplied p_tenant_id branches, got: %', v_comment;
  end if;

  if v_comment not like '%no Supreme Admin shortcut%' then
    raise exception 'assertion failed: expected the comment to explicitly state the tenant-qualified branch has no Supreme Admin shortcut (the exact finding this repair closes), got: %', v_comment;
  end if;
end;
$$;

\echo '>> regression check: every other four-layer/RLS/RBAC control this repair could plausibly have touched is unaffected -- a tenant_admin still resolves correctly for their own tenant, and RLS on app.tenants still isolates'
do $$
declare
  v_ctx app.access_context;
  v_count integer;
begin
  v_ctx := app.resolve_access_context('00000000-0000-0000-0000-000000022001', (select id from app.tenants where slug = 'acmehard'));
  if v_ctx.layer <> 'tenant_admin' then
    raise exception 'assertion failed: expected tenant A''s admin to still resolve as tenant_admin after this checkpoint''s comment-only repair, got %', v_ctx.layer;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000022001", "role": "authenticated"}';
  select count(*) into v_count from app.tenants;
  if v_count <> 1 then
    raise exception 'assertion failed: expected tenant A''s admin to still see exactly 1 tenant via RLS, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> PLT-138 hardening: the single PLT-137 finding is closed, zero critical/high blocker existed, zero regression introduced'
