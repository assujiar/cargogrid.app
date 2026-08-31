-- Closes `ISS-2026-126`, `ISS-2026-127` item 1, and `ISS-2026-128` item 1 -- three entries
-- filed separately that were always one gap, and each says so about the others.
--
-- WHAT THEY ALL SAID, AND WHY IT IS ANSWERABLE NOW
--
--   CPL-316 built `app.evaluate_customer_loyalty_earning_for_paid_invoice`, CPL-317 built
--   `app.recalculate_customer_loyalty_tier`, CPL-318 built `app.post_loyalty_points_earned`.
--   All three are real, idempotent and correct. All three are reachable ONLY by a staff member
--   clicking a button, one record at a time, and each entry disclosed that in the same words:
--   registering scheduled-job wiring is "a genuinely new, capability-sized addition beyond this
--   prompt's own bounded scope."
--
--   That was true, and it stopped being true on 2026-08-31, when
--   `20260831090000_create_tenant_configurable_task_scheduler.sql` shipped the capability those
--   three entries were each waiting on: a Supreme-Admin-owned catalogue of schedulable tasks, a
--   per-tenant schedule with a real accountable identity, and a dispatcher. Two loyalty tasks
--   are already in that catalogue. These three were not, for a reason that is not scheduling at
--   all -- and that reason is the actual work in this file.
--
-- THE REAL OBSTACLE: THESE THREE RPCs ARE PER-RECORD, AND A SCHEDULE HAS NO RECORD
--
--   `app.expire_loyalty_point_lots` could be put in the catalogue directly because it already
--   takes a tenant and sweeps it. These three take an AR open item, a loyalty account, and an
--   earning event respectively. A cron entry has none of those. So what was missing was never a
--   scheduler entry -- it was the sweep that finds the work.
--
--   Each function below is exactly that and nothing more: a query that finds the records still
--   waiting, and a loop that calls the existing per-record RPC on each. Not one line of earning
--   computation, tier evaluation or lot posting is reimplemented here. If any of that logic is
--   wrong it is wrong in one place, as it was before.
--
-- THE ONE DESIGN DECISION THAT MATTERS: A SKIPPED RECORD IS NOT A FAILED SWEEP
--
--   Every one of these per-record RPCs raises on an ineligible record, and raising is right for
--   them: a staff member clicking "evaluate this invoice" on an invoice below the programme
--   minimum deserves to be told why, not to get silence.
--
--   A sweep meets those same conditions constantly and legitimately -- an unpaid invoice, a
--   customer with no loyalty enrolment, a programme with no published rule version, an account
--   whose programme has no base tier. If one raise aborted the run, a single ineligible record
--   would stop every eligible one behind it, and the nightly sweep would do nothing at all until
--   somebody noticed. So each call runs in its own subtransaction: a raise rolls back that
--   record alone and is counted as a skip with its own reason, and the sweep continues.
--
--   Skips are recorded, not swallowed. The first twenty reasons are written onto the job row, so
--   "the sweep ran and processed nothing" is always readable as WHY nothing -- twenty is a
--   deliberate cap, because an unbounded reason list on a tenant with ten thousand ineligible
--   invoices would be a payload nobody can read and a row nobody wants to store.
--
-- AUTHORITY IS UNCHANGED, AND DELIBERATELY NOT CENTRALISED HERE
--
--   Each sweep checks `LYL:Edit` for its own caller, exactly as `app.run_loyalty_expiry_sweep`
--   does -- and then every inner RPC re-checks the same permission for the same identity on
--   every single record. That is redundant on purpose. The sweep's own gate is what stops an
--   unauthorised caller starting a run at all; the inner gates are what make it impossible for a
--   sweep to become a way to do something its caller could not do one record at a time.
--
--   Under the scheduler the identity is the real person who authorised the schedule, whose
--   authority is re-checked on every run. Nothing here runs as "the system".
--
-- A NEAR-MISS WORTH RECORDING, CAUGHT BY THIS REPOSITORY'S OWN GATE
--
--   The `create or replace` of `app._run_scheduled_task_once` below was first drafted from the
--   dispatcher as `20260831090000` created it -- eleven branches. But `20260831100000` had
--   already extended it to sixteen. Replacing from the CREATING migration would have silently
--   deleted five live dispatch branches, and every schedule using them would have started
--   raising `scheduled_task_not_dispatchable` on its next run.
--
--   This is exactly the trap this repository already names: reading the migration that created
--   a function is not reading the function. What caught it was not care -- it was
--   `scripts/db-tests/task-scheduler.sql`'s own assertion that EVERY active catalogue task
--   reaches a real dispatch branch, which failed loudly on the first full run. The version
--   below is rebuilt from the currently-applied definition, with all sixteen prior branches
--   byte-identical and three added.

-- ===========================================================================
-- 1. Job types. app.jobs' own CHECK constraint is an allow-list, so three new
-- sweep types have to be added to it before enqueue_job will accept them.
-- A corrective ALTER, never an edit to the applied migration that created it.
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type = any (array[
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry',
    'document_generation', 'dashboard_refresh', 'loyalty_expiration', 'recurring_billing',
    'integration_sync', 'route_load_planning', 'print_label', 'roster_generation',
    'leave_accrual', 'leave_carry_forward_expiry', 'payroll_calculation',
    'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation',
    'loyalty_expiry_sweep', 'automation_action_execution', 'logistics_partner_sync',
    'finance_bank_feed_sync', 'external_sync', 'audit_export', 'retention_archive',
    'incident_escalation_sweep',
    -- ISS-2026-126 / 127 / 128:
    'loyalty_earning_evaluation_sweep', 'loyalty_tier_recalculation_sweep', 'loyalty_points_posting_sweep'
  ])
);

-- The CHECK constraint is not the only list of job types. `app.generic_job_types()`
-- (ATW-031, ISS-2026-012) is the function half of the same truth, and
-- `scripts/db-tests/background-job.sql` asserts the two stay set-equal -- which is
-- exactly what caught the first draft of this migration, where only the CHECK was
-- widened. The gate working, not an afterthought. The CHECK deliberately keeps its own
-- literal list rather than calling the function: a CHECK is never re-validated when a
-- function it calls changes, which would recreate the drift that pairing closes.

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync', 'external_sync',
    'audit_export', 'retention_archive', 'incident_escalation_sweep',
    -- ISS-2026-126 / 127 / 128:
    'loyalty_earning_evaluation_sweep', 'loyalty_tier_recalculation_sweep', 'loyalty_points_posting_sweep'
  ]::text[];
$$;

-- ===========================================================================
-- 2. app.run_loyalty_earning_evaluation_sweep -- ISS-2026-126
-- ===========================================================================

create function app.run_loyalty_earning_evaluation_sweep(
  p_tenant_id uuid,
  p_as_of timestamptz default now(),
  p_actor_auth_user_id uuid default null,
  p_actor_label text default null,
  p_run_label text default null
)
returns table (job_id uuid, status text, run_label text, processed_count integer, skipped_count integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, now());
  v_run_label text;
  v_job app.jobs;
  v_final app.jobs;
  v_worker_id text;
  v_candidate record;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_skips jsonb := '[]'::jsonb;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_run_label := coalesce(nullif(trim(p_run_label), ''), to_char(v_as_of, 'YYYY-MM-DD'));

  v_job := app.enqueue_job(
    p_tenant_id, 'loyalty_earning_evaluation_sweep', jsonb_build_object('run_label', v_run_label),
    0, 'loyalty_earning_evaluation_sweep:' || p_tenant_id::text || ':' || v_run_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-loyalty-earning-evaluation-sweep:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = clock_timestamp() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    -- The candidate query mirrors the per-invoice RPC's own first three guards (paid, not
    -- held, not already evaluated) so the common ineligible cases never become skips at all.
    -- The remaining guards -- enrolment, active programme, published rule version, minimum
    -- amount -- deliberately stay where they are, inside the RPC: duplicating them here would
    -- be a second copy of the eligibility rule, free to drift from the one that decides.
    --
    -- `idempotency_key = 'ar-open-item:' || id` is the RPC's own deterministic, source-derived
    -- key, read here rather than re-derived from anything else, so this filter and that RPC
    -- cannot disagree about what "already evaluated" means.
    for v_candidate in
      select ar.id
      from app.finance_ar_open_items ar
      where ar.tenant_id = p_tenant_id
        and ar.status = 'paid'
        and not ar.is_held
        and not exists (
          select 1 from app.loyalty_earning_events e
          where e.tenant_id = p_tenant_id and e.idempotency_key = 'ar-open-item:' || ar.id::text
        )
      order by ar.updated_at, ar.id
    loop
      begin
        perform app.evaluate_customer_loyalty_earning_for_paid_invoice(p_tenant_id, v_candidate.id, p_actor_auth_user_id, p_actor_label);
        v_processed := v_processed + 1;
      exception
        when others then
          -- One ineligible invoice must never stop the eligible ones behind it. The
          -- subtransaction this block opens rolls back only this record.
          v_skipped := v_skipped + 1;
          if jsonb_array_length(v_skips) < 20 then
            v_skips := v_skips || jsonb_build_object('ar_open_item_id', v_candidate.id, 'reason', split_part(sqlerrm, ':', 1));
          end if;
      end;
    end loop;

    update app.jobs j
    set payload = j.payload || jsonb_build_object(
      'processed_count', v_processed, 'skipped_count', v_skipped, 'skips', v_skips,
      'swept_at', v_as_of, 'requested_as_of', p_as_of)
    where j.job_id = v_job.job_id;

    v_final := app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_loyalty_earning_evaluation_sweep',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('run_label', v_run_label, 'processed_count', v_processed, 'skipped_count', v_skipped)
    );
  else
    v_final := v_job;
    v_processed := coalesce((v_final.payload->>'processed_count')::integer, 0);
    v_skipped := coalesce((v_final.payload->>'skipped_count')::integer, 0);
  end if;

  job_id := v_final.job_id;
  status := v_final.status;
  run_label := v_run_label;
  processed_count := v_processed;
  skipped_count := v_skipped;
  return next;
end;
$$;

comment on function app.run_loyalty_earning_evaluation_sweep is
  'ISS-2026-126: finds every fully-paid, unheld AR open item this tenant has not yet evaluated for loyalty earning, and calls app.evaluate_customer_loyalty_earning_for_paid_invoice on each. Reimplements none of that RPC''s own eligibility or computation -- the candidate query mirrors only its first three guards (paid, not held, not already evaluated, via the RPC''s own deterministic ar-open-item: idempotency key) so the common ineligible cases never become skips; enrolment, programme, rule-version and minimum-amount checks stay inside the RPC where the decision lives. Each call runs in its own subtransaction, so an ineligible record is a counted skip with its own reason rather than an aborted run -- the first twenty reasons land on the job row, capped because an unbounded list is a payload nobody reads. LYL:Edit here AND again inside the RPC per record, on purpose: the outer gate stops an unauthorised run starting, the inner gates stop a sweep ever doing what its caller could not do one record at a time. Idempotent per (tenant, run_label) through app.enqueue_job, exactly as app.run_loyalty_expiry_sweep is.';

-- ===========================================================================
-- 3. app.run_loyalty_tier_recalculation_sweep -- ISS-2026-127 item 1
-- ===========================================================================

create function app.run_loyalty_tier_recalculation_sweep(
  p_tenant_id uuid,
  p_as_of timestamptz default now(),
  p_actor_auth_user_id uuid default null,
  p_actor_label text default null,
  p_run_label text default null
)
returns table (job_id uuid, status text, run_label text, processed_count integer, skipped_count integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, now());
  v_run_label text;
  v_job app.jobs;
  v_final app.jobs;
  v_worker_id text;
  v_candidate record;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_skips jsonb := '[]'::jsonb;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_run_label := coalesce(nullif(trim(p_run_label), ''), to_char(v_as_of, 'YYYY-MM-DD'));

  v_job := app.enqueue_job(
    p_tenant_id, 'loyalty_tier_recalculation_sweep', jsonb_build_object('run_label', v_run_label),
    0, 'loyalty_tier_recalculation_sweep:' || p_tenant_id::text || ':' || v_run_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-loyalty-tier-recalculation-sweep:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = clock_timestamp() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    -- Every active enrolment, not only those with recent activity. Tier rules can be
    -- time-based (a qualifying window elapsing with no new spend is itself a reason to move
    -- an account DOWN), so filtering to accounts with new earning events would silently skip
    -- exactly the demotions a periodic recalculation exists to catch. The per-account RPC is
    -- idempotent, so recalculating an unchanged account costs a no-op, not a spurious movement.
    for v_candidate in
      select a.id from app.loyalty_accounts a
      where a.tenant_id = p_tenant_id and a.status = 'active'
      order by a.id
    loop
      begin
        perform app.recalculate_customer_loyalty_tier(p_tenant_id, v_candidate.id, p_actor_auth_user_id, p_actor_label);
        v_processed := v_processed + 1;
      exception
        when others then
          -- A programme with no base tier raises per account (ISS-2026-127 item 2, a disclosed
          -- and deliberate design choice). Under a sweep that must not take the whole run down.
          v_skipped := v_skipped + 1;
          if jsonb_array_length(v_skips) < 20 then
            v_skips := v_skips || jsonb_build_object('loyalty_account_id', v_candidate.id, 'reason', split_part(sqlerrm, ':', 1));
          end if;
      end;
    end loop;

    update app.jobs j
    set payload = j.payload || jsonb_build_object(
      'processed_count', v_processed, 'skipped_count', v_skipped, 'skips', v_skips,
      'swept_at', v_as_of, 'requested_as_of', p_as_of)
    where j.job_id = v_job.job_id;

    v_final := app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_loyalty_tier_recalculation_sweep',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('run_label', v_run_label, 'processed_count', v_processed, 'skipped_count', v_skipped)
    );
  else
    v_final := v_job;
    v_processed := coalesce((v_final.payload->>'processed_count')::integer, 0);
    v_skipped := coalesce((v_final.payload->>'skipped_count')::integer, 0);
  end if;

  job_id := v_final.job_id;
  status := v_final.status;
  run_label := v_run_label;
  processed_count := v_processed;
  skipped_count := v_skipped;
  return next;
end;
$$;

comment on function app.run_loyalty_tier_recalculation_sweep is
  'ISS-2026-127 item 1: recalculates the membership tier of every ACTIVE loyalty account in the tenant via app.recalculate_customer_loyalty_tier, reimplementing none of its evaluation. Deliberately every active enrolment rather than only accounts with new earning events: tier rules can be time-based, so a qualifying window elapsing with no new spend is itself a reason to move an account down, and an activity filter would silently skip exactly the demotions a periodic recalculation exists to catch -- the RPC is idempotent, so an unchanged account costs a no-op rather than a spurious movement. A programme with no base tier raises per account (ISS-2026-127 item 2, a disclosed design choice); under a sweep that is a counted skip, never an aborted run. Idempotent per (tenant, run_label).';

-- ===========================================================================
-- 4. app.run_loyalty_points_posting_sweep -- ISS-2026-128 item 1
-- ===========================================================================

create function app.run_loyalty_points_posting_sweep(
  p_tenant_id uuid,
  p_as_of timestamptz default now(),
  p_actor_auth_user_id uuid default null,
  p_actor_label text default null,
  p_run_label text default null
)
returns table (job_id uuid, status text, run_label text, processed_count integer, skipped_count integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, now());
  v_run_label text;
  v_job app.jobs;
  v_final app.jobs;
  v_worker_id text;
  v_candidate record;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_skips jsonb := '[]'::jsonb;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_run_label := coalesce(nullif(trim(p_run_label), ''), to_char(v_as_of, 'YYYY-MM-DD'));

  v_job := app.enqueue_job(
    p_tenant_id, 'loyalty_points_posting_sweep', jsonb_build_object('run_label', v_run_label),
    0, 'loyalty_points_posting_sweep:' || p_tenant_id::text || ':' || v_run_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-loyalty-points-posting-sweep:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = clock_timestamp() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    -- Points-type earning events with no lot yet. `source_earning_event_id` on the lot is the
    -- real link the posting RPC itself creates, so "already posted" is read from the thing that
    -- posting actually produces rather than from a status column that could drift from it.
    --
    -- p_expiry_days is deliberately NOT passed: ISS-2026-128 item 2 was closed by
    -- 20260828000000, which made the window a per-programme configuration the RPC resolves
    -- itself. Supplying one here would override tenant configuration with a scheduler default,
    -- quietly undoing that fix.
    for v_candidate in
      select e.id from app.loyalty_earning_events e
      where e.tenant_id = p_tenant_id
        and e.reward_type = 'points'
        and not exists (select 1 from app.loyalty_point_lots l where l.tenant_id = p_tenant_id and l.source_earning_event_id = e.id)
      order by e.created_at, e.id
    loop
      begin
        perform app.post_loyalty_points_earned(p_tenant_id, v_candidate.id, p_actor_auth_user_id, p_actor_label);
        v_processed := v_processed + 1;
      exception
        when others then
          v_skipped := v_skipped + 1;
          if jsonb_array_length(v_skips) < 20 then
            v_skips := v_skips || jsonb_build_object('earning_event_id', v_candidate.id, 'reason', split_part(sqlerrm, ':', 1));
          end if;
      end;
    end loop;

    update app.jobs j
    set payload = j.payload || jsonb_build_object(
      'processed_count', v_processed, 'skipped_count', v_skipped, 'skips', v_skips,
      'swept_at', v_as_of, 'requested_as_of', p_as_of)
    where j.job_id = v_job.job_id;

    v_final := app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_loyalty_points_posting_sweep',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('run_label', v_run_label, 'processed_count', v_processed, 'skipped_count', v_skipped)
    );
  else
    v_final := v_job;
    v_processed := coalesce((v_final.payload->>'processed_count')::integer, 0);
    v_skipped := coalesce((v_final.payload->>'skipped_count')::integer, 0);
  end if;

  job_id := v_final.job_id;
  status := v_final.status;
  run_label := v_run_label;
  processed_count := v_processed;
  skipped_count := v_skipped;
  return next;
end;
$$;

comment on function app.run_loyalty_points_posting_sweep is
  'ISS-2026-128 item 1: converts every points-type earning event with no point lot yet into one, via app.post_loyalty_points_earned. "Already posted" is read from app.loyalty_point_lots.source_earning_event_id -- the link posting itself creates -- rather than from a status column that could drift from it. p_expiry_days is deliberately not passed: 20260828000000 (closing this entry''s own item 2) made the window a per-programme configuration the RPC resolves itself, and supplying one here would override tenant configuration with a scheduler default. Per-record subtransaction isolation and (tenant, run_label) idempotency, as with its two sibling sweeps.';

-- ===========================================================================
-- 5. Grants + public.* wrappers (RGL-394 Option 2).
--
-- `revoke ... from anon, authenticated, service_role, public` rather than `from public`
-- alone: Supabase's ALTER DEFAULT PRIVILEGES grants anon EXECUTE explicitly at CREATE
-- time, and an explicit grant survives a PUBLIC revoke (ISS-2026-309).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.run_loyalty_earning_evaluation_sweep(uuid, timestamptz, uuid, text, text) to authenticated, service_role;
grant execute on function app.run_loyalty_tier_recalculation_sweep(uuid, timestamptz, uuid, text, text) to authenticated, service_role;
grant execute on function app.run_loyalty_points_posting_sweep(uuid, timestamptz, uuid, text, text) to authenticated, service_role;

create function public.run_loyalty_earning_evaluation_sweep(
  p_tenant_id uuid, p_as_of timestamptz default now(), p_actor_auth_user_id uuid default null,
  p_actor_label text default null, p_run_label text default null
)
returns table (job_id uuid, status text, run_label text, processed_count integer, skipped_count integer)
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.run_loyalty_earning_evaluation_sweep(p_tenant_id, p_as_of, p_actor_auth_user_id, p_actor_label, p_run_label);
$wrap$;

comment on function public.run_loyalty_earning_evaluation_sweep(uuid, timestamptz, uuid, text, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_loyalty_earning_evaluation_sweep, never a reimplementation.';

revoke execute on function public.run_loyalty_earning_evaluation_sweep(uuid, timestamptz, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.run_loyalty_earning_evaluation_sweep(uuid, timestamptz, uuid, text, text) to authenticated, service_role;

create function public.run_loyalty_tier_recalculation_sweep(
  p_tenant_id uuid, p_as_of timestamptz default now(), p_actor_auth_user_id uuid default null,
  p_actor_label text default null, p_run_label text default null
)
returns table (job_id uuid, status text, run_label text, processed_count integer, skipped_count integer)
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.run_loyalty_tier_recalculation_sweep(p_tenant_id, p_as_of, p_actor_auth_user_id, p_actor_label, p_run_label);
$wrap$;

comment on function public.run_loyalty_tier_recalculation_sweep(uuid, timestamptz, uuid, text, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_loyalty_tier_recalculation_sweep, never a reimplementation.';

revoke execute on function public.run_loyalty_tier_recalculation_sweep(uuid, timestamptz, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.run_loyalty_tier_recalculation_sweep(uuid, timestamptz, uuid, text, text) to authenticated, service_role;

create function public.run_loyalty_points_posting_sweep(
  p_tenant_id uuid, p_as_of timestamptz default now(), p_actor_auth_user_id uuid default null,
  p_actor_label text default null, p_run_label text default null
)
returns table (job_id uuid, status text, run_label text, processed_count integer, skipped_count integer)
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.run_loyalty_points_posting_sweep(p_tenant_id, p_as_of, p_actor_auth_user_id, p_actor_label, p_run_label);
$wrap$;

comment on function public.run_loyalty_points_posting_sweep(uuid, timestamptz, uuid, text, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_loyalty_points_posting_sweep, never a reimplementation.';

revoke execute on function public.run_loyalty_points_posting_sweep(uuid, timestamptz, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.run_loyalty_points_posting_sweep(uuid, timestamptz, uuid, text, text) to authenticated, service_role;

-- ===========================================================================
-- 6. The catalogue rows, and the dispatch branches that make them real.
--
-- `tenant_admin_configurable = true` for all three, on the same question the original
-- catalogue asked: is this the tenant's own business rhythm, or the platform's? How often
-- a loyalty programme awards points, moves members between tiers, and converts earnings
-- into spendable lots is the tenant's own commercial policy, exactly like the two loyalty
-- expiry tasks already in the catalogue.
--
-- min_interval_minutes = 60 rather than 5: each of these walks a whole tenant's invoices,
-- enrolments or earning events, and none of them is answering a service-level clock. A
-- floor that permits a five-minute cadence would invite a schedule that costs far more
-- than it can possibly earn.
-- ===========================================================================

insert into app.scheduled_task_definitions
  (task_code, display_name, description, tenant_admin_configurable, min_interval_minutes, default_interval_minutes, required_params)
values
  ('loyalty_earning_evaluation_sweep', 'Loyalty earning evaluation',
   'Evaluates loyalty earning for every fully-paid invoice not yet evaluated.', true, 60, 1440, '{}'),
  ('loyalty_tier_recalculation_sweep', 'Loyalty tier recalculation',
   'Recalculates the membership tier of every active loyalty account.', true, 60, 1440, '{}'),
  ('loyalty_points_posting_sweep', 'Loyalty points posting',
   'Converts points-type earning events into point lots that customers can spend.', true, 60, 1440, '{}')
on conflict (task_code) do nothing;

-- Same signature, so `create or replace` genuinely replaces rather than overloading
-- (ISS-2026-260). Three new branches; every existing branch is byte-identical.
create or replace function app._run_scheduled_task_once(p_schedule app.tenant_scheduled_tasks, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_actor uuid := p_schedule.authorized_by_auth_user_id;
  v_label text := 'scheduler:' || p_schedule.task_code;
  v_period text := to_char(p_now, 'YYYY-MM-DD');
begin
  case p_schedule.task_code
    when 'loyalty_expiry_sweep' then
      perform app.run_loyalty_expiry_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_point_lot_expiry' then
      perform app.expire_loyalty_point_lots(p_schedule.tenant_id, v_actor, v_label, p_now);
    when 'loyalty_benefit_entitlement_expiry' then
      perform app.expire_loyalty_benefit_entitlements(p_schedule.tenant_id, v_actor, v_label, p_now);
    when 'loyalty_earning_evaluation_sweep' then
      perform app.run_loyalty_earning_evaluation_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_tier_recalculation_sweep' then
      perform app.run_loyalty_tier_recalculation_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_points_posting_sweep' then
      perform app.run_loyalty_points_posting_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'employee_position_activation' then
      perform app.activate_due_employee_position_assignments(p_schedule.tenant_id, v_actor, v_label);
    when 'leave_accrual_batch' then
      perform app.run_leave_accrual_batch(
        p_schedule.tenant_id, (p_schedule.params ->> 'leave_type_id')::uuid, p_now::date, v_period, v_actor, v_label);
    when 'leave_carry_forward_batch' then
      perform app.run_leave_carry_forward_batch(
        p_schedule.tenant_id, (p_schedule.params ->> 'leave_type_id')::uuid, p_now::date, v_period, v_actor, v_label);
    when 'training_certificate_expiry' then
      perform app.run_training_certificate_expiry_batch(p_schedule.tenant_id, p_now::date, v_period, v_actor, v_label);
    when 'training_certificate_expiry_reminder' then
      perform app.run_training_certificate_expiry_reminder_batch(
        p_schedule.tenant_id, p_now::date, (p_schedule.params ->> 'lookahead_days')::integer, v_period, v_actor, v_label);
    when 'incident_escalation_sweep' then
      perform app.run_incident_escalation_sweep(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'ticket_sla_evaluation' then
      perform app.run_ticket_sla_evaluation_batch(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'ticket_escalation_evaluation' then
      perform app.run_ticket_escalation_evaluation_batch(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    -- ISS-2026-249
    when 'authority_denial_anomaly_sweep' then
      perform app.run_authority_denial_anomaly_sweep(
        p_schedule.tenant_id, p_now,
        (p_schedule.params ->> 'window_minutes')::integer,
        (p_schedule.params ->> 'threshold')::integer,
        v_actor, v_label);
    -- ISS-2026-313
    when 'employee_lifecycle_activation' then
      perform app.activate_due_employee_lifecycle_transitions(p_schedule.tenant_id, v_actor, v_label);
    when 'kb_article_version_expiry' then
      perform app.expire_kb_article_versions_batch(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'vendor_compliance_waiver_expiry' then
      perform app.expire_vendor_compliance_waivers(
        p_schedule.tenant_id, v_actor, v_label, (p_schedule.params ->> 'max_rows')::integer);
    when 'vendor_compliance_status_refresh' then
      perform app.recalculate_tenant_vendor_compliance_status(
        p_schedule.tenant_id, v_actor, v_label, (p_schedule.params ->> 'max_vendors')::integer);
    else
      raise exception 'scheduled_task_not_dispatchable: % has a catalogue row but no dispatch branch', p_schedule.task_code
        using errcode = 'check_violation';
  end case;
end;
$$;

comment on function app._run_scheduled_task_once is
  'Internal (app._ prefix, service_role-only): the explicit per-task dispatch, now nineteen enumerated calls after ISS-2026-126/127/128 added the three loyalty sweeps. Deliberately a CASE rather than dynamic SQL assembled from the row -- task_code is catalogue-controlled today, but a scheduler that EXECUTEs a statement built from a table column is one bad migration away from an injection surface. Every call passes the schedule''s own authorized_by_auth_user_id as the actor, which is what makes a scheduled run attributable to a person. A catalogue row with no dispatch branch raises rather than silently doing nothing.';

revoke execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) from public, anon, authenticated;
grant execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) to service_role;
