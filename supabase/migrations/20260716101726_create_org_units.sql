-- Platform Core capability PLT-109 (Organization and Operational Hierarchy, CG-S6-PLT-006)
-- Tenant-scoped organization tree: company/branch/department/business_unit nodes with
-- cycle-free, cross-tenant-safe parent/child edges, a materialized-path ancestry column
-- for indexed ancestor/descendant queries (no recursive N+1 -- Prompt 109 §17), and
-- move/rename/status lifecycle guarded by optimistic concurrency (Prompt 109 §14).
--
-- Node-type parent rules are this checkpoint's own disclosed construction -- no ratified
-- ADR or architecture document fixes an exact allowed-parent-type matrix beyond
-- `05_DATABASE_SCHEMA_WORKSTREAM.md` §2's flat list ("companies, branches, departments,
-- business_units", no relationships specified). Chosen shape: company is always a root;
-- branch's parent is a company; department's parent is a company, a branch, or another
-- department (sub-departments allowed); business_unit's parent is a company (a
-- cross-cutting grouping, not nested under branch/department). Recorded here, not
-- silently assumed, so a later capability can revisit it with an explicit decision.
--
-- Referenced nodes are never hard-deleted (Prompt 109 §24) -- there is no delete
-- function, only app.set_org_unit_status() to 'inactive', and deactivation is blocked
-- while any active child exists (a real dependency check, not merely documented intent).

create table app.org_units (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  unit_type text not null,
  parent_id uuid references app.org_units (id),
  code text not null,
  name text not null,
  status text not null default 'active',
  path uuid[] not null default '{}'::uuid[],
  depth integer not null default 0,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint org_units_unit_type_check
    check (unit_type in ('company', 'branch', 'department', 'business_unit')),
  constraint org_units_status_check
    check (status in ('active', 'inactive')),
  constraint org_units_not_self_parent check (parent_id is distinct from id),
  constraint org_units_code_unique unique (tenant_id, code)
);

comment on table app.org_units is
  'Tenant-scoped organization hierarchy (PLT-109): company/branch/department/business_unit nodes. path is the materialized ancestor-id list (root first, self excluded) -- ancestor/descendant queries use it directly, never a recursive CTE. Nodes are never hard-deleted; app.set_org_unit_status() is the only lifecycle transition.';

create index org_units_tenant_id_idx on app.org_units (tenant_id);
create index org_units_parent_id_idx on app.org_units (parent_id);
create index org_units_path_gin_idx on app.org_units using gin (path);

create table app.org_unit_history (
  id uuid primary key default gen_random_uuid(),
  org_unit_id uuid not null,
  tenant_id uuid not null,
  event_type text not null,
  before_parent_id uuid,
  after_parent_id uuid,
  before_name text,
  after_name text,
  before_status text,
  after_status text,
  reason text,
  requested_by text,
  occurred_at timestamptz not null default now(),
  constraint org_unit_history_event_type_check
    check (event_type in ('create', 'move', 'rename', 'status_change'))
);

create index org_unit_history_org_unit_id_idx
  on app.org_unit_history (org_unit_id, occurred_at desc);

create function app.touch_org_unit_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger org_units_touch_row
  before update on app.org_units
  for each row
  execute function app.touch_org_unit_row();

-- Allowed parent-type matrix + cross-tenant/cycle guard, enforced on every insert and on
-- every parent_id change (the only way a cycle or a cross-tenant edge could ever appear).
create function app.enforce_org_unit_parent_shape()
returns trigger
language plpgsql
as $$
declare
  v_parent app.org_units;
begin
  if new.parent_id is null then
    if new.unit_type <> 'company' then
      raise exception 'invalid_org_unit_parent: % must have a parent (only company is a root type)', new.unit_type
        using errcode = 'check_violation';
    end if;
    return new;
  end if;

  select * into v_parent from app.org_units where id = new.parent_id;
  if not found then
    raise exception 'org_unit_parent_not_found: parent % does not exist', new.parent_id
      using errcode = 'no_data_found';
  end if;

  if v_parent.tenant_id <> new.tenant_id then
    raise exception 'cross_tenant_parent: parent % belongs to a different tenant', new.parent_id
      using errcode = 'check_violation';
  end if;

  if not (
    (new.unit_type = 'branch' and v_parent.unit_type = 'company')
    or (new.unit_type = 'department' and v_parent.unit_type in ('company', 'branch', 'department'))
    or (new.unit_type = 'business_unit' and v_parent.unit_type = 'company')
  ) then
    raise exception 'invalid_org_unit_parent: a % may not be parented under a %', new.unit_type, v_parent.unit_type
      using errcode = 'check_violation';
  end if;

  -- Cycle guard: a node can never become its own ancestor. On UPDATE (move), the
  -- candidate parent's own path (or id) must not contain this node.
  if tg_op = 'UPDATE' and (v_parent.path @> array[old.id] or v_parent.id = old.id) then
    raise exception 'org_unit_cycle: % cannot be moved under its own descendant %', old.id, new.parent_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger org_units_enforce_parent_shape
  before insert or update of parent_id on app.org_units
  for each row
  execute function app.enforce_org_unit_parent_shape();

-- Recomputes this row's own path/depth from its (already-validated) parent. Runs after
-- the shape/cycle guard above so it always sees a legal parent_id.
create function app.recompute_org_unit_path()
returns trigger
language plpgsql
as $$
declare
  v_parent app.org_units;
begin
  if new.parent_id is null then
    new.path := '{}'::uuid[];
    new.depth := 0;
    return new;
  end if;

  select * into v_parent from app.org_units where id = new.parent_id;
  new.path := v_parent.path || v_parent.id;
  new.depth := v_parent.depth + 1;
  return new;
end;
$$;

create trigger org_units_recompute_path
  before insert or update of parent_id on app.org_units
  for each row
  execute function app.recompute_org_unit_path();

-- Idempotent creation -- a repeated create for the same (tenant_id, code) returns the
-- original row if the type/parent match, or raises a real conflict if they do not
-- (a genuine code reuse across a different node, not a safe retry).
create function app.create_org_unit(
  p_tenant_id uuid,
  p_unit_type text,
  p_parent_id uuid,
  p_code text,
  p_name text,
  p_requested_by text
)
returns app.org_units
language plpgsql
as $$
declare
  v_existing app.org_units;
  v_unit app.org_units;
begin
  select * into v_existing from app.org_units where tenant_id = p_tenant_id and code = p_code;

  if found then
    if v_existing.unit_type <> p_unit_type or v_existing.parent_id is distinct from p_parent_id then
      raise exception 'org_unit_code_conflict: code % already exists for tenant % with a different type/parent', p_code, p_tenant_id
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  insert into app.org_units (tenant_id, unit_type, parent_id, code, name)
  values (p_tenant_id, p_unit_type, p_parent_id, p_code, p_name)
  returning * into v_unit;

  insert into app.org_unit_history (org_unit_id, tenant_id, event_type, after_parent_id, after_name, after_status, requested_by)
  values (v_unit.id, p_tenant_id, 'create', p_parent_id, p_name, 'active', p_requested_by);

  return v_unit;
end;
$$;

-- Moves a node (and, by the path-cascade below, every descendant) under a new parent.
-- Optimistic concurrency: p_expected_version must match the row's current record_version,
-- or the move is rejected outright rather than silently overwriting a concurrent change.
create function app.move_org_unit(
  p_id uuid,
  p_new_parent_id uuid,
  p_expected_version integer,
  p_requested_by text
)
returns app.org_units
language plpgsql
as $$
declare
  v_current app.org_units;
  v_updated app.org_units;
  v_old_path_prefix uuid[];
  v_new_path_prefix uuid[];
  v_depth_delta integer;
begin
  select * into v_current from app.org_units where id = p_id;
  if not found then
    raise exception 'org_unit_not_found: no org unit %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'org_unit_version_conflict: expected version %, found %', p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;

  v_old_path_prefix := v_current.path || v_current.id;

  update app.org_units
  set parent_id = p_new_parent_id
  where id = p_id
  returning * into v_updated;

  v_new_path_prefix := v_updated.path || v_updated.id;
  v_depth_delta := v_updated.depth - v_current.depth;

  -- Cascade: every descendant's path had v_old_path_prefix as a leading segment;
  -- splice in the new prefix in its place and shift depth by the same delta. Bounded by
  -- this node's actual descendant count, not a recursive per-row walk.
  update app.org_units d
  set path = v_new_path_prefix || d.path[array_length(v_old_path_prefix, 1) + 1 : array_length(d.path, 1)],
      depth = d.depth + v_depth_delta
  where d.path @> array[p_id];

  insert into app.org_unit_history (org_unit_id, tenant_id, event_type, before_parent_id, after_parent_id, requested_by)
  values (p_id, v_current.tenant_id, 'move', v_current.parent_id, p_new_parent_id, p_requested_by);

  return v_updated;
end;
$$;

create function app.rename_org_unit(
  p_id uuid,
  p_new_name text,
  p_expected_version integer,
  p_requested_by text
)
returns app.org_units
language plpgsql
as $$
declare
  v_current app.org_units;
  v_updated app.org_units;
begin
  select * into v_current from app.org_units where id = p_id;
  if not found then
    raise exception 'org_unit_not_found: no org unit %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'org_unit_version_conflict: expected version %, found %', p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;

  update app.org_units set name = p_new_name where id = p_id returning * into v_updated;

  insert into app.org_unit_history (org_unit_id, tenant_id, event_type, before_name, after_name, requested_by)
  values (p_id, v_current.tenant_id, 'rename', v_current.name, p_new_name, p_requested_by);

  return v_updated;
end;
$$;

-- Deactivation is blocked while any active child exists (a real, checked dependency, not
-- just a documented intent) -- children must be deactivated first, innermost out.
create function app.set_org_unit_status(
  p_id uuid,
  p_new_status text,
  p_expected_version integer,
  p_reason text,
  p_requested_by text
)
returns app.org_units
language plpgsql
as $$
declare
  v_current app.org_units;
  v_updated app.org_units;
  v_active_children integer;
begin
  select * into v_current from app.org_units where id = p_id;
  if not found then
    raise exception 'org_unit_not_found: no org unit %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'org_unit_version_conflict: expected version %, found %', p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;

  if v_current.status = p_new_status then
    return v_current;
  end if;

  if p_new_status = 'inactive' then
    select count(*) into v_active_children
    from app.org_units
    where parent_id = p_id and status = 'active';

    if v_active_children > 0 then
      raise exception 'org_unit_has_active_children: % cannot be deactivated while % active child/children exist', p_id, v_active_children
        using errcode = 'check_violation';
    end if;
  end if;

  update app.org_units set status = p_new_status where id = p_id returning * into v_updated;

  insert into app.org_unit_history (org_unit_id, tenant_id, event_type, before_status, after_status, reason, requested_by)
  values (p_id, v_current.tenant_id, 'status_change', v_current.status, p_new_status, p_reason, p_requested_by);

  return v_updated;
end;
$$;

-- Scope ancestry helpers (Prompt 109 §20 task 4) -- direct path-array reads, no recursion.
create function app.org_unit_ancestor_ids(p_id uuid)
returns uuid[]
language sql
stable
as $$
  select path from app.org_units where id = p_id;
$$;

create function app.org_unit_descendant_ids(p_id uuid)
returns setof uuid
language sql
stable
as $$
  select id from app.org_units where path @> array[p_id];
$$;

-- RLS: identical defense-in-depth posture to PLT-105/106/107/108.
alter table app.org_units enable row level security;
alter table app.org_unit_history enable row level security;

grant select, insert, update, delete
  on app.org_units, app.org_unit_history
  to service_role;
grant execute on function app.create_org_unit(uuid, text, uuid, text, text, text) to service_role;
grant execute on function app.move_org_unit(uuid, uuid, integer, text) to service_role;
grant execute on function app.rename_org_unit(uuid, text, integer, text) to service_role;
grant execute on function app.set_org_unit_status(uuid, text, integer, text, text) to service_role;
grant execute on function app.org_unit_ancestor_ids(uuid) to service_role;
grant execute on function app.org_unit_descendant_ids(uuid) to service_role;
