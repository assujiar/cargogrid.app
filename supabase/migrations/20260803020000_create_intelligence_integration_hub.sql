-- Phase 9 IAE-008 (Integration Hub, Prompt 336, CG-S14-IAE-008) -- a
-- catalog/credential/health/ownership GOVERNANCE layer for case-by-case
-- third-party adapters. Second and last capability of Batch 2.
--
-- ===========================================================================
-- Design decisions (cited, not re-derived)
-- ===========================================================================
--
-- 1. **Governance layer only, never a protocol abstraction** -- `ADR-0025`
--    Part C already ratified this exact reading of Prompt 336's own text
--    against `RPD-038` ("Non-AI third-party integrations are custom and
--    have no generic provider abstraction... implemented case by case in
--    the shared product codebase"). This migration builds a catalog
--    (`app.integration_adapters`), a tenant's own configured instance of
--    one adapter (`app.integration_connections`), a fully isolated
--    credential store, and a real health-check history -- it never
--    implements a single third-party protocol call. Prompts 342-346 remain
--    case-by-case adapters that each register themselves into this catalog
--    (a future per-adapter task, disclosed not built here).
-- 2. **Module code `INTHUB`, already seeded by `IAE-007`
--    (`20260803010000_create_intelligence_automation_rule_engine.sql`).**
--    Confirmed by `01_MODULE_DEPENDENCY_MAP.md` §2.1: `INTHUB` owns
--    Prompts 335-341 as one module. No new `app.entitlement_modules`/
--    `app.permissions` row is needed -- `INTHUB:Configure`/`INTHUB:View`
--    (already seeded) are reused directly, the same two actions IAE-007
--    already gates its own mutations with.
-- 3. **The credential store is intentionally STRONGER isolation than the
--    closest pre-existing precedent, not a copy of it.**
--    `app.third_party_provider_connections.webhook_secret_value`
--    (`20260729380000_create_advanced_tms_third_party_provider_adapter.sql`)
--    stores a raw secret in the SAME table `authenticated` already holds
--    `grant select` on (protected only by the TS service layer's own
--    column-list discipline, never `select("*")` -- confirmed by direct
--    inspection: that table's own comment claims "zero authenticated/anon
--    grant" but the migration's own grant statement contradicts it,
--    disclosed here as an observed, PRE-EXISTING, out-of-scope condition,
--    not fixed by this checkpoint). This migration instead puts the raw
--    credential value in ITS OWN separate table
--    (`app.integration_connection_credentials`), RLS-enabled with ZERO
--    policies and ZERO grant to `authenticated`/`anon` at all -- not even
--    row-scoped. Only a `SECURITY DEFINER` function (executing as the
--    function owner, which bypasses RLS the same way every other
--    `SECURITY DEFINER` function in this repository already relies on) can
--    ever touch it. A raw `select("*")` on `app.integration_connections`
--    can structurally never leak a credential, because the credential is
--    not a column of that table at all.
-- 4. **Health is a real, queryable append-only history
--    (`app.integration_health_checks`), not only a mutable "last status"
--    snapshot.** The auto-disable threshold (10 consecutive failures)
--    mirrors `app.webhook_endpoints`'s own already-ratified `ADR-0011`
--    threshold exactly -- reused, not re-derived. `app.record_integration_
--    health_check` is caller-supplied-result (INTHUB:Configure-gated, the
--    "Test connection" UI action Prompt 336 §21's own Main flow describes)
--    -- an automated live poller that calls out to the real third-party
--    endpoint is disclosed `NOT_RUN`, the same standing "no live
--    worker/poller exists anywhere in this repository yet" condition every
--    prior job-queue/webhook-delivery capability already discloses.
-- 5. **Disabling a connection is a real, checkable state
--    (`app.check_integration_connection_active`), not merely a status
--    label with no consumer.** No adapter beyond the pre-existing,
--    separate GPS connection table currently exists to call it (disclosed,
--    matches design decision 1) -- but the guard function itself is real
--    and proven directly: a disabled connection's own guard call returns
--    `false`, an active one returns `true`, live-tested in the db-test.
-- 6. **`app.integration_adapters` is a registry, not a fixed CHECK enum**,
--    mirroring `app.config_types`/`app.notification_types`/`app.webhook_
--    event_types`'s own already-established "future capabilities add real
--    values via a Supreme-gated register function, never a schema
--    migration" convention -- reused, not reinvented. **Self-caught
--    correction (repository-wide `rbac-enforcement.sql` sweep, ATW-032/
--    ISS-2026-032, caught live before commit):** `app.register_integration_
--    adapter`'s own `app.is_supreme_admin(p_actor_auth_user_id)` check
--    validates the CLAIMED actor, never the calling session -- granting it
--    to `authenticated` would let any session pass a Supreme Admin's own
--    UUID and act as them. Fixed by granting `service_role` only, matching
--    every prior registry-registration function's own identical grant
--    exactly (`register_notification_type`/`register_config_type`/
--    `register_webhook_event_type` are all `service_role`-only for the
--    same reason).
-- 7. **Owner/runbook linkage is a genuinely new primitive** -- no prior
--    migration carries an accountable-owner or runbook-URL column on any
--    operational resource (confirmed by direct grep before writing this
--    migration; the only existing "runbook" convention in this repository
--    is a static markdown document under `docs/runbooks/`, never DB-linked).
--    `owner_team`/`owner_email`/`runbook_url` are plain, loosely-validated
--    text columns -- deliberately simple, not a new accountable-identity
--    subsystem.
-- 8. **`customer_user`-layer/C-05 discipline applied proactively from the
--    first draft**, applying this same phase's own Batch 1 Tier C lessons
--    rather than rediscovering them (mirrors `IAE-007`'s own identical
--    discipline).
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke
-- execute on all functions in schema app from public` before its final
-- grants.

-- ===========================================================================
-- 1. app.integration_adapters -- the catalog registry.
-- ===========================================================================

create table app.integration_adapters (
  code text primary key,
  name text not null,
  category text not null,
  owner_primitive_code text not null default 'INTHUB',
  registered_by text,
  created_at timestamptz not null default now()
);

comment on table app.integration_adapters is
  'IAE-008: the catalog of registered third-party adapter TYPES (Prompt 336 §20 "adapter registry"). A registry, not a fixed CHECK enum (design decision 6) -- mirrors app.config_types/app.notification_types/app.webhook_event_types exactly. category is a free, disclosed grouping label (e.g. communication/telematics/financial/automation), not a closed taxonomy.';

create function app.register_integration_adapter(
  p_code text,
  p_name text,
  p_category text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.integration_adapters
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.integration_adapters;
  v_adapter app.integration_adapters;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register an integration adapter'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.integration_adapters where code = p_code;
  if found then
    return v_existing;
  end if;

  if coalesce(length(trim(p_code)), 0) = 0 or coalesce(length(trim(p_name)), 0) = 0 or coalesce(length(trim(p_category)), 0) = 0 then
    raise exception 'integration_adapter_missing_field: code, name and category are all required'
      using errcode = 'check_violation';
  end if;

  insert into app.integration_adapters (code, name, category, registered_by)
  values (p_code, p_name, p_category, p_registered_by)
  returning * into v_adapter;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_integration_adapter',
    'app.integration_adapters', null, 'success', null, null, to_jsonb(v_adapter)
  );

  return v_adapter;
end;
$$;

comment on function app.register_integration_adapter is
  'IAE-008: Supreme-Admin-only, idempotent by code -- mirrors app.register_notification_type/app.register_config_type/app.register_webhook_event_type''s own identical shape exactly.';

-- ===========================================================================
-- 2. app.integration_connections -- a tenant's own configured instance of
-- one adapter. No config-version draft/publish ceremony (design choice,
-- disclosed): unlike a shared workflow/approval/automation-rule DEFINITION
-- that must be reviewed before it takes effect, a connection's own
-- settings take effect immediately by nature (an updated API base URL is
-- simply in use from that point on) -- record_version + app.audit_logs
-- already give a complete, queryable change history without the heavier
-- CFG draft/publish machinery.
-- ===========================================================================

create table app.integration_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  adapter_code text not null references app.integration_adapters (code),
  name text not null,
  environment text not null default 'production',
  status text not null default 'active',
  owner_team text,
  owner_email text,
  runbook_url text,
  config jsonb not null default '{}'::jsonb,
  consecutive_failure_count integer not null default 0,
  last_health_check_at timestamptz,
  last_health_status text,
  auto_disabled_at timestamptz,
  disabled_reason text,
  created_by_auth_user_id uuid references auth.users (id),
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint integration_connections_environment_check check (environment in ('sandbox', 'production')),
  constraint integration_connections_status_check check (status in ('active', 'disabled', 'testing')),
  constraint integration_connections_health_status_check check (last_health_status is null or last_health_status in ('healthy', 'unhealthy')),
  constraint integration_connections_failure_count_check check (consecutive_failure_count >= 0),
  constraint integration_connections_tenant_adapter_env_unique unique (tenant_id, adapter_code, environment)
);

comment on table app.integration_connections is
  'IAE-008: one tenant''s own configured instance of one registered adapter, scoped by environment (sandbox/production may coexist). config holds non-secret settings only (base URL, feature toggles, ...) -- the credential itself lives in the fully isolated app.integration_connection_credentials (design decision 3), never a column here.';

create index integration_connections_tenant_id_idx on app.integration_connections (tenant_id);
create index integration_connections_adapter_code_idx on app.integration_connections (adapter_code);

create function app.touch_integration_connection_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger integration_connections_touch_row
  before update on app.integration_connections
  for each row
  execute function app.touch_integration_connection_row();

-- ===========================================================================
-- 3. app.integration_connection_credentials -- fully isolated, RLS-enabled
-- with ZERO policies and ZERO grant to authenticated/anon (design decision
-- 3). Only a SECURITY DEFINER function (running as its own owner, which
-- bypasses RLS the same way every SECURITY DEFINER function in this
-- repository already relies on) can ever read or write this table.
-- ===========================================================================

create table app.integration_connection_credentials (
  connection_id uuid primary key references app.integration_connections (id),
  credential_value text not null,
  created_by_auth_user_id uuid references auth.users (id),
  created_at timestamptz not null default now(),
  rotated_at timestamptz
);

comment on table app.integration_connection_credentials is
  'IAE-008: the raw credential value for one connection, in its own physically separate table with zero authenticated/anon grant and zero RLS policy (design decision 3) -- a raw select("*") on app.integration_connections can structurally never expose this, unlike the closest pre-existing precedent (app.third_party_provider_connections.webhook_secret_value), disclosed rather than copied.';

alter table app.integration_connection_credentials enable row level security;

-- ===========================================================================
-- 4. app.integration_health_checks -- append-only health-check history
-- (design decision 4).
-- ===========================================================================

create table app.integration_health_checks (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references app.integration_connections (id),
  status text not null,
  detail text,
  checked_by text,
  checked_at timestamptz not null default now(),
  constraint integration_health_checks_status_check check (status in ('healthy', 'unhealthy'))
);

create index integration_health_checks_connection_id_idx on app.integration_health_checks (connection_id, checked_at desc);

-- ===========================================================================
-- 5. Connection lifecycle: create / update config / rotate credential /
-- set status / record health check / check-active guard.
-- ===========================================================================

create function app.create_integration_connection(
  p_tenant_id uuid,
  p_adapter_code text,
  p_name text,
  p_environment text,
  p_owner_team text,
  p_owner_email text,
  p_runbook_url text,
  p_config jsonb,
  p_credential_value text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_connection app.integration_connections;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.integration_adapters where code = p_adapter_code) then
    raise exception 'integration_adapter_unknown: % is not a registered integration adapter', p_adapter_code
      using errcode = 'check_violation';
  end if;

  if coalesce(length(trim(p_name)), 0) = 0 then
    raise exception 'integration_connection_missing_name: a non-empty name is required' using errcode = 'check_violation';
  end if;
  if coalesce(length(trim(p_credential_value)), 0) = 0 then
    raise exception 'integration_connection_missing_credential: a non-empty credential_value is required' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(coalesce(p_config, '{}'::jsonb)) then
    raise exception 'integration_connection_unsafe_config: config failed structural validation' using errcode = 'check_violation';
  end if;

  insert into app.integration_connections (
    tenant_id, adapter_code, name, environment, owner_team, owner_email, runbook_url, config,
    created_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_adapter_code, p_name, coalesce(p_environment, 'production'), p_owner_team, p_owner_email, p_runbook_url, coalesce(p_config, '{}'::jsonb),
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_connection;

  insert into app.integration_connection_credentials (connection_id, credential_value, created_by_auth_user_id)
  values (v_connection.id, p_credential_value, p_actor_auth_user_id);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_integration_connection',
    'app.integration_connections', v_connection.id, 'success', null, null,
    jsonb_build_object('adapter_code', v_connection.adapter_code, 'environment', v_connection.environment)
  );

  return v_connection;
end;
$$;

comment on function app.create_integration_connection is
  'IAE-008: INTHUB:Configure-gated. Creates the connection plus its own isolated credential row in one transaction. The credential value is never included in the returned app.integration_connections row (it is not a column of that table) or in the captured audit event (design decision 3).';

create function app.update_integration_connection_config(
  p_connection_id uuid,
  p_config jsonb,
  p_owner_team text,
  p_owner_email text,
  p_runbook_url text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_connection app.integration_connections;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_connection from app.integration_connections where id = p_connection_id for update;
  if not found then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_connection.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_connection.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_connection.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_config_value(coalesce(p_config, '{}'::jsonb)) then
    raise exception 'integration_connection_unsafe_config: config failed structural validation' using errcode = 'check_violation';
  end if;

  update app.integration_connections
  set config = coalesce(p_config, '{}'::jsonb), owner_team = p_owner_team, owner_email = p_owner_email, runbook_url = p_runbook_url
  where id = p_connection_id
  returning * into v_connection;

  perform app.capture_audit_event(
    v_connection.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_integration_connection_config',
    'app.integration_connections', v_connection.id, 'success', null, null, jsonb_build_object('config', v_connection.config)
  );

  return v_connection;
end;
$$;

comment on function app.update_integration_connection_config is
  'IAE-008: INTHUB:Configure-gated. Locks the connection row for update before deciding (C-04). Updates non-secret config/owner/runbook fields only -- never touches the credential (use app.rotate_integration_connection_credential for that).';

create function app.rotate_integration_connection_credential(
  p_connection_id uuid,
  p_new_credential_value text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_connection app.integration_connections;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_connection from app.integration_connections where id = p_connection_id;
  if not found then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_connection.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_connection.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_connection.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(length(trim(p_new_credential_value)), 0) = 0 then
    raise exception 'integration_connection_missing_credential: a non-empty credential_value is required' using errcode = 'check_violation';
  end if;

  update app.integration_connection_credentials
  set credential_value = p_new_credential_value, rotated_at = now()
  where connection_id = p_connection_id;

  perform app.capture_audit_event(
    v_connection.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_integration_connection_credential',
    'app.integration_connections', v_connection.id, 'success', null, null, '{}'::jsonb
  );

  return v_connection;
end;
$$;

comment on function app.rotate_integration_connection_credential is
  'IAE-008: INTHUB:Configure-gated. The caller supplies the new credential value directly (this is a housekeeping/rotation action, not a generation one -- unlike app.rotate_third_party_provider_webhook_secret, which generates its own value because a webhook signing secret has no external source to type in). Never returns or audits the credential value itself.';

create function app.set_integration_connection_status(
  p_connection_id uuid,
  p_status text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_connection app.integration_connections;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_connection from app.integration_connections where id = p_connection_id for update;
  if not found then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_connection.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_connection.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_connection.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('active', 'disabled', 'testing') then
    raise exception 'integration_connection_invalid_status: % is not one of active/disabled/testing', p_status using errcode = 'check_violation';
  end if;

  update app.integration_connections
  set status = p_status,
      disabled_reason = case when p_status = 'disabled' then p_reason else null end,
      auto_disabled_at = case when p_status = 'disabled' then null else auto_disabled_at end,
      consecutive_failure_count = case when p_status = 'active' then 0 else consecutive_failure_count end
  where id = p_connection_id
  returning * into v_connection;

  perform app.capture_audit_event(
    v_connection.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_integration_connection_status',
    'app.integration_connections', v_connection.id, 'success', null, null, jsonb_build_object('status', p_status, 'reason', p_reason)
  );

  return v_connection;
end;
$$;

comment on function app.set_integration_connection_status is
  'IAE-008: INTHUB:Configure-gated. Manual disable/re-enable/test-mode. auto_disabled_at is cleared and the failure counter reset only on an explicit re-activation to active (never implicitly by moving to testing) -- "disabling stops new jobs while preserving evidence/history" (Prompt 336 §24): the connection row and every app.integration_health_checks row are never deleted, only the status changes.';

create function app.record_integration_health_check(
  p_connection_id uuid,
  p_status text,
  p_detail text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.integration_health_checks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_connection app.integration_connections;
  v_decision app.rbac_decision;
  v_check app.integration_health_checks;
  v_new_failure_count integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_connection from app.integration_connections where id = p_connection_id for update;
  if not found then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  if not (app.has_active_tenant_membership(v_connection.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_connection.tenant_id, 'INTHUB', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks INTHUB:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_connection.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('healthy', 'unhealthy') then
    raise exception 'integration_health_check_invalid_status: % is not one of healthy/unhealthy', p_status using errcode = 'check_violation';
  end if;

  insert into app.integration_health_checks (connection_id, status, detail, checked_by)
  values (p_connection_id, p_status, p_detail, p_actor_label)
  returning * into v_check;

  v_new_failure_count := case when p_status = 'unhealthy' then v_connection.consecutive_failure_count + 1 else 0 end;

  -- Auto-disable threshold (10 consecutive failures) mirrors app.webhook_
  -- endpoints' own already-ratified ADR-0011 threshold exactly (design
  -- decision 4) -- reused, not re-derived.
  update app.integration_connections
  set last_health_check_at = now(),
      last_health_status = p_status,
      consecutive_failure_count = v_new_failure_count,
      status = case when v_new_failure_count >= 10 and status = 'active' then 'disabled' else status end,
      auto_disabled_at = case when v_new_failure_count >= 10 and status = 'active' then now() else auto_disabled_at end,
      disabled_reason = case when v_new_failure_count >= 10 and status = 'active' then 'auto-disabled after 10 consecutive failed health checks' else disabled_reason end
  where id = p_connection_id;

  perform app.capture_audit_event(
    v_connection.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_integration_health_check',
    'app.integration_health_checks', v_check.id, 'success', null, null, jsonb_build_object('status', p_status)
  );

  return v_check;
end;
$$;

comment on function app.record_integration_health_check is
  'IAE-008: INTHUB:Configure-gated. Records a real, caller-supplied health-check RESULT (the "Test connection" UI action, Prompt 336 §21) -- an automated poller that performs the actual outbound call is disclosed NOT_RUN (design decision 4). Auto-disables an active connection at 10 consecutive unhealthy checks, mirroring ADR-0011''s own threshold.';

create function app.check_integration_connection_active(p_connection_id uuid)
returns boolean
language sql
stable
set search_path = app, pg_temp
as $$
  select coalesce((select status = 'active' from app.integration_connections where id = p_connection_id), false);
$$;

comment on function app.check_integration_connection_active is
  'IAE-008: a real, reusable guard (design decision 5) a future domain-owned job-enqueue path can call before doing work on behalf of a disabled connection. No caller exists yet anywhere in this repository (disclosed) -- proven directly against a real disabled/active connection in the db-test, not merely asserted to exist.';

-- ===========================================================================
-- 6. RLS -- tenant-scoped SELECT, customer_user-layer excluded from the
-- first draft (design decision 8). app.integration_adapters is a global,
-- non-sensitive catalog (mirrors app.notification_types/app.config_types'
-- own no-RLS/direct-grant shape). app.integration_connection_credentials
-- gets RLS enabled with ZERO policies and ZERO grant (design decision 3).
-- ===========================================================================

alter table app.integration_connections enable row level security;
alter table app.integration_health_checks enable row level security;

create policy integration_connections_select_scoped on app.integration_connections
  for select to authenticated
  using (
    app.has_active_tenant_membership(tenant_id, auth.uid())
    and not app.actor_holds_customer_user_layer(tenant_id, auth.uid())
  );

create policy integration_health_checks_select_scoped on app.integration_health_checks
  for select to authenticated
  using (
    exists (
      select 1 from app.integration_connections c
      where c.id = integration_health_checks.connection_id
        and app.has_active_tenant_membership(c.tenant_id, auth.uid())
        and not app.actor_holds_customer_user_layer(c.tenant_id, auth.uid())
    )
  );

-- ===========================================================================
-- 7. Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.integration_adapters to authenticated, service_role;
grant select on app.integration_connections to authenticated, service_role;
grant select on app.integration_health_checks to authenticated, service_role;
-- app.integration_connection_credentials: deliberately ZERO grant to
-- authenticated/anon, not even select (design decision 3).
grant select, insert, update on app.integration_connection_credentials to service_role;

-- service_role-only (never authenticated), matching every prior Supreme-
-- Admin-gated registry-registration function exactly (app.register_
-- notification_type/app.register_config_type/app.register_webhook_event_
-- type are all service_role-only for the identical reason) -- caught live
-- by the repository-wide rbac-enforcement.sql sweep (ATW-032/ISS-2026-032):
-- app.is_supreme_admin(p_actor_auth_user_id) validates the CLAIMED actor,
-- never the calling session, so granting this to authenticated would let
-- any session pass a Supreme Admin's own UUID and act as them.
grant execute on function app.register_integration_adapter(text, text, text, uuid, text) to service_role;
grant execute on function app.create_integration_connection(uuid, text, text, text, text, text, text, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_integration_connection_config(uuid, jsonb, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.rotate_integration_connection_credential(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_integration_connection_status(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_integration_health_check(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.check_integration_connection_active(uuid) to authenticated, service_role;
