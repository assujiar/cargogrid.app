-- Real, executable test evidence for PLT-119 (Localization, CG-S6-PLT-016).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001101', 'tenantadminloc@example.test'),
    ('00000000-0000-0000-0000-000000001102', 'regularuserloc@example.test'),
    ('00000000-0000-0000-0000-000000001103', 'supremeloc@example.test'),
    ('00000000-0000-0000-0000-000000001104', 'othertenantadminloc@example.test');

  perform app.provision_tenant('acmeloc', 'Acme Localization Co', 'idem-acmeloc', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001101', 'tenantadminloc@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminloc@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001101', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001102', 'regularuserloc@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserloc@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001102', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001103', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoloc', 'Gizmo Localization Co', 'idem-gizmoloc', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoloc');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001104', 'othertenantadminloc@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminloc@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001104', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.validate_locale_code / app.validate_timezone_name / app.validate_currency_code: the bounded, sourced sets'
do $$
begin
  if not app.validate_locale_code('id') or not app.validate_locale_code('en') then
    raise exception 'assertion failed: expected id/en to validate';
  end if;
  if app.validate_locale_code('fr') then
    raise exception 'assertion failed: expected an unsupported locale to be rejected';
  end if;

  if not app.validate_timezone_name('Asia/Jakarta') or not app.validate_timezone_name('UTC') then
    raise exception 'assertion failed: expected Asia/Jakarta and UTC to validate';
  end if;
  if app.validate_timezone_name('America/New_York') then
    raise exception 'assertion failed: expected a non-Indonesia, non-UTC timezone to be rejected (bounded set)';
  end if;

  if not app.validate_currency_code('IDR') or not app.validate_currency_code('USD') then
    raise exception 'assertion failed: expected IDR/USD to validate';
  end if;
  if app.validate_currency_code('EUR') then
    raise exception 'assertion failed: expected an unsupported currency to be rejected';
  end if;
end;
$$;

\echo '>> app.canonical_terms: seeded with real, already-shipped enum values; a tenant cannot mutate it'
do $$
declare
  v_count integer;
  v_has_privilege boolean;
begin
  select count(*) into v_count from app.canonical_terms;
  if v_count < 20 then
    raise exception 'assertion failed: expected at least 20 seeded canonical terms, saw %', v_count;
  end if;

  if not exists (select 1 from app.canonical_terms where code = 'tenant_status.active') then
    raise exception 'assertion failed: expected tenant_status.active to be seeded (PLT-105)';
  end if;
  if not exists (select 1 from app.canonical_terms where code = 'domain_status.active') then
    raise exception 'assertion failed: expected domain_status.active to be seeded (PLT-118)';
  end if;

  select has_table_privilege('authenticated', 'app.canonical_terms', 'INSERT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no INSERT privilege on app.canonical_terms';
  end if;
  select has_table_privilege('authenticated', 'app.canonical_terms', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold direct SELECT on app.canonical_terms (platform-owned baseline, no PII)';
  end if;
end;
$$;

\echo '>> app.tenant_locale_versions CHECK/trigger validation: malformed locale/timezone/currency/terminology are all rejected structurally'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');

  begin
    insert into app.tenant_locale_versions (tenant_id, version_number, default_locale) values (v_tenant_id, 900, 'fr');
    raise exception 'assertion failed: expected an unsupported locale to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_locale_versions (tenant_id, version_number, default_timezone) values (v_tenant_id, 901, 'America/New_York');
    raise exception 'assertion failed: expected an unsupported timezone to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_locale_versions (tenant_id, version_number, default_currency) values (v_tenant_id, 902, 'EUR');
    raise exception 'assertion failed: expected an unsupported currency to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_locale_versions (tenant_id, version_number, terminology_overrides)
    values (v_tenant_id, 903, '{"not_a_real_code": "X"}'::jsonb);
    raise exception 'assertion failed: expected an unknown canonical_terms code to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_locale_versions (tenant_id, version_number, terminology_overrides)
    values (v_tenant_id, 904, '{"tenant_status.active": "<script>alert(1)</script>"}'::jsonb);
    raise exception 'assertion failed: expected an angle-bracket terminology label to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.create_tenant_locale_draft: idempotent, authority-gated'
do $$
declare
  v_tenant_id uuid;
  v_draft1 app.tenant_locale_versions;
  v_draft2 app.tenant_locale_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');

  begin
    perform app.create_tenant_locale_draft(v_tenant_id, '00000000-0000-0000-0000-000000001102', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied';
  exception
    when insufficient_privilege then
      null;
  end;

  v_draft1 := app.create_tenant_locale_draft(v_tenant_id, '00000000-0000-0000-0000-000000001101', 'tenant admin');
  if v_draft1.status <> 'draft' or v_draft1.default_locale <> 'id' then
    raise exception 'assertion failed: expected a fresh draft defaulting to id/Asia/Jakarta/IDR';
  end if;

  v_draft2 := app.create_tenant_locale_draft(v_tenant_id, '00000000-0000-0000-0000-000000001101', 'tenant admin');
  if v_draft2.id <> v_draft1.id then
    raise exception 'assertion failed: expected a repeated call to return the same existing draft';
  end if;
end;
$$;

\echo '>> app.set_tenant_locale_config: only mutates a draft, applies terminology overrides for real seeded codes'
do $$
declare
  v_tenant_id uuid;
  v_draft app.tenant_locale_versions;
  v_updated app.tenant_locale_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');
  select * into v_draft from app.tenant_locale_versions where tenant_id = v_tenant_id and status = 'draft';

  v_updated := app.set_tenant_locale_config(
    v_draft.id, '00000000-0000-0000-0000-000000001101', 'en', 'UTC', 'USD',
    '{"tenant_status.active": "Live", "principal_layer.tenant_admin": "Account Owner"}'::jsonb, 'tenant admin'
  );
  if v_updated.default_locale <> 'en' or v_updated.default_timezone <> 'UTC' or v_updated.default_currency <> 'USD' then
    raise exception 'assertion failed: expected the draft to reflect the new locale/timezone/currency';
  end if;
  if v_updated.terminology_overrides ->> 'tenant_status.active' <> 'Live' then
    raise exception 'assertion failed: expected the terminology override to persist';
  end if;

  begin
    perform app.set_tenant_locale_config(v_draft.id, '00000000-0000-0000-0000-000000001102', 'id', 'Asia/Jakarta', 'IDR', '{}'::jsonb, 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> app.publish_tenant_locale_version: supersedes the prior published version; at most one published version at a time'
do $$
declare
  v_tenant_id uuid;
  v_draft app.tenant_locale_versions;
  v_published app.tenant_locale_versions;
  v_second_draft app.tenant_locale_versions;
  v_second_published app.tenant_locale_versions;
  v_first_after app.tenant_locale_versions;
  v_published_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');
  select * into v_draft from app.tenant_locale_versions where tenant_id = v_tenant_id and status = 'draft';

  begin
    perform app.publish_tenant_locale_version('00000000-0000-0000-0000-000000001199', '00000000-0000-0000-0000-000000001101', null, 'tenant admin');
    raise exception 'assertion failed: expected a nonexistent version_id to raise locale_version_not_found';
  exception
    when no_data_found then
      null;
  end;

  v_published := app.publish_tenant_locale_version(v_draft.id, '00000000-0000-0000-0000-000000001101', null, 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the draft to publish successfully';
  end if;

  v_second_draft := app.create_tenant_locale_draft(v_tenant_id, '00000000-0000-0000-0000-000000001101', 'tenant admin');
  perform app.set_tenant_locale_config(v_second_draft.id, '00000000-0000-0000-0000-000000001101', 'id', 'Asia/Jakarta', 'IDR', '{}'::jsonb, 'tenant admin');
  v_second_published := app.publish_tenant_locale_version(v_second_draft.id, '00000000-0000-0000-0000-000000001101', null, 'tenant admin');

  select * into v_first_after from app.tenant_locale_versions where id = v_published.id;
  if v_first_after.status <> 'archived' then
    raise exception 'assertion failed: expected the first published version to be archived after supersession, got %', v_first_after.status;
  end if;

  select count(*) into v_published_count from app.tenant_locale_versions where tenant_id = v_tenant_id and status = 'published';
  if v_published_count <> 1 then
    raise exception 'assertion failed: expected exactly one published version at a time, saw %', v_published_count;
  end if;
end;
$$;

\echo '>> app.resolve_tenant_locale / app.resolve_locale_context: tenant-source resolution and cross-tenant isolation'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_result record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoloc');

  select * into v_result from app.resolve_tenant_locale(v_tenant_id);
  if v_result.source <> 'tenant' or v_result.default_locale <> 'id' or v_result.default_currency <> 'IDR' then
    raise exception 'assertion failed: expected acmeloc''s published (id/Asia/Jakarta/IDR) version to resolve, got source=% locale=%', v_result.source, v_result.default_locale;
  end if;

  select * into v_result from app.resolve_tenant_locale(v_other_tenant_id);
  if v_result.source <> 'default' then
    raise exception 'assertion failed: expected gizmoloc (never published) to fall back to the platform default';
  end if;
  if v_result.default_locale <> 'id' or v_result.default_timezone <> 'Asia/Jakarta' or v_result.default_currency <> 'IDR' then
    raise exception 'assertion failed: expected the Indonesia-first platform default (id/Asia/Jakarta/IDR)';
  end if;

  -- Cross-tenant isolation: acmeloc's terminology never leaks into gizmoloc's context.
  select * into v_result from app.resolve_locale_context(v_other_tenant_id);
  if v_result.terminology_overrides ? 'tenant_status.active' then
    raise exception 'assertion failed: expected gizmoloc''s context to never carry acmeloc''s terminology overrides';
  end if;
end;
$$;

\echo '>> app.resolve_tenant_locale: an active domain-holding tenant that is suspended falls back to the platform default'
do $$
declare
  v_tenant_id uuid;
  v_result record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');
  perform app.transition_tenant_status(v_tenant_id, 'suspended', 'billing hold', 'tester');

  select * into v_result from app.resolve_tenant_locale(v_tenant_id);
  if v_result.source <> 'default' then
    raise exception 'assertion failed: expected a suspended tenant to fall back to the platform default';
  end if;

  perform app.transition_tenant_status(v_tenant_id, 'active', 'billing resolved', 'tester');
  select * into v_result from app.resolve_tenant_locale(v_tenant_id);
  if v_result.source <> 'tenant' then
    raise exception 'assertion failed: expected resolution to resume once the tenant is active again';
  end if;
end;
$$;

\echo '>> app.resolve_locale_context: the real three-tier fallback (user -> tenant -> platform default), each field independently'
do $$
declare
  v_tenant_id uuid;
  v_result record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');

  -- No user preference set yet: falls straight through to the tenant's published config.
  select * into v_result from app.resolve_locale_context(v_tenant_id, '00000000-0000-0000-0000-000000001101');
  if v_result.locale <> 'id' or v_result.timezone <> 'Asia/Jakarta' or v_result.currency <> 'IDR' then
    raise exception 'assertion failed: expected the tenant admin (no personal preference set) to inherit the tenant''s published config';
  end if;

  -- Set only a personal timezone preference -- locale/currency must still come from the tenant.
  update app.users set preferred_timezone = 'UTC' where email = 'tenantadminloc@example.test';
  select * into v_result from app.resolve_locale_context(v_tenant_id, '00000000-0000-0000-0000-000000001101');
  if v_result.timezone <> 'UTC' then
    raise exception 'assertion failed: expected the personal timezone preference to override the tenant default';
  end if;
  if v_result.locale <> 'id' or v_result.currency <> 'IDR' then
    raise exception 'assertion failed: expected locale/currency to remain the tenant default -- fallback is per-field independent, not all-or-nothing';
  end if;

  -- A user with no auth_user_id given at all: pure tenant/platform resolution, no user tier.
  select * into v_result from app.resolve_locale_context(v_tenant_id, null);
  if v_result.timezone <> 'Asia/Jakarta' then
    raise exception 'assertion failed: expected a null user id to skip the user tier entirely';
  end if;
end;
$$;

\echo '>> app.users preferred_locale/preferred_timezone/preferred_currency CHECK constraints reject unsupported values'
do $$
declare
  v_user_id uuid;
begin
  v_user_id := (select id from app.users where email = 'regularuserloc@example.test');

  begin
    update app.users set preferred_locale = 'fr' where id = v_user_id;
    raise exception 'assertion failed: expected an unsupported preferred_locale to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    update app.users set preferred_currency = 'EUR' where id = v_user_id;
    raise exception 'assertion failed: expected an unsupported preferred_currency to be rejected';
  exception
    when check_violation then
      null;
  end;

  -- A valid value is accepted (regression guard: the CHECK constraint is not overly strict).
  update app.users set preferred_locale = 'en' where id = v_user_id;
end;
$$;

\echo '>> app.rollback_tenant_locale_version: never mutates history -- creates a brand-new version carrying the target''s exact snapshot; rejects rolling back a draft'
do $$
declare
  v_tenant_id uuid;
  v_target_id uuid;
  v_current_published_id uuid;
  v_rolled_back app.tenant_locale_versions;
  v_new_draft app.tenant_locale_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');
  v_target_id := (select id from app.tenant_locale_versions where tenant_id = v_tenant_id and version_number = 1);
  v_current_published_id := (select id from app.tenant_locale_versions where tenant_id = v_tenant_id and status = 'published');
  if v_target_id = v_current_published_id then
    raise exception 'assertion failed (test setup bug): rollback target must differ from the currently published version';
  end if;

  v_rolled_back := app.rollback_tenant_locale_version(v_target_id, '00000000-0000-0000-0000-000000001101', 'reverting to prior locale config', 'tenant admin');
  if v_rolled_back.status <> 'published' or v_rolled_back.id = v_target_id then
    raise exception 'assertion failed: expected rollback to publish a brand-new version, not reuse the target''s id';
  end if;
  if v_rolled_back.default_currency <> 'USD' then
    raise exception 'assertion failed: expected the rolled-back version to carry the target''s exact snapshot (USD), got %', v_rolled_back.default_currency;
  end if;

  if (select status from app.tenant_locale_versions where id = v_target_id) <> 'archived' then
    raise exception 'assertion failed: expected the rollback target itself to remain untouched (still archived, not mutated)';
  end if;

  v_new_draft := app.create_tenant_locale_draft(v_tenant_id, '00000000-0000-0000-0000-000000001101', 'tenant admin');
  begin
    perform app.rollback_tenant_locale_version(v_new_draft.id, '00000000-0000-0000-0000-000000001101', 'x', 'tenant admin');
    raise exception 'assertion failed: expected rolling back a draft to be rejected';
  exception
    when check_violation then
      null;
  end;
  perform app.discard_tenant_locale_draft(v_new_draft.id, '00000000-0000-0000-0000-000000001101', 'cleanup', 'tenant admin');
end;
$$;

\echo '>> every lifecycle mutation self-captures a canonical app.audit_logs entry (no bespoke *_history table exists for this capability)'
do $$
declare
  v_tenant_id uuid;
  v_actions text[] := array['create_tenant_locale_draft', 'set_tenant_locale_config', 'publish_tenant_locale_version', 'rollback_tenant_locale_version', 'discard_tenant_locale_draft'];
  v_action text;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeloc');

  foreach v_action in array v_actions loop
    select count(*) into v_count
    from app.audit_logs
    where tenant_id = v_tenant_id and action = v_action and resource_type = 'app.tenant_locale_versions';
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated/anon have no direct table access to app.tenant_locale_versions; anon holds EXECUTE only on the public resolvers'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.tenant_locale_versions', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct SELECT privilege on app.tenant_locale_versions';
  end if;

  select has_table_privilege('anon', 'app.tenant_locale_versions', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no direct SELECT privilege on app.tenant_locale_versions';
  end if;

  select has_function_privilege('anon', 'app.resolve_tenant_locale(uuid)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected anon to hold EXECUTE on app.resolve_tenant_locale (needed pre-authentication)';
  end if;

  select has_function_privilege('anon', 'app.resolve_locale_context(uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected anon to hold EXECUTE on app.resolve_locale_context (needed pre-authentication)';
  end if;

  select has_function_privilege('anon', 'app.create_tenant_locale_draft(uuid, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.create_tenant_locale_draft (ERR-2026-004 regression guard)';
  end if;
end;
$$;
