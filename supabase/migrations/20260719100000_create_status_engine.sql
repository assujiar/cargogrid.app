-- Platform Core capability PLT-124 (Status Engine, CG-S6-PLT-021)
-- Canonical status registry with versioned tenant presentation layered on top of
-- workflow transitions (Prompt 124 §4). "Workflow/authorization controls transitions;
-- status engine describes/resolves" (Prompt 124 §24) -- this capability never decides
-- whether a transition is legal (that is `PLT-122`'s `app.transition_workflow_instance()`
-- / a future domain's own transition authority); it only registers what a status
-- *means* (permanently) and how it is *labeled* (tenant-configurable, versioned).
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **Zero real domain status sets are seeded in this migration.**
--   `docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md` §7.2 catalogues the real,
--   sourced 24 status transitions across 6 domain entities (Lead/Quotation/Shipment/
--   Invoice/Vendor/Ticket) -- but its own §13 Module Adoption Map and §15 Atomic
--   Backlog place every one of those at Phase 2 (Commercial: Lead/Quotation), Phase 3
--   (Operations: Shipment), Phase 4 (Finance: Invoice), Phase 6 (Procurement: Vendor),
--   or Phase 7 (HRIS/Ticketing: Ticket) -- verbatim: "Workflow/Status/Numbering/Form
--   engines | 1 | Bootstrap all 4 as empty templates." This migration is exactly that
--   bootstrap: the registry/presentation/legacy-mapping *mechanism*, with no status_set
--   row of any kind inserted. The one safe representative example this checkpoint uses
--   (Quotation's real, sourced 6-state/5-transition shape) is built and proven entirely
--   inside `scripts/db-tests/status.sql` -- no such row exists anywhere in this
--   migration itself, and activating it against a real `quotations` table is explicitly
--   Phase 2 Commercial config adoption scope, not built here.
-- * **Canonical status meaning is permanent; presentation is the only tenant-
--   configurable surface** (§24: "Canonical status meaning never changes with label/
--   color" -- `07_*.md` §6's "canonical semantics versus tenant labels" rule, the
--   config-engine-side counterpart of `05_DATABASE_SCHEMA_WORKSTREAM.md` §2's
--   `status_code`/`canonical_status` dual-column pattern). `app.canonical_statuses` rows
--   are registered once (Supreme-only, idempotent) and never mutated in place; only a
--   tenant's own presentation (label/color/icon) is ever versioned/republished.
-- * **Presentation reuses `PLT-121`'s Configuration Engine directly, once per status
--   set.** A single generic `config_type_code='status'` (seeded empty/template-only by
--   `PLT-121` itself) cannot host more than one tenant-scoped presentation object at a
--   time (`config_objects_scope_shape_check` forces `scope_id` to be null at
--   `scope_level='tenant'`, so only one object could ever exist per tenant for a single
--   shared type) -- multiple status sets (Quotation, Shipment, Invoice, ...) need
--   independent versioning at the same scope level. `app.register_status_set()`
--   resolves this the same "registry, not enum" way `PLT-120`'s
--   `app.register_master_type()`/`PLT-122`'s hook allowlist already did: it calls
--   `PLT-121`'s own `app.register_config_type('status:' || code, ...)` to mint a
--   dedicated, independently-versionable presentation type per status set, composing
--   the existing extensibility mechanism rather than forking a parallel one. The
--   originally-seeded generic `'status'` type itself stays exactly what `PLT-121`
--   disclosed it to be -- an empty, unused template placeholder.
-- * **Accessible non-color cues are structurally required, not optional** (Prompt 124
--   §15: "accessible non-color cues"). `app.validate_status_presentation()` rejects a
--   status label entry with no `icon` value at publish time (`status_missing_
--   accessible_cue`) -- a tenant cannot ship a color-only status distinction.
-- * **Legacy mapping has no silent collision** (§25). `app.status_legacy_mappings`
--   carries a real `unique(status_set_code, legacy_value)` constraint; re-registering
--   the same mapping is idempotent, but mapping an already-mapped legacy value to a
--   *different* canonical status raises `status_legacy_mapping_collision` rather than
--   silently overwriting the prior mapping.
-- * **No configuration item here can grant a transition or hide a prohibited state**
--   (§16). `app.resolve_status_presentation()` always resolves a real, existing
--   canonical status (or fails with `status_unknown_code`) -- there is no code path
--   that lets a tenant's presentation config suppress or rename-away a canonical
--   status's existence; only its label/color/icon are ever tenant-configurable.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

create table app.status_sets (
  code text primary key,
  name text not null,
  owner_primitive_code text not null,
  registered_by text,
  created_at timestamptz not null default now()
);

comment on table app.status_sets is
  'PLT-124: the registry of canonical status *sets* (one per domain entity lifecycle, e.g. quotation_status, shipment_status). Registering a set also mints its own dedicated app.config_types row (code ''status:<code>'') via app.register_config_type() -- this migration''s own header explains why one shared generic type cannot host every set''s independent tenant presentation.';

create table app.canonical_statuses (
  id uuid primary key default gen_random_uuid(),
  status_set_code text not null references app.status_sets (code),
  code text not null,
  category text not null,
  sort_order integer not null default 0,
  registered_by text,
  created_at timestamptz not null default now(),
  is_terminal boolean generated always as (category = 'terminal') stored,
  constraint canonical_statuses_category_check check (category in ('initial', 'active', 'terminal')),
  constraint canonical_statuses_set_code_unique unique (status_set_code, code)
);

comment on table app.canonical_statuses is
  'PLT-124: a permanent, stable machine ID within a status set (Prompt 124 §24: "canonical status meaning never changes"). Never mutated in place once registered -- only app.status_legacy_mappings and tenant presentation (config_items on the matching status:<code> config_type) ever change.';

create index canonical_statuses_status_set_code_idx on app.canonical_statuses (status_set_code, sort_order);

create table app.status_legacy_mappings (
  id uuid primary key default gen_random_uuid(),
  status_set_code text not null references app.status_sets (code),
  legacy_value text not null,
  canonical_status_id uuid not null references app.canonical_statuses (id),
  registered_by text,
  created_at timestamptz not null default now(),
  constraint status_legacy_mappings_set_value_unique unique (status_set_code, legacy_value)
);

comment on table app.status_legacy_mappings is
  'PLT-124: legacy/external status value -> canonical status_id, for import/migration compatibility (Prompt 124 §19). unique(status_set_code, legacy_value) is the real "no silent collision" guarantee (§25) -- a legacy value maps to exactly one canonical status per set, structurally.';

create index status_legacy_mappings_status_set_code_idx on app.status_legacy_mappings (status_set_code);

-- Idempotent (returns the existing row on a repeated call) -- Supreme-Admin-only, the
-- same registry-not-enum authority pattern PLT-120/122's own allowlist registries use.
create function app.register_status_set(
  p_code text,
  p_name text,
  p_owner_primitive_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.status_sets
language plpgsql
as $$
declare
  v_existing app.status_sets;
  v_set app.status_sets;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a status set'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.status_sets where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.status_sets (code, name, owner_primitive_code, registered_by)
  values (p_code, p_name, p_owner_primitive_code, p_registered_by)
  returning * into v_set;

  perform app.register_config_type('status:' || p_code, p_name || ' Presentation', p_owner_primitive_code, p_actor_auth_user_id, p_registered_by);

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_status_set',
    'app.status_sets', null, 'success', null, null, to_jsonb(v_set)
  );

  return v_set;
end;
$$;

create function app.register_canonical_status(
  p_status_set_code text,
  p_code text,
  p_category text,
  p_sort_order integer,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.canonical_statuses
language plpgsql
as $$
declare
  v_existing app.canonical_statuses;
  v_status app.canonical_statuses;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a canonical status'
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from app.status_sets where code = p_status_set_code) then
    raise exception 'status_set_not_found: no status set %', p_status_set_code
      using errcode = 'no_data_found';
  end if;
  if p_category not in ('initial', 'active', 'terminal') then
    raise exception 'status_invalid_category: category % is not one of initial/active/terminal', p_category
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.canonical_statuses where status_set_code = p_status_set_code and code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.canonical_statuses (status_set_code, code, category, sort_order, registered_by)
  values (p_status_set_code, p_code, p_category, coalesce(p_sort_order, 0), p_registered_by)
  returning * into v_status;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_canonical_status',
    'app.canonical_statuses', v_status.id, 'success', null, null, to_jsonb(v_status)
  );

  return v_status;
end;
$$;

-- Idempotent for an identical repeat; raises status_legacy_mapping_collision (never
-- silently overwrites) if the legacy_value is already mapped to a *different* canonical
-- status (Prompt 124 §25: "legacy mapping has no silent collision").
create function app.register_status_legacy_mapping(
  p_status_set_code text,
  p_legacy_value text,
  p_canonical_status_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.status_legacy_mappings
language plpgsql
as $$
declare
  v_canonical app.canonical_statuses;
  v_existing app.status_legacy_mappings;
  v_mapping app.status_legacy_mappings;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a status legacy mapping'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_canonical from app.canonical_statuses where status_set_code = p_status_set_code and code = p_canonical_status_code;
  if not found then
    raise exception 'status_unknown_code: % is not a registered canonical status in set %', p_canonical_status_code, p_status_set_code
      using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.status_legacy_mappings where status_set_code = p_status_set_code and legacy_value = p_legacy_value;
  if found then
    if v_existing.canonical_status_id <> v_canonical.id then
      raise exception 'status_legacy_mapping_collision: legacy value % in set % is already mapped to a different canonical status', p_legacy_value, p_status_set_code
        using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  insert into app.status_legacy_mappings (status_set_code, legacy_value, canonical_status_id, registered_by)
  values (p_status_set_code, p_legacy_value, v_canonical.id, p_registered_by)
  returning * into v_mapping;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_status_legacy_mapping',
    'app.status_legacy_mappings', v_mapping.id, 'success', null, null, to_jsonb(v_mapping)
  );

  return v_mapping;
end;
$$;

create function app.resolve_legacy_status(p_status_set_code text, p_legacy_value text)
returns app.canonical_statuses
language plpgsql
stable
as $$
declare
  v_status app.canonical_statuses;
begin
  select cs.* into v_status
  from app.status_legacy_mappings m
  join app.canonical_statuses cs on cs.id = m.canonical_status_id
  where m.status_set_code = p_status_set_code and m.legacy_value = p_legacy_value;

  if not found then
    raise exception 'status_legacy_value_unmapped: no mapping for legacy value % in set %', p_legacy_value, p_status_set_code
      using errcode = 'no_data_found';
  end if;

  return v_status;
end;
$$;

create function app.get_status_set_registry(p_status_set_code text)
returns setof app.canonical_statuses
language sql
stable
as $$
  select * from app.canonical_statuses where status_set_code = p_status_set_code order by sort_order;
$$;

-- Publish-time structural gate over a 'status:<code>'-typed config_version's own
-- config_items (Prompt 124 §20 task 2/4). Expects exactly one item, 'labels' -- a jsonb
-- object keyed by canonical status code, each value {label, icon, color?}.
create function app.validate_status_presentation(p_version_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_config_type_code text;
  v_status_set_code text;
  v_labels jsonb;
  v_code text;
  v_entry jsonb;
begin
  select o.config_type_code into v_config_type_code
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where v.id = p_version_id;

  if v_config_type_code is null or left(v_config_type_code, 7) <> 'status:' then
    raise exception 'status_not_a_presentation_version: version % does not belong to a status:<code> config object', p_version_id
      using errcode = 'check_violation';
  end if;
  v_status_set_code := substr(v_config_type_code, 8);

  select value into v_labels from app.config_items where config_version_id = p_version_id and key = 'labels';
  if v_labels is null or jsonb_typeof(v_labels) <> 'object' then
    raise exception 'status_missing_labels: version % has no ''labels'' item, or it is not an object', p_version_id
      using errcode = 'check_violation';
  end if;

  for v_code, v_entry in select * from jsonb_each(v_labels) loop
    if not exists (select 1 from app.canonical_statuses where status_set_code = v_status_set_code and code = v_code) then
      raise exception 'status_unknown_code: % is not a registered canonical status in set %', v_code, v_status_set_code
        using errcode = 'check_violation';
    end if;
    if coalesce(v_entry ->> 'label', '') = '' then
      raise exception 'status_missing_label: entry for % has no non-empty label', v_code
        using errcode = 'check_violation';
    end if;
    if coalesce(v_entry ->> 'icon', '') = '' then
      raise exception 'status_missing_accessible_cue: entry for % has no non-empty icon (Prompt 124 §15: color alone is not an accessible cue)', v_code
        using errcode = 'check_violation';
    end if;
    if (v_entry ->> 'color') is not null and (v_entry ->> 'color') !~ '^#[0-9a-fA-F]{6}$' then
      raise exception 'status_invalid_color: entry for % has a color that is not a #rrggbb hex value', v_code
        using errcode = 'check_violation';
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_status_presentation is
  'PLT-124: the publish-time structural gate -- every labeled code must be a real registered canonical status in the matching set, every entry needs a non-empty label AND a non-empty icon (the required accessible non-color cue), and any color present must be a real #rrggbb hex value.';

create function app.publish_status_presentation(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
begin
  perform app.validate_status_presentation(p_version_id);
  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

-- The real resolve API (Prompt 124 §14/§21/§22): composes PLT-121's own
-- app.resolve_config() 6-level precedence walk against the status set's own dedicated
-- config_type, then falls back to a structural, code-derived (never fabricated or
-- tenant-specific) presentation when nothing has published yet or this specific code
-- was never labeled -- "falls back safely" (§22), never raises for a real canonical
-- code. Raises status_unknown_code only if the code itself was never registered at all.
create function app.resolve_status_presentation(
  p_status_set_code text,
  p_canonical_status_code text,
  p_tenant_id uuid,
  p_company_id uuid default null,
  p_branch_id uuid default null,
  p_role_id uuid default null,
  p_user_id uuid default null
)
returns table (
  canonical_status_code text,
  category text,
  is_terminal boolean,
  resolved_label text,
  resolved_color text,
  resolved_icon text,
  is_fallback boolean,
  resolved_version_id uuid
)
language plpgsql
stable
as $$
declare
  v_canonical app.canonical_statuses;
  v_resolved record;
  v_entry jsonb;
begin
  select * into v_canonical from app.canonical_statuses where status_set_code = p_status_set_code and code = p_canonical_status_code;
  if not found then
    raise exception 'status_unknown_code: % is not a registered canonical status in set %', p_canonical_status_code, p_status_set_code
      using errcode = 'no_data_found';
  end if;

  select * into v_resolved from app.resolve_config('status:' || p_status_set_code, p_tenant_id, p_company_id, p_branch_id, p_role_id, p_user_id);

  if found then
    v_entry := v_resolved.items -> 'labels' -> p_canonical_status_code;
  end if;

  if v_entry is not null then
    return query select
      v_canonical.code, v_canonical.category, v_canonical.is_terminal,
      v_entry ->> 'label', v_entry ->> 'color', v_entry ->> 'icon',
      false, v_resolved.resolved_version_id;
  else
    return query select
      v_canonical.code, v_canonical.category, v_canonical.is_terminal,
      initcap(replace(v_canonical.code, '_', ' ')), null::text, 'circle',
      true, null::uuid;
  end if;
end;
$$;

comment on function app.resolve_status_presentation is
  'PLT-124: real 6-level precedence resolution (composing PLT-121''s app.resolve_config() against this status set''s own status:<code> config type), falling back to a structural, code-derived label/neutral icon (never a fabricated tenant-specific color) when nothing has published yet -- Prompt 124 §22''s "falls back safely."';

alter table app.status_sets enable row level security;
alter table app.canonical_statuses enable row level security;
alter table app.status_legacy_mappings enable row level security;

-- All three are platform-owned reference data -- safe to expose broadly, the same
-- posture PLT-122's app.workflow_hooks already established.
create policy status_sets_select_authenticated on app.status_sets
  for select to authenticated
  using (true);
create policy canonical_statuses_select_authenticated on app.canonical_statuses
  for select to authenticated
  using (true);
create policy status_legacy_mappings_select_authenticated on app.status_legacy_mappings
  for select to authenticated
  using (true);

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.status_sets to authenticated, service_role;
grant insert, update, delete on app.status_sets to service_role;
grant select on app.canonical_statuses to authenticated, service_role;
grant insert, update, delete on app.canonical_statuses to service_role;
grant select on app.status_legacy_mappings to authenticated, service_role;
grant insert, update, delete on app.status_legacy_mappings to service_role;

grant execute on function app.register_status_set(text, text, text, uuid, text) to service_role;
grant execute on function app.register_canonical_status(text, text, text, integer, uuid, text) to service_role;
grant execute on function app.register_status_legacy_mapping(text, text, text, uuid, text) to service_role;
grant execute on function app.resolve_legacy_status(text, text) to authenticated, service_role;
grant execute on function app.get_status_set_registry(text) to authenticated, service_role;
grant execute on function app.validate_status_presentation(uuid) to service_role;
grant execute on function app.publish_status_presentation(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.resolve_status_presentation(text, text, uuid, uuid, uuid, uuid, uuid) to authenticated, service_role;
