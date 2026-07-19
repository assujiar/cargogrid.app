-- Platform Core capability PLT-121 (Configuration Engine, CG-S6-PLT-018)
-- The shared versioned configuration foundation every later engine/module builds on:
-- config_type registry -> config_object (a scoped namespace) -> config_version
-- (draft/publish/rollback) -> config_item (the actual key/value settings) ->
-- config_dependency (cross-item dependency graph, cycle-checked at publish).
-- Implements Tech Arch §13's metadata model and 6-level override precedence
-- (docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md §4/§6/§8/§9, "VERIFIED"),
-- condensed onto this repository's own already-established versioning idiom
-- (PLT-111/117/119's draft/publish/rollback pattern) rather than introducing an
-- eighth, one-off lifecycle state machine.
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **10 config types bootstrap here, empty/template only** —
--   `07_CONFIGURATION_ENGINE_WORKSTREAM.md` §13's own Module Adoption Map, Phase 1
--   row, verbatim: "`workflow`, `approval`, `status`, `numbering`, `form`, `field`,
--   `notification`, `feature`, `branding`, `terminology` — all 10 engine types
--   bootstrap here, empty/template only." No real rule/approval/status content is
--   seeded (§12, forbidden: "full workflow/approval/forms modules... mass hard-code
--   migration") — later phases (§13's own table: Commercial at Phase 2, Operations at
--   Phase 3, ...) register their own real config content into this same mechanism via
--   `app.register_config_type()`, the same "shared mechanism, not a fork" discipline
--   `PLT-120`'s `app.register_master_type()` already established for master data.
-- * **The 8-state Tech Arch §13.3 lifecycle (`Draft -> Validating -> ValidationFailed
--   -> ReadyToPublish -> Published -> Active -> Superseded/RolledBack -> Archived`) is
--   condensed onto this repository's own established `draft/published/archived`
--   3-state pattern** (`PLT-111`'s `role_versions`, `PLT-117`'s `tenant_brand_versions`,
--   `PLT-119`'s `tenant_locale_versions`) plus rollback-via-new-version — a materially
--   different state machine for one capability alone would be inconsistency, not extra
--   rigor. `Validating`/`ValidationFailed`/`ReadyToPublish` collapse into
--   `app.publish_config_version()`'s own synchronous dependency/cycle validation gate
--   (§8) — a publish either passes validation and becomes `published`, or is rejected
--   outright; there is no separate persisted "failed validation" state to inspect later
--   because failure never mutates anything. `Active` collapses into `published` +
--   `effective_from` (checked by the resolver at read time, §6/§9) — no separate
--   physical state transition is needed for determinism. `Superseded` = `archived`
--   (superseded reason); `RolledBack` = `archived` + a new version created via
--   `app.rollback_config_version()` referencing it (never mutates the rolled-back
--   version itself, `PLT-117`/`119`'s own rollback discipline).
-- * **The bounded rule-expression evaluator (§11/§12 `ADR-CAND-ARCH-015`, "a rule
--   expression language... must be a bounded, sandboxed expression evaluator") is
--   deliberately NOT built here.** This checkpoint's `app.validate_config_value()`
--   enforces structural/injection safety on every `config_items.value` (real, tested,
--   database-enforced) -- but *executing* a bounded expression against real transaction
--   data has no real consumer yet (no business rule with actual runtime semantics
--   exists anywhere in this still-Platform-Core-only repository). Building the
--   evaluator now, with nothing real to evaluate, would be untestable busywork, the
--   same reasoning `PLT-116` applied to deferring `app.event_logs`. Deferred to
--   whichever Phase 2+ capability first needs to actually evaluate a rule (e.g.
--   `BR-QTN-001`'s margin-threshold condition).
-- * `config_items.canonical_ref` reuses `PLT-119`'s already-shipped
--   `app.canonical_terms` catalogue directly (when provided) rather than inventing a
--   second, competing canonical-reference mechanism — the same "reuse the existing
--   canonical mechanism" discipline `PLT-117` applied to `PLT-116`'s audit trail.
-- * Company/branch/role-scoped config objects reference `app.org_units`/`app.roles`
--   polymorphically via a single `scope_id` column, validated at the *application*
--   layer (every mutation function below), not a per-scope-level physical FK — the
--   same disclosed, sourced pattern `05_DATABASE_SCHEMA_WORKSTREAM.md` §4 already
--   established for `ticket_links` ("polymorphic links... use a typed reference table
--   with application-level validation, never a bare untyped FK"), reused here rather
--   than invented fresh.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

-- The config-type registry (Tech Arch §13.1's config_type catalogue). Extensible via
-- app.register_config_type() -- never a fixed CHECK enum -- the same registry-not-enum
-- choice PLT-120's app.master_types made, for the same reason: future phases add real
-- types (rule, sla, report, ...) without a schema migration.
create table app.config_types (
  code text primary key,
  name text not null,
  owner_primitive_code text not null,
  registered_by text,
  created_at timestamptz not null default now()
);

comment on table app.config_types is
  'PLT-121: the registry of configuration kinds (Tech Arch §13.1). owner_primitive_code names the owning Platform primitive from docs/architecture/01_MODULE_DEPENDENCY_MAP.md §2 (WF/APPR/STAT/NUM/FORM/NOTIF/FLAG/WLB, ...) -- deliberately NOT a foreign key to app.entitlement_modules, which PLT-106 scoped to the 9 business-domain subscription modules only (COM/OPS/FIN/PRC/HRS/TKT/CPT/LYL/REP) -- platform primitives are never themselves an entitlement-gated module.';

insert into app.config_types (code, name, owner_primitive_code, registered_by) values
  ('workflow', 'Workflow', 'WF', 'platform-core-foundation'),
  ('approval', 'Approval', 'APPR', 'platform-core-foundation'),
  ('status', 'Status', 'STAT', 'platform-core-foundation'),
  ('numbering', 'Numbering', 'NUM', 'platform-core-foundation'),
  ('form', 'Form', 'FORM', 'platform-core-foundation'),
  ('field', 'Custom Field', 'FORM', 'platform-core-foundation'),
  ('notification', 'Notification', 'NOTIF', 'platform-core-foundation'),
  ('feature', 'Feature Flag', 'FLAG', 'platform-core-foundation'),
  ('branding', 'Branding', 'WLB', 'platform-core-foundation'),
  ('terminology', 'Terminology', 'WLB', 'platform-core-foundation');

create function app.register_config_type(
  p_code text,
  p_name text,
  p_owner_primitive_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.config_types
language plpgsql
as $$
declare
  v_existing app.config_types;
  v_type app.config_types;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a config type'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.config_types where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.config_types (code, name, owner_primitive_code, registered_by)
  values (p_code, p_name, p_owner_primitive_code, p_registered_by)
  returning * into v_type;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_config_type',
    'app.config_types', null, 'success', null, null, to_jsonb(v_type)
  );

  return v_type;
end;
$$;

-- Structural/injection safety on every config value -- object or array only, bounded
-- depth/size, string leaves reject angle brackets. Real bounded-expression *evaluation*
-- is deliberately out of scope (this migration's own header).
create function app.validate_config_value(p_value jsonb, p_depth integer default 0)
returns boolean
language plpgsql
immutable
as $$
declare
  v_key text;
  v_element jsonb;
begin
  if p_depth > 5 then
    return false;
  end if;
  if p_value is null then
    return true;
  end if;

  if jsonb_typeof(p_value) = 'object' then
    if length(p_value::text) > 8192 then
      return false;
    end if;
    for v_key, v_element in select * from jsonb_each(p_value) loop
      if jsonb_typeof(v_element) = 'string' then
        if (v_element #>> '{}') ~ '[<>]' then
          return false;
        end if;
      elsif jsonb_typeof(v_element) in ('object', 'array') then
        if not app.validate_config_value(v_element, p_depth + 1) then
          return false;
        end if;
      elsif jsonb_typeof(v_element) not in ('number', 'boolean', 'null') then
        return false;
      end if;
    end loop;
    return true;
  elsif jsonb_typeof(p_value) = 'array' then
    if jsonb_array_length(p_value) > 50 then
      return false;
    end if;
    for v_element in select * from jsonb_array_elements(p_value) loop
      if jsonb_typeof(v_element) = 'string' then
        if (v_element #>> '{}') ~ '[<>]' then
          return false;
        end if;
      elsif jsonb_typeof(v_element) in ('object', 'array') then
        if not app.validate_config_value(v_element, p_depth + 1) then
          return false;
        end if;
      elsif jsonb_typeof(v_element) not in ('number', 'boolean', 'null') then
        return false;
      end if;
    end loop;
    return true;
  elsif jsonb_typeof(p_value) = 'string' then
    return (p_value #>> '{}') !~ '[<>]';
  else
    return true;
  end if;
end;
$$;

comment on function app.validate_config_value is
  'PLT-121: recursive structural/injection safety (depth<=5, <=8KB per object, <=50 array elements, no angle brackets in any string) -- data safety only, never an executable-code check beyond "this cannot be a script/markup payload." See this migration''s own header for the deliberately-deferred bounded rule evaluator.';

-- CONFIG_SET: a scoped configuration namespace -- one row per (config_type, tenant,
-- scope_level, scope_id) combination. scope_id is polymorphic (org_units.id for
-- company/branch, roles.id for role, auth.users.id for user) -- validated at the
-- application layer, not a physical FK (this migration's own header).
create table app.config_objects (
  id uuid primary key default gen_random_uuid(),
  config_type_code text not null references app.config_types (code),
  tenant_id uuid references app.tenants (id),
  scope_level text not null,
  scope_id uuid,
  created_by text,
  created_at timestamptz not null default now(),
  constraint config_objects_scope_level_check check (scope_level in ('global', 'tenant', 'company', 'branch', 'role', 'user')),
  constraint config_objects_scope_shape_check check (
    (scope_level = 'global' and tenant_id is null and scope_id is null) or
    (scope_level = 'tenant' and tenant_id is not null and scope_id is null) or
    (scope_level in ('company', 'branch', 'role', 'user') and tenant_id is not null and scope_id is not null)
  )
);

comment on table app.config_objects is
  'PLT-121: CONFIG_SET (Tech Arch §13.2) -- a scoped configuration namespace. The scope_shape_check CHECK constraint enforces Tech Arch §13.4''s 6-level precedence shape structurally: global carries neither tenant_id nor scope_id, tenant carries only tenant_id, company/branch/role/user require both.';

create unique index config_objects_scope_unique on app.config_objects (
  config_type_code, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
  scope_level, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)
);
create index config_objects_tenant_id_idx on app.config_objects (tenant_id);

-- CONFIG_VERSION: draft/published/archived, mirroring PLT-111/117/119 exactly.
create table app.config_versions (
  id uuid primary key default gen_random_uuid(),
  config_object_id uuid not null references app.config_objects (id),
  version_number integer not null,
  status text not null default 'draft',
  effective_from timestamptz,
  effective_to timestamptz,
  cloned_from_version_id uuid references app.config_versions (id),
  rollback_of_version_id uuid references app.config_versions (id),
  created_by text,
  published_by text,
  published_at timestamptz,
  archived_at timestamptz,
  archived_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint config_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint config_versions_object_version_unique unique (config_object_id, version_number)
);

create index config_versions_object_id_idx on app.config_versions (config_object_id);
create unique index config_versions_single_draft_per_object
  on app.config_versions (config_object_id) where status = 'draft';
create unique index config_versions_single_published_per_object
  on app.config_versions (config_object_id) where status = 'published';

create function app.touch_config_version_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger config_versions_touch_row
  before update on app.config_versions
  for each row
  execute function app.touch_config_version_row();

-- CONFIG_ITEM: the actual key/value settings within one version. canonical_ref
-- optionally ties back to PLT-119's app.canonical_terms (reused, not re-invented).
create table app.config_items (
  id uuid primary key default gen_random_uuid(),
  config_version_id uuid not null references app.config_versions (id),
  key text not null,
  value jsonb not null default '{}'::jsonb,
  canonical_ref text references app.canonical_terms (code),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint config_items_version_key_unique unique (config_version_id, key),
  constraint config_items_value_check check (app.validate_config_value(value))
);

comment on table app.config_items is
  'PLT-121: CONFIG_ITEM (Tech Arch §13.2). canonical_ref, when set, references PLT-119''s app.canonical_terms -- Tech Arch §13.4''s "canonical semantics versus tenant labels" rule made concrete: a config item may relabel a canonical term''s presentation, but the canonical code itself (and therefore its meaning to reporting/finance/audit) never moves.';

create index config_items_version_id_idx on app.config_items (config_version_id);

-- CONFIG_DEPENDENCY: cross-item dependency graph, cycle-checked at publish (§8).
create table app.config_dependencies (
  config_item_id uuid not null references app.config_items (id),
  depends_on_config_item_id uuid not null references app.config_items (id),
  created_at timestamptz not null default now(),
  primary key (config_item_id, depends_on_config_item_id),
  constraint config_dependencies_no_self_reference check (config_item_id <> depends_on_config_item_id)
);

comment on table app.config_dependencies is
  'PLT-121: CONFIG_DEPENDENCY (Tech Arch §13.2/§8). app.detect_config_dependency_cycle() walks this graph at publish time -- "no circular workflow dependency" (§8), extended to every config_type per 07_CONFIGURATION_ENGINE_WORKSTREAM.md §7.3.';

-- Recursive cycle detection, bounded (depth<=20, matching PLT-120's
-- app.resolve_master_record() merge-chain bound for the same "never loop forever on
-- malformed/adversarial data" reason). Returns true if a cycle reachable from
-- p_start_item_id exists.
create function app.detect_config_dependency_cycle(p_start_item_id uuid)
returns boolean
language sql
stable
as $$
  with recursive walk(item_id, depth, visited) as (
    select d.depends_on_config_item_id, 1, array[p_start_item_id, d.depends_on_config_item_id]
    from app.config_dependencies d
    where d.config_item_id = p_start_item_id
    union all
    select d.depends_on_config_item_id, w.depth + 1, w.visited || d.depends_on_config_item_id
    from app.config_dependencies d
    join walk w on d.config_item_id = w.item_id
    where w.depth < 20 and not (d.depends_on_config_item_id = any (w.visited))
  )
  select exists (
    select 1 from app.config_dependencies d
    join walk w on d.config_item_id = w.item_id
    where d.depends_on_config_item_id = p_start_item_id
  );
$$;

-- Authority (§26): "Supreme definitions/defaults; Tenant Admin allowed tenant values" --
-- scope_level='global' is Supreme-only; every other scope level requires
-- app.is_support_grant_authority() for the object's tenant_id (PLT-115's authority
-- check, reused verbatim across PLT-117/118/119/120 and here).
create function app.check_config_object_authority(p_scope_level text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select case
    when p_scope_level = 'global' then app.is_supreme_admin(p_actor_auth_user_id)
    else app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id)
  end;
$$;

-- Idempotent: auto-creates the config_object if it does not exist yet, then the draft
-- version if none is already pending -- mirrors PLT-117/119's app.create_*_draft
-- idempotency exactly, extended one level (object auto-vivification) since this
-- capability introduces a container above the version for the first time.
create function app.create_config_draft(
  p_config_type_code text,
  p_tenant_id uuid,
  p_scope_level text,
  p_scope_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.config_versions
language plpgsql
as $$
declare
  v_object app.config_objects;
  v_existing_draft app.config_versions;
  v_next_version integer;
  v_version app.config_versions;
begin
  if not app.check_config_object_authority(p_scope_level, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority for scope % of tenant %', p_actor_auth_user_id, p_scope_level, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_object
  from app.config_objects
  where config_type_code = p_config_type_code
    and tenant_id is not distinct from p_tenant_id
    and scope_level = p_scope_level
    and scope_id is not distinct from p_scope_id;

  if not found then
    begin
      insert into app.config_objects (config_type_code, tenant_id, scope_level, scope_id, created_by)
      values (p_config_type_code, p_tenant_id, p_scope_level, p_scope_id, p_created_by)
      returning * into v_object;
    exception
      when unique_violation then
        -- A concurrent call auto-vivified the same object first -- re-select rather
        -- than raise, the same idempotent-under-concurrency guarantee every other
        -- create_*_draft function in this repository provides for its own row.
        select * into v_object
        from app.config_objects
        where config_type_code = p_config_type_code
          and tenant_id is not distinct from p_tenant_id
          and scope_level = p_scope_level
          and scope_id is not distinct from p_scope_id;
    end;
  end if;

  select * into v_existing_draft from app.config_versions where config_object_id = v_object.id and status = 'draft';
  if found then
    return v_existing_draft;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.config_versions where config_object_id = v_object.id;

  insert into app.config_versions (config_object_id, version_number, created_by)
  values (v_object.id, v_next_version, p_created_by)
  returning * into v_version;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_config_draft',
    'app.config_versions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$$;

-- Bulk-replaces a draft's item set (the same "delete then insert the new set" pattern
-- PLT-117's app.set_tenant_brand_tokens uses for document_template_refs). p_items is a
-- jsonb array of {"key": text, "value": jsonb, "canonical_ref": text|null}.
create function app.set_config_items(
  p_version_id uuid,
  p_items jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns integer
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_item jsonb;
  v_count integer;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.check_config_object_authority(v_object.scope_level, v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority for scope % of tenant %', p_actor_auth_user_id, v_object.scope_level, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'config_version_not_draft: version % is %, only a draft''s items may be changed', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  delete from app.config_items where config_version_id = p_version_id;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    insert into app.config_items (config_version_id, key, value, canonical_ref)
    values (p_version_id, v_item ->> 'key', coalesce(v_item -> 'value', '{}'::jsonb), v_item ->> 'canonical_ref');
  end loop;

  select count(*) into v_count from app.config_items where config_version_id = p_version_id;

  perform app.capture_audit_event(
    v_object.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_config_items',
    'app.config_versions', p_version_id, 'success', null, null, jsonb_build_object('item_count', v_count)
  );

  return v_count;
end;
$$;

-- Publish gate: dependency-cycle validation (§8/§23: "cycle... blocks publish") runs
-- for every item in this version before any status change is committed.
create function app.publish_config_version(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_prior_published app.config_versions;
  v_updated app.config_versions;
  v_item_id uuid;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.check_config_object_authority(v_object.scope_level, v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority for scope % of tenant %', p_actor_auth_user_id, v_object.scope_level, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'config_version_not_draft: version % is %, only a draft may be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  for v_item_id in select id from app.config_items where config_version_id = p_version_id loop
    if app.detect_config_dependency_cycle(v_item_id) then
      raise exception 'circular_config_dependency: a dependency cycle was detected starting from config_item %', v_item_id
        using errcode = 'check_violation';
    end if;
  end loop;

  select * into v_prior_published from app.config_versions where config_object_id = v_version.config_object_id and status = 'published';
  if found then
    update app.config_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by a newer published version'
    where id = v_prior_published.id;
  end if;

  update app.config_versions
  set status = 'published', published_by = p_actor_label, published_at = now(), effective_from = coalesce(p_effective_from, now())
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_object.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_config_version',
    'app.config_versions', v_updated.id, 'success', null, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.discard_config_draft(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_updated app.config_versions;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  select * into v_object from app.config_objects where id = v_version.config_object_id;

  if not app.check_config_object_authority(v_object.scope_level, v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority for scope % of tenant %', p_actor_auth_user_id, v_object.scope_level, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'config_version_not_draft: version % is %, only a draft may be discarded', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.config_versions
  set status = 'archived', archived_at = now(), archived_reason = coalesce(p_reason, 'discarded')
  where id = p_version_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_object.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_config_draft',
    'app.config_versions', v_updated.id, 'success', p_reason, to_jsonb(v_version), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Rollback -- clones the target version's item set into a brand-new version and
-- publishes it immediately, never mutating the target (PLT-117/119's exact discipline,
-- extended one level to also clone the child config_items rows).
create function app.rollback_config_version(
  p_target_version_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
declare
  v_target app.config_versions;
  v_object app.config_objects;
  v_next_version integer;
  v_new_version app.config_versions;
  v_prior_published app.config_versions;
  v_published app.config_versions;
begin
  select * into v_target from app.config_versions where id = p_target_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_target_version_id
      using errcode = 'no_data_found';
  end if;

  if v_target.status = 'draft' then
    raise exception 'cannot_rollback_draft: version % is still a draft, nothing stable to roll back to', p_target_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_object from app.config_objects where id = v_target.config_object_id;

  if not app.check_config_object_authority(v_object.scope_level, v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority for scope % of tenant %', p_actor_auth_user_id, v_object.scope_level, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.config_versions where config_object_id = v_target.config_object_id;

  insert into app.config_versions (config_object_id, version_number, cloned_from_version_id, rollback_of_version_id, created_by)
  values (v_target.config_object_id, v_next_version, p_target_version_id, p_target_version_id, p_actor_label)
  returning * into v_new_version;

  insert into app.config_items (config_version_id, key, value, canonical_ref)
  select v_new_version.id, key, value, canonical_ref from app.config_items where config_version_id = p_target_version_id;

  select * into v_prior_published from app.config_versions where config_object_id = v_target.config_object_id and status = 'published';
  if found then
    update app.config_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by rollback to version ' || v_target.version_number
    where id = v_prior_published.id;
  end if;

  update app.config_versions
  set status = 'published', published_by = p_actor_label, published_at = now(), effective_from = now()
  where id = v_new_version.id
  returning * into v_published;

  perform app.capture_audit_event(
    v_object.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_config_version',
    'app.config_versions', v_published.id, 'success', p_reason, to_jsonb(v_target), to_jsonb(v_published)
  );

  return v_published;
end;
$$;

-- The 6-level precedence resolver (Tech Arch §13.4, verbatim): walks user -> role ->
-- branch -> company -> tenant -> global, returning the first level with a currently-
-- effective published version -- the most specific override always wins, deterministic
-- (§6: "No two transactions... may resolve to different versions"). SECURITY DEFINER
-- because app.config_versions/app.config_items carry no direct authenticated grant at
-- all (draft content should never be casually browsable, this migration's own header)
-- -- the caller-supplied tenant_id/scope parameters are the real security boundary for
-- this specific call path, the same "resolver bypasses RLS internally, its own
-- parameters are the boundary" pattern PLT-117/118/119's evaluators already established
-- (a deliberate departure from PLT-113's default-deny grant posture, not an oversight).
create function app.resolve_config(
  p_config_type_code text,
  p_tenant_id uuid,
  p_company_id uuid default null,
  p_branch_id uuid default null,
  p_role_id uuid default null,
  p_user_id uuid default null
)
returns table (
  config_type_code text,
  resolved_scope_level text,
  resolved_version_id uuid,
  effective_from timestamptz,
  items jsonb
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_object app.config_objects;
  v_version app.config_versions;
  v_scope_level text;
  v_scope_id uuid;
  v_levels text[] := array['user', 'role', 'branch', 'company', 'tenant', 'global'];
  v_ids uuid[] := array[p_user_id, p_role_id, p_branch_id, p_company_id, null, null];
  i integer;
begin
  for i in 1 .. array_length(v_levels, 1) loop
    v_scope_level := v_levels[i];
    v_scope_id := v_ids[i];

    if v_scope_level in ('company', 'branch', 'role', 'user') and v_scope_id is null then
      continue;
    end if;

    select * into v_object
    from app.config_objects o
    where o.config_type_code = p_config_type_code
      and o.scope_level = v_scope_level
      and o.tenant_id is not distinct from (case when v_scope_level = 'global' then null else p_tenant_id end)
      and o.scope_id is not distinct from v_scope_id;

    if found then
      select * into v_version
      from app.config_versions v
      where v.config_object_id = v_object.id
        and v.status = 'published'
        and v.effective_from <= now()
        and (v.effective_to is null or v.effective_to > now());

      if found then
        return query
          select
            p_config_type_code,
            v_scope_level,
            v_version.id,
            v_version.effective_from,
            coalesce((select jsonb_object_agg(ci.key, ci.value) from app.config_items ci where ci.config_version_id = v_version.id), '{}'::jsonb);
        return;
      end if;
    end if;
  end loop;

  return;
end;
$$;

comment on function app.resolve_config is
  'PLT-121: the 6-level precedence resolver (Tech Arch §13.4). Returns zero rows if no level -- not even global -- has a currently-effective published version, matching Prompt 121 §22''s "inherited override resolves by documented precedence" without a mandatory hard-coded platform default (unlike PLT-117/118/119''s evaluators, which always fall back to a concrete default value -- configuration content itself has no universal, honest default this early, only the mechanism does).';

-- EXC-CFG-001 (Blueprint §13, "stale configuration version") made concrete: a caller
-- re-checks its previously-resolved version_id against the live resolution at submit
-- time, per 07_CONFIGURATION_ENGINE_WORKSTREAM.md §7.4 -- "the server re-resolves
-- precedence at submit time... rejects... on mismatch." No real submission surface
-- exists yet to wire this into (no business-domain transaction table exists yet) --
-- disclosed NOT_RUN wiring; the mechanism itself is real and directly testable today.
create function app.verify_config_version_current(
  p_config_type_code text,
  p_tenant_id uuid,
  p_expected_version_id uuid,
  p_company_id uuid default null,
  p_branch_id uuid default null,
  p_role_id uuid default null,
  p_user_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_current record;
begin
  select * into v_current from app.resolve_config(p_config_type_code, p_tenant_id, p_company_id, p_branch_id, p_role_id, p_user_id);
  if not found then
    return p_expected_version_id is null;
  end if;
  return v_current.resolved_version_id = p_expected_version_id;
end;
$$;

comment on function app.verify_config_version_current is
  'PLT-121: EXC-CFG-001''s real mechanism -- returns false the instant a resolution no longer matches what a caller resolved earlier (a publish/rollback happened in between), the concrete "stale configuration version" rejection check.';

-- Admin view-model read path (§15).
create function app.list_config_versions(
  p_config_type_code text,
  p_tenant_id uuid,
  p_scope_level text,
  p_scope_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.config_versions
language plpgsql
stable
as $$
declare
  v_object app.config_objects;
begin
  if not app.check_config_object_authority(p_scope_level, p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority for scope % of tenant %', p_actor_auth_user_id, p_scope_level, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_object
  from app.config_objects o
  where o.config_type_code = p_config_type_code
    and o.tenant_id is not distinct from p_tenant_id
    and o.scope_level = p_scope_level
    and o.scope_id is not distinct from p_scope_id;

  if not found then
    return;
  end if;

  return query select * from app.config_versions where config_object_id = v_object.id order by version_number desc;
end;
$$;

alter table app.config_types enable row level security;
alter table app.config_objects enable row level security;
alter table app.config_versions enable row level security;
alter table app.config_items enable row level security;
alter table app.config_dependencies enable row level security;

-- app.config_types is platform-owned reference data -- safe to expose broadly.
create policy config_types_select_authenticated on app.config_types
  for select to authenticated
  using (true);

-- app.config_objects: a tenant sees its own tenant-scoped/company/branch/role/user
-- objects plus every global object; Supreme Admin sees everything -- the same
-- global-visibility RLS branch PLT-120's app.master_records introduced.
create policy config_objects_select_scoped on app.config_objects
  for select to authenticated
  using (tenant_id is null or app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- app.config_versions/app.config_items/app.config_dependencies are deliberately NOT
-- given a direct authenticated grant -- only the resolver/list functions above expose
-- them, since draft content (unlike a published master-data record) should never be
-- casually browsable mid-edit. RLS is still enabled (defense in depth matching every
-- other table's posture), but with no policy at all for authenticated -- service_role
-- only, the same posture PLT-117''s app.tenant_brand_versions established.

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.config_types to authenticated, service_role;
grant select on app.config_objects to authenticated, service_role;
grant select, insert, update, delete on app.config_types to service_role;
grant insert, update, delete on app.config_objects to service_role;
grant select, insert, update, delete on app.config_versions to service_role;
grant select, insert, update, delete on app.config_items to service_role;
grant select, insert, update, delete on app.config_dependencies to service_role;
grant execute on function app.validate_config_value(jsonb, integer) to service_role;
grant execute on function app.detect_config_dependency_cycle(uuid) to service_role;
grant execute on function app.check_config_object_authority(text, uuid, uuid) to service_role;
grant execute on function app.register_config_type(text, text, text, uuid, text) to service_role;
grant execute on function app.create_config_draft(text, uuid, text, uuid, uuid, text) to service_role;
grant execute on function app.set_config_items(uuid, jsonb, uuid, text) to service_role;
grant execute on function app.publish_config_version(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.discard_config_draft(uuid, uuid, text, text) to service_role;
grant execute on function app.rollback_config_version(uuid, uuid, text, text) to service_role;
grant execute on function app.list_config_versions(text, uuid, text, uuid, uuid) to service_role;
-- Read-only resolution: SECURITY DEFINER (see the function's own comment), granted only
-- to authenticated -- unlike PLT-117/118/119's anon-granted evaluators, config
-- resolution has no pre-authentication use case, so anon is deliberately excluded here.
grant execute on function app.resolve_config(text, uuid, uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.verify_config_version_current(text, uuid, uuid, uuid, uuid, uuid, uuid) to authenticated, service_role;
