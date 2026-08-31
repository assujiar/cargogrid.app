-- Closes `ISS-2026-314`, and the finding is bigger than that entry could see.
--
-- `ISS-2026-314` recorded that `scripts/db-tests/scheduled-reports.sql`'s two-process race
-- assertion fails intermittently — two concurrent callers advanced `next_run_at` by two steps
-- instead of one — and stated honestly that the evidence "cannot distinguish 'the product races'
-- from 'the test's synchronisation is fragile'". It can now, and the answer is neither.
--
-- ROOT CAUSE: THE RACE ONLY MADE A SINGLE-CALLER DEFECT VISIBLE
--
--   `app.run_scheduled_report` advances `next_run_at` by exactly one step **on every call**,
--   with no check that the occurrence it just processed was actually due. `app.create_scheduled_
--   report` computes `next_run_at` as the next FUTURE occurrence. So the very first manual "Run
--   now" on a fresh schedule processes tomorrow's occurrence and moves the schedule past it —
--   **the scheduled delivery that occurrence represented never happens.**
--
--   One click silently eats one future delivery. Two concurrent clicks eat two, which is what the
--   race test caught. The concurrency was the messenger, not the message.
--
--   The intermittency has a mechanism too, and it is why this looked like a flake. The existing
--   staleness guard compares an **unlocked** pre-read against the locked row. It catches a second
--   caller only when that caller's unlocked read happened before the winner committed. A caller
--   arriving a moment later reads the already-advanced value, finds nothing to complain about, and
--   processes the NEXT occurrence. The failure window is exactly the width of that read-then-lock
--   gap — narrow, timing-dependent, and entirely real.
--
--   No lock closes it, because it is not a locking problem: a caller arriving after the winner
--   commits is indistinguishable from a legitimate second trigger. The fix has to be about which
--   occurrences may move the schedule, not about who got there first.
--
-- THE FIX: A TRIGGER ONLY ADVANCES THE SCHEDULE IF IT WAS ACTUALLY DUE
--
--   "Run now" keeps working exactly as before — the run row is created, the job is enqueued,
--   recipients are re-authorised and notified. What it no longer does is consume a future
--   occurrence. `next_run_at` moves only when the occurrence being processed had genuinely
--   arrived (`<= now()`), which is the only case where moving past it is right.
--
--   This function's own existing comment already named the harm ("silently skipping the real next
--   due date"); it simply enforced it through a timing-dependent guard rather than directly.
--
--   The concurrent case then becomes deterministic rather than lucky:
--     * occurrence not yet due — neither caller advances; both land on the same occurrence, where
--       the `(scheduled_report_id, occurrence_at)` unique index and the occurrence-derived
--       idempotency key already collapse them to one run and one job.
--     * occurrence due — one caller advances, and the second either hits the staleness guard and
--       returns the winner's run, or reads the advanced value, finds it in the future, and does
--       not advance either.
--   Two steps is no longer reachable by any interleaving.
--
-- `create or replace`, same signature: no call site changes, and `server/mutations/
-- scheduled-report.ts` needs no edit.

create or replace function app.run_scheduled_report(
  p_scheduled_report_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.scheduled_report_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_schedule app.scheduled_reports;
  v_decision app.rbac_decision;
  v_job app.jobs;
  v_run app.scheduled_report_runs;
  v_recipient record;
  v_total integer := 0;
  v_reauthorized integer := 0;
  v_denied integer := 0;
  v_idempotency_key text;
  v_config_version_id uuid;
  v_intended_occurrence timestamptz;
  v_report_type_version_id uuid;
  v_occurrence_was_due boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select next_run_at into v_intended_occurrence from app.scheduled_reports where id = p_scheduled_report_id;

  select * into v_schedule from app.scheduled_reports where id = p_scheduled_report_id for update;
  if not found then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;
  if v_schedule.status <> 'active' then
    raise exception 'scheduled_report_not_active: % is %, only an active schedule may run', p_scheduled_report_id, v_schedule.status using errcode = 'check_violation';
  end if;

  if not (app.has_active_tenant_membership(v_schedule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_schedule.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_schedule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Retained from the original Tier C fix: still the right answer when a concurrent winner
  -- advanced a genuinely due occurrence out from under this caller. It is no longer load-bearing
  -- for correctness on its own -- see the header -- because it can only catch the interleavings
  -- where this caller's unlocked pre-read happened to land before the winner committed.
  if v_intended_occurrence is not null and v_schedule.next_run_at <> v_intended_occurrence then
    select * into v_run from app.scheduled_report_runs
    where scheduled_report_id = p_scheduled_report_id and occurrence_at = v_intended_occurrence;
    if found then
      return v_run;
    end if;
    raise exception 'scheduled_report_occurrence_already_advanced: % was concurrently advanced past the occurrence this request observed (%) -- retry to trigger the current occurrence', p_scheduled_report_id, v_intended_occurrence
      using errcode = 'serialization_failure';
  end if;

  -- ISS-2026-314. Decided once, here, against the locked row, and used only to gate the advance
  -- at the very end. Everything between is unchanged: an early trigger still produces a real run,
  -- a real job, and real notifications -- it simply does not consume the occurrence it borrowed.
  v_occurrence_was_due := v_schedule.next_run_at is not null and v_schedule.next_run_at <= now();

  v_idempotency_key := 'scheduled-report-' || p_scheduled_report_id || '-' || to_char(v_schedule.next_run_at, 'YYYYMMDDHH24MI');

  v_job := app.enqueue_job(
    v_schedule.tenant_id, 'report_generation',
    jsonb_build_object('scheduled_report_id', p_scheduled_report_id, 'report_type_code', v_schedule.report_type_code, 'filters', v_schedule.filters),
    0, v_idempotency_key, 3, p_actor_auth_user_id, p_actor_label
  );

  select id into v_report_type_version_id from app.report_type_versions
  where report_type_code = v_schedule.report_type_code order by version_number desc limit 1;

  if not exists (select 1 from app.report_runs where job_id = v_job.job_id) then
    insert into app.report_runs (
      tenant_id, report_type_code, run_type, status, parameters, job_id,
      report_type_version_id, requested_by_auth_user_id, created_by
    ) values (
      v_schedule.tenant_id, v_schedule.report_type_code, 'export', 'queued', v_schedule.filters, v_job.job_id,
      v_report_type_version_id, p_actor_auth_user_id, p_actor_label
    );
  end if;

  insert into app.scheduled_report_runs (scheduled_report_id, job_id, occurrence_at, artifact_expires_at, triggered_by_auth_user_id, triggered_by_label)
  values (p_scheduled_report_id, v_job.job_id, v_schedule.next_run_at, now() + interval '7 days', p_actor_auth_user_id, p_actor_label)
  on conflict (scheduled_report_id, occurrence_at) do update set scheduled_report_id = excluded.scheduled_report_id
  returning * into v_run;

  select resolved_version_id into v_config_version_id
  from app.resolve_config('notification:scheduled_report_ready', v_schedule.tenant_id);

  for v_recipient in select * from app.scheduled_report_recipients where scheduled_report_id = p_scheduled_report_id loop
    v_total := v_total + 1;
    if app.has_active_tenant_membership(v_schedule.tenant_id, v_recipient.recipient_auth_user_id)
      and not app.actor_holds_customer_user_layer(v_schedule.tenant_id, v_recipient.recipient_auth_user_id)
    then
      v_reauthorized := v_reauthorized + 1;
      if v_config_version_id is not null then
        perform app.queue_notification(
          v_config_version_id, v_schedule.tenant_id, 'scheduled_report_ready', v_recipient.recipient_auth_user_id,
          'in_app', 'en', jsonb_build_object('scheduledReportName', v_schedule.name, 'runId', v_run.id),
          'scheduled-report-run-' || p_scheduled_report_id || '-' || to_char(v_schedule.next_run_at, 'YYYYMMDDHH24MI') || '-' || v_recipient.recipient_auth_user_id,
          p_actor_auth_user_id, p_actor_label
        );
      end if;
    else
      v_denied := v_denied + 1;
    end if;
  end loop;

  update app.scheduled_report_runs
  set recipients_total = v_total, recipients_reauthorized = v_reauthorized, recipients_denied = v_denied
  where id = v_run.id
  returning * into v_run;

  -- ISS-2026-314: the one behavioural change. last_run_at is stamped either way -- the run really
  -- did happen -- but next_run_at moves only for an occurrence that had actually arrived. An
  -- early trigger borrows the occurrence; it no longer swallows it.
  if v_occurrence_was_due then
    update app.scheduled_reports
    set last_run_at = now(), next_run_at = app.compute_scheduled_report_next_run(cron_minute, cron_hour, cron_day_of_month, cron_day_of_week, timezone, v_schedule.next_run_at)
    where id = p_scheduled_report_id;
  else
    update app.scheduled_reports set last_run_at = now() where id = p_scheduled_report_id;
  end if;

  perform app.capture_audit_event(
    v_schedule.tenant_id, p_actor_auth_user_id, p_actor_label, 'run_scheduled_report',
    'app.scheduled_report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('occurrence_at', v_schedule.next_run_at, 'occurrence_was_due', v_occurrence_was_due, 'job_id', v_job.job_id)
  );

  return v_run;
end;
$$;

comment on function app.run_scheduled_report is
  'IAE-006: triggers a scheduled report for its current occurrence -- REP:Configure, tenant-scoped, recipients re-authorised at run time (Prompt 334 §24), job and run row both idempotent on the occurrence. ISS-2026-314 (20260831200000): next_run_at now advances ONLY when the occurrence processed had actually arrived. Before this, every call advanced unconditionally, so a single early "Run now" on a fresh schedule silently consumed the upcoming occurrence and that scheduled delivery never happened; two concurrent clicks consumed two, which is how the db-test race caught it intermittently. The race was the messenger, not the message -- and no lock could have fixed it, because a caller arriving after the winner commits is indistinguishable from a legitimate second trigger. An early trigger still produces a real run, job and notifications; it simply borrows the occurrence instead of swallowing it.';
