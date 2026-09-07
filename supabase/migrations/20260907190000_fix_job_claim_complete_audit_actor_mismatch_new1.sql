-- CG-AUDIT-2026-09-02 NEW-1 remediation (self-found during D2's own regression testing --
-- see 20260907100000_fix_route_planning_cross_tenant_guard_iss_d2.sql -- confirmed live,
-- not theoretical: any genuinely different authenticated session claiming or completing a
-- job than the job's own original requester raised `actor_identity_mismatch`, before any
-- job-type-specific authority check (e.g. that migration's own D2 guard) was ever reached).
--
-- `app.claim_next_job` and `app.complete_job` both lack any real actor-identity parameter
-- of their own (only `p_worker_id text` / `p_actor_label text`, worker labels with no real
-- identity backing) -- yet both passed `v_job.requested_by_auth_user_id` (the job's
-- ORIGINAL requester, not the calling worker) as `app.capture_audit_event`'s identity-
-- asserted `p_actor_auth_user_id` parameter. `capture_audit_event`'s IAE-037 Tier C fix
-- (20260809100000) defaults `p_support_access_grant_id` from `app.current_support_session
-- (p_tenant_id, p_actor_auth_user_id)`, whose own first statement is
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id)`
-- (20260810400000) -- correct for the ~1735 other call sites across this repository, where
-- the passed actor genuinely IS the caller's own session identity by construction, but
-- wrong for these two: under a genuine (non-null) session identity that is NOT the job's
-- original requester, this raised `actor_identity_mismatch` unconditionally, before either
-- function's own caller's job-type-specific authority guard (e.g.
-- `app.run_next_route_planning_job`'s CG-AUDIT-2026-09-02 D2 fix) was ever reached --
-- over-blocking legitimate same-tenant cross-user operation of the SAME queue, not merely
-- closing off cross-tenant abuse. Masked in production today because the only real caller
-- is the job supervisor's service-role client (null session identity, which the check
-- exempts) -- reproduced live against a disposable database for this fix: enqueue a job as
-- one genuine tenant member, then claim/complete it as a second, equally genuine, active
-- member of the SAME tenant (never the job's own original requester) -- reliably raised
-- actor_identity_mismatch before this fix, never after.
--
-- Fix: pass `auth.uid()` -- the CALLER's own real session identity (null for service-role/
-- nested-SECURITY-DEFINER-only calls, exactly preserving today's production behavior; the
-- genuine session identity when invoked from within an authenticated user's own SECURITY
-- DEFINER wrapper, trivially satisfying `assert_actor_is_session_identity` since the two
-- values are now identical by construction) -- as the identity-asserted actor, never
-- `v_job.requested_by_auth_user_id`. The original requester remains genuinely useful audit
-- information, so it moves into the event's own metadata instead of being discarded.
-- `app.record_job_failure` (20260816000000) already does this correctly (a real
-- `p_actor_auth_user_id` parameter, not a substituted job field) and needed no change;
-- `app.heartbeat_job` never calls `capture_audit_event` at all and is unaffected.
--
-- `CREATE OR REPLACE FUNCTION` for both -- unchanged signatures, no `DROP + CREATE`; neither
-- function was ever touched by any later migration (confirmed via a case-insensitive grep
-- for a later `ALTER FUNCTION`/`CREATE [OR REPLACE] FUNCTION` naming either one), so there
-- is no later security-mode hardening to preserve and no `public.*` wrapper to widen.
--
-- `auth.uid()` is read defensively (begin/exception, never bare), mirroring `app.
-- assert_actor_is_session_identity`'s own established idiom verbatim ("a deployment
-- without Supabase's auth schema, or a malformed JWT claim, must degrade to 'no session
-- identity known' rather than raising") -- neither function ever read this GUC before this
-- fix, so a malformed/leaked `request.jwt.claims` value (live-reproduced while writing this
-- migration's own db-test regression: a custom/placeholder GUC set via `SET LOCAL` outside
-- an explicit transaction block does not revert to unset, it reverts to an empty string,
-- which is not valid JSON) must degrade to null, the same safe default as never having set
-- it at all, never propagate as an uncaught error out of a job-queue primitive.

create or replace function app.claim_next_job(p_worker_id text, p_job_types text[], p_lease_duration_seconds integer default 300)
returns app.jobs
language plpgsql
as $function$
declare
  v_job app.jobs;
  v_session_identity uuid;
begin
  if p_worker_id is null or length(p_worker_id) = 0 then
    raise exception 'job_worker_id_required: a worker id is required to claim a job'
      using errcode = 'check_violation';
  end if;
  if p_lease_duration_seconds is null or p_lease_duration_seconds <= 0 then
    raise exception 'job_invalid_lease_duration: lease duration must be positive'
      using errcode = 'check_violation';
  end if;

  select * into v_job
  from app.jobs
  where job_type = any (p_job_types)
    and (
      (status = 'pending' and (next_attempt_at is null or next_attempt_at <= now()))
      or (status = 'in_progress' and locked_until < now())
    )
  order by priority desc, created_at asc
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update app.jobs
  set status = 'in_progress',
      locked_by = p_worker_id,
      locked_until = now() + (p_lease_duration_seconds || ' seconds')::interval,
      next_attempt_at = null,
      -- ATW-032: a re-claim after LEASE EXPIRY must count as an attempt. app.record_job_failure
      -- increments attempts on the ordinary failure path, but a worker that CRASHES never
      -- reaches it -- it just stops renewing the lease. Without this, such a job was
      -- re-claimed indefinitely, never reached max_attempts, and never dead-lettered: one
      -- crash-looping job could occupy a worker forever and starve the queue behind it.
      -- Only the expiry path counts; a first claim of a pending job does not.
      attempts = case when v_job.status = 'in_progress' then v_job.attempts + 1 else v_job.attempts end
  where job_id = v_job.job_id
  returning * into v_job;

  -- CG-AUDIT-2026-09-02 NEW-1: auth.uid() (the caller's own session identity, null when
  -- called by service-role or from a nested SECURITY DEFINER context with no session),
  -- never v_job.requested_by_auth_user_id -- see this migration's own header.
  begin
    v_session_identity := auth.uid();
  exception
    when others then
      v_session_identity := null;
  end;
  perform app.capture_audit_event(
    v_job.tenant_id, v_session_identity, p_worker_id, 'claim_next_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_type', v_job.job_type, 'locked_by', p_worker_id, 'requested_by_auth_user_id', v_job.requested_by_auth_user_id)
  );

  return v_job;
end;
$function$;

comment on function app.claim_next_job(text, text[], integer) is
  'CG-AUDIT-2026-09-02 NEW-1: the audit event''s identity-asserted actor is now auth.uid() (the caller''s own session identity), never the job''s original requester -- a genuinely different authenticated session claiming a job no longer raises actor_identity_mismatch before this function''s own caller (e.g. a job-type-specific run_next_*_job wrapper) ever reaches its own authority guard. The original requester is preserved as event metadata instead of being discarded.';

create or replace function app.complete_job(
  p_job_id uuid,
  p_worker_id text,
  p_result_url text,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_updated app.jobs;
  v_session_identity uuid;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status <> 'in_progress' or v_job.locked_by is distinct from p_worker_id then
    raise exception 'job_lease_not_held: worker % does not hold the current lease for job %', p_worker_id, p_job_id
      using errcode = 'check_violation';
  end if;

  update app.jobs
  set status = 'completed',
      completed_at = now(),
      result_url = p_result_url,
      locked_by = null,
      locked_until = null,
      next_attempt_at = null,
      error = null
  where job_id = p_job_id
  returning * into v_updated;

  -- CG-AUDIT-2026-09-02 NEW-1: identical fix and reasoning as app.claim_next_job above.
  begin
    v_session_identity := auth.uid();
  exception
    when others then
      v_session_identity := null;
  end;
  perform app.capture_audit_event(
    v_job.tenant_id, v_session_identity, p_actor_label, 'complete_job',
    'app.jobs', p_job_id, 'success', null,
    jsonb_build_object('status', v_job.status),
    jsonb_build_object('status', v_updated.status, 'requested_by_auth_user_id', v_job.requested_by_auth_user_id)
  );

  return v_updated;
end;
$$;

comment on function app.complete_job(uuid, text, text, text) is
  'CG-AUDIT-2026-09-02 NEW-1: same fix as app.claim_next_job -- auth.uid() as the identity-asserted actor, the original requester preserved as event metadata instead of being discarded.';
