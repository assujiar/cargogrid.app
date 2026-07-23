-- Commercial capability COM-148 (RFQ and Costing Request, CG-S7-COM-007)
-- A bounded Commercial cost-request shell over one canonical opportunity: inherits its
-- requirements as a versioned snapshot (never retyped), collects componentized cost
-- responses from an internal or vendor source, and stays a governed request/response
-- record -- explicitly NOT full Procurement RFQ/sourcing/PO/vendor onboarding (Prompt 148
-- §24, that remains Phase 6 Procurement's own scope).
--
-- Scope boundaries (disclosed, not silently narrowed):
--  1. "Configuration versions" (Prompt 148 §24: "pins source opportunity and
--     configuration versions") -- no Commercial capability has integrated with the
--     Configuration Engine (PLT-121) yet (COM-146/147 both disclosed the same boundary
--     for the Status Engine). The only version this migration pins is the source
--     opportunity's own record_version (source_opportunity_version) -- the concrete,
--     buildable interpretation available now.
--  2. Vendor identity is a free-text vendor_ref, never a reference into a real vendor
--     master -- Procurement Phase 6 owns vendor onboarding; ADR-0015 already reserves
--     rate/cost-lookup master ownership for COM-149 (Rate and Cost Lookup), the very next
--     capability. This migration builds the request/response shell COM-149 will feed
--     live rate data into -- it does not perform automated lookup itself.
--  3. SLA is a plain due_at field with an is_overdue read-time computation (query-side,
--     `due_at < now()`) -- no background job/notification dispatch (PLT-127/132) is wired.
--     Every prior Commercial capability deferred generic-engine integration the same way;
--     wiring live SLA reminders is a materially larger scope than this bounded task.
--
-- Field masking reuses the exact PLT-114/COM-147 pattern for the seeded, protected
-- COM:View cost permission (never previously consumed) -- and applies the lesson learned
-- authoring COM-147 directly: app.costing_responses_directory below is security_invoker
-- = false (view-owner-mode) from the start, because an invoker-mode view cannot read a
-- column-REVOKEd field at all, even inside a masking CASE (Postgres checks column
-- privileges against the invoker for every referenced column at parse time, not the
-- runtime CASE branch outcome) -- proven the hard way in COM-147's own build log §3.3;
-- no need to rediscover it here. This view adds its own explicit app.can_access_record(...)
-- row filter, the same deliberate strengthening over PLT-114's bare app.users_directory
-- COM-147 already introduced.

-- The seeded permission catalogue (PLT-111) already has a 'View cost' action, but only
-- for the FIN and PRC modules (docs/build-log/phase-01/PLT-111.md's own seed data) --
-- permissions are scoped per resource_module_code, so those rows do not grant anything
-- for module 'COM'. Adding this tenant-facing Commercial-scoped row is the same technique
-- COM-143 used to add 'Assign' for 'COM' after the fact -- a new catalogue row, not an
-- edit to any existing one.
insert into app.permissions (action, resource_module_code, category, protected)
values ('View cost', 'COM', 'sensitive', true);

create table app.costing_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  opportunity_id uuid not null references app.opportunities (id),
  source_opportunity_version integer not null,
  requirements_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  due_at timestamptz,
  assignee_user_id uuid references auth.users (id),
  cancel_reason text,
  revised_from_id uuid references app.costing_requests (id),
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint costing_requests_status_check check (
    status in ('pending', 'assigned', 'responded', 'cancelled', 'superseded')
  ),
  constraint costing_requests_cancel_reason_check check (
    (status = 'cancelled' and cancel_reason is not null and length(trim(cancel_reason)) > 0)
    or (status <> 'cancelled')
  ),
  constraint costing_requests_requirements_check check (jsonb_typeof(requirements_snapshot) = 'object'),
  constraint costing_requests_not_self_revise check (revised_from_id is null or revised_from_id <> id)
);

comment on table app.costing_requests is
  'COM-148: one Commercial cost request per (tenant, opportunity, source_opportunity_version) -- app.request_costing is idempotent on that triple. requirements_snapshot is a point-in-time copy of the opportunity''s own requirements (never a live re-typed reference, the same no-reentry rule every prior Commercial capability follows). A revision creates a new row (revised_from_id) and marks the prior one status=superseded -- never edited or deleted, so response evidence linked to a superseded request remains reachable (Prompt 148 §25: "revisions never overwrite a response used by an issued quote").';

create unique index costing_requests_opportunity_version_unique on app.costing_requests (tenant_id, opportunity_id, source_opportunity_version);
create index costing_requests_tenant_status_idx on app.costing_requests (tenant_id, status);
create index costing_requests_tenant_owner_idx on app.costing_requests (tenant_id, owner_user_id);
create index costing_requests_tenant_assignee_idx on app.costing_requests (tenant_id, assignee_user_id);
create index costing_requests_due_idx on app.costing_requests (tenant_id, due_at) where status in ('pending', 'assigned');

create table app.costing_request_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  costing_request_id uuid not null references app.costing_requests (id),
  component_code text not null,
  description text,
  quantity numeric(14, 3),
  unit text,
  created_at timestamptz not null default now(),
  constraint costing_request_components_quantity_check check (quantity is null or quantity >= 0)
);

comment on table app.costing_request_components is
  'COM-148: the line items a costing request asks to be priced (e.g. "origin haulage", "ocean freight", "destination customs") -- a bounded list, not a Procurement service catalogue.';

create index costing_request_components_request_idx on app.costing_request_components (costing_request_id);

create table app.costing_responses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  costing_request_id uuid not null references app.costing_requests (id),
  source_type text not null,
  vendor_ref text,
  currency text not null,
  total_amount numeric(14, 2) not null default 0,
  effective_at timestamptz not null default now(),
  expiry_at timestamptz,
  submitted_by text,
  created_at timestamptz not null default now(),
  constraint costing_responses_source_type_check check (source_type in ('internal', 'vendor')),
  constraint costing_responses_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint costing_responses_total_check check (total_amount >= 0),
  constraint costing_responses_validity_check check (expiry_at is null or expiry_at > effective_at),
  constraint costing_responses_vendor_ref_check check (
    (source_type = 'vendor' and vendor_ref is not null and length(trim(vendor_ref)) > 0)
    or source_type = 'internal'
  )
);

comment on table app.costing_responses is
  'COM-148: a componentized cost response to one costing request, from an internal or (free-text-referenced) vendor source -- vendor_ref is never a reference into a real vendor master (Procurement Phase 6 owns that; ADR-0015 reserves rate/cost-lookup ownership for COM-149). total_amount is always server-computed as the sum of app.costing_response_components, never a client-supplied figure that could drift from its own line items.';

create index costing_responses_request_idx on app.costing_responses (costing_request_id);

create table app.costing_response_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  costing_response_id uuid not null references app.costing_responses (id),
  costing_request_component_id uuid not null references app.costing_request_components (id),
  amount numeric(14, 2) not null,
  created_at timestamptz not null default now(),
  constraint costing_response_components_amount_check check (amount >= 0),
  constraint costing_response_components_unique unique (costing_response_id, costing_request_component_id)
);

comment on table app.costing_response_components is
  'COM-148: one priced amount per requested component per response -- app.costing_responses.total_amount is always exactly the sum of these rows for that response.';

create index costing_response_components_response_idx on app.costing_response_components (costing_response_id);

-- Field-masking gate (PLT-114/COM-147 pattern) for the seeded, protected COM:View cost
-- permission -- never previously consumed by any Commercial capability.
create function app.has_view_cost(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'COM', 'View cost')).allowed;
$$;

comment on function app.has_view_cost is
  'Field-masking gate (COM-148, mirrors COM-147''s app.has_view_selling_price) -- true if the caller holds the real, seeded COM:View cost permission (PLT-111/112) for the given tenant.';

grant execute on function app.has_view_cost(uuid, uuid) to authenticated;

create function app.request_costing(
  p_opportunity_id uuid,
  p_components jsonb,
  p_due_at timestamptz,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.costing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
  v_ready boolean;
  v_missing text[];
  v_request app.costing_requests;
  v_component jsonb;
begin
  select * into v_opportunity from app.opportunities where id = p_opportunity_id;
  if not found then
    raise exception 'opportunity_not_found: %', p_opportunity_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_opportunity.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_opportunity.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Reuses app.get_opportunity_costing_readiness (COM-147) directly -- it already
  -- performs its own app.can_access_record check against this opportunity, so no
  -- duplicate access check is needed here.
  select ready, missing into v_ready, v_missing from app.get_opportunity_costing_readiness(p_opportunity_id, p_actor_auth_user_id);
  if not v_ready then
    raise exception 'requirements_incomplete: opportunity % is missing %', p_opportunity_id, array_to_string(v_missing, ', ')
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.costing_requests (
      tenant_id, opportunity_id, source_opportunity_version, requirements_snapshot, due_at,
      owner_user_id, org_unit_id, created_by
    ) values (
      v_opportunity.tenant_id, p_opportunity_id, v_opportunity.record_version, v_opportunity.requirements, p_due_at,
      v_opportunity.owner_user_id, v_opportunity.org_unit_id, p_created_by
    )
    returning * into v_request;
  exception
    when unique_violation then
      select * into v_request from app.costing_requests
      where tenant_id = v_opportunity.tenant_id and opportunity_id = p_opportunity_id and source_opportunity_version = v_opportunity.record_version;
      return v_request;
  end;

  if p_components is not null then
    for v_component in select * from jsonb_array_elements(p_components)
    loop
      insert into app.costing_request_components (tenant_id, costing_request_id, component_code, description, quantity, unit)
      values (
        v_request.tenant_id, v_request.id,
        v_component ->> 'code',
        v_component ->> 'description',
        nullif(v_component ->> 'quantity', '')::numeric,
        v_component ->> 'unit'
      );
    end loop;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_created_by, 'request_costing',
    'app.costing_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.request_costing is
  'COM-148: idempotent on (tenant_id, opportunity_id, source_opportunity_version) including under a concurrent-insert race. Requires app.get_opportunity_costing_readiness to report ready=true first -- an incomplete opportunity cannot start a cost request (Prompt 148 §23).';

create function app.assign_costing_request(
  p_request_id uuid,
  p_expected_version integer,
  p_assignee_user_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.costing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.costing_requests;
  v_decision app.rbac_decision;
begin
  select * into v_request from app.costing_requests where id = p_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: costing request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot be assigned', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.costing_requests
  set assignee_user_id = p_assignee_user_id,
      status = case when status = 'pending' then 'assigned' else status end,
      updated_at = now(),
      record_version = record_version + 1
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_costing_request',
    'app.costing_requests', v_request.id, 'success', null, null, jsonb_build_object('assignee_user_id', p_assignee_user_id)
  );

  return v_request;
end;
$$;

create function app.submit_costing_response(
  p_request_id uuid,
  p_source_type text,
  p_vendor_ref text,
  p_currency text,
  p_effective_at timestamptz,
  p_expiry_at timestamptz,
  p_components jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.costing_responses
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.costing_requests;
  v_decision_edit app.rbac_decision;
  v_response app.costing_responses;
  v_component jsonb;
  v_component_id uuid;
  v_amount numeric;
  v_total numeric := 0;
begin
  select * into v_request from app.costing_requests where id = p_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot accept a response', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision_edit := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision_edit.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision_edit.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_view_cost(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View cost required to submit a cost response', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_components is null or jsonb_array_length(p_components) = 0 then
    raise exception 'components_required: a costing response requires at least one priced component'
      using errcode = 'not_null_violation';
  end if;

  insert into app.costing_responses (
    tenant_id, costing_request_id, source_type, vendor_ref, currency, effective_at, expiry_at, submitted_by
  ) values (
    v_request.tenant_id, p_request_id, p_source_type, p_vendor_ref, p_currency,
    coalesce(p_effective_at, now()), p_expiry_at, p_actor_label
  )
  returning * into v_response;

  for v_component in select * from jsonb_array_elements(p_components)
  loop
    v_component_id := (v_component ->> 'requestComponentId')::uuid;
    v_amount := (v_component ->> 'amount')::numeric;

    if not exists (select 1 from app.costing_request_components where id = v_component_id and costing_request_id = p_request_id) then
      raise exception 'unknown_request_component: % does not belong to costing request %', v_component_id, p_request_id
        using errcode = 'check_violation';
    end if;

    insert into app.costing_response_components (tenant_id, costing_response_id, costing_request_component_id, amount)
    values (v_request.tenant_id, v_response.id, v_component_id, v_amount);

    v_total := v_total + v_amount;
  end loop;

  update app.costing_responses set total_amount = v_total where id = v_response.id returning * into v_response;

  if v_request.status in ('pending', 'assigned') then
    update app.costing_requests set status = 'responded', updated_at = now(), record_version = record_version + 1 where id = p_request_id;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_costing_response',
    'app.costing_responses', v_response.id, 'success', null, null,
    jsonb_build_object('costing_request_id', p_request_id, 'source_type', p_source_type, 'total_amount', v_total, 'currency', p_currency)
  );

  return v_response;
end;
$$;

comment on function app.submit_costing_response is
  'COM-148: requires both COM:Edit and COM:View cost -- an actor cannot enter a cost figure they are not entitled to see back (mirrors COM-147''s app.update_opportunity value-write gate). total_amount is always computed as the sum of the supplied components, never trusted from the caller. Moves the parent request to status=responded on its first response.';

create function app.revise_costing_request(
  p_request_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.costing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_source app.costing_requests;
  v_opportunity app.opportunities;
  v_decision app.rbac_decision;
  v_ready boolean;
  v_missing text[];
  v_new_request app.costing_requests;
begin
  select * into v_source from app.costing_requests where id = p_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_source.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot be revised', p_request_id, v_source.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_source.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_source.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_source.tenant_id, v_source.owner_user_id, app.lead_record_scope_org_unit_ids(v_source.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_opportunity from app.opportunities where id = v_source.opportunity_id;

  select ready, missing into v_ready, v_missing from app.get_opportunity_costing_readiness(v_opportunity.id, p_actor_auth_user_id);
  if not v_ready then
    raise exception 'requirements_incomplete: opportunity % is missing %', v_opportunity.id, array_to_string(v_missing, ', ')
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.costing_requests (
      tenant_id, opportunity_id, source_opportunity_version, requirements_snapshot, due_at,
      revised_from_id, owner_user_id, org_unit_id, created_by
    ) values (
      v_opportunity.tenant_id, v_opportunity.id, v_opportunity.record_version, v_opportunity.requirements, v_source.due_at,
      v_source.id, v_opportunity.owner_user_id, v_opportunity.org_unit_id, p_created_by
    )
    returning * into v_new_request;
  exception
    when unique_violation then
      raise exception 'no_new_version: opportunity % has not changed since costing request % -- nothing to revise', v_opportunity.id, p_request_id
        using errcode = 'check_violation';
  end;

  insert into app.costing_request_components (tenant_id, costing_request_id, component_code, description, quantity, unit)
  select v_new_request.tenant_id, v_new_request.id, component_code, description, quantity, unit
  from app.costing_request_components
  where costing_request_id = v_source.id;

  update app.costing_requests
  set status = 'superseded', updated_at = now(), record_version = record_version + 1
  where id = v_source.id;

  perform app.capture_audit_event(
    v_new_request.tenant_id, p_actor_auth_user_id, p_created_by, 'revise_costing_request',
    'app.costing_requests', v_new_request.id, 'success', null, null, jsonb_build_object('revised_from_id', v_source.id)
  );

  return v_new_request;
end;
$$;

comment on function app.revise_costing_request is
  'COM-148: creates a new costing request row pinned to the opportunity''s *current* record_version/requirements and marks the source superseded -- never edits the source in place, so every response already linked to it remains reachable (Prompt 148 §25). Raises no_new_version if the opportunity has not actually changed since the source request (the unique (tenant, opportunity, version) constraint would otherwise silently return the same row, which is the wrong outcome for an explicit "revise" action).';

create function app.cancel_costing_request(
  p_request_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.costing_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.costing_requests;
  v_decision app.rbac_decision;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: cancelling a costing request requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_request from app.costing_requests where id = p_request_id;
  if not found then
    raise exception 'costing_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: costing request % expected version % but found %', p_request_id, p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_request.status in ('cancelled', 'superseded') then
    raise exception 'invalid_transition: costing request % is % and cannot be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, p_request_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.costing_requests
  set status = 'cancelled', cancel_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_costing_request',
    'app.costing_requests', v_request.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_request;
end;
$$;

-- Field-masked projection of app.costing_responses (COM-148, mirrors COM-147's
-- app.opportunities_directory -- security_invoker=false is required for the masking to
-- work at all; see this migration's header note).
create view app.costing_responses_directory
as
select
  r.id,
  r.tenant_id,
  r.costing_request_id,
  r.source_type,
  r.vendor_ref,
  case when app.has_view_cost(r.tenant_id) then r.currency else null end as currency,
  case when app.has_view_cost(r.tenant_id) then r.total_amount else null end as total_amount,
  not app.has_view_cost(r.tenant_id) as cost_masked,
  r.effective_at,
  r.expiry_at,
  (r.expiry_at is not null and r.expiry_at < now()) as is_expired,
  r.submitted_by,
  r.created_at
from app.costing_responses r
join app.costing_requests cr on cr.id = r.costing_request_id
where app.can_access_record(auth.uid(), cr.tenant_id, cr.owner_user_id, app.lead_record_scope_org_unit_ids(cr.org_unit_id), null);

comment on view app.costing_responses_directory is
  'COM-148: field-masked projection of app.costing_responses -- currency/total_amount are nulled out (cost_masked=true) for any caller lacking the real, seeded COM:View cost permission. authenticated has no direct column-level grant on those two columns on app.costing_responses itself (see column grant below), forcing every read through this view. Adds its own explicit app.can_access_record(...) row filter since security_invoker=false means the base table''s RLS does not apply to this view''s own read.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

alter table app.costing_requests enable row level security;
alter table app.costing_request_components enable row level security;
alter table app.costing_responses enable row level security;
alter table app.costing_response_components enable row level security;

create policy costing_requests_select_scoped on app.costing_requests
  for select to authenticated
  using (
    app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null)
  );

create policy costing_request_components_select_scoped on app.costing_request_components
  for select to authenticated
  using (
    exists (
      select 1 from app.costing_requests cr
      where cr.id = costing_request_components.costing_request_id
        and app.can_access_record(auth.uid(), cr.tenant_id, cr.owner_user_id, app.lead_record_scope_org_unit_ids(cr.org_unit_id), null)
    )
  );

-- Base-table select is record-scoped like every other Commercial table, but the two
-- sensitive columns (currency, total_amount) are additionally withheld at the column-grant
-- layer below -- app.costing_responses_directory is the only path that can ever surface
-- them, and only to a caller holding COM:View cost.
create policy costing_responses_select_scoped on app.costing_responses
  for select to authenticated
  using (
    exists (
      select 1 from app.costing_requests cr
      where cr.id = costing_responses.costing_request_id
        and app.can_access_record(auth.uid(), cr.tenant_id, cr.owner_user_id, app.lead_record_scope_org_unit_ids(cr.org_unit_id), null)
    )
  );

-- Component-level cost detail has no "masked but visible" state -- an actor either holds
-- COM:View cost and sees every row, or holds no entitlement to this table at all.
create policy costing_response_components_select_scoped on app.costing_response_components
  for select to authenticated
  using (
    app.has_view_cost(tenant_id)
    and exists (
      select 1 from app.costing_responses r
      join app.costing_requests cr on cr.id = r.costing_request_id
      where r.id = costing_response_components.costing_response_id
        and app.can_access_record(auth.uid(), cr.tenant_id, cr.owner_user_id, app.lead_record_scope_org_unit_ids(cr.org_unit_id), null)
    )
  );

grant usage on schema app to authenticated;
grant select on app.costing_requests to authenticated, service_role;
grant select on app.costing_request_components to authenticated, service_role;
grant select on app.costing_response_components to authenticated, service_role;
grant select on app.costing_responses_directory to authenticated, service_role;

-- The database guarantee (matches PLT-114/COM-147's own proven technique): a bare
-- column-level REVOKE cannot carve an exception out of a broader table-level GRANT -- the
-- table-level grant must be revoked entirely and re-granted on an explicit column list
-- that omits currency/total_amount.
grant select (
  id, tenant_id, costing_request_id, source_type, vendor_ref, effective_at, expiry_at,
  submitted_by, created_at
) on app.costing_responses to authenticated;
grant select on app.costing_responses to service_role;

grant execute on function app.request_costing(uuid, jsonb, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.assign_costing_request(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.submit_costing_response(uuid, text, text, text, timestamptz, timestamptz, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.revise_costing_request(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_costing_request(uuid, integer, text, uuid, text) to authenticated, service_role;
