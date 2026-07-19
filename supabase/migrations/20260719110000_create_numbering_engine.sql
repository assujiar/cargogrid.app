-- Platform Core capability PLT-125 (Numbering Engine, CG-S6-PLT-022)
-- Configurable, collision-safe numbering with versioned formats, scopes, reservations,
-- and audit (Prompt 125 §4). A numbering *definition* is not a new table family --
-- exactly like `PLT-122`/`123`/`124`'s definitions, it is `PLT-121`'s own
-- `config_type_code='numbering'` config_object/config_version/config_items, reused
-- directly. This migration adds only what the Configuration Engine does not already
-- provide: format-token structural validation at publish time, and the runtime
-- counter/allocation tables that make atomic, collision-safe allocation a real database
-- guarantee rather than an application-level convention.
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **No module-specific hard-coded format exists anywhere in this migration** (§12,
--   forbidden: "module-specific hard-coded formats"). The one representative example
--   this checkpoint uses (an `INV-{SCOPE_CODE}-{YYYY}-{SEQ}` invoice-shaped format) is built and
--   proven entirely inside `scripts/db-tests/numbering.sql` against synthetic tenant
--   data -- no format/definition row of any kind is seeded into this migration itself.
-- * **The internal canonical ID remains stable; the display number is a separate,
--   generated artifact** (§24). `app.numbering_allocations.id` is the real primary key
--   any FK would reference; `formatted_number` is a rendered, human-readable string with
--   its own `unique(tenant_id, formatted_number)` constraint -- the two are
--   deliberately never conflated, the same `05_DATABASE_SCHEMA_WORKSTREAM.md` §2
--   dual-column discipline `PLT-124`'s own header already cites for canonical vs.
--   presentation columns.
-- * **Allocated numbers are never silently recycled** (§24: "not silently recycled
--   unless explicit audited rule"). Voiding/releasing an allocation only changes its
--   `status` (`voided`/`released`) -- it never returns the consumed sequence value to
--   the counter, and every state change is captured via `app.capture_audit_event()`.
--   This is the standard, compliance-safe behavior real numbering systems (invoice
--   numbers, purchase order numbers) require: a cancelled document still burns its
--   number rather than creating a gap-filling duplicate risk.
-- * **Format tokens are a real, bounded allowlist** (`{YYYY}`, `{YY}`, `{MM}`, `{DD}`,
--   `{SEQ}`, `{SCOPE_CODE}`), not an arbitrary template/expression language -- the same
--   "no arbitrary executable code" guardrail `docs/architecture/
--   07_CONFIGURATION_ENGINE_WORKSTREAM.md` §11 states for every `config_type`.
--   `app.validate_numbering_definition()` requires the `{SEQ}` token to appear exactly
--   once (never zero, never more than once -- either would make allocation ambiguous)
--   and rejects any other unrecognized `{...}` token.
-- * **Atomic, collision-safe allocation is a real database guarantee**, not an
--   application-level promise. `app.allocate_numbering_seq()` is a single
--   `INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING` statement -- Postgres's
--   standard safe atomic-counter pattern, serialized by the row lock the upsert itself
--   takes, not an advisory lock or an application-level retry loop. A genuine
--   concurrent-load benchmark across multiple real database connections is disclosed
--   `NOT_RUN` in this single-threaded SQL test sandbox (the same class of environment
--   boundary `PLT-117..124`'s own `test:e2e` disclosure already establishes) --
--   correctness under sequential concurrent-shaped calls (same key, repeated calls)
--   is proven directly instead.
-- * **Legacy bootstrap never renumbers historical records** (§19/§25: "legacy counter
--   starts above verified maximum"). `app.bootstrap_numbering_counter()` seeds a
--   counter's *last-used* value directly and structurally refuses to ever lower an
--   existing counter (`numbering_counter_cannot_decrease`) -- the next real allocation
--   after a bootstrap is always `starting_seq + 1`, never a reused legacy value.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

-- Publish-time structural gate over a 'numbering'-typed config_version's own
-- config_items (Prompt 125 §20 task 1/2). Expects 'format' (a template string),
-- 'reset_period' ('never'/'yearly'/'monthly'/'daily'), and 'padding' (integer >=1).
create function app.validate_numbering_definition(p_version_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_format text;
  v_reset_period text;
  v_padding integer;
  v_seq_occurrences integer;
  v_tokens text[];
  v_token text;
  v_allowed_tokens text[] := array['YYYY', 'YY', 'MM', 'DD', 'SEQ', 'SCOPE_CODE'];
begin
  select value #>> '{}' into v_format from app.config_items where config_version_id = p_version_id and key = 'format';
  select value #>> '{}' into v_reset_period from app.config_items where config_version_id = p_version_id and key = 'reset_period';
  select (value #>> '{}')::integer into v_padding from app.config_items where config_version_id = p_version_id and key = 'padding';

  if v_format is null or length(v_format) = 0 then
    raise exception 'numbering_missing_format: version % has no non-empty ''format'' item', p_version_id
      using errcode = 'check_violation';
  end if;

  v_seq_occurrences := (length(v_format) - length(replace(v_format, '{SEQ}', ''))) / length('{SEQ}');
  if v_seq_occurrences <> 1 then
    raise exception 'numbering_invalid_seq_token_count: format must contain exactly one {SEQ} token, found %', v_seq_occurrences
      using errcode = 'check_violation';
  end if;

  select array_agg(m[1]) into v_tokens from regexp_matches(v_format, '\{([A-Z_]+)\}', 'g') as m;
  foreach v_token in array coalesce(v_tokens, array[]::text[]) loop
    if not (v_token = any (v_allowed_tokens)) then
      raise exception 'numbering_unknown_token: format references unrecognized token {%}', v_token
        using errcode = 'check_violation';
    end if;
  end loop;

  if v_reset_period is null or v_reset_period not in ('never', 'yearly', 'monthly', 'daily') then
    raise exception 'numbering_invalid_reset_period: reset_period % is not one of never/yearly/monthly/daily', v_reset_period
      using errcode = 'check_violation';
  end if;

  if v_padding is null or v_padding < 1 or v_padding > 10 then
    raise exception 'numbering_invalid_padding: padding % must be between 1 and 10', v_padding
      using errcode = 'check_violation';
  end if;

  return true;
end;
$$;

comment on function app.validate_numbering_definition is
  'PLT-125: the publish-time structural gate -- format must contain exactly one {SEQ} token and no unrecognized token, reset_period must be a real bounded value, padding must be a sane width. This is the "collision analysis" (Prompt 125 §20 task 2) at the format-shape level; actual collision prevention at allocation time is a real unique constraint (see app.numbering_allocations below), not merely a validation-time promise.';

create function app.publish_numbering_definition(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_effective_from timestamptz,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
begin
  perform app.validate_numbering_definition(p_version_id);
  return app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);
end;
$$;

-- Renders a format template against a concrete seq/padding/scope_code/as_of instant.
-- Pure token substitution over the fixed allowlist above -- never an executable
-- expression (this migration's own header).
create function app.format_numbering_value(
  p_format text,
  p_seq integer,
  p_padding integer,
  p_scope_code text,
  p_as_of timestamptz default now()
)
returns text
language sql
immutable
as $$
  select replace(
    replace(
      replace(
        replace(
          replace(
            replace(p_format, '{YYYY}', to_char(p_as_of, 'YYYY')),
            '{YY}', to_char(p_as_of, 'YY')
          ),
          '{MM}', to_char(p_as_of, 'MM')
        ),
        '{DD}', to_char(p_as_of, 'DD')
      ),
      '{SCOPE_CODE}', coalesce(p_scope_code, '')
    ),
    '{SEQ}', lpad(p_seq::text, p_padding, '0')
  );
$$;

-- One row per (definition version, caller-provided scope_key, computed period_key) --
-- scope_key is a polymorphic, application-provided disambiguator (e.g. a branch code),
-- the same disclosed pattern PLT-119/121/122's polymorphic references already
-- established, not a physical FK.
create table app.numbering_counters (
  id uuid primary key default gen_random_uuid(),
  config_version_id uuid not null references app.config_versions (id),
  scope_key text not null default 'default',
  period_key text not null,
  next_seq integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint numbering_counters_next_seq_check check (next_seq >= 0),
  constraint numbering_counters_unique unique (config_version_id, scope_key, period_key)
);

comment on table app.numbering_counters is
  'PLT-125: the atomic counter state for one (definition version, scope_key, period_key) tuple. next_seq holds the *last allocated* value -- app.allocate_numbering_seq()''s single INSERT ... ON CONFLICT DO UPDATE statement is the sole real mutation path, serialized by Postgres''s own row lock.';

create function app.touch_numbering_counter_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger numbering_counters_touch_row
  before update on app.numbering_counters
  for each row
  execute function app.touch_numbering_counter_row();

-- Single-statement atomic allocate-or-increment (Prompt 125 §17: "atomic counter
-- allocation with short locks/high concurrency"). A brand-new key inserts directly at
-- 1 and returns 1; an existing key (including one seeded above its legacy maximum by
-- app.bootstrap_numbering_counter()) increments by exactly 1 and returns the new value.
create function app.allocate_numbering_seq(
  p_config_version_id uuid,
  p_scope_key text,
  p_period_key text
)
returns integer
language plpgsql
as $$
declare
  v_seq integer;
begin
  insert into app.numbering_counters (config_version_id, scope_key, period_key, next_seq)
  values (p_config_version_id, p_scope_key, p_period_key, 1)
  on conflict (config_version_id, scope_key, period_key)
  do update set next_seq = app.numbering_counters.next_seq + 1
  returning next_seq into v_seq;

  return v_seq;
end;
$$;

-- Legacy bootstrap (Prompt 125 §19/§25): seeds a counter's *last-used* value directly.
-- Structurally refuses to ever lower an existing counter -- the next real allocation
-- after this call is always starting_seq + 1, never a reused legacy value.
create function app.bootstrap_numbering_counter(
  p_config_version_id uuid,
  p_scope_key text,
  p_period_key text,
  p_starting_seq integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.numbering_counters
language plpgsql
as $$
declare
  v_object_tenant_id uuid;
  v_object_scope_level text;
  v_existing app.numbering_counters;
  v_counter app.numbering_counters;
begin
  select o.tenant_id, o.scope_level into v_object_tenant_id, v_object_scope_level
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where v.id = p_config_version_id;
  if not found then
    raise exception 'numbering_definition_not_found: no config version %', p_config_version_id
      using errcode = 'no_data_found';
  end if;

  if not app.check_config_object_authority(v_object_scope_level, v_object_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to bootstrap this numbering counter', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_starting_seq < 0 then
    raise exception 'numbering_invalid_starting_seq: starting_seq must be >= 0'
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.numbering_counters where config_version_id = p_config_version_id and scope_key = p_scope_key and period_key = p_period_key;
  if found then
    if p_starting_seq < v_existing.next_seq then
      raise exception 'numbering_counter_cannot_decrease: starting_seq % is below the counter''s current value % (legacy bootstrap must start above the verified maximum)', p_starting_seq, v_existing.next_seq
        using errcode = 'check_violation';
    end if;
    update app.numbering_counters set next_seq = p_starting_seq where id = v_existing.id returning * into v_counter;
  else
    insert into app.numbering_counters (config_version_id, scope_key, period_key, next_seq)
    values (p_config_version_id, p_scope_key, p_period_key, p_starting_seq)
    returning * into v_counter;
  end if;

  perform app.capture_audit_event(
    v_object_tenant_id, p_actor_auth_user_id, p_actor_label, 'bootstrap_numbering_counter',
    'app.numbering_counters', v_counter.id, 'success', null, to_jsonb(v_existing), to_jsonb(v_counter)
  );

  return v_counter;
end;
$$;

-- Every successfully rendered number (allocated or reserved). formatted_number's own
-- unique(tenant_id, formatted_number) is the real, final collision guarantee -- even if
-- two different definitions somehow rendered the same literal string, the second
-- allocation would fail loudly (unique_violation) rather than silently duplicate.
create table app.numbering_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  config_version_id uuid not null references app.config_versions (id),
  scope_key text not null default 'default',
  period_key text not null,
  seq integer not null,
  formatted_number text not null,
  entity_type text not null default 'generic',
  entity_id uuid,
  status text not null default 'allocated',
  idempotency_key text not null,
  allocated_by text,
  allocated_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint numbering_allocations_status_check check (status in ('reserved', 'allocated', 'released', 'voided')),
  constraint numbering_allocations_tenant_formatted_unique unique (tenant_id, formatted_number),
  constraint numbering_allocations_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.numbering_allocations is
  'PLT-125: the internal canonical id column is `id`; `formatted_number` is a separate, generated, human-readable artifact (this migration''s own header). status never reverts to a state that frees seq for reuse -- released/voided are both terminal, permanent, audited (Prompt 125 §24).';

create index numbering_allocations_tenant_id_idx on app.numbering_allocations (tenant_id);
create index numbering_allocations_config_version_id_idx on app.numbering_allocations (config_version_id);

create function app.touch_numbering_allocation_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger numbering_allocations_touch_row
  before update on app.numbering_allocations
  for each row
  execute function app.touch_numbering_allocation_row();

-- Allocation-time authority is deliberately looser than definition-management authority
-- (Prompt 125 §26: "services allocate for permitted records") -- the same
-- has_active_tenant_membership()-or-Supreme posture PLT-122/123's own instance-level
-- authority checks use, not app.check_config_object_authority() (which governs the
-- underlying config_object instead).
create function app.check_numbering_allocation_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- Shared core: authority + published-version check, idempotent existing-allocation
-- short-circuit, format/reset_period/padding lookup, atomic seq allocation, and the
-- final formatted_number render -- used by both app.allocate_number() (status directly
-- 'allocated', the main flow) and app.reserve_number() (status 'reserved', the
-- alternative reserve/confirm/release flow, Prompt 125 §22).
create function app.allocate_or_reserve_number(
  p_status text,
  p_config_version_id uuid,
  p_tenant_id uuid,
  p_scope_key text,
  p_entity_type text,
  p_entity_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_allocated_by text
)
returns app.numbering_allocations
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_existing app.numbering_allocations;
  v_format text;
  v_reset_period text;
  v_padding integer;
  v_period_key text;
  v_seq integer;
  v_formatted text;
  v_allocation app.numbering_allocations;
begin
  if not app.check_numbering_allocation_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'numbering_definition_not_published: config version % is not a published numbering definition', p_config_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.numbering_allocations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  select value #>> '{}' into v_format from app.config_items where config_version_id = p_config_version_id and key = 'format';
  select value #>> '{}' into v_reset_period from app.config_items where config_version_id = p_config_version_id and key = 'reset_period';
  select (value #>> '{}')::integer into v_padding from app.config_items where config_version_id = p_config_version_id and key = 'padding';

  v_period_key := case v_reset_period
    when 'never' then 'ALL'
    when 'yearly' then to_char(now(), 'YYYY')
    when 'monthly' then to_char(now(), 'YYYY-MM')
    when 'daily' then to_char(now(), 'YYYY-MM-DD')
  end;

  v_seq := app.allocate_numbering_seq(p_config_version_id, coalesce(p_scope_key, 'default'), v_period_key);
  v_formatted := app.format_numbering_value(v_format, v_seq, v_padding, p_scope_key, now());

  insert into app.numbering_allocations (
    tenant_id, config_version_id, scope_key, period_key, seq, formatted_number,
    entity_type, entity_id, status, idempotency_key, allocated_by
  )
  values (
    p_tenant_id, p_config_version_id, coalesce(p_scope_key, 'default'), v_period_key, v_seq, v_formatted,
    coalesce(p_entity_type, 'generic'), p_entity_id, p_status, p_idempotency_key, p_allocated_by
  )
  returning * into v_allocation;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_allocated_by,
    case when p_status = 'reserved' then 'reserve_number' else 'allocate_number' end,
    'app.numbering_allocations', v_allocation.id, 'success', null, null, to_jsonb(v_allocation)
  );

  return v_allocation;
end;
$$;

create function app.allocate_number(
  p_config_version_id uuid,
  p_tenant_id uuid,
  p_scope_key text,
  p_entity_type text,
  p_entity_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_allocated_by text
)
returns app.numbering_allocations
language sql
as $$
  select app.allocate_or_reserve_number('allocated', p_config_version_id, p_tenant_id, p_scope_key, p_entity_type, p_entity_id, p_idempotency_key, p_actor_auth_user_id, p_allocated_by);
$$;

create function app.reserve_number(
  p_config_version_id uuid,
  p_tenant_id uuid,
  p_scope_key text,
  p_entity_type text,
  p_entity_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_allocated_by text
)
returns app.numbering_allocations
language sql
as $$
  select app.allocate_or_reserve_number('reserved', p_config_version_id, p_tenant_id, p_scope_key, p_entity_type, p_entity_id, p_idempotency_key, p_actor_auth_user_id, p_allocated_by);
$$;

create function app.confirm_number_reservation(
  p_allocation_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.numbering_allocations
language plpgsql
as $$
declare
  v_allocation app.numbering_allocations;
  v_updated app.numbering_allocations;
begin
  select * into v_allocation from app.numbering_allocations where id = p_allocation_id;
  if not found then
    raise exception 'numbering_allocation_not_found: no numbering allocation %', p_allocation_id
      using errcode = 'no_data_found';
  end if;
  if not app.check_numbering_allocation_authority(v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_allocation.status <> 'reserved' then
    raise exception 'numbering_allocation_not_reserved: allocation % is %, only a reserved allocation can be confirmed', p_allocation_id, v_allocation.status
      using errcode = 'check_violation';
  end if;

  update app.numbering_allocations set status = 'allocated' where id = p_allocation_id returning * into v_updated;

  perform app.capture_audit_event(
    v_allocation.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_number_reservation',
    'app.numbering_allocations', v_updated.id, 'success', null, to_jsonb(v_allocation), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.release_number_reservation(
  p_allocation_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text
)
returns app.numbering_allocations
language plpgsql
as $$
declare
  v_allocation app.numbering_allocations;
  v_updated app.numbering_allocations;
begin
  select * into v_allocation from app.numbering_allocations where id = p_allocation_id;
  if not found then
    raise exception 'numbering_allocation_not_found: no numbering allocation %', p_allocation_id
      using errcode = 'no_data_found';
  end if;
  if not app.check_numbering_allocation_authority(v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_allocation.status <> 'reserved' then
    raise exception 'numbering_allocation_not_reserved: allocation % is %, only a reserved allocation can be released', p_allocation_id, v_allocation.status
      using errcode = 'check_violation';
  end if;

  update app.numbering_allocations set status = 'released', voided_at = now(), voided_reason = p_reason where id = p_allocation_id returning * into v_updated;

  perform app.capture_audit_event(
    v_allocation.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_number_reservation',
    'app.numbering_allocations', v_updated.id, 'success', p_reason, to_jsonb(v_allocation), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.void_number_allocation(
  p_allocation_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text
)
returns app.numbering_allocations
language plpgsql
as $$
declare
  v_allocation app.numbering_allocations;
  v_updated app.numbering_allocations;
begin
  select * into v_allocation from app.numbering_allocations where id = p_allocation_id;
  if not found then
    raise exception 'numbering_allocation_not_found: no numbering allocation %', p_allocation_id
      using errcode = 'no_data_found';
  end if;
  if not app.check_numbering_allocation_authority(v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_allocation.status <> 'allocated' then
    raise exception 'numbering_allocation_not_allocated: allocation % is %, only an allocated number can be voided', p_allocation_id, v_allocation.status
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'numbering_void_reason_required: voiding an allocated number requires an explicit, non-empty reason (Prompt 125 §24: not recycled unless an explicit audited rule)'
      using errcode = 'check_violation';
  end if;

  update app.numbering_allocations set status = 'voided', voided_at = now(), voided_reason = p_reason where id = p_allocation_id returning * into v_updated;

  perform app.capture_audit_event(
    v_allocation.tenant_id, p_actor_auth_user_id, p_actor_label, 'void_number_allocation',
    'app.numbering_allocations', v_updated.id, 'success', p_reason, to_jsonb(v_allocation), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- Read view-model (Prompt 125 §15: "format preview/config view models"). SECURITY
-- DEFINER: not strictly required (app.numbering_allocations already carries a direct
-- authenticated grant below), kept plain for consistency with that grant.
create function app.get_numbering_allocation_status(
  p_allocation_id uuid,
  p_actor_auth_user_id uuid
)
returns app.numbering_allocations
language plpgsql
stable
as $$
declare
  v_allocation app.numbering_allocations;
begin
  select * into v_allocation from app.numbering_allocations where id = p_allocation_id;
  if not found then
    raise exception 'numbering_allocation_not_found: no numbering allocation %', p_allocation_id
      using errcode = 'no_data_found';
  end if;
  if not app.check_numbering_allocation_authority(v_allocation.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, v_allocation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return v_allocation;
end;
$$;

alter table app.numbering_counters enable row level security;
alter table app.numbering_allocations enable row level security;

-- app.numbering_counters carries no tenant_id of its own (it is keyed off a
-- config_version, which may be shared across scope levels) -- no direct authenticated
-- grant at all; every real read path is through app.numbering_allocations or the
-- dedicated RPCs above.
create policy numbering_allocations_select_scoped on app.numbering_allocations
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select, insert, update, delete on app.numbering_counters to service_role;
grant select on app.numbering_allocations to authenticated, service_role;
grant insert, update, delete on app.numbering_allocations to service_role;

grant execute on function app.validate_numbering_definition(uuid) to service_role;
grant execute on function app.publish_numbering_definition(uuid, uuid, timestamptz, text) to service_role;
grant execute on function app.format_numbering_value(text, integer, integer, text, timestamptz) to authenticated, service_role;
grant execute on function app.allocate_numbering_seq(uuid, text, text) to service_role;
grant execute on function app.bootstrap_numbering_counter(uuid, text, text, integer, uuid, text) to service_role;
grant execute on function app.check_numbering_allocation_authority(uuid, uuid) to service_role;
grant execute on function app.allocate_or_reserve_number(text, uuid, uuid, text, text, uuid, text, uuid, text) to service_role;
grant execute on function app.allocate_number(uuid, uuid, text, text, uuid, text, uuid, text) to service_role;
grant execute on function app.reserve_number(uuid, uuid, text, text, uuid, text, uuid, text) to service_role;
grant execute on function app.confirm_number_reservation(uuid, uuid, text) to service_role;
grant execute on function app.release_number_reservation(uuid, uuid, text, text) to service_role;
grant execute on function app.void_number_allocation(uuid, uuid, text, text) to service_role;
grant execute on function app.get_numbering_allocation_status(uuid, uuid) to authenticated, service_role;
