-- Real, executable test evidence for the ISS-2026-123 staff-review list RPCs
-- (supabase/migrations/20260901100000_create_customer_portal_change_request_staff_review.sql)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.
--
-- UUID range 00000000-0000-0000-0000-000000910xxx (tenant srev1) / ...911xxx (tenant srev2) --
-- grep-verified unclaimed before this file was written.
--
-- Covers, live: (1) the account-scope-only customer-facing list RPCs return EMPTY for a staff
-- caller with no customer account scope, across all three tables -- the exact gap this
-- migration closes; (2) the new staff-review RPCs see every pending request tenant-wide,
-- regardless of which account it belongs to, for a COM:Approve holder; (3) deny-by-default: a
-- staff identity lacking COM:Approve, and a customer identity with real account scope but no
-- COM:Approve, both get an EMPTY result, never an error, from every staff-review RPC; (4)
-- cross-tenant isolation; (5) status filtering (pending vs approved); (6) raw-table/grant
-- defense-in-depth for the 3 new functions.

\set ON_ERROR_STOP on

\echo '>> setup: tenant srev1 (staff: COM Create/Edit/Approve + CPT Create, and a no-authority staff member; two accounts Alpha/Beta, each with their own admin, so pending requests span more than one account); a second, empty tenant srev2 for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000910001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000910002';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000910010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000910020';
  v_staff2 uuid := '00000000-0000-0000-0000-000000911001';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@srev1.test'),
    (v_staff_noauth, 'noauth@srev1.test'),
    (v_alpha_admin, 'alpha-admin@srev1.test'),
    (v_beta_admin, 'beta-admin@srev1.test'),
    (v_staff2, 'staff@srev2.test');

  perform app.provision_tenant('srev1', 'Staff Review Tenant One', 'idem-srev1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'srev1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  v_company1 := (app.create_org_unit(v_tenant1, 'company', null, 'SREV1-CO', 'Srev1 Co', 'tester')).id;

  perform app.provision_tenant('srev2', 'Staff Review Tenant Two', 'idem-srev2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'srev2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'SREV2-CO', 'Srev2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@srev1.test', 'Srev1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@srev1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_staff_noauth, 'noauth@srev1.test', 'No Authority Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noauth@srev1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@srev2.test', 'Srev2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@srev2.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant1, 'Commercial Portal Staff', 'CPT Create + COM Create/Edit/Approve', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'CPT' and action = 'Create') or (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve'))),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), v_staff, v_staff, 'tester');

  v_role2 := (app.create_role(v_tenant2, 'Portal Admin', 'CPT Create', 'tester')).id;
  v_draft2 := app.create_role_version(v_role2, 'tester');
  perform app.set_role_version_permissions(v_draft2.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_role2 and status = 'published'), v_staff2, v_staff2, 'tester');

  insert into app.accounts (tenant_id, legal_name, tax_id, normalized_legal_name, normalized_tax_id, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (
    v_tenant1, 'Srev1 Account Alpha Pte Ltd', '01.910.910.1-910.910',
    app.normalize_prospect_identifier('Srev1 Account Alpha Pte Ltd'), app.normalize_prospect_identifier('01.910.910.1-910.910'),
    app.compute_prospect_duplicate_fingerprint(v_tenant1, app.normalize_prospect_identifier('Srev1 Account Alpha Pte Ltd'), app.normalize_prospect_identifier('01.910.910.1-910.910')),
    '{}'::jsonb, v_company1, 'tester'
  ) returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Srev1 Account Beta', 'srev1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'srev1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'srev1-staff');

  -- One pending request per table, spread across BOTH accounts -- proves tenant-wide, not
  -- merely "the requesting staff member's own account scope" (staff has none anyway).
  perform app.submit_customer_profile_change_request(v_tenant1, v_account_alpha, 'trade_name', to_jsonb('Alpha New Trade Name'::text), 'srev1-tn-alpha', v_alpha_admin, 'alpha-admin');
  perform app.submit_customer_profile_change_request(v_tenant1, v_account_beta, 'billing_address', jsonb_build_object('line1', 'Jl. Beta'), 'srev1-ba-beta', v_beta_admin, 'beta-admin');
  perform app.submit_customer_legal_identity_change_request(v_tenant1, v_account_alpha, 'legal_name', to_jsonb('Srev1 Alpha Renamed'::text), 'srev1-ln-alpha', v_alpha_admin, 'alpha-admin');
  perform app.submit_customer_contact_change_request(v_tenant1, v_account_beta, 'add', null, 'Beta New Contact', null, 'beta-new@srev1.test', null, null, null, 'srev1-add-beta', v_beta_admin, 'beta-admin');
end;
$$;

\echo '>> the ORIGINAL, account-scope-only customer-facing list RPCs return EMPTY for a staff caller across all three tables -- the exact gap this migration closes'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srev1');
  v_staff uuid := '00000000-0000-0000-0000-000000910001';
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_portal_profile_change_requests(v_tenant1, v_staff, null, null, null, null, 200);
  if v_count <> 0 then raise exception 'FIXTURE ASSUMPTION VIOLATED: expected the account-scope-only list RPC to return empty for a staff caller, got %', v_count; end if;

  select count(*) into v_count from app.list_customer_portal_legal_identity_change_requests(v_tenant1, v_staff, null, null, null, null, 200);
  if v_count <> 0 then raise exception 'FIXTURE ASSUMPTION VIOLATED: expected the account-scope-only list RPC to return empty for a staff caller, got %', v_count; end if;

  select count(*) into v_count from app.list_customer_portal_contact_change_requests(v_tenant1, v_staff, null, null, null, null, 200);
  if v_count <> 0 then raise exception 'FIXTURE ASSUMPTION VIOLATED: expected the account-scope-only list RPC to return empty for a staff caller, got %', v_count; end if;
end;
$$;

\echo '>> the new staff-review RPCs see every pending request tenant-wide, spanning both accounts, for a COM:Approve holder; deny-by-default for staff lacking COM:Approve and for a customer identity with real account scope but no COM:Approve; status filtering; cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'srev1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'srev2');
  v_staff uuid := '00000000-0000-0000-0000-000000910001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000910002';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000910010';
  v_staff2 uuid := '00000000-0000-0000-0000-000000911001';
  v_count integer;
  v_accounts integer;
  v_req app.customer_portal_profile_change_requests;
begin
  -- (2) Tenant-wide visibility, spanning both accounts: Alpha's trade_name + Beta's billing_address.
  select count(*), count(distinct account_id) into v_count, v_accounts from app.list_profile_change_requests_staff_review(v_tenant1, v_staff, 'pending', null, null, 200);
  if v_count <> 2 or v_accounts <> 2 then raise exception 'FAIL: expected 2 pending profile change requests spanning 2 accounts, got % rows / % accounts', v_count, v_accounts; end if;

  select count(*), count(distinct account_id) into v_count, v_accounts from app.list_legal_identity_change_requests_staff_review(v_tenant1, v_staff, 'pending', null, null, 200);
  if v_count <> 1 then raise exception 'FAIL: expected 1 pending legal identity request, got %', v_count; end if;

  select count(*), count(distinct account_id) into v_count, v_accounts from app.list_contact_change_requests_staff_review(v_tenant1, v_staff, 'pending', null, null, 200);
  if v_count <> 1 then raise exception 'FAIL: expected 1 pending contact change request, got %', v_count; end if;

  -- Confirm BOTH accounts are represented across the profile-change-request table (Alpha's
  -- trade_name + Beta's billing_address).
  select count(distinct account_id) into v_accounts from app.list_profile_change_requests_staff_review(v_tenant1, v_staff, null, null, null, 200);
  if v_accounts <> 2 then raise exception 'FAIL: expected requests from BOTH accounts to be visible tenant-wide, got % distinct accounts', v_accounts; end if;

  -- (3) Deny-by-default: staff lacking COM:Approve.
  select count(*) into v_count from app.list_profile_change_requests_staff_review(v_tenant1, v_staff_noauth, 'pending', null, null, 200);
  if v_count <> 0 then raise exception 'FAIL: expected empty result for staff lacking COM:Approve, got %', v_count; end if;

  -- (3) Deny-by-default: a customer identity with real account scope but no COM:Approve.
  select count(*) into v_count from app.list_profile_change_requests_staff_review(v_tenant1, v_alpha_admin, 'pending', null, null, 200);
  if v_count <> 0 then raise exception 'FAIL: expected empty result for a customer identity with no COM:Approve, got %', v_count; end if;

  -- (5) Status filtering: decide one to 'approved', confirm it drops out of the pending filter
  -- and appears under 'approved'.
  select * into v_req from app.customer_portal_profile_change_requests where tenant_id = v_tenant1 and idempotency_key = 'srev1-tn-alpha';
  perform app.decide_customer_profile_change_request(v_req.id, v_req.record_version, 'approve', 'verified', v_staff, 'srev1-staff');

  select count(*) into v_count from app.list_profile_change_requests_staff_review(v_tenant1, v_staff, 'pending', null, null, 200);
  if v_count <> 1 then raise exception 'FAIL: expected 1 pending profile change request remaining (Beta''s billing_address) after deciding Alpha''s, got %', v_count; end if;

  select count(*) into v_count from app.list_profile_change_requests_staff_review(v_tenant1, v_staff, 'approved', null, null, 200);
  if v_count <> 1 then raise exception 'FAIL: expected 1 approved profile change request, got %', v_count; end if;

  -- (4) Cross-tenant isolation: srev2's own staff sees zero srev1 rows, even querying srev1's own tenant id.
  select count(*) into v_count from app.list_profile_change_requests_staff_review(v_tenant1, v_staff2, null, null, null, 200);
  if v_count <> 0 then raise exception 'FAIL: expected zero rows for a srev2 identity querying srev1''s tenant, got %', v_count; end if;

  select count(*) into v_count from app.list_profile_change_requests_staff_review(v_tenant2, v_staff2, null, null, null, 200);
  if v_count <> 0 then raise exception 'FAIL: expected zero rows -- srev2 has never had a profile change request submitted, got %', v_count; end if;
end;
$$;

\echo '>> raw-table/grant defense-in-depth for the 3 new staff-review functions: anon holds no EXECUTE; authenticated/service_role hold EXECUTE'
do $$
declare
  v_fn text;
  v_has_priv boolean;
  v_functions text[] := array[
    'app.list_profile_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer)',
    'app.list_legal_identity_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer)',
    'app.list_contact_change_requests_staff_review(uuid, uuid, text, timestamptz, uuid, integer)'
  ];
begin
  foreach v_fn in array v_functions loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has_priv;
    if v_has_priv then
      raise exception 'assertion failed: anon must NOT hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('service_role', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: service_role SHOULD hold EXECUTE on %', v_fn;
    end if;
  end loop;
end;
$$;

\echo '>> customer-portal-change-request-staff-review.sql: all assertions passed'
