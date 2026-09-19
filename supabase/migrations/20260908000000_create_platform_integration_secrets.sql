-- Platform integration secrets (user-directed extension of CG-AUDIT-2026-09-02 A6/D4).
-- The user asked for a VirusTotal API key (to close A6's "no malware scanner exists"
-- gap) to be configurable from the Supreme Admin UI, generalized so any FUTURE
-- platform-level (not tenant-owned) third-party API key can be added the same way,
-- rather than as an environment variable.
--
-- Every existing secret-bearing table in this repository
-- (app.integration_connection_credentials, app.third_party_provider_connections,
-- app.webhook_endpoints) is TENANT-scoped -- a tenant's own credential for its own
-- third-party account. There is no precedent for a secret the PLATFORM ITSELF holds
-- to call an outbound service on every tenant's behalf (VirusTotal is exactly this:
-- one CargoGrid-operated account, not a per-tenant integration). This migration adds
-- that missing shape, reusing the EXISTING encryption mechanism
-- (app._encrypt_integration_secret/_decrypt_integration_secret, pgcrypto
-- pgp_sym_encrypt/pgp_sym_decrypt keyed by the app.integration_secrets_encryption_key
-- GUC -- 20260826050000) rather than inventing a second one, and mirroring
-- app.platform_scheduled_task_definitions/app.platform_scheduled_tasks
-- (20260902020000) as the established "platform-wide, no tenant_id, Supreme-Admin-only"
-- shape.
--
-- Disclosed dependency (CG-AUDIT-2026-09-02 D4, still open): every write and read
-- through this table calls app.integration_secrets_encryption_key(), which raises
-- encryption_key_not_configured whenever the underlying GUC is unset -- true in every
-- environment today, since nothing in this repository's own code or infrastructure
-- ever sets it (D4's own finding: "the GUC is set nowhere outside db-test fixtures").
-- This migration does not close D4 -- it cannot; provisioning that GUC value is a
-- real secret-custody decision for whoever operates the deployment, the same
-- disclosed operator boundary as CRON_SECRET (A5) and a real TOTP provider (D1). Once
-- that one GUC is set, this table and every RPC below work exactly as written; until
-- then, a Supreme Admin attempting to save a key here sees a clear
-- encryption_key_not_configured error rather than a silent failure or a plaintext
-- fallback.

create table app.platform_integration_secrets (
  secret_key text primary key,
  secret_value_encrypted bytea not null,
  description text,
  configured_by_auth_user_id uuid not null references auth.users (id),
  configured_at timestamptz not null default now(),
  rotated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_integration_secrets_key_shape_check check (secret_key ~ '^[a-z][a-z0-9_]{2,63}$')
);

comment on table app.platform_integration_secrets is
  'Platform-wide (no tenant_id) third-party API keys/credentials the platform itself holds to call an outbound service on every tenant''s behalf -- e.g. virustotal_api_key. Never a tenant''s own credential (that remains app.integration_connection_credentials). secret_value_encrypted uses the identical pgcrypto mechanism as that table (app._encrypt_integration_secret/_decrypt_integration_secret), never a parallel scheme. Supreme-Admin-only to write or list; only service_role may ever decrypt a value, and only server-side outbound-call code should ever do so -- never returned to any UI once saved.';

create function app.touch_platform_integration_secrets_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger platform_integration_secrets_touch_row
before update on app.platform_integration_secrets
for each row execute function app.touch_platform_integration_secrets_row();

-- ===========================================================================
-- Writer: Supreme-Admin-only, upsert (set = create-or-rotate in one call, matching
-- app.configure_platform_scheduled_task's own upsert shape). Never returns the
-- decrypted value -- the caller already has it, and this repository's own
-- established convention (PasswordInput's own "write-only until deliberately
-- revealed" UX) never echoes a secret back after it is saved.
-- ===========================================================================

create function app.set_platform_integration_secret(
  p_secret_key text,
  p_secret_value text,
  p_description text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.platform_integration_secrets
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_row app.platform_integration_secrets;
  v_is_rotation boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not configure a platform integration secret -- Supreme Admin only', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_secret_key !~ '^[a-z][a-z0-9_]{2,63}$' then
    raise exception 'platform_integration_secret_invalid_key: % must be lowercase snake_case, 3-64 characters, starting with a letter', p_secret_key
      using errcode = 'check_violation';
  end if;

  if p_secret_value is null or length(p_secret_value) = 0 then
    raise exception 'platform_integration_secret_value_required: a non-empty secret value is required'
      using errcode = 'check_violation';
  end if;

  select exists (select 1 from app.platform_integration_secrets where secret_key = p_secret_key) into v_is_rotation;

  insert into app.platform_integration_secrets as s
    (secret_key, secret_value_encrypted, description, configured_by_auth_user_id, configured_at, rotated_at)
  values
    (p_secret_key, app._encrypt_integration_secret(p_secret_value), p_description, p_actor_auth_user_id, now(), case when v_is_rotation then now() else null end)
  on conflict (secret_key) do update
  set secret_value_encrypted = excluded.secret_value_encrypted,
      description = coalesce(excluded.description, s.description),
      configured_by_auth_user_id = excluded.configured_by_auth_user_id,
      rotated_at = now()
  returning * into v_row;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, case when v_is_rotation then 'rotate_platform_integration_secret' else 'set_platform_integration_secret' end,
    'app.platform_integration_secrets', null, 'success', null, null,
    jsonb_build_object('secret_key', p_secret_key, 'description', v_row.description)
  );

  return v_row;
end;
$$;

comment on function app.set_platform_integration_secret is
  'Supreme-Admin-only. Upsert on secret_key -- a second call with an existing key rotates it (re-encrypts, re-stamps configured_by/rotated_at) rather than erroring. The plaintext value is never persisted, logged, or returned -- only app._encrypt_integration_secret''s own ciphertext is stored, and the audit event''s own metadata carries the key NAME and description only, never the value.';

revoke execute on all functions in schema app from public;
grant execute on function app.set_platform_integration_secret(text, text, text, uuid, text) to authenticated, service_role;

create function public.set_platform_integration_secret(p_secret_key text, p_secret_value text, p_description text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.platform_integration_secrets
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.set_platform_integration_secret(p_secret_key, p_secret_value, p_description, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.set_platform_integration_secret(text, text, text, uuid, text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.set_platform_integration_secret with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- ISS-2026-309: revoking only from the PUBLIC pseudo-role is not enough -- Supabase's
-- own ALTER DEFAULT PRIVILEGES rule grants EXECUTE on every new public.* function
-- directly to anon/authenticated/service_role at CREATE time, which a bare `from
-- public` never touches (the exact live incident scripts/db-tests/lib/setup-
-- disposable-db.sh's own ISS-2026-309 comment and 20260830200000's fix both document).
-- Revoke from all four, then re-grant only the intended subset.
revoke execute on function public.set_platform_integration_secret(text, text, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.set_platform_integration_secret(text, text, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- Reader (decrypted): service_role-only, exactly like app.get_logistics_partner_
-- credential and its 5 siblings (20260826050000) -- only server-side outbound-call
-- code may ever decrypt a platform secret, never a browser session.
-- ===========================================================================

create function app.get_platform_integration_secret(p_secret_key text)
returns text
language sql
stable
set search_path = app, public, extensions, pg_temp
as $$
  select app._decrypt_integration_secret(secret_value_encrypted) from app.platform_integration_secrets where secret_key = p_secret_key;
$$;

comment on function app.get_platform_integration_secret is
  'service_role-only reader, mirroring app.get_logistics_partner_credential and its siblings (20260826050000) exactly. Returns null (never raises) when the key does not exist -- callers distinguish "not configured yet" from "configured but decryption failed" (the latter still raises, from app._decrypt_integration_secret/app.integration_secrets_encryption_key).';

grant execute on function app.get_platform_integration_secret(text) to service_role;

create function public.get_platform_integration_secret(p_secret_key text)
returns text
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.get_platform_integration_secret(p_secret_key);
$wrap$;

comment on function public.get_platform_integration_secret(text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_platform_integration_secret with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- ISS-2026-309: see the identical note on public.set_platform_integration_secret above.
revoke execute on function public.get_platform_integration_secret(text) from anon, authenticated, service_role, public;
grant execute on function public.get_platform_integration_secret(text) to service_role;

-- ===========================================================================
-- List: Supreme-Admin-only, masked -- names, descriptions, and provenance only,
-- NEVER the encrypted bytes or the decrypted value. Mirrors app.list_platform_
-- scheduled_tasks's own Supreme-Admin-only listing shape.
-- ===========================================================================

create function app.list_platform_integration_secrets(p_actor_auth_user_id uuid)
returns table (
  secret_key text, description text, configured_by_auth_user_id uuid,
  configured_at timestamptz, rotated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not list platform integration secrets -- Supreme Admin only', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select s.secret_key, s.description, s.configured_by_auth_user_id, s.configured_at, s.rotated_at
  from app.platform_integration_secrets s
  order by s.secret_key;
end;
$$;

comment on function app.list_platform_integration_secrets is
  'Supreme-Admin-only. Deliberately excludes secret_value_encrypted from its own return shape -- there is no code path anywhere that lets a saved platform secret be read back through this function, only replaced via app.set_platform_integration_secret.';

revoke execute on all functions in schema app from public;
grant execute on function app.list_platform_integration_secrets(uuid) to authenticated, service_role;

create function public.list_platform_integration_secrets(p_actor_auth_user_id uuid)
returns table (secret_key text, description text, configured_by_auth_user_id uuid, configured_at timestamptz, rotated_at timestamptz)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_platform_integration_secrets(p_actor_auth_user_id);
$wrap$;

comment on function public.list_platform_integration_secrets(uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_platform_integration_secrets with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- ISS-2026-309: see the identical note on public.set_platform_integration_secret above.
revoke execute on function public.list_platform_integration_secrets(uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_platform_integration_secrets(uuid) to authenticated, service_role;

-- ===========================================================================
-- Schema-privilege defense in depth (ERR-2026-004/PLT-118 standing convention):
-- anon holds zero EXECUTE on any function above, and authenticated/anon hold zero
-- table-level privilege on app.platform_integration_secrets at all -- every access
-- is through the three RPCs above, never a direct table grant.
-- ===========================================================================

revoke all on app.platform_integration_secrets from public, anon, authenticated;
grant all on app.platform_integration_secrets to service_role;
alter table app.platform_integration_secrets enable row level security;
