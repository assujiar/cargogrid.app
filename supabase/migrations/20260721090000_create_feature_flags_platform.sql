-- Platform Core capability PLT-133 (Feature Flags, CG-S6-PLT-030)
-- Extends the Phase 0 flag foundation (scripts/feature-flags/flags.ts,
-- docs/standards/FEATURE_FLAG_STANDARDS.md, CG-S5-PH0-019/Prompt 98) into tenant-safe
-- Platform Core administration/evaluation, integrated with entitlement (PLT-106) and
-- audit (PLT-116). A feature flag *definition/target* is deliberately **not** a new
-- table family -- it is PLT-121's own `config_type='feature'` config_object/
-- config_version/config_items mechanism, reused directly (the same "shared mechanism,
-- not a fork" discipline PLT-120/122/124's own registries already established). This
-- migration adds only what the Configuration Engine does not already provide: the flag
-- catalogue, flag-specific structural validation of target dimensions, the
-- entitlement-aware server-authoritative evaluator, and a kill-switch convenience path.
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * **One dedicated `config_type` per flag (`'feature:' || flag_key`), minted via
--   `app.register_config_type()` from `app.register_feature_flag()`** -- the exact
--   `PLT-124` `app.register_status_set()` pattern, for the identical reason: the
--   generic `'feature'` type PLT-121 already seeded cannot host more than one
--   independently-versioned object per scope level (`config_objects_scope_unique`).
--   The originally-seeded generic `'feature'` type itself stays exactly what PLT-121
--   left it: an unused placeholder, exactly like `PLT-124`'s leftover generic
--   `'status'` type.
-- * **Feature flags support only `global`/`tenant` scope, not the full 6-level
--   precedence PLT-121's generic resolver walks.** Tech Arch's own flag dimensions
--   (Prompt 133 §61/scripts/feature-flags/flags.ts) are environment/tenant/rollout/
--   cohort/effective-date/kill -- an org-hierarchy company/branch/role/user precedence
--   was never one of them. `app.create_feature_flag_draft()`/`app.set_feature_flag_items()`
--   enforce this restriction structurally (reject any other scope_level), a deliberate,
--   disclosed narrowing of `config_objects_scope_shape_check`'s wider physical
--   allowance, not an oversight.
-- * **The kill switch and environment allowlist are global-only, structurally
--   non-overridable dimensions.** `app.set_feature_flag_items()` rejects any attempt to
--   set `kill_switch`/`environments` at `scope_level='tenant'` with a `check_violation`
--   -- not merely an evaluator-side precedence rule (which a future code path could get
--   wrong), but a database-enforced guarantee that no tenant-scoped override can ever
--   resurrect a platform-wide kill. This is this checkpoint's own considered resolution
--   of a real tension the Phase 0 evaluator's single-object precedence
--   (`scripts/feature-flags/flags.ts`'s `evaluate()`: kill switch checked unconditionally
--   first) did not have to face, since Platform Core's own config-engine precedence
--   model (most-specific-wins) would otherwise let a tenant override "un-kill" a global
--   emergency stop.
-- * **Bucketing is SQL-native (`md5`), not a port of `scripts/feature-flags/flags.ts`'s
--   `sha256`-based `bucketFor()`.** The two are not required to produce bit-identical
--   bucket assignments for the same tenant+flag -- Prompt 133 §14 names *this*
--   capability's own evaluator ("server evaluation authoritative") as the authority for
--   Platform Core flags; the Phase 0 TS module is untouched and remains available for
--   whatever its own existing (non-Platform-Core) callers are. Both are deterministic
--   and evenly distributed, which is the actual correctness property either needs.
-- * **`app.evaluate_feature_flag()` has no code path that can return anything other
--   than `{enabled, reason}`** -- it never touches `app.roles`/`app.role_assignments`/
--   any RLS policy/any entitlement *grant* (only a read-only entitlement *check*, which
--   can only narrow exposure, never widen it beyond what PLT-106 already allows). This
--   is Prompt 133 §16's "Flags cannot grant permission/module entitlement... " made
--   structurally true, not just a documented promise, the same "structurally
--   incapable" discipline `scripts/feature-flags/flags.ts`'s own header established at
--   Phase 0.
-- * **No real domain flag is seeded anywhere in this migration.** The one safe,
--   representative example (a synthetic `'platform.example_rollout'` flag) is
--   registered and exercised entirely inside `scripts/db-tests/feature-flags.sql`,
--   the identical "prove it in the db-test, not in permanent migration data" discipline
--   `PLT-122`/`124`'s own headers already applied.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

-- The flag catalogue -- one row per known flag_key, independent of any tenant/version.
-- module_code, when set, ties the flag to one of PLT-106's 9 business-domain modules
-- for entitlement-aware evaluation (see app.evaluate_feature_flag below) -- never a
-- foreign key into anything that itself grants access, only PLT-106's own read-only
-- evaluator.
create table app.feature_flags (
  flag_key text primary key,
  name text not null,
  description text,
  module_code text references app.entitlement_modules (code),
  registered_by text,
  created_at timestamptz not null default now(),
  constraint feature_flags_flag_key_format check (flag_key ~ '^[a-z][a-z0-9_.]{1,63}$')
);

comment on table app.feature_flags is
  'PLT-133: the registry of platform feature flags. Registering a flag also mints its own dedicated app.config_types row (code ''feature:<flag_key>'') via app.register_config_type() -- one flag needs independent versioning per scope level, the same reason PLT-124''s status sets each mint their own config_type. module_code, when set, is a read-only entitlement-check hook (app.evaluate_entitlement), never an authorization grant.';

create index feature_flags_module_code_idx on app.feature_flags (module_code) where module_code is not null;

create type app.feature_flag_decision as (
  enabled boolean,
  reason text,
  resolved_scope_level text,
  resolved_version_id uuid,
  evaluated_at timestamptz
);

comment on type app.feature_flag_decision is
  'PLT-133: the result of app.evaluate_feature_flag()/app.debug_feature_flag(). reason is one of: unknown_flag, module_not_entitled, unconfigured, kill_switch, environment_gate, tenant_override_deny, tenant_override_allow, cohort_mismatch, rollout_bucket, default -- the fixed, explainable precedence order this migration''s own evaluator implements, mirroring scripts/feature-flags/flags.ts''s EvaluationDecisionReason semantics.';

-- Idempotent, Supreme-Admin-only -- the same registry-not-enum authority pattern every
-- prior *_types/*_sets registration function in this repository already uses.
create function app.register_feature_flag(
  p_flag_key text,
  p_name text,
  p_description text,
  p_module_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.feature_flags
language plpgsql
as $$
declare
  v_existing app.feature_flags;
  v_flag app.feature_flags;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a feature flag'
      using errcode = 'insufficient_privilege';
  end if;

  if p_module_code is not null and not exists (select 1 from app.entitlement_modules where code = p_module_code) then
    raise exception 'feature_flag_unknown_module: % is not a registered entitlement module', p_module_code
      using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.feature_flags where flag_key = p_flag_key;
  if found then
    return v_existing;
  end if;

  insert into app.feature_flags (flag_key, name, description, module_code, registered_by)
  values (p_flag_key, p_name, p_description, p_module_code, p_registered_by)
  returning * into v_flag;

  perform app.register_config_type('feature:' || p_flag_key, p_name, 'FLAG', p_actor_auth_user_id, p_registered_by);

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_feature_flag',
    'app.feature_flags', null, 'success', null, null, to_jsonb(v_flag)
  );

  return v_flag;
end;
$$;

-- Validating wrapper around app.create_config_draft -- rejects an unknown flag_key or a
-- scope_level outside {global, tenant} before delegating (this migration's own header
-- explains why). Authority (Supreme for global, tenant-admin/support-grant for tenant)
-- is enforced by the reused app.create_config_draft/app.check_config_object_authority,
-- not duplicated here.
create function app.create_feature_flag_draft(
  p_flag_key text,
  p_tenant_id uuid,
  p_scope_level text,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.config_versions
language plpgsql
as $$
begin
  if not exists (select 1 from app.feature_flags where flag_key = p_flag_key) then
    raise exception 'feature_flag_not_found: no feature flag %', p_flag_key
      using errcode = 'no_data_found';
  end if;

  if p_scope_level not in ('global', 'tenant') then
    raise exception 'feature_flag_invalid_scope: feature flags support only global/tenant scope, got %', p_scope_level
      using errcode = 'check_violation';
  end if;
  if p_scope_level = 'global' and p_tenant_id is not null then
    raise exception 'feature_flag_global_scope_no_tenant: a global-scope feature flag draft must not carry a tenant_id'
      using errcode = 'check_violation';
  end if;
  if p_scope_level = 'tenant' and p_tenant_id is null then
    raise exception 'feature_flag_tenant_scope_requires_tenant: a tenant-scope feature flag draft requires a tenant_id'
      using errcode = 'check_violation';
  end if;

  return app.create_config_draft('feature:' || p_flag_key, p_tenant_id, p_scope_level, null, p_actor_auth_user_id, p_created_by);
end;
$$;

-- Structural validation of the flag-specific target dimensions, then delegates to
-- app.set_config_items -- the only place kill_switch/environments are forced global-only
-- (this migration's own header). Global scope always carries a complete dimension set
-- (defaults applied); tenant scope only ever carries the dimensions actually overridden
-- (a null parameter means "inherit from global", proven in scripts/db-tests/feature-flags.sql).
create function app.set_feature_flag_items(
  p_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_kill_switch boolean default null,
  p_environments text[] default null,
  p_rollout_percentage integer default null,
  p_cohorts text[] default null,
  p_tenant_state text default null
)
returns integer
language plpgsql
as $$
declare
  v_version app.config_versions;
  v_object app.config_objects;
  v_items jsonb;
  v_known_environments text[] := array['local', 'development', 'testing', 'staging', 'uat', 'production', 'sandbox'];
  v_count integer;
begin
  select * into v_version from app.config_versions where id = p_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_version_id
      using errcode = 'no_data_found';
  end if;

  select * into v_object from app.config_objects where id = v_version.config_object_id;
  if v_object.config_type_code not like 'feature:%' then
    raise exception 'feature_flag_not_a_flag_version: version % does not belong to a feature flag object', p_version_id
      using errcode = 'check_violation';
  end if;

  if p_rollout_percentage is not null and (p_rollout_percentage < 0 or p_rollout_percentage > 100) then
    raise exception 'feature_flag_invalid_rollout_percentage: rollout_percentage must be between 0 and 100, got %', p_rollout_percentage
      using errcode = 'check_violation';
  end if;

  if v_object.scope_level = 'global' then
    if p_tenant_state is not null then
      raise exception 'feature_flag_global_scope_no_tenant_state: tenant_state may only be set at tenant scope'
        using errcode = 'check_violation';
    end if;
    if p_environments is not null and not (p_environments <@ v_known_environments) then
      raise exception 'feature_flag_invalid_environment: environments must be a subset of %', v_known_environments
        using errcode = 'check_violation';
    end if;

    v_items := jsonb_build_array(
      jsonb_build_object('key', 'kill_switch', 'value', to_jsonb(coalesce(p_kill_switch, false))),
      jsonb_build_object('key', 'environments', 'value', to_jsonb(coalesce(p_environments, array[]::text[]))),
      jsonb_build_object('key', 'rollout_percentage', 'value', to_jsonb(coalesce(p_rollout_percentage, 0))),
      jsonb_build_object('key', 'cohorts', 'value', to_jsonb(coalesce(p_cohorts, array[]::text[])))
    );
  elsif v_object.scope_level = 'tenant' then
    if p_kill_switch is not null or p_environments is not null then
      raise exception 'feature_flag_tenant_scope_no_kill_switch: kill_switch/environments are global-only, non-overridable dimensions'
        using errcode = 'check_violation';
    end if;
    if p_tenant_state is not null and p_tenant_state not in ('allow', 'deny', 'inherit') then
      raise exception 'feature_flag_invalid_tenant_state: tenant_state must be one of allow/deny/inherit, got %', p_tenant_state
        using errcode = 'check_violation';
    end if;

    v_items := jsonb_build_array(jsonb_build_object('key', 'tenant_state', 'value', to_jsonb(coalesce(p_tenant_state, 'inherit'))));
    if p_rollout_percentage is not null then
      v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'rollout_percentage', 'value', to_jsonb(p_rollout_percentage)));
    end if;
    if p_cohorts is not null then
      v_items := v_items || jsonb_build_array(jsonb_build_object('key', 'cohorts', 'value', to_jsonb(p_cohorts)));
    end if;
  else
    raise exception 'feature_flag_invalid_scope: feature flags support only global/tenant scope, got %', v_object.scope_level
      using errcode = 'check_violation';
  end if;

  v_count := app.set_config_items(p_version_id, v_items, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_object.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_feature_flag_items',
    'app.config_versions', p_version_id, 'success', null, null, jsonb_build_object('items', v_items)
  );

  return v_count;
end;
$$;

-- Deterministic [0, 100) bucket assignment for tenant+flag_key (SQL-native md5, see this
-- migration's own header for why it need not bit-match scripts/feature-flags/flags.ts's
-- sha256 bucketFor()). Casting a 32-bit bit string to bigint zero-extends (never
-- negative), so the modulo below is always in [0, 99].
create function app.feature_flag_bucket(p_bucket_key uuid, p_flag_key text)
returns integer
language sql
immutable
as $$
  select (('x' || substr(md5(p_bucket_key::text || ':' || p_flag_key), 1, 8))::bit(32)::bigint % 100)::integer;
$$;

-- The server-authoritative evaluator (Prompt 133 §14/§21-23). SECURITY DEFINER because
-- app.config_versions/app.config_items carry no direct authenticated grant at all (the
-- same posture PLT-121/122/124's own resolvers/evaluators already established) --
-- app.feature_flags/app.entitlement_modules/app.evaluate_entitlement are the real
-- security-relevant boundary for this call path, not a bypass.
create function app.evaluate_feature_flag(
  p_flag_key text,
  p_tenant_id uuid,
  p_environment text,
  p_cohorts text[] default array[]::text[],
  p_now timestamptz default now()
)
returns app.feature_flag_decision
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_flag app.feature_flags;
  v_entitlement app.entitlement_decision;
  v_global_object app.config_objects;
  v_global_version app.config_versions;
  v_global_items jsonb;
  v_tenant_object app.config_objects;
  v_tenant_version app.config_versions;
  v_tenant_items jsonb;
  v_environments text[];
  v_rollout integer;
  v_cohorts text[];
  v_tenant_state text;
  v_bucket integer;
  v_resolved_scope text;
  v_resolved_version uuid;
begin
  select * into v_flag from app.feature_flags where flag_key = p_flag_key;
  if not found then
    return row(false, 'unknown_flag', null, null, p_now)::app.feature_flag_decision;
  end if;

  if v_flag.module_code is not null and p_tenant_id is not null then
    v_entitlement := app.evaluate_entitlement(p_tenant_id, v_flag.module_code, null, p_now);
    if not v_entitlement.allowed then
      return row(false, 'module_not_entitled', null, null, p_now)::app.feature_flag_decision;
    end if;
  end if;

  select o.* into v_global_object from app.config_objects o
    where o.config_type_code = 'feature:' || p_flag_key and o.scope_level = 'global' and o.tenant_id is null;
  if not found then
    return row(false, 'unconfigured', null, null, p_now)::app.feature_flag_decision;
  end if;

  select v.* into v_global_version from app.config_versions v
    where v.config_object_id = v_global_object.id and v.status = 'published'
      and v.effective_from <= p_now and (v.effective_to is null or v.effective_to > p_now);
  if not found then
    return row(false, 'unconfigured', null, null, p_now)::app.feature_flag_decision;
  end if;

  select jsonb_object_agg(key, value) into v_global_items from app.config_items where config_version_id = v_global_version.id;

  if coalesce((v_global_items ->> 'kill_switch')::boolean, false) then
    return row(false, 'kill_switch', 'global', v_global_version.id, p_now)::app.feature_flag_decision;
  end if;

  select coalesce(array(select jsonb_array_elements_text(v_global_items -> 'environments')), array[]::text[]) into v_environments;
  if coalesce(array_length(v_environments, 1), 0) > 0 and not (p_environment = any (v_environments)) then
    return row(false, 'environment_gate', 'global', v_global_version.id, p_now)::app.feature_flag_decision;
  end if;

  v_rollout := coalesce((v_global_items ->> 'rollout_percentage')::integer, 0);
  select coalesce(array(select jsonb_array_elements_text(v_global_items -> 'cohorts')), array[]::text[]) into v_cohorts;
  v_resolved_scope := 'global';
  v_resolved_version := v_global_version.id;

  if p_tenant_id is not null then
    select o.* into v_tenant_object from app.config_objects o
      where o.config_type_code = 'feature:' || p_flag_key and o.scope_level = 'tenant' and o.tenant_id = p_tenant_id;
    if found then
      select v.* into v_tenant_version from app.config_versions v
        where v.config_object_id = v_tenant_object.id and v.status = 'published'
          and v.effective_from <= p_now and (v.effective_to is null or v.effective_to > p_now);
      if found then
        select jsonb_object_agg(key, value) into v_tenant_items from app.config_items where config_version_id = v_tenant_version.id;
        v_tenant_state := coalesce(v_tenant_items ->> 'tenant_state', 'inherit');
        v_resolved_scope := 'tenant';
        v_resolved_version := v_tenant_version.id;

        if v_tenant_state = 'deny' then
          return row(false, 'tenant_override_deny', 'tenant', v_tenant_version.id, p_now)::app.feature_flag_decision;
        elsif v_tenant_state = 'allow' then
          return row(true, 'tenant_override_allow', 'tenant', v_tenant_version.id, p_now)::app.feature_flag_decision;
        end if;

        if v_tenant_items ? 'rollout_percentage' then
          v_rollout := (v_tenant_items ->> 'rollout_percentage')::integer;
        end if;
        if v_tenant_items ? 'cohorts' then
          select coalesce(array(select jsonb_array_elements_text(v_tenant_items -> 'cohorts')), array[]::text[]) into v_cohorts;
        end if;
      end if;
    end if;
  end if;

  if coalesce(array_length(v_cohorts, 1), 0) > 0 then
    if p_cohorts is null or not (v_cohorts && p_cohorts) then
      return row(false, 'cohort_mismatch', v_resolved_scope, v_resolved_version, p_now)::app.feature_flag_decision;
    end if;
  end if;

  v_bucket := app.feature_flag_bucket(coalesce(p_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), p_flag_key);
  if v_bucket < v_rollout then
    return row(true, 'rollout_bucket', v_resolved_scope, v_resolved_version, p_now)::app.feature_flag_decision;
  end if;

  return row(false, 'default', v_resolved_scope, v_resolved_version, p_now)::app.feature_flag_decision;
end;
$$;

comment on function app.evaluate_feature_flag is
  'PLT-133: the fixed, explainable precedence order -- unknown flag -> entitlement -> unconfigured -> kill_switch -> environment_gate -> tenant deny/allow -> cohort_mismatch -> rollout_bucket -> default. Every branch returns only {enabled, reason} -- no code path in this function can grant a permission, module entitlement, or bypass RLS/validation (Prompt 133 §16), structurally, not by convention.';

-- The panic-button convenience path (Prompt 133 §20 task 4: "kill"). Force-sets
-- kill_switch=true on a fresh global draft while preserving the currently published
-- global version's other dimensions (never a silent reset of rollout/environments/
-- cohorts), then publishes immediately. Supreme-Admin-only -- the kill switch is a
-- global-only, non-overridable dimension (this migration's own header), so only the
-- authority that can touch global scope may pull it.
create function app.kill_feature_flag(
  p_flag_key text,
  p_actor_auth_user_id uuid,
  p_reason text,
  p_actor_label text
)
returns app.config_versions
language plpgsql
as $$
declare
  v_draft app.config_versions;
  v_published app.config_versions;
  v_result app.config_versions;
begin
  if not exists (select 1 from app.feature_flags where flag_key = p_flag_key) then
    raise exception 'feature_flag_not_found: no feature flag %', p_flag_key
      using errcode = 'no_data_found';
  end if;

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may kill a global feature flag'
      using errcode = 'insufficient_privilege';
  end if;

  v_draft := app.create_feature_flag_draft(p_flag_key, null, 'global', p_actor_auth_user_id, p_actor_label);

  select v.* into v_published
  from app.config_versions v
  join app.config_objects o on o.id = v.config_object_id
  where o.config_type_code = 'feature:' || p_flag_key and o.scope_level = 'global' and v.status = 'published';

  perform app.set_feature_flag_items(
    v_draft.id, p_actor_auth_user_id, p_actor_label,
    p_kill_switch => true,
    p_environments => (select coalesce(array(select jsonb_array_elements_text(ci.value)), array[]::text[]) from app.config_items ci where ci.config_version_id = v_published.id and ci.key = 'environments'),
    p_rollout_percentage => (select (ci.value #>> '{}')::integer from app.config_items ci where ci.config_version_id = v_published.id and ci.key = 'rollout_percentage'),
    p_cohorts => (select coalesce(array(select jsonb_array_elements_text(ci.value)), array[]::text[]) from app.config_items ci where ci.config_version_id = v_published.id and ci.key = 'cohorts')
  );

  v_result := app.publish_config_version(v_draft.id, p_actor_auth_user_id, now(), p_actor_label);

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'kill_feature_flag',
    'app.feature_flags', null, 'success', p_reason, null, jsonb_build_object('flag_key', p_flag_key)
  );

  return v_result;
end;
$$;

-- Privileged debug/explain path (Prompt 133 §14/§78: "debug... privileged access").
-- Authority mirrors app.check_config_object_authority's own split: Supreme for a
-- platform-wide (tenant_id null) debug call, support-grant authority (tenant_admin/
-- Supreme/an active support grant) for a tenant-scoped one -- reused, not reinvented.
-- Every call is itself audited, distinctly from the read-only app.evaluate_feature_flag
-- it wraps.
create function app.debug_feature_flag(
  p_flag_key text,
  p_tenant_id uuid,
  p_environment text,
  p_cohorts text[],
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.feature_flag_decision
language plpgsql
as $$
declare
  v_decision app.feature_flag_decision;
begin
  if p_tenant_id is null then
    if not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: only Supreme Admin may debug a platform-wide feature flag evaluation'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
      raise exception 'insufficient_authority: identity % lacks debug authority for tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  v_decision := app.evaluate_feature_flag(p_flag_key, p_tenant_id, p_environment, coalesce(p_cohorts, array[]::text[]));

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'debug_feature_flag',
    'app.feature_flags', null, 'success', v_decision.reason, null,
    jsonb_build_object('flag_key', p_flag_key, 'environment', p_environment, 'enabled', v_decision.enabled, 'resolved_scope_level', v_decision.resolved_scope_level)
  );

  return v_decision;
end;
$$;

alter table app.feature_flags enable row level security;

-- app.feature_flags is platform-owned reference data -- safe to expose broadly, the
-- same posture app.config_types/app.status_sets already established.
create policy feature_flags_select_authenticated on app.feature_flags
  for select to authenticated
  using (true);

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.feature_flags to authenticated, service_role;
grant insert, update, delete on app.feature_flags to service_role;
grant execute on function app.register_feature_flag(text, text, text, text, uuid, text) to service_role;
grant execute on function app.create_feature_flag_draft(text, uuid, text, uuid, text) to service_role;
grant execute on function app.set_feature_flag_items(uuid, uuid, text, boolean, text[], integer, text[], text) to service_role;
grant execute on function app.feature_flag_bucket(uuid, text) to service_role;
grant execute on function app.kill_feature_flag(text, uuid, text, text) to service_role;
grant execute on function app.debug_feature_flag(text, uuid, text, text[], uuid, text) to service_role;
-- Read-only, server-authoritative evaluation: SECURITY DEFINER (see the function's own
-- comment), granted to authenticated -- the flag-consuming application code path, the
-- same "resolver bypasses RLS internally, its own parameters are the boundary" pattern
-- PLT-121's app.resolve_config already established.
grant execute on function app.evaluate_feature_flag(text, uuid, text, text[], timestamptz) to authenticated, service_role;
