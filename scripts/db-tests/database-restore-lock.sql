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
