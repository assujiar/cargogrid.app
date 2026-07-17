-- Platform Core capability PLT-120 (Master Data Foundation, CG-S6-PLT-017)
-- A reusable master-data registry (master "type" catalogue + generic master "record"
-- rows) with tenant/global scope, stable codes, aliases, versioning, dedupe-safe merge,
-- and cross-tenant-safe resolution -- the shared primitive every later business domain
-- (Commercial, Operations, Finance, Procurement, ...) registers its own master types
-- into, rather than each domain inventing its own registry pattern (Prompt 120 §4/§24).
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **Exactly one real, sourced initial master type is seeded: `vendor_rate`.**
--   `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md` §4 (verbatim): "`vendor_rates`
--   is owned by `PRC` (Procurement) from Phase 1's master-data foundation onward -- the
--   table is created in Phase 1's `MDM` slice (empty, no Procurement UI yet) with `PRC`
--   as the documented sole writer once Phase 6 ships" -- this resolves `ADR-CAND-ARCH-001`
--   (`01_MODULE_DEPENDENCY_MAP.md` §11) in favor of option (a): a shared Phase-1
--   master-data table, not two independently-writable vendor-rate masters. No sample
--   `master_records` row is seeded for it (§12, forbidden: "full domain masters beyond
--   approved initial set") -- only the *type definition* itself, matching the source
--   document's own "empty, no Procurement UI yet" framing. `app.v_active_vendor_rates`
--   is the exact convenience view that same section names.
-- * **`attributes` is a generic, type-agnostic jsonb bag**, not a hard-coded set of
--   vendor-rate-specific business columns (rate amount, service type, ...) -- no
--   Procurement domain schema exists yet to source real field names from honestly, and
--   inventing them now would be exactly the "full domain masters beyond approved
--   initial set" this prompt forbids (§12). `app.validate_master_attributes()` enforces
--   only structural/injection safety (an object, string leaf values only, no angle
--   brackets, a bounded size) -- real business-field validation is Phase 6's own
--   `PRC` capability's responsibility when it ships and extends this same row shape.
-- * **No dependency-check mechanism exists for deactivation** (Prompt 120 §20 task 3's
--   "dependency checks") beyond the merge-lineage guarantee itself -- no downstream
--   business-domain table references `app.master_records` yet (still Platform-Core-only,
--   greenfield), so there is nothing real to check yet; disclosed `NOT_RUN`, the same
--   "mechanism proven, live wiring deferred" posture `PLT-107` established for GoTrue.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

-- Recursive structural/injection-safety validator, reused directly from PLT-117's
-- app.redact_audit_payload()/app.validate_document_template_refs() discipline: an
-- object only, string leaf values only, no angle brackets, bounded size per string.
-- Applied to both app.master_records.attributes and .aliases (aliases coerced to a
-- one-element-per-entry object internally via the caller, see app.validate_master_aliases
-- below) -- never a table CHECK constraint alone for aliases, since aliases is an array,
-- not an object; a dedicated array-shaped validator follows.
create function app.validate_master_attributes(p_attributes jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_key text;
  v_value jsonb;
begin
  if p_attributes is null or jsonb_typeof(p_attributes) <> 'object' then
    return false;
  end if;
  if length(p_attributes::text) > 8192 then
    return false;
  end if;

  for v_key, v_value in select * from jsonb_each(p_attributes) loop
    if jsonb_typeof(v_value) = 'string' then
      if (v_value #>> '{}') ~ '[<>]' then
        return false;
      end if;
    elsif jsonb_typeof(v_value) not in ('number', 'boolean', 'null') then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_master_attributes is
  'PLT-120: structural/injection safety only (object, <=8KB, string values reject angle brackets, no nested object/array) -- real business-field semantics belong to whichever future domain capability actually defines a master_type''s attribute shape.';

create function app.validate_master_aliases(p_aliases jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_element jsonb;
begin
  if p_aliases is null or jsonb_typeof(p_aliases) <> 'array' then
    return false;
  end if;
  if jsonb_array_length(p_aliases) > 20 then
    return false;
  end if;

  for v_element in select * from jsonb_array_elements(p_aliases) loop
    if jsonb_typeof(v_element) <> 'string' then
      return false;
    end if;
    if length(v_element #>> '{}') = 0 or length(v_element #>> '{}') > 120 or (v_element #>> '{}') ~ '[<>]' then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_master_aliases is
  'PLT-120: aliases is a bounded (<=20), plain-text (<=120 chars, no angle brackets) array -- alternate lookup labels/codes for the one canonical record, never a second source of truth (Prompt 120 §24).';

-- The master "type" catalogue -- what kinds of master data exist, who owns them, and at
-- what scope. Registered once per type (by Supreme Admin only, §26), extended by future
-- domain capabilities as they ship their own master types.
create table app.master_types (
  code text primary key,
  name text not null,
  scope text not null,
  owner_module_code text references app.entitlement_modules (code),
  registered_by text,
  created_at timestamptz not null default now(),
  constraint master_types_scope_check check (scope in ('global', 'tenant'))
);

comment on table app.master_types is
  'PLT-120: the registry of master-data kinds (Prompt 120 §20 task 1). scope=''global'' means one shared catalogue across every tenant (Supreme-managed); scope=''tenant'' means each tenant maintains its own independent set of records under this type (Tenant Admin-managed, per tenant). owner_module_code ties a type to the business-domain module that will eventually own its real business semantics -- ''vendor_rate'' -> ''PRC'' (Procurement), sourced from 05_DATABASE_SCHEMA_WORKSTREAM.md §4/§11''s ADR-CAND-ARCH-001 resolution.';

insert into app.master_types (code, name, scope, owner_module_code, registered_by) values
  ('vendor_rate', 'Vendor Rate', 'tenant', 'PRC', 'platform-core-foundation');

create function app.register_master_type(
  p_code text,
  p_name text,
  p_scope text,
  p_owner_module_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.master_types
language plpgsql
as $$
declare
  v_existing app.master_types;
  v_type app.master_types;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a master type'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.master_types where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.master_types (code, name, scope, owner_module_code, registered_by)
  values (p_code, p_name, p_scope, p_owner_module_code, p_registered_by)
  returning * into v_type;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_master_type',
    'app.master_types', null, 'success', null, null, to_jsonb(v_type)
  );

  return v_type;
end;
$$;

comment on function app.register_master_type is
  'PLT-120: idempotent (a repeated call with an existing code returns that row, never raises), Supreme-Admin-only. Platform-wide event (tenant_id=null in the audit entry -- a master type is never tenant-scoped, only its records are).';

-- The generic master "record" -- one row per canonical entity instance, regardless of
-- which master_type it belongs to. tenant_id is null for a scope=''global'' type''s
-- records, and required for a scope=''tenant'' type''s records -- enforced by a trigger
-- (app.enforce_master_record_scope), not a CHECK constraint, since it requires a
-- cross-table lookup against app.master_types (not IMMUTABLE-safe).
create table app.master_records (
  id uuid primary key default gen_random_uuid(),
  master_type_code text not null references app.master_types (code),
  tenant_id uuid references app.tenants (id),
  code text not null,
  name text not null,
  aliases jsonb not null default '[]'::jsonb,
  attributes jsonb not null default '{}'::jsonb,
  canonical_status text not null default 'active',
  merged_into_id uuid references app.master_records (id),
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  created_by text,
  deactivated_at timestamptz,
  deactivated_by text,
  deactivated_reason text,
  merged_at timestamptz,
  merged_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint master_records_canonical_status_check check (canonical_status in ('active', 'deactivated', 'merged')),
  constraint master_records_aliases_check check (app.validate_master_aliases(aliases)),
  constraint master_records_attributes_check check (app.validate_master_attributes(attributes)),
  constraint master_records_merged_status_check check (
    (canonical_status = 'merged' and merged_into_id is not null) or
    (canonical_status <> 'merged' and merged_into_id is null)
  )
);

comment on table app.master_records is
  'PLT-120: one row per canonical master-data instance. code is the stable natural key; aliases are alternate lookup labels for the same one canonical record (Prompt 120 §24: "labels/aliases do not duplicate truth"). merged_into_id preserves lineage when two records are found to be duplicates (app.merge_master_records) -- the source row is never deleted, only marked canonical_status=''merged'' and pointed at its survivor.';

create index master_records_type_tenant_idx on app.master_records (master_type_code, tenant_id);
create index master_records_name_idx on app.master_records (name);
-- Tenant-scoped codes are unique per (type, tenant); global-scoped codes are unique per
-- type alone. Unconditional on canonical_status (not partial) -- a code is never
-- reusable by a different record even after deactivation/merge, preserving a permanent,
-- unambiguous audit trail (Prompt 120 §24/§25: "deterministic," "no ambiguous
-- resolution").
create unique index master_records_tenant_code_unique
  on app.master_records (master_type_code, tenant_id, code) where tenant_id is not null;
create unique index master_records_global_code_unique
  on app.master_records (master_type_code, code) where tenant_id is null;

create function app.enforce_master_record_scope()
returns trigger
language plpgsql
as $$
declare
  v_type app.master_types;
begin
  select * into v_type from app.master_types where code = new.master_type_code;
  if not found then
    raise exception 'unknown_master_type: no master type %', new.master_type_code
      using errcode = 'foreign_key_violation';
  end if;

  if v_type.scope = 'global' and new.tenant_id is not null then
    raise exception 'scope_mismatch: master type % is global-scoped, tenant_id must be null', new.master_type_code
      using errcode = 'check_violation';
  end if;
  if v_type.scope = 'tenant' and new.tenant_id is null then
    raise exception 'scope_mismatch: master type % is tenant-scoped, tenant_id is required', new.master_type_code
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger master_records_enforce_scope
  before insert or update on app.master_records
  for each row
  execute function app.enforce_master_record_scope();

create function app.touch_master_record_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger master_records_touch_row
  before update on app.master_records
  for each row
  execute function app.touch_master_record_row();

-- Authority (§26): Supreme manages the global catalogue (tenant_id is null); Tenant
-- Admin manages their own tenant's masters -- app.is_support_grant_authority() is
-- deliberately NOT reused here for the global-scope branch (it answers "tenant_admin of
-- tenant X, or Supreme" for a *specific* tenant_id, which is meaningless for a global,
-- tenant_id-less record) -- app.is_supreme_admin() is the correct, narrower check.
create function app.create_master_record(
  p_master_type_code text,
  p_tenant_id uuid,
  p_code text,
  p_name text,
  p_aliases jsonb,
  p_attributes jsonb,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.master_records
language plpgsql
as $$
declare
  v_existing app.master_records;
  v_record app.master_records;
begin
  if p_tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only Supreme Admin may create a global-scoped master record'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
      raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  select * into v_existing
  from app.master_records
  where master_type_code = p_master_type_code
    and code = p_code
    and (tenant_id = p_tenant_id or (tenant_id is null and p_tenant_id is null));
  if found then
    return v_existing;
  end if;

  insert into app.master_records (master_type_code, tenant_id, code, name, aliases, attributes, created_by)
  values (p_master_type_code, p_tenant_id, p_code, p_name, coalesce(p_aliases, '[]'::jsonb), coalesce(p_attributes, '{}'::jsonb), p_created_by)
  returning * into v_record;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_master_record',
    'app.master_records', v_record.id, 'success', null, null, to_jsonb(v_record)
  );

  return v_record;
exception
  when unique_violation then
    raise exception 'master_record_already_exists: code % already exists for master type %', p_code, p_master_type_code
      using errcode = 'unique_violation';
end;
$$;

create function app.update_master_record(
  p_record_id uuid,
  p_expected_version integer,
  p_name text,
  p_aliases jsonb,
  p_attributes jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.master_records
language plpgsql
as $$
declare
  v_before app.master_records;
  v_after app.master_records;
begin
  select * into v_before from app.master_records where id = p_record_id;
  if not found then
    raise exception 'master_record_not_found: no master record %', p_record_id
      using errcode = 'no_data_found';
  end if;

  if v_before.tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only Supreme Admin may update a global-scoped master record'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
      raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_before.canonical_status <> 'active' then
    raise exception 'master_record_not_active: record % is %, only an active record may be updated', p_record_id, v_before.canonical_status
      using errcode = 'check_violation';
  end if;

  if v_before.record_version <> p_expected_version then
    raise exception 'stale_record_version: expected version % but record % is at version %', p_expected_version, p_record_id, v_before.record_version
      using errcode = 'check_violation';
  end if;

  update app.master_records
  set name = coalesce(p_name, name),
      aliases = coalesce(p_aliases, aliases),
      attributes = coalesce(p_attributes, attributes)
  where id = p_record_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_master_record',
    'app.master_records', v_after.id, 'success', null, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

create function app.deactivate_master_record(
  p_record_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.master_records
language plpgsql
as $$
declare
  v_before app.master_records;
  v_after app.master_records;
begin
  select * into v_before from app.master_records where id = p_record_id;
  if not found then
    raise exception 'master_record_not_found: no master record %', p_record_id
      using errcode = 'no_data_found';
  end if;

  if v_before.tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only Supreme Admin may deactivate a global-scoped master record'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not app.is_support_grant_authority(p_actor_auth_user_id, v_before.tenant_id) then
      raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_before.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_before.canonical_status <> 'active' then
    raise exception 'master_record_not_active: record % is %, only an active record may be deactivated', p_record_id, v_before.canonical_status
      using errcode = 'check_violation';
  end if;

  update app.master_records
  set canonical_status = 'deactivated', deactivated_at = now(), deactivated_by = p_actor_label, deactivated_reason = p_reason, effective_to = now()
  where id = p_record_id
  returning * into v_after;

  perform app.capture_audit_event(
    v_after.tenant_id, p_actor_auth_user_id, p_actor_label, 'deactivate_master_record',
    'app.master_records', v_after.id, 'success', p_reason, to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

-- Merge-safe dedupe (Prompt 120 §20 task 2/§24): the source is never deleted -- it is
-- marked canonical_status='merged' and permanently pointed at its survivor via
-- merged_into_id, and its aliases (plus its own former code) are folded into the
-- target's alias list, so anything that used to resolve the source's code still
-- resolves correctly through the target (app.resolve_master_record follows the chain).
create function app.merge_master_records(
  p_source_id uuid,
  p_target_id uuid,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.master_records
language plpgsql
as $$
declare
  v_source app.master_records;
  v_target app.master_records;
  v_merged_aliases jsonb;
  v_updated_target app.master_records;
begin
  if p_source_id = p_target_id then
    raise exception 'invalid_merge: cannot merge a master record into itself'
      using errcode = 'check_violation';
  end if;

  select * into v_source from app.master_records where id = p_source_id;
  if not found then
    raise exception 'master_record_not_found: no master record %', p_source_id
      using errcode = 'no_data_found';
  end if;

  select * into v_target from app.master_records where id = p_target_id;
  if not found then
    raise exception 'master_record_not_found: no master record %', p_target_id
      using errcode = 'no_data_found';
  end if;

  if v_source.master_type_code <> v_target.master_type_code or v_source.tenant_id is distinct from v_target.tenant_id then
    raise exception 'invalid_merge: source and target must share the same master type and tenant scope'
      using errcode = 'check_violation';
  end if;

  if v_source.canonical_status <> 'active' or v_target.canonical_status <> 'active' then
    raise exception 'invalid_merge: both source and target must be active (source=%, target=%)', v_source.canonical_status, v_target.canonical_status
      using errcode = 'check_violation';
  end if;

  if v_source.tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only Supreme Admin may merge a global-scoped master record'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not app.is_support_grant_authority(p_actor_auth_user_id, v_source.tenant_id) then
      raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_source.tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  v_merged_aliases := v_target.aliases || v_source.aliases || jsonb_build_array(v_source.code);
  if jsonb_array_length(v_merged_aliases) > 20 then
    v_merged_aliases := (select jsonb_agg(elem) from (select elem from jsonb_array_elements(v_merged_aliases) elem limit 20) sub);
  end if;

  update app.master_records
  set aliases = v_merged_aliases
  where id = p_target_id
  returning * into v_updated_target;

  update app.master_records
  set canonical_status = 'merged', merged_into_id = p_target_id, merged_at = now(), merged_by = p_actor_label, effective_to = now()
  where id = p_source_id;

  perform app.capture_audit_event(
    v_source.tenant_id, p_actor_auth_user_id, p_actor_label, 'merge_master_records',
    'app.master_records', p_source_id, 'success', p_reason, to_jsonb(v_source), jsonb_build_object('merged_into_id', p_target_id)
  );

  return v_updated_target;
end;
$$;

-- Resolves a code or alias to its live canonical record, following a merge chain if the
-- directly-matched row has itself since been merged into another (§25: "no ambiguous
-- resolution" -- exactly one terminal active record, or none). Not SECURITY DEFINER --
-- relies on RLS (below) for tenant isolation, the same "plain grant + RLS" pattern
-- PLT-113 established for primary tables, since (unlike PLT-117/118/119's evaluators)
-- master-data lookup has no pre-authentication use case requiring anon access.
create function app.resolve_master_record(
  p_master_type_code text,
  p_tenant_id uuid,
  p_code_or_alias text
)
returns app.master_records
language plpgsql
stable
as $$
declare
  v_record app.master_records;
  v_guard integer := 0;
begin
  select * into v_record
  from app.master_records m
  where m.master_type_code = p_master_type_code
    and (m.tenant_id = p_tenant_id or (m.tenant_id is null and p_tenant_id is null))
    and (m.code = p_code_or_alias or m.aliases @> to_jsonb(array[p_code_or_alias]))
  order by (m.code = p_code_or_alias) desc
  limit 1;

  if not found then
    return null;
  end if;

  while v_record.canonical_status = 'merged' and v_guard < 10 loop
    select * into v_record from app.master_records where id = v_record.merged_into_id;
    v_guard := v_guard + 1;
  end loop;

  return v_record;
end;
$$;

comment on function app.resolve_master_record is
  'PLT-120: resolves a code or alias to its live canonical record, transparently following a bounded (<=10 hop) merge chain. Returns null (never an error) for no match -- "ambiguous resolution" is structurally impossible since code/alias uniqueness plus the code-match-first ORDER BY guarantee at most one starting row.';

-- Keyset-paginated search (Prompt 120 §17: "indexed search/lookup, server pagination...
-- no full datasets").
create function app.search_master_records(
  p_master_type_code text,
  p_tenant_id uuid,
  p_query text default null,
  p_limit integer default 50,
  p_after_code text default null
)
returns setof app.master_records
language sql
stable
as $$
  select *
  from app.master_records m
  where m.master_type_code = p_master_type_code
    and (m.tenant_id = p_tenant_id or (m.tenant_id is null and p_tenant_id is null))
    and (p_query is null or m.code ilike '%' || p_query || '%' or m.name ilike '%' || p_query || '%')
    and (p_after_code is null or m.code > p_after_code)
  order by m.code
  limit least(p_limit, 200);
$$;

-- Sourced convenience view (docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md §4,
-- verbatim: "Commercial's Phase 2 costing reads it via a view (app.v_active_vendor_rates,
-- matching the partial-index pattern in §6) rather than copying rows").
create view app.v_active_vendor_rates as
select * from app.master_records where master_type_code = 'vendor_rate' and canonical_status = 'active';

comment on view app.v_active_vendor_rates is
  'PLT-120: the exact read view docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md §4 names for Commercial''s future Phase-2 vendor-rate lookup against Procurement''s Phase-1-seeded, Phase-6-owned master type. Empty until Phase 6 (PRC) actually writes real vendor_rate records -- no sample data seeded here (this migration''s own header).';

alter table app.master_types enable row level security;
alter table app.master_records enable row level security;

-- app.master_types is platform-owned reference data (what kinds of masters exist) --
-- safe to expose broadly, no PII/tenant data.
create policy master_types_select_authenticated on app.master_types
  for select to authenticated
  using (true);

-- app.master_records: a tenant sees its own tenant-scoped rows plus every global-scoped
-- row; Supreme Admin sees everything -- the same has_active_tenant_membership()/
-- is_supreme_admin() composition PLT-113 already established for every other
-- tenant-scoped table, extended with the "OR tenant_id is null" global-visibility branch
-- this table introduces for the first time.
create policy master_records_select_scoped on app.master_records
  for select to authenticated
  using (tenant_id is null or app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant usage on schema app to authenticated;
grant select on app.master_types to authenticated, service_role;
grant select on app.master_records to authenticated, service_role;
grant select on app.v_active_vendor_rates to authenticated, service_role;
grant insert, update, delete on app.master_types to service_role;
grant insert, update, delete on app.master_records to service_role;
grant execute on function app.validate_master_attributes(jsonb) to service_role;
grant execute on function app.validate_master_aliases(jsonb) to service_role;
grant execute on function app.register_master_type(text, text, text, text, uuid, text) to service_role;
grant execute on function app.create_master_record(text, uuid, text, text, jsonb, jsonb, uuid, text) to service_role;
grant execute on function app.update_master_record(uuid, integer, text, jsonb, jsonb, uuid, text) to service_role;
grant execute on function app.deactivate_master_record(uuid, uuid, text, text) to service_role;
grant execute on function app.merge_master_records(uuid, uuid, uuid, text, text) to service_role;
-- Read-only resolution/search: RLS-governed, safe for a direct authenticated grant (the
-- same "plain grant + RLS" posture PLT-113 established, not a SECURITY DEFINER
-- evaluator -- master-data lookup has no pre-authentication use case).
grant execute on function app.resolve_master_record(text, uuid, text) to authenticated, service_role;
grant execute on function app.search_master_records(text, uuid, text, integer, text) to authenticated, service_role;
