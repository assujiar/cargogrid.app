-- Real, executable test evidence for IAE-028 (IP Restriction and Network
-- Access, Prompt 356) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Scoped to this checkpoint's own additive
-- migration (supabase/migrations/20260807200000_create_intelligence_ip_restriction_network_access.sql).
-- Fresh, distinctive tenant fixture (iaeip), fixture id range
-- 00000000-0000-0000-0000-000032xxxxxx.

\set ON_ERROR_STOP on

\echo '>> setup: tenant iaeip with admin1 (tenant_admin + SEC:Configure/View/Approve), viewer1 (SEC:View only); a second tenant iaeip2 for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000032000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000032000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000032000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000032000003';
  v_admin1_role uuid;
  v_admin1_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_admin2_role uuid;
  v_admin2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iaeip.test'),
    (v_admin1, 'admin@iaeip.test'),
    (v_viewer1, 'viewer@iaeip.test'),
    (v_admin2, 'admin@iaeip2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaeip', 'IaeIp Co', 'idem-iaeip', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeip');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaeip2', 'IaeIp2 Co', 'idem-iaeip2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeip2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaeip.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeip.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaeip.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaeip.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaeip2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeip2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeIp Admin', 'SEC:Configure/View/Approve', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action in ('Configure', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_supreme, 'supreme');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeIp Viewer', 'SEC:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_supreme, 'supreme');

  v_admin2_role := (app.create_role(v_tenant2, 'IaeIp2 Admin', 'SEC:Configure/View/Approve -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action in ('Configure', 'View', 'Approve')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_supreme, 'supreme');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.get_or_create_ip_allowlist_policy: SEC:View-gated -- admin1/viewer1 succeed, a different tenant''s own admin (admin2) is rejected; app.set_ip_allowlist_enforcement_mode: default is disabled; the lockout guard rejects moving straight to enforced with zero active entries; viewer1 (SEC:View only) rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
  v_admin1 uuid := '00000000-0000-0000-0000-000032000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000032000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000032000003';
  v_policy app.ip_allowlist_policies;
begin
  begin
    perform app.get_or_create_ip_allowlist_policy(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 (a different tenant''s own admin) reading tenant1''s own IP allowlist policy, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_policy := app.get_or_create_ip_allowlist_policy(v_tenant1, v_admin1);
  if v_policy.enforcement_mode <> 'disabled' then
    raise exception 'assertion failed: expected default mode disabled, got %', v_policy.enforcement_mode;
  end if;
  v_policy := app.get_or_create_ip_allowlist_policy(v_tenant1, v_viewer1);
  if v_policy.enforcement_mode <> 'disabled' then
    raise exception 'assertion failed: expected the SAME idempotent default row for viewer1 (SEC:View), got %', v_policy.enforcement_mode;
  end if;

  begin
    perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'dry_run', v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (SEC:View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'enforced', v_admin1, 'admin1');
    raise exception 'assertion failed: expected ip_allowlist_no_active_entries (lockout guard, zero entries yet), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_policy := app.set_ip_allowlist_enforcement_mode(v_tenant1, 'dry_run', v_admin1, 'admin1');
  if v_policy.enforcement_mode <> 'dry_run' then
    raise exception 'assertion failed: expected dry_run, got %', v_policy.enforcement_mode;
  end if;
end;
$$;

\echo '>> app.add_ip_allowlist_entry: a malformed CIDR is rejected via ip_allowlist_invalid_cidr, never a raw Postgres type-cast crash; a well-formed IPv4 and a well-formed IPv6 CIDR both succeed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
  v_admin1 uuid := '00000000-0000-0000-0000-000032000001';
  v_entry app.ip_allowlist_entries;
begin
  begin
    perform app.add_ip_allowlist_entry(v_tenant1, 'not-a-cidr-at-all', 'bad', 'all', v_admin1, 'admin1');
    raise exception 'assertion failed: expected ip_allowlist_invalid_cidr, the call unexpectedly succeeded';
  exception when invalid_text_representation then
    null;
  end;

  v_entry := app.add_ip_allowlist_entry(v_tenant1, '203.0.113.0/24', 'office IPv4 range', 'all', v_admin1, 'admin1');
  if v_entry.cidr::text <> '203.0.113.0/24' then
    raise exception 'assertion failed: expected 203.0.113.0/24, got %', v_entry.cidr;
  end if;

  v_entry := app.add_ip_allowlist_entry(v_tenant1, '2001:db8::/32', 'office IPv6 range', 'admin', v_admin1, 'admin1');
  if v_entry.cidr::text <> '2001:db8::/32' then
    raise exception 'assertion failed: expected 2001:db8::/32, got %', v_entry.cidr;
  end if;
end;
$$;

\echo '>> app.assert_ip_allowed under dry_run: an in-range IP is allowed (no log noise beyond the allow itself is required, but we log it too for a complete evidence trail); an out-of-range IP is NEVER denied under dry_run -- it always returns successfully -- but IS logged as dry_run_would_deny'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
  v_before_count integer;
  v_after_count integer;
  v_last_decision text;
begin
  -- In-range: matches the 203.0.113.0/24 entry.
  perform app.assert_ip_allowed(v_tenant1, '203.0.113.42', 'all', 'test-caller-in-range');

  select count(*) into v_before_count from app.ip_access_evaluations where tenant_id = v_tenant1;

  -- Out-of-range under dry_run: must NOT raise.
  perform app.assert_ip_allowed(v_tenant1, '198.51.100.7', 'all', 'test-caller-out-of-range');

  select count(*) into v_after_count from app.ip_access_evaluations where tenant_id = v_tenant1;
  if v_after_count <> v_before_count + 1 then
    raise exception 'assertion failed: expected exactly one new evaluation row logged, got % -> %', v_before_count, v_after_count;
  end if;

  -- Filtered by the specific test IP, not "most recent by occurred_at" -- every
  -- statement inside one transaction shares the identical now() value, so two
  -- evaluation rows inserted in the same do-block can tie on occurred_at.
  select decision into v_last_decision from app.ip_access_evaluations where tenant_id = v_tenant1 and ip_address = '198.51.100.7';
  if v_last_decision <> 'dry_run_would_deny' then
    raise exception 'assertion failed: expected dry_run_would_deny, got %', v_last_decision;
  end if;
end;
$$;

\echo '>> app.assert_ip_allowed scope isolation: an entry scoped to admin does not authorize the ui/api scope and vice versa; app.set_ip_allowlist_enforcement_mode(''enforced'') now succeeds (real active entries exist); under enforced, an out-of-range IP is genuinely denied (ip_not_allowed) and an in-range one is genuinely allowed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
  v_admin1 uuid := '00000000-0000-0000-0000-000032000001';
begin
  -- The IPv6 entry above is scoped 'admin' only -- an 'api' scope check against the
  -- same address must NOT match it. Still under dry_run here, so this call never
  -- raises regardless of match; the real scope-isolation assertion is the logged
  -- evaluation row checked next.
  perform app.assert_ip_allowed(v_tenant1, '2001:db8::1', 'api', 'test-scope-mismatch');
  if not exists (
    select 1 from app.ip_access_evaluations
    where tenant_id = v_tenant1 and ip_address = '2001:db8::1' and scope = 'api' and decision = 'dry_run_would_deny'
  ) then
    raise exception 'assertion failed: expected a dry_run_would_deny evaluation for the admin-scoped entry checked against the api scope (scope isolation)';
  end if;

  perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'enforced', v_admin1, 'admin1');

  begin
    perform app.assert_ip_allowed(v_tenant1, '198.51.100.7', 'all', 'test-enforced-deny');
    raise exception 'assertion failed: expected ip_not_allowed under enforced mode for an out-of-range IP, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  -- In-range, enforced: succeeds with no exception.
  perform app.assert_ip_allowed(v_tenant1, '203.0.113.99', 'all', 'test-enforced-allow');
end;
$$;

\echo '>> app.assert_ip_allowed: a malformed IP address under enforced mode is denied, never a raw crash'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
begin
  begin
    perform app.assert_ip_allowed(v_tenant1, 'not-an-ip-address', 'all', 'test-malformed-ip');
    raise exception 'assertion failed: expected ip_not_allowed for a malformed IP under enforced mode, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> app.set_ip_allowlist_enforcement_mode(''disabled''): the real break-glass rollback path always works, no precondition; app.assert_ip_allowed becomes a true no-op again (zero new log rows)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
  v_admin1 uuid := '00000000-0000-0000-0000-000032000001';
  v_policy app.ip_allowlist_policies;
  v_before_count integer;
  v_after_count integer;
begin
  v_policy := app.set_ip_allowlist_enforcement_mode(v_tenant1, 'disabled', v_admin1, 'admin1');
  if v_policy.enforcement_mode <> 'disabled' then
    raise exception 'assertion failed: expected disabled, got %', v_policy.enforcement_mode;
  end if;

  select count(*) into v_before_count from app.ip_access_evaluations where tenant_id = v_tenant1;
  perform app.assert_ip_allowed(v_tenant1, '203.0.113.99', 'all', 'test-disabled-noop');
  perform app.assert_ip_allowed(v_tenant1, '10.0.0.1', 'all', 'test-disabled-noop-out-of-range-too');
  select count(*) into v_after_count from app.ip_access_evaluations where tenant_id = v_tenant1;
  if v_after_count <> v_before_count then
    raise exception 'assertion failed: expected zero new log rows while disabled, got % -> %', v_before_count, v_after_count;
  end if;
end;
$$;

\echo '>> app.revoke_ip_allowlist_entry: a revoked entry no longer matches; app.ip_allowlist_bypass_grants: self-approval forbidden at the CHECK level; a different SEC:Approve holder approves; app.has_active_ip_allowlist_bypass reflects the real, current state'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
  v_admin1 uuid := '00000000-0000-0000-0000-000032000001';
  v_supreme uuid := '00000000-0000-0000-0000-000032000000';
  v_entry_id uuid;
  v_grant app.ip_allowlist_bypass_grants;
begin
  select id into v_entry_id from app.ip_allowlist_entries where tenant_id = v_tenant1 and cidr = '203.0.113.0/24'::cidr;
  perform app.revoke_ip_allowlist_entry(v_entry_id, v_admin1, 'admin1');

  perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'enforced', v_admin1, 'admin1');
  begin
    perform app.assert_ip_allowed(v_tenant1, '203.0.113.99', 'all', 'test-revoked-entry-no-longer-matches');
    raise exception 'assertion failed: expected ip_not_allowed once the matching entry is revoked, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  if app.has_active_ip_allowlist_bypass(v_tenant1, v_admin1) then
    raise exception 'assertion failed: expected no active bypass yet';
  end if;

  v_grant := app.request_ip_allowlist_bypass(v_tenant1, v_admin1, 'locked out after revoking the office range', v_admin1, 'admin1');
  begin
    perform app.approve_ip_allowlist_bypass(v_grant.id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected ip_bypass_self_approval_forbidden, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  v_grant := app.approve_ip_allowlist_bypass(v_grant.id, v_supreme, 'supreme');
  if v_grant.status <> 'approved' then
    raise exception 'assertion failed: expected approved, got %', v_grant.status;
  end if;

  if not app.has_active_ip_allowlist_bypass(v_tenant1, v_admin1) then
    raise exception 'assertion failed: expected an active bypass now';
  end if;

  -- Reset back to disabled so this fixture's own final state does not leak into any
  -- later standalone re-run assumption.
  perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'disabled', v_admin1, 'admin1');
end;
$$;

\echo '>> cross-tenant isolation: admin2 (tenant iaeip2) cannot read/act on iaeip''s own allowlist entries/evaluations/bypass grants'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
  v_admin2 uuid := '00000000-0000-0000-0000-000032000003';
begin
  begin
    perform count(*) from app.list_ip_allowlist_entries_for_tenant(v_tenant1, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for admin2 listing tenant1''s own allowlist entries, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  begin
    perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'dry_run', v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 configuring tenant1''s own policy, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on every new table is denied at the raw-RLS level'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000032000001", "role": "authenticated"}';
  begin
    perform count(*) from app.ip_allowlist_policies;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.ip_allowlist_policies, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.ip_allowlist_entries;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.ip_allowlist_entries, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.ip_access_evaluations;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.ip_access_evaluations, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.ip_allowlist_bypass_grants;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.ip_allowlist_bypass_grants, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every new function'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'get_or_create_ip_allowlist_policy', 'set_ip_allowlist_enforcement_mode',
      'add_ip_allowlist_entry', 'revoke_ip_allowlist_entry', 'assert_ip_allowed',
      'request_ip_allowlist_bypass', 'approve_ip_allowlist_bypass', 'has_active_ip_allowlist_bypass',
      'list_ip_allowlist_entries_for_tenant', 'list_ip_access_evaluations_for_tenant', 'list_ip_allowlist_bypass_grants_for_tenant'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 11 functions, found %', v_anon_grant_count;
  end if;
end;
$$;

\echo '>> ISS-2026-307: a DENIED evaluation is durably recorded, where assert_ip_allowed loses its own row to the exception it raises'
do $$
declare
  v_t uuid := (select id from app.tenants where slug = 'iaeip');
  v_admin1 uuid := '00000000-0000-0000-0000-000032000001';
  v_before bigint;
  v_after_assert bigint;
  v_after_evaluate bigint;
  v_decision text;
  v_alerts bigint;
begin
  -- This block runs after the break-glass rollback assertion above, which deliberately leaves
  -- the policy `disabled` and its earlier entry revoked. Re-establish an enforcing policy with
  -- one allowlisted range, through the real RPCs, so what follows exercises genuine
  -- enforcement rather than a no-op.
  perform app.add_ip_allowlist_entry(v_t, '10.0.0.0/8', 'iss307 range', 'all', v_admin1, 'admin1');
  perform app.set_ip_allowlist_enforcement_mode(v_t, 'enforced', v_admin1, 'admin1');

  select count(*) into v_before from app.ip_access_evaluations where tenant_id = v_t and decision = 'denied';

  -- (1) The defect, asserted as a property rather than described in a comment: enforcement
  -- through assert_ip_allowed cannot leave a denial record behind, because the exception it
  -- raises to deny the caller rolls back the row it just wrote. Live-reproduced 2026-08-30.
  begin
    perform app.assert_ip_allowed(v_t, '203.0.113.9', 'admin', 'iss307-assert');
    raise exception 'assertion failed: assert_ip_allowed did not deny a non-allowlisted address';
  exception
    when insufficient_privilege then null;
  end;
  select count(*) into v_after_assert from app.ip_access_evaluations where tenant_id = v_t and decision = 'denied';
  if v_after_assert <> v_before then
    raise exception 'assertion failed: expected assert_ip_allowed''s denial row to be rolled back with its own exception (before=%, after=%) -- if this now persists, the residual documented in 20260830170000 has been closed and this assertion should be inverted, not deleted',
      v_before, v_after_assert;
  end if;

  -- (2) The fix: the evaluator returns the same decision and its row SURVIVES, because it
  -- never raises. This is the durable path a caller uses when the denial must be recorded.
  v_decision := app.evaluate_ip_access(v_t, '203.0.113.9', 'admin', 'iss307-evaluate');
  if v_decision <> 'denied' then
    raise exception 'assertion failed: expected decision denied, got %', v_decision;
  end if;
  select count(*) into v_after_evaluate from app.ip_access_evaluations where tenant_id = v_t and decision = 'denied';
  if v_after_evaluate <> v_before + 1 then
    raise exception 'assertion failed: expected exactly one durable denied row (before=%, after=%)', v_before, v_after_evaluate;
  end if;
  if not exists (
    select 1 from app.ip_access_evaluations
    where tenant_id = v_t and decision = 'denied' and subject_label = 'iss307-evaluate' and ip_address = '203.0.113.9'
  ) then
    raise exception 'assertion failed: the durable denied row does not carry the subject and address that were denied';
  end if;

  -- (3) ISS-2026-249's security-denial slice: a genuine denial now reaches the alerting
  -- system. Before this, every security denial produced zero incident.
  -- Exactly one, not "at least one": app.raise_observability_alert deduplicates on
  -- (tenant, source_type, signal_type) inside its route's window, so a host being probed
  -- repeatedly opens one incident and files the rest as duplicate_signal timeline events.
  -- The assert_ip_allowed denial above raised its own alert too, and lost it to the same
  -- rollback that lost its evaluation row -- so a count of 1 here also re-proves that.
  select count(*) into v_alerts from app.incidents
  where tenant_id = v_t and source_type = 'security' and signal_type = 'error';
  if v_alerts <> 1 then
    raise exception 'assertion failed: expected exactly one deduplicated security incident from the denied IP, found %', v_alerts;
  end if;

  -- (4) The decision logic did not drift: an allowlisted address still returns allowed, and
  -- assert_ip_allowed still permits it. Both functions must agree, since one composes the other.
  if app.evaluate_ip_access(v_t, '10.1.2.3', 'admin', 'iss307-allowed') <> 'allowed' then
    raise exception 'assertion failed: an allowlisted address was not allowed by the evaluator';
  end if;
  perform app.assert_ip_allowed(v_t, '10.1.2.3', 'admin', 'iss307-allowed-assert');

  -- (5) A malformed address is denied, not silently allowed and not an unclassified crash --
  -- the original function's own documented rule, preserved through the split.
  if app.evaluate_ip_access(v_t, 'not-an-ip', 'admin', 'iss307-malformed') <> 'denied' then
    raise exception 'assertion failed: a malformed address was not denied under enforced mode';
  end if;
end;
$$;


\echo '>> ISS-2026-302 completeness sweep: EVERY app.* function gating on SEC:Configure, FIN:Approve or HRS:Approve now takes p_client_ip and calls app.assert_ip_allowed -- this is the assertion that catches the next such function being added without the gate, which is how the gap opened in the first place'
do $$
declare
  v_missing text[];
  v_wired integer;
  v_wrapper_mismatch text[];
begin
  -- The three tuples ISS-2026-236 named. FIN:Approve is reached through the
  -- app.check_finance_*_authority helpers, which take the action as a parameter -- that is
  -- exactly why a naive count of literal evaluate_permission('FIN', 'Approve') calls returns
  -- zero and the entry's own figure of 61 was low.
  select array_agg(fn order by fn), count(*) filter (where wired) into v_missing, v_wired from (
    select n.nspname || '.' || p.proname as fn,
           (pg_get_functiondef(p.oid) like '%p_client_ip%'
            and pg_get_functiondef(p.oid) like '%assert_ip_allowed%') as wired
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.provolatile = 'v'
      and (pg_get_functiondef(p.oid) ~ '''SEC'',\s*''Configure'''
        or pg_get_functiondef(p.oid) ~ '''HRS'',\s*''Approve'''
        or pg_get_functiondef(p.oid) ~ 'check_finance_[a-z_]+_authority\(\s*''Approve''')
  ) s where not wired;

  -- app.create_and_post_finance_system_journal is the one deliberate exclusion: its front
  -- door admits FIN:Edit OR FIN:Approve, no request reaches it directly, and it exists to be
  -- composed by app.post_finance_subledger_batch / app.allocate_finance_receipt /
  -- app.post_finance_correction. Naming it here rather than filtering it out of the query
  -- above keeps the exclusion visible to the next reader instead of hiding it in a predicate.
  if coalesce(v_missing, array[]::text[]) <> array['app.create_and_post_finance_system_journal'] then
    raise exception 'assertion failed: expected exactly one deliberately-unwired function, got %', coalesce(v_missing, array[]::text[]);
  end if;

  if v_wired <> 0 then
    raise exception 'assertion failed: the missing-set query must only return unwired functions';
  end if;

  select count(*) into v_wired from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.provolatile = 'v'
    and pg_get_functiondef(p.oid) like '%p_client_ip%'
    and pg_get_functiondef(p.oid) like '%assert_ip_allowed%'
    and (pg_get_functiondef(p.oid) ~ '''SEC'',\s*''Configure'''
      or pg_get_functiondef(p.oid) ~ '''HRS'',\s*''Approve'''
      or pg_get_functiondef(p.oid) ~ 'check_finance_[a-z_]+_authority\(\s*''Approve''');
  if v_wired <> 65 then
    raise exception 'assertion failed: expected 65 wired functions, got %', v_wired;
  end if;

  -- The public.* wrapper must expose the parameter too, or the gate is unreachable from
  -- PostgREST and every browser-originated call silently skips it.
  select array_agg(fn order by fn) into v_wrapper_mismatch from (
    select a.proname as fn
    from pg_proc a join pg_namespace na on na.oid = a.pronamespace
    join pg_proc b on b.proname = a.proname
    join pg_namespace nb on nb.oid = b.pronamespace and nb.nspname = 'public'
    where na.nspname = 'app'
      and a.provolatile = 'v'
      and pg_get_functiondef(a.oid) like '%p_client_ip%'
      and pg_get_functiondef(a.oid) like '%assert_ip_allowed%'
      and (pg_get_functiondef(a.oid) ~ '''SEC'',\s*''Configure'''
        or pg_get_functiondef(a.oid) ~ '''HRS'',\s*''Approve'''
        or pg_get_functiondef(a.oid) ~ 'check_finance_[a-z_]+_authority\(\s*''Approve''')
      and pg_get_function_identity_arguments(b.oid) not like '%p_client_ip%'
  ) s;
  if v_wrapper_mismatch is not null then
    raise exception 'assertion failed: % public.* wrapper(s) do not expose p_client_ip, so the gate is unreachable from PostgREST -- %',
      array_length(v_wrapper_mismatch, 1), v_wrapper_mismatch;
  end if;

  raise notice 'PASS: all 65 wired, 1 deliberately excluded and named, every wrapper exposes the parameter';
end;
$$;

\echo '>> ISS-2026-302 behaviour, end to end on a real one of the 65: app.add_ip_allowlist_entry (SEC:Configure) denies an out-of-allowlist caller, allows an in-range one, is a no-op when no address is supplied, and is skipped for a holder of an approved bypass grant'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
  v_supreme uuid := '00000000-0000-0000-0000-000032000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000032000001';
  v_admin3 uuid := '00000000-0000-0000-0000-000032000004';
  v_role uuid;
  v_draft app.role_versions;
  v_entry app.ip_allowlist_entries;
  v_before integer;
begin
  -- A SECOND administrator, deliberately WITHOUT the bypass grant admin1 acquired above.
  -- Reusing admin1 would have proved only that a bypass holder is not blocked, which is the
  -- least interesting of the four cases here.
  insert into auth.users (id, email) values (v_admin3, 'admin3@iaeip.test');
  perform app.invite_user(v_tenant1, v_admin3, 'admin3@iaeip.test', 'Admin Three', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin3@iaeip.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin3, 'tenant_admin', v_tenant1, null, 'tester');
  v_role := (app.create_role(v_tenant1, 'IaeIp Admin Three', 'SEC:Configure/View', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(v_draft.id, array(select id from app.permissions where resource_module_code = 'SEC' and action in ('Configure', 'View')), 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), v_admin3, v_supreme, 'supreme');

  -- A live allowlist range and real enforcement. admin1 carries an approved bypass from the
  -- block above, so it can still reconfigure the policy from anywhere -- which is the whole
  -- point of the bypass and is what stops this fixture locking itself out.
  perform app.add_ip_allowlist_entry(v_tenant1, '10.0.0.0/8', 'datacentre range', 'admin', v_admin1, 'admin1');
  perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'enforced', v_admin1, 'admin1');

  -- 1. Out of range, no bypass: refused. This is the case that did not exist before -- the
  --    identical call, from the identical address, succeeded on all 65 of these functions.
  begin
    perform app.add_ip_allowlist_entry(v_tenant1, '192.0.2.0/24', 'from an unlisted address', 'admin', v_admin3, 'admin3', '203.0.113.77');
    raise exception 'assertion failed: expected ip_not_allowed for an out-of-allowlist caller on a SEC:Configure action';
  exception when insufficient_privilege then
    if sqlerrm not like 'ip_not_allowed%' then raise; end if;
  end;

  -- The refusal is genuinely the IP gate and not the authority check quietly failing: the
  -- same actor, same call, from an in-range address, succeeds.
  v_entry := app.add_ip_allowlist_entry(v_tenant1, '192.0.2.0/24', 'from a listed address', 'admin', v_admin3, 'admin3', '10.1.2.3');
  if v_entry.cidr::text <> '192.0.2.0/24' then
    raise exception 'assertion failed: expected the in-range call to succeed, got %', v_entry.cidr;
  end if;

  -- 3. No address supplied: unchanged behaviour. Every existing caller passes four arguments
  --    and must keep working exactly as before -- a widened signature that broke them would
  --    be a far worse defect than the one being fixed.
  v_entry := app.add_ip_allowlist_entry(v_tenant1, '198.51.100.0/24', 'no address supplied', 'admin', v_admin3, 'admin3');
  if v_entry.cidr::text <> '198.51.100.0/24' then
    raise exception 'assertion failed: expected the no-address call to behave exactly as before';
  end if;

  -- 4. Approved bypass grant: honoured, from the same address that just refused admin3.
  -- (203.0.113.77, deliberately NOT the 203.0.113.9 the ISS-2026-307 block above records a
  -- durable denial for -- reusing it would have made the residual assertion below count
  -- somebody else's row.)
  if not app.has_active_ip_allowlist_bypass(v_tenant1, v_admin1) then
    raise exception 'assertion failed: fixture precondition -- admin1 should still hold the approved bypass';
  end if;
  v_entry := app.add_ip_allowlist_entry(v_tenant1, '198.18.0.0/15', 'bypass holder, out-of-range address', 'admin', v_admin1, 'admin1', '203.0.113.77');
  if v_entry.cidr::text <> '198.18.0.0/15' then
    raise exception 'assertion failed: expected an approved bypass to skip the gate';
  end if;

  -- ISS-2026-307's residual, asserted as a property rather than left as prose: the denial in
  -- case 1 raised inside the business transaction, so its own evaluation row went with the
  -- rollback. If this ever starts persisting, invert this assertion -- do not delete it.
  select count(*) into v_before from app.ip_access_evaluations
  where tenant_id = v_tenant1 and ip_address = '203.0.113.77' and decision = 'denied';
  if v_before <> 0 then
    raise exception 'assertion failed: a denial raised inside a business transaction is expected to lose its evaluation row (ISS-2026-307 residual); it now persists (% row(s)), so this assertion should be INVERTED, not removed', v_before;
  end if;

  perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'disabled', v_admin1, 'admin1');
  raise notice 'PASS: the IP gate denies, allows, no-ops without an address, and honours a bypass, on a real one of the 65';
end;
$$;

\echo '>> ISS-2026-307: a denial raised INSIDE a business transaction still loses its app.ip_access_evaluations row -- and now leaves a counted, greppable trace anyway, because a sequence advance and a RAISE LOG line are the two things Postgres does not roll back'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeip');
  v_admin1 uuid := '00000000-0000-0000-0000-000032000001';
  v_admin3 uuid := '00000000-0000-0000-0000-000032000004';
  v_serial_before bigint;
  v_serial_after bigint;
  v_rows_before integer;
  v_rows_after integer;
  v_gap record;
begin
  -- Re-arm enforcement. admin1 holds the approved bypass from the block above, so it can still
  -- reconfigure from anywhere; admin3 does not, which is what makes it the probe.
  perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'enforced', v_admin1, 'admin1');

  v_serial_before := coalesce(pg_sequence_last_value('app.ip_denial_serial'::regclass), 0);
  select count(*) into v_rows_before from app.ip_access_evaluations where tenant_id = v_tenant1 and decision = 'denied';

  -- A REAL denial from inside a real business RPC, caught here exactly as a caller's own
  -- transaction boundary would discard it. app.add_ip_allowlist_entry is one of the 65
  -- functions ISS-2026-302 wired, so this is the production shape, not a synthetic probe.
  begin
    perform app.add_ip_allowlist_entry(v_tenant1, '192.51.100.0/24', 'from an unlisted address', 'admin', v_admin3, 'admin3', '172.16.0.5');
    raise exception 'assertion failed: fixture precondition -- expected ip_not_allowed for an out-of-allowlist caller';
  exception when insufficient_privilege then
    if sqlerrm not like 'ip_not_allowed%' then raise; end if;
  end;

  v_serial_after := coalesce(pg_sequence_last_value('app.ip_denial_serial'::regclass), 0);
  select count(*) into v_rows_after from app.ip_access_evaluations where tenant_id = v_tenant1 and decision = 'denied';

  -- The row is still lost. Asserted as a PROPERTY, not tolerated as an accident: if this ever
  -- starts persisting, this assertion must be INVERTED, not deleted -- it would mean the
  -- underlying rollback behaviour changed and the whole mechanism below needs rethinking.
  if v_rows_after <> v_rows_before then
    raise exception 'assertion failed: a denial raised inside a business transaction is expected to lose its app.ip_access_evaluations row (% -> %); it now persists, so this assertion should be INVERTED, not removed', v_rows_before, v_rows_after;
  end if;

  -- ...and the durable counter advanced anyway, through the same aborted subtransaction.
  if v_serial_after <> v_serial_before + 1 then
    raise exception 'assertion failed: expected the non-transactional denial counter to advance by exactly 1 across the aborted call (% -> %) -- a sequence advance is never rolled back, which is the entire reason one is used here', v_serial_before, v_serial_after;
  end if;

  -- And the gap is reported rather than left for someone to notice.
  select * into v_gap from app.get_ip_denial_evidence_gap();
  if v_gap.total_denials < v_serial_after then
    raise exception 'assertion failed: expected total_denials to reflect the sequence (>= %), got %', v_serial_after, v_gap.total_denials;
  end if;
  if v_gap.unrecorded_denials < 1 then
    raise exception 'assertion failed: expected at least one unrecorded denial to be reported, got % (total=% recorded=%)', v_gap.unrecorded_denials, v_gap.total_denials, v_gap.recorded_denials;
  end if;

  -- The counter counts EVERY denial, not only the lost ones: a denial through the evaluator,
  -- which does not raise and so keeps its row, must advance it too -- otherwise total_denials
  -- would undercount and the gap arithmetic would be wrong in the safe direction, which is
  -- still wrong.
  v_serial_before := v_serial_after;
  v_rows_before := v_rows_after;
  perform app.evaluate_ip_access(v_tenant1, '172.16.0.6', 'admin', 'iss307-evaluator-denial');
  select count(*) into v_rows_after from app.ip_access_evaluations where tenant_id = v_tenant1 and decision = 'denied';
  v_serial_after := coalesce(pg_sequence_last_value('app.ip_denial_serial'::regclass), 0);
  if v_serial_after <> v_serial_before + 1 or v_rows_after <> v_rows_before + 1 then
    raise exception 'assertion failed: a denial through the evaluator must advance the counter AND keep its row (serial % -> %, rows % -> %)', v_serial_before, v_serial_after, v_rows_before, v_rows_after;
  end if;

  -- An ALLOWED evaluation must not advance it -- a counter that ticks on success would make
  -- the gap meaningless.
  v_serial_before := v_serial_after;
  perform app.evaluate_ip_access(v_tenant1, '10.1.2.3', 'admin', 'iss307-evaluator-allow');
  if coalesce(pg_sequence_last_value('app.ip_denial_serial'::regclass), 0) <> v_serial_before then
    raise exception 'assertion failed: an allowed evaluation must not advance the denial counter';
  end if;

  perform app.set_ip_allowlist_enforcement_mode(v_tenant1, 'disabled', v_admin1, 'admin1');
  raise notice 'ISS-2026-307 proof: an in-transaction denial still loses its row, and is still counted; the evaluator path is counted and keeps its row; an allow is not counted; and app.get_ip_denial_evidence_gap reports the difference';
end;
$$;

\echo '>> ISS-2026-307 privilege regression: the denial counter and the gap report are operator/forensics tooling -- service_role only on both app.* and public.*, and no anon/authenticated reach to the sequence itself'
do $$
begin
  if has_function_privilege('anon', 'app.get_ip_denial_evidence_gap()', 'EXECUTE')
     or has_function_privilege('authenticated', 'app.get_ip_denial_evidence_gap()', 'EXECUTE')
     or has_function_privilege('anon', 'public.get_ip_denial_evidence_gap()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.get_ip_denial_evidence_gap()', 'EXECUTE') then
    raise exception 'assertion failed: app./public.get_ip_denial_evidence_gap must be service_role-only (the ISS-2026-298 platform-default-grant leak class)';
  end if;
  if not has_function_privilege('service_role', 'app.get_ip_denial_evidence_gap()', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.get_ip_denial_evidence_gap()', 'EXECUTE') then
    raise exception 'assertion failed: service_role must retain EXECUTE on both sides of the wrapper pair';
  end if;

  -- The sequence itself: a tenant session must not be able to read or advance the count of
  -- how many times the platform has blocked someone.
  if has_sequence_privilege('anon', 'app.ip_denial_serial', 'USAGE')
     or has_sequence_privilege('anon', 'app.ip_denial_serial', 'SELECT')
     or has_sequence_privilege('authenticated', 'app.ip_denial_serial', 'USAGE')
     or has_sequence_privilege('authenticated', 'app.ip_denial_serial', 'SELECT') then
    raise exception 'assertion failed: app.ip_denial_serial must carry no anon/authenticated privilege';
  end if;

  raise notice 'ISS-2026-307 privilege proof: the gap report is service_role-only on both sides and the counter sequence is unreachable from anon/authenticated';
end $$;

\echo 'ALL IAE-028 (IP Restriction and Network Access) ASSERTIONS PASSED'
