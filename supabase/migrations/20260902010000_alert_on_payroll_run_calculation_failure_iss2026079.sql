-- Closes ISS-2026-079 (docs/runtime/KNOWN_ISSUES.md) -- alerting only, per explicit owner
-- direction. This migration does NOT touch app.calculate_payroll_run's transaction/commit model,
-- its resumability, or its cancellation logic. Not attempted, not in scope.
--
-- WHAT THE ENTRY FOUND, RE-VERIFIED LIVE BEFORE WRITING ANYTHING HERE
--
--   `pg_get_functiondef` against the hosted project (awdlicmwzdxquopwtcfd), not the migration
--   file text: `app.calculate_payroll_run` (20260731000000, unredefined since -- grep-confirmed)
--   is one `plpgsql` FUNCTION, i.e. one transaction from the caller's perspective. It has exactly
--   one exception handler, and it is scoped to a single employee inside the per-row loop:
--
--     begin
--       perform app._calculate_payroll_run_for_employee(...);
--     exception when others then
--       insert into app.payroll_exceptions (...) values (..., 'calculation_error', 'high', sqlerrm);
--     end;
--
--   That handler is real and already alerts a human through the existing payroll_exceptions
--   workflow (per-employee, non-fatal). It is NOT what ISS-2026-079 is about. The entry is about
--   the WHOLE INVOCATION dying -- a statement timeout, a deadlock the outer statement can't
--   absorb, the connection dropping, the process being killed -- which happens OUTSIDE that
--   per-row block (before the loop, between the loop and app.complete_job, or as a truly fatal
--   error even the per-row handler cannot catch). There is no top-level exception handler on
--   `calculate_payroll_run` at all, live-confirmed. When that happens, PostgreSQL rolls the WHOLE
--   transaction back: the `app.jobs` row `enqueue_job` inserted, the `payroll_runs.status =
--   'calculating'` update, every deleted/re-inserted calculation line -- all of it. Nothing
--   commits, so nothing is left to alert ON from inside that same transaction.
--
-- WHY THE FIX CANNOT LIVE INSIDE `app.calculate_payroll_run` ITSELF
--
--   This is the same structural wall `ISS-2026-249` hit and the same ruling applies:
--
--     **A database function that rolls back cannot durably record the failure it rolled back
--     on.** Any `perform app.raise_observability_alert(...)` added inside
--     `calculate_payroll_run`'s own body, before a crash that aborts the transaction, is rolled
--     back along with everything else -- it would never be observed once the crash is the kind
--     this entry is actually about. And per the owner's explicit scope for this item, wrapping
--     the whole function in its own top-level exception handler that re-raises (the only way to
--     keep today's all-or-nothing caller contract while catching internally) does not help
--     either: PL/pgSQL's exception block is a savepoint, and a RE-RAISE after it unwinds
--     everything written after that savepoint too, including a freshly-inserted incident row --
--     and changing the caller contract to NOT re-raise would change how callers observe success
--     or failure, which is exactly the redesign the owner ruled out for this item.
--
--   So, mirroring `20260831100000`'s `app.record_authority_denial` /
--   `server/policies/authority-denial-recorder.ts` exactly: the recording happens at the
--   boundary that catches the error -- a fresh statement, in a fresh transaction, after the
--   rollback has already happened. That is the one place the fact "this run's calculation
--   attempt failed" both exists (the caller has the exception) and can be written down.
--
-- WHAT THIS MIGRATION ADDS
--
--   `app.record_payroll_run_calculation_failure` -- a normal (non-crashing, on the happy path)
--   function the application boundary calls AFTER catching a genuinely unexpected failure from
--   `app.calculate_payroll_run`. It looks the run back up by id (the row still exists --
--   `calculate_payroll_run` never deletes `app.payroll_runs`, only updates it, and that update
--   is exactly what rolled back), re-checks the SAME `HRS:Edit` authority `calculate_payroll_run`
--   itself requires (defense in depth against a caller that lost that authority between the two
--   calls, and against a browser forging a direct call), and composes
--   `app.raise_observability_alert` (IAE-030) -- never a second, parallel alerting path -- naming
--   the run id, tenant, period, run type, acting identity and the caught error text, with high
--   severity and a dedupe discriminator keyed on the run id: a worker crashing repeatedly on the
--   SAME run inside the dedupe window collapses into one incident (a duplicate_signal timeline
--   entry each time), but two DIFFERENT runs failing never collapse into each other's incident --
--   a human resuming run A must not have to wonder whether run B's own failure is hiding inside
--   it. `source_type = 'job'`, `signal_type = 'error'`, matching `app.record_job_failure`'s own
--   existing convention for a background-job-shaped failure (20260827000000).
--
--   The TS-layer half (`server/policies/payroll-run-failure-recorder.ts`, wired into
--   `calculatePayrollRunAction`) is deliberately selective: it does NOT alert on the routine,
--   already-classified rejections `calculate_payroll_run` raises before doing any real work
--   (`stale_version`, `insufficient_authority`, `payroll_run_not_found`,
--   `payroll_period_inputs_not_frozen`, `invalid_transition`, `idempotency_key_conflict`, ...) --
--   those are the authorization/validation layer working, not a crash, and alerting on each one
--   would be exactly the false-positive flood `ISS-2026-249`'s own ruling warned against. It
--   alerts only on an error `PayrollMutationError` cannot classify (code = "unknown") or a raw,
--   non-`PayrollMutationError` throw (a network failure, a dropped connection) -- the shape a
--   genuine mid-calculation crash actually takes once it reaches the caller.
--
-- Additive only. No column, constraint, grant or policy on any existing object is dropped or
-- narrowed. Mirrors the RGL-394 Option-2 public.* wrapper pattern exactly, since
-- calculatePayrollRunAction calls through PostgREST with an authenticated session, not
-- service_role.

create function app.record_payroll_run_calculation_failure(
  p_run_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_error_detail text
)
returns app.incidents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
  v_period app.payroll_periods;
  v_incident app.incidents;
begin
  select * into v_run from app.payroll_runs where id = p_run_id;
  if not found then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  -- Same HRS:Edit gate app.calculate_payroll_run itself requires -- this is a report ABOUT a
  -- calculation attempt, so only someone entitled to make that attempt may file one, matching
  -- app.record_authority_denial's own "the recorder enforces its own authority" discipline.
  if not app.check_payroll_authority('Edit', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_period from app.payroll_periods where id = v_run.payroll_period_id;

  v_incident := app.raise_observability_alert(
    v_run.tenant_id,
    'job',
    'error',
    format('Payroll run %s (period %s) failed to complete calculation', p_run_id, coalesce(v_period.code, '(unknown)')),
    'high',
    format(
      'app.calculate_payroll_run for run %s (tenant %s, period %s, run_type %s) did not complete -- the whole attempt rolled back and left no other durable trace (ISS-2026-079: the job lifecycle runs inside one transaction, with no multi-transaction resumability). Reported by identity %s (%s) immediately after catching the failure. Error: %s. A human must inspect the underlying cause and manually re-trigger app.calculate_payroll_run for this run once resolved -- there is no automatic resumption.',
      p_run_id, v_run.tenant_id, coalesce(v_period.code, '(unknown)'), v_run.run_type,
      coalesce(p_actor_auth_user_id::text, '(unattributed)'), coalesce(p_actor_label, '(unattributed)'),
      coalesce(p_error_detail, '(no detail captured)')
    ),
    -- Dedupe per RUN, not per tenant: two different runs failing inside the same window must
    -- open two incidents, but repeated crashes on the SAME run collapse into one.
    p_run_id::text
  );

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_payroll_run_calculation_failure',
    'app.payroll_runs', p_run_id, 'success', null, null,
    jsonb_build_object('incident_id', v_incident.id, 'error_detail', p_error_detail)
  );

  return v_incident;
end;
$$;

comment on function app.record_payroll_run_calculation_failure is
  'ISS-2026-079: records that one app.calculate_payroll_run attempt failed and alerts a human, called from the application boundary AFTER it catches the error -- the failing invocation itself rolled back and left nothing to alert from. Composes app.raise_observability_alert (IAE-030), never a second alerting path. Deliberately does not change app.calculate_payroll_run''s own transaction/commit model or resumability -- alerting only, per explicit owner scope for this item. Dedup discriminator is the run id, so repeated crashes on the same run collapse into one incident while two different failing runs never collapse into each other''s.';

revoke execute on function app.record_payroll_run_calculation_failure(uuid, uuid, text, text) from public;
grant execute on function app.record_payroll_run_calculation_failure(uuid, uuid, text, text) to authenticated, service_role;

-- RGL-394 Option-2 wrapper: app is not exposed to PostgREST.
create function public.record_payroll_run_calculation_failure(p_run_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_error_detail text)
returns app.incidents
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.record_payroll_run_calculation_failure(p_run_id, p_actor_auth_user_id, p_actor_label, p_error_detail);
$wrap$;

comment on function public.record_payroll_run_calculation_failure(uuid, uuid, text, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.record_payroll_run_calculation_failure, never a reimplementation. Matches app.*''s grant set exactly.';

revoke execute on function public.record_payroll_run_calculation_failure(uuid, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.record_payroll_run_calculation_failure(uuid, uuid, text, text) to authenticated, service_role;
