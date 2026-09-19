-- Real, executable test evidence for app.platform_integration_secrets (user-directed
-- extension of CG-AUDIT-2026-09-02 A6/D4, 20260908000000) -- run via `pnpm run
-- db:test` against a real, disposable Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000099000001..002. Grep-verified
-- unclaimed against every other *.sql fixture in this directory before use.

\set ON_ERROR_STOP on

-- ISS-2026-257 convention (mirrors integration-hub.sql/enterprise-mfa-session-
-- controls.sql and every other file that exercises app._encrypt_integration_secret/
-- _decrypt_integration_secret): production key provisioning/rotation/custody is a
-- disclosed, out-of-scope infrastructure concern (CG-AUDIT-2026-09-02 D4).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: a Supreme Admin and a plain identity with no principal membership at all'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000099000001';
  v_no_grant uuid := '00000000-0000-0000-0000-000099000002';
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@pissecrets.test'),
    (v_no_grant, 'nogrant@pissecrets.test');
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');
end;
$$;

\echo '>> app.set_platform_integration_secret: without the encryption GUC set, fails closed with encryption_key_not_configured -- proves this table is genuinely gated by CG-AUDIT-2026-09-02 D4''s own disclosed dependency, not silently working around it'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000099000001';
begin
  perform set_config('app.integration_secrets_encryption_key', '', true);
  begin
    perform app.set_platform_integration_secret('probe_only_key', 'probe-value', null, v_supreme, 'tester');
    raise exception 'assertion failed: expected encryption_key_not_configured with the GUC unset';
  exception
    when others then
      if sqlerrm !~ 'encryption_key_not_configured' then raise; end if;
  end;
end;
$$;

-- Restore the real test key for every assertion below (set local above was
-- transaction-scoped to that one DO block only).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> app.set_platform_integration_secret: Supreme-Admin-only (an identity with no principal membership at all is rejected); invalid key shape rejected; empty value rejected'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000099000001';
  v_no_grant uuid := '00000000-0000-0000-0000-000099000002';
begin
  begin
    perform app.set_platform_integration_secret('probe_key', 'probe-value', null, v_no_grant, 'nogrant');
    raise exception 'assertion failed: expected insufficient_authority for an identity with no principal membership at all';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.set_platform_integration_secret('Bad Key Shape!', 'probe-value', null, v_supreme, 'tester');
    raise exception 'assertion failed: expected platform_integration_secret_invalid_key for an uppercase/space-containing key';
  exception
    when check_violation then
      if sqlerrm !~ 'platform_integration_secret_invalid_key' then raise; end if;
  end;

  begin
    perform app.set_platform_integration_secret('probe_key', '', null, v_supreme, 'tester');
    raise exception 'assertion failed: expected platform_integration_secret_value_required for an empty value';
  exception
    when check_violation then
      if sqlerrm !~ 'platform_integration_secret_value_required' then raise; end if;
  end;
end;
$$;

\echo '>> app.set_platform_integration_secret / app.get_platform_integration_secret: real round-trip through pgcrypto encryption; rotation upserts in place (never a second row) and stamps rotated_at; an unconfigured key decrypts to null, never raises'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000099000001';
  v_first app.platform_integration_secrets;
  v_rotated app.platform_integration_secrets;
  v_count integer;
begin
  v_first := app.set_platform_integration_secret('virustotal_api_key', 'first-secret-value', 'VirusTotal free-tier API key', v_supreme, 'tester');
  if v_first.secret_key <> 'virustotal_api_key' or v_first.rotated_at is not null or v_first.description <> 'VirusTotal free-tier API key' then
    raise exception 'assertion failed: unexpected first-set row %', v_first;
  end if;
  if app.get_platform_integration_secret('virustotal_api_key') <> 'first-secret-value' then
    raise exception 'assertion failed: expected the first value to decrypt correctly';
  end if;

  v_rotated := app.set_platform_integration_secret('virustotal_api_key', 'second-secret-value', null, v_supreme, 'tester');
  if v_rotated.rotated_at is null then
    raise exception 'assertion failed: expected rotated_at to be set on a second set() call for the same key';
  end if;
  -- A null p_description on rotation preserves the prior description rather than
  -- clobbering it -- app.set_platform_integration_secret's own coalesce(excluded.
  -- description, s.description).
  if v_rotated.description <> 'VirusTotal free-tier API key' then
    raise exception 'assertion failed: expected the prior description to survive a rotation that passed null, got %', v_rotated.description;
  end if;
  if app.get_platform_integration_secret('virustotal_api_key') <> 'second-secret-value' then
    raise exception 'assertion failed: expected the rotated value to decrypt correctly';
  end if;

  select count(*) into v_count from app.platform_integration_secrets where secret_key = 'virustotal_api_key';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one row after rotation (upsert), got %', v_count;
  end if;

  if app.get_platform_integration_secret('a_key_nobody_ever_configured') is not null then
    raise exception 'assertion failed: expected null, not an exception, for an unconfigured key';
  end if;
end;
$$;

\echo '>> app.list_platform_integration_secrets: Supreme-Admin-only; lists key/description/provenance but NEVER a value, encrypted or otherwise (proven structurally -- the RETURNS TABLE shape has no such column at all, not merely omitted at read time)'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000099000001';
  v_no_grant uuid := '00000000-0000-0000-0000-000099000002';
  v_row record;
begin
  begin
    perform app.list_platform_integration_secrets(v_no_grant);
    raise exception 'assertion failed: expected insufficient_authority for an identity with no principal membership at all';
  exception
    when insufficient_privilege then null;
  end;

  select * into v_row from app.list_platform_integration_secrets(v_supreme) where secret_key = 'virustotal_api_key';
  if not found or v_row.description <> 'VirusTotal free-tier API key' or v_row.rotated_at is null then
    raise exception 'assertion failed: expected virustotal_api_key to appear in the list with its rotated description, got %', v_row;
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 3 new functions (both app.* and their public.* wrappers -- ISS-2026-309''s own class of regression); authenticated/anon hold zero table-level privilege on app.platform_integration_secrets at all'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and grantee = 'anon'
    and routine_name in ('set_platform_integration_secret', 'get_platform_integration_secret', 'list_platform_integration_secrets');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across app.*/public.* platform-integration-secret functions, found %', v_count;
  end if;

  select count(*) into v_count
  from information_schema.role_table_grants
  where table_schema = 'app' and table_name = 'platform_integration_secrets' and grantee in ('anon', 'authenticated');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon/authenticated table-level grants on app.platform_integration_secrets, found %', v_count;
  end if;

  -- get_platform_integration_secret is service_role-only -- authenticated must not hold it either.
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public') and grantee = 'authenticated' and routine_name = 'get_platform_integration_secret';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero authenticated EXECUTE grants on get_platform_integration_secret (service_role-only reader), found %', v_count;
  end if;
end;
$$;

\echo '>> platform-integration-secrets.sql: all assertions passed'
