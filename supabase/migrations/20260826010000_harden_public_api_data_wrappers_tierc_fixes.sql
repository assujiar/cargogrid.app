-- RGL-394 Tier C self-correction pass on the same checkpoint's own first-round
-- commit (20260826000000_create_public_api_data_wrappers.sql, 2367 public.*
-- wrapper functions). Two independent, live-forced defects found during the live
-- application of that migration, both closed here before the wrapper layer is
-- called VERIFIED -- never shipped broken, mirroring this repository's own
-- established self-correction discipline (HDN-374/375/377/386).
--
-- ===========================================================================
-- Finding 1, CRITICAL, live-forced: 140 of the 2367 wrapper functions were
-- generated with a hardcoded `security definer` despite their own app.<name>
-- counterpart being `security invoker` -- the exact RLS-bypass-by-wrapper defect
-- class 20260826000000's own header comment (lines 54-73) explicitly documents
-- as the reason `security definer`/`invoker` must be copied per-function, never
-- hardcoded. All 140 are concentrated in the Finance module (app.acknowledge_
-- finance_period_checklist_item, app.activate_finance_account, app.allocate_
-- finance_receipt, app.apply_finance_ap_settlement and 136 others of the same
-- shape) -- confirmed live-forced by direct pg_proc.prosecdef comparison against
-- every corresponding app.<name>, not a sample: a wrapper in this state runs as
-- its owner (`postgres`, which has BYPASSRLS) instead of the real calling role,
-- silently bypassing every RLS policy the underlying app.<name> function was
-- relying on for tenant isolation. This is a defect in the committed migration
-- file's own generated content (confirmed by direct inspection of
-- 20260826000000_create_public_api_data_wrappers.sql itself, which hardcodes
-- `security definer` for e.g. app.acknowledge_finance_period_checklist_item
-- despite that function itself being `security invoker`) -- not an artifact of
-- how it was applied. Per this repository's own "never edit an applied
-- migration" rule, the 140 wrapper definitions are corrected here via `ALTER
-- FUNCTION ... SECURITY INVOKER`, not by editing the original file. search_path
-- is untouched by this ALTER (it is not a security-mode property) and remains
-- `pg_catalog, pg_temp` for these wrappers exactly as the original migration set
-- it -- schema-qualified calls to app.<name> in the wrapper body resolve
-- regardless of search_path, so this ALTER is the complete fix.
--
-- ===========================================================================
-- Finding 2, CRITICAL, live-forced: this Supabase project's own platform-level
-- bootstrap carries `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
-- GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role` (standard
-- Supabase provisioning -- `public` is the platform's own default PostgREST API
-- schema, and this default exists so an ordinary `create function` in Supabase
-- Studio "just works" through the API without manual grants). Because migrations
-- apply as role `postgres`, every one of the 2367 `create function public.*`
-- statements in 20260826000000 silently picked up this default EXECUTE grant to
-- anon AND authenticated AT CREATION TIME, in addition to whatever that same
-- migration explicitly granted afterward. The migration's own per-function
-- `revoke execute on function public.<name>(...) from public` (its only grant
-- cleanup step) does NOT undo this -- revoking from the PUBLIC pseudo-role never
-- touches a role-specific grant a default-privilege rule already attached to
-- `anon`/`authenticated` by name. Net effect, live-forced: 2359 of 2367 wrapper
-- functions carried an EXECUTE grant to anon and/or authenticated that their own
-- app.<name> counterpart never had -- including app.ping() (service_role-only by
-- design, HDN-382) confirmed independently anon-CALLABLE end-to-end over the
-- real PostgREST endpoint before this fix, and reproducibly denied (401,
-- `permission denied for function ping`) after it. This is a live,
-- production-forced, unintended-authorization-widening regression across nearly
-- the entire wrapper surface, distinct from Finding 1 (a bypass of RLS from
-- within an authorized call) -- this one is un-intended AUTHORIZATION itself.
--
-- Root-cause fix (changing the schema-level default so future `create function
-- public.*` statements stop inheriting this grant) is NOT possible from a
-- migration: `alter default privileges for role postgres in schema public...`
-- was live-forced to fail with `42501: permission denied to change default
-- privileges` -- Supabase reserves this platform-level configuration to its own
-- internal provisioning role, deliberately unreachable by the `postgres` role
-- migrations run as. This is the correct, expected platform boundary, not a bug
-- to route around. Consequently: (a) every wrapper function's ACL is reset here
-- to exactly mirror its app.<name> counterpart's real, current grants (which
-- were never touched by this default-privilege behavior and remain the
-- trustworthy source of truth), and (b) the standing convention this migration
-- set established (20260826000000's own header, "any future migration that
-- grants EXECUTE on a new app.* function... must create its public.* wrapper in
-- that same migration") is hereby AMENDED: a new public.* wrapper function must
-- ALWAYS explicitly `revoke execute on function public.<name>(...) from anon,
-- authenticated, service_role, public` before granting back exactly the roles
-- app.<name> itself grants -- revoking from PUBLIC alone is insufficient in this
-- schema, unlike everywhere else in this codebase.
--
-- Both fixes below are idempotent (each loop only touches a function whose
-- current live state does not already match its app.<name> counterpart), so
-- re-running this migration is safe and a no-op once applied.
--
-- Exhaustively re-verified after both fixes, live, not by sample: grant-parity
-- mismatches 2367 -> 0, security-mode mismatches 140 -> 0, zero PUBLIC-role
-- leaks (already 0, unaffected), return-type/volatility/set-returning parity
-- (0 mismatches, confirming neither fix disturbed anything outside its own
-- scope), and the missing-wrapper exhaustive existence check (0, once the 32
-- genuine trigger-handler exclusions documented in 20260826000000's own header
-- are accounted for).

do $$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select pp.oid as pub_oid, ap.prosecdef as app_secdef, pp.proname,
           pg_get_function_identity_arguments(pp.oid) as args
    from pg_proc ap
    join pg_namespace an on an.oid = ap.pronamespace and an.nspname = 'app'
    join pg_proc pp on pp.proname = ap.proname
    join pg_namespace pn on pn.oid = pp.pronamespace and pn.nspname = 'public'
    where exists (
      select 1 from pg_description d
      where d.objoid = pp.oid and d.description like 'RGL-394 Option-2 wrapper%'
    )
    and pg_get_function_identity_arguments(ap.oid) = pg_get_function_identity_arguments(pp.oid)
    and ap.prosecdef is distinct from pp.prosecdef
  loop
    if r.app_secdef then
      execute format('alter function public.%I(%s) security definer', r.proname, r.args);
    else
      execute format('alter function public.%I(%s) security invoker', r.proname, r.args);
    end if;
    v_count := v_count + 1;
  end loop;

  raise notice 'RGL-394 Tier C fix 1: corrected security mode on % public.* wrapper function(s)', v_count;
end $$;

do $$
declare
  r record;
  v_anon boolean;
  v_authenticated boolean;
  v_service_role boolean;
  v_count integer := 0;
begin
  for r in
    select pp.oid as pub_oid, ap.oid as app_oid, pp.proname, pg_get_function_identity_arguments(pp.oid) as args
    from pg_proc ap
    join pg_namespace an on an.oid = ap.pronamespace and an.nspname = 'app'
    join pg_proc pp on pp.proname = ap.proname
    join pg_namespace pn on pn.oid = pp.pronamespace and pn.nspname = 'public'
    where exists (
      select 1 from pg_description d
      where d.objoid = pp.oid and d.description like 'RGL-394 Option-2 wrapper%'
    )
    and pg_get_function_identity_arguments(ap.oid) = pg_get_function_identity_arguments(pp.oid)
  loop
    v_anon := has_function_privilege('anon', r.app_oid, 'execute');
    v_authenticated := has_function_privilege('authenticated', r.app_oid, 'execute');
    v_service_role := has_function_privilege('service_role', r.app_oid, 'execute');

    if has_function_privilege('anon', r.pub_oid, 'execute') is distinct from v_anon
       or has_function_privilege('authenticated', r.pub_oid, 'execute') is distinct from v_authenticated
       or has_function_privilege('service_role', r.pub_oid, 'execute') is distinct from v_service_role
       or has_function_privilege('public', r.pub_oid, 'execute')
    then
      execute format('revoke execute on function public.%I(%s) from anon, authenticated, service_role, public', r.proname, r.args);

      if v_anon then
        execute format('grant execute on function public.%I(%s) to anon', r.proname, r.args);
      end if;
      if v_authenticated then
        execute format('grant execute on function public.%I(%s) to authenticated', r.proname, r.args);
      end if;
      if v_service_role then
        execute format('grant execute on function public.%I(%s) to service_role', r.proname, r.args);
      end if;

      v_count := v_count + 1;
    end if;
  end loop;

  raise notice 'RGL-394 Tier C fix 2: reset ACL (closed default-privilege grant leak) on % public.* wrapper function(s)', v_count;
end $$;
