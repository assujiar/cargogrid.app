-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Regression evidence for the "Ticketing / white-label / localization / IAM and the rest"
-- lane (4 migrations, 20260903130000-20260903133000, 102 functions / 107 raise sites),
-- the residual left open after the 20260902100000-20260902104000 batch this file's
-- sibling scripts/db-tests/tenant-id-error-message-redaction.sql already covers.
--
-- Proves, for one representative function per module family in this lane:
--
--   1. A caller with ZERO relationship to the record's real tenant (never invited, no
--      app.tenant_user_identities row, no app.principal_memberships row anywhere for that
--      tenant) gets a GENERIC not-found error -- byte-identical in shape to the one a
--      nonexistent id already produced -- whose text does NOT contain the record's real
--      tenant_id. That is the fix.
--   2. A genuine member of that SAME tenant who simply lacks the specific role/layer
--      authority still gets the ORIGINAL, specific insufficient_authority message WITH the
--      tenant_id in it, under the unchanged insufficient_privilege errcode. Preserving that
--      distinction is the whole point of the fix shape: the tenant_id is not a new
--      disclosure to an actor who already demonstrably belongs to the tenant, and nothing
--      about the underlying refusal moved.
--
-- The six functions below are picked one per module family this lane touched -- white-label,
-- localization, ticketing/knowledge-base, platform webhooks, master data and Finance. Not
-- exhaustive by design (102 functions is out of scope for one test file); the exhaustive
-- accounting is scripts/security/classify-tenant-id-error-disclosure.ts, whose
-- "LATEST definition only" RISK_UNSCOPED_LOOKUP count this lane moved 468 -> 361.
--
-- Both authority shapes this lane's functions use are represented: the RBAC evaluator
-- (app.check_ticket_authority / app.check_finance_account_authority, thin wrappers over
-- app.evaluate_permission) and the elevated-layer predicate
-- (app.is_support_grant_authority, "Supreme Admin or this tenant's own tenant_admin").
-- The second shape matters: unlike app.evaluate_permission it does not itself require
-- app.has_active_tenant_membership, so it is the shape where the added gate could in
-- principle have changed an outcome -- and the member-side assertions below prove it did
-- not.

\set ON_ERROR_STOP on

-- ISS-2026-257: the same fixed test-only key scripts/db-tests/api-key-webhook.sql sets, needed
-- because this file registers a real webhook endpoint (whose secret is encrypted at rest) as
-- one of its six fixture records. Production key provisioning/rotation/custody is a disclosed,
-- out-of-scope infrastructure concern. set_config's third argument is false (session scope),
-- so this file does not depend on any other test file having run first.
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> ISS-2026-146 (misc lane) setup: tenant iss146misc with a tenant_admin holding FIN+TKT authority (fixture author), a zero-role org_user member (the "genuine member without authority" case), and an identity with no relationship to the tenant at all (the "outsider" case this fix closes)'
do $$
declare
  v_tenant uuid;
  v_supreme uuid := '00000000-0000-0000-0000-0000146b0000';
  v_admin uuid := '00000000-0000-0000-0000-0000146b0001';
  v_member uuid := '00000000-0000-0000-0000-0000146b0002';
  v_outsider uuid := '00000000-0000-0000-0000-0000146b0003';
  v_role_id uuid;
  v_role_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iss146misc.test'),
    (v_admin, 'admin@iss146misc.test'),
    (v_member, 'memberzero@iss146misc.test'),
    (v_outsider, 'outsider@iss146misc.test');
  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iss146misc', 'ISS-2026-146 Misc Lane Co', 'idem-iss146-misc', 'tester');
  v_tenant := (select id from app.tenants where slug = 'iss146misc');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant, 'company', null, 'ISS146M-CO', 'ISS146 Misc Co', 'tester');

  perform app.invite_user(v_tenant, v_admin, 'admin@iss146misc.test', 'ISS146M Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iss146misc.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin, 'tenant_admin', v_tenant, null, 'tester');

  -- A REAL, active member of this tenant, deliberately with NO role assignment and only the
  -- org_user layer -- so it fails both authority shapes (no FIN/TKT permission, and not a
  -- tenant_admin) while unambiguously passing app.has_active_tenant_membership.
  perform app.invite_user(v_tenant, v_member, 'memberzero@iss146misc.test', 'ISS146M Zero Role Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'memberzero@iss146misc.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_member, 'org_user', v_tenant, null, 'tester');

  -- v_outsider exists in auth.users and nowhere else: never invited to this tenant or any
  -- other, no principal membership anywhere. This is the caller class the original
  -- disclosure let learn a foreign tenant's real UUID from a denial message alone.

  v_role_id := (app.create_role(v_tenant, 'ISS146M Fixture Author', 'FIN + TKT authority, used only to create the fixture records probed below', 'tester')).id;
  v_role_draft := app.create_role_version(v_role_id, 'tester');
  perform app.set_role_version_permissions(v_role_draft.id, array(select id from app.permissions where resource_module_code = any(array['FIN', 'TKT'])), 'tester');
  perform app.publish_role_version(v_role_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_role_id and status = 'published'), v_admin, v_supreme, 'supreme');

  perform app.register_webhook_event_type('iss146misc.event', 'ISS-2026-146 Misc Lane Event', 'API-WH', v_supreme, 'supreme');
end;
$$;

\echo '>> ISS-2026-146 (misc lane) setup: one real record per module family, all created inside iss146misc by its own tenant_admin -- these are the records the outsider probes below'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146misc');
  v_admin uuid := '00000000-0000-0000-0000-0000146b0001';
  v_org_unit uuid := (select id from app.org_units where tenant_id = v_tenant and code = 'ISS146M-CO');
  v_brand app.tenant_brand_versions;
  v_locale app.tenant_locale_versions;
  v_article app.kb_articles;
  v_endpoint record;
  v_master app.master_records;
  v_account app.finance_accounts;
begin
  -- White label: app.set_tenant_brand_tokens is the fixed function under test.
  v_brand := app.create_tenant_brand_draft(v_tenant, v_admin, 'admin');

  -- Localization: app.set_tenant_locale_config is the fixed function under test.
  v_locale := app.create_tenant_locale_draft(v_tenant, v_admin, 'admin');

  -- Ticketing / knowledge base: app.create_kb_article_version is the fixed function.
  v_article := app.create_kb_article(v_tenant, 'iss146misc-article', v_admin, 'admin');

  -- Platform webhooks: app.disable_webhook_endpoint is the fixed function under test.
  select * into v_endpoint from app.register_webhook_endpoint(
    v_tenant, 'https://hooks.example-partner.test/iss146misc', '["iss146misc.event"]'::jsonb, v_admin, 'admin');

  -- Master data: app.deactivate_master_record is the fixed function under test.
  v_master := app.create_master_record('vendor', v_tenant, 'ISS146M-VEND-1', 'ISS146 Misc Vendor', null, null, v_admin, 'admin');

  -- Finance: app.activate_finance_account is the fixed function under test. Left as a
  -- freshly-created draft at record_version 1 so the member-side probe below reaches the
  -- authority check rather than short-circuiting on state or optimistic-concurrency.
  v_account := app.create_finance_account_draft(
    v_tenant, v_org_unit, 'ISS146M-1000', 'ISS146 Misc Asset', 'asset', 'debit', null, false, null, v_admin, 'admin');

  if v_brand.id is null or v_locale.id is null or v_article.id is null or v_endpoint.id is null
     or v_master.id is null or v_account.id is null then
    raise exception 'assertion failed: test precondition failed -- one or more fixture records were not created';
  end if;
  if v_account.status <> 'draft' or v_account.record_version <> 1 then
    raise exception 'assertion failed: test precondition failed -- expected a draft finance account at version 1, got status=% version=%', v_account.status, v_account.record_version;
  end if;
end;
$$;

\echo '>> ISS-2026-146 (white label): app.set_tenant_brand_tokens -- outsider gets a generic brand_version_not_found with NO tenant_id, the real member without tenant_admin authority still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146misc');
  v_member uuid := '00000000-0000-0000-0000-0000146b0002';
  v_outsider uuid := '00000000-0000-0000-0000-0000146b0003';
  v_version_id uuid := (select id from app.tenant_brand_versions where tenant_id = v_tenant and status = 'draft');
  v_msg text;
begin
  begin
    perform app.set_tenant_brand_tokens(v_version_id, v_outsider, '{"primary": "#123456"}'::jsonb, null, null, null, null, 'outsider');
    raise exception 'assertion failed: expected brand_version_not_found for an outsider with zero relationship to iss146misc';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'brand_version_not_found' then
        raise exception 'assertion failed: expected brand_version_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider''s error still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.set_tenant_brand_tokens(v_version_id, v_member, '{"primary": "#123456"}'::jsonb, null, null, null, null, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real iss146misc member who is not a tenant_admin';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' then
        raise exception 'assertion failed: expected the original insufficient_authority message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (not a new disclosure to them) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (localization): app.set_tenant_locale_config -- outsider gets a generic locale_version_not_found with NO tenant_id, the real member without tenant_admin authority still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146misc');
  v_member uuid := '00000000-0000-0000-0000-0000146b0002';
  v_outsider uuid := '00000000-0000-0000-0000-0000146b0003';
  v_version_id uuid := (select id from app.tenant_locale_versions where tenant_id = v_tenant and status = 'draft');
  v_msg text;
begin
  begin
    perform app.set_tenant_locale_config(v_version_id, v_outsider, 'en-US', 'UTC', 'USD', null, 'outsider');
    raise exception 'assertion failed: expected locale_version_not_found for an outsider with zero relationship to iss146misc';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'locale_version_not_found' then
        raise exception 'assertion failed: expected locale_version_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider''s error still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.set_tenant_locale_config(v_version_id, v_member, 'en-US', 'UTC', 'USD', null, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real iss146misc member who is not a tenant_admin';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' then
        raise exception 'assertion failed: expected the original insufficient_authority message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (not a new disclosure to them) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (ticketing / knowledge base): app.create_kb_article_version -- outsider gets a generic kb_article_not_found with NO tenant_id, the real member without TKT:Edit still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146misc');
  v_member uuid := '00000000-0000-0000-0000-0000146b0002';
  v_outsider uuid := '00000000-0000-0000-0000-0000146b0003';
  v_article_id uuid := (select id from app.kb_articles where tenant_id = v_tenant and code = 'iss146misc-article');
  v_msg text;
begin
  begin
    perform app.create_kb_article_version(v_article_id, 'Outsider Draft', null, 'body', null, true, false, false, v_outsider, 'outsider');
    raise exception 'assertion failed: expected kb_article_not_found for an outsider with zero relationship to iss146misc';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'kb_article_not_found' then
        raise exception 'assertion failed: expected kb_article_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider''s error still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.create_kb_article_version(v_article_id, 'Member Draft', null, 'body', null, true, false, false, v_member, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real iss146misc member with no TKT role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'TKT:Edit' then
        raise exception 'assertion failed: expected the original insufficient_authority TKT:Edit message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (not a new disclosure to them) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (platform webhooks): app.disable_webhook_endpoint -- outsider gets a generic webhook_endpoint_not_found with NO tenant_id, the real member without tenant_admin authority still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146misc');
  v_member uuid := '00000000-0000-0000-0000-0000146b0002';
  v_outsider uuid := '00000000-0000-0000-0000-0000146b0003';
  v_endpoint_id uuid := (select id from app.webhook_endpoints where tenant_id = v_tenant and url = 'https://hooks.example-partner.test/iss146misc');
  v_msg text;
begin
  begin
    perform app.disable_webhook_endpoint(v_endpoint_id, 'outsider attempt', v_outsider, 'outsider');
    raise exception 'assertion failed: expected webhook_endpoint_not_found for an outsider with zero relationship to iss146misc';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'webhook_endpoint_not_found' then
        raise exception 'assertion failed: expected webhook_endpoint_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider''s error still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.disable_webhook_endpoint(v_endpoint_id, 'member attempt', v_member, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real iss146misc member who is not a tenant_admin';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' then
        raise exception 'assertion failed: expected the original insufficient_authority message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (not a new disclosure to them) -- got %', v_msg;
      end if;
  end;

  if (select status from app.webhook_endpoints where id = v_endpoint_id) <> 'active' then
    raise exception 'assertion failed: neither refused call may have changed the endpoint''s state';
  end if;
end;
$$;

\echo '>> ISS-2026-146 (master data): app.deactivate_master_record -- outsider gets a generic master_record_not_found with NO tenant_id, the real member without tenant_admin authority still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146misc');
  v_member uuid := '00000000-0000-0000-0000-0000146b0002';
  v_outsider uuid := '00000000-0000-0000-0000-0000146b0003';
  v_record_id uuid := (select id from app.master_records where tenant_id = v_tenant and code = 'ISS146M-VEND-1');
  v_msg text;
begin
  begin
    perform app.deactivate_master_record(v_record_id, v_outsider, 'outsider attempt', 'outsider');
    raise exception 'assertion failed: expected master_record_not_found for an outsider with zero relationship to iss146misc';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'master_record_not_found' then
        raise exception 'assertion failed: expected master_record_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider''s error still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.deactivate_master_record(v_record_id, v_member, 'member attempt', 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real iss146misc member who is not a tenant_admin';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' then
        raise exception 'assertion failed: expected the original insufficient_authority message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (not a new disclosure to them) -- got %', v_msg;
      end if;
  end;
end;
$$;

\echo '>> ISS-2026-146 (finance): app.activate_finance_account -- outsider gets a generic finance_account_not_found with NO tenant_id, the real member without FIN:Approve still gets the original insufficient_authority WITH the tenant_id'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146misc');
  v_member uuid := '00000000-0000-0000-0000-0000146b0002';
  v_outsider uuid := '00000000-0000-0000-0000-0000146b0003';
  v_account_id uuid := (select id from app.finance_accounts where tenant_id = v_tenant and code = 'ISS146M-1000');
  v_msg text;
begin
  begin
    perform app.activate_finance_account(v_account_id, 1, v_outsider, 'outsider');
    raise exception 'assertion failed: expected finance_account_not_found for an outsider with zero relationship to iss146misc';
  exception
    when no_data_found then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'finance_account_not_found' then
        raise exception 'assertion failed: expected finance_account_not_found, got %', v_msg;
      end if;
      if v_msg like ('%' || v_tenant::text || '%') then
        raise exception 'assertion failed: THE FIX FAILED -- the outsider''s error still discloses the real tenant_id: %', v_msg;
      end if;
  end;

  begin
    perform app.activate_finance_account(v_account_id, 1, v_member, 'memberzero');
    raise exception 'assertion failed: expected insufficient_authority for a real iss146misc member with no FIN role';
  exception
    when insufficient_privilege then
      get stacked diagnostics v_msg = message_text;
      if v_msg !~ 'insufficient_authority' or v_msg !~ 'FIN:Approve' then
        raise exception 'assertion failed: expected the original insufficient_authority FIN:Approve message, got %', v_msg;
      end if;
      if v_msg !~ v_tenant::text then
        raise exception 'assertion failed: expected the tenant_id to STILL appear for a genuine same-tenant member (not a new disclosure to them) -- got %', v_msg;
      end if;
  end;

  if (select status from app.finance_accounts where id = v_account_id) <> 'draft' then
    raise exception 'assertion failed: neither refused call may have activated the account';
  end if;
end;
$$;

\echo '>> ISS-2026-146 (misc lane): the outsider is still a total stranger -- a sanity check that the fixture actually models "zero relationship", so the six generic not-found results above cannot be explained by anything else'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'iss146misc');
  v_member uuid := '00000000-0000-0000-0000-0000146b0002';
  v_outsider uuid := '00000000-0000-0000-0000-0000146b0003';
begin
  if app.has_active_tenant_membership(v_tenant, v_outsider) then
    raise exception 'assertion failed: the outsider fixture is wrong -- it holds an active membership in iss146misc';
  end if;
  if exists (select 1 from app.principal_memberships where auth_user_id = v_outsider) then
    raise exception 'assertion failed: the outsider fixture is wrong -- it holds a principal membership somewhere';
  end if;
  if not app.has_active_tenant_membership(v_tenant, v_member) then
    raise exception 'assertion failed: the member fixture is wrong -- it must be a genuine active member of iss146misc';
  end if;
end;
$$;

\echo '>> ISS-2026-146 (misc lane): all 6 module families PASSED -- outsider probes never see the real tenant_id, genuine same-tenant refusals are byte-identical to before this lane'
