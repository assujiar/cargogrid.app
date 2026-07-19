-- Platform Core capability PLT-122 (Workflow Engine, CG-S6-PLT-019)
-- Reusable workflow definitions and instances with deterministic guarded transitions,
-- snapshots, and recovery (Prompt 122 §4). A workflow *definition* is deliberately
-- **not** a new table family -- it is PLT-121's own `config_type='workflow'`
-- config_object/config_version/config_items, reused directly (the same "shared
-- mechanism, not a fork" discipline `PLT-120`/`121` already established for
-- master/config registries). This migration adds only what the Configuration Engine
-- does not already provide: workflow-specific structural validation (states/
-- transitions/reachability/dead-end) at publish time, a hook allowlist, and the
-- runtime instance/transition-history tables.
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **No domain workflow beyond one safe, isolated, synthetic example exists anywhere
--   in this migration** (§12, forbidden: "domain workflows beyond example... broad
--   module adoption"). The representative example (a `draft -> submitted ->
--   approved|rejected` workflow) is built and proven end-to-end entirely inside
--   `scripts/db-tests/workflow.sql` using synthetic tenant data -- **no example
--   workflow row is seeded into this migration itself**, so no permanent
--   fake-business-data table row exists for a future reader to mistake for real product
--   scope.
-- * **Guards/effects are a real, bounded allowlist (`app.workflow_hooks`), not arbitrary
--   code** (§24: "Hooks are allowlisted domain contracts, not arbitrary code"). Exactly
--   two safe, real, template-only hooks are seeded: `always_true` (a guard that
--   unconditionally permits a transition) and `noop` (an effect with no side effects).
--   `app.evaluate_workflow_guard()` only has real logic for `always_true` -- any other
--   *registered* guard code fails closed with `guard_not_implemented` rather than
--   silently passing, since building real guard-execution logic for a business rule
--   that does not exist yet anywhere in this still-Platform-Core-only repository would
--   be untestable busywork (the same reasoning `PLT-121`'s own header applied to
--   deferring the bounded rule-expression evaluator). A future domain capability that
--   registers a real guard via `app.register_workflow_hook()` is also the capability
--   responsible for extending `app.evaluate_workflow_guard()`'s own dispatch with that
--   guard's real logic.
-- * **`entity_type`/`entity_id` on `app.workflow_instances` are a polymorphic reference,
--   application-validated, not a physical per-type FK** -- the same disclosed, sourced
--   pattern `05_DATABASE_SCHEMA_WORKSTREAM.md` §4 established for `ticket_links` and
--   `PLT-121`'s own `config_objects.scope_id` already reused. No real business-domain
--   entity table exists yet to bind to.
-- * **"Reachability/dead-end/cycle rules" (§25)**: reachability and dead-end validation
--   are both real, enforced publish-time gates (below). "Cycle" is handled by making
--   the reachability walk itself a bounded (≤50 hop) recursive CTE -- workflows are
--   explicitly allowed to contain legitimate business cycles (e.g. a revision/
--   resubmission loop, `07_CONFIGURATION_ENGINE_WORKSTREAM.md` §7.1's own named
--   pattern), so "cycle" here means the *validator* must never loop forever on a
--   cyclic graph, not that a cyclic workflow is rejected.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.
--   Every `SECURITY DEFINER` function below was checked against that exact class of
--   defect (a resolver/evaluator needing `SECURITY DEFINER` because its target table
--   carries no direct `authenticated` grant) before this migration was first tested,
--   the lesson `PLT-121`'s own authoring already recorded.

create table app.workflow_hooks (
  code text primary key,
  hook_type text not null,
  name text not null,
  description text,
  registered_by text,
  created_at timestamptz not null default now(),
  constraint workflow_hooks_hook_type_check check (hook_type in ('guard', 'effect'))
);

comment on table app.workflow_hooks is
  'PLT-122: the allowlist of guard/effect hook codes a workflow transition may reference (Prompt 122 §16/§24: "cannot run arbitrary code"). Extensible via app.register_workflow_hook() -- the same registry-not-enum choice PLT-120/121''s app.master_types/app.config_types made, for the same reason: future domains register real hooks without a schema migration.';

insert into app.workflow_hooks (code, hook_type, name, description, registered_by) values
  ('always_true', 'guard', 'Always True', 'Unconditionally permits the transition -- a real, safe template guard, not a placeholder that silently no-ops.', 'platform-core-foundation'),
  ('noop', 'effect', 'No-op', 'An effect with no side effects -- a real, safe template effect for a transition that needs no post-transition action.', 'platform-core-foundation');

create function app.register_workflow_hook(
  p_code text,
  p_hook_type text,
  p_name text,
  p_description text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.workflow_hooks
language plpgsql
as $$
declare
  v_existing app.workflow_hooks;
  v_hook app.workflow_hooks;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a workflow hook'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.workflow_hooks where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.workflow_hooks (code, hook_type, name, description, registered_by)
  values (p_code, p_hook_type, p_name, p_description, p_registered_by)
  returning * into v_hook;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_workflow_hook',
    'app.workflow_hooks', null, 'success', null, null, to_jsonb(v_hook)
  );

  return v_hook;
end;
$$;

-- Structural validation of a workflow definition's config_items (Prompt 122 §20 task 1/2:
-- "define... state/transition/guard/effect... contracts," "cycle/dead-end checks").
-- Expects three items on the version: 'states' (jsonb array of strings),
-- 'initial_state' (jsonb string), 'terminal_states' (jsonb array of strings, may be
-- empty), 'transitions' (jsonb array of {from, to, guard, effect}, guard/effect
-- optional). Raises a specific, distinct error per failure mode rather than one generic
-- "invalid" message.
create function app.validate_workflow_definition(p_version_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_states jsonb;
  v_initial_state text;
  v_terminal_states jsonb;
  v_transitions jsonb;
  v_state text;
  v_transition jsonb;
  v_reachable text[];
  v_frontier text[];
  v_next_frontier text[];
  v_depth integer := 0;
  v_unreachable_count integer;
begin
  select value into v_states from app.config_items where config_version_id = p_version_id and key = 'states';
  select value #>> '{}' into v_initial_state from app.config_items where config_version_id = p_version_id and key = 'initial_state';
  select coalesce(value, '[]'::jsonb) into v_terminal_states from app.config_items where config_version_id = p_version_id and key = 'terminal_states';
  select coalesce(value, '[]'::jsonb) into v_transitions from app.config_items where config_version_id = p_version_id and key = 'transitions';

  if v_states is null or jsonb_typeof(v_states) <> 'array' or jsonb_array_length(v_states) = 0 then
    raise exception 'workflow_missing_states: version % has no ''states'' item, or it is not a non-empty array', p_version_id
      using errcode = 'check_violation';
  end if;

  if v_initial_state is null or not (v_states ? v_initial_state) then
    raise exception 'workflow_invalid_initial_state: initial_state % is not one of the declared states', v_initial_state
      using errcode = 'check_violation';
  end if;

  for v_state in select jsonb_array_elements_text(v_terminal_states) loop
    if not (v_states ? v_state) then
      raise exception 'workflow_invalid_terminal_state: terminal state % is not one of the declared states', v_state
        using errcode = 'check_violation';
    end if;
  end loop;

  for v_transition in select * from jsonb_array_elements(v_transitions) loop
    if not (v_states ? (v_transition ->> 'from')) then
      raise exception 'workflow_invalid_transition_from: transition references undeclared from-state %', v_transition ->> 'from'
        using errcode = 'check_violation';
    end if;
    if not (v_states ? (v_transition ->> 'to')) then
      raise exception 'workflow_invalid_transition_to: transition references undeclared to-state %', v_transition ->> 'to'
        using errcode = 'check_violation';
    end if;
    if v_transition ->> 'guard' is not null and not exists (select 1 from app.workflow_hooks where code = v_transition ->> 'guard' and hook_type = 'guard') then
      raise exception 'workflow_unknown_guard: transition references unregistered guard %', v_transition ->> 'guard'
        using errcode = 'check_violation';
    end if;
    if v_transition ->> 'effect' is not null and not exists (select 1 from app.workflow_hooks where code = v_transition ->> 'effect' and hook_type = 'effect') then
      raise exception 'workflow_unknown_effect: transition references unregistered effect %', v_transition ->> 'effect'
        using errcode = 'check_violation';
    end if;
  end loop;

  -- Reachability: bounded-depth (<=50) breadth-first walk from initial_state -- safe on
  -- a cyclic graph (this migration's own header), never loops forever.
  v_reachable := array[v_initial_state];
  v_frontier := array[v_initial_state];
  while array_length(v_frontier, 1) > 0 and v_depth < 50 loop
    select coalesce(array_agg(distinct t ->> 'to'), array[]::text[]) into v_next_frontier
    from jsonb_array_elements(v_transitions) t
    where (t ->> 'from') = any (v_frontier) and not ((t ->> 'to') = any (v_reachable));

    exit when array_length(v_next_frontier, 1) is null;
    v_reachable := v_reachable || v_next_frontier;
    v_frontier := v_next_frontier;
    v_depth := v_depth + 1;
  end loop;

  select count(*) into v_unreachable_count
  from jsonb_array_elements_text(v_states) s
  where not (s = any (v_reachable));
  if v_unreachable_count > 0 then
    raise exception 'workflow_unreachable_state: % declared state(s) are unreachable from initial_state %', v_unreachable_count, v_initial_state
      using errcode = 'check_violation';
  end if;

  -- Dead end: every non-terminal state must have at least one outgoing transition.
  for v_state in select jsonb_array_elements_text(v_states) loop
    if not (v_terminal_states ? v_state) and not exists (select 1 from jsonb_array_elements(v_transitions) t where (t ->> 'from') = v_state) then
      raise exception 'workflow_dead_end_state: non-terminal state % has no outgoing transition', v_state
        using errcode = 'check_violation';
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_workflow_definition is
  'PLT-122: the publish-time structural gate (Prompt 122 §20 task 2/§23) -- every declared state reachable from initial_state, every non-terminal state has an outgoing transition, every guard/effect reference resolves to a real registered hook. Raises a distinct, named exception per failure mode rather than one generic error.';

-- Wraps app.publish_config_version() with the workflow-specific structural gate above,
-- run first -- composes PLT-121''s own supersession/audit logic rather than
-- duplicating it (the same "reuse, don''t fork" discipline this migration''s header
-- states).
create function app.publish_workflow_definition(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
begin
  perform app.validate_workflow_definition(p_version_id);
  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

-- Runtime instance table. config_version_id binds the instance to the exact published
-- definition snapshot at start time (Prompt 122 §24: "Running instance binds definition
-- snapshot; later publish does not mutate history") -- a later republish of the same
-- workflow config_object creates a *new* config_versions row (PLT-121's own
-- never-mutate-a-published-version discipline), so this FK alone is what makes the
-- binding permanent and safe.
create table app.workflow_instances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  config_version_id uuid not null references app.config_versions (id),
  entity_type text not null default 'generic',
  entity_id uuid,
  current_state text not null,
  status text not null default 'active',
  idempotency_key text not null,
  started_by text,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workflow_instances_status_check check (status in ('active', 'completed', 'cancelled', 'failed')),
  constraint workflow_instances_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.workflow_instances is
  'PLT-122: a running (or concluded) execution of a published workflow definition. entity_type/entity_id are a polymorphic, application-validated reference (this migration''s own header) -- no real business-domain entity table exists yet to bind to physically.';

create index workflow_instances_tenant_id_idx on app.workflow_instances (tenant_id);
create index workflow_instances_config_version_id_idx on app.workflow_instances (config_version_id);

create function app.touch_workflow_instance_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger workflow_instances_touch_row
  before update on app.workflow_instances
  for each row
  execute function app.touch_workflow_instance_row();

-- Append-only transition history (Prompt 122 §18: "instance start/transition/failure/
-- override/cancel with actor/reason/snapshot").
create table app.workflow_transition_history (
  id uuid primary key default gen_random_uuid(),
  instance_id uuid not null references app.workflow_instances (id),
  event_type text not null,
  from_state text,
  to_state text,
  actor_auth_user_id uuid references auth.users (id),
  actor_label text,
  reason text,
  occurred_at timestamptz not null default now(),
  constraint workflow_transition_history_event_type_check check (event_type in ('start', 'transition', 'cancel', 'fail'))
);

create index workflow_transition_history_instance_id_idx on app.workflow_transition_history (instance_id, occurred_at);

-- Instance-level authority is deliberately looser than definition-management authority
-- (Prompt 122 §26: "Definition admin and instance transition/view are separately
-- permissioned") -- app.has_active_tenant_membership() (any active tenant member, the
-- same predicate PLT-113''s RLS policies use), not app.is_support_grant_authority()
-- (tenant_admin/Supreme only, which governs the underlying config_object/config_version
-- instead). Running a workflow instance (e.g. submitting a quotation) is a normal
-- business action, not an administrative one.
create function app.check_workflow_instance_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- Idempotent (unique on tenant_id+idempotency_key) start -- reads initial_state from the
-- bound published definition''s own config_items rather than duplicating it as a column.
create function app.start_workflow_instance(
  p_config_version_id uuid,
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_started_by text
)
returns app.workflow_instances
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_initial_state text;
  v_existing app.workflow_instances;
  v_instance app.workflow_instances;
begin
  if not app.check_workflow_instance_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'workflow_definition_not_published: config version % is not a published workflow definition', p_config_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.workflow_instances where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  select value #>> '{}' into v_initial_state from app.config_items where config_version_id = p_config_version_id and key = 'initial_state';
  if v_initial_state is null then
    raise exception 'workflow_definition_not_published: config version % has no initial_state item', p_config_version_id
      using errcode = 'check_violation';
  end if;

  insert into app.workflow_instances (tenant_id, config_version_id, entity_type, entity_id, current_state, idempotency_key, started_by)
  values (p_tenant_id, p_config_version_id, coalesce(p_entity_type, 'generic'), p_entity_id, v_initial_state, p_idempotency_key, p_started_by)
  returning * into v_instance;

  insert into app.workflow_transition_history (instance_id, event_type, from_state, to_state, actor_auth_user_id, actor_label, reason)
  values (v_instance.id, 'start', null, v_initial_state, p_actor_auth_user_id, p_started_by, 'workflow started');

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_started_by, 'start_workflow_instance',
    'app.workflow_instances', v_instance.id, 'success', null, null, to_jsonb(v_instance)
  );

  return v_instance;
end;
$$;

-- Real logic for the one seeded example guard; fails closed (never silently passes) for
-- any other registered-but-unimplemented guard code -- see this migration's own header.
create function app.evaluate_workflow_guard(p_guard_code text)
returns boolean
language plpgsql
stable
as $$
begin
  if p_guard_code is null then
    return true;
  end if;
  if p_guard_code = 'always_true' then
    return true;
  end if;
  if exists (select 1 from app.workflow_hooks where code = p_guard_code and hook_type = 'guard') then
    raise exception 'guard_not_implemented: guard % is registered but has no real evaluation logic yet', p_guard_code
      using errcode = 'feature_not_supported';
  end if;
  raise exception 'workflow_unknown_guard: guard % is not registered', p_guard_code
    using errcode = 'check_violation';
end;
$$;

-- Real optimistic concurrency (p_expected_current_state) -- rejects a stale transition
-- attempt rather than silently overwriting, the same PLT-109 discipline. Applies a
-- transition only if it is declared in the bound definition's own transitions item and
-- its guard (if any) evaluates true.
create function app.transition_workflow_instance(
  p_instance_id uuid,
  p_expected_current_state text,
  p_to_state text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.workflow_instances
language plpgsql
as $$
declare
  v_instance app.workflow_instances;
  v_transitions jsonb;
  v_terminal_states jsonb;
  v_matched_transition jsonb;
  v_updated app.workflow_instances;
begin
  select * into v_instance from app.workflow_instances where id = p_instance_id;
  if not found then
    raise exception 'workflow_instance_not_found: no workflow instance %', p_instance_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_workflow_instance_authority(v_instance.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_instance.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_instance.status <> 'active' then
    raise exception 'workflow_instance_not_active: instance % is %, only an active instance may transition', p_instance_id, v_instance.status
      using errcode = 'check_violation';
  end if;

  if v_instance.current_state <> p_expected_current_state then
    raise exception 'stale_workflow_state: expected state % but instance % is at state %', p_expected_current_state, p_instance_id, v_instance.current_state
      using errcode = 'check_violation';
  end if;

  select value into v_transitions from app.config_items where config_version_id = v_instance.config_version_id and key = 'transitions';
  select coalesce(value, '[]'::jsonb) into v_terminal_states from app.config_items where config_version_id = v_instance.config_version_id and key = 'terminal_states';

  select t into v_matched_transition
  from jsonb_array_elements(v_transitions) t
  where (t ->> 'from') = v_instance.current_state and (t ->> 'to') = p_to_state
  limit 1;

  if v_matched_transition is null then
    raise exception 'invalid_workflow_transition: % -> % is not a declared transition for this definition', v_instance.current_state, p_to_state
      using errcode = 'check_violation';
  end if;

  if not app.evaluate_workflow_guard(v_matched_transition ->> 'guard') then
    raise exception 'workflow_guard_rejected: guard % rejected transition % -> %', v_matched_transition ->> 'guard', v_instance.current_state, p_to_state
      using errcode = 'check_violation';
  end if;

  update app.workflow_instances
  set current_state = p_to_state,
      status = case when v_terminal_states ? p_to_state then 'completed' else 'active' end,
      ended_at = case when v_terminal_states ? p_to_state then now() else null end
  where id = p_instance_id
  returning * into v_updated;

  insert into app.workflow_transition_history (instance_id, event_type, from_state, to_state, actor_auth_user_id, actor_label, reason)
  values (p_instance_id, 'transition', v_instance.current_state, p_to_state, p_actor_auth_user_id, p_actor_label, p_reason);

  perform app.capture_audit_event(
    v_instance.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_workflow_instance',
    'app.workflow_instances', v_updated.id, 'success', p_reason, to_jsonb(v_instance), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.cancel_workflow_instance(
  p_instance_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text
)
returns app.workflow_instances
language plpgsql
as $$
declare
  v_instance app.workflow_instances;
  v_updated app.workflow_instances;
begin
  select * into v_instance from app.workflow_instances where id = p_instance_id;
  if not found then
    raise exception 'workflow_instance_not_found: no workflow instance %', p_instance_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_workflow_instance_authority(v_instance.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_instance.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_instance.status <> 'active' then
    raise exception 'workflow_instance_not_active: instance % is %, only an active instance may be cancelled', p_instance_id, v_instance.status
      using errcode = 'check_violation';
  end if;

  update app.workflow_instances
  set status = 'cancelled', ended_at = now(), ended_reason = p_reason
  where id = p_instance_id
  returning * into v_updated;

  insert into app.workflow_transition_history (instance_id, event_type, from_state, to_state, actor_auth_user_id, actor_label, reason)
  values (p_instance_id, 'cancel', v_instance.current_state, v_instance.current_state, p_actor_auth_user_id, p_actor_label, p_reason);

  perform app.capture_audit_event(
    v_instance.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_workflow_instance',
    'app.workflow_instances', v_updated.id, 'success', p_reason, to_jsonb(v_instance), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Read view-model (Prompt 122 §15: "reusable transition/action/timeline view models").
-- SECURITY DEFINER: app.workflow_transition_history carries no direct `authenticated`
-- grant at all (its own comment above) -- this function is the sole read path, so it
-- must run with the owner's privilege to see the underlying rows, the exact bug class
-- ERR-2026-004 first caught in app.mask_email() and PLT-121's own resolver functions.
create function app.get_workflow_instance_history(
  p_instance_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.workflow_transition_history
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_instance app.workflow_instances;
begin
  select * into v_instance from app.workflow_instances where id = p_instance_id;
  if not found then
    raise exception 'workflow_instance_not_found: no workflow instance %', p_instance_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_workflow_instance_authority(v_instance.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_instance.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.workflow_transition_history where instance_id = p_instance_id order by occurred_at;
end;
$$;

alter table app.workflow_hooks enable row level security;
alter table app.workflow_instances enable row level security;
alter table app.workflow_transition_history enable row level security;

-- app.workflow_hooks is platform-owned reference data -- safe to expose broadly.
create policy workflow_hooks_select_authenticated on app.workflow_hooks
  for select to authenticated
  using (true);

-- app.workflow_instances is normal tenant business data (unlike PLT-121's draft config
-- content) -- direct RLS-governed SELECT for authenticated, matching PLT-113's posture
-- for primary tables. Writes remain RPC-only (service_role), per this repository's
-- standing "no direct authenticated write" discipline.
create policy workflow_instances_select_scoped on app.workflow_instances
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- app.workflow_transition_history has no tenant_id column of its own (it belongs to an
-- instance) -- no direct authenticated grant at all; app.get_workflow_instance_history()
-- above is the only read path, matching the audit_logs/tenant_brand_versions posture of
-- "the function itself is the access-control boundary" for a table that cannot carry a
-- simple RLS predicate.

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.workflow_hooks to authenticated, service_role;
grant insert, update, delete on app.workflow_hooks to service_role;
grant select on app.workflow_instances to authenticated, service_role;
grant insert, update, delete on app.workflow_instances to service_role;
grant select, insert, update, delete on app.workflow_transition_history to service_role;
grant execute on function app.register_workflow_hook(text, text, text, text, uuid, text) to service_role;
grant execute on function app.validate_workflow_definition(uuid) to service_role;
grant execute on function app.publish_workflow_definition(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.evaluate_workflow_guard(text) to service_role;
grant execute on function app.start_workflow_instance(uuid, uuid, text, uuid, text, uuid, text) to service_role;
grant execute on function app.transition_workflow_instance(uuid, text, text, uuid, text, text) to service_role;
grant execute on function app.cancel_workflow_instance(uuid, uuid, text, text) to service_role;
grant execute on function app.check_workflow_instance_authority(uuid, uuid) to service_role;
grant execute on function app.get_workflow_instance_history(uuid, uuid) to authenticated, service_role;
