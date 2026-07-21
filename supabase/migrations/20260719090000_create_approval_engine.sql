-- Platform Core capability PLT-123 (Approval Engine, CG-S6-PLT-020)
-- Reusable approval definitions/requests/steps/decisions/delegations with deterministic
-- approver resolution, separation of duties, and audit (Prompt 123 §4). Exactly like
-- `PLT-122`'s workflow *definitions*, an approval *definition* is **not** a new table
-- family -- it is `PLT-121`'s own `config_type_code='approval'` config_object/
-- config_version/config_items, reused directly (the same "shared mechanism, not a fork"
-- discipline `PLT-120`/`121`/`122` already established). This migration adds only what
-- the Configuration Engine does not already provide: approval-specific structural
-- validation at publish time, and the runtime request/step/decision/delegation tables.
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **No domain approval policy beyond one safe, isolated, synthetic example exists
--   anywhere in this migration** (§12, forbidden: "domain-specific approval policies
--   beyond example... full inbox UI, finance overrides"). The representative example
--   (a 2-step sequential manager-then-finance approval) is built and proven end-to-end
--   entirely inside `scripts/db-tests/approval.sql` using synthetic tenant data -- no
--   example definition row is seeded into this migration itself.
-- * **Three deterministic routing patterns**: `sequential` (steps open one at a time,
--   in `step_order`; a rejection anywhere fails the whole request immediately),
--   `parallel` (every step opens at once; the request approves only once every step
--   reaches its own `required_approvals` count), and `threshold` (every step opens at
--   once like `parallel`, but the request approves the instant
--   `threshold_required_steps` of the total step count individually reach `approved`,
--   and every still-pending step is then marked `skipped` -- a real, deterministic
--   "N of M" business pattern, not the same algorithm as `parallel` under a different
--   name). All three are proven directly in `db:test`, not merely asserted.
-- * **Approver resolution is real, not a placeholder.** `approver_type='role'` resolves
--   to every identity holding an *active* `app.role_assignments` row whose
--   `role_versions.status = 'published'` for that `role_id` -- the exact join shape
--   `PLT-112`'s own `app.evaluate_permission()` already established and its own comment
--   there documents: a stale assignment pointing at an since-superseded role version
--   fails closed rather than silently granting approval authority.
--   `approver_type='specific_user'` resolves to exactly one named identity.
--   `app.count_eligible_approvers_for_step()` is a real, tested guard against the
--   "no approver" exception case (§23) -- `app.request_approval()` refuses to create a
--   request against a step with zero currently-eligible approvers, rather than creating
--   an undecidable request that would sit pending forever.
-- * **Separation of duties**: `allow_self_approval` (definition-level, default `false`)
--   is a real, enforced gate -- the requester is structurally blocked from deciding their
--   own request's steps unless the definition explicitly allows it, proven directly.
-- * **Delegation is real and bounded**, not a feature-flag placeholder:
--   `app.approval_delegations` carries a hard `CHECK`-enforced maximum duration (90 days
--   -- a constructed, disclosed default per this migration's own scope, the same
--   "bounded rather than indefinite" security posture `PLT-115`'s 24h/2h support-grant
--   expiry caps already established for this repository, not a fabricated business
--   policy). An expired or revoked delegation is excluded from eligibility by the same
--   `now() between starts_at and expires_at and revoked_at is null` predicate every
--   decision-authority check evaluates live, never a cached snapshot.
-- * **Escalation** (`app.escalate_approval_step()`) is the real, audited manual
--   reassignment action Prompt 123 §18/§22 call for (an authorized override actor
--   reassigns an active step's approver target). The automatic SLA-expiry trigger job
--   that would invoke it on a timer is disclosed `NOT_RUN` -- no scheduler/cron
--   infrastructure exists anywhere in this still-Platform-Core-only repository yet.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.
--   Every `SECURITY DEFINER` function below was checked against that exact class of
--   defect before this migration was first tested.

-- Publish-time structural gate over a workflow-typed... err, approval-typed config
-- version's own `config_items` (Prompt 123 §20 task 1/2). Expects: 'pattern' (one of
-- 'sequential'/'parallel'/'threshold'), 'steps' (jsonb array of
-- {step_order, approver_type, role_id, specific_user_id, required_approvals}),
-- 'threshold_required_steps' (integer, only meaningful when pattern='threshold'),
-- 'allow_self_approval' (boolean, defaults false when absent).
create function app.validate_approval_definition(p_version_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_pattern text;
  v_steps jsonb;
  v_threshold_required_steps integer;
  v_step jsonb;
  v_step_orders integer[] := array[]::integer[];
  v_step_order integer;
  v_approver_type text;
  v_role_id uuid;
  v_specific_user_id uuid;
  v_required_approvals integer;
  v_step_count integer;
begin
  select value #>> '{}' into v_pattern from app.config_items where config_version_id = p_version_id and key = 'pattern';
  select value into v_steps from app.config_items where config_version_id = p_version_id and key = 'steps';
  select (value #>> '{}')::integer into v_threshold_required_steps from app.config_items where config_version_id = p_version_id and key = 'threshold_required_steps';

  if v_pattern is null or v_pattern not in ('sequential', 'parallel', 'threshold') then
    raise exception 'approval_invalid_pattern: pattern % is not one of sequential/parallel/threshold', v_pattern
      using errcode = 'check_violation';
  end if;

  if v_steps is null or jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) = 0 then
    raise exception 'approval_missing_steps: version % has no ''steps'' item, or it is not a non-empty array', p_version_id
      using errcode = 'check_violation';
  end if;
  v_step_count := jsonb_array_length(v_steps);

  for v_step in select * from jsonb_array_elements(v_steps) loop
    v_step_order := (v_step ->> 'step_order')::integer;
    v_approver_type := v_step ->> 'approver_type';
    v_role_id := nullif(v_step ->> 'role_id', '')::uuid;
    v_specific_user_id := nullif(v_step ->> 'specific_user_id', '')::uuid;
    v_required_approvals := coalesce((v_step ->> 'required_approvals')::integer, 1);

    if v_step_order is null or v_step_order = any (v_step_orders) then
      raise exception 'approval_invalid_step_order: step_order % is missing or duplicated', v_step_order
        using errcode = 'check_violation';
    end if;
    v_step_orders := v_step_orders || v_step_order;

    if v_approver_type not in ('role', 'specific_user') then
      raise exception 'approval_invalid_approver_type: approver_type % is not one of role/specific_user', v_approver_type
        using errcode = 'check_violation';
    end if;
    if v_approver_type = 'role' and v_role_id is null then
      raise exception 'approval_missing_approver_ref: step % declares approver_type=role but no role_id', v_step_order
        using errcode = 'check_violation';
    end if;
    if v_approver_type = 'specific_user' and v_specific_user_id is null then
      raise exception 'approval_missing_approver_ref: step % declares approver_type=specific_user but no specific_user_id', v_step_order
        using errcode = 'check_violation';
    end if;
    if v_approver_type = 'role' and not exists (select 1 from app.roles where id = v_role_id) then
      raise exception 'approval_unknown_role: step % references a role_id that does not exist', v_step_order
        using errcode = 'check_violation';
    end if;
    if v_approver_type = 'specific_user' and not exists (select 1 from auth.users where id = v_specific_user_id) then
      raise exception 'approval_unknown_user: step % references a specific_user_id that does not exist', v_step_order
        using errcode = 'check_violation';
    end if;
    if v_required_approvals < 1 then
      raise exception 'approval_invalid_required_approvals: step % declares required_approvals < 1', v_step_order
        using errcode = 'check_violation';
    end if;
  end loop;

  if v_pattern = 'threshold' then
    if v_threshold_required_steps is null or v_threshold_required_steps < 1 or v_threshold_required_steps > v_step_count then
      raise exception 'approval_invalid_threshold: threshold_required_steps % must be between 1 and the declared step count %', v_threshold_required_steps, v_step_count
        using errcode = 'check_violation';
    end if;
  end if;

  return true;
end;
$$;

comment on function app.validate_approval_definition is
  'PLT-123: the publish-time structural gate (Prompt 123 §20/§23) -- pattern is one of the 3 supported values, every step has a distinct step_order and a resolvable approver reference, and a threshold pattern''s N is within [1, step count]. Raises a distinct, named exception per failure mode rather than one generic error.';

-- Wraps app.publish_config_version() with the approval-specific structural gate above,
-- run first -- composes PLT-121's own supersession/audit logic rather than duplicating
-- it (the same "reuse, don't fork" discipline this migration's header states).
create function app.publish_approval_definition(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
begin
  perform app.validate_approval_definition(p_version_id);
  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

-- Runtime request table. config_version_id binds the request to the exact published
-- definition snapshot at request time (mirrors PLT-122's own instance/definition-
-- snapshot binding discipline exactly) -- a later republish of the same approval
-- config_object creates a *new* config_versions row (PLT-121's never-mutate-a-
-- published-version discipline), so this FK alone makes the binding permanent and safe.
create table app.approval_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  config_version_id uuid not null references app.config_versions (id),
  entity_type text not null default 'generic',
  entity_id uuid,
  pattern text not null,
  status text not null default 'pending',
  idempotency_key text not null,
  requested_by_auth_user_id uuid references auth.users (id),
  requested_by text,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint approval_requests_pattern_check check (pattern in ('sequential', 'parallel', 'threshold')),
  constraint approval_requests_status_check check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  constraint approval_requests_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.approval_requests is
  'PLT-123: a running (or concluded) approval routing over a published approval definition. entity_type/entity_id are a polymorphic, application-validated reference, the same disclosed pattern PLT-122''s app.workflow_instances already established -- no real business-domain entity table exists yet to bind to physically.';

create index approval_requests_tenant_id_idx on app.approval_requests (tenant_id);
create index approval_requests_config_version_id_idx on app.approval_requests (config_version_id);

create function app.touch_approval_request_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger approval_requests_touch_row
  before update on app.approval_requests
  for each row
  execute function app.touch_approval_request_row();

-- One row per resolved step on a specific request -- the request-time materialization
-- of the definition's own 'steps' config_item, plus live decision-progress state.
create table app.approval_request_steps (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references app.approval_requests (id),
  step_order integer not null,
  approver_type text not null,
  role_id uuid references app.roles (id),
  specific_user_id uuid references auth.users (id),
  required_approvals integer not null default 1,
  approvals_count integer not null default 0,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint approval_request_steps_approver_type_check check (approver_type in ('role', 'specific_user')),
  constraint approval_request_steps_status_check check (status in ('pending', 'active', 'approved', 'rejected', 'skipped')),
  constraint approval_request_steps_required_approvals_check check (required_approvals >= 1),
  constraint approval_request_steps_request_order_unique unique (request_id, step_order)
);

create index approval_request_steps_request_id_idx on app.approval_request_steps (request_id);

create function app.touch_approval_request_step_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger approval_request_steps_touch_row
  before update on app.approval_request_steps
  for each row
  execute function app.touch_approval_request_step_row();

-- Append-only decision log. unique(request_step_id, actor_auth_user_id) is the real
-- "no duplicate decision by the same approver" guard (Prompt 123 §25: "Only pending
-- authorized step can decide once") -- a second decision attempt by the same identity
-- hits this constraint directly, surfaced as approval_decision_already_recorded.
create table app.approval_decisions (
  id uuid primary key default gen_random_uuid(),
  request_step_id uuid not null references app.approval_request_steps (id),
  actor_auth_user_id uuid not null references auth.users (id),
  actor_label text,
  decision text not null,
  reason text,
  decided_at timestamptz not null default now(),
  constraint approval_decisions_decision_check check (decision in ('approved', 'rejected')),
  constraint approval_decisions_step_actor_unique unique (request_step_id, actor_auth_user_id)
);

create index approval_decisions_request_step_id_idx on app.approval_decisions (request_step_id, decided_at);

-- Bounded delegation: a delegator temporarily authorizes a delegate to decide on their
-- behalf, scoped either to one role or to everything the delegator could decide
-- ('all'). expires_at is mandatory and capped at 90 days from starts_at -- a
-- constructed, disclosed bound (this migration's own header), not a fabricated
-- business policy.
create table app.approval_delegations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  delegator_auth_user_id uuid not null references auth.users (id),
  delegate_auth_user_id uuid not null references auth.users (id),
  scope text not null default 'all',
  role_id uuid references app.roles (id),
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null,
  created_by text,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_reason text,
  constraint approval_delegations_scope_check check (scope in ('all', 'role')),
  constraint approval_delegations_scope_shape_check check (
    (scope = 'all' and role_id is null) or
    (scope = 'role' and role_id is not null)
  ),
  constraint approval_delegations_not_self check (delegator_auth_user_id <> delegate_auth_user_id),
  constraint approval_delegations_expiry_check check (expires_at > starts_at and expires_at <= starts_at + interval '90 days')
);

create index approval_delegations_tenant_id_idx on app.approval_delegations (tenant_id);
create index approval_delegations_delegate_id_idx on app.approval_delegations (delegate_auth_user_id);

-- Instance-level (request) authority mirrors PLT-122's own instance-authority posture
-- exactly (Prompt 123 §26: "requester, approver, observer... distinct and tenant-
-- scoped") -- any active tenant member may request/view; deciding a specific step is
-- gated separately below by app.is_eligible_approval_approver().
create function app.check_approval_request_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- Counts identities currently eligible to decide a not-yet-materialized step
-- (role -> every distinct active-assignment-to-a-published-version holder of that
-- role; specific_user -> 1 if that identity exists, else 0). Used by
-- app.request_approval() to fail fast on Prompt 123 §23's "no approver" exception
-- case, rather than silently creating an undecidable request.
create function app.count_eligible_approvers_for_step(p_tenant_id uuid, p_approver_type text, p_role_id uuid, p_specific_user_id uuid)
returns integer
language sql
stable
as $$
  select case
    when p_approver_type = 'role' then (
      select count(distinct ra.auth_user_id)
      from app.role_assignments ra
      join app.role_versions rv on rv.id = ra.role_version_id
      where ra.tenant_id = p_tenant_id and rv.role_id = p_role_id and ra.status = 'active' and rv.status = 'published'
    )
    when p_approver_type = 'specific_user' then (
      select count(*) from auth.users where id = p_specific_user_id
    )
    else 0
  end;
$$;

-- Live eligibility check for a *materialized* request step -- direct role/user match,
-- or an active, unexpired, unrevoked delegation from someone who is themselves
-- *directly* eligible (delegation chains are deliberately not followed transitively --
-- a bounded, disclosed scope choice that also structurally rules out a delegation-cycle
-- infinite loop, rather than requiring a depth cap the way PLT-122's reachability walk
-- does). Never a cached snapshot (Prompt 123 §23: "expired delegation... fails safely").
create function app.is_eligible_approval_approver(p_step app.approval_request_steps, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  v_direct boolean;
begin
  if p_step.approver_type = 'role' then
    v_direct := exists (
      select 1 from app.role_assignments ra
      join app.role_versions rv on rv.id = ra.role_version_id
      where ra.tenant_id = p_tenant_id and rv.role_id = p_step.role_id and ra.auth_user_id = p_actor_auth_user_id
        and ra.status = 'active' and rv.status = 'published'
    );
  else
    v_direct := (p_step.specific_user_id = p_actor_auth_user_id);
  end if;

  if v_direct then
    return true;
  end if;

  -- Delegation: p_actor_auth_user_id stands in for a delegator who is themselves
  -- directly eligible, via an active, unexpired, unrevoked delegation scoped to
  -- 'all' or to this exact role.
  return exists (
    select 1
    from app.approval_delegations d
    where d.tenant_id = p_tenant_id
      and d.delegate_auth_user_id = p_actor_auth_user_id
      and d.revoked_at is null
      and now() between d.starts_at and d.expires_at
      and (
        (d.scope = 'all' and (
          (p_step.approver_type = 'role' and exists (
            select 1 from app.role_assignments ra join app.role_versions rv on rv.id = ra.role_version_id
            where ra.tenant_id = p_tenant_id and rv.role_id = p_step.role_id and ra.auth_user_id = d.delegator_auth_user_id and ra.status = 'active' and rv.status = 'published'
          ))
          or (p_step.approver_type = 'specific_user' and p_step.specific_user_id = d.delegator_auth_user_id)
        ))
        or
        (d.scope = 'role' and p_step.approver_type = 'role' and d.role_id = p_step.role_id and exists (
          select 1 from app.role_assignments ra join app.role_versions rv on rv.id = ra.role_version_id
          where ra.tenant_id = p_tenant_id and rv.role_id = p_step.role_id and ra.auth_user_id = d.delegator_auth_user_id and ra.status = 'active' and rv.status = 'published'
        ))
      )
  );
end;
$$;

-- Idempotent (unique on tenant_id+idempotency_key) request creation -- reads
-- pattern/steps/threshold_required_steps/allow_self_approval from the bound published
-- definition's own config_items, materializes one app.approval_request_steps row per
-- declared step, and opens the correct step(s) per pattern (sequential: only
-- step_order=1; parallel/threshold: every step at once). Refuses to create a request
-- against any step with zero currently-eligible approvers (Prompt 123 §23's "no
-- approver" exception case, checked proactively rather than left to silently stall).
create function app.request_approval(
  p_config_version_id uuid,
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_requested_by text
)
returns app.approval_requests
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_existing app.approval_requests;
  v_pattern text;
  v_steps jsonb;
  v_step jsonb;
  v_step_order integer;
  v_approver_type text;
  v_role_id uuid;
  v_specific_user_id uuid;
  v_required_approvals integer;
  v_eligible_count integer;
  v_request app.approval_requests;
  v_step_status text;
begin
  if not app.check_approval_request_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'approval_definition_not_published: config version % is not a published approval definition', p_config_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.approval_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  select value #>> '{}' into v_pattern from app.config_items where config_version_id = p_config_version_id and key = 'pattern';
  select value into v_steps from app.config_items where config_version_id = p_config_version_id and key = 'steps';
  if v_pattern is null or v_steps is null then
    raise exception 'approval_definition_not_published: config version % has no pattern/steps item', p_config_version_id
      using errcode = 'check_violation';
  end if;

  for v_step in select * from jsonb_array_elements(v_steps) loop
    v_approver_type := v_step ->> 'approver_type';
    v_role_id := nullif(v_step ->> 'role_id', '')::uuid;
    v_specific_user_id := nullif(v_step ->> 'specific_user_id', '')::uuid;
    v_eligible_count := app.count_eligible_approvers_for_step(p_tenant_id, v_approver_type, v_role_id, v_specific_user_id);
    if v_eligible_count = 0 then
      raise exception 'approval_no_eligible_approver: step % has zero currently-eligible approvers in tenant %', v_step ->> 'step_order', p_tenant_id
        using errcode = 'check_violation';
    end if;
  end loop;

  insert into app.approval_requests (tenant_id, config_version_id, entity_type, entity_id, pattern, idempotency_key, requested_by_auth_user_id, requested_by)
  values (p_tenant_id, p_config_version_id, coalesce(p_entity_type, 'generic'), p_entity_id, v_pattern, p_idempotency_key, p_actor_auth_user_id, p_requested_by)
  returning * into v_request;

  for v_step in select * from jsonb_array_elements(v_steps) loop
    v_step_order := (v_step ->> 'step_order')::integer;
    v_approver_type := v_step ->> 'approver_type';
    v_role_id := nullif(v_step ->> 'role_id', '')::uuid;
    v_specific_user_id := nullif(v_step ->> 'specific_user_id', '')::uuid;
    v_required_approvals := coalesce((v_step ->> 'required_approvals')::integer, 1);
    v_step_status := case when v_pattern = 'sequential' and v_step_order <> 1 then 'pending' else 'active' end;

    insert into app.approval_request_steps (request_id, step_order, approver_type, role_id, specific_user_id, required_approvals, status)
    values (v_request.id, v_step_order, v_approver_type, v_role_id, v_specific_user_id, v_required_approvals, v_step_status);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_requested_by, 'request_approval',
    'app.approval_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

-- The core decision engine (Prompt 123 §20 task 3/§21/§22/§25). Real optimistic
-- concurrency and no-duplicate-decision protection come from two structural guarantees
-- rather than an explicit expected-version parameter: the atomic
-- `UPDATE ... WHERE status = 'active'` below (a concurrent decision on an
-- already-resolved step finds zero matching rows and fails cleanly, the same "stale
-- record fails safely" pattern PLT-122's own transition function uses), and
-- approval_decisions' own `unique(request_step_id, actor_auth_user_id)` (a second
-- decision attempt by the same identity is a real, distinct, structural rejection, not
-- an application-level check that could be raced).
create function app.decide_approval_step(
  p_request_step_id uuid,
  p_decision text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text default null
)
returns app.approval_request_steps
language plpgsql
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_allow_self_approval boolean;
  v_updated_step app.approval_request_steps;
  v_next_step_id uuid;
  v_remaining_active integer;
  v_approved_step_count integer;
  v_total_step_count integer;
  v_threshold_required_steps integer;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'approval_invalid_decision: decision % must be approved or rejected', p_decision
      using errcode = 'check_violation';
  end if;

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;

  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'approval_request_not_pending: request % is %, only a pending request can be decided', v_request.id, v_request.status
      using errcode = 'check_violation';
  end if;
  if v_step.status <> 'active' then
    raise exception 'approval_step_not_active: step % is %, only an active step can be decided', p_request_step_id, v_step.status
      using errcode = 'check_violation';
  end if;

  select coalesce((value #>> '{}')::boolean, false) into v_allow_self_approval
  from app.config_items where config_version_id = v_request.config_version_id and key = 'allow_self_approval';
  if not coalesce(v_allow_self_approval, false) and v_request.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'approval_self_approval_denied: identity % requested this approval and self-approval is not allowed', p_actor_auth_user_id
      using errcode = 'check_violation';
  end if;

  if not app.is_eligible_approval_approver(v_step, v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an eligible approver for step %', p_actor_auth_user_id, p_request_step_id
      using errcode = 'insufficient_privilege';
  end if;

  begin
    insert into app.approval_decisions (request_step_id, actor_auth_user_id, actor_label, decision, reason)
    values (p_request_step_id, p_actor_auth_user_id, p_actor_label, p_decision, p_reason);
  exception
    when unique_violation then
      raise exception 'approval_decision_already_recorded: identity % has already decided step %', p_actor_auth_user_id, p_request_step_id
        using errcode = 'unique_violation';
  end;

  if p_decision = 'rejected' then
    update app.approval_request_steps set status = 'rejected' where id = p_request_step_id and status = 'active' returning * into v_updated_step;
    if not found then
      raise exception 'approval_step_not_active: step % changed concurrently, no longer active', p_request_step_id
        using errcode = 'check_violation';
    end if;
    update app.approval_request_steps set status = 'skipped' where request_id = v_request.id and status in ('pending', 'active') and id <> p_request_step_id;
    update app.approval_requests set status = 'rejected', ended_at = now(), ended_reason = p_reason where id = v_request.id;
  else
    update app.approval_request_steps
    set approvals_count = approvals_count + 1,
        status = case when approvals_count + 1 >= required_approvals then 'approved' else 'active' end
    where id = p_request_step_id and status = 'active'
    returning * into v_updated_step;
    if not found then
      raise exception 'approval_step_not_active: step % changed concurrently, no longer active', p_request_step_id
        using errcode = 'check_violation';
    end if;

    if v_updated_step.status = 'approved' then
      if v_request.pattern = 'sequential' then
        select id into v_next_step_id from app.approval_request_steps where request_id = v_request.id and step_order = v_updated_step.step_order + 1;
        if found then
          update app.approval_request_steps set status = 'active' where id = v_next_step_id;
        else
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = 'all sequential steps approved' where id = v_request.id;
        end if;
      elsif v_request.pattern = 'parallel' then
        select count(*) into v_remaining_active from app.approval_request_steps where request_id = v_request.id and status not in ('approved', 'skipped');
        if v_remaining_active = 0 then
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = 'all parallel steps approved' where id = v_request.id;
        end if;
      else -- threshold
        select count(*) into v_approved_step_count from app.approval_request_steps where request_id = v_request.id and status = 'approved';
        select count(*) into v_total_step_count from app.approval_request_steps where request_id = v_request.id;
        select (value #>> '{}')::integer into v_threshold_required_steps from app.config_items where config_version_id = v_request.config_version_id and key = 'threshold_required_steps';
        if v_approved_step_count >= v_threshold_required_steps then
          update app.approval_request_steps set status = 'skipped' where request_id = v_request.id and status in ('pending', 'active');
          update app.approval_requests set status = 'approved', ended_at = now(), ended_reason = format('threshold %s of %s steps approved', v_threshold_required_steps, v_total_step_count) where id = v_request.id;
        end if;
      end if;
    end if;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_approval_step',
    'app.approval_request_steps', p_request_step_id, 'success', p_reason, to_jsonb(v_step), to_jsonb(v_updated_step)
  );

  select * into v_updated_step from app.approval_request_steps where id = p_request_step_id;
  return v_updated_step;
end;
$$;

create function app.cancel_approval_request(
  p_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text
)
returns app.approval_requests
language plpgsql
as $$
declare
  v_request app.approval_requests;
  v_updated app.approval_requests;
begin
  select * into v_request from app.approval_requests where id = p_request_id;
  if not found then
    raise exception 'approval_request_not_found: no approval request %', p_request_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'approval_request_not_pending: request % is %, only a pending request can be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  update app.approval_requests set status = 'cancelled', ended_at = now(), ended_reason = p_reason where id = p_request_id returning * into v_updated;
  update app.approval_request_steps set status = 'skipped' where request_id = p_request_id and status in ('pending', 'active');

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_approval_request',
    'app.approval_requests', v_updated.id, 'success', p_reason, to_jsonb(v_request), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Manual escalation (Prompt 123 §18/§22): an override authority (Supreme, or the
-- tenant's own support-grant authority -- PLT-121's app.check_config_object_authority
-- posture reused for the same "definition-admin-grade" override, not the looser
-- instance-level app.check_approval_request_authority) reassigns an active step's
-- approver target. The step stays 'active'; only its resolution target changes.
create function app.escalate_approval_step(
  p_request_step_id uuid,
  p_new_approver_type text,
  p_new_role_id uuid,
  p_new_specific_user_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text
)
returns app.approval_request_steps
language plpgsql
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated app.approval_request_steps;
begin
  if p_new_approver_type not in ('role', 'specific_user') then
    raise exception 'approval_invalid_approver_type: approver_type % is not one of role/specific_user', p_new_approver_type
      using errcode = 'check_violation';
  end if;

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id
      using errcode = 'no_data_found';
  end if;
  select * into v_request from app.approval_requests where id = v_step.request_id;

  if not app.check_config_object_authority('tenant', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks override authority to escalate step %', p_actor_auth_user_id, p_request_step_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_step.status <> 'active' then
    raise exception 'approval_step_not_active: step % is %, only an active step can be escalated', p_request_step_id, v_step.status
      using errcode = 'check_violation';
  end if;

  update app.approval_request_steps
  set approver_type = p_new_approver_type, role_id = p_new_role_id, specific_user_id = p_new_specific_user_id
  where id = p_request_step_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'escalate_approval_step',
    'app.approval_request_steps', p_request_step_id, 'success', p_reason, to_jsonb(v_step), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Delegator or tenant_admin/Supreme may create a delegation on the delegator's behalf.
create function app.create_approval_delegation(
  p_tenant_id uuid,
  p_delegator_auth_user_id uuid,
  p_delegate_auth_user_id uuid,
  p_scope text,
  p_role_id uuid,
  p_starts_at timestamptz,
  p_expires_at timestamptz,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.approval_delegations
language plpgsql
as $$
declare
  v_delegation app.approval_delegations;
begin
  if p_actor_auth_user_id <> p_delegator_auth_user_id and not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % may not create a delegation on behalf of %', p_actor_auth_user_id, p_delegator_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.approval_delegations (tenant_id, delegator_auth_user_id, delegate_auth_user_id, scope, role_id, starts_at, expires_at, created_by)
  values (p_tenant_id, p_delegator_auth_user_id, p_delegate_auth_user_id, p_scope, p_role_id, coalesce(p_starts_at, now()), p_expires_at, p_created_by)
  returning * into v_delegation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_approval_delegation',
    'app.approval_delegations', v_delegation.id, 'success', null, null, to_jsonb(v_delegation)
  );

  return v_delegation;
end;
$$;

create function app.revoke_approval_delegation(
  p_delegation_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text
)
returns app.approval_delegations
language plpgsql
as $$
declare
  v_delegation app.approval_delegations;
  v_updated app.approval_delegations;
begin
  select * into v_delegation from app.approval_delegations where id = p_delegation_id;
  if not found then
    raise exception 'approval_delegation_not_found: no approval delegation %', p_delegation_id
      using errcode = 'no_data_found';
  end if;

  if p_actor_auth_user_id <> v_delegation.delegator_auth_user_id and not app.is_support_grant_authority(p_actor_auth_user_id, v_delegation.tenant_id) then
    raise exception 'insufficient_authority: identity % may not revoke this delegation', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_delegation.revoked_at is not null then
    raise exception 'approval_delegation_already_revoked: delegation % was already revoked', p_delegation_id
      using errcode = 'check_violation';
  end if;

  update app.approval_delegations set revoked_at = now(), revoked_reason = p_reason where id = p_delegation_id returning * into v_updated;

  perform app.capture_audit_event(
    v_delegation.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_approval_delegation',
    'app.approval_delegations', v_updated.id, 'success', p_reason, to_jsonb(v_delegation), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Read view-models (Prompt 123 §15: "reusable pending approver/timeline/action view
-- models"). Both are SECURITY DEFINER: app.approval_decisions carries no direct
-- `authenticated` grant at all, and the pending-inbox query must evaluate
-- app.is_eligible_approval_approver() across every tenant member's own steps, which
-- itself reads app.role_assignments/app.role_versions/app.approval_delegations --
-- tables with no broad `authenticated` grant.
create function app.get_approval_request_history(
  p_request_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  step_id uuid,
  step_order integer,
  approver_type text,
  step_status text,
  decision_id uuid,
  actor_auth_user_id uuid,
  actor_label text,
  decision text,
  reason text,
  decided_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.approval_requests;
begin
  select * into v_request from app.approval_requests where id = p_request_id;
  if not found then
    raise exception 'approval_request_not_found: no approval request %', p_request_id
      using errcode = 'no_data_found';
  end if;
  if not app.check_approval_request_authority(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select s.id, s.step_order, s.approver_type, s.status, d.id, d.actor_auth_user_id, d.actor_label, d.decision, d.reason, d.decided_at
    from app.approval_request_steps s
    left join app.approval_decisions d on d.request_step_id = s.id
    where s.request_id = p_request_id
    order by s.step_order, d.decided_at;
end;
$$;

-- The pending-approver inbox view model: every currently-active step across the tenant
-- this actor is eligible to decide right now.
create function app.list_pending_approval_steps_for_actor(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.approval_request_steps
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.check_approval_request_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select s.*
    from app.approval_request_steps s
    join app.approval_requests r on r.id = s.request_id
    where r.tenant_id = p_tenant_id and r.status = 'pending' and s.status = 'active'
      and app.is_eligible_approval_approver(s, p_tenant_id, p_actor_auth_user_id);
end;
$$;

alter table app.approval_requests enable row level security;
alter table app.approval_request_steps enable row level security;
alter table app.approval_decisions enable row level security;
alter table app.approval_delegations enable row level security;

-- app.approval_requests/app.approval_request_steps are normal tenant business data
-- (unlike PLT-121's draft config content) -- direct RLS-governed SELECT for
-- authenticated, matching PLT-113's posture for primary tables and PLT-122's own
-- workflow_instances precedent exactly.
create policy approval_requests_select_scoped on app.approval_requests
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy approval_request_steps_select_scoped on app.approval_request_steps
  for select to authenticated
  using (exists (
    select 1 from app.approval_requests r
    where r.id = approval_request_steps.request_id
      and (app.has_active_tenant_membership(r.tenant_id) or app.is_supreme_admin())
  ));

create policy approval_delegations_select_scoped on app.approval_delegations
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- app.approval_decisions has no tenant_id column of its own (it belongs to a step,
-- which belongs to a request) -- no direct authenticated grant at all;
-- app.get_approval_request_history() above is the only read path, the same posture
-- PLT-122's own app.workflow_transition_history already established.

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.approval_requests to authenticated, service_role;
grant insert, update, delete on app.approval_requests to service_role;
grant select on app.approval_request_steps to authenticated, service_role;
grant insert, update, delete on app.approval_request_steps to service_role;
grant select on app.approval_delegations to authenticated, service_role;
grant insert, update, delete on app.approval_delegations to service_role;
grant select, insert, update, delete on app.approval_decisions to service_role;

grant execute on function app.validate_approval_definition(uuid) to service_role;
grant execute on function app.publish_approval_definition(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.count_eligible_approvers_for_step(uuid, text, uuid, uuid) to service_role;
grant execute on function app.is_eligible_approval_approver(app.approval_request_steps, uuid, uuid) to service_role;
grant execute on function app.check_approval_request_authority(uuid, uuid) to service_role;
grant execute on function app.request_approval(uuid, uuid, text, uuid, text, uuid, text) to service_role;
grant execute on function app.decide_approval_step(uuid, text, uuid, text, text) to service_role;
grant execute on function app.cancel_approval_request(uuid, uuid, text, text) to service_role;
grant execute on function app.escalate_approval_step(uuid, text, uuid, uuid, uuid, text, text) to service_role;
grant execute on function app.create_approval_delegation(uuid, uuid, uuid, text, uuid, timestamptz, timestamptz, uuid, text) to service_role;
grant execute on function app.revoke_approval_delegation(uuid, uuid, text, text) to service_role;
grant execute on function app.get_approval_request_history(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_pending_approval_steps_for_actor(uuid, uuid) to authenticated, service_role;
