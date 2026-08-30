-- ISS-2026-251 (docs/runtime/KNOWN_ISSUES.md, Medium) -- `app.alert_routes.owner_team`/
-- `owner_email` are real and correctly copied onto each incident, but were inert routing
-- metadata: nothing dispatched to them, and no automatic escalation existed, so an
-- unacknowledged incident never paged anyone. Business Rule §24 requires "owner, severity,
-- deduplication **and escalation path**" -- three of four were real; the escalation path
-- was the genuinely absent piece.
--
-- ---------------------------------------------------------------------------------------
-- Half of this entry is already closed, and this migration closes the other half
-- ---------------------------------------------------------------------------------------
--
-- The entry names two distinct absences, and its 2026-08-28 re-verification confirmed both
-- by searching for vendor SDKs (`pagerduty|slack|sendgrid|smtp|twilio|…`) and finding none:
--
--   1. **No dispatch mechanism** -- nothing ever contacted the owner. Closed on 2026-08-30
--      by `20260830140000_create_incident_communication.sql` (`ISS-2026-258`), which
--      reaches the incident's own alert-route owner through `PLT-127`'s Notification
--      Engine. That re-verification searched for third-party *vendor* SDKs and correctly
--      found none -- but this repository's own Notification Engine was never in that search
--      pattern, and it is the dispatch mechanism. `owner_email` is no longer inert.
--
--   2. **No automatic escalation** -- "an unacknowledged-after-N-minutes reminder". Still
--      absent after that fix, because a broadcast is a deliberate human action. **This
--      migration closes it.**
--
-- Building it here rather than as a second dispatch path is the point `ISS-2026-251` itself
-- makes: it composes `app.broadcast_incident_communication`, so an escalation reaches its
-- audience through exactly the same mechanism, leaves exactly the same record, and cannot
-- drift from it.
--
-- ---------------------------------------------------------------------------------------
-- Thresholds are policy, not constants
-- ---------------------------------------------------------------------------------------
--
-- `app.incident_escalation_policies` carries per-severity thresholds, with platform
-- defaults as `tenant_id is null` rows and per-tenant overrides layered on top -- the same
-- nullable-tenant registry shape `app.alert_routes` already uses. The seeded defaults are
-- anchored to `docs/architecture/11_DEVOPS_WORKSTREAM.md` §8.4's own P1-P4 response
-- targets (P1 = 15 minutes) rather than invented: a `critical` incident escalates if
-- unacknowledged for 15 minutes.
--
-- ---------------------------------------------------------------------------------------
-- What this does NOT do, stated rather than left to be discovered
-- ---------------------------------------------------------------------------------------
--
-- **Nothing invokes the sweep on a timer.** `app.run_incident_escalation_sweep` is a real,
-- authority-gated, idempotent, tested function; what calls it every N minutes is an
-- operational wiring step (a scheduler, a cron, a platform hook) that does not exist in
-- this repository for *any* batch. That is not a gap peculiar to this fix:
-- `app.run_ticket_sla_evaluation_batch`, `app.run_ticket_escalation_evaluation_batch`,
-- `app.run_leave_accrual_batch`, `app.run_loyalty_expiry_sweep` and every other `run_*`
-- batch here sit in exactly the same position, and `PLT-131`'s own header already disclosed
-- that `app.jobs.locked_by`/`locked_until` are real columns with no live worker behind them.
-- Escalation now *exists and is callable*, where before it did not exist at all; being
-- called on a schedule is a deployment concern, and it is named as one in this entry's own
-- KNOWN_ISSUES annotation rather than implied to be done.
--
-- Per `ERR-2026-004`: explicit `revoke execute on all functions in schema app from public;`
-- before the final grants. No already-applied migration is edited.

-- ===========================================================================
-- 1. Job type widening -- BOTH places, in lockstep.
--
--    app.generic_job_types() is the single source of truth app.enqueue_job
--    reads (20260730410000), and jobs_job_type_check must stay set-equal to
--    it -- a standing drift-gate assertion in
--    scripts/db-tests/background-job.sql enforces exactly that. Widening one
--    without the other fails that gate, which is the point of having it.
--
--    Both lists are carried forward from 20260807500000, the LATEST of the
--    successive widenings. A first draft of this migration copied
--    20260805050000's list instead and silently dropped 'audit_export' and
--    'retention_archive' -- caught on the first run by
--    scripts/db-tests/advanced-audit-impersonation.sql, not by review. Restating
--    a 28-item list by hand is exactly the transcription hazard this repository
--    keeps meeting; the correct list was extracted programmatically from the
--    latest definition rather than retyped.
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync', 'external_sync',
    'audit_export', 'retention_archive', 'incident_escalation_sweep'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'ISS-2026-251: widened to add ''incident_escalation_sweep''. The full prior list is carried forward verbatim from 20260807500000 (the latest of the successive widenings -- a first draft of this migration copied 20260805050000''s list instead and dropped audit_export/retention_archive, caught immediately by advanced-audit-impersonation.sql). Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

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
    'audit_export', 'retention_archive', 'incident_escalation_sweep'
  ]::text[];
$$;

-- ===========================================================================
-- 2. Thresholds as policy.
-- ===========================================================================

create table app.incident_escalation_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  severity text not null,
  unacknowledged_after_minutes integer not null,
  unresolved_after_minutes integer not null,
  updated_by text,
  updated_at timestamptz not null default now(),
  constraint incident_escalation_policies_severity_check check (severity in ('low', 'medium', 'high', 'critical')),
  constraint incident_escalation_policies_unack_check check (unacknowledged_after_minutes between 1 and 10080),
  constraint incident_escalation_policies_unresolved_check check (unresolved_after_minutes between 1 and 43200),
  -- An "unresolved" escalation that could fire before the "unacknowledged" one would
  -- invert the ladder and page the second level first.
  constraint incident_escalation_policies_ladder_check check (unresolved_after_minutes >= unacknowledged_after_minutes),
  constraint incident_escalation_policies_unique unique nulls not distinct (tenant_id, severity)
);

comment on table app.incident_escalation_policies is
  'ISS-2026-251: per-severity escalation thresholds. tenant_id null is the platform default; a tenant row overrides it for that tenant only -- the same nullable-tenant registry shape app.alert_routes already uses. Seeded defaults are anchored to docs/architecture/11_DEVOPS_WORKSTREAM.md §8.4''s own P1-P4 response targets rather than invented.';

create index incident_escalation_policies_tenant_idx on app.incident_escalation_policies (tenant_id, severity);

insert into app.incident_escalation_policies (tenant_id, severity, unacknowledged_after_minutes, unresolved_after_minutes, updated_by) values
  (null, 'critical', 15, 60, 'platform-default'),
  (null, 'high', 30, 240, 'platform-default'),
  (null, 'medium', 120, 1440, 'platform-default'),
  (null, 'low', 480, 4320, 'platform-default');

create function app.set_incident_escalation_policy(
  p_tenant_id uuid,
  p_severity text,
  p_unacknowledged_after_minutes integer,
  p_unresolved_after_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.incident_escalation_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_authorized boolean;
  v_policy app.incident_escalation_policies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- The platform default is Supreme Admin's to set; a tenant's own override needs
  -- MON:Configure for that tenant. Mirrors app.set_alert_route exactly.
  if p_tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'Configure');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to set an incident escalation policy', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.incident_escalation_policies (tenant_id, severity, unacknowledged_after_minutes, unresolved_after_minutes, updated_by)
  values (p_tenant_id, p_severity, p_unacknowledged_after_minutes, p_unresolved_after_minutes, p_actor_label)
  on conflict (tenant_id, severity) do update
    set unacknowledged_after_minutes = excluded.unacknowledged_after_minutes,
        unresolved_after_minutes = excluded.unresolved_after_minutes,
        updated_by = excluded.updated_by,
        updated_at = now()
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_incident_escalation_policy',
    'app.incident_escalation_policies', v_policy.id, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$$;

comment on function app.set_incident_escalation_policy is
  'ISS-2026-251: upserts one (tenant, severity) escalation threshold pair. Supreme Admin for the platform default (tenant_id null), MON:Configure for a tenant override -- mirroring app.set_alert_route.';

create function app.resolve_incident_escalation_policy(p_tenant_id uuid, p_severity text)
returns app.incident_escalation_policies
language sql
stable
set search_path = app, pg_temp
as $$
  select * from app.incident_escalation_policies
  where severity = p_severity and (tenant_id = p_tenant_id or tenant_id is null)
  -- The tenant's own row wins over the platform default when both exist.
  order by (tenant_id is null)
  limit 1;
$$;

comment on function app.resolve_incident_escalation_policy is
  'ISS-2026-251: the effective threshold pair for one tenant and severity -- the tenant''s own override when present, otherwise the platform default. Ordering by (tenant_id is null) puts the specific row first.';

-- ===========================================================================
-- 3. What has already been escalated.
-- ===========================================================================

create table app.incident_escalations (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null references app.incidents (id),
  level text not null,
  escalated_at timestamptz not null default now(),
  communication_id uuid references app.incident_communications (id),
  job_id uuid,
  constraint incident_escalations_level_check check (level in ('unacknowledged', 'unresolved')),
  constraint incident_escalations_unique unique (incident_id, level)
);

create index incident_escalations_incident_idx on app.incident_escalations (incident_id, escalated_at desc);

comment on table app.incident_escalations is
  'ISS-2026-251: one row per (incident, escalation level), uniquely constrained. That unique index -- not the sweep''s job row -- is the real idempotency guarantee: an incident escalates at most once per level no matter how often the sweep runs, how many sweeps run concurrently, or whether a job row exists at all. communication_id links to the message the escalation actually sent, so "we escalated" and "we told someone" are provably the same event rather than two claims.';

-- ===========================================================================
-- 4. The sweep.
-- ===========================================================================

create function app.run_incident_escalation_sweep(
  p_tenant_id uuid,
  p_as_of timestamptz,
  p_period_label text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (escalated_count integer, job_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_job_id uuid;
  v_worker_id text;
  v_decision app.rbac_decision;
  v_authorized boolean;
  v_as_of timestamptz := coalesce(p_as_of, now());
  v_incident record;
  v_policy app.incident_escalation_policies;
  v_level text;
  v_comm app.incident_communications;
  v_escalated integer := 0;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'Edit');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to run the incident escalation sweep', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_period_label is null or length(trim(p_period_label)) = 0 then
    raise exception 'invalid_period: a non-empty p_period_label is required' using errcode = 'check_violation';
  end if;

  -- A job row is tracked for a tenant-scoped sweep, following
  -- app.run_ticket_escalation_evaluation_batch's own enqueue -> self-claim -> complete
  -- shape. A PLATFORM-scoped sweep gets none, and that is a fact about app.jobs rather
  -- than a shortcut: app.jobs.tenant_id is NOT NULL, so there is no job row a
  -- platform-scoped run could legitimately be attached to. Nothing is lost -- the real
  -- idempotency guarantee is incident_escalations_unique, not the job.
  if p_tenant_id is not null then
    v_job := app.enqueue_job(
      p_tenant_id, 'incident_escalation_sweep',
      jsonb_build_object('as_of', v_as_of, 'period_label', p_period_label),
      0, 'incident_escalation_sweep:' || p_tenant_id::text || ':' || p_period_label, 1,
      p_actor_auth_user_id, p_actor_label
    );
    v_job_id := v_job.job_id;
    if v_job.status <> 'pending' then
      -- This exact period already ran. Return its job without re-sweeping.
      escalated_count := 0; job_id := v_job_id;
      return next;
      return;
    end if;
    v_worker_id := 'inline-incident-escalation-sweep:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
    where j.job_id = v_job_id and j.status = 'pending';
  end if;

  for v_incident in
    select i.* from app.incidents i
    where i.tenant_id is not distinct from p_tenant_id
      and i.status <> 'resolved'
    order by i.opened_at asc
  loop
    v_policy := app.resolve_incident_escalation_policy(v_incident.tenant_id, v_incident.severity);
    if v_policy is null then
      continue;
    end if;

    -- The two levels are a LADDER, not two independent flags, and getting that wrong is
    -- how a sweep double-pages. A first version escalated the higher level ('unresolved')
    -- on one run and then, on the next run, escalated the SAME incident again at the lower
    -- level ('unacknowledged') because that row did not exist yet -- caught by this fix's
    -- own regression, not by review. Once the top of the ladder has been raised, there is
    -- nothing below it left to say.
    if exists (select 1 from app.incident_escalations e where e.incident_id = v_incident.id and e.level = 'unresolved') then
      continue;
    end if;

    v_level := null;
    if v_incident.status in ('open', 'acknowledged')
       and v_incident.opened_at <= v_as_of - (v_policy.unresolved_after_minutes || ' minutes')::interval then
      v_level := 'unresolved';
    elsif v_incident.status = 'open'
       and v_incident.opened_at <= v_as_of - (v_policy.unacknowledged_after_minutes || ' minutes')::interval
       and not exists (select 1 from app.incident_escalations e where e.incident_id = v_incident.id and e.level = 'unacknowledged') then
      v_level := 'unacknowledged';
    end if;

    if v_level is null then
      continue;
    end if;

    -- Claim the level FIRST. Two concurrent sweeps both reaching this incident must not
    -- both send: the loser hits incident_escalations_unique and skips, rather than
    -- double-paging an on-call engineer at 3am.
    begin
      insert into app.incident_escalations (incident_id, level, job_id)
      values (v_incident.id, v_level, v_job_id);
    exception
      when unique_violation then
        continue;
    end;

    v_comm := app.broadcast_incident_communication(
      v_incident.id, 'internal',
      case v_level
        when 'unresolved' then 'ESCALATION: still unresolved -- ' || v_incident.title
        else 'ESCALATION: unacknowledged -- ' || v_incident.title
      end,
      case v_level
        when 'unresolved' then
          'This ' || v_incident.severity || ' incident has been open since ' || to_char(v_incident.opened_at, 'YYYY-MM-DD HH24:MI') ||
          ' UTC and is still unresolved, past the ' || v_policy.unresolved_after_minutes ||
          '-minute threshold for its severity. Escalating.'
        else
          'This ' || v_incident.severity || ' incident has been open since ' || to_char(v_incident.opened_at, 'YYYY-MM-DD HH24:MI') ||
          ' UTC and nobody has acknowledged it, past the ' || v_policy.unacknowledged_after_minutes ||
          '-minute threshold for its severity. Escalating.'
      end,
      null,
      'escalation:' || v_incident.id::text || ':' || v_level,
      p_actor_auth_user_id, p_actor_label
    );

    update app.incident_escalations
    set communication_id = v_comm.id
    where incident_id = v_incident.id and level = v_level;

    v_escalated := v_escalated + 1;
  end loop;

  if v_job_id is not null then
    perform app.complete_job(v_job_id, v_worker_id, null, p_actor_label);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_incident_escalation_sweep',
    'app.incidents', null, 'success', null, null,
    jsonb_build_object('period_label', p_period_label, 'escalated_count', v_escalated, 'as_of', v_as_of)
  );

  escalated_count := v_escalated; job_id := v_job_id;
  return next;
end;
$$;

comment on function app.run_incident_escalation_sweep is
  'ISS-2026-251: escalates every unacknowledged or long-unresolved incident past its severity''s own threshold, by composing app.broadcast_incident_communication -- so an escalation reaches its audience through the same mechanism, and leaves the same record, as any other incident message. It never builds a second dispatch path, which is the caution ISS-2026-251 itself raises. The two levels are a ladder, not independent flags: once ''unresolved'' is raised nothing below it fires again. The escalation row is also claimed BEFORE the message is sent, so two concurrent sweeps cannot double-page either. Tenant-scoped runs are tracked as a real PLT-132 job (enqueue -> self-claim -> complete, idempotent per period, mirroring app.run_ticket_escalation_evaluation_batch); a platform-scoped run has no job because app.jobs.tenant_id is NOT NULL, and loses nothing -- incident_escalations_unique is the real guarantee. NOTHING INVOKES THIS ON A TIMER: that is an operational wiring step this repository has for no batch, and it is disclosed rather than implied.';

-- ===========================================================================
-- 5. Reads.
-- ===========================================================================

create function app.list_incident_escalation_policies(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.incident_escalation_policies
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'View');
  if not v_decision.allowed and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks MON:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.incident_escalation_policies
  where tenant_id = p_tenant_id or tenant_id is null
  order by severity, (tenant_id is null);
end;
$$;

comment on function app.list_incident_escalation_policies is
  'ISS-2026-251: the escalation thresholds visible to one tenant -- its own overrides and the platform defaults they sit on top of, so a reader can see BOTH what applies and what it replaced. MON:View-gated.';

create function app.list_incident_escalations(p_incident_id uuid, p_actor_auth_user_id uuid)
returns setof app.incident_escalations
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_incident app.incidents;
  v_decision app.rbac_decision;
  v_authorized boolean;
begin
  select * into v_incident from app.incidents where id = p_incident_id;
  if not found then
    raise exception 'incident_not_found: %', p_incident_id using errcode = 'no_data_found';
  end if;
  if v_incident.tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_incident.tenant_id, 'MON', 'View');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks MON:View for incident %', p_actor_auth_user_id, p_incident_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.incident_escalations where incident_id = p_incident_id order by escalated_at asc;
end;
$$;

comment on function app.list_incident_escalations is
  'ISS-2026-251: the escalation history of one incident, oldest first. MON:View-gated (Supreme Admin for a platform-scoped incident), mirroring app.list_incident_communications.';

-- ===========================================================================
-- 6. RLS: default-deny, RPC-only.
-- ===========================================================================

alter table app.incident_escalation_policies enable row level security;
alter table app.incident_escalations enable row level security;

revoke all on app.incident_escalation_policies from public, anon, authenticated;
revoke all on app.incident_escalations from public, anon, authenticated;
grant all on app.incident_escalation_policies, app.incident_escalations to service_role;

-- ===========================================================================
-- 7. PostgREST wrappers (mode parity with each app.* counterpart).
-- ===========================================================================

create function public.set_incident_escalation_policy(p_tenant_id uuid, p_severity text, p_unacknowledged_after_minutes integer, p_unresolved_after_minutes integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.incident_escalation_policies
language sql
security definer
set search_path = app, public, pg_temp
as $$
  select app.set_incident_escalation_policy(p_tenant_id, p_severity, p_unacknowledged_after_minutes, p_unresolved_after_minutes, p_actor_auth_user_id, p_actor_label);
$$;

create function public.resolve_incident_escalation_policy(p_tenant_id uuid, p_severity text)
returns app.incident_escalation_policies
language sql
stable
set search_path = app, public, pg_temp
as $$
  select app.resolve_incident_escalation_policy(p_tenant_id, p_severity);
$$;

create function public.run_incident_escalation_sweep(p_tenant_id uuid, p_as_of timestamptz, p_period_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns table (escalated_count integer, job_id uuid)
language sql
security definer
set search_path = app, public, pg_temp
as $$
  select * from app.run_incident_escalation_sweep(p_tenant_id, p_as_of, p_period_label, p_actor_auth_user_id, p_actor_label);
$$;

create function public.list_incident_escalation_policies(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.incident_escalation_policies
language sql
stable
security definer
set search_path = app, public, pg_temp
as $$
  select * from app.list_incident_escalation_policies(p_tenant_id, p_actor_auth_user_id);
$$;

create function public.list_incident_escalations(p_incident_id uuid, p_actor_auth_user_id uuid)
returns setof app.incident_escalations
language sql
stable
security definer
set search_path = app, public, pg_temp
as $$
  select * from app.list_incident_escalations(p_incident_id, p_actor_auth_user_id);
$$;

-- ===========================================================================
-- 8. Grants (ERR-2026-004).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function
  app.set_incident_escalation_policy(uuid, text, integer, integer, uuid, text),
  app.resolve_incident_escalation_policy(uuid, text),
  app.run_incident_escalation_sweep(uuid, timestamptz, text, uuid, text),
  app.list_incident_escalation_policies(uuid, uuid),
  app.list_incident_escalations(uuid, uuid)
to authenticated, service_role;

revoke execute on function public.set_incident_escalation_policy(uuid, text, integer, integer, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.set_incident_escalation_policy(uuid, text, integer, integer, uuid, text) to authenticated, service_role;

revoke execute on function public.resolve_incident_escalation_policy(uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.resolve_incident_escalation_policy(uuid, text) to authenticated, service_role;

revoke execute on function public.run_incident_escalation_sweep(uuid, timestamptz, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.run_incident_escalation_sweep(uuid, timestamptz, text, uuid, text) to authenticated, service_role;

revoke execute on function public.list_incident_escalation_policies(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_incident_escalation_policies(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_incident_escalations(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_incident_escalations(uuid, uuid) to authenticated, service_role;
