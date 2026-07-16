-- Real, executable test evidence for PLT-105 (Tenant Provisioning and Lifecycle,
-- CG-S6-PLT-002) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database (never a shared/production database; see scripts/db-tests/run.sh).
--
-- Each assertion is a standalone DO block (autocommit statement) that RAISEs on
-- failure -- a failing assertion aborts the whole psql run with a nonzero exit code
-- and a readable message, exactly like a node:test assertion failure.

\set ON_ERROR_STOP on

\echo '>> idempotent provisioning: same idempotency_key never creates a second row'
do $$
declare
  v_first app.tenants;
  v_second app.tenants;
  v_count integer;
begin
  select * into v_first from app.provision_tenant('acme', 'Acme Corp', 'idem-acme-1', 'tester');
  if v_first.canonical_status <> 'provisioning' then
    raise exception 'assertion failed: expected canonical_status=provisioning, got %', v_first.canonical_status;
  end if;

  -- Same idempotency key, deliberately different slug/name -- must be ignored.
  select * into v_second from app.provision_tenant('different-slug', 'Different Name', 'idem-acme-1', 'tester');
  if v_second.id <> v_first.id or v_second.slug <> 'acme' then
    raise exception 'assertion failed: retry with same idempotency_key must return the original row unchanged, got id=% slug=%', v_second.id, v_second.slug;
  end if;

  select count(*) into v_count from app.tenants where idempotency_key = 'idem-acme-1';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row for idempotency_key=idem-acme-1, found %', v_count;
  end if;

  select count(*) into v_count from app.tenant_status_history where tenant_id = v_first.id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 history row after 2 provision calls (the retry must not append a duplicate), found %', v_count;
  end if;
end;
$$;

\echo '>> duplicate slug with a different idempotency_key is rejected'
do $$
begin
  begin
    perform app.provision_tenant('acme', 'Acme Impostor', 'idem-acme-2', 'tester');
    raise exception 'assertion failed: expected a unique_violation for duplicate slug, but provisioning succeeded';
  exception
    when unique_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> canonical lifecycle: provisioning -> active -> suspended -> active -> terminated'
do $$
declare
  v_tenant app.tenants;
begin
  select id into v_tenant from app.tenants where slug = 'acme';

  select * into v_tenant from app.transition_tenant_status(v_tenant.id, 'active', 'bootstrap complete', 'tester');
  if v_tenant.canonical_status <> 'active' or v_tenant.activated_at is null then
    raise exception 'assertion failed: expected active status with activated_at set, got status=% activated_at=%', v_tenant.canonical_status, v_tenant.activated_at;
  end if;
  if v_tenant.record_version <> 2 then
    raise exception 'assertion failed: expected record_version=2 after one transition, got %', v_tenant.record_version;
  end if;

  select * into v_tenant from app.transition_tenant_status(v_tenant.id, 'suspended', 'billing hold', 'tester');
  if v_tenant.canonical_status <> 'suspended' or v_tenant.deactivated_at is null then
    raise exception 'assertion failed: expected suspended status with deactivated_at set, got status=% deactivated_at=%', v_tenant.canonical_status, v_tenant.deactivated_at;
  end if;

  select * into v_tenant from app.transition_tenant_status(v_tenant.id, 'active', 'billing resolved', 'tester');
  if v_tenant.canonical_status <> 'active' then
    raise exception 'assertion failed: expected reactivation to active, got %', v_tenant.canonical_status;
  end if;

  select * into v_tenant from app.transition_tenant_status(v_tenant.id, 'terminated', 'customer offboarded', 'tester');
  if v_tenant.canonical_status <> 'terminated' or v_tenant.terminated_at is null then
    raise exception 'assertion failed: expected terminated status with terminated_at set, got status=% terminated_at=%', v_tenant.canonical_status, v_tenant.terminated_at;
  end if;

  perform 1 from app.tenant_status_history where tenant_id = v_tenant.id and to_status = 'terminated' and from_status = 'active';
  if not found then
    raise exception 'assertion failed: expected a history row recording active -> terminated';
  end if;
end;
$$;

\echo '>> terminated is a true terminal state -- no further transition is ever allowed'
do $$
declare
  v_tenant_id uuid;
begin
  select id into v_tenant_id from app.tenants where slug = 'acme';
  begin
    perform app.transition_tenant_status(v_tenant_id, 'active', 'attempted revival', 'tester');
    raise exception 'assertion failed: expected transitioning out of terminated to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> an invalid (non-adjacent) transition is rejected, e.g. active -> provisioning'
do $$
declare
  v_tenant app.tenants;
begin
  select * into v_tenant from app.provision_tenant('globex', 'Globex Inc', 'idem-globex-1', 'tester');
  perform app.transition_tenant_status(v_tenant.id, 'active', 'bootstrap complete', 'tester');
  begin
    perform app.transition_tenant_status(v_tenant.id, 'provisioning', 'nonsense rollback', 'tester');
    raise exception 'assertion failed: expected active -> provisioning to be rejected, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> a legal hold blocks termination until explicitly cleared'
do $$
declare
  v_tenant app.tenants;
begin
  select * into v_tenant from app.provision_tenant('initech', 'Initech LLC', 'idem-initech-1', 'tester');
  perform app.transition_tenant_status(v_tenant.id, 'active', 'bootstrap complete', 'tester');
  update app.tenants set legal_hold = true where id = v_tenant.id;

  begin
    perform app.transition_tenant_status(v_tenant.id, 'terminated', 'attempted termination under hold', 'tester');
    raise exception 'assertion failed: expected termination under an active legal hold to be rejected, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;

  update app.tenants set legal_hold = false where id = v_tenant.id;
  perform app.transition_tenant_status(v_tenant.id, 'terminated', 'hold cleared, termination proceeds', 'tester');

  perform 1 from app.tenants where id = v_tenant.id and canonical_status = 'terminated';
  if not found then
    raise exception 'assertion failed: expected termination to succeed once the legal hold was cleared';
  end if;
end;
$$;

\echo '>> transitioning a non-existent tenant fails cleanly, not silently'
do $$
begin
  begin
    perform app.transition_tenant_status('00000000-0000-0000-0000-000000000000'::uuid, 'active', 'n/a', 'tester');
    raise exception 'assertion failed: expected tenant_not_found for a non-existent tenant id, but it succeeded';
  exception
    when no_data_found then
      null; -- expected
  end;
end;
$$;

\echo '>> defense in depth: anon and authenticated are denied at the schema-privilege layer (never even reach RLS); service_role has explicit access and sees every row'
do $$
declare
  v_count integer;
begin
  set local role anon;
  begin
    select count(*) into v_count from app.tenants;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer (no USAGE grant on app for this table), but the query succeeded with count=%', v_count;
  exception
    when insufficient_privilege then
      null; -- expected: no USAGE grant on schema app for anon
  end;
  reset role;
end;
$$;

-- Updated at PLT-113 (RLS Tenant Policy Foundation): `authenticated` now has a real,
-- narrow SELECT grant + RLS policy on app.tenants (docs/build-log/phase-01/PLT-113.md).
-- With no `request.jwt.claims` set in this ad-hoc role switch, auth.uid() resolves to
-- null, so app.has_active_tenant_membership() is false for every row -- the query now
-- succeeds (no more insufficient_privilege) but correctly returns zero rows, RLS itself
-- doing the denial rather than the schema-privilege layer. This is a real security
-- improvement this checkpoint's own migration introduces, not a weakened assertion --
-- see scripts/db-tests/rls-tenant-policy.sql for the full authenticated-session coverage
-- (tenant isolation, Supreme Admin cross-tenant visibility, zero-membership denial).
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  select count(*) into v_count from app.tenants;
  if v_count <> 0 then
    raise exception 'assertion failed: authenticated with no JWT claims set must see zero tenants via RLS (not an error, just an empty result), saw %', v_count;
  end if;
  reset role;
end;
$$;

do $$
declare
  v_count integer;
begin
  set local role service_role;
  select count(*) into v_count from app.tenants;
  if v_count < 3 then
    raise exception 'assertion failed: service_role has an explicit grant and must see every provisioned tenant (expected at least 3: acme, globex, initech), saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-105 db-test assertions passed.'
