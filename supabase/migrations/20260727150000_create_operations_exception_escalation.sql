-- Operations capability OPS-174 (Exception and Escalation, CG-S8-OPS-008)
-- Basic operational exception intake, ownership, SLA, escalation, and resolution
-- linked to Shipment Order/milestone evidence (Prompt 174 §4/§20).
--
-- Taxonomy scope, disclosed rather than left implicit: type (delay/hold/damage/loss/
-- incident) and severity (low/medium/high/critical) are fixed CHECK-constrained enums,
-- not a permanent cross-tenant registry table -- unlike `OPS-173`'s milestone codes
-- (which needed platform-wide permanent semantics shared across every tenant's own
-- template), this "basic exception/incident taxonomy" (§20 task 1) is exactly the same
-- bounded shape `OPS-169` already used for `app.shipment_orders.mode` -- a small, fixed,
-- versionable-via-migration set. Inventing a second registry mechanism for an
-- equally-small fixed set would be unjustified scope, not rigor.
--
-- SLA/escalation policy IS real and versioned, per Prompt 174 §24 ("Severity/SLA/
-- escalation rules are versioned and pinned at detection unless explicit reevaluation
-- occurs"). Mirrors `OPS-173`'s own considered choice: a directly tenant-scoped
-- versioned-definition table (`app.exception_sla_policy_versions`, draft -> published ->
-- archived, one row per `(tenant_id, type, severity)`), not Configuration Engine (whose
-- precedence dimensions -- company/branch/role/user -- do not fit "by type and
-- severity" any better than they fit `OPS-173`'s own "by mode"). "Pinned at detection"
-- is a real governed snapshot, the same pattern this entire session has used
-- everywhere else (Job Order's customer_snapshot, Shipment Order's cargo_service_
-- snapshot): `app.report_exception` copies the resolved policy's own `sla_hours` and
-- `id` onto the exception row at creation time -- a later republish of the policy never
-- silently changes an already-open exception's own due date.
--
-- Sensitive-field masking (Prompt 174 §16/§26: "restrict... damage/loss details, claim
-- amount") reuses the exact precedent `COM-148`/`COM-156` already established
-- (`app.has_view_cost`/`app.has_view_margin`): this migration registers one new
-- protected permission action, `OPS:View cost` (the same pre-approved 19-action vocabulary
-- PLT-111 fixed, paired with the OPS module -- a distinct catalogue row from COM's own
-- `COM:View cost`, never a collision, since permissions are keyed on (resource_module_code, action)), and `app.exceptions_directory`
-- masks `internal_notes`/`damage_loss_details`/`claim_amount`/`claim_currency` for any
-- actor lacking it -- the same "authenticated has no direct column-level grant on the
-- sensitive columns, forcing every read through the masked view" guarantee `OPS-168`'s
-- own `app.job_orders_directory` already proved. Writing those same fields
-- (`app.set_exception_sensitive_fields`) requires both `OPS:Edit` and `OPS:View cost`
-- -- an actor who cannot see this data cannot blindly set it either.
--
-- Automatic, time-driven escalation ("SLA jobs enforce reminders/escalation," §14) is
-- the same "mechanism real, live scheduler wiring deferred" posture already disclosed
-- at `PLT-129`/`PLT-132` (no cron/poll infrastructure exists anywhere in this
-- repository yet) -- `app.escalate_exception` is a real, callable, reason-required,
-- idempotent-safe escalation step any caller (a human today, a future scheduled job
-- once one exists) can invoke; this migration does not build a fake scheduler to call
-- it automatically.
--
-- Full claims adjudication, insurance settlement, and financial posting are explicitly
-- out of Phase 3 scope (§24) -- `claim_amount`/`claim_currency` are a recorded,
-- non-authoritative estimate only, never posted to any ledger, never a float (numeric
-- (14,2), the same precision every other money-shaped column in this repository uses).
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

insert into app.permissions (action, resource_module_code, category, protected)
values ('View cost', 'OPS', 'sensitive', true);

create table app.exception_sla_policy_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  type text not null,
  severity text not null,
  status text not null default 'draft',
  sla_hours numeric(8, 2),
  escalation_schedule jsonb not null default '[]'::jsonb,
  supersedes_version_id uuid references app.exception_sla_policy_versions (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exception_sla_policy_versions_type_check check (type in ('delay', 'hold', 'damage', 'loss', 'incident')),
  constraint exception_sla_policy_versions_severity_check check (severity in ('low', 'medium', 'high', 'critical')),
  constraint exception_sla_policy_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint exception_sla_policy_versions_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id)
);

comment on table app.exception_sla_policy_versions is
  'OPS-174: a versioned, tenant-scoped SLA/escalation policy per (type, severity) (draft -> published -> archived, mirroring app.margin_rule_versions''/COM-150''s own simpler tenant-scoped versioned-definition pattern -- the same considered choice OPS-173 already made over Configuration Engine reuse). escalation_schedule is a jsonb array of hour-offsets-past-due at which a future scheduler may call app.escalate_exception; this migration does not itself schedule anything (no cron/poll infrastructure exists yet, the same disclosed PLT-129/132 posture).';

create unique index exception_sla_policy_versions_tenant_type_severity_published_unique on app.exception_sla_policy_versions (tenant_id, type, severity) where status = 'published';
create unique index exception_sla_policy_versions_tenant_type_severity_draft_unique on app.exception_sla_policy_versions (tenant_id, type, severity) where status = 'draft';

create function app.touch_exception_sla_policy_version_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger exception_sla_policy_versions_touch_row
  before update on app.exception_sla_policy_versions
  for each row
  execute function app.touch_exception_sla_policy_version_row();

create function app.create_exception_sla_policy_draft(
  p_tenant_id uuid,
  p_type text,
  p_severity text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.exception_sla_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing_draft app.exception_sla_policy_versions;
  v_decision app.rbac_decision;
  v_version app.exception_sla_policy_versions;
begin
  if p_type not in ('delay', 'hold', 'damage', 'loss', 'incident') then
    raise exception 'exception_invalid_type: % is not a supported exception type', p_type using errcode = 'check_violation';
  end if;
  if p_severity not in ('low', 'medium', 'high', 'critical') then
    raise exception 'exception_invalid_severity: % is not a supported severity', p_severity using errcode = 'check_violation';
  end if;

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_draft from app.exception_sla_policy_versions where tenant_id = p_tenant_id and type = p_type and severity = p_severity and status = 'draft';
  if found then
    return v_existing_draft;
  end if;

  insert into app.exception_sla_policy_versions (tenant_id, type, severity, created_by)
  values (p_tenant_id, p_type, p_severity, p_actor_label)
  returning * into v_version;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_exception_sla_policy_draft',
    'app.exception_sla_policy_versions', v_version.id, 'success', null, null, jsonb_build_object('type', p_type, 'severity', p_severity)
  );

  return v_version;
end;
$$;

create function app.set_exception_sla_policy_terms(
  p_version_id uuid,
  p_sla_hours numeric,
  p_escalation_schedule jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.exception_sla_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.exception_sla_policy_versions;
  v_decision app.rbac_decision;
begin
  select * into v_version from app.exception_sla_policy_versions where id = p_version_id;
  if not found then
    raise exception 'exception_sla_policy_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: exception SLA policy % is % and can no longer be edited', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if p_sla_hours is not null and p_sla_hours <= 0 then
    raise exception 'exception_invalid_sla_hours: sla_hours must be positive' using errcode = 'check_violation';
  end if;
  if p_escalation_schedule is not null and jsonb_typeof(p_escalation_schedule) <> 'array' then
    raise exception 'exception_invalid_escalation_schedule: escalation_schedule must be a jsonb array' using errcode = 'check_violation';
  end if;

  if not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.exception_sla_policy_versions
  set sla_hours = p_sla_hours, escalation_schedule = coalesce(p_escalation_schedule, '[]'::jsonb)
  where id = p_version_id
  returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_exception_sla_policy_terms',
    'app.exception_sla_policy_versions', v_version.id, 'success', null, null,
    jsonb_build_object('sla_hours', p_sla_hours, 'escalation_schedule', p_escalation_schedule)
  );

  return v_version;
end;
$$;

create function app.publish_exception_sla_policy_version(
  p_version_id uuid,
  p_expected_version integer,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.exception_sla_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.exception_sla_policy_versions;
  v_superseded app.exception_sla_policy_versions;
  v_decision app.rbac_decision;
begin
  select * into v_version from app.exception_sla_policy_versions where id = p_version_id;
  if not found then
    raise exception 'exception_sla_policy_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: exception SLA policy % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: exception SLA policy % is % and cannot be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if v_version.sla_hours is null then
    raise exception 'exception_invalid_sla_hours: a policy cannot publish without sla_hours set' using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.exception_sla_policy_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'exception_sla_policy_not_found: supersedes target % not found', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.status = 'published' then
      update app.exception_sla_policy_versions set status = 'archived' where id = p_supersedes_version_id;
    end if;
  end if;

  update app.exception_sla_policy_versions
  set status = 'published', supersedes_version_id = p_supersedes_version_id
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_exception_sla_policy_version',
    'app.exception_sla_policy_versions', v_version.id, 'success', null, null,
    jsonb_build_object('type', v_version.type, 'severity', v_version.severity, 'supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$$;

create table app.operational_exceptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  milestone_event_id uuid references app.milestone_events (id),
  type text not null,
  severity text not null,
  status text not null default 'open',
  owner_user_id uuid references auth.users (id),
  sla_policy_version_id uuid references app.exception_sla_policy_versions (id),
  sla_hours numeric(8, 2),
  due_at timestamptz,
  escalation_level integer not null default 0,
  source text not null,
  correlation_key text,
  description text not null,
  internal_notes text,
  damage_loss_details jsonb,
  claim_amount numeric(14, 2),
  claim_currency text,
  resolution_evidence text,
  resolved_at timestamptz,
  reopened_at timestamptz,
  closed_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint operational_exceptions_type_check check (type in ('delay', 'hold', 'damage', 'loss', 'incident')),
  constraint operational_exceptions_severity_check check (severity in ('low', 'medium', 'high', 'critical')),
  constraint operational_exceptions_status_check check (status in ('open', 'acknowledged', 'resolved', 'reopened', 'closed')),
  constraint operational_exceptions_source_check check (source in ('manual', 'system')),
  constraint operational_exceptions_escalation_level_check check (escalation_level >= 0),
  constraint operational_exceptions_claim_amount_check check (claim_amount is null or claim_amount >= 0)
);

comment on table app.operational_exceptions is
  'OPS-174: one row per operational exception/incident, scoped to a Shipment Order and optionally one milestone event as evidence. sla_hours/sla_policy_version_id/due_at are a governed snapshot pinned at app.report_exception time -- a later republish of the tenant''s own SLA policy never retroactively changes an already-open exception''s own due date (Prompt 174 §24). internal_notes/damage_loss_details/claim_amount/claim_currency are masked at read time by app.exceptions_directory (OPS:View cost) -- authenticated has no direct column-level grant on those four columns on this base table.';

create index operational_exceptions_tenant_shipment_idx on app.operational_exceptions (tenant_id, shipment_order_id);
create index operational_exceptions_tenant_status_idx on app.operational_exceptions (tenant_id, status);
create index operational_exceptions_tenant_severity_idx on app.operational_exceptions (tenant_id, severity);
create index operational_exceptions_tenant_owner_idx on app.operational_exceptions (tenant_id, owner_user_id);
create index operational_exceptions_tenant_due_idx on app.operational_exceptions (tenant_id, due_at);
create unique index operational_exceptions_system_dedup_unique on app.operational_exceptions (tenant_id, shipment_order_id, correlation_key) where source = 'system' and correlation_key is not null;

create function app.touch_operational_exception_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger operational_exceptions_touch_row
  before update on app.operational_exceptions
  for each row
  execute function app.touch_operational_exception_row();

create table app.exception_escalations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  exception_id uuid not null references app.operational_exceptions (id),
  escalation_level integer not null,
  reason text not null,
  actor_auth_user_id uuid,
  actor_label text,
  escalated_at timestamptz not null default now()
);

comment on table app.exception_escalations is
  'OPS-174: append-only escalation history -- one row per real escalation step, never rewritten. escalation_level is the new level reached by that step.';

create index exception_escalations_tenant_exception_idx on app.exception_escalations (tenant_id, exception_id, escalated_at);

create function app.has_view_exception_cost(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'OPS', 'View cost')).allowed;
$$;

comment on function app.has_view_exception_cost is
  'Field-masking gate (OPS-174, mirrors COM-148/COM-156''s app.has_view_cost/app.has_view_margin) -- true if the caller holds the real, newly-seeded OPS:View cost permission for the given tenant.';

-- The one path that creates an exception -- idempotent on (tenant_id, shipment_order_id,
-- correlation_key) for source='system' (Prompt 174 §25: "deduplicate system-detected
-- events by source/correlation window"). Resolves the tenant's own published SLA
-- policy for (type, severity), if one exists, and pins it (sla_hours/due_at/
-- sla_policy_version_id) -- if none is published yet, those three columns stay null,
-- never an error (an SLA policy is optional configuration, not a hard precondition).
create function app.report_exception(
  p_shipment_order_id uuid,
  p_milestone_event_id uuid,
  p_type text,
  p_severity text,
  p_description text,
  p_source text,
  p_correlation_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_policy app.exception_sla_policy_versions;
  v_existing app.operational_exceptions;
  v_exception app.operational_exceptions;
begin
  if p_type not in ('delay', 'hold', 'damage', 'loss', 'incident') then
    raise exception 'exception_invalid_type: % is not a supported exception type', p_type using errcode = 'check_violation';
  end if;
  if p_severity not in ('low', 'medium', 'high', 'critical') then
    raise exception 'exception_invalid_severity: % is not a supported severity', p_severity using errcode = 'check_violation';
  end if;
  if p_source not in ('manual', 'system') then
    raise exception 'exception_invalid_source: % is not one of manual/system', p_source using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  if p_milestone_event_id is not null and not exists (select 1 from app.milestone_events where id = p_milestone_event_id and shipment_order_id = p_shipment_order_id) then
    raise exception 'milestone_event_not_found: % is not an event on shipment order %', p_milestone_event_id, p_shipment_order_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_source = 'system' and p_correlation_key is not null then
    select * into v_existing from app.operational_exceptions
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and correlation_key = p_correlation_key;
    if found then
      return v_existing;
    end if;
  end if;

  select * into v_policy from app.exception_sla_policy_versions
  where tenant_id = v_shipment.tenant_id and type = p_type and severity = p_severity and status = 'published';

  insert into app.operational_exceptions (
    tenant_id, shipment_order_id, milestone_event_id, type, severity, source, correlation_key, description,
    sla_policy_version_id, sla_hours, due_at, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_milestone_event_id, p_type, p_severity, p_source, p_correlation_key, p_description,
    v_policy.id, v_policy.sla_hours, case when v_policy.sla_hours is not null then now() + (v_policy.sla_hours || ' hours')::interval else null end,
    p_actor_label
  )
  returning * into v_exception;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'report_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'type', p_type, 'severity', p_severity, 'source', p_source)
  );

  return v_exception;
exception
  when unique_violation then
    select * into v_exception from app.operational_exceptions
    where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and correlation_key = p_correlation_key;
    return v_exception;
end;
$$;

comment on function app.report_exception is
  'OPS-174: the one path that creates an exception. Idempotent (dedup) on (tenant_id, shipment_order_id, correlation_key) when source=''system'' -- a repeated system detection of the same underlying event returns the existing row, never a duplicate. Pins the tenant''s own currently-published SLA policy for (type, severity) at creation time; leaves sla_hours/due_at null (not an error) when no policy has been published yet.';

-- Reason is mandatory only when reassigning an already-owned exception (mirrors
-- app.reassign_resource''s own distinction between a first assignment and a real
-- reassignment, OPS-172).
create function app.assign_exception_owner(
  p_exception_id uuid,
  p_owner_user_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.owner_user_id is not null and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: reassigning an already-owned exception requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Assign');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Assign (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set owner_user_id = p_owner_user_id
  where id = p_exception_id
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_exception_owner',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('owner_user_id', p_owner_user_id, 'reason', p_reason)
  );

  return v_exception;
end;
$$;

create function app.acknowledge_exception(
  p_exception_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status not in ('open', 'reopened') then
    raise exception 'invalid_transition: exception % is % and cannot be acknowledged', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'acknowledged'
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$$;

-- Escalation is orthogonal to status -- an exception may be open/acknowledged/reopened
-- AND at any escalation_level. Blocked once resolved/closed (nothing left to escalate).
create function app.escalate_exception(
  p_exception_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_new_level integer;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: escalating an exception requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.status in ('resolved', 'closed') then
    raise exception 'invalid_transition: exception % is % and can no longer be escalated', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  v_new_level := v_exception.escalation_level + 1;

  update app.operational_exceptions
  set escalation_level = v_new_level
  where id = p_exception_id
  returning * into v_exception;

  insert into app.exception_escalations (tenant_id, exception_id, escalation_level, reason, actor_auth_user_id, actor_label)
  values (v_exception.tenant_id, p_exception_id, v_new_level, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'escalate_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('escalation_level', v_new_level, 'reason', p_reason)
  );

  return v_exception;
end;
$$;

create function app.resolve_exception(
  p_exception_id uuid,
  p_expected_version integer,
  p_resolution_evidence text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_resolution_evidence is null or length(trim(p_resolution_evidence)) = 0 then
    raise exception 'evidence_required: resolving an exception requires non-empty resolution_evidence' using errcode = 'check_violation';
  end if;

  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status not in ('open', 'acknowledged', 'reopened') then
    raise exception 'invalid_transition: exception % is % and cannot be resolved', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'resolved', resolution_evidence = p_resolution_evidence, resolved_at = now()
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('resolution_evidence', p_resolution_evidence)
  );

  return v_exception;
end;
$$;

create function app.close_exception(
  p_exception_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status <> 'resolved' then
    raise exception 'invalid_transition: exception % is % and cannot be closed', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Close');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Close (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'closed', closed_at = now()
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$$;

create function app.reopen_exception(
  p_exception_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: reopening an exception requires a non-empty reason' using errcode = 'check_violation';
  end if;

  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if v_exception.record_version <> p_expected_version then
    raise exception 'stale_version: exception % expected version % but found %', p_exception_id, p_expected_version, v_exception.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_exception.status not in ('resolved', 'closed') then
    raise exception 'invalid_transition: exception % is % and cannot be reopened', p_exception_id, v_exception.status
      using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set status = 'reopened', reopened_at = now()
  where id = p_exception_id and record_version = p_expected_version
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_exception',
    'app.operational_exceptions', v_exception.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_exception;
end;
$$;

comment on function app.reopen_exception is
  'OPS-174: resolved/closed -> reopened. The underlying resolution_evidence/damage_loss_details/prior escalation history are never deleted or cleared by this reopen (Prompt 174 §24: "resolution never deletes the underlying... evidence") -- only status/reopened_at change.';

-- Writing the sensitive fields requires OPS:Edit AND OPS:View cost -- an actor
-- who cannot see this data cannot blindly set it either.
create function app.set_exception_sensitive_fields(
  p_exception_id uuid,
  p_internal_notes text,
  p_damage_loss_details jsonb,
  p_claim_amount numeric,
  p_claim_currency text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.operational_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if p_claim_amount is not null and p_claim_amount < 0 then
    raise exception 'exception_invalid_claim_amount: claim_amount must not be negative' using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_exception_cost(v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.operational_exceptions
  set internal_notes = p_internal_notes, damage_loss_details = p_damage_loss_details, claim_amount = p_claim_amount, claim_currency = p_claim_currency
  where id = p_exception_id
  returning * into v_exception;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_exception_sensitive_fields',
    'app.operational_exceptions', v_exception.id, 'success', null, null, '{}'::jsonb
  );

  return v_exception;
end;
$$;

comment on function app.set_exception_sensitive_fields is
  'OPS-174: the one path that may set internal_notes/damage_loss_details/claim_amount/claim_currency -- gated by both OPS:Edit and OPS:View cost, so an actor who cannot see this masked data cannot blindly write it either. The audit payload deliberately omits the sensitive values themselves (an empty jsonb object), never logging claim/damage detail in cleartext audit evidence.';

create function app.get_exception_escalation_history(
  p_exception_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.exception_escalations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.operational_exceptions;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_exception from app.operational_exceptions where id = p_exception_id;
  if not found then
    raise exception 'exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_exception.shipment_order_id;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_exception.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_exception.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.exception_escalations where exception_id = p_exception_id order by escalated_at asc;
end;
$$;

alter table app.exception_sla_policy_versions enable row level security;
alter table app.operational_exceptions enable row level security;
alter table app.exception_escalations enable row level security;

create policy exception_sla_policy_versions_select_scoped on app.exception_sla_policy_versions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy operational_exceptions_select_scoped on app.operational_exceptions
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = operational_exceptions.shipment_order_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy exception_escalations_select_scoped on app.exception_escalations
  for select to authenticated
  using (
    exists (
      select 1 from app.operational_exceptions oe
      join app.shipment_orders so on so.id = oe.shipment_order_id
      where oe.id = exception_escalations.exception_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

-- Field-masked projection of app.operational_exceptions -- the same "no direct
-- column-level grant on the sensitive columns, forcing every read through this view"
-- guarantee OPS-168's own app.job_orders_directory already proved.
create view app.exceptions_directory
as
select
  oe.id, oe.tenant_id, oe.shipment_order_id, oe.milestone_event_id, oe.type, oe.severity, oe.status,
  oe.owner_user_id, oe.sla_policy_version_id, oe.sla_hours, oe.due_at, oe.escalation_level, oe.source, oe.correlation_key,
  oe.description,
  case when app.has_view_exception_cost(oe.tenant_id) then oe.internal_notes else null end as internal_notes,
  case when app.has_view_exception_cost(oe.tenant_id) then oe.damage_loss_details else null end as damage_loss_details,
  case when app.has_view_exception_cost(oe.tenant_id) then oe.claim_amount else null end as claim_amount,
  case when app.has_view_exception_cost(oe.tenant_id) then oe.claim_currency else null end as claim_currency,
  not app.has_view_exception_cost(oe.tenant_id) as sensitive_masked,
  oe.resolution_evidence, oe.resolved_at, oe.reopened_at, oe.closed_at, oe.record_version, oe.created_by, oe.created_at, oe.updated_at
from app.operational_exceptions oe
join app.shipment_orders so on so.id = oe.shipment_order_id
where app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null);

comment on view app.exceptions_directory is
  'OPS-174: field-masked projection of app.operational_exceptions -- internal_notes/damage_loss_details/claim_amount/claim_currency nulled out (sensitive_masked=true) without OPS:View cost. authenticated has no direct column-level grant on those four columns on the base table, forcing every read through this view.';

revoke execute on all functions in schema app from public;

grant select on app.exception_sla_policy_versions to authenticated, service_role;
grant insert, update, delete on app.exception_sla_policy_versions to service_role;
grant select on app.exception_escalations to authenticated, service_role;
grant insert, update, delete on app.exception_escalations to service_role;
grant select on app.exceptions_directory to authenticated, service_role;
grant select on app.operational_exceptions to service_role;
grant insert, update, delete on app.operational_exceptions to service_role;

grant execute on function app.create_exception_sla_policy_draft(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_exception_sla_policy_terms(uuid, numeric, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.publish_exception_sla_policy_version(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.report_exception(uuid, uuid, text, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.assign_exception_owner(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.acknowledge_exception(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.escalate_exception(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_exception(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.close_exception(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_exception(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_exception_sensitive_fields(uuid, text, jsonb, numeric, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_exception_escalation_history(uuid, uuid) to authenticated, service_role;
grant execute on function app.has_view_exception_cost(uuid, uuid) to authenticated, service_role;
