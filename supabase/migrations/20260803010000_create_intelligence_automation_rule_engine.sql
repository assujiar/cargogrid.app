-- Phase 9 IAE-007 (Automation Rule Engine, Prompt 335, CG-S14-IAE-007) --
-- condition/action automation with versioning, approval-gated publish, dry
-- run and storm/loop guardrails.
--
-- ===========================================================================
-- Design decisions (cited, not re-derived)
-- ===========================================================================
--
-- 1. **Module code: `INTHUB`, newly seeded into `app.entitlement_modules`.**
--    `docs/architecture/01_MODULE_DEPENDENCY_MAP.md` §2.1 already names
--    `INTHUB` ("Integration Hub, automation rules, public/customer/vendor
--    API, webhooks, n8n"), owning phase 9, prompts 335-341 -- this is the
--    FIRST of those 7 prompts to ship code, so this migration is the first
--    to insert the row. This is not an ad hoc 10th module: it is the
--    already-ratified architecture document's own designated code for
--    exactly this capability grouping, cited the same way `PLT-106`'s own
--    original 9-row seed cites the same document's §3.2. Actions seeded:
--    `Configure` (create/edit/dry-run/publish/pause/rollback a rule) and
--    `View` (read rule definitions and execution history), mirroring
--    `REP`'s own minimal action set exactly.
-- 2. **Rule identity is a bespoke versioned table pair
--    (`app.automation_rules`/`app.automation_rule_versions`), NOT the
--    Configuration Engine (`PLT-121`), despite `PLT-122`/`PLT-123`
--    (Workflow/Approval) both riding `config_type`/`config_object`/
--    `config_version`.** Direct inspection of `app.config_objects`
--    (`config_objects_scope_unique` on `(config_type_code, tenant_id,
--    scope_level, scope_id)`) shows the Configuration Engine models "at
--    most ONE object per (type, scope)" -- correct for a tenant's ONE
--    workflow/approval definition of a given named purpose, wrong for "a
--    tenant creates as many independently-named automation rules as it
--    wants." This is the exact same shape question `IAE-003`/`IAE-004`
--    already answered in this same batch (dashboards, saved views) by NOT
--    using `CFG` -- reused here for the identical reason, not re-derived.
--    `app.automation_rule_versions` mirrors `app.tenant_dashboard_versions`
--    exactly: draft/published/archived, `current_version_id` back-reference
--    added via `alter table` after both tables exist (the same forward-FK
--    ordering trick `20260802020000_create_intelligence_dashboard_builder.sql`
--    already used).
-- 3. **Publish IS gated by the existing Approval Engine (`PLT-123`),
--    reused directly, not forked.** A dedicated, granular config_type_code
--    `'approval:automation_rule_publish'` is registered (mirrors the
--    established granular-purpose-key convention
--    `'notification:scheduled_report_ready'` already used in
--    `20260802050000_create_intelligence_scheduled_reports.sql`), owned by
--    `APPR`. Each tenant configures its OWN approval definition for this
--    one purpose (a real, disclosed setup step -- `request_automation_rule_
--    publish_approval` raises a clear, named error if a tenant has never
--    published one, rather than silently allowing an unapproved publish or
--    silently no-op-ing). `publish_automation_rule_version` requires an
--    `approved` `app.approval_requests` row whose `entity_type`/`entity_id`
--    binds to the EXACT draft version being published (never merely "some
--    approval exists somewhere for this rule") -- this directly satisfies
--    Prompt 335 §24's "AI suggestions may draft rules but cannot publish
--    them autonomously." `app.request_approval`/`app.decide_approval_step`
--    are themselves `service_role`-only (`PLT-123`'s own migration), so a
--    real end-user session can never call either directly -- both get a
--    domain-scoped `SECURITY DEFINER` proxy (`request_automation_rule_
--    publish_approval`/`decide_automation_rule_publish_approval`) granted to
--    `authenticated`, mirroring the identical proxy shape every prior
--    SECURITY DEFINER function in this repository already uses to reach a
--    service_role-only primitive. `decide_automation_rule_publish_approval`
--    refuses a step that does not belong to an `automation_rule_version`
--    request by name -- never a generic "decide any approval step" bypass.
-- 4. **Trigger/action execution reuses only platform primitives, never a
--    domain-specific mutation.** Per `ADR-0025` Part D, this migration
--    registers its own new `app.jobs` job_type
--    (`automation_action_execution`) into the existing single canonical
--    registry (`20260730410000_harden_job_type_single_source_of_truth.sql`)
--    and enqueues onto `app.jobs` -- no second queue/scheduler table. The
--    action allowlist is deliberately bounded to exactly three platform
--    primitives: `notify` (`app.queue_notification`, `PLT-127`),
--    `transition_workflow` (`app.transition_workflow_instance`, `PLT-122`
--    -- Prompt 335's own objective text lists "workflow steps" as an
--    explicit action category), and `enqueue_job` (`app.enqueue_job`
--    targeting ONLY this migration's own new job type, carrying an
--    arbitrary sub-action descriptor in its payload -- execution of that
--    payload is disclosed `NOT_RUN`, the same standing "no live job worker
--    exists anywhere in this repository" condition every prior job type in
--    this repo already discloses, not a new gap this migration introduces).
--    "Assignments" and other domain-specific mutations from the prompt's
--    own objective text are satisfied generically through `enqueue_job`
--    targeting a FUTURE domain-owned job type/worker -- out of this
--    migration's own bounded scope, disclosed rather than reached into
--    Ticketing/Operations/other domains' own tables directly (Module
--    Dependency Map R1: "a business-domain module must not import or query
--    another domain's tables directly").
-- 5. **Trigger evaluation entrypoint (`app.evaluate_event_for_automation_
--    rules`) is `service_role`-only, not `authenticated`.** It represents a
--    trusted server-side event dispatcher, never a live end-user browser
--    session -- there is no `assert_actor_is_session_identity` call inside
--    it for the same reason `app.dispatch_event_as_job` has none. It still
--    requires a real, active-tenant-member `p_actor_auth_user_id` (the
--    identity every dispatched action is attributed to), checked explicitly
--    inside the function as defense in depth even though the `service_role`
--    grant already bounds who can call it at all. No domain capability
--    calls `app.append_event_log`/this function automatically yet (`ADR-
--    0025`'s own evidence section already confirmed zero real event
--    producers exist in this repository) -- wiring a real domain trigger is
--    a disclosed, future, per-domain task; this migration proves the
--    engine end-to-end via direct, explicit calls in
--    `scripts/db-tests/automation-rule-engine.sql`, never a fabricated
--    "it just works" claim.
-- 6. **Loop/storm suppression is a genuinely new primitive -- no cooldown/
--    debounce pattern exists anywhere else in this repository to reuse**
--    (confirmed by direct grep before writing this migration). Real,
--    concurrency-safe (row-locked, mirrors this same batch's own Tier C
--    `app.run_scheduled_report` concurrency lesson) per-rule
--    `cooldown_seconds` (a fixed quiet period after each real fire) AND a
--    sliding `max_fires_per_window`/`window_seconds` cap, both enforced
--    inside `app.evaluate_event_for_automation_rules` before any action
--    runs. A suppressed evaluation still records a real, queryable
--    `app.automation_rule_executions` row (`status='suppressed'`) -- never
--    a silent no-op.
-- 7. **Idempotency**: `app.automation_rule_executions` is unique on
--    `(automation_rule_id, idempotency_key)`; the key is the triggering
--    `app.event_logs.id` when the caller supplies one (so the SAME source
--    event re-delivered to the SAME rule can never double-fire), or a
--    freshly generated one for a source-event-less (synthetic/manual) call,
--    which therefore never dedupes against a prior call by design.
-- 8. **Condition language is a small, bounded, non-Turing-complete
--    evaluator** (`app.evaluate_automation_condition`): an array of
--    `{field, operator, value}` triples, AND-combined, operators
--    `eq/neq/gt/gte/lt/lte/contains`. This mirrors `PLT-121`'s own
--    `app.validate_config_value`'s explicit disclosure that "real bounded-
--    expression evaluation is deliberately out of scope" for the
--    Configuration Engine itself -- this migration is the first to build a
--    real (if intentionally small) one, scoped narrowly to flat
--    field-comparisons only; no boolean OR/nesting, disclosed not built.
-- 9. **Dry run is a pure, side-effect-free simulation** (`app.dry_run_
--    automation_rule`): evaluates the rule's own current DRAFT version's
--    conditions against a caller-supplied sample event payload and returns
--    which actions WOULD fire, structurally, without calling
--    `queue_notification`/`enqueue_job`/`transition_workflow_instance` at
--    all -- proven directly in the db-test by asserting zero rows are ever
--    inserted into `app.notifications`/`app.jobs`/`app.workflow_transition_
--    history` as a result of a dry run.
-- 10. **C-05/`customer_user`-layer discipline applied proactively from
--    first draft**, not discovered after the fact this time -- every
--    tenant-scoped RLS policy below excludes `app.actor_holds_customer_
--    user_layer`, and every by-id lookup folds a cross-tenant caller into
--    the same not-found error a genuinely missing id would produce. Direct
--    application of this same batch's own Tier C review findings, not
--    re-derived.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke
-- execute on all functions in schema app from public` before its final
-- grants, the standing per-migration convention.

-- ===========================================================================
-- 0. Entitlement module, permissions, config type, job type -- registry
-- widening, no already-applied migration edited.
-- ===========================================================================

insert into app.entitlement_modules (code, name, owning_phase) values
  ('INTHUB', 'Integration Hub, automation rules, public/customer/vendor API, webhooks, n8n', 9);

insert into app.permissions (action, resource_module_code, category, protected) values
  ('Configure', 'INTHUB', 'admin', false),
  ('View', 'INTHUB', 'standard', false);

insert into app.config_types (code, name, owner_primitive_code, registered_by) values
  ('approval:automation_rule_publish', 'Automation Rule Publish Approval', 'APPR', 'phase-09-foundation');

-- Widen app.jobs.job_type -- the established drop/add-constraint pattern,
-- current full list (verified against every prior `drop constraint
-- jobs_job_type_check` migration, `20260801240000`'s own the most recent)
-- carried forward verbatim, plus this checkpoint's own one new value.
-- app.generic_job_types() widened identically.
alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'IAE-007 (mirrors every prior domain adopter''s own identical widening pattern): widened to add ''automation_action_execution'' -- the Automation Rule Engine''s own generic action-dispatch job type (ADR-0025 Part D). Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

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
    'automation_action_execution'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012): the single authority for which job_type values the GENERIC queue mechanics accept. IAE-007 widened to add automation_action_execution.';

-- ===========================================================================
-- 1. app.automation_rules / app.automation_rule_versions -- rule identity
-- and versioned definitions.
-- ===========================================================================

create table app.automation_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  name text not null,
  description text,
  status text not null default 'active',
  current_version_id uuid,
  cooldown_seconds integer not null default 60,
  max_fires_per_window integer not null default 20,
  window_seconds integer not null default 3600,
  last_fired_at timestamptz,
  window_started_at timestamptz,
  fire_count_in_window integer not null default 0,
  created_by_auth_user_id uuid references auth.users (id),
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint automation_rules_status_check check (status in ('active', 'paused', 'archived')),
  constraint automation_rules_cooldown_check check (cooldown_seconds >= 0),
  constraint automation_rules_max_fires_check check (max_fires_per_window >= 1),
  constraint automation_rules_window_check check (window_seconds >= 1),
  constraint automation_rules_fire_count_check check (fire_count_in_window >= 0),
  constraint automation_rules_tenant_name_unique unique (tenant_id, name)
);

comment on table app.automation_rules is
  'IAE-007: one row per tenant-created automation rule. current_version_id is null until the first approved publish -- a rule with no current_version_id is structurally never evaluated (see app.evaluate_event_for_automation_rules), so status=active on an unpublished rule is harmless. cooldown_seconds/max_fires_per_window/window_seconds/last_fired_at/window_started_at/fire_count_in_window are this migration''s own new loop/storm-suppression primitive (design decision 6) -- no prior pattern existed to reuse.';

create index automation_rules_tenant_id_idx on app.automation_rules (tenant_id);

create table app.automation_rule_versions (
  id uuid primary key default gen_random_uuid(),
  automation_rule_id uuid not null references app.automation_rules (id),
  version_number integer not null,
  status text not null default 'draft',
  trigger_event_type text,
  conditions jsonb not null default '[]'::jsonb,
  actions jsonb not null default '[]'::jsonb,
  created_by_auth_user_id uuid references auth.users (id),
  created_by text,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  constraint automation_rule_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint automation_rule_versions_rule_version_unique unique (automation_rule_id, version_number)
);

comment on table app.automation_rule_versions is
  'IAE-007: one row per version of a rule''s own trigger/conditions/actions definition, mirroring app.tenant_dashboard_versions'' own draft/published/archived shape exactly (design decision 2). trigger_event_type is nullable at the row level (an empty draft has none yet) -- app.validate_automation_rule_definition enforces it non-empty before publish.';

create index automation_rule_versions_rule_id_idx on app.automation_rule_versions (automation_rule_id);
create index automation_rule_versions_trigger_idx on app.automation_rule_versions (trigger_event_type) where status = 'published';

alter table app.automation_rules add constraint automation_rules_current_version_fk
  foreign key (current_version_id) references app.automation_rule_versions (id);

create function app.touch_automation_rule_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger automation_rules_touch_row
  before update on app.automation_rules
  for each row
  execute function app.touch_automation_rule_row();

-- ===========================================================================
-- 2. app.automation_rule_executions -- runtime firing log.
-- ===========================================================================

create table app.automation_rule_executions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  automation_rule_id uuid not null references app.automation_rules (id),
  automation_rule_version_id uuid not null references app.automation_rule_versions (id),
  trigger_event_type text not null,
  source_event_id uuid references app.event_logs (id),
  event_payload jsonb not null default '{}'::jsonb,
  status text not null,
  suppressed_reason text,
  actions_taken jsonb not null default '[]'::jsonb,
  idempotency_key text not null,
  triggered_by text,
  executed_at timestamptz not null default now(),
  constraint automation_rule_executions_status_check check (status in ('completed', 'suppressed', 'failed')),
  constraint automation_rule_executions_rule_key_unique unique (automation_rule_id, idempotency_key)
);

comment on table app.automation_rule_executions is
  'IAE-007: one row per real evaluation attempt of a rule against a matching triggering event -- includes suppressed (cooldown/storm) and failed outcomes, never only successes (design decision 6/9). unique(automation_rule_id, idempotency_key) closes double-firing on a re-delivered source event (design decision 7).';

create index automation_rule_executions_tenant_id_idx on app.automation_rule_executions (tenant_id, executed_at desc);
create index automation_rule_executions_rule_id_idx on app.automation_rule_executions (automation_rule_id, executed_at desc);

-- ===========================================================================
-- 3. app.validate_automation_rule_definition / app.evaluate_automation_condition
-- ===========================================================================

create function app.evaluate_automation_condition(p_conditions jsonb, p_event_payload jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_cond jsonb;
  v_field text;
  v_operator text;
  v_expected jsonb;
  v_actual jsonb;
  v_actual_num numeric;
  v_expected_num numeric;
begin
  if p_conditions is null or jsonb_typeof(p_conditions) <> 'array' or jsonb_array_length(p_conditions) = 0 then
    return true;
  end if;

  for v_cond in select * from jsonb_array_elements(p_conditions) loop
    v_field := v_cond ->> 'field';
    v_operator := v_cond ->> 'operator';
    v_expected := v_cond -> 'value';
    v_actual := p_event_payload -> v_field;

    if v_operator = 'eq' then
      if v_actual is distinct from v_expected then return false; end if;
    elsif v_operator = 'neq' then
      if v_actual is not distinct from v_expected then return false; end if;
    elsif v_operator = 'contains' then
      if v_actual is null or v_expected is null
         or jsonb_typeof(v_actual) <> 'string' or jsonb_typeof(v_expected) <> 'string'
         or strpos(v_actual #>> '{}', v_expected #>> '{}') = 0 then
        return false;
      end if;
    elsif v_operator in ('gt', 'gte', 'lt', 'lte') then
      begin
        v_actual_num := (v_actual #>> '{}')::numeric;
        v_expected_num := (v_expected #>> '{}')::numeric;
      exception when others then
        return false;
      end;
      if v_operator = 'gt' and not (v_actual_num > v_expected_num) then return false; end if;
      if v_operator = 'gte' and not (v_actual_num >= v_expected_num) then return false; end if;
      if v_operator = 'lt' and not (v_actual_num < v_expected_num) then return false; end if;
      if v_operator = 'lte' and not (v_actual_num <= v_expected_num) then return false; end if;
    else
      return false;
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.evaluate_automation_condition is
  'IAE-007: the bounded, non-Turing-complete condition evaluator (design decision 8) -- an array of {field,operator,value} triples, AND-combined. An empty/absent conditions array always matches (an unconditional trigger). An unknown operator or a non-numeric operand for a numeric operator fails closed (returns false), never raises.';

create function app.validate_automation_rule_definition(p_trigger_event_type text, p_conditions jsonb, p_actions jsonb)
returns boolean
language plpgsql
as $$
declare
  v_cond jsonb;
  v_action jsonb;
  v_action_type text;
  v_job_type text;
begin
  if coalesce(length(trim(p_trigger_event_type)), 0) = 0 then
    raise exception 'automation_rule_missing_trigger: a trigger_event_type is required to publish'
      using errcode = 'check_violation';
  end if;

  if not app.validate_config_value(coalesce(p_conditions, '[]'::jsonb)) then
    raise exception 'automation_rule_unsafe_conditions: conditions failed structural validation'
      using errcode = 'check_violation';
  end if;
  if p_conditions is not null and jsonb_typeof(p_conditions) <> 'array' then
    raise exception 'automation_rule_invalid_conditions: conditions must be a jsonb array'
      using errcode = 'check_violation';
  end if;
  for v_cond in select * from jsonb_array_elements(coalesce(p_conditions, '[]'::jsonb)) loop
    if coalesce(v_cond ->> 'field', '') = '' then
      raise exception 'automation_rule_condition_missing_field: every condition requires a field'
        using errcode = 'check_violation';
    end if;
    if coalesce(v_cond ->> 'operator', '') not in ('eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'contains') then
      raise exception 'automation_rule_condition_invalid_operator: % is not a supported condition operator', v_cond ->> 'operator'
        using errcode = 'check_violation';
    end if;
    if not (v_cond ? 'value') then
      raise exception 'automation_rule_condition_missing_value: every condition requires a value'
        using errcode = 'check_violation';
    end if;
  end loop;

  if not app.validate_config_value(coalesce(p_actions, '[]'::jsonb)) then
    raise exception 'automation_rule_unsafe_actions: actions failed structural validation'
      using errcode = 'check_violation';
  end if;
  if p_actions is null or jsonb_typeof(p_actions) <> 'array' or jsonb_array_length(p_actions) = 0 then
    raise exception 'automation_rule_missing_actions: at least one action is required to publish'
      using errcode = 'check_violation';
  end if;
  if jsonb_array_length(p_actions) > 10 then
    raise exception 'automation_rule_too_many_actions: at most 10 actions are allowed per rule'
      using errcode = 'check_violation';
  end if;

  for v_action in select * from jsonb_array_elements(p_actions) loop
    v_action_type := v_action ->> 'action_type';
    if v_action_type not in ('notify', 'transition_workflow', 'enqueue_job') then
      raise exception 'automation_rule_invalid_action_type: % is not a supported action_type', v_action_type
        using errcode = 'check_violation';
    end if;

    if v_action_type = 'notify' then
      if coalesce(v_action ->> 'notification_type_code', '') = '' then
        raise exception 'automation_rule_action_missing_notification_type: a notify action requires notification_type_code'
          using errcode = 'check_violation';
      end if;
      if not exists (select 1 from app.notification_types where code = v_action ->> 'notification_type_code') then
        raise exception 'automation_rule_action_unknown_notification_type: % is not a registered notification type', v_action ->> 'notification_type_code'
          using errcode = 'check_violation';
      end if;
      if coalesce(v_action ->> 'channel', '') = '' then
        raise exception 'automation_rule_action_missing_channel: a notify action requires channel'
          using errcode = 'check_violation';
      end if;
      if coalesce(v_action ->> 'recipient_field', '') = '' then
        raise exception 'automation_rule_action_missing_recipient_field: a notify action requires recipient_field (the event payload key holding the recipient''s auth_user_id)'
          using errcode = 'check_violation';
      end if;
    elsif v_action_type = 'transition_workflow' then
      if coalesce(v_action ->> 'instance_id_field', '') = '' then
        raise exception 'automation_rule_action_missing_instance_field: a transition_workflow action requires instance_id_field'
          using errcode = 'check_violation';
      end if;
      if coalesce(v_action ->> 'to_state', '') = '' then
        raise exception 'automation_rule_action_missing_to_state: a transition_workflow action requires to_state'
          using errcode = 'check_violation';
      end if;
    elsif v_action_type = 'enqueue_job' then
      v_job_type := v_action ->> 'job_type';
      if v_job_type is distinct from 'automation_action_execution' then
        raise exception 'automation_rule_action_invalid_job_type: an enqueue_job action may only target automation_action_execution, got %', v_job_type
          using errcode = 'check_violation';
      end if;
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_automation_rule_definition is
  'IAE-007: the publish-time structural gate -- trigger_event_type is non-empty, every condition has field/operator/value with a supported operator, at least 1 and at most 10 actions exist, and every action carries the required params for its own action_type (design decision 4/8). Raises a distinct, named exception per failure mode.';

-- ===========================================================================
-- 4. Rule authoring: create / set definition / dry run
-- ===========================================================================

create function app.create_automation_rule(
  p_tenant_id uuid,
  p_name text,
  p_description text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.automation_rules
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rule app.automation_rules;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.automation_rules (tenant_id, name, description, created_by_auth_user_id, created_by)
  values (p_tenant_id, p_name, p_description, p_actor_auth_user_id, p_actor_label)
  returning * into v_rule;

  insert into app.automation_rule_versions (automation_rule_id, version_number, status, created_by_auth_user_id, created_by)
  values (v_rule.id, 1, 'draft', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_automation_rule',
    'app.automation_rules', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$$;

comment on function app.create_automation_rule is
  'IAE-007: INTHUB:Configure-gated. Creates the rule wrapper plus a real, empty version-1 draft in the same transaction -- a draft always exists for the lifetime of the rule (design decision 2).';

create function app.set_automation_rule_definition(
  p_rule_id uuid,
  p_trigger_event_type text,
  p_conditions jsonb,
  p_actions jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.automation_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.automation_rules;
  v_decision app.rbac_decision;
  v_draft app.automation_rule_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_rule from app.automation_rules where id = p_rule_id for update;
  if not found then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_draft from app.automation_rule_versions
  where automation_rule_id = p_rule_id and status = 'draft'
  order by version_number desc limit 1;
  if not found then
    raise exception 'automation_rule_no_open_draft: rule % has no open draft version', p_rule_id using errcode = 'check_violation';
  end if;

  if not app.validate_config_value(coalesce(p_conditions, '[]'::jsonb)) or not app.validate_config_value(coalesce(p_actions, '[]'::jsonb)) then
    raise exception 'automation_rule_unsafe_definition: conditions/actions failed structural validation' using errcode = 'check_violation';
  end if;

  update app.automation_rule_versions
  set trigger_event_type = p_trigger_event_type, conditions = coalesce(p_conditions, '[]'::jsonb), actions = coalesce(p_actions, '[]'::jsonb)
  where id = v_draft.id
  returning * into v_draft;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_automation_rule_definition',
    'app.automation_rule_versions', v_draft.id, 'success', null, null, to_jsonb(v_draft)
  );

  return v_draft;
end;
$$;

comment on function app.set_automation_rule_definition is
  'IAE-007: INTHUB:Configure-gated, draft-only. Writes the trigger/conditions/actions onto the rule''s own currently-open draft version -- structural (never business) validation only here; full publish-time validation is app.validate_automation_rule_definition, invoked separately by the publish path.';

create function app.dry_run_automation_rule(
  p_rule_id uuid,
  p_sample_event_payload jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns jsonb
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.automation_rules;
  v_decision app.rbac_decision;
  v_draft app.automation_rule_versions;
  v_matched boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_rule from app.automation_rules where id = p_rule_id;
  if not found then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_draft from app.automation_rule_versions
  where automation_rule_id = p_rule_id and status = 'draft'
  order by version_number desc limit 1;
  if not found then
    raise exception 'automation_rule_no_open_draft: rule % has no open draft version', p_rule_id using errcode = 'check_violation';
  end if;

  v_matched := app.evaluate_automation_condition(v_draft.conditions, coalesce(p_sample_event_payload, '{}'::jsonb));

  -- Pure simulation -- NO app.queue_notification/app.enqueue_job/app.transition_workflow_instance
  -- call anywhere in this function (design decision 9), proven directly in
  -- the db-test by asserting zero side-effect rows result from a dry run.
  return jsonb_build_object(
    'matched', v_matched,
    'trigger_event_type', v_draft.trigger_event_type,
    'would_fire_actions', case when v_matched then v_draft.actions else '[]'::jsonb end
  );
end;
$$;

comment on function app.dry_run_automation_rule is
  'IAE-007: INTHUB:Configure-gated. Evaluates the rule''s own current DRAFT version''s conditions against a caller-supplied sample event payload and reports which actions WOULD fire -- a pure, side-effect-free simulation (design decision 9), never a real notification/job/transition.';

-- ===========================================================================
-- 5. Publish flow: approval request + approval-gated publish
-- ===========================================================================

create function app.request_automation_rule_publish_approval(
  p_rule_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.approval_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.automation_rules;
  v_decision app.rbac_decision;
  v_draft app.automation_rule_versions;
  v_approval_version_id uuid;
  v_request app.approval_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_rule from app.automation_rules where id = p_rule_id;
  if not found then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_draft from app.automation_rule_versions
  where automation_rule_id = p_rule_id and status = 'draft'
  order by version_number desc limit 1;
  if not found then
    raise exception 'automation_rule_no_open_draft: rule % has no open draft version', p_rule_id using errcode = 'check_violation';
  end if;

  perform app.validate_automation_rule_definition(v_draft.trigger_event_type, v_draft.conditions, v_draft.actions);

  select cv.id into v_approval_version_id
  from app.config_objects co
  join app.config_versions cv on cv.config_object_id = co.id and cv.status = 'published'
  where co.config_type_code = 'approval:automation_rule_publish' and co.tenant_id = v_rule.tenant_id and co.scope_level = 'tenant';

  if v_approval_version_id is null then
    raise exception 'automation_rule_publish_approval_not_configured: tenant % has not published an approval:automation_rule_publish definition yet', v_rule.tenant_id
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.request_approval(
    v_approval_version_id, v_rule.tenant_id, 'automation_rule_version', v_draft.id,
    'automation-rule-publish-' || v_draft.id, p_actor_auth_user_id, p_actor_label
  );

  return v_request;
end;
$$;

comment on function app.request_automation_rule_publish_approval is
  'IAE-007: INTHUB:Configure-gated. Validates the draft is structurally publishable, then opens a real app.approval_requests row against the tenant''s own published approval:automation_rule_publish definition (PLT-123, reused directly), bound to this exact draft version via entity_type/entity_id (design decision 3). Raises a clear, named error if the tenant has never configured that approval definition -- never a silent allow or silent no-op.';

-- app.decide_approval_step (PLT-123) is service_role-only (its own migration's
-- own grant) -- no end-user session can call it directly. A tenant-facing
-- approver deciding a real, human-in-the-loop step needs the SAME
-- SECURITY DEFINER proxy shape app.request_automation_rule_publish_approval
-- already established for app.request_approval above, scoped to this
-- domain's own entity_type so it can never become a generic "decide any
-- approval step in the tenant" bypass.
create function app.decide_automation_rule_publish_approval(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.approval_request_steps
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'automation_rule_publish_approval_step_not_found: %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'automation_rule_version' then
    raise exception 'automation_rule_publish_approval_wrong_domain: step % does not belong to an automation rule publish request', p_request_step_id
      using errcode = 'check_violation';
  end if;

  return app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);
end;
$$;

comment on function app.decide_automation_rule_publish_approval is
  'IAE-007: a domain-scoped SECURITY DEFINER proxy to app.decide_approval_step (PLT-123, service_role-only) -- lets a real, eligible tenant approver decide a step through the same eligibility/separation-of-duties/idempotent-decision logic app.decide_approval_step already enforces, without granting authenticated broad access to decide ANY approval step in the tenant. Refuses a step that does not belong to an automation_rule_version request by name.';

create function app.publish_automation_rule_version(
  p_rule_id uuid,
  p_approval_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.automation_rules
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.automation_rules;
  v_decision app.rbac_decision;
  v_draft app.automation_rule_versions;
  v_request app.approval_requests;
  v_next_version integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_rule from app.automation_rules where id = p_rule_id for update;
  if not found then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_draft from app.automation_rule_versions
  where automation_rule_id = p_rule_id and status = 'draft'
  order by version_number desc limit 1;
  if not found then
    raise exception 'automation_rule_no_open_draft: rule % has no open draft version', p_rule_id using errcode = 'check_violation';
  end if;

  select * into v_request from app.approval_requests where id = p_approval_request_id;
  if not found or v_request.tenant_id <> v_rule.tenant_id then
    raise exception 'automation_rule_publish_approval_not_found: no approval request % for tenant %', p_approval_request_id, v_rule.tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_request.entity_type <> 'automation_rule_version' or v_request.entity_id <> v_draft.id then
    raise exception 'automation_rule_publish_approval_mismatch: approval request % is not for the exact draft version being published', p_approval_request_id
      using errcode = 'check_violation';
  end if;
  if v_request.status <> 'approved' then
    raise exception 'automation_rule_publish_not_approved: approval request % is %, not approved', p_approval_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  perform app.validate_automation_rule_definition(v_draft.trigger_event_type, v_draft.conditions, v_draft.actions);

  update app.automation_rule_versions set status = 'published', published_at = now() where id = v_draft.id;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.automation_rule_versions where automation_rule_id = p_rule_id;
  insert into app.automation_rule_versions (automation_rule_id, version_number, status, trigger_event_type, conditions, actions, created_by_auth_user_id, created_by)
  values (p_rule_id, v_next_version, 'draft', v_draft.trigger_event_type, v_draft.conditions, v_draft.actions, p_actor_auth_user_id, p_actor_label);

  update app.automation_rules set current_version_id = v_draft.id where id = p_rule_id
  returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_automation_rule_version',
    'app.automation_rule_versions', v_draft.id, 'success', null, null,
    jsonb_build_object('approval_request_id', p_approval_request_id)
  );

  return v_rule;
end;
$$;

comment on function app.publish_automation_rule_version is
  'IAE-007: INTHUB:Configure-gated. Locks the rule row for update before deciding (C-04). Requires an approved app.approval_requests row bound to the EXACT draft version being published (design decision 3) -- a different, unrelated, or non-approved request is rejected by name, never silently accepted. Publishes the draft, points current_version_id at it, then opens a fresh draft copying the just-published definition, mirroring app.publish_tenant_dashboard_version''s own established shape.';

create function app.set_automation_rule_status(
  p_rule_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.automation_rules
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.automation_rules;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_rule from app.automation_rules where id = p_rule_id for update;
  if not found then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'automation_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rule.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('active', 'paused', 'archived') then
    raise exception 'automation_rule_invalid_status: % is not one of active/paused/archived', p_status using errcode = 'check_violation';
  end if;

  update app.automation_rules set status = p_status where id = p_rule_id
  returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_automation_rule_status',
    'app.automation_rules', v_rule.id, 'success', null, null, jsonb_build_object('status', p_status)
  );

  return v_rule;
end;
$$;

comment on function app.set_automation_rule_status is
  'IAE-007: INTHUB:Configure-gated. Pause/resume/archive -- a paused/archived rule is structurally excluded from app.evaluate_event_for_automation_rules regardless of its own current_version_id (Alternative flow: "A rule misfires; admin pauses it").';

-- ===========================================================================
-- 6. Trigger evaluation entrypoint -- the real, bounded execution engine.
-- ===========================================================================

create function app.evaluate_event_for_automation_rules(
  p_tenant_id uuid,
  p_event_type text,
  p_event_payload jsonb,
  p_source_event_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.automation_rule_executions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_match record;
  v_rule app.automation_rules;
  v_version app.automation_rule_versions;
  v_matched boolean;
  v_idempotency_key text;
  v_existing app.automation_rule_executions;
  v_execution app.automation_rule_executions;
  v_action jsonb;
  v_actions_taken jsonb;
  v_action_status text;
  v_action_error text;
  v_config_version_id uuid;
  v_recipient uuid;
  v_instance app.workflow_instances;
  v_had_failure boolean;
begin
  if not (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_match in
    select r.id as rule_id, v.id as version_id
    from app.automation_rules r
    join app.automation_rule_versions v on v.id = r.current_version_id
    where r.tenant_id = p_tenant_id and r.status = 'active' and r.current_version_id is not null
      and v.trigger_event_type = p_event_type
    order by r.created_at
  loop
    select * into v_version from app.automation_rule_versions where id = v_match.version_id;

    v_matched := app.evaluate_automation_condition(v_version.conditions, coalesce(p_event_payload, '{}'::jsonb));
    if not v_matched then
      continue;
    end if;

    v_idempotency_key := coalesce(p_source_event_id::text, gen_random_uuid()::text);

    select * into v_existing from app.automation_rule_executions
    where automation_rule_id = v_match.rule_id and idempotency_key = v_idempotency_key;
    if found then
      return next v_existing;
      continue;
    end if;

    -- Real, concurrency-safe cooldown/storm decision -- row-locked before
    -- deciding, mirroring this same batch's own Tier C app.run_scheduled_
    -- report concurrency lesson (design decision 6).
    select * into v_rule from app.automation_rules where id = v_match.rule_id for update;

    if v_rule.status <> 'active' or v_rule.current_version_id is distinct from v_match.version_id then
      -- Concurrently paused/republished since the unlocked match above --
      -- skip silently rather than act against a superseded version.
      continue;
    end if;

    if v_rule.last_fired_at is not null and v_rule.last_fired_at > now() - make_interval(secs => v_rule.cooldown_seconds) then
      insert into app.automation_rule_executions (
        tenant_id, automation_rule_id, automation_rule_version_id, trigger_event_type, source_event_id,
        event_payload, status, suppressed_reason, idempotency_key, triggered_by
      ) values (
        p_tenant_id, v_rule.id, v_version.id, p_event_type, p_source_event_id,
        coalesce(p_event_payload, '{}'::jsonb), 'suppressed', 'cooldown', v_idempotency_key, p_actor_label
      ) returning * into v_execution;
      return next v_execution;
      continue;
    end if;

    if v_rule.window_started_at is null or v_rule.window_started_at < now() - make_interval(secs => v_rule.window_seconds) then
      update app.automation_rules set window_started_at = now(), fire_count_in_window = 0 where id = v_rule.id
      returning * into v_rule;
    end if;

    if v_rule.fire_count_in_window >= v_rule.max_fires_per_window then
      insert into app.automation_rule_executions (
        tenant_id, automation_rule_id, automation_rule_version_id, trigger_event_type, source_event_id,
        event_payload, status, suppressed_reason, idempotency_key, triggered_by
      ) values (
        p_tenant_id, v_rule.id, v_version.id, p_event_type, p_source_event_id,
        coalesce(p_event_payload, '{}'::jsonb), 'suppressed', 'storm_window_exceeded', v_idempotency_key, p_actor_label
      ) returning * into v_execution;
      return next v_execution;
      continue;
    end if;

    update app.automation_rules
    set last_fired_at = now(), fire_count_in_window = fire_count_in_window + 1
    where id = v_rule.id;

    v_actions_taken := '[]'::jsonb;
    v_had_failure := false;

    for v_action in select * from jsonb_array_elements(v_version.actions) loop
      v_action_status := 'completed';
      v_action_error := null;
      begin
        if v_action ->> 'action_type' = 'notify' then
          v_recipient := nullif(p_event_payload ->> (v_action ->> 'recipient_field'), '')::uuid;
          if v_recipient is null then
            raise exception 'automation_action_missing_recipient: event payload has no usable % field', v_action ->> 'recipient_field';
          end if;

          select resolved_version_id into v_config_version_id
          from app.resolve_config('notification:' || (v_action ->> 'notification_type_code'), p_tenant_id);
          if v_config_version_id is null then
            raise exception 'automation_action_notification_type_unconfigured: % has no resolvable config for tenant %', v_action ->> 'notification_type_code', p_tenant_id;
          end if;

          perform app.queue_notification(
            v_config_version_id, p_tenant_id, v_action ->> 'notification_type_code', v_recipient,
            v_action ->> 'channel', coalesce(v_action ->> 'locale', 'en'), coalesce(p_event_payload, '{}'::jsonb),
            'automation-' || v_rule.id || '-' || v_idempotency_key,
            p_actor_auth_user_id, p_actor_label
          );
        elsif v_action ->> 'action_type' = 'transition_workflow' then
          select * into v_instance from app.workflow_instances
          where id = nullif(p_event_payload ->> (v_action ->> 'instance_id_field'), '')::uuid;
          if v_instance.id is null then
            raise exception 'automation_action_workflow_instance_not_found: event payload has no resolvable % workflow instance', v_action ->> 'instance_id_field';
          end if;

          perform app.transition_workflow_instance(
            v_instance.id, v_instance.current_state, v_action ->> 'to_state',
            p_actor_auth_user_id, p_actor_label, v_action ->> 'reason'
          );
        elsif v_action ->> 'action_type' = 'enqueue_job' then
          perform app.enqueue_job(
            p_tenant_id, 'automation_action_execution', coalesce(v_action -> 'payload', '{}'::jsonb),
            0, 'automation-' || v_rule.id || '-' || v_idempotency_key || '-enqueue_job',
            3, p_actor_auth_user_id, p_actor_label
          );
        end if;
      exception when others then
        v_action_status := 'failed';
        v_action_error := sqlerrm;
        v_had_failure := true;
      end;

      v_actions_taken := v_actions_taken || jsonb_build_array(jsonb_build_object(
        'action_type', v_action ->> 'action_type', 'status', v_action_status, 'error', v_action_error
      ));
    end loop;

    insert into app.automation_rule_executions (
      tenant_id, automation_rule_id, automation_rule_version_id, trigger_event_type, source_event_id,
      event_payload, status, actions_taken, idempotency_key, triggered_by
    ) values (
      p_tenant_id, v_rule.id, v_version.id, p_event_type, p_source_event_id,
      coalesce(p_event_payload, '{}'::jsonb), case when v_had_failure then 'failed' else 'completed' end,
      v_actions_taken, v_idempotency_key, p_actor_label
    ) returning * into v_execution;

    return next v_execution;
  end loop;

  return;
end;
$$;

comment on function app.evaluate_event_for_automation_rules is
  'IAE-007: the real trigger-evaluation entrypoint (design decision 5) -- service_role-only, a trusted system dispatcher, never a live end-user session. For every active, published rule in the tenant matching p_event_type: evaluates conditions, enforces cooldown_seconds/max_fires_per_window under a real row lock (design decision 6), and on a genuine fire executes notify/transition_workflow/enqueue_job actions in order, recording one real app.automation_rule_executions row per attempt (completed/suppressed/failed, never a silent no-op). No domain capability calls this automatically yet -- disclosed, not fabricated (design decision 5).';

-- ===========================================================================
-- 7. RLS -- tenant-scoped SELECT, customer_user-layer excluded from the
-- first draft (design decision 10).
-- ===========================================================================

alter table app.automation_rules enable row level security;
alter table app.automation_rule_versions enable row level security;
alter table app.automation_rule_executions enable row level security;

create policy automation_rules_select_scoped on app.automation_rules
  for select to authenticated
  using (
    app.has_active_tenant_membership(tenant_id, (select auth.uid()))
    and not app.actor_holds_customer_user_layer(tenant_id, (select auth.uid()))
  );

create policy automation_rule_versions_select_scoped on app.automation_rule_versions
  for select to authenticated
  using (
    exists (
      select 1 from app.automation_rules r
      where r.id = automation_rule_versions.automation_rule_id
        and app.has_active_tenant_membership(r.tenant_id, (select auth.uid()))
        and not app.actor_holds_customer_user_layer(r.tenant_id, (select auth.uid()))
    )
  );

create policy automation_rule_executions_select_scoped on app.automation_rule_executions
  for select to authenticated
  using (
    app.has_active_tenant_membership(tenant_id, (select auth.uid()))
    and not app.actor_holds_customer_user_layer(tenant_id, (select auth.uid()))
  );

-- ===========================================================================
-- 8. Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.automation_rules to authenticated, service_role;
grant select on app.automation_rule_versions to authenticated, service_role;
grant select on app.automation_rule_executions to authenticated, service_role;

grant execute on function app.evaluate_automation_condition(jsonb, jsonb) to authenticated, service_role;
grant execute on function app.validate_automation_rule_definition(text, jsonb, jsonb) to authenticated, service_role;
grant execute on function app.create_automation_rule(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_automation_rule_definition(uuid, text, jsonb, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.dry_run_automation_rule(uuid, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.request_automation_rule_publish_approval(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.decide_automation_rule_publish_approval(uuid, text, uuid, text, text) to authenticated, service_role;
grant execute on function app.publish_automation_rule_version(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.set_automation_rule_status(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.evaluate_event_for_automation_rules(uuid, text, jsonb, uuid, uuid, text) to service_role;
