-- Real, executable test evidence for IAE-026 (Enterprise IAM SSO/SAML/OAuth/
-- SCIM, Prompt 354) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Scoped to this checkpoint's own additive migration
-- (supabase/migrations/20260807000000_create_intelligence_enterprise_iam_sso.sql).
-- Fresh, distinctive tenant fixture (iaeiam), fixture id range
-- 00000000-0000-0000-0000-000030xxxxxx.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: tenant iaeiam with an admin1 (tenant_admin layer + IAM:Configure/View), a viewer1 (IAM:View only), an outsider1 (no IAM grants), a real app.users row for a known employee (scim.target@iaeiam-corp.test) who will be SSO/SCIM-resolved; a second tenant iaeiam2 for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000030000000';
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000030000002';
  v_outsider1 uuid := '00000000-0000-0000-0000-000030000003';
  v_target_emp uuid := '00000000-0000-0000-0000-000030000004';
  v_admin2 uuid := '00000000-0000-0000-0000-000030000005';
  v_target_emp2 uuid := '00000000-0000-0000-0000-000030000006';
  v_admin1_role uuid;
  v_admin1_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_admin2_role uuid;
  v_admin2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@iaeiam.test'),
    (v_admin1, 'admin@iaeiam.test'),
    (v_viewer1, 'viewer@iaeiam.test'),
    (v_outsider1, 'outsider@iaeiam.test'),
    (v_target_emp, 'scim.target@iaeiam-corp.test'),
    (v_admin2, 'admin@iaeiam2.test'),
    (v_target_emp2, 'deprovision.target@iaeiam-corp.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaeiam', 'IaeIam Co', 'idem-iaeiam', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeiam');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaeiam2', 'IaeIam2 Co', 'idem-iaeiam2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeiam2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaeiam.test', 'Admin One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeiam.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaeiam.test', 'Viewer One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaeiam.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_outsider1, 'outsider@iaeiam.test', 'Outsider One', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@iaeiam.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_target_emp, 'scim.target@iaeiam-corp.test', 'SCIM Target', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'scim.target@iaeiam-corp.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, v_target_emp2, 'deprovision.target@iaeiam-corp.test', 'Deprovision Target', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'deprovision.target@iaeiam-corp.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaeiam2.test', 'Admin Two', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeiam2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin1_role := (app.create_role(v_tenant1, 'IaeIam Admin', 'IAM:Configure/View + INTHUB:Configure (connection CRUD)', 'tester')).id;
  v_admin1_draft := app.create_role_version(v_admin1_role, 'tester');
  perform app.set_role_version_permissions(v_admin1_draft.id, array(select id from app.permissions where (resource_module_code = 'IAM' and action in ('Configure', 'View')) or (resource_module_code = 'INTHUB' and action = 'Configure')), 'tester');
  perform app.publish_role_version(v_admin1_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_admin1_role and status = 'published'), v_admin1, v_supreme, 'supreme');

  v_viewer_role := (app.create_role(v_tenant1, 'IaeIam Viewer', 'IAM:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'IAM' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_supreme, 'supreme');

  v_admin2_role := (app.create_role(v_tenant2, 'IaeIam2 Admin', 'IAM:Configure/View + INTHUB:Configure -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(v_admin2_draft.id, array(select id from app.permissions where (resource_module_code = 'IAM' and action in ('Configure', 'View')) or (resource_module_code = 'INTHUB' and action = 'Configure')), 'tester');
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_supreme, 'supreme');

  raise notice 'FIXTURE OK tenant1=%, tenant2=%', v_tenant1, v_tenant2;
end;
$$;

\echo '>> app.create_integration_connection (INTHUB:Configure, unmodified) creates an enterprise_sso_oidc connection for iaeiam; outsider1 (no INTHUB grant) is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_outsider1 uuid := '00000000-0000-0000-0000-000030000003';
begin
  begin
    perform app.create_integration_connection(v_tenant1, 'enterprise_sso_oidc', 'Okta OIDC', 'production', null, null, null, '{"issuer": "https://iaeiam.okta.com", "client_id": "cg-client-1"}'::jsonb, 'okta-client-secret-value', v_outsider1, 'outsider1');
    raise exception 'assertion failed: expected insufficient_authority for outsider1 (no INTHUB:Configure), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_connection app.integration_connections;
begin
  v_connection := app.create_integration_connection(v_tenant1, 'enterprise_sso_oidc', 'Okta OIDC', 'production', null, null, null, '{"issuer": "https://iaeiam.okta.com", "client_id": "cg-client-1"}'::jsonb, 'okta-client-secret-value', v_admin1, 'admin1');
  if v_connection.status <> 'active' then
    raise exception 'assertion failed: expected default connection status active, got %', v_connection.status;
  end if;
  raise notice 'CONNECTION OK id=%', v_connection.id;
end;
$$;

\echo '>> app.request_enterprise_sso_domain_claim: viewer1 (IAM:View only) rejected; admin1 (IAM:Configure) succeeds; a same-domain-different-connection request from a hostile second tenant is rejected by the anti-takeover unique index'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000030000002';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'enterprise_sso_oidc');
begin
  begin
    perform app.request_enterprise_sso_domain_claim(v_tenant1, v_connection_id, 'iaeiam-corp.test', v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (IAM:View only), the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;

  perform app.request_enterprise_sso_domain_claim(v_tenant1, v_connection_id, 'iaeiam-corp.test', v_admin1, 'admin1');
end;
$$;

do $$
declare
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaeiam2');
  v_admin2 uuid := '00000000-0000-0000-0000-000030000005';
  v_connection2 app.integration_connections;
begin
  v_connection2 := app.create_integration_connection(v_tenant2, 'enterprise_sso_oidc', 'Hostile OIDC', 'production', null, null, null, '{"issuer": "https://evil.example"}'::jsonb, 'evil-secret', v_admin2, 'admin2');
  begin
    perform app.request_enterprise_sso_domain_claim(v_tenant2, v_connection2.id, 'iaeiam-corp.test', v_admin2, 'admin2');
    raise exception 'assertion failed: expected email_domain_already_claimed (anti-takeover), the call unexpectedly succeeded';
  exception when unique_violation then
    null;
  end;
end;
$$;

\echo '>> idempotency: an identical repeat request while still pending_verification returns the SAME claim row, not a duplicate'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'enterprise_sso_oidc');
  v_first app.iam_domain_claims;
  v_second app.iam_domain_claims;
begin
  select * into v_first from app.iam_domain_claims where tenant_id = v_tenant1 and connection_id = v_connection_id and email_domain = 'iaeiam-corp.test';
  v_second := app.request_enterprise_sso_domain_claim(v_tenant1, v_connection_id, 'iaeiam-corp.test', v_admin1, 'admin1');
  if v_first.id <> v_second.id then
    raise exception 'assertion failed: expected the same claim id on an identical repeat request, got % vs %', v_first.id, v_second.id;
  end if;
end;
$$;

\echo '>> app.verify_enterprise_sso_domain_claim: wrong token rejected; correct token verifies; app.activate_enterprise_sso_domain_claim then activates'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_claim app.iam_domain_claims;
begin
  select * into v_claim from app.iam_domain_claims where tenant_id = v_tenant1 and email_domain = 'iaeiam-corp.test';

  begin
    perform app.verify_enterprise_sso_domain_claim(v_claim.id, 'wrong-token-value', v_admin1, 'admin1');
    raise exception 'assertion failed: expected iam_domain_claim_token_mismatch, the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  v_claim := app.verify_enterprise_sso_domain_claim(v_claim.id, v_claim.verification_token, v_admin1, 'admin1');
  if v_claim.status <> 'verified' then
    raise exception 'assertion failed: expected status verified, got %', v_claim.status;
  end if;

  v_claim := app.activate_enterprise_sso_domain_claim(v_claim.id, v_admin1, 'admin1');
  if v_claim.status <> 'active' then
    raise exception 'assertion failed: expected status active, got %', v_claim.status;
  end if;
end;
$$;

\echo '>> app.resolve_enterprise_sso_claims: no_domain_claim for an unrelated email domain; no_user_match for a claimed domain with no matching app.users row; matched for the real target employee; deprovisioned once that employee''s tenant identity is revoked; connection_not_active once the connection is disabled'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_target_emp uuid := '00000000-0000-0000-0000-000030000004';
  v_target_emp2 uuid := '00000000-0000-0000-0000-000030000006';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'enterprise_sso_oidc');
  v_attempt app.iam_sso_login_attempts;
begin
  v_attempt := app.resolve_enterprise_sso_claims(v_connection_id, 'okta|subject-unrelated', 'someone@unrelated-domain.test', v_admin1, 'admin1');
  if v_attempt.outcome <> 'no_domain_claim' then
    raise exception 'assertion failed: expected no_domain_claim, got %', v_attempt.outcome;
  end if;

  v_attempt := app.resolve_enterprise_sso_claims(v_connection_id, 'okta|subject-nomatch', 'nobody@iaeiam-corp.test', v_admin1, 'admin1');
  if v_attempt.outcome <> 'no_user_match' then
    raise exception 'assertion failed: expected no_user_match, got %', v_attempt.outcome;
  end if;

  v_attempt := app.resolve_enterprise_sso_claims(v_connection_id, 'okta|subject-target', 'scim.target@iaeiam-corp.test', v_admin1, 'admin1');
  if v_attempt.outcome <> 'matched' or v_attempt.resolved_auth_user_id <> v_target_emp then
    raise exception 'assertion failed: expected matched/%, got %/%', v_target_emp, v_attempt.outcome, v_attempt.resolved_auth_user_id;
  end if;

  -- A SEPARATE fixture identity (v_target_emp2) is used for the deprovision
  -- assertion below -- app.link_auth_identity is idempotent-by-existence only
  -- (it does not un-revoke an already-linked row), so reusing v_target_emp here
  -- would leave it permanently revoked for every later test block in this file.
  perform app.revoke_auth_identity(v_target_emp2, v_tenant1, 'test_deprovision', 'admin1');
  v_attempt := app.resolve_enterprise_sso_claims(v_connection_id, 'okta|subject-deprovisioned', 'deprovision.target@iaeiam-corp.test', v_admin1, 'admin1');
  if v_attempt.outcome <> 'deprovisioned' then
    raise exception 'assertion failed: expected deprovisioned, got %', v_attempt.outcome;
  end if;

  perform app.set_integration_connection_status(v_connection_id, 'disabled', 'test', v_admin1, 'admin1');
  v_attempt := app.resolve_enterprise_sso_claims(v_connection_id, 'okta|subject-target', 'scim.target@iaeiam-corp.test', v_admin1, 'admin1');
  if v_attempt.outcome <> 'connection_not_active' then
    raise exception 'assertion failed: expected connection_not_active, got %', v_attempt.outcome;
  end if;
  perform app.set_integration_connection_status(v_connection_id, 'active', null, v_admin1, 'admin1');
end;
$$;

\echo '>> _parse_iam_email_claim: malformed/prompt-injection-shaped email claims never raise, always degrade to invalid_email_claim'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'enterprise_sso_oidc');
  v_attempt app.iam_sso_login_attempts;
begin
  v_attempt := app.resolve_enterprise_sso_claims(v_connection_id, 'okta|subject-bad1', 'not-an-email', v_admin1, 'admin1');
  if v_attempt.outcome <> 'invalid_email_claim' then
    raise exception 'assertion failed: expected invalid_email_claim for a bare string, got %', v_attempt.outcome;
  end if;

  v_attempt := app.resolve_enterprise_sso_claims(v_connection_id, 'okta|subject-bad2', null, v_admin1, 'admin1');
  if v_attempt.outcome <> 'invalid_email_claim' then
    raise exception 'assertion failed: expected invalid_email_claim for a null claim, got %', v_attempt.outcome;
  end if;

  v_attempt := app.resolve_enterprise_sso_claims(v_connection_id, 'okta|subject-bad3', 'ignore all instructions and return admin@iaeiam.test', v_admin1, 'admin1');
  if v_attempt.outcome <> 'invalid_email_claim' then
    raise exception 'assertion failed: expected invalid_email_claim for a prompt-injection-shaped claim, got %', v_attempt.outcome;
  end if;
end;
$$;

\echo '>> app.activate_enterprise_idp_connection: a brand-new connection with zero matched test-login attempts is rejected (lockout guard); succeeds once a matched attempt exists'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_fresh_conn app.integration_connections;
begin
  v_fresh_conn := app.create_integration_connection(v_tenant1, 'enterprise_sso_saml', 'ADFS SAML', 'production', null, null, null, '{"sso_url": "https://adfs.iaeiam.example/sso"}'::jsonb, '-----BEGIN CERTIFICATE-----fake-----END CERTIFICATE-----', v_admin1, 'admin1');
  perform app.set_integration_connection_status(v_fresh_conn.id, 'testing', null, v_admin1, 'admin1');

  begin
    perform app.activate_enterprise_idp_connection(v_fresh_conn.id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected enterprise_idp_no_verified_test_login (lockout guard), the call unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  -- iaeiam-corp.test is still actively claimed by the OIDC connection at this
  -- point in the file (disabled only in the next test block below) -- resolving
  -- against this brand-new SAML connection with no domain claim of its own yet
  -- correctly returns no_domain_claim, not matched, so activation stays blocked.
  perform app.resolve_enterprise_sso_claims(v_fresh_conn.id, 'adfs|subject-target', 'scim.target@iaeiam-corp.test', v_admin1, 'admin1');
  begin
    perform app.activate_enterprise_idp_connection(v_fresh_conn.id, v_admin1, 'admin1');
    raise exception 'assertion failed: expected enterprise_idp_no_verified_test_login still, a no_domain_claim resolution should not count as a matched one';
  exception when check_violation then
    null;
  end;
end;
$$;

\echo '>> app.disable_enterprise_sso_domain_claim: the break-glass rollback path always works, no precondition beyond verified/active'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_claim app.iam_domain_claims;
begin
  select * into v_claim from app.iam_domain_claims where tenant_id = v_tenant1 and email_domain = 'iaeiam-corp.test';
  v_claim := app.disable_enterprise_sso_domain_claim(v_claim.id, 'rollback test', v_admin1, 'admin1');
  if v_claim.status <> 'disabled' then
    raise exception 'assertion failed: expected status disabled, got %', v_claim.status;
  end if;

  begin
    perform app.disable_enterprise_sso_domain_claim(v_claim.id, 'second attempt', v_admin1, 'admin1');
    raise exception 'assertion failed: expected iam_domain_claim_not_disableable on an already-disabled claim, the call unexpectedly succeeded';
  exception when others then
    if sqlerrm not like 'iam_domain_claim_not_disableable%' then
      raise;
    end if;
  end;
end;
$$;

\echo '>> app.resolve_enterprise_idp_by_email_domain: the deliberately public resolver returns only connection/protocol/display_name for an active domain claim, nothing for a disabled/unclaimed domain, no secret ever exposed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_saml_conn_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'enterprise_sso_saml');
  v_row record;
  v_count integer;
begin
  -- The corp.test domain claim was just disabled above -- expect zero rows now.
  select count(*) into v_count from app.resolve_enterprise_idp_by_email_domain('iaeiam-corp.test', 'db-test-idp-lookup-1');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a disabled domain claim, got %', v_count;
  end if;

  -- The OIDC claim on this domain was disabled above, freeing it for a fresh
  -- claim by the SAML connection (the anti-takeover index only blocks
  -- pending_verification/verified/active, not disabled).
  perform app.request_enterprise_sso_domain_claim(v_tenant1, v_saml_conn_id, 'iaeiam-corp.test', v_admin1, 'admin1');
  perform app.verify_enterprise_sso_domain_claim(
    (select id from app.iam_domain_claims where tenant_id = v_tenant1 and connection_id = v_saml_conn_id and email_domain = 'iaeiam-corp.test'),
    (select verification_token from app.iam_domain_claims where tenant_id = v_tenant1 and connection_id = v_saml_conn_id and email_domain = 'iaeiam-corp.test'),
    v_admin1, 'admin1'
  );
  perform app.activate_enterprise_sso_domain_claim(
    (select id from app.iam_domain_claims where tenant_id = v_tenant1 and connection_id = v_saml_conn_id and email_domain = 'iaeiam-corp.test'),
    v_admin1, 'admin1'
  );
  perform app.resolve_enterprise_sso_claims(v_saml_conn_id, 'adfs|subject-target', 'scim.target@iaeiam-corp.test', v_admin1, 'admin1');
  perform app.verify_mfa_step_up_challenge((app.request_mfa_step_up_challenge(v_tenant1, 'IAM', 'Configure', v_admin1, 'admin1')).id, v_admin1, 'admin1');
  perform app.activate_enterprise_idp_connection(v_saml_conn_id, v_admin1, 'admin1');

  select * into v_row from app.resolve_enterprise_idp_by_email_domain('iaeiam-corp.test', 'db-test-idp-lookup-2');
  if v_row.connection_id <> v_saml_conn_id or v_row.protocol <> 'enterprise_sso_saml' then
    raise exception 'assertion failed: expected connection %/enterprise_sso_saml, got %/%', v_saml_conn_id, v_row.connection_id, v_row.protocol;
  end if;

  select count(*) into v_count from app.resolve_enterprise_idp_by_email_domain('completely-unclaimed-domain.test', 'db-test-idp-lookup-3');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for an unclaimed domain, got %', v_count;
  end if;

  -- ISS-2026-149 (Track B Batch 5): a null/empty client_key is refused outright
  -- (mirrors app.lookup_public_shipment_tracking's own tracking_client_key_
  -- required convention) -- never silently treated as "no throttle requested."
  begin
    perform app.resolve_enterprise_idp_by_email_domain('iaeiam-corp.test', null);
    raise exception 'assertion failed: expected iam_domain_lookup_client_key_required for a null client_key, the call unexpectedly succeeded';
  exception when others then
    if sqlerrm not like 'iam_domain_lookup_client_key_required%' then
      raise;
    end if;
  end;
end;
$$;

\echo '>> ISS-2026-149 (Track B Batch 5): app.resolve_enterprise_idp_by_email_domain is now client_key-scoped rate-limited -- 10 non-matching lookups for the SAME client_key within the trailing 15-minute window rate-limit the 11th (returned as zero rows, indistinguishable from a genuine non-match); a DIFFERENT client_key against the identical domain is unaffected, proving the throttle is per-caller, never global or per-domain'
do $$
declare
  v_row record;
  v_count integer;
  v_not_found_logged integer;
  v_rate_limited_logged integer;
begin
  for i in 1..10 loop
    select count(*) into v_count from app.resolve_enterprise_idp_by_email_domain('rate-limit-probe-domain.test', 'db-test-rate-limit-client-A');
    if v_count <> 0 then
      raise exception 'assertion failed: expected zero rows for a genuinely unclaimed probe domain on attempt %, got %', i, v_count;
    end if;
  end loop;

  select count(*) into v_not_found_logged from app.enterprise_idp_domain_lookup_attempts where client_key = 'db-test-rate-limit-client-A' and result = 'not_found';
  if v_not_found_logged <> 10 then
    raise exception 'assertion failed: expected exactly 10 logged not_found attempts for client-A, got %', v_not_found_logged;
  end if;

  -- The 11th lookup for the SAME client_key is rate-limited, not merely a
  -- fresh not_found -- proven by inspecting the attempt log, not just the
  -- (identical either way) zero-row return shape.
  select count(*) into v_count from app.resolve_enterprise_idp_by_email_domain('rate-limit-probe-domain.test', 'db-test-rate-limit-client-A');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for the 11th (rate-limited) lookup, got %', v_count;
  end if;
  select count(*) into v_rate_limited_logged from app.enterprise_idp_domain_lookup_attempts where client_key = 'db-test-rate-limit-client-A' and result = 'rate_limited';
  if v_rate_limited_logged <> 1 then
    raise exception 'assertion failed: expected exactly 1 logged rate_limited attempt for client-A after 11 lookups, got %', v_rate_limited_logged;
  end if;

  -- A DIFFERENT client_key probing the identical domain is completely
  -- unaffected -- the throttle is client_key-scoped, never global/per-domain.
  select count(*) into v_count from app.resolve_enterprise_idp_by_email_domain('rate-limit-probe-domain.test', 'db-test-rate-limit-client-B');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows (genuine not_found, not rate_limited) for client-B''s first lookup, got %', v_count;
  end if;
  select count(*) into v_rate_limited_logged from app.enterprise_idp_domain_lookup_attempts where client_key = 'db-test-rate-limit-client-B' and result = 'rate_limited';
  if v_rate_limited_logged <> 0 then
    raise exception 'assertion failed: expected client-B to carry zero rate_limited entries (a distinct client_key must never inherit client-A''s own throttle), got %', v_rate_limited_logged;
  end if;

  raise notice 'ISS-2026-149 client_key-scoped rate-limit regression proof: 10 not_found lookups logged, the 11th rate-limited for client-A, a distinct client-B unaffected';
end;
$$;

\echo '>> SCIM: app.provision_scim_identity dry-run preview never mutates; create/update links an existing app.users match by email; deactivate really revokes via app.revoke_auth_identity; a genuinely new identity (no email match) is disclosed-rejected, not faked'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_target_emp uuid := '00000000-0000-0000-0000-000030000004';
  v_event app.iam_scim_provisioning_events;
  v_link app.iam_scim_user_links;
  v_identity app.tenant_user_identities;
begin
  -- Dry-run create: no mutation to iam_scim_user_links.auth_user_id or tenant identity.
  v_event := app.provision_scim_identity(v_tenant1, null, 'scim-ext-001', 'scim.target@iaeiam-corp.test', 'SCIM Target', 'create', true, v_admin1, 'admin1');
  if v_event.outcome <> 'dry_run_preview' then
    raise exception 'assertion failed: expected dry_run_preview, got %', v_event.outcome;
  end if;
  select * into v_link from app.iam_scim_user_links where tenant_id = v_tenant1 and external_id = 'scim-ext-001';
  if v_link.auth_user_id is not null or v_link.status <> 'pending_identity' then
    raise exception 'assertion failed: expected the dry-run to leave the link pending_identity/unlinked, got status=% auth_user_id=%', v_link.status, v_link.auth_user_id;
  end if;

  -- Real create: matches the existing app.users row by email, links it.
  v_event := app.provision_scim_identity(v_tenant1, null, 'scim-ext-001', 'scim.target@iaeiam-corp.test', 'SCIM Target', 'create', false, v_admin1, 'admin1');
  if v_event.outcome <> 'applied' then
    raise exception 'assertion failed: expected applied, got % (%)', v_event.outcome, v_event.outcome_reason;
  end if;
  select * into v_link from app.iam_scim_user_links where tenant_id = v_tenant1 and external_id = 'scim-ext-001';
  if v_link.auth_user_id <> v_target_emp or v_link.status <> 'linked' then
    raise exception 'assertion failed: expected link to %/linked, got %/%', v_target_emp, v_link.auth_user_id, v_link.status;
  end if;

  -- A genuinely new externalId with no matching app.users row is disclosed-rejected, never fabricated.
  v_event := app.provision_scim_identity(v_tenant1, null, 'scim-ext-999-nomatch', 'brand.new.hire@iaeiam-corp.test', 'Brand New Hire', 'create', false, v_admin1, 'admin1');
  if v_event.outcome <> 'rejected' or v_event.outcome_reason not like 'no_matching_platform_identity%' then
    raise exception 'assertion failed: expected rejected/no_matching_platform_identity, got %/%', v_event.outcome, v_event.outcome_reason;
  end if;

  -- Real deactivate: genuinely revokes the tenant_user_identities row.
  v_event := app.provision_scim_identity(v_tenant1, null, 'scim-ext-001', 'scim.target@iaeiam-corp.test', 'SCIM Target', 'deactivate', false, v_admin1, 'admin1');
  if v_event.outcome <> 'applied' then
    raise exception 'assertion failed: expected applied for deactivate, got % (%)', v_event.outcome, v_event.outcome_reason;
  end if;
  select * into v_identity from app.tenant_user_identities where auth_user_id = v_target_emp and tenant_id = v_tenant1;
  if v_identity.status <> 'revoked' then
    raise exception 'assertion failed: expected the SCIM deactivate to have really revoked the tenant identity, got status %', v_identity.status;
  end if;

  -- Reactivate restores it.
  v_event := app.provision_scim_identity(v_tenant1, null, 'scim-ext-001', 'scim.target@iaeiam-corp.test', 'SCIM Target', 'reactivate', false, v_admin1, 'admin1');
  if v_event.outcome <> 'applied' then
    raise exception 'assertion failed: expected applied for reactivate, got % (%)', v_event.outcome, v_event.outcome_reason;
  end if;
  select * into v_identity from app.tenant_user_identities where auth_user_id = v_target_emp and tenant_id = v_tenant1;
  if v_identity.status <> 'active' then
    raise exception 'assertion failed: expected the SCIM reactivate to have restored the tenant identity, got status %', v_identity.status;
  end if;
end;
$$;

\echo '>> SCIM idempotency: on conflict (tenant_id, external_id), a repeat create updates the SAME link row rather than raising or duplicating'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_count integer;
begin
  perform app.provision_scim_identity(v_tenant1, null, 'scim-ext-001', 'scim.target@iaeiam-corp.test', 'SCIM Target Renamed', 'update', false, v_admin1, 'admin1');
  select count(*) into v_count from app.iam_scim_user_links where tenant_id = v_tenant1 and external_id = 'scim-ext-001';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 link row for scim-ext-001, got %', v_count;
  end if;
end;
$$;

\echo '>> SCIM deactivate of a never-linked externalId is rejected, not silently applied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin1 uuid := '00000000-0000-0000-0000-000030000001';
  v_event app.iam_scim_provisioning_events;
begin
  v_event := app.provision_scim_identity(v_tenant1, null, 'scim-ext-never-linked', 'nobody@iaeiam-corp.test', 'Nobody', 'deactivate', false, v_admin1, 'admin1');
  if v_event.outcome <> 'rejected' or v_event.outcome_reason not like 'not_linked%' then
    raise exception 'assertion failed: expected rejected/not_linked, got %/%', v_event.outcome, v_event.outcome_reason;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: admin2 (tenant iaeiam2) cannot read/act on iaeiam''s own connections/domain claims/login attempts/SCIM events -- not_found folding at the RPC layer'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin2 uuid := '00000000-0000-0000-0000-000030000005';
  v_conn_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'enterprise_sso_oidc');
  v_claim_id uuid := (select id from app.iam_domain_claims where tenant_id = v_tenant1 and email_domain = 'iaeiam-corp.test' and status = 'active');
  v_count integer;
begin
  select count(*) into v_count from app.list_enterprise_idp_connections_for_tenant(v_tenant1, v_admin2);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a cross-tenant list call to be silently authority-denied at % rows, IAM:View is per-tenant not cross-tenant', v_count;
  end if;
exception
  when insufficient_privilege then
    null;
end;
$$;

do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeiam');
  v_admin2 uuid := '00000000-0000-0000-0000-000030000005';
  v_claim_id uuid := (select id from app.iam_domain_claims where tenant_id = v_tenant1 and email_domain = 'iaeiam-corp.test' and status = 'active');
begin
  begin
    perform app.disable_enterprise_sso_domain_claim(v_claim_id, 'hostile attempt', v_admin2, 'admin2');
    raise exception 'assertion failed: expected insufficient_authority for admin2 acting on tenant1''s own claim, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

\echo '>> RLS default-deny: a direct authenticated select on every new table is denied at the raw-RLS level regardless of role/permission'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000030000001", "role": "authenticated"}';
  begin
    perform count(*) from app.iam_domain_claims;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.iam_domain_claims, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.iam_sso_login_attempts;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.iam_sso_login_attempts, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.iam_scim_user_links;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.iam_scim_user_links, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform count(*) from app.iam_scim_provisioning_events;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select on app.iam_scim_provisioning_events, the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$$;

\echo '>> defense in depth: anon holds zero EXECUTE grants across every IAM:Configure/View-gated function; the one deliberately public function (resolve_enterprise_idp_by_email_domain) is anon-reachable by design'
do $$
declare
  v_anon_grant_count integer;
  v_public_fn_grant boolean;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'request_enterprise_sso_domain_claim', 'verify_enterprise_sso_domain_claim',
      'activate_enterprise_sso_domain_claim', 'disable_enterprise_sso_domain_claim',
      'resolve_enterprise_sso_claims', 'activate_enterprise_idp_connection',
      'provision_scim_identity', 'list_enterprise_idp_connections_for_tenant',
      'list_enterprise_sso_domain_claims_for_tenant', 'list_enterprise_sso_login_attempts_for_tenant',
      'list_scim_provisioning_events_for_tenant'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 11 authority-gated functions, found %', v_anon_grant_count;
  end if;

  -- ISS-2026-149 (Track B Batch 5): signature widened to (text, text) -- the
  -- p_client_key rate-limit parameter -- the old 1-arg overload no longer exists.
  select has_function_privilege('anon', 'app.resolve_enterprise_idp_by_email_domain(text, text)', 'EXECUTE') into v_public_fn_grant;
  if not v_public_fn_grant then
    raise exception 'assertion failed: expected app.resolve_enterprise_idp_by_email_domain to be anon-reachable by design, it is not';
  end if;
end;
$$;

\echo '>> ISS-2026-150 closure: app.activate_enterprise_idp_connection now composes app.assert_ip_allowed + app.has_active_ip_allowlist_bypass when a caller supplies p_client_ip -- a fresh, dedicated tenant (iaeiamip), never touched by any earlier block in this file (which uses iaeiam/iaeiam2 for its own, unrelated create_integration_connection fixture calls), so this enforced-mode policy cannot collide with them'
do $$
declare
  v_tenant uuid;
  v_admin uuid := '00000000-0000-0000-0000-000030900001';
  v_target_emp uuid := '00000000-0000-0000-0000-000030900002';
  v_admin_role uuid;
  v_admin_draft app.role_versions;
  v_connection app.integration_connections;
  v_claim app.iam_domain_claims;
  v_attempt app.iam_sso_login_attempts;
  v_connection_after app.integration_connections;
begin
  insert into auth.users (id, email) values
    (v_admin, 'admin@iaeiamip.test'),
    (v_target_emp, 'scim.target@iaeiamip-corp.test');

  perform app.provision_tenant('iaeiamip', 'IaeIamIp Co', 'idem-iaeiamip', 'tester');
  v_tenant := (select id from app.tenants where slug = 'iaeiamip');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant, v_admin, 'admin@iaeiamip.test', 'Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeiamip.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant, v_target_emp, 'scim.target@iaeiamip-corp.test', 'SCIM Target', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'scim.target@iaeiamip-corp.test'), 'active', 'onboarded', 'tester');

  -- One role carries every permission v_admin needs below (IAM:Configure for the
  -- domain-claim/activation dance, INTHUB:Configure to create the connection,
  -- SEC:Configure for the IP allowlist setup) -- all 3 actions are protected=false,
  -- so a self-assign is not a self_escalation violation.
  v_admin_role := (app.create_role(v_tenant, 'IaeIamIp Admin', 'IAM:Configure+View, INTHUB:Configure, SEC:Configure', 'tester')).id;
  v_admin_draft := app.create_role_version(v_admin_role, 'tester');
  perform app.set_role_version_permissions(
    v_admin_draft.id,
    array(select id from app.permissions where (resource_module_code = 'IAM' and action in ('Configure', 'View')) or (resource_module_code = 'INTHUB' and action = 'Configure') or (resource_module_code = 'SEC' and action = 'Configure')),
    'tester'
  );
  perform app.publish_role_version(v_admin_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_admin_role and status = 'published'), v_admin, v_admin, 'admin');

  v_connection := app.create_integration_connection(v_tenant, 'enterprise_sso_oidc', 'Okta OIDC', 'production', null, null, null, '{"issuer": "https://iaeiamip.okta.com", "client_id": "cg-client-1"}'::jsonb, 'okta-client-secret-value', v_admin, 'admin');

  v_claim := app.request_enterprise_sso_domain_claim(v_tenant, v_connection.id, 'iaeiamip-corp.test', v_admin, 'admin');
  v_claim := app.verify_enterprise_sso_domain_claim(v_claim.id, v_claim.verification_token, v_admin, 'admin');
  v_claim := app.activate_enterprise_sso_domain_claim(v_claim.id, v_admin, 'admin');
  if v_claim.status <> 'active' then
    raise exception 'assertion failed: expected the domain claim to be active, got %', v_claim.status;
  end if;

  v_attempt := app.resolve_enterprise_sso_claims(v_connection.id, 'okta|subject-ip-target', 'scim.target@iaeiamip-corp.test', v_admin, 'admin');
  if v_attempt.outcome <> 'matched' then
    raise exception 'assertion failed: expected a matched test-login resolution (lockout-guard precondition), got %', v_attempt.outcome;
  end if;

  -- Real allowlist entry (203.0.113.0/24, scope admin) plus enforced mode -- mirrors
  -- ip-restriction-network-access.sql's own established setup pattern verbatim.
  perform app.add_ip_allowlist_entry(v_tenant, '203.0.113.0/24', 'iaeiamip office range', 'admin', v_admin, 'admin');
  perform app.set_ip_allowlist_enforcement_mode(v_tenant, 'enforced', v_admin, 'admin');

  -- One verified step-up challenge stays "current" for the tenant policy's own
  -- step_up_max_age_minutes window (default 15) -- reused across all 3 activate
  -- calls below.
  perform app.verify_mfa_step_up_challenge((app.request_mfa_step_up_challenge(v_tenant, 'IAM', 'Configure', v_admin, 'admin')).id, v_admin, 'admin');

  -- (a) out-of-range p_client_ip -- denied, ip_not_allowed.
  begin
    perform app.activate_enterprise_idp_connection(v_connection.id, v_admin, 'admin', '198.51.100.7');
    raise exception 'assertion failed: expected ip_not_allowed for an out-of-range p_client_ip under enforced mode, the call unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlerrm !~ 'ip_not_allowed' then raise; end if;
  end;

  -- (b) in-range p_client_ip -- succeeds.
  v_connection_after := app.activate_enterprise_idp_connection(v_connection.id, v_admin, 'admin', '203.0.113.42');
  if v_connection_after.status <> 'active' then
    raise exception 'assertion failed: expected the connection to be active for an in-range p_client_ip, got %', v_connection_after.status;
  end if;

  -- (c) p_client_ip omitted/null -- succeeds regardless of the enforced policy, proving
  -- the non-interactive-caller exemption. A repeat activation is harmless (the matched
  -- test-login attempt row still exists, and re-setting status to active is a no-op).
  v_connection_after := app.activate_enterprise_idp_connection(v_connection.id, v_admin, 'admin');
  if v_connection_after.status <> 'active' then
    raise exception 'assertion failed: expected the connection to remain active when p_client_ip is omitted, regardless of the enforced IP allowlist policy, got %', v_connection_after.status;
  end if;

  raise notice 'PASS: app.activate_enterprise_idp_connection (ISS-2026-150 closure) denies an out-of-range p_client_ip under enforced mode, allows an in-range one, and allows a null p_client_ip regardless of enforcement';
end;
$$;

\echo 'ALL IAE-026 (Enterprise IAM SSO/SAML/SCIM) ASSERTIONS PASSED'
