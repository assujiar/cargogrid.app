-- Real, executable regression evidence for ISS-2026-267/HDN-BLK-036 (Step 16 historical
-- issue backlog remediation, docs/runtime/KNOWN_ISSUES.md ISS-2026-267): the composed
-- in-place restore procedure documented in docs/runbooks/database-restore.md §4 item 4
-- had no mutual-exclusion mechanism -- two concurrent restore attempts against the same
-- target could race, live-reproduced there via a bare CREATE TABLE collision.
--
-- The fix (see the runbook's own "ISS-2026-267 resolution" paragraph for the full design
-- rationale) is Postgres's own built-in session-level advisory lock, pg_try_advisory_lock/
-- pg_advisory_unlock -- no new schema object, so nothing is lost when the restore
-- procedure's own step (a) drops the app schema, and the lock auto-releases if the
-- operator's session crashes mid-procedure (no stale-lock cleanup logic needed). Fixed key,
-- documented once in the runbook and never reused: pg_try_advisory_lock(872314, 1).
--
-- This file proves the mechanism genuinely serializes two real, independent psql processes
-- (not a single-session simulation) using this repository's own already-established
-- two-process concurrency-race helper (scripts/db-tests/wms-picking-concurrency-helper.sh,
-- first built for advanced-tms-wms-outbound.sql/-picking.sql) rather than trusting the
-- built-in primitive's documented behavior without a live check.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
-- Needed here because this file's own ISS-2026-254 regression block below inserts a
-- disabled app.webhook_endpoints row, whose secret_value_encrypted column requires
-- app._encrypt_integration_secret(), which fails closed without this GUC set.
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

select current_database() as pg_test_db \gset

-- Process A acquires the lock immediately, holds it for 2 seconds, then releases it --
-- all three statements run sequentially inside the SAME psql -c session/connection, so
-- the lock is held across all of them, exactly matching how a human operator would hold
-- one dedicated terminal open for the whole restore procedure.
\set race_sql_a 'select ''A_ACQUIRE='' || pg_try_advisory_lock(872314, 1)::text; select pg_sleep(2); select ''A_RELEASE='' || pg_advisory_unlock(872314, 1)::text;'
-- Process B waits 300ms (long enough for A''s own near-instant first statement to have
-- already run and acquired the lock, well inside A''s own 2-second hold) then attempts the
-- SAME key once. This is the "second responder starts the procedure while the first is
-- still running" scenario ISS-2026-267 itself reproduced.
\set race_sql_b 'select pg_sleep(0.3); select ''B_ATTEMPT='' || pg_try_advisory_lock(872314, 1)::text;'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-restore-lock-race-a.out
\setenv RACE_OUT_B /tmp/cargogrid-restore-lock-race-b.out

\echo '>> ISS-2026-267 regression: two real, independent psql processes race for the same restore-procedure advisory lock'
\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

\set out_a `cat "$RACE_OUT_A"`
\set out_b `cat "$RACE_OUT_B"`
select set_config('cargogrid.restore_lock_out_a', :'out_a', false);
select set_config('cargogrid.restore_lock_out_b', :'out_b', false);

\echo '>> asserting genuine mutual exclusion: A acquires, B''s concurrent attempt against the SAME key correctly fails while A still holds it, A releases cleanly'
do $$
declare
  v_out_a text := current_setting('cargogrid.restore_lock_out_a');
  v_out_b text := current_setting('cargogrid.restore_lock_out_b');
begin
  if v_out_a not like '%A_ACQUIRE=t%' then
    raise exception 'assertion failed: expected process A to successfully acquire pg_try_advisory_lock(872314, 1) as the first/only holder, got: %', v_out_a;
  end if;

  if v_out_a not like '%A_RELEASE=t%' then
    raise exception 'assertion failed: expected process A to successfully release the lock it held, got: %', v_out_a;
  end if;

  if v_out_b not like '%B_ATTEMPT=f%' then
    raise exception 'assertion failed: expected process B''s concurrent attempt (300ms after A started, well inside A''s 2s hold) to fail with pg_try_advisory_lock returning false -- if this is true instead, the two processes did NOT mutually exclude, which is exactly the ISS-2026-267 race this test exists to catch. Got: %', v_out_b;
  end if;

  raise notice 'ISS-2026-267 mutual-exclusion proof: process A held the lock for its full 2-second window; process B''s concurrent attempt against the identical key correctly failed; A released cleanly afterward';
end $$;

\echo '>> asserting the lock is not left stuck: a fresh attempt after both racing processes have finished (A released explicitly, B never held it) succeeds immediately'
do $$
begin
  if not pg_try_advisory_lock(872314, 1) then
    raise exception 'assertion failed: expected the restore-procedure lock to be free and immediately acquirable once process A (the only holder) had released and disconnected -- a stuck lock here would mean an interrupted restore permanently blocks every future restore attempt';
  end if;

  if not pg_advisory_unlock(872314, 1) then
    raise exception 'assertion failed: expected this session''s own just-acquired lock to release cleanly via an explicit pg_advisory_unlock call';
  end if;

  raise notice 'ISS-2026-267 release proof: the lock was free immediately after the racing processes finished, and this session''s own explicit acquire/release both behaved correctly';
end $$;

\echo '>> ISS-2026-267/HDN-BLK-036 regression evidence complete: the composed in-place restore procedure''s advisory-lock mutual exclusion is live-proved, not merely documented'

-- ISS-2026-265/HDN-BLK-034: the restore procedure's own step (j) -- a single, explicit
-- audit event recording that a restore occurred (closing "zero audit trail"; TRUNCATE
-- bypassing per-row triggers itself is fundamental Postgres behavior this function
-- neither claims nor can fix -- see the runbook's own resolution note).
\echo '>> ISS-2026-265/HDN-BLK-034 regression: app.record_database_restore_event writes a real, explicit app.audit_logs entry -- the one closable half of "TRUNCATE leaves zero audit trail"'
do $$
declare
  v_row app.audit_logs;
begin
  v_row := app.record_database_restore_event('drill-operator', 'in_place_truncate_restore', 603, 'ISS-2026-265 regression drill');

  if v_row.tenant_id is not null then
    raise exception 'assertion failed: expected a whole-schema restore event to record tenant_id = null (the established platform-level-event convention), got %', v_row.tenant_id;
  end if;
  if v_row.action <> 'database_restore' or v_row.actor_label <> 'drill-operator' or v_row.result <> 'success' then
    raise exception 'assertion failed: expected action=database_restore/actor_label=drill-operator/result=success, got action=%, actor_label=%, result=%', v_row.action, v_row.actor_label, v_row.result;
  end if;
  if (v_row.after_value ->> 'scope') <> 'in_place_truncate_restore' or (v_row.after_value ->> 'tables_truncated')::integer <> 603 then
    raise exception 'assertion failed: expected the after_value payload to carry the real scope/table count supplied, got %', v_row.after_value;
  end if;
  if not exists (select 1 from app.audit_logs where id = v_row.id) then
    raise exception 'assertion failed: expected the returned row to actually be persisted in app.audit_logs, not merely constructed in memory';
  end if;

  -- Invalid scope/table-count/actor-label are all rejected, not silently accepted.
  begin
    perform app.record_database_restore_event('', 'in_place_truncate_restore', 1);
    raise exception 'assertion failed: expected an empty actor_label to be rejected';
  exception
    when others then
      if sqlerrm not like 'restore_event_missing_actor_label%' then raise; end if;
  end;
  begin
    perform app.record_database_restore_event('drill-operator', 'not_a_real_scope', 1);
    raise exception 'assertion failed: expected an unrecognized scope to be rejected';
  exception
    when others then
      if sqlerrm not like 'restore_event_invalid_scope%' then raise; end if;
  end;
  begin
    perform app.record_database_restore_event('drill-operator', 'in_place_truncate_restore', -1);
    raise exception 'assertion failed: expected a negative table count to be rejected';
  exception
    when others then
      if sqlerrm not like 'restore_event_invalid_table_count%' then raise; end if;
  end;

  raise notice 'ISS-2026-265 audit-trail proof: a real, explicit, persisted app.audit_logs row documents that a restore occurred, with the actual scope/table-count carried into its after_value payload -- closing this finding''s own "zero audit trail" half';
end $$;

\echo '>> ISS-2026-265/HDN-BLK-034 regression evidence complete'

-- ISS-2026-254 (partial, disclosed as voluntary): app.capture_security_state_snapshot /
-- app.detect_reverted_security_state -- a real, live, catalog-queried comparison, not a
-- documentation-only warning. Simulates exactly the shape the finding itself describes:
-- capture a snapshot while a legal hold / revoked key / disabled webhook / suspended user
-- / suspended membership are all in force, then directly mutate each back to its
-- pre-decision state (standing in for "a restore silently reverted this"), and confirm
-- detect_reverted_security_state reports every single one, then confirm a second snapshot
-- taken AFTER the revert reports nothing (a snapshot is only ever compared against its own
-- point in time, never treated as a standing invariant).
\echo '>> ISS-2026-254 regression: app.capture_security_state_snapshot / app.detect_reverted_security_state'
do $$
declare
  v_tenant app.tenants;
  v_placer uuid := '00000000-0000-0000-0000-000000000254';
  v_actor_auth uuid := '00000000-0000-0000-0000-000000000255';
  v_user app.users;
  v_membership app.principal_memberships;
  v_hold app.legal_holds;
  v_key app.api_keys;
  v_endpoint app.webhook_endpoints;
  v_snap public.security_state_snapshots;
  v_snap_after public.security_state_snapshots;
  v_reverted_count integer;
  v_reverted_after_count integer;
begin
  insert into auth.users (id, email) values (v_placer, 'iss254-holdplacer@example.test');
  insert into auth.users (id, email) values (v_actor_auth, 'iss254-actor@example.test');

  select * into v_tenant from app.provision_tenant('iss254tenant', 'ISS-2026-254 Regression Tenant', 'idem-iss254-1', 'tester');
  perform app.transition_tenant_status(v_tenant.id, 'active', 'bootstrap complete', 'tester');

  v_user := app.invite_user(v_tenant.id, v_actor_auth, 'iss254-actor@example.test', 'ISS-2026-254 Actor', null, 'tester', now() + interval '7 days');
  update app.users set status = 'active', activated_at = now() where id = v_user.id;
  perform app.transition_user_status(v_user.id, 'suspended', 'ISS-2026-254 regression drill', 'tester');

  v_membership := app.grant_principal_membership(v_actor_auth, 'org_user', v_tenant.id, null, 'tester');
  perform app.revoke_principal_membership(v_membership.id, 'ISS-2026-254 regression drill', 'tester');

  insert into app.legal_holds (tenant_id, record_class, scope_record_table, scope_record_id, reason, placed_by_auth_user_id, placed_by)
  values (v_tenant.id, 'operational', 'app.tenants', v_tenant.id, 'ISS-2026-254 regression drill', v_placer, 'tester')
  returning * into v_hold;

  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, created_by_auth_user_id, status, revoked_at, revoked_reason)
  values (v_tenant.id, 'ISS-2026-254 regression key', 'cg_iss254', 'iss254-fake-hash-value-not-a-real-key', '["ops:view"]'::jsonb, v_actor_auth, 'revoked', now(), 'ISS-2026-254 regression drill')
  returning * into v_key;

  insert into app.webhook_endpoints (tenant_id, url, secret_value_encrypted, created_by_auth_user_id, status, auto_disabled_at, disabled_reason)
  values (v_tenant.id, 'https://example.test/iss254-webhook', app._encrypt_integration_secret('iss254-fake-secret-not-real'), v_actor_auth, 'disabled', now(), 'ISS-2026-254 regression drill')
  returning * into v_endpoint;

  v_snap := app.capture_security_state_snapshot('iss254-drill-operator');

  if not (v_hold.id = any (v_snap.legal_hold_ids)) then
    raise exception 'assertion failed: expected the active legal hold to be captured in the snapshot';
  end if;
  if not (v_key.id = any (v_snap.revoked_api_key_ids)) then
    raise exception 'assertion failed: expected the revoked api key to be captured in the snapshot';
  end if;
  if not (v_endpoint.id = any (v_snap.disabled_webhook_endpoint_ids)) then
    raise exception 'assertion failed: expected the disabled webhook endpoint to be captured in the snapshot';
  end if;
  if not (v_user.id = any (v_snap.non_active_user_ids)) then
    raise exception 'assertion failed: expected the suspended user to be captured in the snapshot';
  end if;
  if not (v_membership.id = any (v_snap.non_active_membership_ids)) then
    raise exception 'assertion failed: expected the revoked membership to be captured in the snapshot';
  end if;

  -- Simulate a restore silently reverting every one of these decisions: directly flip
  -- each row back to its pre-decision state, bypassing every RPC (exactly what a raw
  -- pg_restore data load does -- it never calls application code). Also matches the real
  -- restore procedure's own --disable-triggers flag: app.principal_memberships carries a
  -- transition-enforcement trigger (app.enforce_principal_membership_transition, revoked
  -- is a terminal state) that a raw UPDATE would normally hit but pg_restore --disable-
  -- triggers bypasses -- session_replication_role = replica reproduces that bypass here.
  set local session_replication_role = replica;
  update app.legal_holds set status = 'released', released_by_auth_user_id = v_actor_auth, released_at = now(), release_reason = 'ISS-2026-254 simulated revert' where id = v_hold.id;
  update app.api_keys set status = 'active', revoked_at = null, revoked_reason = null where id = v_key.id;
  update app.webhook_endpoints set status = 'active', auto_disabled_at = null, disabled_reason = null where id = v_endpoint.id;
  update app.users set status = 'active', suspended_at = null, suspended_reason = null where id = v_user.id;
  update app.principal_memberships set status = 'active', revoked_at = null, revoked_reason = null where id = v_membership.id;
  set local session_replication_role = origin;

  select count(*) into v_reverted_count from app.detect_reverted_security_state(v_snap.id);
  if v_reverted_count <> 5 then
    raise exception 'assertion failed: expected exactly 5 reverted rows (one per category) after simulating a full revert, got %', v_reverted_count;
  end if;

  perform 1 from app.detect_reverted_security_state(v_snap.id) where category = 'legal_hold' and record_id = v_hold.id;
  if not found then raise exception 'assertion failed: expected the reverted legal hold to be reported by category'; end if;
  perform 1 from app.detect_reverted_security_state(v_snap.id) where category = 'api_key' and record_id = v_key.id;
  if not found then raise exception 'assertion failed: expected the reverted api key to be reported by category'; end if;
  perform 1 from app.detect_reverted_security_state(v_snap.id) where category = 'webhook_endpoint' and record_id = v_endpoint.id;
  if not found then raise exception 'assertion failed: expected the reverted webhook endpoint to be reported by category'; end if;
  perform 1 from app.detect_reverted_security_state(v_snap.id) where category = 'user' and record_id = v_user.id;
  if not found then raise exception 'assertion failed: expected the reverted user to be reported by category'; end if;
  perform 1 from app.detect_reverted_security_state(v_snap.id) where category = 'membership' and record_id = v_membership.id;
  if not found then raise exception 'assertion failed: expected the reverted membership to be reported by category'; end if;

  -- A fresh snapshot taken AFTER the revert reflects the (now fully reverted) live state,
  -- so comparing it against itself reports nothing -- proves detection is a genuine
  -- point-in-time comparison, not a hardcoded always-flag.
  v_snap_after := app.capture_security_state_snapshot('iss254-drill-operator-post-revert');
  select count(*) into v_reverted_after_count from app.detect_reverted_security_state(v_snap_after.id);
  if v_reverted_after_count <> 0 then
    raise exception 'assertion failed: expected a snapshot taken after the revert to detect nothing against itself, got % rows', v_reverted_after_count;
  end if;

  -- An unknown snapshot id is rejected, not silently treated as an empty snapshot.
  begin
    perform 1 from app.detect_reverted_security_state('00000000-0000-0000-0000-000000000000'::uuid);
    raise exception 'assertion failed: expected an unknown snapshot id to be rejected';
  exception
    when others then
      if sqlerrm not like 'security_snapshot_not_found%' then raise; end if;
  end;

  raise notice 'ISS-2026-254 partial-fix proof: a pre-restore snapshot correctly captures the active hold/revoked key/disabled webhook/suspended user/suspended membership, and post-revert detection correctly reports all 5 by category, while a same-point-in-time comparison correctly reports none';
end $$;

\echo '>> ISS-2026-254 regression evidence complete'

-- ISS-2026-299: public.security_state_snapshots is the first table this repository has
-- ever created directly in public schema. Live-proved exploitable in production before
-- the fix: anon/authenticated held direct SELECT/INSERT on it with RLS disabled --
-- Supabase's own default-privilege bootstrap, the identical class of gap ISS-2026-298
-- already found and fixed once for public.* FUNCTIONS, reproduced here for a TABLE.
-- Fixed live via a direct apply_migration call, then repository-side via
-- 20260826090000_harden_security_state_snapshots_table_privilege_leak.sql (RLS enabled,
-- fail-closed with zero policies; anon/authenticated explicitly revoked, not merely
-- `from public`). This regression guard proves it locally too, not merely live.
\echo '>> ISS-2026-299 regression: public.security_state_snapshots carries no anon/authenticated table privilege and has RLS enabled'
do $$
declare
  v_rls_enabled boolean;
begin
  select relrowsecurity into v_rls_enabled from pg_class where oid = 'public.security_state_snapshots'::regclass;
  if not v_rls_enabled then
    raise exception 'assertion failed: expected RLS to be enabled on public.security_state_snapshots';
  end if;

  if has_table_privilege('anon', 'public.security_state_snapshots', 'SELECT') then
    raise exception 'assertion failed: expected anon to hold no SELECT privilege on public.security_state_snapshots';
  end if;
  if has_table_privilege('authenticated', 'public.security_state_snapshots', 'SELECT') then
    raise exception 'assertion failed: expected authenticated to hold no SELECT privilege on public.security_state_snapshots';
  end if;
  if has_table_privilege('anon', 'public.security_state_snapshots', 'INSERT') then
    raise exception 'assertion failed: expected anon to hold no INSERT privilege on public.security_state_snapshots';
  end if;
  if has_table_privilege('authenticated', 'public.security_state_snapshots', 'INSERT') then
    raise exception 'assertion failed: expected authenticated to hold no INSERT privilege on public.security_state_snapshots';
  end if;
  if not has_table_privilege('service_role', 'public.security_state_snapshots', 'SELECT') then
    raise exception 'assertion failed: expected service_role to retain full access to public.security_state_snapshots';
  end if;

  raise notice 'ISS-2026-299 proof: public.security_state_snapshots is RLS-enabled and holds zero anon/authenticated table privilege -- only service_role can reach it';
end $$;

\echo '>> ISS-2026-299 regression evidence complete'
