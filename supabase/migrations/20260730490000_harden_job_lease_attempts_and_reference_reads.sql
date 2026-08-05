-- CG-S10-ATW-032 (post-Prompt-248 audit) — three verified findings from the audit register.
--
-- 1. **`app.claim_next_job` never counted a lease-expiry re-claim as an attempt.**
--    `app.record_job_failure` increments `attempts` on the ordinary failure path, but a
--    worker that CRASHES never reaches it — it simply stops renewing its lease, and
--    `claim_next_job`'s own `(status = 'in_progress' and locked_until < now())` branch
--    re-claims the row. That branch set `locked_by`/`locked_until`/`next_attempt_at` and
--    left `attempts` untouched, so a crash-looping job was re-claimed indefinitely, never
--    reached `max_attempts`, and never dead-lettered. One poisoned job could hold a worker
--    forever and starve everything queued behind it. Only the expiry path now counts; a
--    first claim of a `pending` job still does not.
--
-- 2. **`app.canonical_terms` had RLS enabled, ZERO policies, and a live `SELECT` grant to
--    `authenticated`.** RLS with no policy is deny-all, so the grant was dead and every
--    authenticated read silently returned zero rows rather than the canonical term list.
--    `canonical_terms` carries no `tenant_id` — it is a platform-global reference table like
--    `app.uoms`, `app.finance_currencies` and `app.milestone_codes`, every one of which has
--    a `select_authenticated` policy with a `true` qualifier. It gets the same policy, so it
--    now behaves like its siblings instead of failing silently.
--
--    Note this is the safe direction: the table is global reference data with no tenant
--    column, so a permissive read policy leaks nothing. The alternative (dropping the
--    grant) would have been equally "correct" against the symptom while leaving the feature
--    broken.
--
-- 3. **`app.get_tenant_tracking_utilization_summary` folded stale vehicles into the
--    reported tracked count.** A stale vehicle genuinely still occupies a tracked-vehicle
--    entitlement slot, so counting it against `tracked_vehicle_limit_remaining` is correct
--    and is preserved. But the same statement also overwrote the RETURNED
--    `tracked_vehicle_count`, while `stale_vehicle_count` continued to be returned
--    separately — so any consumer adding the two double-counted every stale vehicle. The
--    limit basis is now computed locally and the reported counts stay disjoint.
--
-- All three were claims from the `ATW-031` audit register, each confirmed against the live
-- schema before being repaired — unlike the majority of that register, which did not
-- survive verification (see `ATW-031-DEEP-AUDIT-FINDINGS.md`).
--
-- Additive: two `CREATE OR REPLACE FUNCTION` on identical signatures and one new policy.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

create policy canonical_terms_select_authenticated on app.canonical_terms
  for select to authenticated using (true);

comment on table app.canonical_terms is
  'Platform-global canonical terminology reference data (no tenant_id). ATW-032: RLS was enabled here with ZERO policies while SELECT was granted to authenticated, so the grant was dead and every authenticated read silently returned nothing. It now carries the same permissive select policy every other global reference table (app.uoms, app.finance_currencies, app.milestone_codes) already had.';

CREATE OR REPLACE FUNCTION app.claim_next_job(p_worker_id text, p_job_types text[], p_lease_duration_seconds integer DEFAULT 300)
 RETURNS app.jobs
 LANGUAGE plpgsql
AS $function$
declare
  v_job app.jobs;
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

  perform app.capture_audit_event(
    v_job.tenant_id, v_job.requested_by_auth_user_id, p_worker_id, 'claim_next_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_type', v_job.job_type, 'locked_by', p_worker_id)
  );

  return v_job;
end;
$function$;

CREATE OR REPLACE FUNCTION app.get_tenant_tracking_utilization_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
 RETURNS app.tenant_tracking_utilization_summary
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_package app.tracking_package_resolution;
  v_result app.tenant_tracking_utilization_summary;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_package := app.resolve_tenant_tracking_package(p_tenant_id);
  v_result.tracking_enabled := v_package.enabled;
  v_result.package_code := v_package.package_code;
  v_result.max_tracked_vehicles := v_package.max_tracked_vehicles;
  v_result.max_mobile_sessions := v_package.max_mobile_sessions;

  select
    count(*),
    count(*) filter (where coverage.coverage_status = 'tracked'),
    count(*) filter (where coverage.coverage_status = 'stale'),
    count(*) filter (where coverage.coverage_status = 'offline'),
    count(*) filter (where coverage.coverage_status = 'not_tracked')
    into
    v_result.total_active_vehicle_count,
    v_result.tracked_vehicle_count,
    v_result.stale_vehicle_count,
    v_result.offline_vehicle_count,
    v_result.not_tracked_vehicle_count
  from app.get_tenant_tracking_coverage(p_tenant_id, p_actor_auth_user_id) coverage;

  -- ATW-032: a stale vehicle still OCCUPIES a tracked-vehicle entitlement slot, so it must
  -- count against the limit -- but it was previously folded into the REPORTED
  -- tracked_vehicle_count as well, while stale_vehicle_count was still returned separately.
  -- Any consumer adding the two double-counted every stale vehicle. The limit basis is now
  -- a local; the reported counts stay disjoint.
  if v_package.max_tracked_vehicles is not null then
    v_result.tracked_vehicle_limit_remaining :=
      v_package.max_tracked_vehicles
      - (coalesce(v_result.tracked_vehicle_count, 0) + coalesce(v_result.stale_vehicle_count, 0));
  end if;

  select count(*), count(*) filter (where status = 'active') into v_result.device_total_count, v_result.device_active_count
    from app.gps_devices where tenant_id = p_tenant_id;

  select count(*) into v_result.mobile_session_active_count
    from app.driver_mobile_tracking_sessions where tenant_id = p_tenant_id and status = 'active';

  select count(*) into v_result.untracked_required_leg_count
    from app.shipment_legs leg
    join app.shipment_leg_tracking_policies pol on pol.shipment_leg_id = leg.id and pol.tracking_required
    where leg.tenant_id = p_tenant_id
      and leg.leg_status in ('dispatched', 'in_transit')
      and not exists (
        select 1 from app.shipment_leg_tracking_sessions sess
        where sess.shipment_leg_id = leg.id and sess.status = 'active' and sess.is_current
      );

  return v_result;
end;
$function$;


revoke execute on all functions in schema app from public;

grant execute on function app.claim_next_job(text,text[],integer) to service_role;
grant execute on function app.get_tenant_tracking_utilization_summary(uuid,uuid) to authenticated, service_role;
