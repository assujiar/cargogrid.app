-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-017 (Ticket SLA and
-- Knowledge Base, Prompt 289) -- SLA half. First of two migrations this
-- prompt adds (this one: SLA policy/calendar/clock; 20260731130000: Knowledge
-- Base) -- split because they are genuinely separate sub-capabilities with
-- their own tables/RPCs/RLS, per this task's own explicit instruction to
-- treat both as real, complete scope. Builds on app.tickets/app.ticket_
-- categories/app.ticket_queues/app.support_queues (HRT-286/287/288) and
-- app.jobs (PLT-131/132) -- never a second ticket or job mechanism.
--
-- Design decisions, disclosed rather than left implicit (matching every
-- prior HRT checkpoint's own discipline):
--
-- 1. **SLA clock start/pause/resume are EXPLICIT RPCs, never a trigger or an
--    implicit side effect of an existing ticket function.** This migration
--    modifies ZERO functions from 20260731060000/080000/100000 -- not
--    app._create_ticket, not app.transition_ticket_status, not any reply
--    function. app.start_ticket_sla_clock is called as a SECOND, explicit
--    step by the creation flow (server action/UI) immediately after
--    app.create_ticket/create_customer_ticket/create_helpdesk_ticket
--    succeeds -- mirrors this repository's own "no hidden side effect,
--    every transition is a single explicit call" discipline (HRT-286
--    decision 6) applied to a NEW cross-cutting concern rather than
--    relaxing it. This also means zero regression risk to the three
--    already-VERIFIED ticket-channel migrations: their own db-test files
--    are re-run byte-for-byte unmodified as part of this checkpoint's own
--    adversarial pass.
-- 2. **Response/resolution "met" detection is READ-TIME DERIVATION, not a
--    write-time hook.** Whether the response target was met is derived from
--    the ticket's own existing data (the first `visibility='public',
--    author_role='staff'` row in app.ticket_messages) and whether the
--    resolution target was met is derived from app.tickets.resolved_at
--    (already set by the existing, unmodified app.transition_ticket_status)
--    -- never a new column threaded into reply_to_ticket/reply_to_
--    customer_ticket/reply_to_helpdesk_ticket. The evaluation job (decision
--    5) reads this derived signal and writes the durable ledger row; the
--    three reply functions and transition_ticket_status are never touched.
-- 3. **SLA policy precedence is fully deterministic and never silently
--    ambiguous (section 24's own business rule, literally).**
--    app.resolve_effective_sla_policy_version ranks every published policy
--    version whose scope structurally matches the ticket (channel required
--    exact match; category/priority/customer_account/queue are each either
--    NULL -- a wildcard -- or an exact match) by specificity in a fixed,
--    named order: customer_account_id set > queue/support_queue_id set >
--    category_id set > priority set > the version's own explicit
--    `precedence_rank` (author-assigned tie-break for two versions of equal
--    structural specificity) . If, after this full ordering, more than one
--    candidate remains tied for first place, the function RAISES
--    `sla_policy_ambiguous_match` rather than picking one arbitrarily --
--    live-reproduced in this checkpoint's own adversarial pass (two
--    channel-only-scoped policy versions for the same channel, no other
--    distinguishing scope, identical precedence_rank).
-- 4. **A clock retains the EXACT policy-version and calendar-version row ids
--    it started against -- both are real foreign keys to specific version
--    rows, not to the parent policy/calendar.** A later publish of a new
--    policy or calendar version can never silently rewrite a running
--    clock's own target/timezone -- live-tested directly (start a clock
--    under calendar version 1, publish calendar version 2, confirm the
--    running clock's own business-time computation still uses version 1
--    verbatim).
-- 5. **Compliance is reproducible FROM the ledger, not from a cached
--    status.** app.ticket_sla_clocks.response_status/resolution_status and
--    their *_at columns are an explicitly documented CACHE -- the real
--    source of truth is app.ticket_sla_clock_events (append-only) plus
--    app.replay_ticket_sla_clock_elapsed, which recomputes total elapsed
--    business minutes purely by walking started/paused/resumed events.
--    app.reconcile_ticket_sla_clock recomputes the cache FROM the ledger
--    alone and is live-tested by deliberately corrupting the cache columns
--    and confirming reconciliation restores the ledger-derived truth.
-- 6. **Idempotent breach/reminder job -- HONEST about what it guarantees
--    (this task's own mandatory reading, the HRT-282/ISS-2026-079 lesson).**
--    app._evaluate_ticket_sla_clock's breach/met/reminder INSERTs are
--    wrapped in a REAL `exception when unique_violation` handler over a
--    real partial unique index on the natural key (clock_id, phase,
--    event_type) for met/breached and (clock_id, phase,
--    reminder_threshold_pct) for reminders -- not merely a pre-check SELECT
--    (C-01/C-02 mandate). This guarantees NO-DUPLICATE-EVENT-ON-RETRY,
--    live-reproduced with two genuinely concurrent OS `psql` processes
--    calling the same evaluation on the same clock. It does NOT claim
--    genuine multi-step crash-mid-calculation resumability: each
--    evaluation call is a single, short, all-or-nothing transaction with no
--    internal checkpointing -- if it crashes mid-transaction nothing
--    commits and a retry simply redoes the (idempotent) work from scratch.
--    This is a materially narrower claim than "resumable," and is stated
--    that way deliberately, not glossed over.
-- 7. **Business-time calendar computation is a real, bounded day-by-day walk
--    -- not a placeholder.** app.compute_sla_business_minutes walks each
--    calendar day between two timestamps in the calendar's own timezone,
--    treats a holiday date as zero business minutes regardless of
--    is_24x7/business-hours configuration, and sums per-weekday business
--    windows otherwise. V1 supports exactly one business-hours window per
--    weekday (no split-shift/lunch-break carve-out) -- disclosed, not
--    hidden; a real, sourced future extension, not an oversight.
-- 8. **Reuses app.jobs (PLT-131/132) exactly, never a second job
--    mechanism.** job_type is widened (`ticket_sla_evaluation`) exactly as
--    every prior HRIS-domain adopter did (HRT-284 decision 5's own header,
--    itself citing PLT-132's disclosure) -- app.jobs.job_type''s CHECK
--    constraint and app.generic_job_types() are widened together, kept
--    set-equal by the standing ATW-031 drift gate. No live cron/poll
--    scheduler exists anywhere in this repository (the same NOT_RUN class
--    PLT-123/PLT-125/PLT-132 already disclosed) -- app.run_ticket_sla_
--    evaluation_batch is the real, callable, tested entry point a future
--    scheduler would invoke periodically; this checkpoint proves the
--    mechanics live, not a running scheduler.
-- 9. **C-24 discipline.** Every free-text column (pause/resume/recalculate
--    `reason`) lives ONLY on app.ticket_sla_clock_events, which is governed
--    by the exact same RLS as the ticket itself (app.can_access_ticket) --
--    mirroring app.ticket_events (HRT-286 decision 9) exactly. NOT ONE
--    `capture_audit_event` call site in this migration passes a raw
--    `p_reason` into `p_reason` or `to_jsonb(row)` for any table here --
--    app.ticket_sla_clock_audit_projection is an explicit allowlist.
-- 10. **Access rules (section 26).** Policy/calendar authoring and publish
--     are TKT:Edit-gated (mirrors app.create_ticket_queue/category exactly
--     -- no new permission code invented). Clock correction
--     (recalculate) additionally requires TKT:Close (the same "higher bar
--     for consequential actions" already established for resolve/close).
--     Pause/resume require only app.is_ticket_staff (ordinary queue work,
--     mirrors reply/classify). A ticket's own requester-side party
--     (app._is_ticket_requester_party, reused verbatim across all three
--     channels -- never re-derived) reads ONLY the customer-safe projection
--     (app.get_ticket_sla_status_for_requester /
--     app.list_ticket_sla_events_for_requester) -- no calendar internals,
--     no pause reason text, no policy identity.
-- 11. **C-02 discipline**: every RETURNS TABLE function below aliases every
--     source table and never writes a bare `where id = ...`.

-- ===========================================================================
-- 0. Widen app.jobs.job_type (decision 8).
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'HRT-289 (decision 8): widened to add ''ticket_sla_evaluation'' -- the sixth HRIS/Ticketing-domain adopter of PLT-132''s own generic job_type list. Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

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
    'ticket_sla_evaluation'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012), widened by HRT-289 to add ''ticket_sla_evaluation''. Unchanged callers: app.enqueue_job and app.dispatch_event_as_job.';

-- ===========================================================================
-- 1. app.sla_calendars / app.sla_calendar_versions -- business calendar,
--    versioned exactly like app.leave_type_policy_versions (HRT-280).
-- ===========================================================================

create table app.sla_calendars (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sla_calendars_status_check check (status in ('active', 'inactive')),
  constraint sla_calendars_code_check check (length(trim(code)) > 0),
  constraint sla_calendars_name_check check (length(trim(name)) > 0),
  constraint sla_calendars_code_unique unique (tenant_id, code)
);

comment on table app.sla_calendars is
  'HRT-289: business calendar identity catalog (parent). Timezone/business-hours/holidays live on app.sla_calendar_versions, never here -- mirrors app.leave_types/app.leave_type_policy_versions'' own identity-vs-ruleset split (HRT-280).';

create index sla_calendars_tenant_status_idx on app.sla_calendars (tenant_id, status);

create trigger sla_calendars_touch before update on app.sla_calendars
  for each row execute function app.touch_ticket_row();

create table app.sla_calendar_versions (
  id uuid primary key default gen_random_uuid(),
  calendar_id uuid not null references app.sla_calendars (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  timezone text not null,
  is_24x7 boolean not null default false,
  published_at timestamptz,
  published_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sla_calendar_versions_status_check check (status in ('draft', 'published', 'superseded')),
  constraint sla_calendar_versions_timezone_check check (length(trim(timezone)) > 0),
  constraint sla_calendar_versions_published_shape_check check (
    (status <> 'published') or (published_at is not null and published_by is not null)
  ),
  constraint sla_calendar_versions_scope_unique unique (calendar_id, version_number)
);

comment on table app.sla_calendar_versions is
  'HRT-289 (decision 4): one immutable, timestamped, timezone-carrying version. A ticket SLA clock references a SPECIFIC row here (never the parent calendar) at start time -- publishing a later version never rewrites an already-started clock''s own business-time computation. Only one row per calendar_id may hold status=''published'' at a time (enforced by app.publish_sla_calendar_version under a row lock on the parent, mirrors app.publish_leave_type_policy_version''s own supersede shape).';

create index sla_calendar_versions_calendar_status_idx on app.sla_calendar_versions (calendar_id, status);

create table app.sla_calendar_business_hours (
  id uuid primary key default gen_random_uuid(),
  calendar_version_id uuid not null references app.sla_calendar_versions (id),
  day_of_week smallint not null,
  start_time time not null,
  end_time time not null,
  constraint sla_calendar_business_hours_dow_check check (day_of_week between 0 and 6),
  constraint sla_calendar_business_hours_window_check check (end_time > start_time),
  constraint sla_calendar_business_hours_unique unique (calendar_version_id, day_of_week)
);

comment on table app.sla_calendar_business_hours is
  'HRT-289 (decision 7, disclosed V1 limitation): at most ONE business-hours window per weekday per calendar version (day_of_week 0=Sunday..6=Saturday, matching Postgres extract(dow)). A split-shift/lunch-break carve-out (two windows in one day) is a real, deferred future extension -- disclosed, not silently dropped.';

create index sla_calendar_business_hours_version_idx on app.sla_calendar_business_hours (calendar_version_id);

create table app.sla_calendar_holidays (
  id uuid primary key default gen_random_uuid(),
  calendar_version_id uuid not null references app.sla_calendar_versions (id),
  holiday_date date not null,
  name text not null,
  constraint sla_calendar_holidays_name_check check (length(trim(name)) > 0),
  constraint sla_calendar_holidays_unique unique (calendar_version_id, holiday_date)
);

comment on table app.sla_calendar_holidays is
  'HRT-289: a holiday_date is treated as ZERO business minutes for the whole calendar day regardless of is_24x7/business-hours configuration (decision 7) -- a genuinely non-business day overrides an otherwise-24x7 calendar.';

create index sla_calendar_holidays_version_date_idx on app.sla_calendar_holidays (calendar_version_id, holiday_date);

-- ===========================================================================
-- 2. app.sla_policies / app.sla_policy_versions -- scoped target catalog,
--    versioned exactly like app.leave_type_policy_versions.
-- ===========================================================================

create table app.sla_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  name text not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sla_policies_status_check check (status in ('active', 'inactive')),
  constraint sla_policies_code_check check (length(trim(code)) > 0),
  constraint sla_policies_name_check check (length(trim(name)) > 0),
  constraint sla_policies_code_unique unique (tenant_id, code)
);

create index sla_policies_tenant_status_idx on app.sla_policies (tenant_id, status);

create trigger sla_policies_touch before update on app.sla_policies
  for each row execute function app.touch_ticket_row();

create table app.sla_policy_versions (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references app.sla_policies (id),
  tenant_id uuid not null references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  channel text not null,
  category_id uuid references app.ticket_categories (id),
  priority text,
  customer_account_id uuid references app.accounts (id),
  queue_id uuid references app.ticket_queues (id),
  support_queue_id uuid references app.support_queues (id),
  calendar_id uuid not null references app.sla_calendars (id),
  response_target_minutes integer not null,
  resolution_target_minutes integer not null,
  precedence_rank integer not null default 0,
  published_at timestamptz,
  published_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sla_policy_versions_status_check check (status in ('draft', 'published', 'superseded')),
  constraint sla_policy_versions_channel_check check (channel in ('internal', 'customer', 'helpdesk')),
  constraint sla_policy_versions_priority_check check (priority is null or priority in ('low', 'normal', 'high', 'urgent')),
  constraint sla_policy_versions_response_target_check check (response_target_minutes > 0),
  constraint sla_policy_versions_resolution_target_check check (resolution_target_minutes > 0),
  constraint sla_policy_versions_customer_scope_shape check (customer_account_id is null or channel = 'customer'),
  constraint sla_policy_versions_queue_scope_shape check (queue_id is null or channel in ('internal', 'customer')),
  constraint sla_policy_versions_support_queue_scope_shape check (support_queue_id is null or channel = 'helpdesk'),
  constraint sla_policy_versions_published_shape_check check (
    (status <> 'published') or (published_at is not null and published_by is not null)
  ),
  constraint sla_policy_versions_scope_unique unique (policy_id, version_number)
);

comment on table app.sla_policy_versions is
  'HRT-289 (decisions 3/4): scope (channel/category/priority/customer_account/queue) lives on the VERSION, mirroring app.leave_type_policy_versions'' own org_unit-scope-per-version shape (HRT-280) -- never on the parent app.sla_policies row. channel is required (exact match, never a wildcard); category_id/priority/customer_account_id/queue_id/support_queue_id are each either NULL (wildcard) or an exact match -- app.resolve_effective_sla_policy_version is the SINGLE deterministic precedence engine (decision 3) every clock-start call uses. calendar_id references the CALENDAR (parent) -- the clock resolves and freezes the calendar''s CURRENT PUBLISHED VERSION at start time (decision 4), so a policy version''s calendar reference can stay stable across calendar republishes.';

create index sla_policy_versions_tenant_channel_idx on app.sla_policy_versions (tenant_id, channel, status);
create index sla_policy_versions_category_idx on app.sla_policy_versions (category_id) where category_id is not null;
create index sla_policy_versions_customer_account_idx on app.sla_policy_versions (customer_account_id) where customer_account_id is not null;

-- ===========================================================================
-- 3. app.ticket_sla_clocks / app.ticket_sla_clock_events -- the per-ticket
--    clock instance and its append-only ledger (decisions 4/5/9).
-- ===========================================================================

create table app.ticket_sla_clocks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  sla_policy_version_id uuid not null references app.sla_policy_versions (id),
  sla_calendar_version_id uuid not null references app.sla_calendar_versions (id),
  status text not null default 'running',
  started_at timestamptz not null default now(),
  response_target_minutes integer not null,
  response_status text not null default 'pending',
  response_met_at timestamptz,
  response_breached_at timestamptz,
  resolution_target_minutes integer not null,
  resolution_status text not null default 'pending',
  resolution_met_at timestamptz,
  resolution_breached_at timestamptz,
  last_evaluated_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_sla_clocks_status_check check (status in ('running', 'paused', 'completed', 'cancelled')),
  constraint ticket_sla_clocks_response_status_check check (response_status in ('pending', 'met', 'breached')),
  constraint ticket_sla_clocks_resolution_status_check check (resolution_status in ('pending', 'met', 'breached')),
  constraint ticket_sla_clocks_response_target_check check (response_target_minutes > 0),
  constraint ticket_sla_clocks_resolution_target_check check (resolution_target_minutes > 0),
  constraint ticket_sla_clocks_ticket_unique unique (ticket_id)
);

comment on table app.ticket_sla_clocks is
  'HRT-289 (decisions 3/4/5): one clock per ticket. sla_policy_version_id/sla_calendar_version_id/response_target_minutes/resolution_target_minutes are a FROZEN snapshot of the exact versions/targets resolved at app.start_ticket_sla_clock time (decision 4) -- a later policy or calendar publish never rewrites them. response_status/resolution_status/*_at are an explicitly documented CACHE, reproducible at any time from app.ticket_sla_clock_events via app.reconcile_ticket_sla_clock (decision 5) -- never the sole source of compliance truth.';

create index ticket_sla_clocks_tenant_status_idx on app.ticket_sla_clocks (tenant_id, status);
create index ticket_sla_clocks_response_pending_idx on app.ticket_sla_clocks (tenant_id) where status in ('running', 'paused') and response_status = 'pending';
create index ticket_sla_clocks_resolution_pending_idx on app.ticket_sla_clocks (tenant_id) where status in ('running', 'paused') and resolution_status = 'pending';

create trigger ticket_sla_clocks_touch before update on app.ticket_sla_clocks
  for each row execute function app.touch_ticket_row();

create table app.ticket_sla_clock_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  clock_id uuid not null references app.ticket_sla_clocks (id),
  ticket_id uuid not null references app.tickets (id),
  phase text,
  event_type text not null,
  reminder_threshold_pct integer,
  business_minutes_elapsed integer,
  occurred_at timestamptz not null default now(),
  actor_auth_user_id uuid,
  actor_label text,
  reason text,
  job_id uuid references app.jobs (job_id),
  constraint ticket_sla_clock_events_phase_check check (phase is null or phase in ('response', 'resolution')),
  constraint ticket_sla_clock_events_event_type_check check (event_type in (
    'started', 'paused', 'resumed', 'met', 'breached', 'reminder', 'recalculated', 'cancelled'
  )),
  constraint ticket_sla_clock_events_phase_shape_check check (
    (event_type in ('met', 'breached', 'reminder') and phase is not null)
    or (event_type in ('started', 'paused', 'resumed', 'recalculated', 'cancelled'))
  ),
  constraint ticket_sla_clock_events_reminder_shape_check check (
    (event_type = 'reminder' and reminder_threshold_pct between 1 and 100)
    or (event_type <> 'reminder' and reminder_threshold_pct is null)
  )
);

comment on table app.ticket_sla_clock_events is
  'HRT-289 (decisions 5/6/9): the append-only compliance ledger -- the ONLY authoritative source app.replay_ticket_sla_clock_elapsed / app.reconcile_ticket_sla_clock read. reason (pause/resume/recalculate free text) lives ONLY here, governed by the exact same RLS as the parent ticket (app.can_access_ticket) -- never app.audit_logs (decision 9), mirroring app.ticket_events (HRT-286) exactly. The two partial unique indexes below are the REAL idempotency guarantee (decision 6): a retried evaluation cannot insert a second met/breached row for the same (clock, phase), nor a second reminder at the same (clock, phase, threshold).';

create unique index ticket_sla_clock_events_met_breach_unique on app.ticket_sla_clock_events (clock_id, phase, event_type) where event_type in ('met', 'breached');
create unique index ticket_sla_clock_events_reminder_unique on app.ticket_sla_clock_events (clock_id, phase, reminder_threshold_pct) where event_type = 'reminder';
create index ticket_sla_clock_events_clock_idx on app.ticket_sla_clock_events (clock_id, occurred_at asc);
create index ticket_sla_clock_events_ticket_idx on app.ticket_sla_clock_events (ticket_id, occurred_at asc);

-- ===========================================================================
-- 4. Authority helpers (decision 10) -- reuse app.check_ticket_authority /
--    app.is_ticket_staff / app.can_access_ticket / app._is_ticket_requester_
--    party verbatim, never re-derived.
-- ===========================================================================

create function app.ticket_sla_clock_audit_projection(p_clock app.ticket_sla_clocks)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_clock.id,
    'tenant_id', p_clock.tenant_id,
    'ticket_id', p_clock.ticket_id,
    'sla_policy_version_id', p_clock.sla_policy_version_id,
    'sla_calendar_version_id', p_clock.sla_calendar_version_id,
    'status', p_clock.status,
    'response_status', p_clock.response_status,
    'resolution_status', p_clock.resolution_status,
    'record_version', p_clock.record_version
  );
$$;

comment on function app.ticket_sla_clock_audit_projection is
  'HRT-289 (decision 9, C-24 discipline): explicit structural-fields-only allowlist -- never to_jsonb(row). This table carries no free-text column, but the allowlist discipline is applied consistently regardless.';

-- ===========================================================================
-- 5. Calendar authoring/publish RPCs -- TKT:Edit-gated (decision 10),
--    idempotent create-or-return (mirrors app.create_ticket_queue exactly).
-- ===========================================================================

create function app.create_sla_calendar(p_tenant_id uuid, p_code text, p_name text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.sla_calendars
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.sla_calendars;
  v_row app.sla_calendars;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'code_required: a non-empty code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a non-empty name is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.sla_calendars where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.sla_calendars (tenant_id, code, name, created_by)
    values (p_tenant_id, p_code, p_name, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.sla_calendars where tenant_id = p_tenant_id and code = p_code;
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_sla_calendar',
    'app.sla_calendars', v_row.id, 'success', null, null, jsonb_build_object('code', v_row.code)
  );

  return v_row;
end;
$$;

create function app.create_sla_calendar_version(
  p_calendar_id uuid, p_timezone text, p_is_24x7 boolean, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.sla_calendar_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_calendar app.sla_calendars;
  v_next_version integer;
  v_row app.sla_calendar_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_calendar from app.sla_calendars where id = p_calendar_id for update;
  if not found then
    raise exception 'sla_calendar_not_found: %', p_calendar_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_calendar.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_calendar.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_timezone is null or length(trim(p_timezone)) = 0 then
    raise exception 'timezone_required: a non-empty IANA timezone name is required' using errcode = 'check_violation';
  end if;
  begin
    perform (now() at time zone p_timezone);
  exception
    when invalid_parameter_value or others then
      raise exception 'invalid_timezone: % is not a recognized timezone name', p_timezone using errcode = 'check_violation';
  end;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.sla_calendar_versions where calendar_id = p_calendar_id;

  insert into app.sla_calendar_versions (calendar_id, tenant_id, version_number, timezone, is_24x7, created_by)
  values (p_calendar_id, v_calendar.tenant_id, v_next_version, p_timezone, coalesce(p_is_24x7, false), p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_calendar.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_sla_calendar_version',
    'app.sla_calendar_versions', v_row.id, 'success', null, null,
    jsonb_build_object('calendar_id', p_calendar_id, 'version_number', v_next_version, 'timezone', p_timezone, 'is_24x7', v_row.is_24x7)
  );

  return v_row;
end;
$$;

comment on function app.create_sla_calendar_version is
  'HRT-289: p_timezone is validated by actually evaluating it (now() at time zone p_timezone) rather than a static allowlist -- an invalid IANA name raises invalid_timezone cleanly instead of a raw Postgres error surfacing later at business-time-computation time.';

create function app.add_sla_calendar_business_hours(
  p_calendar_version_id uuid, p_day_of_week smallint, p_start_time time, p_end_time time, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.sla_calendar_business_hours
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.sla_calendar_versions;
  v_row app.sla_calendar_business_hours;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.sla_calendar_versions where id = p_calendar_version_id;
  if not found then
    raise exception 'sla_calendar_version_not_found: %', p_calendar_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: calendar version % is % not draft', p_calendar_version_id, v_version.status using errcode = 'check_violation';
  end if;

  begin
    insert into app.sla_calendar_business_hours (calendar_version_id, day_of_week, start_time, end_time)
    values (p_calendar_version_id, p_day_of_week, p_start_time, p_end_time)
    returning * into v_row;
  exception
    when unique_violation then
      update app.sla_calendar_business_hours set start_time = p_start_time, end_time = p_end_time
      where calendar_version_id = p_calendar_version_id and day_of_week = p_day_of_week
      returning * into v_row;
  end;

  return v_row;
end;
$$;

create function app.add_sla_calendar_holiday(
  p_calendar_version_id uuid, p_holiday_date date, p_name text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.sla_calendar_holidays
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.sla_calendar_versions;
  v_row app.sla_calendar_holidays;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.sla_calendar_versions where id = p_calendar_version_id;
  if not found then
    raise exception 'sla_calendar_version_not_found: %', p_calendar_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: calendar version % is % not draft', p_calendar_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a non-empty holiday name is required' using errcode = 'check_violation';
  end if;

  begin
    insert into app.sla_calendar_holidays (calendar_version_id, holiday_date, name)
    values (p_calendar_version_id, p_holiday_date, p_name)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.sla_calendar_holidays where calendar_version_id = p_calendar_version_id and holiday_date = p_holiday_date;
  end;

  return v_row;
end;
$$;

create function app.publish_sla_calendar_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.sla_calendar_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.sla_calendar_versions;
  v_calendar app.sla_calendars;
  v_updated app.sla_calendar_versions;
  v_has_hours boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.sla_calendar_versions where id = p_version_id for update;
  if not found then
    raise exception 'sla_calendar_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  -- Lock order (C-21 discipline): parent calendar row, then the version row
  -- already locked above -- this is the ONLY function in this migration that
  -- locks both, so there is no sibling to deadlock against.
  select * into v_calendar from app.sla_calendars where id = v_version.calendar_id for update;

  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: calendar version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  select exists (select 1 from app.sla_calendar_business_hours h where h.calendar_version_id = p_version_id) into v_has_hours;
  if not v_version.is_24x7 and not v_has_hours then
    raise exception 'calendar_incomplete: version % has no business hours and is not is_24x7' , p_version_id using errcode = 'check_violation';
  end if;

  update app.sla_calendar_versions set status = 'superseded'
  where calendar_id = v_version.calendar_id and status = 'published';

  update app.sla_calendar_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for calendar version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_sla_calendar_version',
    'app.sla_calendar_versions', p_version_id, 'success', null, null,
    jsonb_build_object('calendar_id', v_version.calendar_id, 'version_number', v_updated.version_number)
  );

  return v_updated;
end;
$$;

comment on function app.publish_sla_calendar_version is
  'HRT-289 (decision 4): publishing supersedes the calendar''s prior published version under a row lock on the PARENT calendar (preventing a concurrent double-publish race), but never touches any app.ticket_sla_clocks row that already froze a specific (now-superseded) version id -- live-tested directly.';

create function app.resolve_sla_calendar_current_version(p_calendar_id uuid)
returns app.sla_calendar_versions
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select v.* from app.sla_calendar_versions v where v.calendar_id = p_calendar_id and v.status = 'published' order by v.version_number desc limit 1;
$$;

grant execute on function app.resolve_sla_calendar_current_version(uuid) to service_role;

-- ===========================================================================
-- 6. Policy authoring/publish RPCs (mirrors calendar section 5 exactly).
-- ===========================================================================

create function app.create_sla_policy(p_tenant_id uuid, p_code text, p_name text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.sla_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.sla_policies;
  v_row app.sla_policies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'code_required: a non-empty code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a non-empty name is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.sla_policies where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.sla_policies (tenant_id, code, name, created_by)
    values (p_tenant_id, p_code, p_name, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.sla_policies where tenant_id = p_tenant_id and code = p_code;
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_sla_policy',
    'app.sla_policies', v_row.id, 'success', null, null, jsonb_build_object('code', v_row.code)
  );

  return v_row;
end;
$$;

create function app.create_sla_policy_version(
  p_policy_id uuid, p_channel text, p_category_id uuid, p_priority text, p_customer_account_id uuid,
  p_queue_id uuid, p_support_queue_id uuid, p_calendar_id uuid, p_response_target_minutes integer,
  p_resolution_target_minutes integer, p_precedence_rank integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.sla_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.sla_policies;
  v_next_version integer;
  v_row app.sla_policy_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_policy from app.sla_policies where id = p_policy_id for update;
  if not found then
    raise exception 'sla_policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_channel is null or not (p_channel = any (array['internal', 'customer', 'helpdesk'])) then
    raise exception 'invalid_channel: % is not one of internal/customer/helpdesk', p_channel using errcode = 'check_violation';
  end if;
  if p_priority is not null and not (p_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', p_priority using errcode = 'check_violation';
  end if;
  if coalesce(p_response_target_minutes, 0) <= 0 or coalesce(p_resolution_target_minutes, 0) <= 0 then
    raise exception 'invalid_target: response/resolution target minutes must both be positive' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.sla_calendars sc where sc.id = p_calendar_id and sc.tenant_id = v_policy.tenant_id) then
    raise exception 'sla_calendar_not_found: % is not a valid calendar for tenant %', p_calendar_id, v_policy.tenant_id using errcode = 'no_data_found';
  end if;
  if p_category_id is not null and not exists (select 1 from app.ticket_categories tc where tc.id = p_category_id and tc.tenant_id = v_policy.tenant_id) then
    raise exception 'ticket_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;
  if p_customer_account_id is not null and (p_channel <> 'customer' or not exists (select 1 from app.accounts a where a.id = p_customer_account_id and a.tenant_id = v_policy.tenant_id)) then
    raise exception 'account_not_available: % is not a valid customer-channel account for tenant %', p_customer_account_id, v_policy.tenant_id using errcode = 'no_data_found';
  end if;
  if p_queue_id is not null and (p_channel not in ('internal', 'customer') or not exists (select 1 from app.ticket_queues tq where tq.id = p_queue_id and tq.tenant_id = v_policy.tenant_id)) then
    raise exception 'ticket_queue_not_found: % is not a valid queue for tenant % channel %', p_queue_id, v_policy.tenant_id, p_channel using errcode = 'no_data_found';
  end if;
  if p_support_queue_id is not null and (p_channel <> 'helpdesk' or not exists (select 1 from app.support_queues sq where sq.id = p_support_queue_id)) then
    raise exception 'support_queue_not_available: % is not a valid support queue for channel %', p_support_queue_id, p_channel using errcode = 'no_data_found';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.sla_policy_versions where policy_id = p_policy_id;

  insert into app.sla_policy_versions (
    policy_id, tenant_id, version_number, channel, category_id, priority, customer_account_id, queue_id,
    support_queue_id, calendar_id, response_target_minutes, resolution_target_minutes, precedence_rank, created_by
  ) values (
    p_policy_id, v_policy.tenant_id, v_next_version, p_channel, p_category_id, p_priority, p_customer_account_id, p_queue_id,
    p_support_queue_id, p_calendar_id, p_response_target_minutes, p_resolution_target_minutes, coalesce(p_precedence_rank, 0), p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_sla_policy_version',
    'app.sla_policy_versions', v_row.id, 'success', null, null,
    jsonb_build_object(
      'policy_id', p_policy_id, 'version_number', v_next_version, 'channel', p_channel, 'category_id', p_category_id,
      'priority', p_priority, 'customer_account_id', p_customer_account_id, 'queue_id', p_queue_id,
      'support_queue_id', p_support_queue_id, 'response_target_minutes', p_response_target_minutes,
      'resolution_target_minutes', p_resolution_target_minutes, 'precedence_rank', v_row.precedence_rank
    )
  );

  return v_row;
end;
$$;

create function app.publish_sla_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.sla_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.sla_policy_versions;
  v_policy app.sla_policies;
  v_updated app.sla_policy_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.sla_policy_versions where id = p_version_id for update;
  if not found then
    raise exception 'sla_policy_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  select * into v_policy from app.sla_policies where id = v_version.policy_id for update;

  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: policy version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.sla_calendar_versions cv where cv.calendar_id = v_version.calendar_id and cv.status = 'published') then
    raise exception 'sla_calendar_not_published: calendar % has no published version yet', v_version.calendar_id using errcode = 'check_violation';
  end if;

  -- Supersede this SAME policy's own prior published version (self-found in
  -- this checkpoint's own adversarial pass: without this, publishing a
  -- revised NARROW v2 left NARROW v1 also status=published, and the two
  -- sibling versions of the SAME policy then tied against each other at
  -- resolution time -- a false sla_policy_ambiguous_match neither version
  -- deserved). Mirrors app.publish_sla_calendar_version's own supersede
  -- exactly, scoped to policy_id under the parent-row lock already taken
  -- above. Deliberately does NOT supersede a DIFFERENT policy's version
  -- (decision 3) -- two DIFFERENT sla_policies may legitimately publish
  -- overlapping-scope versions; that ambiguity is caught at RESOLUTION time
  -- (app.resolve_effective_sla_policy_version), never suppressed here.
  update app.sla_policy_versions
  set status = 'superseded'
  where policy_id = v_version.policy_id and status = 'published';

  update app.sla_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for policy version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_sla_policy_version',
    'app.sla_policy_versions', p_version_id, 'success', null, null,
    jsonb_build_object('policy_id', v_version.policy_id, 'version_number', v_updated.version_number)
  );

  return v_updated;
end;
$$;

comment on function app.publish_sla_policy_version is
  'HRT-289 (decision 3, self-found adversarial-pass fix): supersedes this SAME policy''s own prior published version (mirrors app.publish_sla_calendar_version) -- publishing a revised version of one policy must not leave its own predecessor also published, which would tie against itself at resolution time. Deliberately does NOT supersede a DIFFERENT policy''s version: two DIFFERENT sla_policies may publish overlapping-scope versions (e.g. two teams each define a channel-wide default), and that is a legitimate, if risky, configuration -- the risk surfaces at RESOLUTION time, not publish time: app.resolve_effective_sla_policy_version raises sla_policy_ambiguous_match rather than silently picking one.';

-- ===========================================================================
-- 7. app.resolve_effective_sla_policy_version -- the deterministic
--    precedence engine (decision 3).
-- ===========================================================================

create function app.resolve_effective_sla_policy_version(
  p_tenant_id uuid, p_channel text, p_category_id uuid, p_priority text,
  p_customer_account_id uuid, p_queue_id uuid, p_support_queue_id uuid
)
returns app.sla_policy_versions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_rec record;
  v_best_id uuid;
  v_tie_count integer := 0;
  v_result app.sla_policy_versions;
begin
  for v_rec in
    select pv.id,
      rank() over (
        order by
          (pv.customer_account_id is not null) desc,
          (pv.queue_id is not null or pv.support_queue_id is not null) desc,
          (pv.category_id is not null) desc,
          (pv.priority is not null) desc,
          pv.precedence_rank desc
      ) as tie_rank
    from app.sla_policy_versions pv
    join app.sla_policies p on p.id = pv.policy_id
    where p.tenant_id = p_tenant_id
      and p.status = 'active'
      and pv.status = 'published'
      and pv.channel = p_channel
      and (pv.category_id is null or pv.category_id = p_category_id)
      and (pv.priority is null or pv.priority = p_priority)
      and (pv.customer_account_id is null or pv.customer_account_id = p_customer_account_id)
      and (pv.queue_id is null or pv.queue_id = p_queue_id)
      and (pv.support_queue_id is null or pv.support_queue_id = p_support_queue_id)
    order by tie_rank asc
  loop
    exit when v_rec.tie_rank > 1;
    v_tie_count := v_tie_count + 1;
    v_best_id := v_rec.id;
  end loop;

  if v_tie_count = 0 then
    return null;
  elsif v_tie_count > 1 then
    raise exception 'sla_policy_ambiguous_match: % published SLA policy versions tie for tenant % channel % -- resolve the tie with a distinct precedence_rank or narrower scope before starting this clock', v_tie_count, p_tenant_id, p_channel
      using errcode = 'check_violation';
  end if;

  select pv.* into v_result from app.sla_policy_versions pv where pv.id = v_best_id;
  return v_result;
end;
$$;

comment on function app.resolve_effective_sla_policy_version is
  'HRT-289 (decision 3, section 24''s own business rule): the ONE deterministic SLA-policy-match engine. Ranks candidates by specificity (customer_account_id set > queue/support_queue_id set > category_id set > priority set > explicit precedence_rank tie-break) using rank() so genuine ties share tie_rank=1; if more than one candidate remains at tie_rank=1 after the full ordering, raises sla_policy_ambiguous_match rather than picking arbitrarily. Zero candidates returns null (caller -- app.start_ticket_sla_clock -- treats this as the "no matching policy" alternative flow, never a hard failure of ticket creation). service_role only (ATW-032/ISS-2026-033 self-found in this checkpoint''s own full db:test run): it takes p_tenant_id with no actor parameter and no authority check, so granting it to authenticated would let any logged-in user of ANY tenant read another tenant''s SLA policy scope/targets by supplying a foreign tenant_id -- an internal resolution helper, called only from within app.start_ticket_sla_clock (owner-privileged nested call, no grant needed) or by service_role.';

grant execute on function app.resolve_effective_sla_policy_version(uuid, text, uuid, text, uuid, uuid, uuid) to service_role;

-- ===========================================================================
-- 8. app.start_ticket_sla_clock / pause / resume / recalculate (decisions
--    1/4/10). Explicit RPCs, never a trigger.
-- ===========================================================================

create function app.start_ticket_sla_clock(p_ticket_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_sla_clocks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_existing app.ticket_sla_clocks;
  v_policy_version app.sla_policy_versions;
  v_calendar_version app.sla_calendar_versions;
  v_row app.ticket_sla_clocks;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select t.* into v_ticket from app.tickets t where t.id = p_ticket_id;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.ticket_sla_clocks where ticket_id = p_ticket_id;
  if found then
    return v_existing;
  end if;

  v_policy_version := app.resolve_effective_sla_policy_version(
    v_ticket.tenant_id, v_ticket.channel, v_ticket.category_id, v_ticket.priority,
    v_ticket.requester_customer_account_id, v_ticket.queue_id, v_ticket.support_queue_id
  );
  if v_policy_version is null then
    raise exception 'sla_policy_not_matched: no published SLA policy version matches ticket % (channel %, category %, priority %)', p_ticket_id, v_ticket.channel, v_ticket.category_id, v_ticket.priority
      using errcode = 'no_data_found';
  end if;

  v_calendar_version := app.resolve_sla_calendar_current_version(v_policy_version.calendar_id);
  if v_calendar_version is null then
    raise exception 'sla_calendar_not_published: policy version %''s calendar % has no published version', v_policy_version.id, v_policy_version.calendar_id
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.ticket_sla_clocks (
      tenant_id, ticket_id, sla_policy_version_id, sla_calendar_version_id,
      response_target_minutes, resolution_target_minutes, created_by
    ) values (
      v_ticket.tenant_id, p_ticket_id, v_policy_version.id, v_calendar_version.id,
      v_policy_version.response_target_minutes, v_policy_version.resolution_target_minutes, p_actor_label
    )
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_sla_clocks where ticket_id = p_ticket_id;
      if not found then
        raise;
      end if;
      return v_row;
  end;

  insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, event_type, occurred_at, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, v_row.id, p_ticket_id, 'started', v_row.started_at, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_ticket_sla_clock',
    'app.ticket_sla_clocks', v_row.id, 'success', null, null, app.ticket_sla_clock_audit_projection(v_row)
  );

  return v_row;
end;
$$;

comment on function app.start_ticket_sla_clock is
  'HRT-289 (decisions 1/3/4): idempotent per ticket (a second call returns the existing clock, never re-prices it). Freezes sla_policy_version_id/sla_calendar_version_id/both targets at THIS moment -- a later publish of a newer policy or calendar version never rewrites this row (decision 4, live-tested). Called EXPLICITLY by the creation flow, never from app._create_ticket/app.create_ticket/app.create_customer_ticket/app.create_helpdesk_ticket (decision 1) -- those three functions are unmodified by this migration.';

create function app.pause_ticket_sla_clock(p_ticket_id uuid, p_expected_version integer, p_pause_reason_code text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_sla_clocks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_clock app.ticket_sla_clocks;
  v_updated app.ticket_sla_clocks;
  v_allowed_codes text[] := array['waiting_on_customer', 'waiting_on_third_party', 'internal_investigation', 'other'];
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select c.* into v_clock from app.ticket_sla_clocks c where c.ticket_id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_sla_clock_not_found: no SLA clock for ticket %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not staff on ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_clock.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_clock.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_clock.status <> 'running' then
    raise exception 'invalid_transition: SLA clock for ticket % is % not running', p_ticket_id, v_clock.status using errcode = 'check_violation';
  end if;
  if p_pause_reason_code is null or not (p_pause_reason_code = any (v_allowed_codes)) then
    raise exception 'invalid_pause_reason: % is not one of %', p_pause_reason_code, v_allowed_codes using errcode = 'check_violation';
  end if;

  update app.ticket_sla_clocks set status = 'paused'
  where ticket_id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for SLA clock on ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, event_type, actor_auth_user_id, actor_label, reason)
  values (v_clock.tenant_id, v_clock.id, p_ticket_id, 'paused', p_actor_auth_user_id, p_actor_label, p_pause_reason_code || coalesce(': ' || p_reason, ''));

  perform app.capture_audit_event(
    v_clock.tenant_id, p_actor_auth_user_id, p_actor_label, 'pause_ticket_sla_clock',
    'app.ticket_sla_clocks', v_clock.id, 'success', null, app.ticket_sla_clock_audit_projection(v_clock), app.ticket_sla_clock_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.pause_ticket_sla_clock is
  'HRT-289 (decision 10, section 25 "allowed pause/resume"): p_pause_reason_code is a closed, validated set -- an arbitrary free-text-only pause is rejected. The combined reason text is stored ONLY on app.ticket_sla_clock_events (decision 9), never passed to capture_audit_event''s own p_reason.';

create function app.resume_ticket_sla_clock(p_ticket_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_sla_clocks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_clock app.ticket_sla_clocks;
  v_updated app.ticket_sla_clocks;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select c.* into v_clock from app.ticket_sla_clocks c where c.ticket_id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_sla_clock_not_found: no SLA clock for ticket %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not staff on ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_clock.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_clock.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_clock.status <> 'paused' then
    raise exception 'invalid_transition: SLA clock for ticket % is % not paused', p_ticket_id, v_clock.status using errcode = 'check_violation';
  end if;

  update app.ticket_sla_clocks set status = 'running'
  where ticket_id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for SLA clock on ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, event_type, actor_auth_user_id, actor_label)
  values (v_clock.tenant_id, v_clock.id, p_ticket_id, 'resumed', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_clock.tenant_id, p_actor_auth_user_id, p_actor_label, 'resume_ticket_sla_clock',
    'app.ticket_sla_clocks', v_clock.id, 'success', null, app.ticket_sla_clock_audit_projection(v_clock), app.ticket_sla_clock_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create function app.recalculate_ticket_sla_clock(p_ticket_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_sla_clocks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_clock app.ticket_sla_clocks;
  v_elapsed integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select c.* into v_clock from app.ticket_sla_clocks c where c.ticket_id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_sla_clock_not_found: no SLA clock for ticket %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Close', v_clock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Close (required for an authorized SLA correction) for tenant %', p_actor_auth_user_id, v_clock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_clock.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_clock.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required for an authorized SLA correction' using errcode = 'check_violation';
  end if;

  v_elapsed := app.replay_ticket_sla_clock_elapsed(v_clock.id, now());

  insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, event_type, business_minutes_elapsed, actor_auth_user_id, actor_label, reason)
  values (v_clock.tenant_id, v_clock.id, p_ticket_id, 'recalculated', v_elapsed, p_actor_auth_user_id, p_actor_label, p_reason);

  update app.ticket_sla_clocks set last_evaluated_at = now() where ticket_id = p_ticket_id and record_version = p_expected_version;

  perform app.capture_audit_event(
    v_clock.tenant_id, p_actor_auth_user_id, p_actor_label, 'recalculate_ticket_sla_clock',
    'app.ticket_sla_clocks', v_clock.id, 'success', null, null, app.ticket_sla_clock_audit_projection(v_clock)
  );

  return app.reconcile_ticket_sla_clock(v_clock.id, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.recalculate_ticket_sla_clock is
  'HRT-289 (section 22 "alternative flow: authorized clock correction with replay"): TKT:Close-gated (the same higher bar as resolve/close, decision 10). Never mutates a prior ledger row -- appends a new recalculated event carrying the freshly-replayed elapsed-minutes snapshot, then calls app.reconcile_ticket_sla_clock so the cache reflects a fresh replay, not an ad hoc edit. p_reason lives only on app.ticket_sla_clock_events, never in p_reason of capture_audit_event.';

-- ===========================================================================
-- 9. Business-time engine (decision 7).
-- ===========================================================================

create function app.compute_sla_business_minutes(p_calendar_version_id uuid, p_from timestamptz, p_to timestamptz)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_calendar app.sla_calendar_versions;
  v_from_local timestamp;
  v_to_local timestamp;
  v_day date;
  v_total integer := 0;
  v_dow smallint;
  v_window record;
  v_window_start timestamp;
  v_window_end timestamp;
  v_overlap_start timestamp;
  v_overlap_end timestamp;
  v_is_holiday boolean;
begin
  if p_to <= p_from then
    return 0;
  end if;
  select * into v_calendar from app.sla_calendar_versions where id = p_calendar_version_id;
  if not found then
    raise exception 'sla_calendar_version_not_found: %', p_calendar_version_id using errcode = 'no_data_found';
  end if;
  if p_to - p_from > interval '5 years' then
    raise exception 'sla_range_too_large: business-minutes computation is bounded to 5 years' using errcode = 'check_violation';
  end if;

  v_from_local := p_from at time zone v_calendar.timezone;
  v_to_local := p_to at time zone v_calendar.timezone;

  v_day := v_from_local::date;
  while v_day <= v_to_local::date loop
    v_is_holiday := exists (select 1 from app.sla_calendar_holidays h where h.calendar_version_id = p_calendar_version_id and h.holiday_date = v_day);
    if not v_is_holiday then
      v_dow := extract(dow from v_day);
      if v_calendar.is_24x7 then
        v_window_start := v_day::timestamp;
        v_window_end := (v_day + 1)::timestamp;
        v_overlap_start := greatest(v_window_start, v_from_local);
        v_overlap_end := least(v_window_end, v_to_local);
        if v_overlap_end > v_overlap_start then
          v_total := v_total + ceil(extract(epoch from (v_overlap_end - v_overlap_start)) / 60)::integer;
        end if;
      else
        for v_window in
          select h.start_time, h.end_time from app.sla_calendar_business_hours h
          where h.calendar_version_id = p_calendar_version_id and h.day_of_week = v_dow
        loop
          v_window_start := v_day + v_window.start_time;
          v_window_end := v_day + v_window.end_time;
          v_overlap_start := greatest(v_window_start, v_from_local);
          v_overlap_end := least(v_window_end, v_to_local);
          if v_overlap_end > v_overlap_start then
            v_total := v_total + ceil(extract(epoch from (v_overlap_end - v_overlap_start)) / 60)::integer;
          end if;
        end loop;
      end if;
    end if;
    v_day := v_day + 1;
  end loop;

  return v_total;
end;
$$;

comment on function app.compute_sla_business_minutes is
  'HRT-289 (decision 7): real day-by-day business-time walk in the calendar version''s OWN timezone. A holiday date contributes zero minutes unconditionally (overrides is_24x7). Bounded to a 5-year span as a sanity guard against a malformed caller, never expected to bind in real SLA usage (targets are minutes-to-days scale).';

grant execute on function app.compute_sla_business_minutes(uuid, timestamptz, timestamptz) to service_role;

-- ===========================================================================
-- 10. Ledger replay / reconciliation (decision 5).
-- ===========================================================================

create function app.replay_ticket_sla_clock_elapsed(p_clock_id uuid, p_as_of timestamptz default now())
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_clock app.ticket_sla_clocks;
  v_event record;
  v_running_since timestamptz;
  v_state text;
  v_total integer := 0;
  v_cap timestamptz;
begin
  select * into v_clock from app.ticket_sla_clocks where id = p_clock_id;
  if not found then
    raise exception 'ticket_sla_clock_not_found: %', p_clock_id using errcode = 'no_data_found';
  end if;

  v_running_since := v_clock.started_at;
  v_state := 'running';
  v_cap := least(p_as_of, now());

  for v_event in
    select e.event_type, e.occurred_at from app.ticket_sla_clock_events e
    where e.clock_id = p_clock_id and e.event_type in ('paused', 'resumed') and e.occurred_at <= v_cap
    order by e.occurred_at asc
  loop
    if v_event.event_type = 'paused' and v_state = 'running' then
      v_total := v_total + app.compute_sla_business_minutes(v_clock.sla_calendar_version_id, v_running_since, v_event.occurred_at);
      v_state := 'paused';
    elsif v_event.event_type = 'resumed' and v_state = 'paused' then
      v_running_since := v_event.occurred_at;
      v_state := 'running';
    end if;
  end loop;

  if v_state = 'running' and v_cap > v_running_since then
    v_total := v_total + app.compute_sla_business_minutes(v_clock.sla_calendar_version_id, v_running_since, v_cap);
  end if;

  return v_total;
end;
$$;

comment on function app.replay_ticket_sla_clock_elapsed is
  'HRT-289 (decision 5, section 24''s own business rule "compliance must be reproducible from the ledger"): reconstructs total elapsed BUSINESS minutes purely from clock.started_at plus every paused/resumed event in app.ticket_sla_clock_events -- never reads any cached status column. p_as_of caps the walk (used to evaluate "was the target met AT the moment of a specific past event", e.g. the first staff reply timestamp). service_role only (ATW-032/ISS-2026-033 self-found in this checkpoint''s own full db:test run): takes a bare p_clock_id with no tenant/actor check, so granting it to authenticated would let any logged-in user of any tenant probe another tenant''s elapsed-minutes value by guessing/enumerating clock ids -- an internal helper for app._evaluate_ticket_sla_clock/app.recalculate_ticket_sla_clock (owner-privileged nested calls); the staff-facing read surface is app.get_ticket_sla_clock''s own cached, RLS/authority-gated projection.';

grant execute on function app.replay_ticket_sla_clock_elapsed(uuid, timestamptz) to service_role;

create function app.reconcile_ticket_sla_clock(p_clock_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_sla_clocks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_clock app.ticket_sla_clocks;
  v_response app.ticket_sla_clock_events;
  v_resolution app.ticket_sla_clock_events;
  v_last_pause_resume app.ticket_sla_clock_events;
  v_is_cancelled boolean;
  v_derived_response text;
  v_derived_resolution text;
  v_derived_status text;
  v_updated app.ticket_sla_clocks;
begin
  select * into v_clock from app.ticket_sla_clocks where id = p_clock_id for update;
  if not found then
    raise exception 'ticket_sla_clock_not_found: %', p_clock_id using errcode = 'no_data_found';
  end if;

  select e.* into v_response from app.ticket_sla_clock_events e
  where e.clock_id = p_clock_id and e.phase = 'response' and e.event_type in ('met', 'breached')
  order by e.occurred_at asc limit 1;

  select e.* into v_resolution from app.ticket_sla_clock_events e
  where e.clock_id = p_clock_id and e.phase = 'resolution' and e.event_type in ('met', 'breached')
  order by e.occurred_at asc limit 1;

  select exists (select 1 from app.ticket_sla_clock_events e where e.clock_id = p_clock_id and e.event_type = 'cancelled') into v_is_cancelled;

  select e.* into v_last_pause_resume from app.ticket_sla_clock_events e
  where e.clock_id = p_clock_id and e.event_type in ('paused', 'resumed')
  order by e.occurred_at desc limit 1;

  v_derived_response := coalesce(v_response.event_type, 'pending');
  v_derived_resolution := coalesce(v_resolution.event_type, 'pending');

  -- decision 5 (self-found adversarial-pass fix): app.ticket_sla_clocks.status
  -- is ALSO a ledger-derived cache, not just response_status/resolution_status
  -- -- omitting it left status=completed stranded after a corrective ledger
  -- edit reverted a phase back to pending, which then wrongly short-circuited
  -- app._evaluate_ticket_sla_clock's own `status not in (running,paused)`
  -- guard. Precedence: cancelled (terminal) > completed (both phases
  -- resolved) > paused/running (derived from the most recent pause/resume
  -- event, default running -- matches the 'started' event''s own initial state).
  if v_is_cancelled then
    v_derived_status := 'cancelled';
  elsif v_derived_response <> 'pending' and v_derived_resolution <> 'pending' then
    v_derived_status := 'completed';
  elsif v_last_pause_resume.event_type = 'paused' then
    v_derived_status := 'paused';
  else
    v_derived_status := 'running';
  end if;

  update app.ticket_sla_clocks set
    status = v_derived_status,
    response_status = v_derived_response,
    response_met_at = case when v_response.event_type = 'met' then v_response.occurred_at else null end,
    response_breached_at = case when v_response.event_type = 'breached' then v_response.occurred_at else null end,
    resolution_status = v_derived_resolution,
    resolution_met_at = case when v_resolution.event_type = 'met' then v_resolution.occurred_at else null end,
    resolution_breached_at = case when v_resolution.event_type = 'breached' then v_resolution.occurred_at else null end,
    last_evaluated_at = now()
  where id = p_clock_id
  returning * into v_updated;

  return v_updated;
end;
$$;

comment on function app.reconcile_ticket_sla_clock is
  'HRT-289 (decision 5): rebuilds status/response_status/resolution_status/*_at PURELY from app.ticket_sla_clock_events (the earliest met/breached row per phase, the most recent pause/resume event, and whether a cancelled event exists) -- proves the cache is genuinely reproducible, not a second source of truth. Live-tested by directly corrupting the cache columns then calling this function and confirming the ledger-derived values win.';

grant execute on function app.reconcile_ticket_sla_clock(uuid, uuid, text) to service_role;

-- ===========================================================================
-- 11. app._evaluate_ticket_sla_clock -- the idempotent evaluation primitive
--     (decisions 2/6).
-- ===========================================================================

create function app._evaluate_ticket_sla_clock(p_clock_id uuid, p_as_of timestamptz, p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_clock app.ticket_sla_clocks;
  v_ticket app.tickets;
  v_first_staff_reply_at timestamptz;
  v_elapsed integer;
  v_pct numeric;
  v_threshold integer;
begin
  select * into v_clock from app.ticket_sla_clocks where id = p_clock_id for update;
  if not found then
    return;
  end if;
  if v_clock.status not in ('running', 'paused') then
    return;
  end if;

  select t.* into v_ticket from app.tickets t where t.id = v_clock.ticket_id;

  -- Terminal ticket states end the clock (cancelled: no compliance is owed).
  if v_ticket.status = 'cancelled' then
    begin
      insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, event_type, job_id)
      values (v_clock.tenant_id, v_clock.id, v_clock.ticket_id, 'cancelled', p_job_id);
    exception
      when unique_violation then
        null;
    end;
    update app.ticket_sla_clocks set status = 'cancelled', last_evaluated_at = now() where id = p_clock_id;
    return;
  end if;

  -- Decision 2: response-met is DERIVED from the ticket's own existing
  -- data (first public staff reply), never a write-time hook.
  if v_clock.response_status = 'pending' then
    select min(m.created_at) into v_first_staff_reply_at
    from app.ticket_messages m
    where m.ticket_id = v_clock.ticket_id and m.visibility = 'public' and m.author_role = 'staff';

    if v_first_staff_reply_at is not null then
      v_elapsed := app.replay_ticket_sla_clock_elapsed(p_clock_id, v_first_staff_reply_at);
      begin
        insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, phase, event_type, business_minutes_elapsed, occurred_at, job_id)
        values (
          v_clock.tenant_id, v_clock.id, v_clock.ticket_id, 'response',
          case when v_elapsed <= v_clock.response_target_minutes then 'met' else 'breached' end,
          v_elapsed, v_first_staff_reply_at, p_job_id
        );
      exception
        when unique_violation then
          null;
      end;
    else
      v_elapsed := app.replay_ticket_sla_clock_elapsed(p_clock_id, p_as_of);
      if v_elapsed > v_clock.response_target_minutes then
        begin
          insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, phase, event_type, business_minutes_elapsed, occurred_at, job_id)
          values (v_clock.tenant_id, v_clock.id, v_clock.ticket_id, 'response', 'breached', v_elapsed, p_as_of, p_job_id);
        exception
          when unique_violation then
            null;
        end;
      else
        v_pct := (v_elapsed::numeric / v_clock.response_target_minutes::numeric) * 100;
        foreach v_threshold in array array[50, 80] loop
          if v_pct >= v_threshold then
            begin
              insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, phase, event_type, reminder_threshold_pct, business_minutes_elapsed, occurred_at, job_id)
              values (v_clock.tenant_id, v_clock.id, v_clock.ticket_id, 'response', 'reminder', v_threshold, v_elapsed, p_as_of, p_job_id);
            exception
              when unique_violation then
                null;
            end;
          end if;
        end loop;
      end if;
    end if;
  end if;

  -- Resolution-met is DERIVED from app.tickets.resolved_at (already set by
  -- the existing, unmodified app.transition_ticket_status).
  if v_clock.resolution_status = 'pending' then
    if v_ticket.status in ('resolved', 'closed') and v_ticket.resolved_at is not null then
      v_elapsed := app.replay_ticket_sla_clock_elapsed(p_clock_id, v_ticket.resolved_at);
      begin
        insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, phase, event_type, business_minutes_elapsed, occurred_at, job_id)
        values (
          v_clock.tenant_id, v_clock.id, v_clock.ticket_id, 'resolution',
          case when v_elapsed <= v_clock.resolution_target_minutes then 'met' else 'breached' end,
          v_elapsed, v_ticket.resolved_at, p_job_id
        );
      exception
        when unique_violation then
          null;
      end;
    else
      v_elapsed := app.replay_ticket_sla_clock_elapsed(p_clock_id, p_as_of);
      if v_elapsed > v_clock.resolution_target_minutes then
        begin
          insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, phase, event_type, business_minutes_elapsed, occurred_at, job_id)
          values (v_clock.tenant_id, v_clock.id, v_clock.ticket_id, 'resolution', 'breached', v_elapsed, p_as_of, p_job_id);
        exception
          when unique_violation then
            null;
        end;
      else
        v_pct := (v_elapsed::numeric / v_clock.resolution_target_minutes::numeric) * 100;
        foreach v_threshold in array array[50, 80] loop
          if v_pct >= v_threshold then
            begin
              insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, phase, event_type, reminder_threshold_pct, business_minutes_elapsed, occurred_at, job_id)
              values (v_clock.tenant_id, v_clock.id, v_clock.ticket_id, 'resolution', 'reminder', v_threshold, v_elapsed, p_as_of, p_job_id);
            exception
              when unique_violation then
                null;
            end;
          end if;
        end loop;
      end if;
    end if;
  end if;

  perform app.reconcile_ticket_sla_clock(p_clock_id, null, 'system:sla-evaluation-job');

  if (select response_status from app.ticket_sla_clocks where id = p_clock_id) <> 'pending'
     and (select resolution_status from app.ticket_sla_clocks where id = p_clock_id) <> 'pending' then
    update app.ticket_sla_clocks set status = 'completed' where id = p_clock_id and status = 'running';
  end if;
end;
$$;

comment on function app._evaluate_ticket_sla_clock is
  'HRT-289 (decisions 2/6): the idempotent per-clock evaluation primitive. Locks the clock row FOR UPDATE (serializes concurrent evaluations of the SAME clock for efficiency) AND wraps every ledger INSERT in a real exception handler over the natural-key partial unique indexes (belt-and-suspenders -- the unique index is the actual correctness guarantee per C-01/C-02, the row lock is an efficiency optimization on top of it, live-confirmed by two genuinely concurrent OS psql processes producing exactly one breach row). service_role only -- callers use app.run_ticket_sla_evaluation_batch.';

grant execute on function app._evaluate_ticket_sla_clock(uuid, timestamptz, uuid) to service_role;

-- ===========================================================================
-- 12. Durable job wrapper (decision 8) -- mirrors app.run_training_
--     certificate_expiry_reminder_batch (HRT-284) exactly.
-- ===========================================================================

create function app.run_ticket_sla_evaluation_batch(p_tenant_id uuid, p_as_of timestamptz, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (evaluated_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_worker_id text;
  v_clock record;
  v_evaluated integer := 0;
  v_as_of timestamptz := coalesce(p_as_of, now());
begin
  if not app.check_ticket_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: a non-empty p_period_label is required' using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'ticket_sla_evaluation', jsonb_build_object('as_of', v_as_of, 'period_label', p_period_label),
    0, 'ticket_sla_evaluation:' || p_tenant_id::text || ':' || p_period_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-ticket-sla-evaluation:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    for v_clock in
      select c.id from app.ticket_sla_clocks c where c.tenant_id = p_tenant_id and c.status in ('running', 'paused')
    loop
      perform app._evaluate_ticket_sla_clock(v_clock.id, v_as_of, v_job.job_id);
      v_evaluated := v_evaluated + 1;
    end loop;

    perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_ticket_sla_evaluation_batch',
      'app.jobs', v_job.job_id, 'success', null, null, jsonb_build_object('period_label', p_period_label, 'evaluated_count', v_evaluated)
    );
  end if;

  evaluated_count := v_evaluated; job_id := v_job.job_id;
  return next;
end;
$$;

comment on function app.run_ticket_sla_evaluation_batch is
  'HRT-289 (decisions 6/8): a real app.jobs row tracked through the actual PLT-132 lifecycle (enqueue -> self-claim -> complete). Idempotent per (tenant, period_label) at the JOB level (a replayed period is a pending-status no-op, mirrors app.run_training_certificate_expiry_batch), AND every individual clock evaluation inside the loop is separately idempotent at the LEDGER level regardless of job replay (decision 6) -- two independent, overlapping guarantees, live-tested independently.';

-- ===========================================================================
-- 13. Read RPCs (decision 10, C-02 discipline).
-- ===========================================================================

create function app.get_ticket_sla_clock(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, ticket_id uuid, sla_policy_version_id uuid, sla_calendar_version_id uuid, status text,
  started_at timestamptz, response_target_minutes integer, response_status text, response_met_at timestamptz, response_breached_at timestamptz,
  resolution_target_minutes integer, resolution_status text, resolution_met_at timestamptz, resolution_breached_at timestamptz,
  last_evaluated_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select c.id, c.ticket_id, c.sla_policy_version_id, c.sla_calendar_version_id, c.status,
    c.started_at, c.response_target_minutes, c.response_status, c.response_met_at, c.response_breached_at,
    c.resolution_target_minutes, c.resolution_status, c.resolution_met_at, c.resolution_breached_at,
    c.last_evaluated_at, c.record_version
  from app.ticket_sla_clocks c
  where c.ticket_id = p_ticket_id;
end;
$$;

comment on function app.get_ticket_sla_clock is
  'HRT-289 (decision 10): staff-only full projection (calendar/policy identity included) -- returns zero rows for a non-staff caller (mirrors app.get_ticket_queue_members'' own graceful-empty pattern, never an oracle-shaped exception). The ticket''s own requester-side party uses app.get_ticket_sla_status_for_requester instead.';

create function app.get_ticket_sla_status_for_requester(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  ticket_id uuid, response_target_minutes integer, response_status text,
  resolution_target_minutes integer, resolution_status text
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select t.* into v_ticket from app.tickets t where t.id = p_ticket_id;
  if not found then
    return;
  end if;
  if not (app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id) or app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id)) then
    return;
  end if;
  return query
  select c.ticket_id, c.response_target_minutes, c.response_status, c.resolution_target_minutes, c.resolution_status
  from app.ticket_sla_clocks c
  where c.ticket_id = p_ticket_id;
end;
$$;

comment on function app.get_ticket_sla_status_for_requester is
  'HRT-289 (decision 10, section 16 "customer users see only customer-safe target/status"): the customer/requester-safe projection -- NO calendar identity, NO policy identity, NO pause reason, NO started_at/*_at timestamps beyond status. Reused for internal/customer/helpdesk requesters alike via app._is_ticket_requester_party (never re-derived); also readable by staff for their own preview.';

create function app.list_ticket_sla_clock_events(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, phase text, event_type text, reminder_threshold_pct integer, business_minutes_elapsed integer,
  occurred_at timestamptz, actor_label text, reason text
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select e.id, e.phase, e.event_type, e.reminder_threshold_pct, e.business_minutes_elapsed, e.occurred_at, e.actor_label, e.reason
  from app.ticket_sla_clock_events e
  where e.ticket_id = p_ticket_id
  order by e.occurred_at asc;
end;
$$;

create function app.list_ticket_sla_events_for_requester(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (phase text, event_type text, occurred_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select t.* into v_ticket from app.tickets t where t.id = p_ticket_id;
  if not found then
    return;
  end if;
  if not (app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id) or app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id)) then
    return;
  end if;
  return query
  select e.phase, e.event_type, e.occurred_at
  from app.ticket_sla_clock_events e
  where e.ticket_id = p_ticket_id and e.event_type in ('met', 'breached')
  order by e.occurred_at asc;
end;
$$;

comment on function app.list_ticket_sla_events_for_requester is
  'HRT-289 (decision 10): only met/breached rows -- never paused/resumed/recalculated (which would leak internal pause-reason existence and staff-correction activity to a requester).';

create function app.list_sla_calendars(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text, status text, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select c.id, c.code, c.name, c.status, c.record_version from app.sla_calendars c where c.tenant_id = p_tenant_id order by c.code asc;
end;
$$;

create function app.list_sla_calendar_versions(p_calendar_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, version_number integer, status text, timezone text, is_24x7 boolean, published_at timestamptz, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_calendar app.sla_calendars;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select c0.* into v_calendar from app.sla_calendars c0 where c0.id = p_calendar_id;
  if not found or not app.has_active_tenant_membership(v_calendar.tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_calendar.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select v.id, v.version_number, v.status, v.timezone, v.is_24x7, v.published_at, v.record_version
  from app.sla_calendar_versions v where v.calendar_id = p_calendar_id order by v.version_number desc;
end;
$$;

create function app.list_sla_policies(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text, status text, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select p.id, p.code, p.name, p.status, p.record_version from app.sla_policies p where p.tenant_id = p_tenant_id order by p.code asc;
end;
$$;

create function app.list_sla_policy_versions(p_policy_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, version_number integer, status text, channel text, category_id uuid, priority text,
  customer_account_id uuid, queue_id uuid, support_queue_id uuid, calendar_id uuid,
  response_target_minutes integer, resolution_target_minutes integer, precedence_rank integer,
  published_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_policy app.sla_policies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select p0.* into v_policy from app.sla_policies p0 where p0.id = p_policy_id;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(v_policy.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select v.id, v.version_number, v.status, v.channel, v.category_id, v.priority, v.customer_account_id, v.queue_id,
    v.support_queue_id, v.calendar_id, v.response_target_minutes, v.resolution_target_minutes, v.precedence_rank,
    v.published_at, v.record_version
  from app.sla_policy_versions v where v.policy_id = p_policy_id order by v.version_number desc;
end;
$$;

-- ===========================================================================
-- 14. RLS (decision 10).
-- ===========================================================================

alter table app.sla_calendars enable row level security;
alter table app.sla_calendar_versions enable row level security;
alter table app.sla_calendar_business_hours enable row level security;
alter table app.sla_calendar_holidays enable row level security;
alter table app.sla_policies enable row level security;
alter table app.sla_policy_versions enable row level security;
alter table app.ticket_sla_clocks enable row level security;
alter table app.ticket_sla_clock_events enable row level security;

create policy sla_calendars_select_scoped on app.sla_calendars
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy sla_calendar_versions_select_scoped on app.sla_calendar_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy sla_calendar_business_hours_select_scoped on app.sla_calendar_business_hours
  for select to authenticated
  using (
    exists (
      select 1 from app.sla_calendar_versions v
      where v.id = calendar_version_id and (app.has_active_tenant_membership(v.tenant_id) and not app.actor_holds_customer_user_layer(v.tenant_id))
    ) or app.is_supreme_admin()
  );

create policy sla_calendar_holidays_select_scoped on app.sla_calendar_holidays
  for select to authenticated
  using (
    exists (
      select 1 from app.sla_calendar_versions v
      where v.id = calendar_version_id and (app.has_active_tenant_membership(v.tenant_id) and not app.actor_holds_customer_user_layer(v.tenant_id))
    ) or app.is_supreme_admin()
  );

create policy sla_policies_select_scoped on app.sla_policies
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy sla_policy_versions_select_scoped on app.sla_policy_versions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy ticket_sla_clocks_select_scoped on app.ticket_sla_clocks
  for select to authenticated
  using (app.can_access_ticket(ticket_id) or app.is_supreme_admin());

create policy ticket_sla_clock_events_select_scoped on app.ticket_sla_clock_events
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and app.is_ticket_staff(ticket_id)) or app.is_supreme_admin());

comment on policy ticket_sla_clock_events_select_scoped on app.ticket_sla_clock_events is
  'HRT-289 (decision 10): unlike app.ticket_events (any ticket participant), the SLA ledger''s raw-table RLS is STAFF-ONLY -- a requester reads SLA status only through app.get_ticket_sla_status_for_requester/app.list_ticket_sla_events_for_requester, never the raw table, because a pause reason on this ledger is a materially more operationally-sensitive detail than a status-change reason on app.ticket_events.';

-- ===========================================================================
-- 15. Grants (decision 10) -- explicit, deliberate, never blanket.
-- ===========================================================================

-- ERR-2026-004: Postgres grants EXECUTE to PUBLIC by default on function
-- creation, so this migration's own new functions need an explicit revoke,
-- not just the deliberate per-function grants below -- self-found in this
-- checkpoint's own full db:test run (ATW-032/ISS-2026-032's own live
-- has_function_privilege('authenticated', ...) sweep, which checks EFFECTIVE
-- privilege, caught app.reconcile_ticket_sla_clock still PUBLIC-executable
-- despite its own explicit service_role-only grant below). Mirrors every
-- prior HRT-286/287/288 ticketing migration's own identical statement.
revoke execute on all functions in schema app from public;

grant select on app.sla_calendars to authenticated;
grant select on app.sla_calendars to service_role;
grant select on app.sla_calendar_versions to authenticated;
grant select on app.sla_calendar_versions to service_role;
grant select on app.sla_calendar_business_hours to authenticated;
grant select on app.sla_calendar_business_hours to service_role;
grant select on app.sla_calendar_holidays to authenticated;
grant select on app.sla_calendar_holidays to service_role;
grant select on app.sla_policies to authenticated;
grant select on app.sla_policies to service_role;
grant select on app.sla_policy_versions to authenticated;
grant select on app.sla_policy_versions to service_role;
grant select on app.ticket_sla_clocks to authenticated;
grant select on app.ticket_sla_clocks to service_role;
grant select on app.ticket_sla_clock_events to authenticated;
grant select on app.ticket_sla_clock_events to service_role;

grant execute on function app.create_sla_calendar(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_sla_calendar_version(uuid, text, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.add_sla_calendar_business_hours(uuid, smallint, time, time, uuid, text) to authenticated, service_role;
grant execute on function app.add_sla_calendar_holiday(uuid, date, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_sla_calendar_version(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.create_sla_policy(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_sla_policy_version(uuid, text, uuid, text, uuid, uuid, uuid, uuid, integer, integer, integer, uuid, text) to authenticated, service_role;
grant execute on function app.publish_sla_policy_version(uuid, integer, uuid, text) to authenticated, service_role;

grant execute on function app.start_ticket_sla_clock(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.pause_ticket_sla_clock(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.resume_ticket_sla_clock(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.recalculate_ticket_sla_clock(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.run_ticket_sla_evaluation_batch(uuid, timestamptz, text, uuid, text) to authenticated, service_role;

grant execute on function app.get_ticket_sla_clock(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ticket_sla_status_for_requester(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_sla_clock_events(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_ticket_sla_events_for_requester(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_sla_calendars(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_sla_calendar_versions(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_sla_policies(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_sla_policy_versions(uuid, uuid) to authenticated, service_role;

grant execute on function app.ticket_sla_clock_audit_projection(app.ticket_sla_clocks) to authenticated, service_role;
