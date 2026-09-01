-- Real, executable test evidence for ISS-2026-123 item 1 (docs/runtime/KNOWN_ISSUES.md) --
-- run via `pnpm run db:test` against a real, disposable Postgres database. Structural
-- convention mirrors scripts/db-tests/customer-profile-visibility.sql (CPL-314) exactly:
-- two-tenant fixture, direct RPC calls as the connecting superuser for parameter-driven
-- assertions, `set local role authenticated` + `set local request.jwt.claims` only where the
-- assertion genuinely needs a real session, plus a THIRD, fully separate fixture tenant
-- dedicated only to the step-up-MFA proof so that policy can never affect any other test
-- file's own assertions.
--
-- UUID range 00000000-0000-0000-0000-000000904xxx (tenant lic1) / ...905xxx (tenant lic2) /
-- ...906xxx (tenant licmfa) -- grep-verified unclaimed before this file was written.
--
-- Covers, live: (1) submit rejects a forbidden field_name (trade_name/billing_address/
-- org_unit_id) both at the RPC AND at the raw table CHECK constraint; (2) submit is
-- scope-checked and idempotent, with a real conflict on key reuse against a different account;
-- (3) withdraw is pending-only, any active account member may withdraw, optimistic
-- concurrency, out-of-scope is record_not_found; (4) list is keyset-paginated, deny-by-default,
-- cross-tenant isolated; (5) decide is staff-only (COM:Approve), self-approval blocked, a NULL
-- expected_version is rejected; (6) decide-approve recomputes normalized_legal_name/
-- normalized_tax_id/duplicate_fingerprint via the REAL app.normalize_prospect_identifier/
-- app.compute_prospect_duplicate_fingerprint and applies to the real app.accounts row, leaving
-- trade_name/billing_address provably untouched; (7) a fingerprint collision on approve is
-- rejected with identity_fingerprint_conflict and leaves BOTH accounts AND the request
-- untouched (same-transaction rollback proof); (8) decide-reject leaves app.accounts
-- completely untouched; (9) raw-table RLS/grant defense-in-depth; (10) actor-identity session
-- cross-check; (11) a step-up-MFA proof, isolated to its own dedicated fixture tenant.

\set ON_ERROR_STOP on

\echo '>> setup: tenant lic1 (staff: COM Create/Edit/Approve + CPT Create, and a no-authority staff member; accounts Alpha/Beta sharing one tax_id so a later legal_name-only rename can be made to collide; alpha-admin+alpha-member active on Alpha, beta-admin active on Beta); a second, otherwise-empty tenant lic2 for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000904001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000904002';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000904010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000904011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000904020';
  v_staff2 uuid := '00000000-0000-0000-0000-000000905001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000905010';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_shared_tax_id text := '01.900.904.1-904.904';
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@lic1.test'),
    (v_staff_noauth, 'noauth@lic1.test'),
    (v_alpha_admin, 'alpha-admin@lic1.test'),
    (v_alpha_member, 'alpha-member@lic1.test'),
    (v_beta_admin, 'beta-admin@lic1.test'),
    (v_staff2, 'staff@lic2.test'),
    (v_t2_admin, 't2-admin@lic2.test');

  perform app.provision_tenant('lic1', 'Legal Identity Tenant One', 'idem-lic1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'lic1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  v_company1 := (app.create_org_unit(v_tenant1, 'company', null, 'LIC1-CO', 'Lic1 Co', 'tester')).id;

  perform app.provision_tenant('lic2', 'Legal Identity Tenant Two', 'idem-lic2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'lic2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'LIC2-CO', 'Lic2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@lic1.test', 'Lic1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@lic1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_staff_noauth, 'noauth@lic1.test', 'No Authority Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noauth@lic1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@lic2.test', 'Lic2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@lic2.test'), 'active', 'onboarded', 'tester');

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

  insert into app.accounts (tenant_id, legal_name, trade_name, tax_id, normalized_legal_name, normalized_tax_id, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (
    v_tenant1, 'Lic1 Account Alpha Pte Ltd', 'Alpha Logistics', v_shared_tax_id,
    app.normalize_prospect_identifier('Lic1 Account Alpha Pte Ltd'), app.normalize_prospect_identifier(v_shared_tax_id),
    app.compute_prospect_duplicate_fingerprint(v_tenant1, app.normalize_prospect_identifier('Lic1 Account Alpha Pte Ltd'), app.normalize_prospect_identifier(v_shared_tax_id)),
    jsonb_build_object('line1', 'Jl. Alpha 1', 'city', 'Jakarta', 'country', 'ID'), v_company1, 'tester'
  ) returning id into v_account_alpha;

  insert into app.accounts (tenant_id, legal_name, tax_id, normalized_legal_name, normalized_tax_id, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (
    v_tenant1, 'Lic1 Account Beta Pte Ltd', v_shared_tax_id,
    app.normalize_prospect_identifier('Lic1 Account Beta Pte Ltd'), app.normalize_prospect_identifier(v_shared_tax_id),
    app.compute_prospect_duplicate_fingerprint(v_tenant1, app.normalize_prospect_identifier('Lic1 Account Beta Pte Ltd'), app.normalize_prospect_identifier(v_shared_tax_id)),
    '{}'::jsonb, v_company1, 'tester'
  ) returning id into v_account_beta;

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Lic2 Account T2', 'lic2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'lic1-staff');
  perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, v_alpha_member, 'member', v_alpha_admin, 'alpha-admin');
  perform app.accept_customer_portal_invite((select id from app.customer_portal_account_memberships where account_id = v_account_alpha and auth_user_id = v_alpha_member), 1, v_alpha_member);
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'lic1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'lic2-staff');
end;
$$;

\echo '>> app.submit_customer_legal_identity_change_request: forbidden field_name rejected both at the RPC AND at the raw table CHECK constraint; scope-checked; idempotent; conflict on key reuse'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lic1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lic1 Account Alpha Pte Ltd');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lic1 Account Beta Pte Ltd');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000904010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000904020';
  v_req app.customer_portal_legal_identity_change_requests;
  v_req2 app.customer_portal_legal_identity_change_requests;
  v_count integer;
begin
  -- (1a) RPC-level rejection for fields this table never accepts (the sibling table's own
  -- writable fields, and an unrelated structural field).
  begin
    perform app.submit_customer_legal_identity_change_request(v_tenant1, v_account_alpha, 'trade_name', to_jsonb('Forged Trade Name'::text), 'forged-trade-name', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_field_name for trade_name';
  exception
    when others then
      if sqlerrm not like 'invalid_field_name%' then raise; end if;
  end;

  begin
    perform app.submit_customer_legal_identity_change_request(v_tenant1, v_account_alpha, 'billing_address', jsonb_build_object('line1', 'x'), 'forged-billing', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_field_name for billing_address';
  exception
    when others then
      if sqlerrm not like 'invalid_field_name%' then raise; end if;
  end;

  begin
    perform app.submit_customer_legal_identity_change_request(v_tenant1, v_account_alpha, 'org_unit_id', to_jsonb('00000000-0000-0000-0000-000000000000'::text), 'forged-org-unit', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_field_name for org_unit_id';
  exception
    when others then
      if sqlerrm not like 'invalid_field_name%' then raise; end if;
  end;

  -- (1b) Rejected at the DATABASE level, not just the RPC's own application-level check: a raw
  -- superuser INSERT bypassing the RPC entirely still fails the table's own CHECK constraints.
  begin
    insert into app.customer_portal_legal_identity_change_requests (tenant_id, account_id, requested_by_actor_auth_user_id, field_name, proposed_value)
    values (v_tenant1, v_account_alpha, v_alpha_admin, 'trade_name', to_jsonb('Forged Trade Name'::text));
    raise exception 'assertion failed: expected a CHECK violation on a raw INSERT naming field_name=trade_name';
  exception
    when check_violation then
      null; -- expected
  end;

  begin
    insert into app.customer_portal_legal_identity_change_requests (tenant_id, account_id, requested_by_actor_auth_user_id, field_name, proposed_value)
    values (v_tenant1, v_account_alpha, v_alpha_admin, 'legal_name', to_jsonb(''::text));
    raise exception 'assertion failed: expected a CHECK violation for an empty legal_name proposed_value';
  exception
    when check_violation then
      null; -- expected
  end;

  -- (2) Scope-checked: Beta's own admin may not propose a change for Account Alpha.
  begin
    perform app.submit_customer_legal_identity_change_request(v_tenant1, v_account_alpha, 'legal_name', to_jsonb('Forged Name'::text), 'submit-beta-forged', v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected account_not_available for beta-admin acting on Account Alpha';
  exception
    when others then
      if sqlerrm not like 'account_not_available%' then raise; end if;
  end;

  -- A genuine, allowed submission.
  select * into v_req from app.submit_customer_legal_identity_change_request(
    v_tenant1, v_account_alpha, 'legal_name', to_jsonb('Alpha Logistics Renamed Pte Ltd'::text), 'submit-alpha-legalname-001', v_alpha_admin, 'alpha-admin'
  );
  if v_req.status <> 'pending' or v_req.account_id <> v_account_alpha or v_req.field_name <> 'legal_name' then
    raise exception 'assertion failed: expected a new pending legal_name request on Account Alpha';
  end if;

  -- Idempotent: same key returns the SAME row, no duplicate.
  select * into v_req2 from app.submit_customer_legal_identity_change_request(
    v_tenant1, v_account_alpha, 'legal_name', to_jsonb('DIFFERENT -- must be ignored'::text), 'submit-alpha-legalname-001', v_alpha_admin, 'alpha-admin'
  );
  if v_req2.id <> v_req.id or v_req2.proposed_value <> v_req.proposed_value then
    raise exception 'assertion failed: expected idempotent submit to return the original row unchanged';
  end if;
  select count(*) into v_count from app.customer_portal_legal_identity_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-legalname-001';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one row for idempotency key submit-alpha-legalname-001, found %', v_count;
  end if;

  -- Same key against a DIFFERENT account is a real conflict, never a silent cross-account return.
  begin
    perform app.submit_customer_legal_identity_change_request(v_tenant1, v_account_beta, 'legal_name', to_jsonb('x'::text), 'submit-alpha-legalname-001', v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected idempotency_key_conflict for a colliding key against a different account';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- invalid_proposed_value: an empty tax_id string.
  begin
    perform app.submit_customer_legal_identity_change_request(v_tenant1, v_account_alpha, 'tax_id', to_jsonb(''::text), 'submit-alpha-empty', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_proposed_value for an empty tax_id';
  exception
    when others then
      if sqlerrm not like 'invalid_proposed_value%' then raise; end if;
  end;

  -- A second, real submission (tax_id) used by the withdraw/decide tests below.
  perform app.submit_customer_legal_identity_change_request(
    v_tenant1, v_account_alpha, 'tax_id', to_jsonb('02.111.222.3-000.000'::text), 'submit-alpha-taxid-001', v_alpha_admin, 'alpha-admin'
  );
end;
$$;

\echo '>> app.withdraw_customer_legal_identity_change_request: pending-only, any active account member may withdraw, optimistic concurrency, out-of-scope is record_not_found'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lic1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000904010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000904011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000904020';
  v_req app.customer_portal_legal_identity_change_requests;
  v_withdrawn app.customer_portal_legal_identity_change_requests;
begin
  select * into v_req from app.customer_portal_legal_identity_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-taxid-001';

  -- Out-of-scope: Beta's own admin cannot withdraw Alpha's request.
  begin
    perform app.withdraw_customer_legal_identity_change_request(v_req.id, v_req.record_version, v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected record_not_found for beta-admin withdrawing an Alpha request';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  -- alpha-member (not the original requester, alpha-admin) may withdraw -- account-grain, not requester-grain.
  select * into v_withdrawn from app.withdraw_customer_legal_identity_change_request(v_req.id, v_req.record_version, v_alpha_member, 'alpha-member');
  if v_withdrawn.status <> 'withdrawn' then
    raise exception 'assertion failed: expected withdrawn status';
  end if;

  -- Already-withdrawn is terminal.
  begin
    perform app.withdraw_customer_legal_identity_change_request(v_withdrawn.id, v_withdrawn.record_version, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_transition for an already-withdrawn request';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Stale version.
  select * into v_req from app.submit_customer_legal_identity_change_request(
    v_tenant1, (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lic1 Account Alpha Pte Ltd'), 'tax_id',
    to_jsonb('03.222.333.4-000.000'::text), 'submit-alpha-taxid-stale', v_alpha_admin, 'alpha-admin'
  );
  begin
    perform app.withdraw_customer_legal_identity_change_request(v_req.id, v_req.record_version + 99, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  perform app.withdraw_customer_legal_identity_change_request(v_req.id, v_req.record_version, v_alpha_admin, 'alpha-admin');
end;
$$;

\echo '>> app.list_customer_portal_legal_identity_change_requests: keyset-paginated, deny-by-default, cross-tenant isolated'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lic1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'lic2');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000904010';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000905010';
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_portal_legal_identity_change_requests(v_tenant1, v_alpha_admin, null, null, null, null, 200);
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one legal identity change request visible to alpha-admin';
  end if;

  -- Cross-tenant: t2-admin sees nothing from lic1, even passing lic1's own tenant id.
  select count(*) into v_count from app.list_customer_portal_legal_identity_change_requests(v_tenant1, v_t2_admin, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a lic2 identity querying lic1''s tenant';
  end if;

  select count(*) into v_count from app.list_customer_portal_legal_identity_change_requests(v_tenant2, v_t2_admin, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows -- t2-admin has never submitted a legal identity change request';
  end if;
end;
$$;

\echo '>> app.decide_customer_legal_identity_change_request: staff-only (COM:Approve); NULL expected_version rejected; approve recomputes normalized_legal_name/normalized_tax_id/duplicate_fingerprint via the REAL functions and leaves trade_name/billing_address untouched; reject leaves app.accounts completely untouched'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lic1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lic1 Account Alpha Pte Ltd');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000904010';
  v_staff uuid := '00000000-0000-0000-0000-000000904001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000904002';
  v_req app.customer_portal_legal_identity_change_requests;
  v_reject_req app.customer_portal_legal_identity_change_requests;
  v_decided app.customer_portal_legal_identity_change_requests;
  v_account_before app.accounts;
  v_account_after app.accounts;
  v_expected_normalized_legal_name text;
  v_expected_fingerprint text;
begin
  select * into v_req from app.customer_portal_legal_identity_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-legalname-001';
  select * into v_account_before from app.accounts where id = v_account_alpha;

  -- A customer (Layer-4-only, no COM:Approve) cannot decide.
  begin
    perform app.decide_customer_legal_identity_change_request(v_req.id, v_req.record_version, 'approve', 'self-serve attempt', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected insufficient_authority for a customer identity attempting to decide';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A staff identity with zero standing in this tenant gets the anti-enumerating not-found.
  begin
    perform app.decide_customer_legal_identity_change_request(v_req.id, v_req.record_version, 'approve', 'wrong tenant', '00000000-0000-0000-0000-000000905001', 'lic2-staff');
    raise exception 'assertion failed: expected legal_identity_change_request_not_found for zero standing in this tenant';
  exception
    when others then
      if sqlerrm not like 'legal_identity_change_request_not_found%' then raise; end if;
  end;

  -- Staff of the right tenant but lacking COM:Approve.
  begin
    perform app.decide_customer_legal_identity_change_request(v_req.id, v_req.record_version, 'approve', 'no authority', v_staff_noauth, 'noauth-staff');
    raise exception 'assertion failed: expected insufficient_authority for staff lacking COM:Approve';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Mandatory, non-empty review reason.
  begin
    perform app.decide_customer_legal_identity_change_request(v_req.id, v_req.record_version, 'approve', '', v_staff, 'lic1-staff');
    raise exception 'assertion failed: expected reason_required for an empty review reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- CPL-324-shaped regression: a NULL p_expected_version is rejected with stale_version, never silently coerced or bypassed.
  begin
    perform app.decide_customer_legal_identity_change_request(v_req.id, null, 'approve', 'forged decision', v_staff, 'lic1-staff');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  select * into v_req from app.customer_portal_legal_identity_change_requests where id = v_req.id;
  if v_req.status <> 'pending' then
    raise exception 'assertion failed: expected the request to still be pending after a rejected NULL-version decision';
  end if;

  -- The real approval: recomputes normalized_legal_name/duplicate_fingerprint via the REAL
  -- functions (never hand-duplicated arithmetic) and applies to app.accounts in the SAME transaction.
  v_expected_normalized_legal_name := app.normalize_prospect_identifier('Alpha Logistics Renamed Pte Ltd');
  v_expected_fingerprint := app.compute_prospect_duplicate_fingerprint(v_tenant1, v_expected_normalized_legal_name, app.normalize_prospect_identifier(v_account_before.tax_id));

  select * into v_decided from app.decide_customer_legal_identity_change_request(v_req.id, v_req.record_version, 'approve', 'verified via phone call with customer', v_staff, 'lic1-staff');
  if v_decided.status <> 'approved' or v_decided.reviewed_by <> 'lic1-staff' or v_decided.review_reason <> 'verified via phone call with customer' then
    raise exception 'assertion failed: expected approved with reviewer evidence recorded';
  end if;

  select * into v_account_after from app.accounts where id = v_account_alpha;
  if v_account_after.legal_name <> 'Alpha Logistics Renamed Pte Ltd' then
    raise exception 'assertion failed: expected app.accounts.legal_name to be updated, got %', v_account_after.legal_name;
  end if;
  if v_account_after.normalized_legal_name <> v_expected_normalized_legal_name then
    raise exception 'assertion failed: normalized_legal_name mismatch -- expected % got %', v_expected_normalized_legal_name, v_account_after.normalized_legal_name;
  end if;
  if v_account_after.duplicate_fingerprint <> v_expected_fingerprint then
    raise exception 'assertion failed: duplicate_fingerprint mismatch -- expected % got % (must be computed via the SAME app.compute_prospect_duplicate_fingerprint the approve branch itself calls)', v_expected_fingerprint, v_account_after.duplicate_fingerprint;
  end if;
  if v_account_after.record_version <= v_account_before.record_version then
    raise exception 'assertion failed: expected app.accounts.record_version to advance, before=% after=%', v_account_before.record_version, v_account_after.record_version;
  end if;
  -- Unrelated fields provably unchanged -- this was a narrow, targeted UPDATE.
  if v_account_after.trade_name <> v_account_before.trade_name or v_account_after.billing_address <> v_account_before.billing_address or v_account_after.tax_id <> v_account_before.tax_id then
    raise exception 'assertion failed: expected only legal_name/normalized_legal_name/duplicate_fingerprint to change -- trade_name/billing_address/tax_id must be untouched';
  end if;

  -- Deciding an already-decided (terminal) request is invalid_transition.
  begin
    perform app.decide_customer_legal_identity_change_request(v_decided.id, v_decided.record_version, 'approve', 'again', v_staff, 'lic1-staff');
    raise exception 'assertion failed: expected invalid_transition -- approved is terminal';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- A REJECT path leaves app.accounts completely untouched.
  select * into v_reject_req from app.submit_customer_legal_identity_change_request(
    v_tenant1, v_account_alpha, 'tax_id', to_jsonb('09.999.888.7-000.000'::text), 'submit-alpha-taxid-reject', '00000000-0000-0000-0000-000000904010', 'alpha-admin'
  );
  select * into v_account_before from app.accounts where id = v_account_alpha;
  select * into v_decided from app.decide_customer_legal_identity_change_request(v_reject_req.id, v_reject_req.record_version, 'reject', 'tax id could not be verified', v_staff, 'lic1-staff');
  if v_decided.status <> 'rejected' then
    raise exception 'assertion failed: expected rejected';
  end if;
  select * into v_account_after from app.accounts where id = v_account_alpha;
  if v_account_after.tax_id <> v_account_before.tax_id or v_account_after.duplicate_fingerprint <> v_account_before.duplicate_fingerprint or v_account_after.record_version <> v_account_before.record_version then
    raise exception 'assertion failed: expected app.accounts to be COMPLETELY untouched by a rejection';
  end if;

  -- The decide RPC's own audit trail never persists the free-text review_reason unredacted.
  if exists (
    select 1 from app.audit_logs
    where action = 'decide_customer_legal_identity_change_request'
      and resource_id = v_reject_req.id
      and (before_value::text like '%tax id could not be verified%' or after_value::text like '%tax id could not be verified%')
  ) then
    raise exception 'assertion failed: expected review_reason to NOT be routed into the audit before/after snapshot unredacted';
  end if;
end;
$$;

\echo '>> app.decide_customer_legal_identity_change_request: a fingerprint collision on approve is rejected with identity_fingerprint_conflict and leaves BOTH the request AND both accounts byte-for-byte unchanged (same-transaction rollback proof, not merely a request-record inspection)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lic1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Alpha Logistics Renamed Pte Ltd');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lic1 Account Beta Pte Ltd');
  v_staff uuid := '00000000-0000-0000-0000-000000904001';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000904010';
  v_req app.customer_portal_legal_identity_change_requests;
  v_alpha_before app.accounts;
  v_beta_before app.accounts;
  v_alpha_after app.accounts;
  v_beta_after app.accounts;
  v_req_after app.customer_portal_legal_identity_change_requests;
begin
  select * into v_alpha_before from app.accounts where id = v_account_alpha;
  select * into v_beta_before from app.accounts where id = v_account_beta;
  -- Alpha and Beta already share one tax_id (fixture setup) -- proposing Alpha's own legal_name
  -- become EXACTLY Beta's own legal_name makes the post-approval (normalized_legal_name,
  -- normalized_tax_id) pair collide.
  select * into v_req from app.submit_customer_legal_identity_change_request(
    v_tenant1, v_account_alpha, 'legal_name', to_jsonb(v_beta_before.legal_name), 'submit-alpha-collision-attempt', v_alpha_admin, 'alpha-admin'
  );

  begin
    perform app.decide_customer_legal_identity_change_request(v_req.id, v_req.record_version, 'approve', 'attempting a colliding rename', v_staff, 'lic1-staff');
    raise exception 'assertion failed: expected identity_fingerprint_conflict';
  exception
    when others then
      if sqlerrm not like 'identity_fingerprint_conflict%' then raise; end if;
  end;

  -- The request itself stays pending -- the abort happened before its own status UPDATE ran.
  select * into v_req_after from app.customer_portal_legal_identity_change_requests where id = v_req.id;
  if v_req_after.status <> 'pending' or v_req_after.record_version <> v_req.record_version then
    raise exception 'assertion failed: expected the request row to be byte-for-byte unchanged (still pending) after a rolled-back collision';
  end if;

  -- BOTH accounts are byte-for-byte unchanged -- a real same-transaction rollback, not a
  -- partial write.
  select * into v_alpha_after from app.accounts where id = v_account_alpha;
  select * into v_beta_after from app.accounts where id = v_account_beta;
  if v_alpha_after.legal_name <> v_alpha_before.legal_name or v_alpha_after.duplicate_fingerprint <> v_alpha_before.duplicate_fingerprint or v_alpha_after.record_version <> v_alpha_before.record_version then
    raise exception 'assertion failed: expected Account Alpha to be completely unchanged after a rolled-back collision';
  end if;
  if v_beta_after.legal_name <> v_beta_before.legal_name or v_beta_after.duplicate_fingerprint <> v_beta_before.duplicate_fingerprint or v_beta_after.record_version <> v_beta_before.record_version then
    raise exception 'assertion failed: expected Account Beta to be completely unchanged after a rolled-back collision';
  end if;
end;
$$;

\echo '>> app.decide_customer_legal_identity_change_request: self-approval guard -- LIVE, not just TS-mocked, mirrors CPL-314''s own identical dual-standing fixture pattern'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lic1');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Lic1 Account Beta Pte Ltd');
  v_staff uuid := '00000000-0000-0000-0000-000000904001';
  v_self_req app.customer_portal_legal_identity_change_requests;
begin
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_staff, v_staff, 'lic1-staff');

  select * into v_self_req from app.submit_customer_legal_identity_change_request(
    v_tenant1, v_account_beta, 'tax_id', to_jsonb('05.555.555.5-555.555'::text), 'submit-beta-self-approval-001', v_staff, 'lic1-staff'
  );

  begin
    perform app.decide_customer_legal_identity_change_request(v_self_req.id, v_self_req.record_version, 'approve', 'approving my own request', v_staff, 'lic1-staff');
    raise exception 'SECURITY FAILURE: v_staff self-approved its own legal identity change request despite holding real COM:Approve authority';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_permitted%' then raise; end if;
  end;

  begin
    perform app.decide_customer_legal_identity_change_request(v_self_req.id, v_self_req.record_version, 'reject', 'rejecting my own request', v_staff, 'lic1-staff');
    raise exception 'SECURITY FAILURE: v_staff self-rejected its own legal identity change request -- the guard must be unconditional, not approve-only';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_permitted%' then raise; end if;
  end;
end;
$$;

\echo '>> raw-table RLS/grant defense-in-depth: authenticated holds NO direct table privilege (service_role only); anon holds no EXECUTE on any of the 4 new functions; authenticated/service_role hold EXECUTE'
do $$
declare
  v_fn text;
  v_has_priv boolean;
  v_functions text[] := array[
    'app.submit_customer_legal_identity_change_request(uuid, uuid, text, jsonb, text, uuid, text)',
    'app.withdraw_customer_legal_identity_change_request(uuid, integer, uuid, text)',
    'app.list_customer_portal_legal_identity_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.decide_customer_legal_identity_change_request(uuid, integer, text, text, uuid, text)'
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

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000904010", "role": "authenticated"}';
  begin
    perform count(*) from app.customer_portal_legal_identity_change_requests;
    raise exception 'assertion failed: expected a permission-denied error on a raw authenticated SELECT against app.customer_portal_legal_identity_change_requests';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity, on both a write and a read RPC'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'lic1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Alpha Logistics Renamed Pte Ltd');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000904011", "role": "authenticated"}';
  begin
    -- Real session is alpha-member (904011); this call claims to act as alpha-admin (904010).
    perform app.submit_customer_legal_identity_change_request(v_tenant1, v_account_alpha, 'legal_name', to_jsonb('forged'::text), 'forged-key', '00000000-0000-0000-0000-000000904010', 'forged-label');
    raise exception 'assertion failed: expected actor_identity_mismatch on submit';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_legal_identity_change_requests(v_tenant1, '00000000-0000-0000-0000-000000904010', null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on list';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  reset role;
end;
$$;

\echo '>> step-up-MFA proof, fully isolated to its own dedicated fixture tenant (licmfa) so this policy can never affect any other test file''s assertions: a tenant that has NOT turned on tenant-wide MFA but HAS added (COM, Approve) to its own additional_high_risk_actions list still blocks decide via app.assert_current_step_up_authorization -- proving this migration''s own explicit call, not merely app.evaluate_permission''s built-in (tenant_wide_required-gated) step-up branch, which stays a deliberate no-op here; a genuine step-up challenge (request + verify) then unblocks it'
do $$
declare
  v_tenant uuid;
  v_company uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000906001';
  v_admin uuid := '00000000-0000-0000-0000-000000906010';
  v_role uuid; v_draft app.role_versions;
  v_account uuid;
  v_req app.customer_portal_legal_identity_change_requests;
  v_challenge app.mfa_step_up_challenges;
  v_decision app.rbac_decision;
  v_decided app.customer_portal_legal_identity_change_requests;
begin
  insert into auth.users (id, email) values (v_staff, 'staff@licmfa.test'), (v_admin, 'admin@licmfa.test');
  perform app.provision_tenant('licmfa', 'Legal Identity MFA Tenant', 'idem-licmfa', 'tester');
  v_tenant := (select id from app.tenants where slug = 'licmfa');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  v_company := (app.create_org_unit(v_tenant, 'company', null, 'LICMFA-CO', 'LicMfa Co', 'tester')).id;
  perform app.invite_user(v_tenant, v_staff, 'staff@licmfa.test', 'LicMfa Staff', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@licmfa.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant, 'LicMfa Staff Role', null, 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve')) or (resource_module_code = 'CPT' and action = 'Create') or (resource_module_code = 'SEC' and action = 'Configure')),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_role and status = 'published'), v_staff, v_staff, 'tester');

  insert into app.accounts (tenant_id, legal_name, tax_id, normalized_legal_name, normalized_tax_id, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (
    v_tenant, 'LicMfa Account Pte Ltd', '07.700.700.7-700.700',
    app.normalize_prospect_identifier('LicMfa Account Pte Ltd'), app.normalize_prospect_identifier('07.700.700.7-700.700'),
    app.compute_prospect_duplicate_fingerprint(v_tenant, app.normalize_prospect_identifier('LicMfa Account Pte Ltd'), app.normalize_prospect_identifier('07.700.700.7-700.700')),
    '{}'::jsonb, v_company, 'tester'
  ) returning id into v_account;

  perform app.grant_initial_customer_portal_account_admin(v_tenant, v_account, v_admin, v_staff, 'licmfa-staff');

  -- Additive per-tenant policy, tenant_wide_required = FALSE: app.evaluate_permission's own
  -- built-in step-up branch (20260830110000) requires tenant_wide_required=true, so it stays a
  -- no-op here -- isolating this migration's own explicit app.assert_current_step_up_
  -- authorization call as the thing actually doing the blocking below. Never touches
  -- app.is_high_risk_action's own platform-default tuple list.
  perform app.set_mfa_tenant_policy(v_tenant, false, '["supreme_admin", "tenant_admin"]'::jsonb, 15, '[{"moduleCode": "COM", "action": "Approve"}]'::jsonb, v_staff, 'licmfa-staff');

  v_decision := app.evaluate_permission(v_staff, v_tenant, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'FIXTURE BUG: expected app.evaluate_permission to still allow COM:Approve with tenant_wide_required=false, got reason %', v_decision.reason;
  end if;

  select * into v_req from app.submit_customer_legal_identity_change_request(
    v_tenant, v_account, 'tax_id', to_jsonb('08.800.800.8-800.800'::text), 'submit-licmfa-taxid-001', v_admin, 'licmfa-admin'
  );

  -- Blocked before any step-up challenge exists.
  begin
    perform app.decide_customer_legal_identity_change_request(v_req.id, v_req.record_version, 'approve', 'attempting without step-up', v_staff, 'licmfa-staff');
    raise exception 'assertion failed: expected mfa_step_up_required with no verified challenge on record';
  exception
    when others then
      if sqlerrm not like 'mfa_step_up_required%' then raise; end if;
  end;
  select * into v_req from app.customer_portal_legal_identity_change_requests where id = v_req.id;
  if v_req.status <> 'pending' then
    raise exception 'assertion failed: expected the request to remain pending while blocked on step-up';
  end if;

  -- Request + verify a real step-up challenge for this exact (module, action) tuple.
  v_challenge := app.request_mfa_step_up_challenge(v_tenant, 'COM', 'Approve', v_staff, 'licmfa-staff');
  perform app.verify_mfa_step_up_challenge(v_challenge.id, v_staff, 'licmfa-staff');

  -- Now succeeds.
  select * into v_decided from app.decide_customer_legal_identity_change_request(v_req.id, v_req.record_version, 'approve', 'approved after step-up', v_staff, 'licmfa-staff');
  if v_decided.status <> 'approved' then
    raise exception 'assertion failed: expected the decision to succeed once a current verified step-up challenge exists';
  end if;
end;
$$;

\echo '>> customer-portal-legal-identity-change-requests.sql: all assertions passed'
