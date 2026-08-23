-- IAE-032 (Prompt 360, Group 8): Dedicated Enterprise Deployment.
--
-- Design decisions (cited, not re-derived):
--
-- 1. Genuinely greenfield -- confirmed by direct grep before writing any code
--    (no `deployment`/`provisioning` table or function exists anywhere in
--    `app`). RPD-011 ("shared database/shared schema with RLS remains
--    default; dedicated instance is a paid Enterprise option only") is the
--    real, structural default this checkpoint preserves: `app.
--    resolve_tenant_deployment_type` returns `'shared'` for every tenant
--    with no record at all, and only a real, approved, `active`
--    `app.tenant_deployment_records` row ever returns `'dedicated'` --
--    mirroring `IAE-031`'s own `app.resolve_retention_days` fallback shape
--    exactly.
-- 2. New `DEPLOY` entitlement module (`View`/`Configure`/`Approve`) --
--    Prompt 360's own workstream is "Enterprise Deployment", distinct from
--    every Group 7 module.
-- 3. No real infrastructure is provisioned by this checkpoint -- there is no
--    dedicated-instance provisioning API/IaC anywhere in this repository,
--    and none is added here. This builds the real, structural GOVERNANCE
--    evidence layer (qualification, contract/security/CTO approval,
--    provisioning status, environment-isolation reference records) an
--    actual provisioning runbook/tool would read from and write into --
--    disclosed honestly, the same bounded-scope posture `IAE-030`'s own "no
--    external APM integration" already established.
-- 4. Real, structural state machine, not merely disclosed: `app.
--    set_deployment_provisioning_status` enforces a real, ordered
--    transition graph (`pending_qualification -> qualified -> provisioning
--    -> active -> decommissioned`) -- "Provisioning requires contract/
--    security/CTO approval" (Prompt 360 §24) is enforced by requiring a real
--    `qualified` status (itself requiring a separate `DEPLOY:Approve`
--    action). Self-approval is forbidden at BOTH the CHECK-constraint level
--    (`tenant_deployment_records_no_self_approval`) AND an explicit,
--    cleanly-named application check inside `app.
--    approve_dedicated_deployment_qualification` itself -- the identical
--    two-layer guard `IAE-031`'s own `legal_holds_no_self_release`
--    precedent established, applied correctly from the first draft here
--    (requires the table to actually track `created_by_auth_user_id`,
--    which it does) before `provisioning`/`active` can ever be reached.
-- 5. `app.tenant_deployment_environment_refs` stores only a real REFERENCE
--    string (a pointer/label to an external secrets manager entry, backup
--    location, or observability workspace) -- never a real secret value --
--    the identical "reference, never the secret itself" boundary `PLT-118`'s
--    own credential-reference tables already established.
-- 6. Lessons carried forward verbatim from Group 7's own Tier C review
--    (`docs/build-log/phase-09/00_EXECUTION_INDEX.md` §16), applied from
--    the first draft rather than re-discovered:
--    (a) every function taking a tenant-shaped identifier has a real actor
--        parameter and a real authority check -- no bare-tenant-id-only
--        helper is ever granted to `authenticated`;
--    (b) every `tenant_id`-nullable UNIQUE constraint (platform-wide default
--        rows) uses `unique nulls not distinct` from the start;
--    (c) every idempotent "get or create" bootstrap uses `on conflict do
--        nothing` + re-select, never a bare check-then-insert;
--    (d) every self-approval-shaped break-glass action has BOTH a hard CHECK
--        constraint AND an explicit, cleanly-named application check.
-- 7. Every authenticated-reachable function is `SECURITY DEFINER` paired
--    with `app.assert_actor_is_session_identity` as its first statement.
-- 8. Per the standing convention since `PLT-118`: explicit, redundant
--    `revoke execute on all functions in schema app from public`.

-- ===========================================================================
-- 1. DEPLOY entitlement module.
-- ===========================================================================

insert into app.entitlement_modules (code, name, owning_phase) values
  ('DEPLOY', 'Enterprise deployment governance: dedicated instance qualification, region policy, provisioning evidence', 9);

insert into app.permissions (action, resource_module_code, category, protected) values
  ('View', 'DEPLOY', 'standard', false),
  ('Configure', 'DEPLOY', 'admin', false),
  ('Approve', 'DEPLOY', 'admin', true);

-- ===========================================================================
-- 2. app.tenant_deployment_records -- real qualification/provisioning state.
-- ===========================================================================

create table app.tenant_deployment_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  deployment_type text not null default 'dedicated',
  status text not null default 'pending_qualification',
  qualification_reason text not null,
  contract_reference text,
  approved_by_auth_user_id uuid references auth.users (id),
  approved_by text,
  approved_at timestamptz,
  provisioned_at timestamptz,
  decommissioned_at timestamptz,
  created_by_auth_user_id uuid references auth.users (id),
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint tenant_deployment_records_type_check check (deployment_type in ('dedicated')),
  constraint tenant_deployment_records_status_check check (status in ('pending_qualification', 'qualified', 'provisioning', 'active', 'decommissioned')),
  constraint tenant_deployment_records_tenant_unique unique (tenant_id),
  constraint tenant_deployment_records_no_self_approval check (approved_by_auth_user_id is null or approved_by_auth_user_id <> created_by_auth_user_id)
);

comment on table app.tenant_deployment_records is
  'IAE-032: one optional row per tenant -- ABSENCE means shared/default deployment (RPD-011). deployment_type is always ''dedicated'' here by construction: a shared tenant never gets a row at all, matching app.resolve_tenant_deployment_type''s own fallback design.';

create function app.touch_tenant_deployment_record_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenant_deployment_records_touch_row
  before update on app.tenant_deployment_records
  for each row
  execute function app.touch_tenant_deployment_record_row();

create function app.request_dedicated_deployment_qualification(
  p_tenant_id uuid,
  p_qualification_reason text,
  p_contract_reference text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_deployment_records
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_record app.tenant_deployment_records;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'DEPLOY', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(trim(p_qualification_reason), '') = '' then
    raise exception 'deployment_qualification_reason_required: a real qualification reason must be stated' using errcode = 'check_violation';
  end if;

  insert into app.tenant_deployment_records (tenant_id, qualification_reason, contract_reference, created_by_auth_user_id, created_by)
  values (p_tenant_id, p_qualification_reason, p_contract_reference, p_actor_auth_user_id, p_actor_label)
  returning * into v_record;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_dedicated_deployment_qualification',
    'app.tenant_deployment_records', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$$;

comment on function app.request_dedicated_deployment_qualification is
  'IAE-032: fails with a real unique_violation if this tenant already has a deployment record -- exactly one dedicated-deployment qualification lifecycle per tenant, never a second parallel one.';

create function app.approve_dedicated_deployment_qualification(
  p_deployment_record_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_deployment_records
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.tenant_deployment_records;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_deployment_records where id = p_deployment_record_id and status = 'pending_qualification' for update;
  if not found then
    raise exception 'deployment_record_not_pending_qualification: % is not a pending-qualification deployment record', p_deployment_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_record.created_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'deployment_self_approval_forbidden: identity % cannot approve a dedicated deployment qualification they themselves requested', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.tenant_deployment_records
  set status = 'qualified', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, approved_at = now()
  where id = p_deployment_record_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_dedicated_deployment_qualification',
    'app.tenant_deployment_records', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$$;

comment on function app.approve_dedicated_deployment_qualification is
  'IAE-032: "Provisioning requires contract/security/CTO approval" (Prompt 360 §24) -- DEPLOY:Approve is a real, separate authority tier from DEPLOY:Configure (which merely requested the qualification); the underlying app.principal_memberships/app.role_assignments authority model does not by itself prevent one identity from holding both, so self-approval is additionally forbidden explicitly here (deployment_self_approval_forbidden) AND at the tenant_deployment_records_no_self_approval CHECK-constraint level, mirroring IAE-031''s own legal_holds_no_self_release precedent.';

create function app.set_deployment_provisioning_status(
  p_deployment_record_id uuid,
  p_new_status text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_deployment_records
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.tenant_deployment_records;
  v_decision app.rbac_decision;
  v_valid_transition boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_deployment_records where id = p_deployment_record_id for update;
  if not found then
    raise exception 'deployment_record_not_found: %', p_deployment_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_valid_transition := (v_record.status, p_new_status) in (
    ('qualified', 'provisioning'),
    ('provisioning', 'active'),
    ('active', 'decommissioned')
  );
  if not v_valid_transition then
    raise exception 'deployment_invalid_transition: % -> % is not a valid provisioning transition', v_record.status, p_new_status
      using errcode = 'check_violation';
  end if;

  update app.tenant_deployment_records
  set status = p_new_status,
      provisioned_at = case when p_new_status = 'active' then now() else provisioned_at end,
      decommissioned_at = case when p_new_status = 'decommissioned' then now() else decommissioned_at end
  where id = p_deployment_record_id
  returning * into v_record;

  perform app.capture_audit_event(
    v_record.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_deployment_provisioning_status',
    'app.tenant_deployment_records', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
end;
$$;

comment on function app.set_deployment_provisioning_status is
  'IAE-032: real, ordered transition graph -- pending_qualification can NEVER reach provisioning/active directly (design decision 4); every transition is a real, audited, DEPLOY:Configure-gated event, not a free-form status field.';

create function app.resolve_tenant_deployment_type(p_tenant_id uuid)
returns text
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select coalesce(
    (select 'dedicated' from app.tenant_deployment_records where tenant_id = p_tenant_id and status = 'active'),
    'shared'
  );
$$;

comment on function app.resolve_tenant_deployment_type is
  'IAE-032: RPD-011''s own real default -- returns ''shared'' for every tenant unless a real deployment record has actually reached status=active. A pending_qualification/qualified/provisioning record does NOT yet flip this -- the tenant remains ''shared'' in fact until provisioning genuinely completes.';

-- ===========================================================================
-- 3. app.tenant_deployment_environment_refs -- reference, never the secret
-- itself (design decision 5).
-- ===========================================================================

create table app.tenant_deployment_environment_refs (
  id uuid primary key default gen_random_uuid(),
  deployment_record_id uuid not null references app.tenant_deployment_records (id),
  environment_category text not null,
  reference_value text not null,
  verified_by_auth_user_id uuid references auth.users (id),
  verified_by text,
  verified_at timestamptz,
  created_by text,
  created_at timestamptz not null default now(),
  constraint tenant_deployment_environment_refs_category_check check (environment_category in ('database', 'secrets', 'backup', 'observability')),
  constraint tenant_deployment_environment_refs_unique unique (deployment_record_id, environment_category)
);

comment on table app.tenant_deployment_environment_refs is
  'IAE-032: a real pointer/label into an external secrets manager, backup system, or observability workspace -- never a real secret value. "Environment secrets and data are isolated by deployment" (Prompt 360 §24) evidence, one row per category per deployment.';

create function app.set_deployment_environment_ref(
  p_deployment_record_id uuid,
  p_environment_category text,
  p_reference_value text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_deployment_environment_refs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.tenant_deployment_records;
  v_decision app.rbac_decision;
  v_ref app.tenant_deployment_environment_refs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_deployment_records where id = p_deployment_record_id;
  if not found then
    raise exception 'deployment_record_not_found: %', p_deployment_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_environment_category not in ('database', 'secrets', 'backup', 'observability') then
    raise exception 'deployment_invalid_environment_category: %', p_environment_category using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_reference_value), '') = '' then
    raise exception 'deployment_reference_value_required: a real reference value must be stated' using errcode = 'check_violation';
  end if;

  insert into app.tenant_deployment_environment_refs (deployment_record_id, environment_category, reference_value, verified_by_auth_user_id, verified_by, verified_at, created_by)
  values (p_deployment_record_id, p_environment_category, p_reference_value, p_actor_auth_user_id, p_actor_label, now(), p_actor_label)
  on conflict (deployment_record_id, environment_category) do update
    set reference_value = excluded.reference_value, verified_by_auth_user_id = excluded.verified_by_auth_user_id, verified_by = excluded.verified_by, verified_at = excluded.verified_at
  returning * into v_ref;

  return v_ref;
end;
$$;

-- ===========================================================================
-- 4. Read paths.
-- ===========================================================================

create function app.get_tenant_deployment_record(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.tenant_deployment_records
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_record app.tenant_deployment_records;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'DEPLOY', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_record from app.tenant_deployment_records where tenant_id = p_tenant_id;
  return v_record;
end;
$$;

create function app.list_deployment_environment_refs(p_deployment_record_id uuid, p_actor_auth_user_id uuid)
returns setof app.tenant_deployment_environment_refs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_record app.tenant_deployment_records;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_record from app.tenant_deployment_records where id = p_deployment_record_id;
  if not found then
    raise exception 'deployment_record_not_found: %', p_deployment_record_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_record.tenant_id, 'DEPLOY', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks DEPLOY:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_record.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.tenant_deployment_environment_refs where deployment_record_id = p_deployment_record_id order by environment_category asc;
end;
$$;

-- ===========================================================================
-- 5. RLS: default-deny, RPC-only.
-- ===========================================================================

alter table app.tenant_deployment_records enable row level security;
alter table app.tenant_deployment_environment_refs enable row level security;

revoke all on app.tenant_deployment_records from public, anon, authenticated;
revoke all on app.tenant_deployment_environment_refs from public, anon, authenticated;
grant all on app.tenant_deployment_records, app.tenant_deployment_environment_refs to service_role;

revoke execute on all functions in schema app from public;

-- app.resolve_tenant_deployment_type takes a bare p_tenant_id with no actor/
-- authority parameter at all -- the identical shape app.is_high_risk_action
-- (IAE-027) and app.resolve_retention_days (IAE-031) already established and
-- were each fixed the same way: any authenticated identity of any tenant
-- could otherwise probe another tenant's own deployment type. The real,
-- actor-gated (DEPLOY:View) disclosure path for a tenant's own deployment
-- state is app.get_tenant_deployment_record -- service_role-only here.
grant execute on function app.resolve_tenant_deployment_type(uuid) to service_role;

grant execute on function
  app.request_dedicated_deployment_qualification(uuid, text, text, uuid, text),
  app.approve_dedicated_deployment_qualification(uuid, uuid, text),
  app.set_deployment_provisioning_status(uuid, text, uuid, text),
  app.set_deployment_environment_ref(uuid, text, text, uuid, text),
  app.get_tenant_deployment_record(uuid, uuid),
  app.list_deployment_environment_refs(uuid, uuid)
to authenticated, service_role;
