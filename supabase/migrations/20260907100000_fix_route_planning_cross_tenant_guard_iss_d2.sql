-- CG-AUDIT-2026-09-02 D2 remediation.
--
-- The independent launch-readiness audit (docs/audit/2026-09-02-independent-launch-readiness-audit.md
-- §4 D2) found that `app.run_next_route_planning_job`'s own cross-tenant guard,
-- `perform app.assert_session_identity_in_tenant(v_scenario.tenant_id)`, sat INSIDE a
-- `begin ... exception when others then ... end;` block whose handler marks the scenario
-- `failed` and records a job failure -- swallowing the guard's own raised exception instead
-- of letting it propagate. The guard's own inline comment already states the intended
-- behavior ("the whole transaction rolls back, and the job claim is released with it -- no
-- job is consumed by a caller not entitled to it"), which the code did not actually deliver:
-- any authenticated user in any tenant could claim the next queued route-planning job
-- (`app.claim_next_job` claims across all tenants, by design, before the owning tenant is
-- knowable) and, instead of being refused, would successfully mark another tenant's
-- scenario `failed` and record a job failure under their own identity.
--
-- This fix moves the guard (and the tightly-coupled `scenario_not_found` check it must run
-- after -- `assert_session_identity_in_tenant` safely no-ops on a null tenant_id, matching
-- its own documented defensive behavior, so this ordering is unchanged from the original)
-- OUT of the inner exception-swallowing block, so a cross-tenant claim now genuinely raises
-- `insufficient_authority`, rolling back the whole function call -- including the job claim
-- `app.claim_next_job` already made -- exactly as the guard's own comment always claimed.
-- The inner `begin ... exception when others ... end;` block is preserved unchanged for its
-- actual purpose: a genuine planning-candidate-generation failure on a scenario the caller
-- IS entitled to still degrades to a recorded job failure rather than an unhandled error.
--
-- Everything else in the function body is verbatim its live predecessor.

create or replace function app.run_next_route_planning_job(p_worker_id text)
returns app.route_planning_scenarios
language plpgsql
security definer
set search_path to 'app', 'public', 'pg_temp'
as $function$
declare
  v_job app.jobs;
  v_scenario_id uuid;
  v_scenario app.route_planning_scenarios;
begin
  v_job := app.claim_next_job(p_worker_id, array['route_load_planning'], 300);
  if v_job is null then
    return null;
  end if;

  v_scenario_id := (v_job.payload ->> 'scenario_id')::uuid;

  select * into v_scenario from app.route_planning_scenarios where id = v_scenario_id;

  -- ATW-032 (ISS-2026-033), CG-AUDIT-2026-09-02 D2: this claims and executes the next queued
  -- planning job for ANY tenant, and was granted to authenticated with no authority check at
  -- all. The owning tenant is not knowable before the scenario resolves, so the guard sits
  -- here, deliberately OUTSIDE the exception-swallowing block below -- a non-member raises,
  -- the whole transaction genuinely rolls back, and the job claim is released with it -- no
  -- job is consumed by a caller not entitled to it.
  perform app.assert_session_identity_in_tenant(v_scenario.tenant_id);

  if not found then
    raise exception 'scenario_not_found: %', v_scenario_id using errcode = 'no_data_found';
  end if;

  begin
    -- Cooperative cancellation: a scenario cancelled after being enqueued is left
    -- untouched by the planner (this migration's own header) -- the job still
    -- completes successfully, it simply has nothing left to do.
    if v_scenario.status = 'executing' then
      perform app.generate_route_planning_candidates(v_scenario_id, p_worker_id);
    end if;

    perform app.complete_job(v_job.job_id, p_worker_id, null, p_worker_id);
  exception
    when others then
      update app.route_planning_scenarios set status = 'failed' where id = v_scenario_id and status = 'executing';
      perform app.record_job_failure(v_job.job_id, SQLERRM, null, p_worker_id);
  end;

  select * into v_scenario from app.route_planning_scenarios where id = v_scenario_id;
  return v_scenario;
end;
$function$;

comment on function app.run_next_route_planning_job(text) is
  'CG-AUDIT-2026-09-02 D2: the cross-tenant guard (assert_session_identity_in_tenant) now sits outside the exception-swallowing block, so a cross-tenant claim genuinely rolls back the whole job claim instead of being recorded as a job failure the guard itself triggered.';
