-- Closes the remaining half of ISS-2026-053 (docs/runtime/KNOWN_ISSUES.md), and registers
-- ISS-2026-308, which the first attempt at this fix uncovered.
--
-- WHAT IS LEFT, after re-deriving the finding against the CURRENT body rather than the one it
-- was written against.
--
--   `app.enqueue_job` (PLT-132) takes an `idempotency_key` and, on a replay with the same key,
--   returns the existing `app.jobs` row. The finding was that it never compared the replay
--   against the original, so reusing a key for a genuinely DIFFERENT request silently returned
--   the first request's job instead of rejecting.
--
--   Half is already fixed: 20260731050000 added a `job_type` comparison on both paths, and the
--   entry's own last update said so and withdrew a draft. `payload` is still not compared, so:
--
--       enqueue_job(tenant, 'retention_archive', '{"olderThanDays": 30}',   …, key 'nightly')
--       enqueue_job(tenant, 'retention_archive', '{"olderThanDays": 3650}', …, key 'nightly')
--
--   returns the FIRST job to the second caller. Same type, so the existing guard passes;
--   different work, silently not done, and the caller is told it succeeded.
--
-- WHY THE OBVIOUS FIX IS WRONG, PROVED BY WRITING IT
--
--   The first version of this migration compared `v_existing.payload` against the request
--   payload. The full db-test suite rejected it immediately, and the failure was not in the new
--   assertions -- it was `app.run_loyalty_expiry_sweep`'s own long-standing
--   "running the sweep AGAIN for the same day does NOT double-expire" test.
--
--   Two independent reasons, and the second is the one that matters:
--
--     1. The sweep keys idempotency per DAY (`loyalty_expiry_sweep:<tenant>:<run_label>`) while
--        putting `clock_timestamp()` in its payload. Key says "once a day", payload says "every
--        call differs". Only the absence of a payload check hid the contradiction.
--     2. **`app.jobs.payload` is not a request field.** The sweep UPDATEs it after the job runs,
--        appending `lots_expired_count`/`entitlements_expired_count`. The column is a request
--        AND result store, so a stored payload can never equal the request that created it once
--        the job has done any work.
--
--   Reason 2 makes an equality check over `payload` wrong by construction, for every producer
--   that records results there -- not just this one. A containment check (`@>`) would tolerate
--   the appended result keys, but it also accepts a replay that OMITS a key the original set,
--   which is most of the original defect back again.
--
-- THE FIX: SEPARATE THE REQUEST FROM THE RESULT
--
--   `app.jobs.request_payload` records what was asked for, at insert, and is never written
--   again. Idempotency compares against that. `payload` keeps its existing dual role untouched,
--   so no producer changes behaviour and no existing row is migrated.
--
--   Rows created before this column exists carry null, and a null skips the comparison. An
--   already-enqueued job therefore cannot start raising conflicts against replays it used to
--   accept -- the guard applies from here forward, not retroactively.
--
--   `priority` and `max_attempts` stay OUT of the tuple deliberately. They are dispatch hints:
--   a caller retrying the same work at a higher priority is making the same request, and
--   rejecting that would turn a harmless retry into an error.
--
--   `app.run_loyalty_expiry_sweep` is corrected too (reason 1 above): its request payload now
--   records `p_as_of` **as supplied by the caller** -- null when defaulted -- so two default
--   calls on the same day are genuinely the same request. The instant actually swept is
--   recorded on completion as `swept_at`, alongside the counts, where a result belongs.
--   `v_as_of` still drives the expiry computation, unchanged.
--
-- A NOTE ON WHERE THESE BODIES COME FROM, because the first draft got it wrong
--
--   The first version copied `app.enqueue_job` from 20260731050000 and
--   `app.run_loyalty_expiry_sweep` from 20260811000000 -- in each case the newest migration a
--   grep for the function name surfaced. Both were stale. 20260810700000
--   (`harden_finance_authority_chain_security_definer`) had since made `enqueue_job`
--   `SECURITY DEFINER` with a pinned `search_path`, and the sweep had been redefined too.
--
--   Copying the older body would have SILENTLY REVERTED a security hardening -- the exact
--   defect class this repository keeps re-encountering. It was caught by
--   `scripts/db-tests/public-api-wrapper-regression.sql`, which noticed that
--   `public.enqueue_job` (definer) no longer matched its `app.*` counterpart (now invoker).
--   A gate catching a security regression the author introduced while fixing something else is
--   the gate earning its keep.
--
--   So both bodies below are reproduced from `pg_get_functiondef` against a database with every
--   migration applied -- the live definition, not the newest file a grep happens to find -- and
--   each edit is asserted to apply exactly once, with the `SECURITY DEFINER` and `search_path`
--   attributes asserted present after patching. See the rebuild script recorded in
--   `docs/build-log/` for this checkpoint.
--
-- Additive only. Nothing is dropped or narrowed; no existing row is rewritten.

-- ===========================================================================
-- 1. The request, recorded separately from the result
-- ===========================================================================
alter table app.jobs add column if not exists request_payload jsonb;

comment on column app.jobs.request_payload is
  'ISS-2026-053: the payload as supplied at enqueue, written once and never updated. app.jobs.payload is a request AND result store -- app.run_loyalty_expiry_sweep, among others, appends its own counts to it after the job runs -- so payload cannot serve as an idempotency tuple. This column can. Null on every row created before 20260830190000, and a null skips the comparison, so the guard never applies retroactively to a job that was enqueued under the old rules.';

CREATE OR REPLACE FUNCTION app.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.jobs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_existing app.jobs;
  v_job app.jobs;
  v_valid_job_types text[] := app.generic_job_types();
  -- Normalized once. The insert below stores this same value, so a null replay of a '{}'
  -- original is not mistaken for a conflict.
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_job_type in ('import', 'export') then
    raise exception 'job_type_requires_dedicated_entrypoint: % jobs must be created via app.create_import_export_job()', p_job_type
      using errcode = 'check_violation';
  end if;

  if not (p_job_type = any (v_valid_job_types)) then
    raise exception 'job_invalid_type: % is not a known generic job type', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
      -- ISS-2026-053: the half 20260731050000 did not close. Same key, same type, a different
      -- payload is a different request, and returning the first job for it silently drops work
      -- while telling the caller it succeeded. Compared against request_payload, never payload:
      -- payload is a request AND result store that producers append to after a job runs.
      if v_existing.request_payload is not null and v_existing.request_payload is distinct from v_payload then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for the same job type (%) with a different payload', p_idempotency_key, p_job_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(v_payload) then
    raise exception 'job_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_max_attempts, 3) <= 0 then
    raise exception 'job_invalid_max_attempts: max_attempts must be positive'
      using errcode = 'check_violation';
  end if;

  -- Batch 283-285 Tier C fix (finding 2, correctness lens): the
  -- check-then-insert above is not atomic -- two genuinely concurrent
  -- callers with the SAME (tenant_id, idempotency_key) can both pass the
  -- "not found" check above and both reach this INSERT. Without this
  -- exception handler the losing caller received a raw, unclassified
  -- Postgres 23505 instead of the SAME idempotent-replay row the winner
  -- (or a slightly-earlier caller) already created -- live-reproduced
  -- with two genuinely concurrent OS processes calling
  -- app.run_training_certificate_expiry_batch (HRT-284) with the same
  -- period label. Mirrors this repository's own established
  -- check-then-insert-with-handler shape (e.g.
  -- app.create_performance_kpi_definition, app.create_payroll_run).
  begin
    insert into app.jobs (
      tenant_id, job_type, payload, request_payload, priority, max_attempts, idempotency_key,
      requested_by_auth_user_id, created_by
    ) values (
      p_tenant_id, p_job_type, v_payload, v_payload, coalesce(p_priority, 0), coalesce(p_max_attempts, 3), p_idempotency_key,
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_job;
  exception
    when unique_violation then
      if p_idempotency_key is null then
        raise; -- not an idempotency-key race (e.g. a different constraint) -- surface unchanged.
      end if;
      select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise; -- constraint fired on something other than the key we expected -- surface unchanged rather than mask it.
      end if;
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
      -- ISS-2026-053: the half 20260731050000 did not close. Same key, same type, a different
      -- payload is a different request, and returning the first job for it silently drops work
      -- while telling the caller it succeeded. Compared against request_payload, never payload:
      -- payload is a request AND result store that producers append to after a job runs.
      if v_existing.request_payload is not null and v_existing.request_payload is distinct from v_payload then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for the same job type (%) with a different payload', p_idempotency_key, p_job_type
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type)
  );

  return v_job;
end;
$function$;

comment on function app.enqueue_job is
  'PLT-132: the generic job entry point. Idempotent on (tenant_id, idempotency_key), with the replay verified against the full request tuple -- job_type (20260731050000) and request_payload (20260830190000, ISS-2026-053). The comparison uses app.jobs.request_payload, never payload: payload is a request AND result store that producers append to after a job runs, so it can never equal the request that created it. priority and max_attempts are deliberately NOT part of the tuple -- they are dispatch hints, and a retry at a higher priority is the same request.';

-- ===========================================================================
-- 4. app.run_loyalty_expiry_sweep -- a request payload that matches its own key
-- ===========================================================================
-- Reproduced from the live catalog (see the note above), with exactly two changes: the enqueued
-- payload drops `as_of` and keeps `run_label`, and the completion update gains `swept_at` and
-- `requested_as_of`. `v_as_of` still drives both expiry primitives, byte-identically.
CREATE OR REPLACE FUNCTION app.run_loyalty_expiry_sweep(p_tenant_id uuid, p_as_of timestamp with time zone, p_actor_auth_user_id uuid, p_actor_label text, p_run_label text DEFAULT NULL::text)
 RETURNS TABLE(job_id uuid, status text, run_label text, lots_expired_count integer, entitlements_expired_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, clock_timestamp());
  v_run_label text;
  v_job app.jobs;
  v_worker_id text;
  v_lots_count integer := 0;
  v_entitlements_count integer := 0;
  v_final app.jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_run_label := coalesce(nullif(trim(p_run_label), ''), to_char(v_as_of, 'YYYY-MM-DD'));

  v_job := app.enqueue_job(
    p_tenant_id, 'loyalty_expiry_sweep', jsonb_build_object('run_label', v_run_label),
    0, 'loyalty_expiry_sweep:' || p_tenant_id::text || ':' || v_run_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-loyalty-expiry-sweep:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = clock_timestamp() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    -- Composes the two already-real, already-idempotent, tenant-wide expiry
    -- primitives (CPL-318/319) -- never reimplements either's own scan/
    -- posting logic. Real counts, from each function's own actually-
    -- returned row set. HDN-374 finding 4: v_as_of is now actually passed
    -- through -- previously silently discarded, so the sweep always used
    -- the real current time regardless of what p_as_of requested.
    select count(*) into v_lots_count from app.expire_loyalty_point_lots(p_tenant_id, p_actor_auth_user_id, p_actor_label, v_as_of);
    select count(*) into v_entitlements_count from app.expire_loyalty_benefit_entitlements(p_tenant_id, p_actor_auth_user_id, p_actor_label, v_as_of);

    -- Design decision 1: real counts recorded ON THE COMPLETED JOB ROW
    -- itself, via the job's own already-jsonb, already-not-null payload
    -- column, extended additively. Table-aliased (`j`) -- this function's
    -- own RETURNS TABLE clause implicitly declares job_id/status as
    -- PL/pgSQL variables in scope, the exact CPL-317-style ambiguous-column
    -- defect class, live-caught during this checkpoint's own smoke test
    -- before this file was finalized.
    update app.jobs j
    set payload = j.payload || jsonb_build_object('lots_expired_count', v_lots_count, 'entitlements_expired_count', v_entitlements_count, 'swept_at', v_as_of, 'requested_as_of', p_as_of)
    where j.job_id = v_job.job_id;

    v_final := app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_loyalty_expiry_sweep',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('run_label', v_run_label, 'lots_expired_count', v_lots_count, 'entitlements_expired_count', v_entitlements_count)
    );
  else
    -- A replay of an already-processed (or already in-flight, per decision
    -- 1's own live-proven serialize-then-no-op race outcome) period -- a
    -- safe no-op, returning whatever the ORIGINAL run's own payload holds.
    v_final := v_job;
    v_lots_count := coalesce((v_final.payload->>'lots_expired_count')::integer, 0);
    v_entitlements_count := coalesce((v_final.payload->>'entitlements_expired_count')::integer, 0);
  end if;

  job_id := v_final.job_id;
  status := v_final.status;
  run_label := v_run_label;
  lots_expired_count := v_lots_count;
  entitlements_expired_count := v_entitlements_count;
  return next;
end;
$function$;

comment on function app.run_loyalty_expiry_sweep is
  'CPL-322/HDN-374, corrected by ISS-2026-308: composes app.expire_loyalty_point_lots and app.expire_loyalty_benefit_entitlements against v_as_of, and records real counts on the completed job row. The ENQUEUED request payload carries run_label alone -- the idempotency key is per run_label, so by this function''s own design two calls with the same label are the same run whatever instant they name. The resolved instant (swept_at) and the caller''s own p_as_of (requested_as_of) are recorded on completion, on the result side, where a per-call value belongs.';
