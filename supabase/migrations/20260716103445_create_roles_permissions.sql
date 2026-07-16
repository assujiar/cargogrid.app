-- Platform Core capability PLT-111 (Role and Permission Builder, CG-S6-PLT-008)
-- Canonical permission catalogue (stable, Supreme-Admin-only) plus a versioned tenant
-- role builder (draft -> publish -> archive, clone) and scope-safe assignment. Role
-- assignment alone never bypasses entitlement/RLS/field/record rules (Prompt 111 §24) --
-- this migration grants no data access by itself; RBAC *enforcement* against these
-- bindings is PLT-112's own scope, not this one's.
--
-- app.permissions is reproduced from real, already-VERIFIED architecture evidence, the
-- same "one source, not a fabricated list" discipline PLT-106 established for its module/
-- feature catalogue: the 19 permission actions are docs/architecture/06_RLS_RBAC_WORKSTREAM.md
-- §5.1 (itself Tech Arch §12.1, verbatim), and the "resource" dimension reuses PLT-106's
-- own 9 real business-domain module codes (app.entitlement_modules) rather than inventing
-- a second, competing resource taxonomy. Not every action applies meaningfully to every
-- module -- the seed below is a real, disclosed, per-module subset, not the full 19x9
-- cross-product.
--
-- Roles themselves are never seeded (Prompt 111 §12 forbids hard-coded tenant roles) --
-- app.roles starts empty; every row is tenant-created.

create table app.permissions (
  id uuid primary key default gen_random_uuid(),
  action text not null,
  resource_module_code text not null references app.entitlement_modules (code),
  category text not null,
  protected boolean not null default false,
  code text generated always as (resource_module_code || ':' || action) stored,
  created_at timestamptz not null default now(),
  constraint permissions_action_check check (action in (
    'View', 'Create', 'Edit', 'Delete', 'Approve', 'Reject', 'Assign', 'Export', 'Import',
    'Print', 'Download', 'View cost', 'View selling price', 'View margin', 'View payroll',
    'View personal data', 'Configure', 'Override', 'Reopen', 'Close'
  )),
  constraint permissions_category_check check (category in ('standard', 'workflow', 'sensitive', 'admin')),
  constraint permissions_module_action_unique unique (resource_module_code, action)
);

comment on table app.permissions is
  'Canonical, stable permission catalogue (PLT-111), reproduced from docs/architecture/06_RLS_RBAC_WORKSTREAM.md §5.1 (19 actions) against PLT-106''s real 9-module catalogue. protected=true matches §5.2''s field-masking-gated actions (View cost/View selling price/View margin/View payroll/View personal data) -- only Supreme Admin controls this catalogue (Prompt 111 §26).';

-- category: 'sensitive' = §5.2's field-masking-gated actions (protected=true);
-- 'workflow' = approval/lifecycle actions; 'admin' = configuration; 'standard' = the rest.
insert into app.permissions (action, resource_module_code, category, protected) values
  ('View', 'COM', 'standard', false), ('Create', 'COM', 'standard', false), ('Edit', 'COM', 'standard', false),
  ('Delete', 'COM', 'standard', false), ('Approve', 'COM', 'workflow', false), ('Export', 'COM', 'standard', false),
  ('View selling price', 'COM', 'sensitive', true),

  ('View', 'OPS', 'standard', false), ('Create', 'OPS', 'standard', false), ('Edit', 'OPS', 'standard', false),
  ('Delete', 'OPS', 'standard', false), ('Assign', 'OPS', 'standard', false), ('Export', 'OPS', 'standard', false),
  ('Print', 'OPS', 'standard', false), ('Download', 'OPS', 'standard', false), ('Override', 'OPS', 'workflow', false),
  ('Reopen', 'OPS', 'workflow', false), ('Close', 'OPS', 'workflow', false),

  ('View', 'FIN', 'standard', false), ('Create', 'FIN', 'standard', false), ('Edit', 'FIN', 'standard', false),
  ('Delete', 'FIN', 'standard', false), ('Approve', 'FIN', 'workflow', false), ('Reject', 'FIN', 'workflow', false),
  ('Export', 'FIN', 'standard', false), ('View cost', 'FIN', 'sensitive', true), ('View margin', 'FIN', 'sensitive', true),
  ('Override', 'FIN', 'workflow', false), ('Reopen', 'FIN', 'workflow', false), ('Close', 'FIN', 'workflow', false),

  ('View', 'PRC', 'standard', false), ('Create', 'PRC', 'standard', false), ('Edit', 'PRC', 'standard', false),
  ('Delete', 'PRC', 'standard', false), ('Approve', 'PRC', 'workflow', false), ('Export', 'PRC', 'standard', false),
  ('View cost', 'PRC', 'sensitive', true),

  ('View', 'HRS', 'standard', false), ('Create', 'HRS', 'standard', false), ('Edit', 'HRS', 'standard', false),
  ('Delete', 'HRS', 'standard', false), ('Approve', 'HRS', 'workflow', false), ('Export', 'HRS', 'standard', false),
  ('View payroll', 'HRS', 'sensitive', true), ('View personal data', 'HRS', 'sensitive', true),

  ('View', 'TKT', 'standard', false), ('Create', 'TKT', 'standard', false), ('Edit', 'TKT', 'standard', false),
  ('Delete', 'TKT', 'standard', false), ('Assign', 'TKT', 'standard', false), ('Export', 'TKT', 'standard', false),
  ('Close', 'TKT', 'workflow', false), ('Reopen', 'TKT', 'workflow', false),

  ('View', 'CPT', 'standard', false), ('Export', 'CPT', 'standard', false), ('Download', 'CPT', 'standard', false),

  ('View', 'LYL', 'standard', false), ('Create', 'LYL', 'standard', false), ('Edit', 'LYL', 'standard', false),
  ('Configure', 'LYL', 'admin', false),

  ('View', 'REP', 'standard', false), ('Export', 'REP', 'standard', false), ('Print', 'REP', 'standard', false),
  ('Configure', 'REP', 'admin', false);

create index permissions_resource_module_code_idx on app.permissions (resource_module_code);

create table app.roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  name text not null,
  description text,
  status text not null default 'active',
  created_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint roles_status_check check (status in ('active', 'archived')),
  constraint roles_tenant_name_unique unique (tenant_id, name)
);

comment on table app.roles is
  'A tenant-created custom role identity (PLT-111). Never seeded -- title/composition are tenant-configurable, but permission semantics remain the canonical app.permissions catalogue (Prompt 111 §24). The role''s actual permission set lives in a specific app.role_versions row, never here directly.';

create index roles_tenant_id_idx on app.roles (tenant_id);

create table app.role_versions (
  id uuid primary key default gen_random_uuid(),
  role_id uuid not null references app.roles (id),
  version_number integer not null,
  status text not null default 'draft',
  effective_from timestamptz,
  cloned_from_version_id uuid references app.role_versions (id),
  created_by text,
  published_by text,
  published_at timestamptz,
  archived_at timestamptz,
  archived_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint role_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint role_versions_role_version_unique unique (role_id, version_number)
);

comment on table app.role_versions is
  'One immutable-once-published snapshot of a role''s permission set (PLT-111). Publishing a new version archives the role''s previously published version -- a version''s bindings are never mutated after publish (Prompt 111 §22: "version change takes effect at approved date without mutating historical snapshot").';

create index role_versions_role_id_idx on app.role_versions (role_id);
-- At most one draft per role at a time.
create unique index role_versions_single_draft_per_role
  on app.role_versions (role_id) where status = 'draft';
-- At most one published version per role at a time.
create unique index role_versions_single_published_per_role
  on app.role_versions (role_id) where status = 'published';

create table app.role_version_permissions (
  role_version_id uuid not null references app.role_versions (id),
  permission_id uuid not null references app.permissions (id),
  primary key (role_version_id, permission_id)
);

create table app.role_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  role_version_id uuid not null references app.role_versions (id),
  auth_user_id uuid not null references auth.users (id),
  status text not null default 'active',
  granted_by text,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint role_assignments_status_check check (status in ('active', 'revoked'))
);

comment on table app.role_assignments is
  'A user holding a published role version within a tenant (PLT-111). Assignment alone grants no access -- RBAC enforcement against these bindings is PLT-112''s scope, not this one''s.';

create index role_assignments_tenant_id_idx on app.role_assignments (tenant_id);
create index role_assignments_auth_user_id_idx on app.role_assignments (auth_user_id);
-- At most one active assignment per (tenant, role_version, user).
create unique index role_assignments_active_unique
  on app.role_assignments (tenant_id, role_version_id, auth_user_id) where status = 'active';

create table app.role_lifecycle_history (
  id uuid primary key default gen_random_uuid(),
  role_id uuid,
  role_version_id uuid,
  role_assignment_id uuid,
  tenant_id uuid not null,
  event_type text not null,
  reason text,
  requested_by text,
  occurred_at timestamptz not null default now(),
  constraint role_lifecycle_history_event_type_check check (event_type in (
    'role_created', 'version_drafted', 'permissions_set', 'published', 'cloned', 'archived', 'assigned', 'revoked'
  ))
);

create index role_lifecycle_history_role_id_idx on app.role_lifecycle_history (role_id, occurred_at desc);

create function app.touch_role_version_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger role_versions_touch_row
  before update on app.role_versions
  for each row
  execute function app.touch_role_version_row();

create function app.touch_role_assignment_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger role_assignments_touch_row
  before update on app.role_assignments
  for each row
  execute function app.touch_role_assignment_row();

-- Idempotent role creation, matching the established PLT-105/107/108/109/110 pattern.
create function app.create_role(
  p_tenant_id uuid,
  p_name text,
  p_description text,
  p_created_by text
)
returns app.roles
language plpgsql
as $$
declare
  v_existing app.roles;
  v_role app.roles;
begin
  select * into v_existing from app.roles where tenant_id = p_tenant_id and name = p_name;
  if found then
    return v_existing;
  end if;

  insert into app.roles (tenant_id, name, description, created_by)
  values (p_tenant_id, p_name, p_description, p_created_by)
  returning * into v_role;

  insert into app.role_lifecycle_history (role_id, tenant_id, event_type, requested_by)
  values (v_role.id, p_tenant_id, 'role_created', p_created_by);

  return v_role;
end;
$$;

-- Idempotent draft creation -- a role may hold at most one draft at a time (enforced by
-- the partial unique index above); a repeated call while a draft already exists returns
-- that draft rather than raising, matching the session's established idempotency pattern.
create function app.create_role_version(
  p_role_id uuid,
  p_created_by text
)
returns app.role_versions
language plpgsql
as $$
declare
  v_role app.roles;
  v_existing_draft app.role_versions;
  v_next_version integer;
  v_version app.role_versions;
begin
  select * into v_role from app.roles where id = p_role_id;
  if not found then
    raise exception 'role_not_found: no role %', p_role_id
      using errcode = 'no_data_found';
  end if;

  select * into v_existing_draft from app.role_versions where role_id = p_role_id and status = 'draft';
  if found then
    return v_existing_draft;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.role_versions where role_id = p_role_id;

  insert into app.role_versions (role_id, version_number, created_by)
  values (p_role_id, v_next_version, p_created_by)
  returning * into v_version;

  insert into app.role_lifecycle_history (role_id, role_version_id, tenant_id, event_type, requested_by)
  values (p_role_id, v_version.id, v_role.tenant_id, 'version_drafted', p_created_by);

  return v_version;
end;
$$;

-- Replaces a draft version's full permission set -- only valid while status = 'draft'
-- (Prompt 111 §22: a published version's bindings are never mutated).
create function app.set_role_version_permissions(
  p_role_version_id uuid,
  p_permission_ids uuid[],
  p_requested_by text
)
returns integer
language plpgsql
as $$
declare
  v_version app.role_versions;
  v_role app.roles;
  v_count integer;
begin
  select * into v_version from app.role_versions where id = p_role_version_id;
  if not found then
    raise exception 'role_version_not_found: no role version %', p_role_version_id
      using errcode = 'no_data_found';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'role_version_not_draft: version % is %, only a draft''s permissions may be changed', p_role_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  delete from app.role_version_permissions where role_version_id = p_role_version_id;

  insert into app.role_version_permissions (role_version_id, permission_id)
  select p_role_version_id, unnest(p_permission_ids);

  select count(*) into v_count from app.role_version_permissions where role_version_id = p_role_version_id;

  select * into v_role from app.roles where id = v_version.role_id;
  insert into app.role_lifecycle_history (role_id, role_version_id, tenant_id, event_type, requested_by)
  values (v_version.role_id, p_role_version_id, v_role.tenant_id, 'permissions_set', p_requested_by);

  return v_count;
end;
$$;

-- Publishing a draft archives the role's previously published version (supersession, the
-- same pattern PLT-106's assign_entitlement established for package assignment).
create function app.publish_role_version(
  p_role_version_id uuid,
  p_effective_from timestamptz,
  p_published_by text
)
returns app.role_versions
language plpgsql
as $$
declare
  v_version app.role_versions;
  v_role app.roles;
  v_prior_published app.role_versions;
  v_updated app.role_versions;
begin
  select * into v_version from app.role_versions where id = p_role_version_id;
  if not found then
    raise exception 'role_version_not_found: no role version %', p_role_version_id
      using errcode = 'no_data_found';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'role_version_not_draft: version % is %, only a draft may be published', p_role_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  select * into v_prior_published from app.role_versions where role_id = v_version.role_id and status = 'published';
  if found then
    update app.role_versions set status = 'archived', archived_at = now(), archived_reason = 'superseded by a newer published version'
    where id = v_prior_published.id;
  end if;

  update app.role_versions
  set status = 'published', published_by = p_published_by, published_at = now(), effective_from = p_effective_from
  where id = p_role_version_id
  returning * into v_updated;

  select * into v_role from app.roles where id = v_version.role_id;
  insert into app.role_lifecycle_history (role_id, role_version_id, tenant_id, event_type, requested_by)
  values (v_version.role_id, p_role_version_id, v_role.tenant_id, 'published', p_published_by);

  return v_updated;
end;
$$;

-- Clones a published or archived version's permission bindings into a brand-new draft --
-- cloning a draft is meaningless (there is nothing stable yet to copy).
create function app.clone_role_version(
  p_role_version_id uuid,
  p_created_by text
)
returns app.role_versions
language plpgsql
as $$
declare
  v_source app.role_versions;
  v_role app.roles;
  v_new app.role_versions;
begin
  select * into v_source from app.role_versions where id = p_role_version_id;
  if not found then
    raise exception 'role_version_not_found: no role version %', p_role_version_id
      using errcode = 'no_data_found';
  end if;

  if v_source.status = 'draft' then
    raise exception 'cannot_clone_draft: version % is still a draft, nothing stable to clone', p_role_version_id
      using errcode = 'check_violation';
  end if;

  v_new := app.create_role_version(v_source.role_id, p_created_by);

  update app.role_versions set cloned_from_version_id = p_role_version_id where id = v_new.id
  returning * into v_new;

  insert into app.role_version_permissions (role_version_id, permission_id)
  select v_new.id, permission_id from app.role_version_permissions where role_version_id = p_role_version_id;

  select * into v_role from app.roles where id = v_source.role_id;
  insert into app.role_lifecycle_history (role_id, role_version_id, tenant_id, event_type, requested_by)
  values (v_source.role_id, v_new.id, v_role.tenant_id, 'cloned', p_created_by);

  return v_new;
end;
$$;

create function app.archive_role_version(
  p_role_version_id uuid,
  p_reason text,
  p_requested_by text
)
returns app.role_versions
language plpgsql
as $$
declare
  v_version app.role_versions;
  v_role app.roles;
  v_updated app.role_versions;
begin
  select * into v_version from app.role_versions where id = p_role_version_id;
  if not found then
    raise exception 'role_version_not_found: no role version %', p_role_version_id
      using errcode = 'no_data_found';
  end if;

  if v_version.status = 'archived' then
    return v_version;
  end if;

  update app.role_versions set status = 'archived', archived_at = now(), archived_reason = p_reason
  where id = p_role_version_id
  returning * into v_updated;

  select * into v_role from app.roles where id = v_version.role_id;
  insert into app.role_lifecycle_history (role_id, role_version_id, tenant_id, event_type, reason, requested_by)
  values (v_version.role_id, p_role_version_id, v_role.tenant_id, 'archived', p_reason, p_requested_by);

  return v_updated;
end;
$$;

-- Idempotent assignment with a real self-escalation guard (Prompt 111 §16/§23): an actor
-- may not assign to *themselves* a role version carrying any protected (sensitive-field)
-- permission. p_actor_auth_user_id is the real identity performing the assignment --
-- distinct from p_granted_by, which stays a free-text audit label like every other
-- function in this session.
create function app.assign_role(
  p_tenant_id uuid,
  p_role_version_id uuid,
  p_auth_user_id uuid,
  p_actor_auth_user_id uuid,
  p_granted_by text
)
returns app.role_assignments
language plpgsql
as $$
declare
  v_version app.role_versions;
  v_role app.roles;
  v_existing app.role_assignments;
  v_has_protected boolean;
  v_assignment app.role_assignments;
begin
  select * into v_version from app.role_versions where id = p_role_version_id;
  if not found then
    raise exception 'role_version_not_found: no role version %', p_role_version_id
      using errcode = 'no_data_found';
  end if;

  if v_version.status <> 'published' then
    raise exception 'role_version_not_published: version % is %, only a published version may be assigned', p_role_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  select * into v_role from app.roles where id = v_version.role_id;
  if v_role.tenant_id <> p_tenant_id then
    raise exception 'cross_tenant_role: role version % does not belong to tenant %', p_role_version_id, p_tenant_id
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from app.users where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and status = 'active') then
    raise exception 'user_not_active_in_tenant: identity % has no active user profile in tenant %', p_auth_user_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if p_actor_auth_user_id = p_auth_user_id then
    select exists (
      select 1 from app.role_version_permissions rvp
      join app.permissions perm on perm.id = rvp.permission_id
      where rvp.role_version_id = p_role_version_id and perm.protected = true
    ) into v_has_protected;

    if v_has_protected then
      raise exception 'self_escalation: an actor may not assign themselves a role version carrying a protected permission'
        using errcode = 'check_violation';
    end if;
  end if;

  select * into v_existing from app.role_assignments
  where tenant_id = p_tenant_id and role_version_id = p_role_version_id and auth_user_id = p_auth_user_id and status = 'active';
  if found then
    return v_existing;
  end if;

  insert into app.role_assignments (tenant_id, role_version_id, auth_user_id, granted_by)
  values (p_tenant_id, p_role_version_id, p_auth_user_id, p_granted_by)
  returning * into v_assignment;

  insert into app.role_lifecycle_history (role_id, role_version_id, role_assignment_id, tenant_id, event_type, requested_by)
  values (v_version.role_id, p_role_version_id, v_assignment.id, p_tenant_id, 'assigned', p_granted_by);

  return v_assignment;
end;
$$;

create function app.revoke_role_assignment(
  p_id uuid,
  p_reason text,
  p_requested_by text
)
returns app.role_assignments
language plpgsql
as $$
declare
  v_current app.role_assignments;
  v_updated app.role_assignments;
begin
  select * into v_current from app.role_assignments where id = p_id;
  if not found then
    raise exception 'role_assignment_not_found: no role assignment %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.status = 'revoked' then
    return v_current;
  end if;

  update app.role_assignments set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = p_id
  returning * into v_updated;

  insert into app.role_lifecycle_history (role_id, role_version_id, role_assignment_id, tenant_id, event_type, reason, requested_by)
  select rv.role_id, v_current.role_version_id, v_current.id, v_current.tenant_id, 'revoked', p_reason, p_requested_by
  from app.role_versions rv where rv.id = v_current.role_version_id;

  return v_updated;
end;
$$;

-- RLS: identical defense-in-depth posture to PLT-105/106/107/108/109/110.
alter table app.permissions enable row level security;
alter table app.roles enable row level security;
alter table app.role_versions enable row level security;
alter table app.role_version_permissions enable row level security;
alter table app.role_assignments enable row level security;
alter table app.role_lifecycle_history enable row level security;

grant select, insert, update, delete
  on app.permissions, app.roles, app.role_versions, app.role_version_permissions, app.role_assignments, app.role_lifecycle_history
  to service_role;
grant execute on function app.create_role(uuid, text, text, text) to service_role;
grant execute on function app.create_role_version(uuid, text) to service_role;
grant execute on function app.set_role_version_permissions(uuid, uuid[], text) to service_role;
grant execute on function app.publish_role_version(uuid, timestamptz, text) to service_role;
grant execute on function app.clone_role_version(uuid, text) to service_role;
grant execute on function app.archive_role_version(uuid, text, text) to service_role;
grant execute on function app.assign_role(uuid, uuid, uuid, uuid, text) to service_role;
grant execute on function app.revoke_role_assignment(uuid, text, text) to service_role;
