-- ISS-2026-134 item 4 (docs/runtime/KNOWN_ISSUES.md), the engagement-metrics half -- the entry's
-- last remaining open item.
--
-- Item 4 reads: "app.execute_loyalty_liability_reconciliation_run / app.get_loyalty_engagement_
-- metrics are on-demand/staff-triggered only". Its reconciliation half was closed 2026-08-31 by
-- 20260831240000, which registered a real `loyalty_liability_reconciliation` task on the
-- tenant-configurable scheduler (20260831090000). The engagement-metrics half stayed open, and
-- every update since has said so plainly rather than rounding the item to closed.
--
-- ===========================================================================
-- Why this needs a snapshot table rather than just a catalogue row
-- ===========================================================================
--
-- The reconciliation half was schedulable as-is because app.execute_loyalty_liability_
-- reconciliation_run WRITES a row -- scheduling it produces a durable artefact. app.get_loyalty_
-- engagement_metrics does not: it is `stable`, it computes over a caller-supplied window and
-- RETURNS the numbers. Registering that on a scheduler would compute a result and throw it away
-- on every fire -- a catalogue row that looks like coverage and delivers nothing. What item 4
-- actually needs is the thing a schedule is FOR: a series of dated measurements a tenant can look
-- back over. So this migration adds the missing durable half -- a snapshot table and a sweep that
-- persists into it -- and registers THAT.
--
-- The metric arithmetic itself is NOT reimplemented. The sweep calls app.get_loyalty_engagement_
-- metrics and stores what it returns, so a snapshot can never drift from what the on-demand read
-- reports for the same window; the read RPC remains the single definition of every metric.
--
-- ===========================================================================
-- Live schema re-verified before writing this file
-- ===========================================================================
--
--   * app._run_scheduled_task_once currently dispatches 22 task_code branches, confirmed via
--     pg_get_functiondef on the hosted project and diffed against the repo's own latest definer
--     (20260902221000) -- byte-identical. It is reproduced below from that live text plus exactly
--     one branch, never retyped: a 22-branch CASE rebuilt by hand is how a branch silently goes
--     missing, and the `else` arm would then raise on a task that used to work.
--   * app.get_loyalty_engagement_metrics(uuid, timestamptz, timestamptz, uuid) is unchanged since
--     20260801250000: LYL:View-gated, `stable`, session-identity-asserted, and it rejects a
--     customer_user caller outright rather than handing back a zeroed row. This migration calls it
--     exactly as a staff caller would and inherits all of that; it adds no second authority path.
--   * app.scheduled_task_definitions carries 22 active rows; this migration makes it 23, which is
--     why scripts/db-tests/task-scheduler.sql's own catalogue-count assertion moves with it.
--
-- ===========================================================================
-- What this migration deliberately does NOT do
-- ===========================================================================
--
-- It does not turn any schedule on. `pg_cron` is still not installed on the live project, and
-- ISS-2026-066's own entry already records that pointing a trigger at app.run_due_scheduled_tasks
-- is a deliberate operator decision, not a migration's to take. What exists after this migration
-- is the mechanism, the catalogue entry, the authority model and the durable artefact -- the same
-- boundary every sibling sweep in this repository already sits behind, unchanged.

-- ===========================================================================
-- STEP 1: the durable artefact.
--
-- `unique (tenant_id, idempotency_key)` mirrors app.loyalty_liability_reconciliation_runs
-- exactly, and is what makes a replayed scheduler fire a no-op instead of a duplicate
-- measurement. window_days is stored, not merely used: a snapshot series is only comparable
-- across rows if you can see which rows measured the same window.
-- ===========================================================================

create table app.loyalty_engagement_metric_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  period_start timestamptz not null,
  period_end timestamptz not null,
  window_days integer not null,
  active_loyalty_accounts_count integer not null default 0,
  points_earned_total numeric not null default 0,
  points_redeemed_total numeric not null default 0,
  redemption_count integer not null default 0,
  redemption_rate numeric not null default 0,
  published_reward_count integer not null default 0,
  rewards_with_redemption_count integer not null default 0,
  computed_at timestamptz not null default clock_timestamp(),
  idempotency_key text not null,
  captured_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lems_period_order_check check (period_start < period_end),
  constraint lems_window_days_check check (window_days >= 1),
  constraint lems_active_accounts_check check (active_loyalty_accounts_count >= 0),
  constraint lems_points_earned_check check (points_earned_total >= 0),
  constraint lems_points_redeemed_check check (points_redeemed_total >= 0),
  constraint lems_redemption_count_check check (redemption_count >= 0),
  constraint lems_redemption_rate_check check (redemption_rate >= 0),
  constraint lems_published_rewards_check check (published_reward_count >= 0),
  constraint lems_rewards_with_redemption_check check (rewards_with_redemption_count >= 0),
  constraint lems_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.loyalty_engagement_metric_snapshots is
  'ISS-2026-134 item 4: a dated series of loyalty engagement measurements, which is what makes app.get_loyalty_engagement_metrics schedulable at all -- that RPC is stable and returns its numbers rather than storing them, so a schedule over it alone would compute a result and discard it every fire. Every column is stored exactly as app.get_loyalty_engagement_metrics returned it for the window: this table never recomputes a metric, so a snapshot cannot drift from what the on-demand read reports. unique (tenant_id, idempotency_key) makes a replayed scheduler fire a no-op rather than a duplicate measurement, mirroring app.loyalty_liability_reconciliation_runs exactly.';

create index loyalty_engagement_metric_snapshots_tenant_period_idx
  on app.loyalty_engagement_metric_snapshots (tenant_id, period_end desc, id desc);

create function app.touch_loyalty_engagement_metric_snapshot_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_engagement_metric_snapshots_touch_row
  before update on app.loyalty_engagement_metric_snapshots
  for each row
  execute function app.touch_loyalty_engagement_metric_snapshot_row();

-- ===========================================================================
-- STEP 2: the sweep. Authority is app.get_loyalty_engagement_metrics' own LYL:View gate,
-- inherited by calling it rather than re-asserted here -- a second authority check in front of
-- an already-gated read is how the two drift apart later.
-- ===========================================================================

create function app.run_loyalty_engagement_metrics_snapshot(
  p_tenant_id uuid,
  p_now timestamptz,
  p_window_days integer,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_idempotency_key text
)
returns app.loyalty_engagement_metric_snapshots
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_window_days integer := coalesce(p_window_days, 30);
  v_period_end timestamptz := coalesce(p_now, clock_timestamp());
  v_period_start timestamptz;
  v_metrics record;
  v_row app.loyalty_engagement_metric_snapshots;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty p_idempotency_key is required' using errcode = 'check_violation';
  end if;

  if v_window_days < 1 then
    raise exception 'invalid_window: p_window_days must be at least 1, got %', v_window_days using errcode = 'check_violation';
  end if;

  -- Replay check BEFORE computing: a scheduler that re-fires for a window it already captured
  -- should cost nothing and change nothing, and should hand back the measurement it already
  -- made rather than a second one taken at a different instant.
  select * into v_row from app.loyalty_engagement_metric_snapshots
  where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_row;
  end if;

  v_period_start := v_period_end - make_interval(days => v_window_days);

  -- The one and only source of every number below. Its own LYL:View gate, session-identity
  -- assertion and customer_user rejection all apply to this call unchanged.
  select * into v_metrics
  from app.get_loyalty_engagement_metrics(p_tenant_id, v_period_start, v_period_end, p_actor_auth_user_id);

  insert into app.loyalty_engagement_metric_snapshots (
    tenant_id, period_start, period_end, window_days,
    active_loyalty_accounts_count, points_earned_total, points_redeemed_total,
    redemption_count, redemption_rate, published_reward_count, rewards_with_redemption_count,
    computed_at, idempotency_key, captured_by
  )
  values (
    p_tenant_id, v_metrics.period_start, v_metrics.period_end, v_window_days,
    v_metrics.active_loyalty_accounts_count, v_metrics.points_earned_total, v_metrics.points_redeemed_total,
    v_metrics.redemption_count, v_metrics.redemption_rate, v_metrics.published_reward_count,
    v_metrics.rewards_with_redemption_count,
    v_metrics.computed_at, p_idempotency_key, p_actor_label
  )
  -- A concurrent caller sharing the same key wins the race and this one re-reads its row,
  -- rather than both raising -- the same atomic shape app.queue_notification (PLT-127) uses.
  on conflict (tenant_id, idempotency_key) do nothing
  returning * into v_row;

  if not found then
    select * into v_row from app.loyalty_engagement_metric_snapshots
    where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    return v_row;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_loyalty_engagement_metrics_snapshot',
    'app.loyalty_engagement_metric_snapshots', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.run_loyalty_engagement_metrics_snapshot(uuid, timestamptz, integer, uuid, text, text) is
  'ISS-2026-134 item 4: captures one dated loyalty-engagement measurement over the trailing p_window_days and persists it, which is what makes the metrics schedulable -- app.get_loyalty_engagement_metrics itself is stable and returns rather than stores. Every number comes from that RPC, never recomputed here, so a snapshot cannot disagree with the on-demand read for the same window. Authority is that RPC''s own LYL:View gate, inherited by calling it rather than re-asserted -- a duplicated check is how two authority rules drift apart. Idempotent per (tenant, idempotency_key): a replayed scheduler fire returns the measurement already taken instead of a second one at a different instant.';

-- ===========================================================================
-- STEP 3: the read side. Same cursor-paginated shape as
-- app.list_loyalty_liability_reconciliation_runs, so the snapshot series is queryable the way
-- every other Loyalty artefact in this repository already is.
-- ===========================================================================

create function app.list_loyalty_engagement_metric_snapshots(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_window_days integer default null,
  p_cursor_period_end timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_engagement_metric_snapshots
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Staff-only, same bar as the metrics themselves: this is tenant-internal analytics, and a
  -- customer_user must not reach it through the snapshot series either.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select s.*
  from app.loyalty_engagement_metric_snapshots s
  where s.tenant_id = p_tenant_id
    and (p_window_days is null or s.window_days = p_window_days)
    and (
      p_cursor_period_end is null
      or s.period_end < p_cursor_period_end
      or (s.period_end = p_cursor_period_end and p_cursor_id is not null and s.id < p_cursor_id)
    )
  order by s.period_end desc, s.id desc
  limit v_limit;
end;
$$;

comment on function app.list_loyalty_engagement_metric_snapshots(uuid, uuid, integer, timestamptz, uuid, integer) is
  'ISS-2026-134 item 4: cursor-paginated read over the engagement-metric snapshot series, LYL:View-gated and session-identity-asserted -- the same staff-only bar app.get_loyalty_engagement_metrics itself applies, so a customer_user cannot reach tenant-internal analytics through the stored series either. Same (period_end, id) keyset shape as app.list_loyalty_liability_reconciliation_runs.';

-- ===========================================================================
-- STEP 4: the catalogue row.
--
-- tenant_admin_configurable = true, unlike its liability-reconciliation sibling and for the
-- reason that sibling's own migration gives: reconciliation produces the financial evidence a
-- certification decision rests on, which is platform governance; how often a tenant wants to
-- measure its own engagement rhythm is that tenant's commercial business, exactly like the
-- earning/tier/points-posting sweeps already delegated to it.
--
-- min_interval_minutes = 1440: a snapshot is a trailing-window measurement. Taking one hourly
-- over a 30-day window produces 24 near-identical rows a day and makes the series harder to read,
-- not fresher -- the same reasoning 20260831240000 gives for its own daily floor.
--
-- required_params = {window_days}: no default, deliberately. A window is the one thing that makes
-- two snapshots comparable or not, and silently defaulting it would produce a series whose rows
-- nobody can tell apart -- the same reasoning that made `currency` required on the liability task.
-- ===========================================================================

insert into app.scheduled_task_definitions
  (task_code, display_name, description, tenant_admin_configurable, min_interval_minutes, default_interval_minutes, required_params)
values
  ('loyalty_engagement_metrics_snapshot', 'Loyalty engagement metrics snapshot',
   'Captures a dated loyalty engagement measurement over a trailing window. Schedule one per window length the tenant reports on.',
   true, 1440, 1440, '{window_days}')
on conflict (task_code) do nothing;

-- ===========================================================================
-- STEP 5: the dispatcher, reproduced from its CURRENT LIVE definition (pg_get_functiondef,
-- confirmed byte-identical to the repo's own latest definer 20260902221000) plus exactly one
-- branch. Twenty-two existing branches unchanged.
-- ===========================================================================

CREATE OR REPLACE FUNCTION app._run_scheduled_task_once(p_schedule app.tenant_scheduled_tasks, p_now timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
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
    when 'loyalty_liability_reconciliation' then
      perform app.execute_loyalty_liability_reconciliation_run(
        p_schedule.tenant_id, p_now, p_schedule.params ->> 'currency', v_actor, v_label,
        'scheduler:' || p_schedule.task_code || ':' || (p_schedule.params ->> 'currency') || ':' || v_period, 1);
    -- ISS-2026-129 item 2:
    when 'loyalty_benefit_issuance_sweep' then
      perform app.run_loyalty_benefit_issuance_rule_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'employee_position_activation' then
      perform app.activate_due_employee_position_assignments(p_schedule.tenant_id, v_actor, v_label);
    when 'onboarding_offboarding_overdue_task_sweep' then
      perform app.run_onboarding_overdue_task_sweep(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
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
    when 'authority_denial_anomaly_sweep' then
      perform app.run_authority_denial_anomaly_sweep(
        p_schedule.tenant_id, p_now,
        (p_schedule.params ->> 'window_minutes')::integer,
        (p_schedule.params ->> 'threshold')::integer,
        v_actor, v_label);
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
    -- ISS-2026-134 item 4. The window length is a schedule parameter rather than a constant:
    -- a tenant watching a weekly engagement rhythm and one reporting a monthly board number
    -- want genuinely different windows, and hardcoding either would make the other's snapshot
    -- series useless. The idempotency key carries the window as well as the day, for the same
    -- reason the liability-reconciliation branch carries its currency -- two windows snapshotted
    -- on the same day are two different measurements, not a duplicate.
    when 'loyalty_engagement_metrics_snapshot' then
      perform app.run_loyalty_engagement_metrics_snapshot(
        p_schedule.tenant_id, p_now, (p_schedule.params ->> 'window_days')::integer, v_actor, v_label,
        'scheduler:' || p_schedule.task_code || ':' || (p_schedule.params ->> 'window_days') || ':' || v_period);
    else
      raise exception 'scheduled_task_not_dispatchable: % has a catalogue row but no dispatch branch', p_schedule.task_code
        using errcode = 'check_violation';
  end case;
end;
$function$;

comment on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) is
  'Internal (app._ prefix, service_role-only): the explicit per-task dispatch, now twenty-three enumerated calls after ISS-2026-134 item 4 added the loyalty engagement-metrics snapshot. Deliberately a CASE rather than dynamic SQL assembled from the row -- task_code is catalogue-controlled today, but a scheduler that EXECUTEs a statement built from a table column is one bad migration away from an injection surface. Every call passes the schedule''s own authorized_by_auth_user_id as the actor, which is what makes a scheduled run attributable to a person. A catalogue row with no dispatch branch raises rather than silently doing nothing.';

-- ===========================================================================
-- STEP 6: RLS and grants. Mirrors 20260801250000's own block exactly -- RLS on with no policy
-- (so nothing but service_role and SECURITY DEFINER functions read the table at all), the
-- standing per-migration PUBLIC-execute revoke, then the explicit role grants.
-- ===========================================================================

alter table app.loyalty_engagement_metric_snapshots enable row level security;

grant select, insert, update on app.loyalty_engagement_metric_snapshots to service_role;

revoke execute on all functions in schema app from public;

grant execute on function app.touch_loyalty_engagement_metric_snapshot_row() to service_role;
grant execute on function app.run_loyalty_engagement_metrics_snapshot(uuid, timestamptz, integer, uuid, text, text) to authenticated, service_role;
grant execute on function app.list_loyalty_engagement_metric_snapshots(uuid, uuid, integer, timestamptz, uuid, integer) to authenticated, service_role;

-- ===========================================================================
-- STEP 7: the RGL-394 Option-2 public.* wrappers. Every externally-callable app.* function needs
-- exactly one, and scripts/db-tests/public-api-wrapper-regression.sql enforces both directions --
-- it caught the omission of these two on the first run of this migration, which is precisely the
-- drift that check exists for. Thin security-definer pass-throughs, never reimplementations.
--
-- Both are granted to `authenticated` and not only `service_role` because both are genuinely
-- staff-callable, not scheduler-only: a LYL:View holder can take an ad-hoc snapshot and read the
-- series from the UI, exactly as the liability-reconciliation sibling already allows.
-- ===========================================================================

create function public.run_loyalty_engagement_metrics_snapshot(
  p_tenant_id uuid, p_now timestamptz, p_window_days integer,
  p_actor_auth_user_id uuid, p_actor_label text, p_idempotency_key text
)
returns app.loyalty_engagement_metric_snapshots
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.run_loyalty_engagement_metrics_snapshot(p_tenant_id, p_now, p_window_days, p_actor_auth_user_id, p_actor_label, p_idempotency_key);
$wrap$;

comment on function public.run_loyalty_engagement_metrics_snapshot(uuid, timestamptz, integer, uuid, text, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_loyalty_engagement_metrics_snapshot, never a reimplementation.';

revoke execute on function public.run_loyalty_engagement_metrics_snapshot(uuid, timestamptz, integer, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.run_loyalty_engagement_metrics_snapshot(uuid, timestamptz, integer, uuid, text, text) to authenticated, service_role;

create function public.list_loyalty_engagement_metric_snapshots(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_window_days integer default null,
  p_cursor_period_end timestamptz default null, p_cursor_id uuid default null, p_limit integer default 50
)
returns setof app.loyalty_engagement_metric_snapshots
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_loyalty_engagement_metric_snapshots(p_tenant_id, p_actor_auth_user_id, p_window_days, p_cursor_period_end, p_cursor_id, p_limit);
$wrap$;

comment on function public.list_loyalty_engagement_metric_snapshots(uuid, uuid, integer, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_loyalty_engagement_metric_snapshots, never a reimplementation.';

revoke execute on function public.list_loyalty_engagement_metric_snapshots(uuid, uuid, integer, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_loyalty_engagement_metric_snapshots(uuid, uuid, integer, timestamptz, uuid, integer) to authenticated, service_role;

-- Re-granted because the blanket revoke above strips it: the dispatcher is service_role-only and
-- must stay that way, exactly as 20260831230000 and 20260902221000 each re-grant it after their
-- own revoke.
revoke execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) from public, anon, authenticated;
grant execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) to service_role;
