-- Intelligence, Automation and Enterprise Expansion: n8n Integration (IAE-013,
-- CG-S14-IAE-013, Prompt 341). Fifth and final prompt of Batch 3. n8n is
-- governed entirely through the ALREADY-BUILT `app.api_keys` (IAE-009) and
-- `app.webhook_endpoints` (PLT-129/IAE-012) primitives -- never a parallel
-- credential or trigger system -- per `RPD-012`'s own "n8n is not the primary
-- engine, an optional external trigger/consumer only" ruling and this
-- prompt's own business rule "No tenant-specific backend code is generated
-- for n8n."
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **n8n calls the SAME `/api/v1` REST surface every other API consumer
--    already calls (IAE-009/010/011), using an n8n-labeled `app.api_keys`
--    row; n8n receives events through the SAME `app.webhook_endpoints`
--    delivery mechanism every other webhook consumer already uses
--    (PLT-129/IAE-012).** No new REST route, no new webhook delivery
--    mechanism -- this migration adds ONLY the governance/labeling layer a
--    no-code external automation tool specifically needs on top of what
--    already exists.
-- 2. **`app.n8n_action_allowlist`: a NEW, small, Supreme-registered,
--    globally-readable catalog of `<module>:<action>` scope strings
--    considered safe for EXTERNAL no-code workflow automation** -- a
--    governance narrowing layered ON TOP of `app.create_api_key`'s own
--    already-existing "can only narrow the actor's own current RBAC, never
--    widen" rule (PLT-129), not a replacement for it: an n8n connector's own
--    requested scopes must pass BOTH checks. Seeded conservatively,
--    read-heavy (`OPS:View`, `PRC:View`, `TKT:View`, `TKT:Create`,
--    `INTHUB:View`, all confirmed real, already-registered `app.permissions`
--    rows) -- deliberately excludes every `Approve`/`Delete`/`Override`/
--    financial-posting scope repository-wide, so an n8n connector cannot
--    structurally be granted a scope capable of bypassing domain approval or
--    human governance (business rule 1). Mirrors `app.webhook_event_types`/
--    `app.api_versions`' own established "small Supreme-registered catalog"
--    shape.
-- 3. **`app.n8n_connectors`: one row per registered connector**, linking an
--    EXISTING `app.api_keys` row (1:1, the outbound action-half credential)
--    with an OPTIONAL EXISTING `app.webhook_endpoints` row (the inbound
--    trigger-half, the tenant's own n8n webhook URL) -- a pure
--    labeling/linking table, never a duplicate of either primitive's own
--    state (status/secret/scopes/delivery history all stay on the linked
--    rows, read live, never copied).
-- 4. **`app.create_n8n_connector`: extends, never forks, `app.create_api_key`
--    (PLT-129)** -- staff-only (`app.check_api_webhook_admin_authority`),
--    validates every requested scope against the allowlist (design decision
--    2) BEFORE delegating to the unmodified `app.create_api_key`, which
--    independently re-validates against the creating actor's own current
--    RBAC (`app.evaluate_permission`, unchanged) -- neither check alone is
--    sufficient, both must pass. The linked `webhook_endpoint_id`, if
--    provided, is validated to belong to the same tenant.
-- 5. **`app.revoke_n8n_connector` delegates to the EXISTING `app.revoke_api_key`
--    (PLT-129/IAE-010/011, unchanged)** for the underlying credential; the
--    connector's own linking row is left in place as a historical record,
--    matching how a revoked `app.api_keys` row is itself never deleted.
-- 6. **Execution audit reuses `app.api_logs` (IAE-009/010) for the
--    connector's own outbound API calls and `app.webhook_deliveries`/
--    `app.webhook_delivery_attempts` (PLT-129/IAE-012) for its own inbound
--    trigger deliveries** -- never a third, parallel audit trail. The
--    console UI's own execution-log view queries both, filtered by the
--    connector's own linked `api_key_id`/`webhook_endpoint_id`.
-- 7. **Sample workflows and the setup guide are pure documentation/UI**, not
--    a new backend surface -- `app/(tenant)/[tenantSlug]/admin/api-keys/`'s
--    own console gains an "n8n connectors" section with copy-pasteable
--    setup guidance, matching business rule "No tenant-specific backend code
--    is generated for n8n" literally.
-- 8. No new job type, no async work of its own.
-- 9. Per `ERR-2026-004`: this migration carries its own explicit
--    `revoke execute on all functions in schema app from public;` before its
--    final grants.

-- ===========================================================================
-- app.n8n_action_allowlist (design decision 2)
-- ===========================================================================

create table app.n8n_action_allowlist (
  scope text primary key,
  description text not null,
  registered_by text,
  created_at timestamptz not null default now(),
  constraint n8n_action_allowlist_scope_format_check check (scope ~ '^[A-Z]+:[A-Za-z ]+$')
);

comment on table app.n8n_action_allowlist is
  'IAE-013: Supreme-registered, globally-readable catalog of scope strings considered safe for EXTERNAL no-code workflow automation -- a narrowing layered on top of app.create_api_key''s own "can only narrow the actor''s own current RBAC, never widen" rule (PLT-129), never a replacement for it. Deliberately excludes every Approve/Delete/Override/financial-posting scope repository-wide.';

create function app.register_n8n_allowlisted_action(
  p_scope text,
  p_description text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.n8n_action_allowlist
language plpgsql
as $$
declare
  v_existing app.n8n_action_allowlist;
  v_row app.n8n_action_allowlist;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register an n8n allowlisted action'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.n8n_action_allowlist where scope = p_scope;
  if found then
    return v_existing;
  end if;

  if not exists (select 1 from app.permissions where code = p_scope) then
    raise exception 'n8n_scope_not_a_real_permission: % is not a registered app.permissions code', p_scope
      using errcode = 'check_violation';
  end if;

  insert into app.n8n_action_allowlist (scope, description, registered_by)
  values (p_scope, p_description, p_registered_by)
  returning * into v_row;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_n8n_allowlisted_action',
    'app.n8n_action_allowlist', null, 'success', null, null, to_jsonb(v_row)
  );

  return v_row;
end;
$$;

comment on function app.register_n8n_allowlisted_action is
  'IAE-013: Supreme-only, idempotent by scope. Rejects a scope that is not a real, already-registered app.permissions code -- the allowlist can only ever narrow a subset of REAL RBAC actions, never invent a fictional one.';

create function app.list_n8n_action_allowlist()
returns setof app.n8n_action_allowlist
language sql
stable
as $$
  select * from app.n8n_action_allowlist order by scope;
$$;

-- ===========================================================================
-- app.n8n_connectors (design decision 3)
-- ===========================================================================

create table app.n8n_connectors (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  api_key_id uuid not null references app.api_keys (id),
  webhook_endpoint_id uuid references app.webhook_endpoints (id),
  name text not null,
  created_by_auth_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint n8n_connectors_name_check check (length(trim(name)) > 0),
  constraint n8n_connectors_api_key_unique unique (api_key_id)
);

comment on table app.n8n_connectors is
  'IAE-013: one row per registered n8n connector, linking an EXISTING app.api_keys row (1:1, the outbound action-half credential) with an OPTIONAL EXISTING app.webhook_endpoints row (the inbound trigger-half) -- a pure labeling/linking table. status/secret/scopes/delivery history all stay on the linked rows, read live, never copied here.';

create index n8n_connectors_tenant_idx on app.n8n_connectors (tenant_id);

create function app.touch_n8n_connectors_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger n8n_connectors_touch_row
  before update on app.n8n_connectors
  for each row
  execute function app.touch_n8n_connectors_row();

-- ===========================================================================
-- app.create_n8n_connector (design decision 4)
-- ===========================================================================

create function app.create_n8n_connector(
  p_tenant_id uuid,
  p_name text,
  p_scopes jsonb,
  p_webhook_endpoint_id uuid,
  p_rate_limit_per_minute integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  connector_id uuid, api_key_id uuid, tenant_id uuid, name text, key_prefix text,
  scopes jsonb, status text, rate_limit_per_minute integer, webhook_endpoint_id uuid,
  created_at timestamptz, raw_key text
)
language plpgsql
as $$
declare
  v_scope text;
  v_key record;
  v_connector app.n8n_connectors;
begin
  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to create an n8n connector for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'n8n_connector_missing_name: p_name must not be empty' using errcode = 'check_violation';
  end if;

  if p_scopes is null or jsonb_typeof(p_scopes) <> 'array' or jsonb_array_length(p_scopes) = 0 then
    raise exception 'api_key_missing_scopes: at least one scope is required' using errcode = 'check_violation';
  end if;
  for v_scope in select * from jsonb_array_elements_text(p_scopes) loop
    if not exists (select 1 from app.n8n_action_allowlist where scope = v_scope) then
      raise exception 'n8n_scope_not_allowlisted: % is not on the n8n safe-action allowlist', v_scope
        using errcode = 'check_violation';
    end if;
  end loop;

  if p_webhook_endpoint_id is not null and not exists (
    select 1 from app.webhook_endpoints where app.webhook_endpoints.id = p_webhook_endpoint_id and app.webhook_endpoints.tenant_id = p_tenant_id
  ) then
    raise exception 'webhook_endpoint_not_found: no endpoint % in tenant %', p_webhook_endpoint_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  -- Extends, never forks, app.create_api_key (PLT-129) -- it independently
  -- re-validates every scope against the CREATING ACTOR's own current RBAC
  -- (app.evaluate_permission), a second, real check the allowlist above does
  -- not substitute for.
  select * into v_key from app.create_api_key(p_tenant_id, p_name, p_scopes, null, p_rate_limit_per_minute, p_actor_auth_user_id, p_actor_label);

  insert into app.n8n_connectors (tenant_id, api_key_id, webhook_endpoint_id, name, created_by_auth_user_id)
  values (p_tenant_id, v_key.id, p_webhook_endpoint_id, p_name, p_actor_auth_user_id)
  returning * into v_connector;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_n8n_connector',
    'app.n8n_connectors', v_connector.id, 'success', null, null,
    jsonb_build_object('id', v_connector.id, 'api_key_id', v_key.id, 'webhook_endpoint_id', p_webhook_endpoint_id)
  );

  return query select v_connector.id, v_key.id, v_key.tenant_id, v_connector.name, v_key.key_prefix, v_key.scopes, v_key.status, v_key.rate_limit_per_minute, v_connector.webhook_endpoint_id, v_connector.created_at, v_key.raw_key;
end;
$$;

comment on function app.create_n8n_connector is
  'IAE-013: staff-only. Every requested scope must pass BOTH app.n8n_action_allowlist (design decision 2) AND app.create_api_key''s own creating-actor RBAC re-check -- neither alone is sufficient. Returns the raw key exactly once, matching every other create_*_api_key precedent.';

-- ===========================================================================
-- app.revoke_n8n_connector (design decision 5)
-- ===========================================================================

create function app.revoke_n8n_connector(
  p_connector_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.api_keys
language plpgsql
as $$
declare
  v_connector app.n8n_connectors;
  v_revoked app.api_keys;
begin
  select * into v_connector from app.n8n_connectors where id = p_connector_id;
  if not found then
    raise exception 'n8n_connector_not_found: no connector %', p_connector_id using errcode = 'no_data_found';
  end if;

  -- Delegates to the EXISTING app.revoke_api_key (PLT-129/IAE-010/011,
  -- unchanged) -- its own authority check (app.check_api_key_manage_authority)
  -- is the real boundary; this function adds no authority logic of its own.
  select * into v_revoked from app.revoke_api_key(v_connector.api_key_id, p_reason, p_actor_auth_user_id, p_actor_label);
  return v_revoked;
end;
$$;

comment on function app.revoke_n8n_connector is
  'IAE-013: delegates entirely to app.revoke_api_key -- the connector''s own linking row is left in place as a historical record, matching how a revoked app.api_keys row is itself never deleted.';

-- ===========================================================================
-- app.list_n8n_connectors_for_tenant (design decision 6)
-- ===========================================================================

create function app.list_n8n_connectors_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  connector_id uuid, api_key_id uuid, tenant_id uuid, name text, key_prefix text,
  scopes jsonb, status text, rate_limit_per_minute integer, last_used_at timestamptz,
  webhook_endpoint_id uuid, webhook_endpoint_url text, webhook_endpoint_status text,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view n8n connectors for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select c.id, k.id, c.tenant_id, c.name, k.key_prefix, k.scopes, k.status, k.rate_limit_per_minute, k.last_used_at,
         c.webhook_endpoint_id, e.url, e.status, c.created_at, c.updated_at
  from app.n8n_connectors c
  join app.api_keys k on k.id = c.api_key_id
  left join app.webhook_endpoints e on e.id = c.webhook_endpoint_id
  where c.tenant_id = p_tenant_id
  order by c.created_at desc;
end;
$$;

comment on function app.list_n8n_connectors_for_tenant is
  'IAE-013: staff-only, joined live with the linked app.api_keys/app.webhook_endpoints rows -- never a copy of their own state. security definer, calls app.assert_actor_is_session_identity first (ATW-032 discipline, applied proactively).';

-- ===========================================================================
-- Real allowlist seed (design decision 2) -- direct insert at migration-apply
-- time, mirroring app.api_versions'/app.webhook_event_types' own seeding
-- precedent (IAE-009/012).
-- ===========================================================================

insert into app.n8n_action_allowlist (scope, description, registered_by) values
  ('OPS:View', 'Read shipment/operations data -- safe, read-only', 'phase-09-foundation'),
  ('PRC:View', 'Read procurement/vendor data -- safe, read-only', 'phase-09-foundation'),
  ('TKT:View', 'Read support ticket data -- safe, read-only', 'phase-09-foundation'),
  ('TKT:Create', 'Create a support ticket -- reversible, no approval required', 'phase-09-foundation'),
  ('INTHUB:View', 'Read integration/webhook/API platform data -- safe, read-only', 'phase-09-foundation');

-- ===========================================================================
-- Grants
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.register_n8n_allowlisted_action(text, text, uuid, text) to service_role;
grant execute on function app.list_n8n_action_allowlist() to authenticated, service_role;
grant execute on function app.create_n8n_connector(uuid, text, jsonb, uuid, integer, uuid, text) to service_role;
grant execute on function app.revoke_n8n_connector(uuid, text, uuid, text) to service_role;
grant execute on function app.list_n8n_connectors_for_tenant(uuid, uuid) to authenticated, service_role;
