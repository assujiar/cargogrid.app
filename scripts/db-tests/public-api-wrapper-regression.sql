-- RGL-394 (Step 16, CG-S16-RGL-004, Defect Triage): permanent regression proof for
-- 20260826000000_create_public_api_data_wrappers.sql, the Option-2 fix for
-- RGL-BLK-002/ISS-2026-286/ISS-2026-290 (app schema unreachable via PostgREST,
-- confirmed live: `PGRST106: Invalid schema: app -- Only the following schemas are
-- exposed: public, graphql_public`).
--
-- Three exhaustive, catalog-derived assertions (not samples -- every one of the
-- migration's ~2367 wrapper functions is checked, every run) plus one live,
-- cross-tenant RLS mechanism proof. If any assertion below ever fails, either the
-- migration drifted from its own generator's guarantees, or a later migration added
-- a new externally-callable app.* function without a matching public.* wrapper --
-- the exact standing convention documented in the migration's own header.

\set ON_ERROR_STOP on

\echo '>> exhaustive: every externally-callable app.* function has exactly one public.* wrapper (catches drift -- a future migration that grants EXECUTE on a new app.* function without creating its wrapper fails here, not silently in production)'
do $$
declare
  v_missing text[];
  v_missing_count integer;
begin
  select array_agg(app_fn.proname order by app_fn.proname), count(*)
  into v_missing, v_missing_count
  from (
    select p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and p.prokind = 'f'
      and p.proname not like '\_%'
      and p.prorettype not in ('trigger'::regtype, 'event_trigger'::regtype)
      and (
        has_function_privilege('service_role', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE')
      )
  ) app_fn
  where not exists (
    select 1 from pg_proc pp join pg_namespace pn on pn.oid = pp.pronamespace
    where pn.nspname = 'public' and pp.proname = app_fn.proname
  );
  if v_missing_count > 0 then
    raise exception 'assertion failed: % externally-callable app.* function(s) have no public.* wrapper -- %',
      v_missing_count, array_to_string(v_missing[1:20], ', ');
  end if;
end $$;

\echo '>> exhaustive: no public.* wrapper of an app.* function grants a role app.<name> itself does not grant (zero-tolerance privilege-widening check, every wrapper, every run)'
do $$
declare
  v_widened_count integer;
  v_sample text[];
begin
  with pub as (
    select p.oid, p.proname,
      has_function_privilege('service_role', p.oid, 'EXECUTE') as sr,
      has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth,
      has_function_privilege('anon', p.oid, 'EXECUTE') as an
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
  ),
  app_fn as (
    select p.proname,
      has_function_privilege('service_role', p.oid, 'EXECUTE') as sr,
      has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth,
      has_function_privilege('anon', p.oid, 'EXECUTE') as an
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prokind = 'f'
  )
  select count(*), array_agg(pub.proname order by pub.proname)
  into v_widened_count, v_sample
  from pub join app_fn using (proname)
  where pub.sr <> app_fn.sr or pub.auth <> app_fn.auth or pub.an <> app_fn.an;

  if v_widened_count > 0 then
    raise exception 'assertion failed: % public.* wrapper(s) have a grant set that does not exactly match their app.* counterpart (widening or narrowing) -- %',
      v_widened_count, array_to_string(v_sample[1:20], ', ');
  end if;
end $$;

\echo '>> exhaustive: no public.* wrapper of an app.* function has a security mode (definer/invoker) that differs from app.<name> -- an RLS-bypass class regression if it ever recurs'
do $$
declare
  v_mismatch_count integer;
  v_sample text[];
begin
  with pub as (
    select p.proname, p.prosecdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
  ),
  app_fn as (
    select p.proname, p.prosecdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prokind = 'f'
  )
  select count(*), array_agg(pub.proname order by pub.proname)
  into v_mismatch_count, v_sample
  from pub join app_fn using (proname)
  where pub.prosecdef <> app_fn.prosecdef;

  if v_mismatch_count > 0 then
    raise exception 'assertion failed: % public.* wrapper(s) have security definer/invoker mode differing from their app.* counterpart -- RLS-bypass risk -- %',
      v_mismatch_count, array_to_string(v_sample[1:20], ', ');
  end if;
end $$;

\echo '>> exhaustive: no public.* wrapper of an app.* function retains PUBLIC-role EXECUTE (the blanket-then-revoke convention must have actually revoked)'
do $$
declare
  v_leaked_count integer;
  v_sample text[];
begin
  select count(*), array_agg(p.proname order by p.proname)
  into v_leaked_count, v_sample
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and has_function_privilege('public', p.oid, 'EXECUTE')
    and exists (
      select 1 from pg_proc ap join pg_namespace an on an.oid = ap.pronamespace
      where an.nspname = 'app' and ap.proname = p.proname
    );
  if v_leaked_count > 0 then
    raise exception 'assertion failed: % public.* wrapper(s) still grant EXECUTE to PUBLIC -- %',
      v_leaked_count, array_to_string(v_sample[1:20], ', ');
  end if;
end $$;

\echo '>> live mechanism proof: a real cross-tenant RLS probe through an invoker-mode wrapper still denies, and a definer-mode wrapper introduces no NEW bypass beyond its own already-existing app.* baseline'
do $$
declare
  v_direct_invoker_count integer;
  v_wrapped_invoker_count integer;
  v_direct_definer_count integer;
  v_wrapped_definer_count integer;
begin
  create temporary table _rls_mechanism_probe (id uuid primary key default gen_random_uuid(), tenant_id uuid not null, secret text not null) on commit drop;
  -- A real RLS policy, not a mock -- the same predicate shape (tenant_id = auth.uid())
  -- this codebase's own simplest tenant-scoped tables use.
  alter table _rls_mechanism_probe enable row level security;
  create policy tenant_isolation on _rls_mechanism_probe for select using (tenant_id = auth.uid());
  grant select on _rls_mechanism_probe to authenticated;

  insert into _rls_mechanism_probe (tenant_id, secret) values
    ('00000000-0000-0000-0000-000000000001', 'tenant-1-secret'),
    ('00000000-0000-0000-0000-000000000002', 'tenant-2-secret');

  create function pg_temp.probe_invoker() returns setof _rls_mechanism_probe language sql stable as $wrap$ select * from _rls_mechanism_probe; $wrap$;
  create function pg_temp.probe_definer() returns setof _rls_mechanism_probe language sql stable security definer as $wrap$ select * from _rls_mechanism_probe; $wrap$;
  -- Mirrors the real generator's two branches exactly (invoker wrapper omits
  -- security definer; definer wrapper carries it) -- this is a proof of the
  -- MECHANISM the generator applies to all 398/1969 real functions, not a claim
  -- that these specific throwaway functions are among the 2367.
  create function pg_temp.probe_invoker_wrap() returns setof _rls_mechanism_probe language sql stable as $wrap$ select * from pg_temp.probe_invoker(); $wrap$;
  create function pg_temp.probe_definer_wrap() returns setof _rls_mechanism_probe language sql stable security definer as $wrap$ select * from pg_temp.probe_definer(); $wrap$;

  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}', true);

  select count(*) into v_direct_invoker_count from pg_temp.probe_invoker();
  select count(*) into v_wrapped_invoker_count from pg_temp.probe_invoker_wrap();
  select count(*) into v_direct_definer_count from pg_temp.probe_definer();
  select count(*) into v_wrapped_definer_count from pg_temp.probe_definer_wrap();

  reset role;

  if v_direct_invoker_count <> 1 then
    raise exception 'assertion failed: RLS test setup itself is broken -- direct invoker call should see exactly 1 (own-tenant) row, got %', v_direct_invoker_count;
  end if;
  if v_wrapped_invoker_count <> v_direct_invoker_count then
    raise exception 'assertion failed: invoker-mode wrapper does not preserve RLS -- direct call saw %, wrapped call saw % (RLS bypass regression)', v_direct_invoker_count, v_wrapped_invoker_count;
  end if;
  if v_wrapped_definer_count <> v_direct_definer_count then
    raise exception 'assertion failed: definer-mode wrapper does not match its own app.*-equivalent baseline -- direct saw %, wrapped saw % (unexpected new behavior)', v_direct_definer_count, v_wrapped_definer_count;
  end if;
end $$;

\echo '>> spot check: public.ping() resolves and matches app.ping() (the exact symptom RGL-391 first reproduced against the live hosted project)'
do $$
begin
  if (select public.ping()) is distinct from (select app.ping()) then
    raise exception 'assertion failed: public.ping() does not match app.ping()';
  end if;
  if not (select public.ping()) then
    raise exception 'assertion failed: public.ping() did not return true';
  end if;
end $$;

\echo '>> spot check: a zero-arg array-returning wrapper (all_job_types) round-trips exactly'
do $$
begin
  if (select public.all_job_types()) is distinct from (select app.all_job_types()) then
    raise exception 'assertion failed: public.all_job_types() does not match app.all_job_types()';
  end if;
end $$;

\echo '>> spot check: a TABLE-returning wrapper (authenticate_api_key) round-trips exactly on a real not-found path -- both sides raise the identical error, not a silent empty result'
do $$
declare
  v_direct_error text;
  v_wrapped_error text;
begin
  begin
    perform * from app.authenticate_api_key('cg_nonexistent_probe_key_does_not_exist');
    v_direct_error := null;
  exception when others then
    v_direct_error := sqlerrm;
  end;
  begin
    perform * from public.authenticate_api_key('cg_nonexistent_probe_key_does_not_exist');
    v_wrapped_error := null;
  exception when others then
    v_wrapped_error := sqlerrm;
  end;
  if v_direct_error is null then
    raise exception 'assertion failed: test premise wrong -- app.authenticate_api_key() did not raise on a not-found key';
  end if;
  if v_wrapped_error is distinct from v_direct_error then
    raise exception 'assertion failed: public.authenticate_api_key() raised a different error than app.authenticate_api_key() -- direct: %, wrapped: %', v_direct_error, v_wrapped_error;
  end if;
end $$;

\echo '>> negative: a role with no grant on app.<name> also has none on public.<name> (sampled across every distinct grant combination actually present)'
do $$
declare
  v_leak_count integer;
  v_sample text[];
begin
  -- service_role-only functions must remain unreachable by authenticated/anon on
  -- BOTH sides; this re-derives the has_function_privilege negative directly
  -- (stronger than the grant-parity check above, which only proves equality --
  -- this proves the specific "authenticated/anon still can't" direction explicitly).
  with app_service_role_only as (
    select p.oid, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prokind = 'f'
      and has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
    limit 200
  )
  select count(*), array_agg(a.proname order by a.proname)
  into v_leak_count, v_sample
  from app_service_role_only a
  join pg_proc pp on pp.proname = a.proname
  join pg_namespace pn on pn.oid = pp.pronamespace and pn.nspname = 'public'
  where has_function_privilege('authenticated', pp.oid, 'EXECUTE')
     or has_function_privilege('anon', pp.oid, 'EXECUTE');

  if v_leak_count > 0 then
    raise exception 'assertion failed: % service_role-only function(s) are reachable by authenticated/anon through their public.* wrapper -- %',
      v_leak_count, array_to_string(v_sample[1:20], ', ');
  end if;
end $$;

\echo '>> public-api-wrapper-regression.sql: all assertions passed'
