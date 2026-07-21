-- Platform Core capability PLT-126 (Form and Custom-Field Builder, CG-S6-PLT-023)
-- Governed form/custom-field definitions, versioning, validation, access metadata, and
-- safe value storage without arbitrary code (Prompt 126 §4). Exactly like
-- `PLT-122`/`123`/`124`/`125`'s definitions, a form is not a new table family for its
-- *definition* -- it is `PLT-121`'s own Configuration Engine, reused directly, with one
-- dedicated `form:<code>` config_type minted per form (the same "registry, not enum"
-- composition `PLT-124`'s Status Engine already established for the exact same
-- structural reason: `config_objects_scope_shape_check` forces `scope_id` null at
-- `scope_level='tenant'`, so the single shared, `PLT-121`-seeded generic `'form'` type
-- could host at most one tenant-scoped object ever -- insufficient for a tenant that
-- wants more than one form).
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **No domain form exists anywhere in this migration** (§12, forbidden: "domain
--   forms/pages... full builder portal"). The one representative example this
--   checkpoint uses (a small "Vendor Onboarding" custom-field set) is built and proven
--   entirely inside `scripts/db-tests/form.sql` -- no form/field row of any kind is
--   seeded into this migration itself.
-- * **EAV query explosion is structurally avoided** (§13). This migration deliberately
--   does *not* create one row per (entity, field) -- `app.custom_field_values` holds
--   exactly one row per (tenant, entity_type, entity_id), with every field's value
--   packed into a single `values jsonb` column. Reading or writing an entity's custom
--   fields is always a single-row operation, never a fan-out join across N field rows,
--   the classic EAV anti-pattern this prompt explicitly names.
-- * **No arbitrary code, ever** (§16/§24). Field types (`text`/`textarea`/`number`/
--   `boolean`/`date`/`select`/`multiselect`/`email`) and validators (`min_length`/
--   `max_length`/`min`/`max`/`pattern`) are both real, bounded allowlists -- the same
--   "no arbitrary executable code" guardrail `07_CONFIGURATION_ENGINE_WORKSTREAM.md`
--   §11 states for every `config_type`. A field's visibility `condition` is a bounded,
--   structural `{field_code, operator, value}` comparison against another field's
--   submitted value -- never an expression language -- and may only reference a field
--   declared *earlier* in the same `fields` array, which makes a condition cycle
--   structurally impossible by construction rather than requiring a separate cycle
--   detector (`PLT-122`'s own bounded-walk reachability check solves the same class of
--   problem differently, for a genuinely cyclic-by-design domain -- workflows -- where
--   this array-order constraint would be wrong; forms have no such requirement).
-- * **`file` is deliberately not in the field-type allowlist.** No file-storage
--   plumbing exists anywhere in this repository yet (disclosed, matching every other
--   "not yet built" boundary this session has recorded) -- adding a `file` field type
--   without a real storage/virus-scanning/access-control backend would be a fabricated,
--   untested security surface, not a real capability.
-- * **Custom fields extend, never replace, canonical semantics** (§24). This migration
--   creates no canonical business-entity columns and never could -- `entity_type`/
--   `entity_id` are the same disclosed, polymorphic, application-validated reference
--   pattern `PLT-119`/`121`/`122`/`123` already established, pointing at whatever real
--   domain table a later phase introduces.
-- * **Sensitive custom-field values get a real, narrower read gate** (§18: "sensitive
--   custom-field access as required"), composing existing primitives rather than
--   reinventing record-level access: any active tenant member may read a values row
--   with no sensitive field in its bound definition; a row containing at least one
--   `sensitive: true` field additionally requires either being the original submitter
--   or holding the same definition-admin-grade authority
--   `app.check_config_object_authority()` already grants for managing the form itself.
-- * **Values remain interpretable under their historical definition** (§19/§25: "no
--   silent coercion"). `app.custom_field_values.config_version_id` binds every stored
--   value set to the exact published definition snapshot active when it was captured --
--   a later republish creates a *new* `config_versions` row (`PLT-121`'s own
--   never-mutate-a-published-version discipline), so already-captured values are never
--   silently reinterpreted against a schema they were never validated against.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

create table app.form_registry (
  code text primary key,
  name text not null,
  owner_primitive_code text not null,
  registered_by text,
  created_at timestamptz not null default now()
);

comment on table app.form_registry is
  'PLT-126: the registry of form identities. Registering a form also mints its own dedicated app.config_types row (code ''form:<code>'') via app.register_config_type() -- this migration''s own header explains why one shared generic type cannot host every form''s independent tenant presentation.';

create function app.register_form(
  p_code text,
  p_name text,
  p_owner_primitive_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.form_registry
language plpgsql
as $$
declare
  v_existing app.form_registry;
  v_form app.form_registry;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a form'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.form_registry where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.form_registry (code, name, owner_primitive_code, registered_by)
  values (p_code, p_name, p_owner_primitive_code, p_registered_by)
  returning * into v_form;

  perform app.register_config_type('form:' || p_code, p_name, p_owner_primitive_code, p_actor_auth_user_id, p_registered_by);

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_form',
    'app.form_registry', null, 'success', null, null, to_jsonb(v_form)
  );

  return v_form;
end;
$$;

-- Bounded, structural condition evaluator -- {field_code, operator, value}, never an
-- expression language (this migration's own header). operator is 'equals'/'not_equals'
-- only; p_values is the submission's own values object.
create function app.evaluate_field_condition(p_condition jsonb, p_values jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_field_code text;
  v_operator text;
  v_expected jsonb;
  v_actual jsonb;
begin
  if p_condition is null then
    return true;
  end if;

  v_field_code := p_condition ->> 'field_code';
  v_operator := p_condition ->> 'operator';
  v_expected := p_condition -> 'value';
  v_actual := p_values -> v_field_code;

  if v_operator = 'equals' then
    return v_actual is not distinct from v_expected;
  elsif v_operator = 'not_equals' then
    return v_actual is distinct from v_expected;
  else
    raise exception 'custom_field_unknown_condition_operator: operator % is not one of equals/not_equals', v_operator
      using errcode = 'check_violation';
  end if;
end;
$$;

-- Publish-time structural gate over a 'form:<code>'-typed config_version's own
-- config_items (Prompt 126 §20 task 1/2). Expects exactly one item, 'fields' -- a jsonb
-- array of {code, label, type, required, options?, validators?, condition?, sensitive?}
-- in declaration order.
create function app.validate_form_definition(p_version_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_fields jsonb;
  v_field jsonb;
  v_field_code text;
  v_field_type text;
  v_options jsonb;
  v_validators jsonb;
  v_validator jsonb;
  v_validator_type text;
  v_condition jsonb;
  v_condition_field_code text;
  v_seen_codes text[] := array[]::text[];
  v_allowed_types text[] := array['text', 'textarea', 'number', 'boolean', 'date', 'select', 'multiselect', 'email'];
  v_allowed_validators text[] := array['min_length', 'max_length', 'min', 'max', 'pattern'];
begin
  select value into v_fields from app.config_items where config_version_id = p_version_id and key = 'fields';

  if v_fields is null or jsonb_typeof(v_fields) <> 'array' or jsonb_array_length(v_fields) = 0 then
    raise exception 'custom_field_missing_fields: version % has no ''fields'' item, or it is not a non-empty array', p_version_id
      using errcode = 'check_violation';
  end if;
  if jsonb_array_length(v_fields) > 50 then
    raise exception 'custom_field_too_many_fields: % fields declared, the bounded limit is 50', jsonb_array_length(v_fields)
      using errcode = 'check_violation';
  end if;

  for v_field in select * from jsonb_array_elements(v_fields) loop
    v_field_code := v_field ->> 'code';
    v_field_type := v_field ->> 'type';
    v_options := v_field -> 'options';
    v_validators := coalesce(v_field -> 'validators', '[]'::jsonb);
    v_condition := v_field -> 'condition';

    if coalesce(v_field_code, '') = '' then
      raise exception 'custom_field_invalid_code: a field is missing a non-empty code'
        using errcode = 'check_violation';
    end if;
    if v_field_code = any (v_seen_codes) then
      raise exception 'custom_field_duplicate_code: field code % is declared more than once', v_field_code
        using errcode = 'check_violation';
    end if;
    if coalesce(v_field ->> 'label', '') = '' then
      raise exception 'custom_field_missing_label: field % has no non-empty label', v_field_code
        using errcode = 'check_violation';
    end if;
    if v_field_type is null or not (v_field_type = any (v_allowed_types)) then
      raise exception 'custom_field_invalid_type: field % has type % which is not an allowed field type', v_field_code, v_field_type
        using errcode = 'check_violation';
    end if;
    if v_field_type in ('select', 'multiselect') and (v_options is null or jsonb_typeof(v_options) <> 'array' or jsonb_array_length(v_options) = 0) then
      raise exception 'custom_field_missing_options: field % is type % and requires a non-empty options array', v_field_code, v_field_type
        using errcode = 'check_violation';
    end if;

    for v_validator in select * from jsonb_array_elements(v_validators) loop
      v_validator_type := v_validator ->> 'type';
      if v_validator_type is null or not (v_validator_type = any (v_allowed_validators)) then
        raise exception 'custom_field_invalid_validator: field % has validator type % which is not an allowed validator', v_field_code, v_validator_type
          using errcode = 'check_violation';
      end if;
      if v_validator_type = 'pattern' and length(coalesce(v_validator ->> 'value', '')) > 200 then
        raise exception 'custom_field_invalid_validator: field %''s pattern validator exceeds the 200-character bound', v_field_code
          using errcode = 'check_violation';
      end if;
    end loop;

    if v_condition is not null then
      v_condition_field_code := v_condition ->> 'field_code';
      if v_condition ->> 'operator' not in ('equals', 'not_equals') then
        raise exception 'custom_field_unknown_condition_operator: field %''s condition operator % is not one of equals/not_equals', v_field_code, v_condition ->> 'operator'
          using errcode = 'check_violation';
      end if;
      if not (v_condition_field_code = any (v_seen_codes)) then
        raise exception 'custom_field_invalid_condition_reference: field %''s condition references % which is not an earlier-declared field (this structurally rules out condition cycles)', v_field_code, v_condition_field_code
          using errcode = 'check_violation';
      end if;
    end if;

    v_seen_codes := v_seen_codes || v_field_code;
  end loop;

  return true;
end;
$$;

comment on function app.validate_form_definition is
  'PLT-126: the publish-time structural gate -- every field has a unique code/real label/allowlisted type (with options required for select/multiselect), every validator is allowlisted with a bounded pattern length, and every condition references only an earlier-declared field code (cycle-free by construction). Raises a distinct, named exception per failure mode.';

create function app.publish_form_definition(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
begin
  perform app.validate_form_definition(p_version_id);
  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

-- Validates a candidate values object against a published definition (Prompt 126 §21/
-- §23/§25): every declared field's type/validators are checked, required fields are
-- enforced *unless* their own condition currently hides them, and any key in p_values
-- that is not a declared field code is rejected outright (no unauthorized/unknown
-- field may ever be stored).
create function app.validate_custom_field_values(p_config_version_id uuid, p_values jsonb)
returns boolean
language plpgsql
as $$
declare
  v_fields jsonb;
  v_field jsonb;
  v_field_code text;
  v_field_type text;
  v_options jsonb;
  v_condition jsonb;
  v_visible boolean;
  v_value jsonb;
  v_validators jsonb;
  v_validator jsonb;
  v_key text;
  v_declared_codes text[] := array[]::text[];
begin
  select value into v_fields from app.config_items where config_version_id = p_config_version_id and key = 'fields';
  if v_fields is null then
    raise exception 'custom_field_missing_fields: config version % has no ''fields'' item', p_config_version_id
      using errcode = 'check_violation';
  end if;

  for v_field in select * from jsonb_array_elements(v_fields) loop
    v_declared_codes := v_declared_codes || (v_field ->> 'code');
  end loop;

  for v_key in select jsonb_object_keys(coalesce(p_values, '{}'::jsonb)) loop
    if not (v_key = any (v_declared_codes)) then
      raise exception 'custom_field_unknown_field: % is not a declared field on this form', v_key
        using errcode = 'check_violation';
    end if;
  end loop;

  for v_field in select * from jsonb_array_elements(v_fields) loop
    v_field_code := v_field ->> 'code';
    v_field_type := v_field ->> 'type';
    v_options := v_field -> 'options';
    v_condition := v_field -> 'condition';
    v_validators := coalesce(v_field -> 'validators', '[]'::jsonb);
    v_value := p_values -> v_field_code;
    v_visible := app.evaluate_field_condition(v_condition, p_values);

    if coalesce((v_field ->> 'required')::boolean, false) and v_visible and v_value is null then
      raise exception 'custom_field_required_missing: field % is required and currently visible, but no value was provided', v_field_code
        using errcode = 'check_violation';
    end if;

    if v_value is null or jsonb_typeof(v_value) = 'null' then
      continue;
    end if;

    if v_field_type in ('text', 'textarea', 'email') and jsonb_typeof(v_value) <> 'string' then
      raise exception 'custom_field_invalid_value: field % expects a string value', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'number' and jsonb_typeof(v_value) <> 'number' then
      raise exception 'custom_field_invalid_value: field % expects a number value', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'boolean' and jsonb_typeof(v_value) <> 'boolean' then
      raise exception 'custom_field_invalid_value: field % expects a boolean value', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'date' and (jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$') then
      raise exception 'custom_field_invalid_value: field % expects a YYYY-MM-DD date string', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'email' and (v_value #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      raise exception 'custom_field_invalid_value: field % expects a valid email address', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'select' and (jsonb_typeof(v_value) <> 'string' or not (v_options ? (v_value #>> '{}'))) then
      raise exception 'custom_field_invalid_value: field %''s value is not one of its declared options', v_field_code
        using errcode = 'check_violation';
    elsif v_field_type = 'multiselect' then
      if jsonb_typeof(v_value) <> 'array' then
        raise exception 'custom_field_invalid_value: field % expects an array of options', v_field_code
          using errcode = 'check_violation';
      end if;
      if exists (select 1 from jsonb_array_elements_text(v_value) e where not (v_options ? e)) then
        raise exception 'custom_field_invalid_value: field %''s value contains an option not in its declared options', v_field_code
          using errcode = 'check_violation';
      end if;
    end if;

    for v_validator in select * from jsonb_array_elements(v_validators) loop
      if v_validator ->> 'type' = 'min_length' and length(v_value #>> '{}') < (v_validator ->> 'value')::integer then
        raise exception 'custom_field_validator_failed: field % is shorter than its min_length validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'max_length' and length(v_value #>> '{}') > (v_validator ->> 'value')::integer then
        raise exception 'custom_field_validator_failed: field % is longer than its max_length validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'min' and (v_value #>> '{}')::numeric < (v_validator ->> 'value')::numeric then
        raise exception 'custom_field_validator_failed: field % is below its min validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'max' and (v_value #>> '{}')::numeric > (v_validator ->> 'value')::numeric then
        raise exception 'custom_field_validator_failed: field % is above its max validator', v_field_code
          using errcode = 'check_violation';
      elsif v_validator ->> 'type' = 'pattern' and (v_value #>> '{}') !~ (v_validator ->> 'value') then
        raise exception 'custom_field_validator_failed: field % does not match its pattern validator', v_field_code
          using errcode = 'check_violation';
      end if;
    end loop;
  end loop;

  return true;
end;
$$;

comment on function app.validate_custom_field_values is
  'PLT-126: real submission-time validation -- every submitted key must be a declared field code, every value''s JSON shape must match its field''s type, every validator is enforced, and a required field is only enforced while its own condition currently makes it visible.';

-- One row per (tenant, entity_type, entity_id) -- deliberately not one row per field
-- (this migration''s own header: "EAV query explosion is structurally avoided").
-- app.validate_config_value() is reused verbatim as the values-column CHECK
-- constraint -- the exact recursive depth/size/injection-safety gate PLT-121 already
-- built and every prior checkpoint's own config_items rows already trust.
create table app.custom_field_values (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  config_version_id uuid not null references app.config_versions (id),
  entity_type text not null default 'generic',
  entity_id uuid not null,
  values jsonb not null default '{}'::jsonb,
  submitted_by_auth_user_id uuid references auth.users (id),
  submitted_by text,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint custom_field_values_values_check check (app.validate_config_value(values)),
  constraint custom_field_values_entity_unique unique (tenant_id, entity_type, entity_id),
  constraint custom_field_values_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.custom_field_values is
  'PLT-126: current custom-field values for one entity -- one row per (tenant, entity_type, entity_id), never one row per field. config_version_id binds this row to the exact published form snapshot active when captured, so a later republish never silently reinterprets already-stored values (Prompt 126 §19/§25).';

create index custom_field_values_tenant_id_idx on app.custom_field_values (tenant_id);
create index custom_field_values_config_version_id_idx on app.custom_field_values (config_version_id);

create function app.touch_custom_field_values_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger custom_field_values_touch_row
  before update on app.custom_field_values
  for each row
  execute function app.touch_custom_field_values_row();

-- Instance-level authority (Prompt 126 §26: "field read/write" is separate from
-- "definition admin") -- the same has_active_tenant_membership()-or-Supreme posture
-- PLT-122/123/125's own instance-level authority checks use, not
-- app.check_config_object_authority() (which governs the underlying form definition
-- instead).
create function app.check_custom_field_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- Idempotent upsert on (tenant_id, idempotency_key). Runs the real submission-time
-- validation gate before ever writing. Overwrites only the current-values row for this
-- entity -- prior audit_logs before/after snapshots are the permanent value-change
-- history (Prompt 126 §18), not a bespoke *_history table.
create function app.set_custom_field_values(
  p_config_version_id uuid,
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_values jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_submitted_by text
)
returns app.custom_field_values
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_existing_by_key app.custom_field_values;
  v_existing_by_entity app.custom_field_values;
  v_row app.custom_field_values;
begin
  if not app.check_custom_field_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'custom_field_definition_not_published: config version % is not a published form definition', p_config_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing_by_key from app.custom_field_values where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing_by_key;
  end if;

  perform app.validate_custom_field_values(p_config_version_id, p_values);

  select * into v_existing_by_entity from app.custom_field_values where tenant_id = p_tenant_id and entity_type = coalesce(p_entity_type, 'generic') and entity_id = p_entity_id;

  if found then
    update app.custom_field_values
    set config_version_id = p_config_version_id, values = p_values, idempotency_key = p_idempotency_key,
        submitted_by_auth_user_id = p_actor_auth_user_id, submitted_by = p_submitted_by
    where id = v_existing_by_entity.id
    returning * into v_row;
  else
    insert into app.custom_field_values (tenant_id, config_version_id, entity_type, entity_id, values, submitted_by_auth_user_id, submitted_by, idempotency_key)
    values (p_tenant_id, p_config_version_id, coalesce(p_entity_type, 'generic'), p_entity_id, p_values, p_actor_auth_user_id, p_submitted_by, p_idempotency_key)
    returning * into v_row;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_submitted_by, 'set_custom_field_values',
    'app.custom_field_values', v_row.id, 'success', null, to_jsonb(v_existing_by_entity), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

-- Sensitive-field-gated read (Prompt 126 §18: "sensitive custom-field access as
-- required"). A values row with no sensitive field in its bound definition is
-- readable by any active tenant member; a row with at least one sensitive field
-- additionally requires being the original submitter or holding the same
-- definition-admin-grade authority app.check_config_object_authority() already grants
-- for managing the form itself.
create function app.get_custom_field_values(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_actor_auth_user_id uuid
)
returns app.custom_field_values
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.custom_field_values;
  v_fields jsonb;
  v_has_sensitive boolean;
  v_object_tenant_id uuid;
  v_object_scope_level text;
begin
  if not app.check_custom_field_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.custom_field_values where tenant_id = p_tenant_id and entity_type = coalesce(p_entity_type, 'generic') and entity_id = p_entity_id;
  if not found then
    raise exception 'custom_field_values_not_found: no custom field values for tenant % entity %/%', p_tenant_id, p_entity_type, p_entity_id
      using errcode = 'no_data_found';
  end if;

  select value into v_fields from app.config_items where config_version_id = v_row.config_version_id and key = 'fields';
  select exists (select 1 from jsonb_array_elements(coalesce(v_fields, '[]'::jsonb)) f where coalesce((f ->> 'sensitive')::boolean, false)) into v_has_sensitive;

  if v_has_sensitive and v_row.submitted_by_auth_user_id <> p_actor_auth_user_id then
    select o.tenant_id, o.scope_level into v_object_tenant_id, v_object_scope_level
    from app.config_versions v join app.config_objects o on o.id = v.config_object_id
    where v.id = v_row.config_version_id;

    if not app.check_config_object_authority(v_object_scope_level, v_object_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % may not read a sensitive custom-field values row they did not submit', p_actor_auth_user_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return v_row;
end;
$$;

alter table app.form_registry enable row level security;
alter table app.custom_field_values enable row level security;

-- app.form_registry is platform-owned reference data -- safe to expose broadly, the
-- same posture PLT-122/124's own allowlist/set registries already established.
create policy form_registry_select_authenticated on app.form_registry
  for select to authenticated
  using (true);

-- app.custom_field_values is normal tenant business data -- direct RLS-governed SELECT
-- for authenticated, matching PLT-113/122/123/125's posture for primary tables. Note
-- this table-level RLS predicate does not itself distinguish sensitive from
-- non-sensitive rows (RLS operates per-row on tenant_id, not per-field on values'
-- inner JSON) -- the finer sensitive-field gate above is enforced entirely inside
-- app.get_custom_field_values() (the intended read path), the same "the function
-- itself is the access-control boundary" posture PLT-116's audit_logs and PLT-122's
-- workflow_transition_history already use for a distinction ordinary table-level RLS
-- cannot express.
create policy custom_field_values_select_scoped on app.custom_field_values
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.form_registry to authenticated, service_role;
grant insert, update, delete on app.form_registry to service_role;
grant select on app.custom_field_values to authenticated, service_role;
grant insert, update, delete on app.custom_field_values to service_role;

grant execute on function app.register_form(text, text, text, uuid, text) to service_role;
grant execute on function app.evaluate_field_condition(jsonb, jsonb) to authenticated, service_role;
grant execute on function app.validate_form_definition(uuid) to service_role;
grant execute on function app.publish_form_definition(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.validate_custom_field_values(uuid, jsonb) to authenticated, service_role;
grant execute on function app.check_custom_field_authority(uuid, uuid) to service_role;
grant execute on function app.set_custom_field_values(uuid, uuid, text, uuid, jsonb, text, uuid, text) to service_role;
grant execute on function app.get_custom_field_values(uuid, text, uuid, uuid) to authenticated, service_role;
