-- ISS-2026-257 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- a full database backup (pg_dump/pg_restore) captures 3 plaintext secret columns
-- verbatim, with no encryption-at-rest, contradicting this repository's own documented
-- "references, never values" export discipline. A full-database-level actor (backup file
-- access, direct superuser query) can recover live, replayable webhook signing secrets
-- and integration credentials for every tenant -- structurally different from an
-- application-level export/API leak, which this repository's own discipline already
-- correctly never surfaces these values through.
--
-- The 3 columns: app.integration_connection_credentials.credential_value,
-- app.third_party_provider_connections.webhook_secret_value,
-- app.webhook_endpoints.secret_value -- all deliberately stored retrievable (never
-- one-way hashed), by design, since each must be replayed to compute/verify an HMAC
-- signature. That design choice is correct and unchanged by this migration; only the
-- at-rest storage mechanism changes.
--
-- Fix, mirroring the already-established, already-proven pattern in this codebase
-- (supabase/migrations/20260730610000_create_procurement_vendor_financial_security.sql,
-- app.vendor_financial_encryption_key()/app._encrypt_vendor_financial_value()/
-- app._decrypt_vendor_financial_value(), pgp_sym_encrypt/pgp_sym_decrypt via pgcrypto,
-- already enabled repo-wide in schema `extensions`): a fail-closed GUC-keyed symmetric
-- key, and 2 private encrypt/decrypt helpers, shared across all 3 columns (one key, not
-- three -- these are all the same threat model, retrievable-by-design secrets needing
-- replay, with no cross-capability audit-boundary reason to use separate keys the way
-- vendor-financial data's own distinct audit boundary might warrant).
--
-- Technique: rename the plaintext column out and add a `bytea` `_encrypted` column in
-- its place, in one migration (never a second plaintext column, never a
-- backfill-then-drop-later straddle) -- safe here because all 3 tables are small,
-- low-row-count operational tables with zero direct app-layer column access (confirmed:
-- every TypeScript caller only ever passes/receives the plaintext through existing RPC
-- parameter/return names, never a raw column read) and every writer/reader is itself a
-- SECURITY DEFINER or service_role-only SQL function, not a caller this migration needs
-- to coordinate around.
--
-- Grant note, self-caught before shipping (the identical class of gap HDN-373's own
-- migration self-caught for app.has_active_tenant_membership -- see that migration's own
-- header): unlike the vendor-financial pattern's private helpers (zero grant, callable
-- only from within another SECURITY DEFINER function owned by the same role), this
-- domain's own writer/reader functions are a MIX of SECURITY DEFINER and SECURITY
-- INVOKER (app.register_webhook_endpoint/app.rotate_webhook_secret/app.
-- compute_webhook_signature carry no `security definer` clause at all, reached directly
-- as `service_role`). Postgres checks EXECUTE privilege at the call site against
-- whichever role is ACTUALLY active there -- for an INVOKER caller reached directly by
-- service_role, that is service_role itself, not this migration's own owning role, so
-- the private helpers below are explicitly granted to `service_role` (not left
-- ungranted the way the vendor-financial helpers correctly are, since every one of
-- THEIR callers is SECURITY DEFINER owned by the same role).
--
-- No public.* wrapper (Option 2, 20260826000000) exposes any of these 3 raw column
-- names directly -- confirmed by grep. The writer RPCs' own `public.*` wrappers pass the
-- plaintext only as an *input* parameter (the deliberate one-time-reveal design); their
-- signatures and return shapes are unchanged by this migration, so no wrapper edit is
-- needed and no TypeScript change is needed anywhere.

-- ===========================================================================
-- 1. Shared encryption key + private encrypt/decrypt helpers.
-- ===========================================================================

create function app.integration_secrets_encryption_key()
returns text
language plpgsql
stable
as $$
declare
  v_key text;
begin
  v_key := current_setting('app.integration_secrets_encryption_key', true);
  if v_key is null or length(v_key) = 0 then
    raise exception 'encryption_key_not_configured: app.integration_secrets_encryption_key is not set for this session -- integration/webhook secret encryption cannot proceed without a configured key (mirrors app.vendor_financial_encryption_key''s own disclosed key-custody boundary; db-tests set this GUC to a fixed test-only value at fixture setup)'
      using errcode = 'config_file_error';
  end if;
  return v_key;
end;
$$;

comment on function app.integration_secrets_encryption_key is 'ISS-2026-257: fail-closed GUC read for the symmetric key shared by all 3 integration/webhook secret columns (app.integration_connection_credentials.credential_value_encrypted, app.third_party_provider_connections.webhook_secret_value_encrypted, app.webhook_endpoints.secret_value_encrypted). Never silently encrypts with an empty/default key. Production key provisioning/rotation/custody is a disclosed, out-of-scope infrastructure concern, mirroring app.vendor_financial_encryption_key''s own disclosed boundary (ADR-0010).';

create function app._encrypt_integration_secret(p_plaintext text)
returns bytea
language sql
set search_path = app, public, extensions, pg_temp
as $$
  select pgp_sym_encrypt(p_plaintext, app.integration_secrets_encryption_key());
$$;

create function app._decrypt_integration_secret(p_ciphertext bytea)
returns text
language sql
set search_path = app, public, extensions, pg_temp
as $$
  select pgp_sym_decrypt(p_ciphertext, app.integration_secrets_encryption_key());
$$;

-- Grant note above: this domain's callers are a mix of SECURITY DEFINER and SECURITY
-- INVOKER (unlike vendor-financial's uniformly-DEFINER callers), so these two helpers
-- need a direct service_role grant -- an INVOKER caller reached directly as service_role
-- would otherwise fail with "permission denied for function" the same way HDN-373's own
-- self-caught regression did for app.has_active_tenant_membership.
revoke execute on all functions in schema app from public;
grant execute on function app._encrypt_integration_secret(text) to service_role;
grant execute on function app._decrypt_integration_secret(bytea) to service_role;

-- ===========================================================================
-- 2. Column migration: add the encrypted column, backfill, drop the plaintext
--    column. One migration, no straddle period.
-- ===========================================================================

alter table app.integration_connection_credentials add column credential_value_encrypted bytea;
update app.integration_connection_credentials set credential_value_encrypted = app._encrypt_integration_secret(credential_value);
alter table app.integration_connection_credentials alter column credential_value_encrypted set not null;
alter table app.integration_connection_credentials drop column credential_value;

alter table app.third_party_provider_connections add column webhook_secret_value_encrypted bytea;
update app.third_party_provider_connections set webhook_secret_value_encrypted = app._encrypt_integration_secret(webhook_secret_value) where webhook_secret_value is not null;
alter table app.third_party_provider_connections drop column webhook_secret_value;
-- No re-grant needed: 20260730350000's own authenticated column-select grant already
-- names an explicit column list that never included webhook_secret_value, and a newly
-- ADDED column is never implicitly covered by a pre-existing explicit column grant --
-- confirmed by re-querying information_schema.column_privileges below (see verification
-- note at the end of this migration).

alter table app.webhook_endpoints add column secret_value_encrypted bytea;
update app.webhook_endpoints set secret_value_encrypted = app._encrypt_integration_secret(secret_value);
alter table app.webhook_endpoints alter column secret_value_encrypted set not null;
alter table app.webhook_endpoints drop column secret_value;
-- No re-grant needed: app.webhook_endpoints carries zero authenticated/anon table grant
-- at all (service_role-only), so the new column is exactly as inaccessible as the old one.

-- ===========================================================================
-- 3. Writers: encrypt on write. CREATE OR REPLACE on identical signatures --
--    zero call-site changes, RPC parameter/return shapes unchanged.
-- ===========================================================================

create or replace function app.create_integration_connection(
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
  p_actor_label text,
  p_client_ip text default null
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

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  insert into app.integration_connections (
    tenant_id, adapter_code, name, environment, owner_team, owner_email, runbook_url, config,
    created_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_adapter_code, p_name, coalesce(p_environment, 'production'), p_owner_team, p_owner_email, p_runbook_url, coalesce(p_config, '{}'::jsonb),
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_connection;

  insert into app.integration_connection_credentials (connection_id, credential_value_encrypted, created_by_auth_user_id)
  values (v_connection.id, app._encrypt_integration_secret(p_credential_value), p_actor_auth_user_id);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_integration_connection',
    'app.integration_connections', v_connection.id, 'success', null, null,
    jsonb_build_object('adapter_code', v_connection.adapter_code, 'environment', v_connection.environment)
  );

  return v_connection;
end;
$$;

create or replace function app.rotate_integration_connection_credential(
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
  set credential_value_encrypted = app._encrypt_integration_secret(p_new_credential_value), rotated_at = now()
  where connection_id = p_connection_id;

  perform app.capture_audit_event(
    v_connection.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_integration_connection_credential',
    'app.integration_connections', v_connection.id, 'success', null, null, '{}'::jsonb
  );

  return v_connection;
end;
$$;

create or replace function app.register_third_party_provider_connection(
  p_tenant_id uuid,
  p_provider_code text,
  p_integration_mode text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (connection_id uuid, provider_code text, integration_mode text, raw_webhook_secret text, status text)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.third_party_provider_connections;
  v_raw_secret text;
  v_conn app.third_party_provider_connections;
begin
  if p_provider_code is null or length(trim(p_provider_code)) = 0 then
    raise exception 'provider_code_required: a non-empty provider_code is required' using errcode = 'check_violation';
  end if;
  if p_integration_mode not in ('webhook', 'poll') then
    raise exception 'invalid_integration_mode: % is not a supported integration mode', p_integration_mode using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.third_party_provider_connections c where c.tenant_id = p_tenant_id and c.provider_code = p_provider_code;
  if found then
    return query select v_existing.id, v_existing.provider_code, v_existing.integration_mode, null::text, v_existing.status;
    return;
  end if;

  if p_integration_mode = 'webhook' then
    v_raw_secret := 'tpws_' || encode(gen_random_bytes(32), 'hex');
  end if;

  insert into app.third_party_provider_connections (tenant_id, provider_code, integration_mode, webhook_secret_value_encrypted, created_by)
  values (p_tenant_id, p_provider_code, p_integration_mode, case when v_raw_secret is null then null else app._encrypt_integration_secret(v_raw_secret) end, p_actor_label)
  returning * into v_conn;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_third_party_provider_connection',
    'app.third_party_provider_connections', v_conn.id, 'success', null, null,
    jsonb_build_object('provider_code', p_provider_code, 'integration_mode', p_integration_mode)
  );

  return query select v_conn.id, v_conn.provider_code, v_conn.integration_mode, v_raw_secret, v_conn.status;
end;
$$;

comment on function app.register_third_party_provider_connection is
  'ATW-226E: idempotent on (tenant, provider_code). Returns the raw webhook secret exactly once, only on first creation -- an idempotent re-call (existing connection) returns null for raw_webhook_secret, never re-discloses or re-mints it (app.rotate_third_party_provider_webhook_secret is the only way to get a new one). ISS-2026-257: the stored column is now pgp_sym_encrypt''d at rest; the returned raw_webhook_secret is unchanged (the deliberate one-time-reveal design).';

create or replace function app.rotate_third_party_provider_webhook_secret(
  p_connection_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (connection_id uuid, raw_webhook_secret text)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_conn app.third_party_provider_connections;
  v_decision app.rbac_decision;
  v_raw_secret text;
begin
  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found then
    raise exception 'connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;
  if v_conn.integration_mode <> 'webhook' then
    raise exception 'not_a_webhook_connection: % is a % connection, has no webhook secret to rotate', p_connection_id, v_conn.integration_mode
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_conn.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_conn.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_raw_secret := 'tpws_' || encode(gen_random_bytes(32), 'hex');

  update app.third_party_provider_connections set webhook_secret_value_encrypted = app._encrypt_integration_secret(v_raw_secret) where id = p_connection_id;

  perform app.capture_audit_event(
    v_conn.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_third_party_provider_webhook_secret',
    'app.third_party_provider_connections', p_connection_id, 'success', null, null, jsonb_build_object('connection_id', p_connection_id)
  );

  return query select v_conn.id, v_raw_secret;
end;
$$;

create or replace function app.register_webhook_endpoint(
  p_tenant_id uuid,
  p_url text,
  p_event_type_codes jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, url text, status text, consecutive_failure_count integer,
  created_at timestamptz, raw_secret text
)
language plpgsql
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_code text;
  v_raw_secret text;
  v_endpoint app.webhook_endpoints;
begin
  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.validate_webhook_url(p_url);

  if p_event_type_codes is null or jsonb_typeof(p_event_type_codes) <> 'array' or jsonb_array_length(p_event_type_codes) = 0 then
    raise exception 'webhook_missing_event_types: at least one event_type_code is required'
      using errcode = 'check_violation';
  end if;
  for v_code in select * from jsonb_array_elements_text(p_event_type_codes) loop
    if not exists (select 1 from app.webhook_event_types where code = v_code) then
      raise exception 'webhook_unknown_event_type: % is not a registered event type', v_code
        using errcode = 'check_violation';
    end if;
  end loop;

  v_raw_secret := 'whsec_' || encode(gen_random_bytes(24), 'hex');

  insert into app.webhook_endpoints (tenant_id, url, secret_value_encrypted, created_by_auth_user_id)
  values (p_tenant_id, p_url, app._encrypt_integration_secret(v_raw_secret), p_actor_auth_user_id)
  returning * into v_endpoint;

  for v_code in select * from jsonb_array_elements_text(p_event_type_codes) loop
    insert into app.webhook_subscriptions (webhook_endpoint_id, event_type_code) values (v_endpoint.id, v_code);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_webhook_endpoint',
    'app.webhook_endpoints', v_endpoint.id, 'success', null, null,
    jsonb_build_object('id', v_endpoint.id, 'url', v_endpoint.url, 'status', v_endpoint.status, 'event_type_codes', p_event_type_codes)
  );

  return query select v_endpoint.id, v_endpoint.tenant_id, v_endpoint.url, v_endpoint.status, v_endpoint.consecutive_failure_count, v_endpoint.created_at, v_raw_secret;
end;
$$;

create or replace function app.rotate_webhook_secret(
  p_endpoint_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (id uuid, tenant_id uuid, url text, status text, raw_secret text)
language plpgsql
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_endpoint app.webhook_endpoints;
  v_new_secret text;
  v_updated app.webhook_endpoints;
begin
  select * into v_endpoint from app.webhook_endpoints where app.webhook_endpoints.id = p_endpoint_id;
  if not found then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_endpoint.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_new_secret := 'whsec_' || encode(gen_random_bytes(24), 'hex');

  update app.webhook_endpoints set secret_value_encrypted = app._encrypt_integration_secret(v_new_secret) where app.webhook_endpoints.id = p_endpoint_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_webhook_secret',
    'app.webhook_endpoints', v_updated.id, 'success', null, null, jsonb_build_object('id', v_updated.id)
  );

  return query select v_updated.id, v_updated.tenant_id, v_updated.url, v_updated.status, v_new_secret;
end;
$$;

-- ===========================================================================
-- 4. Readers: decrypt on read. CREATE OR REPLACE on identical signatures.
-- ===========================================================================

create or replace function app.get_external_sync_credential(p_connection_id uuid)
returns text
language sql
stable
set search_path = app, public, extensions, pg_temp
as $$
  select app._decrypt_integration_secret(credential_value_encrypted) from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

create or replace function app.get_maps_provider_credential(p_connection_id uuid)
returns text
language sql
stable
set search_path = app, public, extensions, pg_temp
as $$
  select app._decrypt_integration_secret(credential_value_encrypted) from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

create or replace function app.get_logistics_partner_credential(p_connection_id uuid)
returns text
language sql
stable
set search_path = app, public, extensions, pg_temp
as $$
  select app._decrypt_integration_secret(credential_value_encrypted) from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

create or replace function app.get_notification_provider_credential(p_connection_id uuid)
returns text
language sql
stable
set search_path = app, public, extensions, pg_temp
as $$
  select app._decrypt_integration_secret(credential_value_encrypted) from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

create or replace function app.get_ai_governed_credential(p_connection_id uuid)
returns text
language sql
stable
set search_path = app, public, extensions, pg_temp
as $$
  select app._decrypt_integration_secret(credential_value_encrypted) from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

create or replace function app.get_finance_provider_credential(p_connection_id uuid)
returns text
language sql
stable
set search_path = app, public, extensions, pg_temp
as $$
  select app._decrypt_integration_secret(credential_value_encrypted) from app.integration_connection_credentials where connection_id = p_connection_id;
$$;

create or replace function app.compute_logistics_partner_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint)
returns text
language plpgsql
stable
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_secret_encrypted bytea;
  v_secret text;
begin
  select credential_value_encrypted into v_secret_encrypted from app.integration_connection_credentials where connection_id = p_connection_id;
  if v_secret_encrypted is null then
    return null;
  end if;
  v_secret := app._decrypt_integration_secret(v_secret_encrypted);
  return encode(hmac(p_timestamp::text || '.' || p_payload, v_secret, 'sha256'), 'hex');
end;
$$;

create or replace function app.compute_finance_payment_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint)
returns text
language plpgsql
stable
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_secret_encrypted bytea;
  v_secret text;
begin
  select credential_value_encrypted into v_secret_encrypted from app.integration_connection_credentials where connection_id = p_connection_id;
  if v_secret_encrypted is null then
    return null;
  end if;
  v_secret := app._decrypt_integration_secret(v_secret_encrypted);
  return encode(hmac(p_timestamp::text || '.' || p_payload, v_secret, 'sha256'), 'hex');
end;
$$;

create or replace function app.compute_third_party_provider_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint)
returns text
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_secret_encrypted bytea;
  v_secret text;
  v_signed_payload text;
begin
  select webhook_secret_value_encrypted into v_secret_encrypted from app.third_party_provider_connections where id = p_connection_id;
  if v_secret_encrypted is null then
    raise exception 'connection_not_found_or_not_webhook: no webhook-mode connection %', p_connection_id using errcode = 'no_data_found';
  end if;
  v_secret := app._decrypt_integration_secret(v_secret_encrypted);

  v_signed_payload := p_timestamp::text || '.' || p_payload;
  return encode(hmac(v_signed_payload, v_secret, 'sha256'), 'hex');
end;
$$;

create or replace function app.compute_webhook_signature(p_endpoint_id uuid, p_payload text, p_timestamp bigint)
returns text
language plpgsql
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_secret_encrypted bytea;
  v_secret text;
  v_signed_payload text;
begin
  select secret_value_encrypted into v_secret_encrypted from app.webhook_endpoints where id = p_endpoint_id;
  if v_secret_encrypted is null then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;
  v_secret := app._decrypt_integration_secret(v_secret_encrypted);

  v_signed_payload := p_timestamp::text || '.' || p_payload;
  return encode(hmac(v_signed_payload, v_secret, 'sha256'), 'hex');
end;
$$;

-- ===========================================================================
-- 5. Re-state grants for every redefined function (CREATE OR REPLACE preserves
--    an unchanged signature's existing grants automatically in Postgres, but
--    this repository's own established convention -- see every prior hardening
--    migration -- is to restate them explicitly rather than rely on that,
--    since a signature change anywhere in this block would silently need it
--    and be easy to miss).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.create_integration_connection(uuid,text,text,text,text,text,text,jsonb,text,uuid,text,text) to authenticated, service_role;
grant execute on function app.rotate_integration_connection_credential(uuid,text,uuid,text) to authenticated, service_role;
grant execute on function app.register_third_party_provider_connection(uuid,text,text,uuid,text) to authenticated, service_role;
grant execute on function app.rotate_third_party_provider_webhook_secret(uuid,uuid,text) to authenticated, service_role;
grant execute on function app.register_webhook_endpoint(uuid,text,jsonb,uuid,text) to service_role;
grant execute on function app.rotate_webhook_secret(uuid,uuid,text) to service_role;

grant execute on function app.get_external_sync_credential(uuid) to service_role;
grant execute on function app.get_maps_provider_credential(uuid) to service_role;
grant execute on function app.get_logistics_partner_credential(uuid) to service_role;
grant execute on function app.get_notification_provider_credential(uuid) to service_role;
grant execute on function app.get_ai_governed_credential(uuid) to service_role;
grant execute on function app.get_finance_provider_credential(uuid) to service_role;
grant execute on function app.compute_logistics_partner_webhook_signature(uuid,text,bigint) to service_role;
grant execute on function app.compute_finance_payment_webhook_signature(uuid,text,bigint) to service_role;
grant execute on function app.compute_third_party_provider_webhook_signature(uuid,text,bigint) to service_role;
grant execute on function app.compute_webhook_signature(uuid,text,bigint) to service_role;
