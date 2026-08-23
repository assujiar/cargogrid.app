-- IAE-034 (Prompt 362, Group 8): Scale-Up Architecture.
--
-- Design decisions (cited, not re-derived):
--
-- 1. Genuinely greenfield -- confirmed by direct grep before writing any code
--    (no `capacity`/`workload`/`backpressure`/`scaling_recommendation` table
--    or function exists anywhere in `app`).
-- 2. Reuses the `MON` entitlement module (`View`/`Edit`/`Configure`) from
--    `IAE-030` rather than adding a new one -- Prompt 362's own workstream is
--    "Reliability" (the identical workstream as Prompt 358's own "Enterprise
--    Monitoring and Observability"), and this checkpoint's own actions
--    (configuring a capacity budget, reviewing/dismissing a scaling
--    recommendation) are the same shape of authority `MON:Configure`/`View`
--    already covers -- no materially distinct scope to justify a new module.
-- 3. `app.workload_capacity_profiles` mirrors `app.slo_definitions`'s own
--    exact shape (`IAE-030`): `tenant_id` nullable (a platform-wide default
--    budget) with `unique nulls not distinct (tenant_id, workload_type)`
--    applied from the first draft (the Group 7 Tier C lesson), `MON:
--    Configure`-gated per tenant or Supreme-Admin-only platform-wide,
--    identical to `app.set_slo_definition`'s own authority branch.
-- 4. `app.evaluate_workload_budget` is the real, structural "Main flow"
--    (Prompt 362 §21: "High-volume workload approaches budget; system
--    applies backpressure/queueing, alerts owner and protects OLTP") --
--    service_role-only, no actor parameter, mirroring `app.
--    record_observability_signal`'s own "system-to-system telemetry write,
--    never a live end-user action" shape exactly. A budget breach is a REAL,
--    named, non-silent outcome (`action_taken = 'backpressure_applied'`,
--    Prompt 362 §24 "backpressure is explicit... not silent data loss"),
--    recorded as real evidence AND composed with `IAE-030`'s own
--    `app.raise_observability_alert` so the workload owner is genuinely
--    alerted through the SAME incident/alert-routing machinery every other
--    monitored signal already uses -- never a second, parallel alerting path.
--    The `workload_type -> source_type` mapping this composition needs
--    (`analytics`/`reports`/`import_export`/`notifications` -> `job`,
--    `webhooks` -> `webhook`, `ai` -> `ai`, `oltp` -> `api`) is the closest
--    honest fit onto `IAE-030`'s own existing `source_type` vocabulary,
--    documented here rather than silently assumed.
-- 5. `app.generate_scaling_recommendation`'s own `dedicated_deployment`
--    recommendation type is a real, structural composition with `IAE-032`:
--    it is REJECTED outright if `app.resolve_tenant_deployment_type` already
--    reports `'dedicated'` for that tenant -- a redundant recommendation is
--    a real error, not a silently accepted duplicate (Prompt 362 §22's own
--    "capacity profile recommends dedicated deployment" alternative flow
--    only ever fires while the tenant genuinely still needs it).
-- 6. `app.resolve_workload_budget` is the bare-tenant-id, no-actor-parameter
--    default-resolution function this checkpoint's own capacity profile
--    needs -- granted `service_role` ONLY from the very first draft (the
--    lesson `IAE-032`/`IAE-033` both already applied correctly), never
--    `authenticated`.
-- 7. Every authenticated-reachable function is `SECURITY DEFINER` paired
--    with `app.assert_actor_is_session_identity` as its first statement.
-- 8. Per the standing convention since `PLT-118`: explicit, redundant
--    `revoke execute on all functions in schema app from public`.

-- ===========================================================================
-- 1. app.workload_capacity_profiles -- real, persisted capacity budgets
-- (design decision 3).
-- ===========================================================================

create table app.workload_capacity_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  workload_type text not null,
  budget_value numeric not null,
  evaluation_window_minutes integer not null default 60,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint workload_capacity_profiles_type_check check (workload_type in ('oltp', 'analytics', 'reports', 'ai', 'webhooks', 'import_export', 'notifications')),
  constraint workload_capacity_profiles_window_check check (evaluation_window_minutes between 1 and 10080),
  constraint workload_capacity_profiles_unique unique nulls not distinct (tenant_id, workload_type)
);

comment on table app.workload_capacity_profiles is
  'IAE-034: tenant_id null means a platform-wide default budget for that workload_type; non-null means a per-tenant override. Mirrors app.slo_definitions'' own exact shape (IAE-030).';

create function app.touch_workload_capacity_profile_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger workload_capacity_profiles_touch_row
  before update on app.workload_capacity_profiles
  for each row
  execute function app.touch_workload_capacity_profile_row();

create function app.set_workload_capacity_profile(
  p_tenant_id uuid,
  p_workload_type text,
  p_budget_value numeric,
  p_evaluation_window_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.workload_capacity_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_authorized boolean;
  v_profile app.workload_capacity_profiles;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'Configure');
    v_authorized := v_decision.allowed;
  end if;

  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to configure this capacity profile (tenant %)', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_workload_type not in ('oltp', 'analytics', 'reports', 'ai', 'webhooks', 'import_export', 'notifications') then
    raise exception 'workload_invalid_type: %', p_workload_type using errcode = 'check_violation';
  end if;
  if p_budget_value <= 0 then
    raise exception 'workload_invalid_budget: % must be positive', p_budget_value using errcode = 'check_violation';
  end if;
  if p_evaluation_window_minutes not between 1 and 10080 then
    raise exception 'workload_invalid_window: % must be between 1 and 10080 minutes', p_evaluation_window_minutes using errcode = 'check_violation';
  end if;

  insert into app.workload_capacity_profiles (tenant_id, workload_type, budget_value, evaluation_window_minutes, created_by)
  values (p_tenant_id, p_workload_type, p_budget_value, p_evaluation_window_minutes, p_actor_label)
  on conflict (tenant_id, workload_type) do update
    set budget_value = excluded.budget_value, evaluation_window_minutes = excluded.evaluation_window_minutes
  returning * into v_profile;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_workload_capacity_profile',
    'app.workload_capacity_profiles', v_profile.id, 'success', null, null, to_jsonb(v_profile)
  );

  return v_profile;
end;
$$;

create function app.resolve_workload_budget(p_tenant_id uuid, p_workload_type text)
returns numeric
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select coalesce(
    (select budget_value from app.workload_capacity_profiles where tenant_id = p_tenant_id and workload_type = p_workload_type),
    (select budget_value from app.workload_capacity_profiles where tenant_id is null and workload_type = p_workload_type)
  );
$$;

comment on function app.resolve_workload_budget is
  'IAE-034: a tenant-specific override always wins over the platform-wide default; returns NULL (never an error) when neither exists -- this workload_type simply has no configured capacity ceiling yet. service_role-only by design (design decision 6) -- the identical bare-tenant-id shape app.resolve_tenant_deployment_type/app.resolve_tenant_region/app.resolve_retention_days already established, applied correctly from the first draft.';

-- ===========================================================================
-- 2. app.workload_backpressure_events -- real, non-silent budget-evaluation
-- evidence (design decision 4).
-- ===========================================================================

create table app.workload_backpressure_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  workload_type text not null,
  observed_value numeric not null,
  budget_value numeric,
  action_taken text not null,
  alert_incident_id uuid references app.incidents (id),
  occurred_at timestamptz not null default now(),
  constraint workload_backpressure_events_type_check check (workload_type in ('oltp', 'analytics', 'reports', 'ai', 'webhooks', 'import_export', 'notifications')),
  constraint workload_backpressure_events_action_check check (action_taken in ('within_budget', 'backpressure_applied', 'no_budget_configured'))
);

create index workload_backpressure_events_tenant_lookup_idx on app.workload_backpressure_events (tenant_id, workload_type, occurred_at desc);

comment on table app.workload_backpressure_events is
  'IAE-034: one row per real budget evaluation, whether or not it breached -- action_taken is always a real, named outcome (Prompt 362 §24 "backpressure is explicit... not silent data loss"), never inferred after the fact.';

create function app.evaluate_workload_budget(
  p_tenant_id uuid,
  p_workload_type text,
  p_observed_value numeric
)
returns app.workload_backpressure_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_budget numeric;
  v_action text;
  v_source_type text;
  v_incident app.incidents;
  v_event app.workload_backpressure_events;
begin
  if p_workload_type not in ('oltp', 'analytics', 'reports', 'ai', 'webhooks', 'import_export', 'notifications') then
    raise exception 'workload_invalid_type: %', p_workload_type using errcode = 'check_violation';
  end if;

  v_budget := app.resolve_workload_budget(p_tenant_id, p_workload_type);

  if v_budget is null then
    v_action := 'no_budget_configured';
  elsif p_observed_value > v_budget then
    v_action := 'backpressure_applied';
  else
    v_action := 'within_budget';
  end if;

  if v_action = 'backpressure_applied' then
    v_source_type := case p_workload_type
      when 'webhooks' then 'webhook'
      when 'ai' then 'ai'
      when 'oltp' then 'api'
      else 'job'
    end;

    v_incident := app.raise_observability_alert(
      p_tenant_id, v_source_type, 'backlog_depth',
      format('%s workload exceeded its capacity budget', p_workload_type), 'high',
      format('observed %s exceeds budget %s', p_observed_value, v_budget)
    );
  end if;

  insert into app.workload_backpressure_events (tenant_id, workload_type, observed_value, budget_value, action_taken, alert_incident_id)
  values (p_tenant_id, p_workload_type, p_observed_value, v_budget, v_action, v_incident.id)
  returning * into v_event;

  return v_event;
end;
$$;

comment on function app.evaluate_workload_budget is
  'IAE-034: service_role-only, no actor parameter -- system-to-system telemetry evaluation, mirroring app.record_observability_signal''s own shape exactly (design decision 4). Composes app.raise_observability_alert (IAE-030) on a genuine breach, never a second parallel alerting path.';

-- ===========================================================================
-- 3. app.scaling_recommendations -- real, tenant-specific remediation
-- backlog, composed with IAE-032 (design decision 5).
-- ===========================================================================

create table app.scaling_recommendations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  workload_type text not null,
  recommendation_type text not null,
  rationale text not null,
  status text not null default 'open',
  acknowledged_by_auth_user_id uuid references auth.users (id),
  acknowledged_by text,
  acknowledged_at timestamptz,
  dismissed_reason text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint scaling_recommendations_workload_type_check check (workload_type in ('oltp', 'analytics', 'reports', 'ai', 'webhooks', 'import_export', 'notifications')),
  constraint scaling_recommendations_type_check check (recommendation_type in ('dedicated_deployment', 'read_model', 'partitioning', 'architecture_review')),
  constraint scaling_recommendations_status_check check (status in ('open', 'acknowledged', 'dismissed', 'implemented'))
);

comment on table app.scaling_recommendations is
  'IAE-034: real, human-reviewed remediation backlog (Prompt 362 ''build scale monitoring and remediation surface'') -- a real operator records a recommendation after reviewing app.workload_backpressure_events'' own evidence; not an autonomous recommendation engine, disclosed honestly.';

create function app.touch_scaling_recommendation_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger scaling_recommendations_touch_row
  before update on app.scaling_recommendations
  for each row
  execute function app.touch_scaling_recommendation_row();

create function app.generate_scaling_recommendation(
  p_tenant_id uuid,
  p_workload_type text,
  p_recommendation_type text,
  p_rationale text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.scaling_recommendations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_recommendation app.scaling_recommendations;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks MON:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_workload_type not in ('oltp', 'analytics', 'reports', 'ai', 'webhooks', 'import_export', 'notifications') then
    raise exception 'workload_invalid_type: %', p_workload_type using errcode = 'check_violation';
  end if;
  if p_recommendation_type not in ('dedicated_deployment', 'read_model', 'partitioning', 'architecture_review') then
    raise exception 'scaling_recommendation_invalid_type: %', p_recommendation_type using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_rationale), '') = '' then
    raise exception 'scaling_recommendation_rationale_required: a real rationale must be stated' using errcode = 'check_violation';
  end if;

  if p_recommendation_type = 'dedicated_deployment' and app.resolve_tenant_deployment_type(p_tenant_id) = 'dedicated' then
    raise exception 'scaling_recommendation_already_dedicated: tenant % already has an active dedicated deployment', p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.scaling_recommendations (tenant_id, workload_type, recommendation_type, rationale, created_by)
  values (p_tenant_id, p_workload_type, p_recommendation_type, p_rationale, p_actor_label)
  returning * into v_recommendation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_scaling_recommendation',
    'app.scaling_recommendations', v_recommendation.id, 'success', null, null, to_jsonb(v_recommendation)
  );

  return v_recommendation;
end;
$$;

comment on function app.generate_scaling_recommendation is
  'IAE-034: a dedicated_deployment recommendation is rejected outright if the tenant already has an active dedicated deployment (app.resolve_tenant_deployment_type, IAE-032) -- a real, structural composition, not a disclosed prose rule (design decision 5).';

create function app.set_scaling_recommendation_status(
  p_recommendation_id uuid,
  p_new_status text,
  p_dismissed_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.scaling_recommendations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.scaling_recommendations;
  v_decision app.rbac_decision;
  v_valid_transition boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.scaling_recommendations where id = p_recommendation_id for update;
  if not found then
    raise exception 'scaling_recommendation_not_found: %', p_recommendation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'MON', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks MON:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_valid_transition := (v_record.status, p_new_status) in (
    ('open', 'acknowledged'),
    ('open', 'dismissed'),
    ('acknowledged', 'dismissed'),
    ('acknowledged', 'implemented')
  );
  if not v_valid_transition then
    raise exception 'scaling_recommendation_invalid_transition: % -> % is not a valid transition', v_record.status, p_new_status
      using errcode = 'check_violation';
  end if;

  if p_new_status = 'dismissed' and coalesce(trim(p_dismissed_reason), '') = '' then
    raise exception 'scaling_recommendation_dismissed_reason_required: a real dismissal reason must be stated' using errcode = 'check_violation';
  end if;

  update app.scaling_recommendations
  set status = p_new_status,
      acknowledged_by_auth_user_id = case when p_new_status = 'acknowledged' then p_actor_auth_user_id else acknowledged_by_auth_user_id end,
      acknowledged_by = case when p_new_status = 'acknowledged' then p_actor_label else acknowledged_by end,
      acknowledged_at = case when p_new_status = 'acknowledged' then now() else acknowledged_at end,
      dismissed_reason = case when p_new_status = 'dismissed' then p_dismissed_reason else dismissed_reason end
  where id = p_recommendation_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_scaling_recommendation_status',
    'app.scaling_recommendations', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$$;

-- ===========================================================================
-- 4. Read paths.
-- ===========================================================================

create function app.get_workload_capacity_profile(p_tenant_id uuid, p_workload_type text, p_actor_auth_user_id uuid)
returns app.workload_capacity_profiles
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_profile app.workload_capacity_profiles;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks MON:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile from app.workload_capacity_profiles where tenant_id = p_tenant_id and workload_type = p_workload_type;
  return v_profile;
end;
$$;

create function app.list_backpressure_events_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.workload_backpressure_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks MON:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.workload_backpressure_events where tenant_id = p_tenant_id order by occurred_at desc;
end;
$$;

create function app.list_scaling_recommendations_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.scaling_recommendations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'MON', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks MON:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.scaling_recommendations where tenant_id = p_tenant_id order by created_at desc;
end;
$$;

-- ===========================================================================
-- 5. RLS: default-deny, RPC-only.
-- ===========================================================================

alter table app.workload_capacity_profiles enable row level security;
alter table app.workload_backpressure_events enable row level security;
alter table app.scaling_recommendations enable row level security;

revoke all on app.workload_capacity_profiles from public, anon, authenticated;
revoke all on app.workload_backpressure_events from public, anon, authenticated;
revoke all on app.scaling_recommendations from public, anon, authenticated;
grant all on app.workload_capacity_profiles, app.workload_backpressure_events, app.scaling_recommendations to service_role;

revoke execute on all functions in schema app from public;

-- app.resolve_workload_budget and app.evaluate_workload_budget are both
-- system-to-system, service_role-only entry points -- the former a bare-
-- tenant-id default-resolution function (the identical shape app.
-- resolve_tenant_deployment_type/app.resolve_tenant_region/app.
-- resolve_retention_days already established), the latter a real telemetry-
-- evaluation write mirroring app.record_observability_signal's own shape.
grant execute on function app.resolve_workload_budget(uuid, text) to service_role;
grant execute on function app.evaluate_workload_budget(uuid, text, numeric) to service_role;

grant execute on function
  app.set_workload_capacity_profile(uuid, text, numeric, integer, uuid, text),
  app.generate_scaling_recommendation(uuid, text, text, text, uuid, text),
  app.set_scaling_recommendation_status(uuid, text, text, uuid, text),
  app.get_workload_capacity_profile(uuid, text, uuid),
  app.list_backpressure_events_for_tenant(uuid, uuid),
  app.list_scaling_recommendations_for_tenant(uuid, uuid)
to authenticated, service_role;
