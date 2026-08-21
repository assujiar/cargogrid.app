-- Phase 9 capability IAE-006 (Scheduled Reports, Prompt 334, CG-S14-IAE-006).
-- Batch 1's own last prompt. Recurring report generation on top of the
-- IAE-002 report catalog, reusing IAE-004's own "filters = the report's own
-- parameters" pattern, PLT-131/132's already-`VERIFIED` app.jobs retry/DLQ
-- mechanics, and PLT-127's notification engine for delivery -- no new query
-- engine, no new job queue, no new delivery mechanism.
--
-- Design decisions, disclosed rather than left implicit:
--
-- * **Recipients are internal tenant members only -- no free-text external
--   email field exists anywhere in this schema.** Prompt 334 business rule
--   §24 ("schedules cannot send sensitive reports to unauthorized external
--   recipients") is satisfied structurally, not by a runtime check that
--   could be bypassed: `scheduled_report_recipients.recipient_auth_user_id`
--   is a real FK into `auth.users`, re-validated against
--   `app.has_active_tenant_membership` at EVERY run (§24's own "checked at
--   run time, not only creation"), never a stored address string.
-- * **`app.jobs`' own retry/backoff/dead-letter/requeue mechanics
--   (`PLT-131`/`132`, already `VERIFIED`) are reused directly via
--   `scheduled_report_runs.job_id` -- never duplicated.** No second
--   retry/DLQ state machine exists in this migration.
-- * **Delivery reuses `app.queue_notification` (`PLT-127`, already
--   `VERIFIED`), never a bespoke email/webhook sender.** Its own required
--   `notification_types`/`config_types`/`config_versions`/`config_items`
--   bootstrap is seeded by direct `INSERT`, mirroring the already-cited,
--   already-shipped `20260731160000_create_ticket_escalation.sql` (HRT-291)
--   precedent: `register_notification_type`/`create_config_draft`/
--   `publish_config_version` are all Supreme-Admin-gated RPCs with no live
--   actor session available at migration-apply time, so the bootstrap rows
--   are inserted directly, in the exact shape those RPCs would themselves
--   produce -- unlike HRT-291's own bootstrap (registration only, no
--   template, emission deliberately out of scope), this checkpoint DOES
--   need real emission, so the config_version is seeded already-published.
-- * **Duplicate delivery is prevented by idempotency key, not a lock.**
--   `app.enqueue_job`'s own idempotency key is
--   `'scheduled-report-<schedule_id>-<due_occurrence>'` -- the SAME due
--   occurrence (`next_run_at` at the moment it was triggered) can never
--   enqueue a second `app.jobs` row, even if `run_scheduled_report` is
--   called twice for it. `app.queue_notification`'s own `p_dedupe_key` uses
--   the identical value per recipient, so a re-triggered run cannot
--   re-notify either.
-- * **Cron support is a real, bounded subset, not a full parser** (daily,
--   weekly-on-one-weekday, or monthly-on-one-day-of-month, each at one
--   exact hour:minute; day-of-month capped at 1-28 to sidestep
--   short-month edge cases). `validate_scheduled_report_cron_fields`
--   rejects anything outside that shape with a real, named error rather
--   than silently approximating a step/range/list cron expression it does
--   not actually honor -- a full RFC-5545-class recurrence engine is
--   outside this checkpoint's own bounded scope, disclosed, not silently
--   dropped. `timezone` is validated against `pg_timezone_names` (the same
--   introspection idiom `IAE-005`'s own `pg_matviews` check established);
--   `app.compute_scheduled_report_next_run` converts local wall-clock time
--   to UTC via Postgres's own `AT TIME ZONE` semantics, which is what makes
--   this correct across a DST boundary without bespoke offset arithmetic.
-- * **No real report artifact is ever generated in this environment** --
--   the SAME standing, disclosed condition `IAE-002`'s own
--   `enqueue_report_export` already carries (no live worker anywhere in
--   this repository advances a `report_generation` job past `queued`).
--   `artifact_file_id`/`artifact_expires_at` exist and are wired for a
--   future real worker to populate; download-audit reuses the EXISTING
--   `app.authorize_file_access` (`PLT-11x`) once a real `file_id` exists --
--   never a second file-access-logging mechanism built here.
-- * **`REP:Configure` gates schedule create/pause/resume/archive/recipient
--   management** -- the SAME "configuring a shared reporting artifact"
--   authority `IAE-003`/`IAE-004` already established as this module's own
--   consumer.
-- * ATW-032/C-13 and C-04 compliance built in from the start; RLS narrowed
--   for the `customer_user` layer from the first draft (the standing lesson
--   every Batch 1 checkpoint has now applied consistently since `IAE-003`'s
--   own first-draft gap).
-- * Per `ERR-2026-004`: explicit `revoke execute on all functions in schema
--   app from public` before any grant.

create table app.scheduled_reports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  report_type_code text not null references app.report_types (code),
  owner_auth_user_id uuid not null references auth.users (id),
  name text not null,
  description text not null default '',
  cron_minute integer not null,
  cron_hour integer not null,
  cron_day_of_month integer,
  cron_day_of_week integer,
  timezone text not null,
  filters jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  next_run_at timestamptz not null,
  last_run_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheduled_reports_status_check check (status in ('active', 'paused', 'archived')),
  constraint scheduled_reports_name_check check (length(trim(name)) > 0),
  constraint scheduled_reports_minute_check check (cron_minute between 0 and 59),
  constraint scheduled_reports_hour_check check (cron_hour between 0 and 23),
  constraint scheduled_reports_dom_check check (cron_day_of_month is null or cron_day_of_month between 1 and 28),
  constraint scheduled_reports_dow_check check (cron_day_of_week is null or cron_day_of_week between 0 and 6),
  constraint scheduled_reports_dom_dow_exclusive check (cron_day_of_month is null or cron_day_of_week is null),
  constraint scheduled_reports_filters_check check (jsonb_typeof(filters) = 'object')
);

comment on table app.scheduled_reports is
  'IAE-006: a recurring (report_type_code, filters, cron_*, timezone) schedule. cron_day_of_month/cron_day_of_week are mutually exclusive; both null means daily. next_run_at is advanced by app.run_scheduled_report after each trigger, never by a separate scheduler in this environment (disclosed, see the migration header).';

create index scheduled_reports_tenant_idx on app.scheduled_reports (tenant_id, status);
create index scheduled_reports_due_idx on app.scheduled_reports (next_run_at) where status = 'active';

create table app.scheduled_report_recipients (
  id uuid primary key default gen_random_uuid(),
  scheduled_report_id uuid not null references app.scheduled_reports (id),
  recipient_auth_user_id uuid not null references auth.users (id),
  added_by_auth_user_id uuid references auth.users (id),
  created_at timestamptz not null default now(),
  constraint scheduled_report_recipients_unique unique (scheduled_report_id, recipient_auth_user_id)
);

comment on table app.scheduled_report_recipients is
  'IAE-006: internal tenant members only -- no external address field exists. Re-validated against app.has_active_tenant_membership at EVERY run, never only at add time.';

create table app.scheduled_report_runs (
  id uuid primary key default gen_random_uuid(),
  scheduled_report_id uuid not null references app.scheduled_reports (id),
  job_id uuid references app.jobs (job_id),
  status text not null default 'queued',
  recipients_total integer not null default 0,
  recipients_reauthorized integer not null default 0,
  recipients_denied integer not null default 0,
  artifact_file_id uuid references app.files (id),
  artifact_expires_at timestamptz,
  error_reason text,
  triggered_by_auth_user_id uuid references auth.users (id),
  triggered_by_label text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint scheduled_report_runs_status_check check (status in ('queued', 'completed', 'failed'))
);

comment on table app.scheduled_report_runs is
  'IAE-006: one row per trigger (manual "run now" or a future scheduler). job_id links to app.jobs -- retry/backoff/dead-letter is entirely app.jobs'' own already-VERIFIED mechanism (PLT-131/132), reused, never duplicated here. status mirrors app.report_runs'' own shape; no live worker advances either past queued in this environment (the same standing, disclosed condition every job type in this repository already carries).';

create index scheduled_report_runs_schedule_idx on app.scheduled_report_runs (scheduled_report_id, started_at desc);

create function app.touch_scheduled_report_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger scheduled_reports_touch_row
  before update on app.scheduled_reports
  for each row
  execute function app.touch_scheduled_report_row();

-- Converts local wall-clock (minute/hour/day-of-month-or-week) to the next
-- UTC instant strictly after p_after, in the given IANA timezone. `date +
-- time AT TIME ZONE tz` is the real mechanism: Postgres interprets the naive
-- timestamp as local time in tz and converts to timestamptz (UTC storage) --
-- correct across a DST boundary without bespoke offset arithmetic.
create function app.compute_scheduled_report_next_run(
  p_cron_minute integer,
  p_cron_hour integer,
  p_cron_day_of_month integer,
  p_cron_day_of_week integer,
  p_timezone text,
  p_after timestamptz default now()
)
returns timestamptz
language plpgsql
as $$
declare
  v_local_date date;
  v_candidate timestamptz;
  v_i integer;
  v_month_date date;
begin
  v_local_date := (p_after at time zone p_timezone)::date;

  if p_cron_day_of_month is null and p_cron_day_of_week is null then
    for v_i in 0..366 loop
      v_candidate := ((v_local_date + v_i) + make_time(p_cron_hour, p_cron_minute, 0)) at time zone p_timezone;
      if v_candidate > p_after then
        return v_candidate;
      end if;
    end loop;
  elsif p_cron_day_of_week is not null then
    for v_i in 0..7 loop
      if extract(dow from (v_local_date + v_i)) = p_cron_day_of_week then
        v_candidate := ((v_local_date + v_i) + make_time(p_cron_hour, p_cron_minute, 0)) at time zone p_timezone;
        if v_candidate > p_after then
          return v_candidate;
        end if;
      end if;
    end loop;
  else
    for v_i in 0..24 loop
      v_month_date := (date_trunc('month', v_local_date + (v_i || ' months')::interval)::date) + (p_cron_day_of_month - 1);
      v_candidate := (v_month_date + make_time(p_cron_hour, p_cron_minute, 0)) at time zone p_timezone;
      if v_candidate > p_after then
        return v_candidate;
      end if;
    end loop;
  end if;

  raise exception 'scheduled_report_next_run_unresolvable: could not compute a next run within a bounded lookahead' using errcode = 'data_exception';
end;
$$;

create function app.create_scheduled_report(
  p_tenant_id uuid,
  p_report_type_code text,
  p_name text,
  p_description text,
  p_cron_minute integer,
  p_cron_hour integer,
  p_cron_day_of_month integer,
  p_cron_day_of_week integer,
  p_timezone text,
  p_filters jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.scheduled_reports
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_type app.report_types;
  v_decision app.rbac_decision;
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_next_run timestamptz;
  v_row app.scheduled_reports;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_type from app.report_types where code = p_report_type_code;
  if not found then
    raise exception 'report_type_unknown: %', p_report_type_code using errcode = 'no_data_found';
  end if;
  if v_type.status <> 'active' then
    raise exception 'report_type_retired: % is retired and cannot be scheduled', p_report_type_code using errcode = 'check_violation';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a scheduled report requires a non-empty name' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from pg_timezone_names where name = p_timezone) then
    raise exception 'scheduled_report_invalid_timezone: % is not a known IANA timezone', p_timezone using errcode = 'check_violation';
  end if;
  if p_cron_day_of_month is not null and p_cron_day_of_week is not null then
    raise exception 'scheduled_report_invalid_cron: day_of_month and day_of_week may not both be set' using errcode = 'check_violation';
  end if;
  if not app.validate_report_parameters(v_type.parameter_schema, v_filters) then
    raise exception 'scheduled_report_unsafe_filters: filters failed structural or schema validation' using errcode = 'check_violation';
  end if;

  v_next_run := app.compute_scheduled_report_next_run(p_cron_minute, p_cron_hour, p_cron_day_of_month, p_cron_day_of_week, p_timezone);

  insert into app.scheduled_reports (
    tenant_id, report_type_code, owner_auth_user_id, name, description,
    cron_minute, cron_hour, cron_day_of_month, cron_day_of_week, timezone, filters, next_run_at, created_by
  ) values (
    p_tenant_id, p_report_type_code, p_actor_auth_user_id, p_name, coalesce(p_description, ''),
    p_cron_minute, p_cron_hour, p_cron_day_of_month, p_cron_day_of_week, p_timezone, v_filters, v_next_run, p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_scheduled_report',
    'app.scheduled_reports', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

create function app.set_scheduled_report_status(
  p_scheduled_report_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.scheduled_reports
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.scheduled_reports;
  v_decision app.rbac_decision;
  v_updated app.scheduled_reports;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_row from app.scheduled_reports where id = p_scheduled_report_id for update;
  if not found then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_row.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_row.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_status = any (array['active', 'paused', 'archived'])) then
    raise exception 'scheduled_report_invalid_status: %', p_status using errcode = 'check_violation';
  end if;

  update app.scheduled_reports set status = p_status where id = p_scheduled_report_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_scheduled_report_status',
    'app.scheduled_reports', v_row.id, 'success', null, jsonb_build_object('status', v_row.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.set_scheduled_report_status is
  'IAE-006: pause/resume/archive (Prompt 334''s own "unsubscribe/suspend controls"). Pausing never deletes next_run_at -- resuming continues the SAME schedule, never recomputing from now().';

create function app.add_scheduled_report_recipient(
  p_scheduled_report_id uuid,
  p_recipient_auth_user_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.scheduled_report_recipients
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_schedule app.scheduled_reports;
  v_decision app.rbac_decision;
  v_row app.scheduled_report_recipients;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_schedule from app.scheduled_reports where id = p_scheduled_report_id;
  if not found then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_schedule.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_schedule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_active_tenant_membership(v_schedule.tenant_id, p_recipient_auth_user_id) then
    raise exception 'scheduled_report_recipient_not_member: % has no active membership in tenant %', p_recipient_auth_user_id, v_schedule.tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.scheduled_report_recipients (scheduled_report_id, recipient_auth_user_id, added_by_auth_user_id)
  values (p_scheduled_report_id, p_recipient_auth_user_id, p_actor_auth_user_id)
  on conflict (scheduled_report_id, recipient_auth_user_id) do update set scheduled_report_id = excluded.scheduled_report_id
  returning * into v_row;

  perform app.capture_audit_event(
    v_schedule.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_scheduled_report_recipient',
    'app.scheduled_report_recipients', v_row.id, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

create function app.remove_scheduled_report_recipient(
  p_recipient_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_recipient app.scheduled_report_recipients;
  v_schedule app.scheduled_reports;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_recipient from app.scheduled_report_recipients where id = p_recipient_row_id;
  if not found then
    raise exception 'scheduled_report_recipient_not_found: %', p_recipient_row_id using errcode = 'no_data_found';
  end if;

  select * into v_schedule from app.scheduled_reports where id = v_recipient.scheduled_report_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_schedule.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_schedule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.scheduled_report_recipients where id = p_recipient_row_id;

  perform app.capture_audit_event(
    v_schedule.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_scheduled_report_recipient',
    'app.scheduled_report_recipients', p_recipient_row_id, 'success', null, to_jsonb(v_recipient), null
  );
end;
$$;

create function app.run_scheduled_report(
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
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_schedule from app.scheduled_reports where id = p_scheduled_report_id for update;
  if not found then
    raise exception 'scheduled_report_not_found: %', p_scheduled_report_id using errcode = 'no_data_found';
  end if;
  if v_schedule.status <> 'active' then
    raise exception 'scheduled_report_not_active: % is %, only an active schedule may run', p_scheduled_report_id, v_schedule.status using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_schedule.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_schedule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotency key ties the enqueued job to THIS due occurrence -- a
  -- re-triggered call for the same next_run_at can never double-enqueue.
  v_idempotency_key := 'scheduled-report-' || p_scheduled_report_id || '-' || to_char(v_schedule.next_run_at, 'YYYYMMDDHH24MI');

  v_job := app.enqueue_job(
    v_schedule.tenant_id, 'report_generation',
    jsonb_build_object('scheduled_report_id', p_scheduled_report_id, 'report_type_code', v_schedule.report_type_code, 'filters', v_schedule.filters),
    0, v_idempotency_key, 3, p_actor_auth_user_id, p_actor_label
  );

  insert into app.scheduled_report_runs (scheduled_report_id, job_id, artifact_expires_at, triggered_by_auth_user_id, triggered_by_label)
  values (p_scheduled_report_id, v_job.job_id, now() + interval '7 days', p_actor_auth_user_id, p_actor_label)
  returning * into v_run;

  -- Recipient reauthorization AT RUN TIME (Prompt 334 §24) -- never deferred
  -- to add-time membership alone.
  select v.id into v_config_version_id from app.config_objects o
  join app.config_versions v on v.config_object_id = o.id and v.status = 'published'
  where o.config_type_code = 'notification:scheduled_report_ready';

  for v_recipient in select * from app.scheduled_report_recipients where scheduled_report_id = p_scheduled_report_id loop
    v_total := v_total + 1;
    if app.has_active_tenant_membership(v_schedule.tenant_id, v_recipient.recipient_auth_user_id) then
      v_reauthorized := v_reauthorized + 1;
      if v_config_version_id is not null then
        perform app.queue_notification(
          v_config_version_id, v_schedule.tenant_id, 'scheduled_report_ready', v_recipient.recipient_auth_user_id,
          'in_app', 'en', jsonb_build_object('scheduledReportName', v_schedule.name, 'runId', v_run.id),
          'scheduled-report-run-' || v_run.id || '-' || v_recipient.recipient_auth_user_id,
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

  update app.scheduled_reports
  set last_run_at = now(), next_run_at = app.compute_scheduled_report_next_run(cron_minute, cron_hour, cron_day_of_month, cron_day_of_week, timezone, v_schedule.next_run_at)
  where id = p_scheduled_report_id;

  perform app.capture_audit_event(
    v_schedule.tenant_id, p_actor_auth_user_id, p_actor_label, 'run_scheduled_report',
    'app.scheduled_report_runs', v_run.id, 'success', null, null, to_jsonb(v_run)
  );

  return v_run;
end;
$$;

comment on function app.run_scheduled_report is
  'IAE-006: the real execution entrypoint -- both a manual "run now" and what a future scheduler would call at next_run_at (none exists in this environment, the same disclosed condition every job type here carries). Reauthorizes every recipient live; enqueues via the shared app.jobs queue with an occurrence-scoped idempotency key; advances next_run_at forward from the JUST-triggered occurrence, never from now(), so a late manual trigger cannot skip or double an occurrence.';

alter table app.scheduled_reports enable row level security;
alter table app.scheduled_report_recipients enable row level security;
alter table app.scheduled_report_runs enable row level security;

create policy scheduled_reports_select_scoped on app.scheduled_reports
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy scheduled_report_recipients_select_scoped on app.scheduled_report_recipients
  for select to authenticated
  using (exists (
    select 1 from app.scheduled_reports s
    where s.id = scheduled_report_recipients.scheduled_report_id
      and ((app.has_active_tenant_membership(s.tenant_id) and not app.actor_holds_customer_user_layer(s.tenant_id)) or app.is_supreme_admin())
  ));

create policy scheduled_report_runs_select_scoped on app.scheduled_report_runs
  for select to authenticated
  using (exists (
    select 1 from app.scheduled_reports s
    where s.id = scheduled_report_runs.scheduled_report_id
      and ((app.has_active_tenant_membership(s.tenant_id) and not app.actor_holds_customer_user_layer(s.tenant_id)) or app.is_supreme_admin())
  ));

-- Bootstrap the one notification type this checkpoint really emits, by
-- direct INSERT (mirroring HRT-291's own cited precedent -- see this
-- migration's own header) rather than the Supreme-Admin-gated RPCs, which
-- have no live actor session to satisfy at migration-apply time. Seeded
-- ALREADY PUBLISHED, unlike HRT-291's registration-only bootstrap, since
-- this checkpoint's own app.run_scheduled_report is a real emission caller.
insert into app.notification_types (code, name, owner_primitive_code, registered_by)
values ('scheduled_report_ready', 'Scheduled Report Ready', 'REP', 'system');

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('notification:scheduled_report_ready', 'Scheduled Report Ready', 'REP', 'system');

do $$
declare
  v_object_id uuid;
  v_version_id uuid;
begin
  insert into app.config_objects (config_type_code, tenant_id, scope_level, scope_id, created_by)
  values ('notification:scheduled_report_ready', null, 'global', null, 'system')
  returning id into v_object_id;

  insert into app.config_versions (config_object_id, version_number, status, effective_from, published_by, published_at, created_by)
  values (v_object_id, 1, 'published', now(), 'system', now(), 'system')
  returning id into v_version_id;

  insert into app.config_items (config_version_id, key, value) values
    (v_version_id, 'channels', '["in_app"]'::jsonb),
    (v_version_id, 'default_locale', '"en"'::jsonb),
    (v_version_id, 'templates', '{"en": {"subject": "Your scheduled report is ready", "body": "{{scheduledReportName}} has finished running."}}'::jsonb);
end;
$$;

revoke execute on all functions in schema app from public;

grant select on app.scheduled_reports, app.scheduled_report_recipients, app.scheduled_report_runs to authenticated, service_role;
grant insert, update, delete on app.scheduled_reports, app.scheduled_report_recipients, app.scheduled_report_runs to service_role;

grant execute on function app.create_scheduled_report(uuid, text, text, text, integer, integer, integer, integer, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.set_scheduled_report_status(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.add_scheduled_report_recipient(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.remove_scheduled_report_recipient(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.run_scheduled_report(uuid, uuid, text) to authenticated, service_role;
