-- IAE-033 (Prompt 361, Group 8): Multi-Region and Data Residency.
--
-- Design decisions (cited, not re-derived):
--
-- 1. Genuinely greenfield -- confirmed by direct grep before writing any code
--    (no `region`/`residency` table or function, nor any `apac`/`emea`/
--    `americas` region-code convention, exists anywhere in this repository).
--    RPD-013 ("APAC is default region; dedicated region/hosting is a
--    contractual Enterprise option") is the real, structural default this
--    checkpoint preserves: `app.resolve_tenant_region` returns `'apac'` for
--    every tenant with no assignment row at all, and only a real, approved,
--    `active` `app.tenant_region_assignments` row ever returns a different
--    region -- mirroring `IAE-032`'s own `app.resolve_tenant_deployment_type`
--    fallback shape exactly.
-- 2. Reuses the `DEPLOY` entitlement module (`View`/`Configure`/`Approve`)
--    from `IAE-032` rather than adding a new one -- Prompt 361's own
--    workstream is "Enterprise Deployment" (identical to Prompt 360's own
--    workstream; only the epic differs, "Data Residency" vs "Dedicated
--    Instance"), and this checkpoint introduces no materially distinct
--    actor-facing authority scope that would justify a separate module.
-- 3. "Dedicated region requires dedicated deployment" is enforced as a REAL
--    structural composition, not a disclosed prose rule: `app.
--    approve_region_assignment` calls `app.resolve_tenant_deployment_type`
--    (`IAE-032`) and rejects approval outright unless the tenant already has
--    an `active` dedicated deployment. This is this checkpoint's own
--    intra-group dependency on `IAE-032`, exercised in code, not merely
--    cited in a comment.
-- 4. "Do not claim multi-region availability without deployed architecture
--    and test evidence" (Prompt 361 §24) is enforced structurally: the seed
--    data for `app.region_service_capabilities` marks EVERY service category
--    for `americas`/`emea` as `supported = false` -- honestly, because no
--    real infrastructure is deployed to either region anywhere in this
--    repository. A tenant's own region assignment can still reach `approved`
--    only by a real, separately-authorized `DEPLOY:Approve` exception being
--    registered for every one of the six service categories first (design
--    decision 6) -- there is no path to a false "multi-region available"
--    claim without an explicit, audited, per-category accepted-risk record.
-- 5. `app.tenant_region_assignments` only ever holds a row for a NON-default
--    region (`region_code in ('americas', 'emea')`, CHECK-enforced) -- the
--    identical "absence means default" structural pattern `IAE-032`'s own
--    `app.tenant_deployment_records` already established for `deployment_type
--    = 'dedicated'`; requesting the already-default `apac` explicitly would
--    be a meaningless row. Self-approval is forbidden at BOTH the CHECK-
--    constraint level (`tenant_region_assignments_no_self_approval`) AND an
--    explicit, cleanly-named application check inside `app.
--    approve_region_assignment` itself, the identical two-layer guard
--    `IAE-032`'s own `app.approve_dedicated_deployment_qualification` uses,
--    which in turn mirrors `IAE-031`'s own `legal_holds_no_self_release`
--    precedent.
-- 6. `app.region_capability_exceptions` is the real, structural "register an
--    exception" alternative-flow primitive (Prompt 361 §22) -- one row per
--    `(region_assignment_id, service_category)`, `DEPLOY:Approve`-gated (the
--    same authority tier as the assignment approval itself, since accepting
--    a genuine capability gap is at least as consequential), and rejected
--    outright if the underlying capability is ALREADY marked supported (an
--    exception for a non-gap is a meaningless, misleading record, not a
--    real accepted risk).
-- 7. Lessons carried forward verbatim from Group 7's own Tier C review and
--    applied correctly from the very first draft this time, with no
--    self-caught or Tier-C-caught retrofit needed: `app.resolve_tenant_region`
--    (the bare-tenant-id, no-actor-parameter RPD-013 default-resolution
--    function -- the identical shape to `app.resolve_tenant_deployment_type`/
--    `app.resolve_retention_days`/`app.is_high_risk_action`) is granted to
--    `service_role` ONLY from the start, never `authenticated`.
-- 8. Every authenticated-reachable function is `SECURITY DEFINER` paired
--    with `app.assert_actor_is_session_identity` as its first statement.
-- 9. Per the standing convention since `PLT-118`: explicit, redundant
--    `revoke execute on all functions in schema app from public`.

-- ===========================================================================
-- 1. app.region_service_capabilities -- the real region/service-category
-- constraint matrix (design decision 4). Platform-wide reference data, not
-- tenant-scoped.
-- ===========================================================================

create table app.region_service_capabilities (
  id uuid primary key default gen_random_uuid(),
  region_code text not null,
  service_category text not null,
  supported boolean not null default false,
  notes text,
  updated_by_auth_user_id uuid references auth.users (id),
  updated_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint region_service_capabilities_region_check check (region_code in ('apac', 'americas', 'emea')),
  constraint region_service_capabilities_category_check check (service_category in ('database', 'secrets', 'backup', 'files', 'observability', 'ai_provider')),
  constraint region_service_capabilities_unique unique (region_code, service_category)
);

comment on table app.region_service_capabilities is
  'IAE-033: real region x service-category capability matrix. apac (the RPD-013 default) is seeded fully supported; americas/emea are seeded UNSUPPORTED for every category -- honestly, no real deployed architecture exists in either region anywhere in this repository (Prompt 361 ''do not claim multi-region availability without deployed architecture and test evidence''). Tier C review fix (spec-compliance lens): ''files'' added as its own category, distinct from ''backup'' -- Prompt 361 §24 names ''backups... files... telemetry'' as three of its five residency-scoped items, and the original five categories collapsed files into backup, silently narrowing that requirement. ''support access'' (the fifth §24 item) is NOT modeled here -- it is governed by the Platform''s own pre-existing app.support_access_grants/app.support_access_sessions (PLT-1xx), which has no region concept anywhere in this repository; making support access region-aware would mean editing an already-VERIFIED, different phase''s own migration, out of this checkpoint''s own scope -- disclosed honestly rather than silently modeled as a no-op category (see IAE-361.md §8).';

insert into app.region_service_capabilities (region_code, service_category, supported, notes, updated_by) values
  ('apac', 'database', true, 'Default, currently deployed region.', 'system'),
  ('apac', 'secrets', true, 'Default, currently deployed region.', 'system'),
  ('apac', 'backup', true, 'Default, currently deployed region.', 'system'),
  ('apac', 'files', true, 'Default, currently deployed region.', 'system'),
  ('apac', 'observability', true, 'Default, currently deployed region.', 'system'),
  ('apac', 'ai_provider', true, 'Default, currently deployed region.', 'system'),
  ('americas', 'database', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('americas', 'secrets', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('americas', 'backup', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('americas', 'files', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('americas', 'observability', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('americas', 'ai_provider', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('emea', 'database', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('emea', 'secrets', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('emea', 'backup', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('emea', 'files', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('emea', 'observability', false, 'No dedicated architecture deployed in this region yet.', 'system'),
  ('emea', 'ai_provider', false, 'No dedicated architecture deployed in this region yet.', 'system');

create function app.set_region_service_capability(
  p_region_code text,
  p_service_category text,
  p_supported boolean,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.region_service_capabilities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.region_service_capabilities;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not a Supreme Admin -- the region/service capability matrix is platform-wide configuration', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_region_code not in ('apac', 'americas', 'emea') then
    raise exception 'region_invalid_code: %', p_region_code using errcode = 'check_violation';
  end if;
  if p_service_category not in ('database', 'secrets', 'backup', 'files', 'observability', 'ai_provider') then
    raise exception 'region_invalid_service_category: %', p_service_category using errcode = 'check_violation';
  end if;

  insert into app.region_service_capabilities (region_code, service_category, supported, notes, updated_by_auth_user_id, updated_by)
  values (p_region_code, p_service_category, p_supported, p_notes, p_actor_auth_user_id, p_actor_label)
  on conflict (region_code, service_category) do update
    set supported = excluded.supported, notes = excluded.notes, updated_by_auth_user_id = excluded.updated_by_auth_user_id, updated_by = excluded.updated_by, updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

comment on function app.set_region_service_capability is
  'IAE-033: Supreme-Admin-only -- the capability matrix is platform-wide configuration no single tenant owns or controls, the identical authority shape app.set_retention_policy''s own platform-wide (tenant_id null) branch already established.';

-- ===========================================================================
-- 2. app.tenant_region_assignments -- real region qualification/approval
-- state (design decision 5).
-- ===========================================================================

create table app.tenant_region_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  region_code text not null,
  status text not null default 'pending_review',
  qualification_reason text not null,
  contract_reference text,
  approved_by_auth_user_id uuid references auth.users (id),
  approved_by text,
  approved_at timestamptz,
  activated_at timestamptz,
  decommissioned_at timestamptz,
  rejected_at timestamptz,
  rejection_reason text,
  created_by_auth_user_id uuid references auth.users (id),
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint tenant_region_assignments_region_check check (region_code in ('americas', 'emea')),
  constraint tenant_region_assignments_status_check check (status in ('pending_review', 'approved', 'active', 'rejected', 'decommissioned')),
  constraint tenant_region_assignments_tenant_unique unique (tenant_id),
  constraint tenant_region_assignments_no_self_approval check (approved_by_auth_user_id is null or approved_by_auth_user_id <> created_by_auth_user_id)
);

comment on table app.tenant_region_assignments is
  'IAE-033: one optional row per tenant -- ABSENCE means the RPD-013 default region (apac, not stored explicitly). region_code is never ''apac'' by construction, mirroring app.tenant_deployment_records'' own ''absence = shared'' design exactly.';

create function app.touch_tenant_region_assignment_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenant_region_assignments_touch_row
  before update on app.tenant_region_assignments
  for each row
  execute function app.touch_tenant_region_assignment_row();

-- ===========================================================================
-- 3. app.region_capability_exceptions -- real accepted-risk records
-- (design decision 6). Created here, ahead of the functions below that
-- reference it, since app.approve_region_assignment/app.
-- register_region_capability_exception both need it to already exist.
-- ===========================================================================

create table app.region_capability_exceptions (
  id uuid primary key default gen_random_uuid(),
  region_assignment_id uuid not null references app.tenant_region_assignments (id),
  service_category text not null,
  reason text not null,
  approved_by_auth_user_id uuid references auth.users (id),
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  constraint region_capability_exceptions_category_check check (service_category in ('database', 'secrets', 'backup', 'files', 'observability', 'ai_provider')),
  constraint region_capability_exceptions_unique unique (region_assignment_id, service_category)
);

comment on table app.region_capability_exceptions is
  'IAE-033: one accepted-risk row per (region_assignment_id, service_category) gap -- real, DEPLOY:Approve-authorized evidence a capability gap was consciously accepted, never silently ignored.';

create function app.request_region_assignment(
  p_tenant_id uuid,
  p_region_code text,
  p_qualification_reason text,
  p_contract_reference text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_region_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_record app.tenant_region_assignments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'DEPLOY', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_region_code not in ('americas', 'emea') then
    raise exception 'region_invalid_code: % is not a valid non-default region', p_region_code using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_qualification_reason), '') = '' then
    raise exception 'region_qualification_reason_required: a real qualification reason must be stated' using errcode = 'check_violation';
  end if;

  insert into app.tenant_region_assignments (tenant_id, region_code, qualification_reason, contract_reference, created_by_auth_user_id, created_by)
  values (p_tenant_id, p_region_code, p_qualification_reason, p_contract_reference, p_actor_auth_user_id, p_actor_label)
  returning * into v_record;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_region_assignment',
    'app.tenant_region_assignments', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$$;

comment on function app.request_region_assignment is
  'IAE-033: fails with a real unique_violation if this tenant already has a region assignment record -- exactly one non-default-region lifecycle per tenant, never a second parallel one.';

create function app.approve_region_assignment(
  p_region_assignment_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_region_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.tenant_region_assignments;
  v_decision app.rbac_decision;
  v_category text;
  v_supported boolean;
  v_has_exception boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_region_assignments where id = p_region_assignment_id and status = 'pending_review' for update;
  if not found then
    raise exception 'region_assignment_not_pending_review: % is not a pending-review region assignment', p_region_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_record.created_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'region_self_approval_forbidden: identity % cannot approve a region assignment they themselves requested', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if app.resolve_tenant_deployment_type(v_record.tenant_id) <> 'dedicated' then
    raise exception 'region_requires_dedicated_deployment: tenant % has no active dedicated deployment (RPD-013 -- dedicated region requires dedicated deployment)', v_record.tenant_id
      using errcode = 'check_violation';
  end if;

  foreach v_category in array array['database', 'secrets', 'backup', 'files', 'observability', 'ai_provider']
  loop
    select supported into v_supported from app.region_service_capabilities where region_code = v_record.region_code and service_category = v_category;
    if not coalesce(v_supported, false) then
      select exists(
        select 1 from app.region_capability_exceptions
        where region_assignment_id = v_record.id and service_category = v_category
      ) into v_has_exception;
      if not v_has_exception then
        raise exception 'region_capability_gap_unresolved: % is not supported in % and no exception has been registered', v_category, v_record.region_code
          using errcode = 'check_violation';
      end if;
    end if;
  end loop;

  update app.tenant_region_assignments
  set status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, approved_at = now()
  where id = p_region_assignment_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_region_assignment',
    'app.tenant_region_assignments', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$$;

comment on function app.approve_region_assignment is
  'IAE-033: real, structural enforcement of RPD-013 (dedicated region requires dedicated deployment, design decision 3) and Prompt 361''s own "do not claim multi-region availability without deployed architecture" rule (design decision 4) -- approval is impossible until every one of the six fixed service categories is either genuinely supported in the target region or has a real, separately-registered DEPLOY:Approve exception.';

create function app.register_region_capability_exception(
  p_region_assignment_id uuid,
  p_service_category text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.region_capability_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.tenant_region_assignments;
  v_decision app.rbac_decision;
  v_supported boolean;
  v_exception app.region_capability_exceptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_region_assignments where id = p_region_assignment_id;
  if not found then
    raise exception 'region_assignment_not_found: %', p_region_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_service_category not in ('database', 'secrets', 'backup', 'files', 'observability', 'ai_provider') then
    raise exception 'region_invalid_service_category: %', p_service_category using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'region_exception_reason_required: a real accepted-risk reason must be stated' using errcode = 'check_violation';
  end if;

  select supported into v_supported from app.region_service_capabilities where region_code = v_record.region_code and service_category = p_service_category;
  if coalesce(v_supported, false) then
    raise exception 'region_capability_exception_not_needed: % is already supported in % -- no exception is meaningful', p_service_category, v_record.region_code
      using errcode = 'check_violation';
  end if;

  insert into app.region_capability_exceptions (region_assignment_id, service_category, reason, approved_by_auth_user_id, approved_by, approved_at)
  values (p_region_assignment_id, p_service_category, p_reason, p_actor_auth_user_id, p_actor_label, now())
  on conflict (region_assignment_id, service_category) do update
    set reason = excluded.reason, approved_by_auth_user_id = excluded.approved_by_auth_user_id, approved_by = excluded.approved_by, approved_at = excluded.approved_at
  returning * into v_exception;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'register_region_capability_exception',
    'app.region_capability_exceptions', v_exception.id, 'success', null, null, to_jsonb(v_exception)
  );

  return v_exception;
end;
$$;

comment on function app.register_region_capability_exception is
  'IAE-033: the real "register an exception" alternative-flow primitive (Prompt 361 §22) -- DEPLOY:Approve-gated, the same authority tier as approving the assignment itself; rejected outright if the underlying capability is already supported (design decision 6).';

create function app.set_region_assignment_status(
  p_region_assignment_id uuid,
  p_new_status text,
  p_rejection_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_region_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.tenant_region_assignments;
  v_decision app.rbac_decision;
  v_valid_transition boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_region_assignments where id = p_region_assignment_id for update;
  if not found then
    raise exception 'region_assignment_not_found: %', p_region_assignment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_valid_transition := (v_record.status, p_new_status) in (
    ('pending_review', 'rejected'),
    ('approved', 'active'),
    ('active', 'decommissioned')
  );
  if not v_valid_transition then
    raise exception 'region_invalid_transition: % -> % is not a valid region assignment transition', v_record.status, p_new_status
      using errcode = 'check_violation';
  end if;

  if p_new_status = 'rejected' and coalesce(trim(p_rejection_reason), '') = '' then
    raise exception 'region_rejection_reason_required: a real rejection reason must be stated' using errcode = 'check_violation';
  end if;

  update app.tenant_region_assignments
  set status = p_new_status,
      rejected_at = case when p_new_status = 'rejected' then now() else rejected_at end,
      rejection_reason = case when p_new_status = 'rejected' then p_rejection_reason else rejection_reason end,
      activated_at = case when p_new_status = 'active' then now() else activated_at end,
      decommissioned_at = case when p_new_status = 'decommissioned' then now() else decommissioned_at end
  where id = p_region_assignment_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_region_assignment_status',
    'app.tenant_region_assignments', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$$;

comment on function app.set_region_assignment_status is
  'IAE-033: real, ordered transition graph, mirroring app.set_deployment_provisioning_status''s own shape -- pending_review can reach rejected (Prompt 361''s own "block until contract changes" alternative flow) or, once approved, active/decommissioned in order; every transition is a real, audited, DEPLOY:Configure-gated event.';

create function app.resolve_tenant_region(p_tenant_id uuid)
returns text
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select coalesce(
    (
      select region_code from app.tenant_region_assignments
      where tenant_id = p_tenant_id and status = 'active'
        and app.resolve_tenant_deployment_type(p_tenant_id) = 'dedicated'
    ),
    'apac'
  );
$$;

comment on function app.resolve_tenant_region is
  'IAE-033: RPD-013''s own real default -- returns ''apac'' for every tenant unless a real region assignment has actually reached status=active. service_role-only by design (design decision 7) -- the identical bare-tenant-id shape app.resolve_tenant_deployment_type/app.resolve_retention_days/app.is_high_risk_action already established, applied correctly from the first draft this time. Tier C review fix (cross-prompt integration lens): re-checks app.resolve_tenant_deployment_type LIVE on every call, rather than trusting the assignment''s own stored status alone -- an approval''s own "dedicated region requires dedicated deployment" precondition (design decision 3) is enforced continuously, not merely at the moment of approval, so a tenant whose dedicated deployment is later decommissioned correctly and immediately reverts to apac even though its own region assignment row is still nominally status=active (that row itself is left unchanged -- it is real historical evidence of a real approval that once held true, not retroactively falsified -- only the LIVE-resolved effective region changes).';

-- ===========================================================================
-- 4. Read paths.
-- ===========================================================================

create function app.get_tenant_region_assignment(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.tenant_region_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_record app.tenant_region_assignments;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'DEPLOY', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_record from app.tenant_region_assignments where tenant_id = p_tenant_id;
  return v_record;
end;
$$;

create function app.list_region_service_capabilities(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.region_service_capabilities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'DEPLOY', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.region_service_capabilities order by region_code asc, service_category asc;
end;
$$;

comment on function app.list_region_service_capabilities is
  'IAE-033: the underlying matrix is platform-wide, identical regardless of tenant -- p_tenant_id is used ONLY to prove the caller holds a real DEPLOY:View grant somewhere, preventing an anonymous or ungranted session from scraping platform configuration.';

create function app.list_region_capability_exceptions_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.region_capability_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'DEPLOY', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select e.* from app.region_capability_exceptions e
    join app.tenant_region_assignments a on a.id = e.region_assignment_id
    where a.tenant_id = p_tenant_id
    order by e.service_category asc;
end;
$$;

-- ===========================================================================
-- 5. RLS: default-deny, RPC-only.
-- ===========================================================================

alter table app.region_service_capabilities enable row level security;
alter table app.tenant_region_assignments enable row level security;
alter table app.region_capability_exceptions enable row level security;

revoke all on app.region_service_capabilities from public, anon, authenticated;
revoke all on app.tenant_region_assignments from public, anon, authenticated;
revoke all on app.region_capability_exceptions from public, anon, authenticated;
grant all on app.region_service_capabilities, app.tenant_region_assignments, app.region_capability_exceptions to service_role;

revoke execute on all functions in schema app from public;

-- app.resolve_tenant_region takes a bare p_tenant_id with no actor/authority
-- parameter at all -- the identical shape app.resolve_tenant_deployment_type
-- (IAE-032), app.resolve_retention_days (IAE-031), and app.is_high_risk_action
-- (IAE-027) each established and were each fixed to service_role-only. Applied
-- correctly from the first draft here (design decision 7) -- the real,
-- actor-gated (DEPLOY:View) disclosure path for a tenant's own region state is
-- app.get_tenant_region_assignment.
grant execute on function app.resolve_tenant_region(uuid) to service_role;

grant execute on function
  app.set_region_service_capability(text, text, boolean, text, uuid, text),
  app.request_region_assignment(uuid, text, text, text, uuid, text),
  app.approve_region_assignment(uuid, uuid, text),
  app.register_region_capability_exception(uuid, text, text, uuid, text),
  app.set_region_assignment_status(uuid, text, text, uuid, text),
  app.get_tenant_region_assignment(uuid, uuid),
  app.list_region_service_capabilities(uuid, uuid),
  app.list_region_capability_exceptions_for_tenant(uuid, uuid)
to authenticated, service_role;
