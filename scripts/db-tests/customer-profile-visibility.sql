-- Real, executable test evidence for CPL-314 (CG-S13-CPL-016, Prompt 314,
-- "Customer Profile") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Structural convention mirrors
-- scripts/db-tests/customer-quote-requests.sql (CPL-302): two-tenant
-- fixture, direct RPC calls as the connecting superuser for
-- parameter-driven assertions, `set local role authenticated` + `set local
-- request.jwt.claims` only where the assertion genuinely needs a real
-- session.
--
-- UUID range 00000000-0000-0000-0000-000000330xxx (tenant cpp1) /
-- ...331xxx (tenant cpp2) -- grep-verified unclaimed before this file was
-- written. Tenant slugs cpp1/cpp2.
--
-- Covers, live: (1) submit rejects a forbidden field_name at the DATABASE
-- level (both the RPC's own early check AND the table's own
-- cppcr_field_name_check/cppcr_proposed_value_shape_check CHECK
-- constraints, proven by a raw superuser INSERT bypassing the RPC
-- entirely); (2) submit is scope-checked (account_not_available for an
-- unowned/forged account) and idempotent on (tenant, idempotency_key); (3)
-- withdraw is pending-only, any active account member may withdraw,
-- optimistic concurrency, out-of-scope is record_not_found; (4) list is
-- keyset-paginated, deny-by-default, cross-tenant isolated; (5)
-- get_customer_portal_account_profile is anti-enumerating and returns
-- legal_name/tax_id read-only plus a correct pending-change summary; (6)
-- list_customer_portal_account_contacts returns only this account's own
-- contacts, deny-by-default for an out-of-scope account; (7) staff
-- approval (COM:Approve) applies the change to the REAL app.accounts row
-- in the same transaction, bumping its own record_version; rejection
-- leaves app.accounts completely untouched; (8) a customer (Layer-4-only,
-- no COM:Approve) cannot decide any request -- confirms the decide RPC is
-- structurally staff-only; (9) cross-tenant/cross-account isolation
-- throughout; (10) raw-table RLS/grant defense-in-depth; (11) actor-identity
-- session cross-check; (12) a real, live authenticated-role positive path.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cpp1 (staff: portal/commercial admin with CPT:Create+COM:Create+COM:Approve, and a no-authority staff member; accounts Alpha/Beta; alpha-admin+alpha-member active on Alpha, beta-admin active on Beta, impersonator with zero relationship); a second, otherwise-empty tenant cpp2 (t2-admin on account T2) for cross-tenant isolation; a real contact linked to Account Alpha'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000330001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000330002';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000330010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000330011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000330020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000330050';
  v_staff2 uuid := '00000000-0000-0000-0000-000000331001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000331010';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_contact app.contacts;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@cpp1.test'),
    (v_staff_noauth, 'noauth@cpp1.test'),
    (v_alpha_admin, 'alpha-admin@cpp1.test'),
    (v_alpha_member, 'alpha-member@cpp1.test'),
    (v_beta_admin, 'beta-admin@cpp1.test'),
    (v_impersonator, 'impersonator@cpp1.test'),
    (v_staff2, 'staff@cpp2.test'),
    (v_t2_admin, 't2-admin@cpp2.test');

  perform app.provision_tenant('cpp1', 'Customer Profile Tenant One', 'idem-cpp1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cpp1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CPP1-CO', 'Cpp1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CPP1-CO');

  perform app.provision_tenant('cpp2', 'Customer Profile Tenant Two', 'idem-cpp2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cpp2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'CPP2-CO', 'Cpp2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@cpp1.test', 'Cpp1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cpp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_staff_noauth, 'noauth@cpp1.test', 'No Authority Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noauth@cpp1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@cpp2.test', 'Cpp2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cpp2.test'), 'active', 'onboarded', 'tester');

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

  insert into app.accounts (tenant_id, legal_name, trade_name, tax_id, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cpp1 Account Alpha Pte Ltd', 'Alpha Logistics', '01.111.222.3-000.000', 'cpp1-alpha-fp', jsonb_build_object('line1', 'Jl. Alpha 1', 'city', 'Jakarta', 'country', 'ID'), v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cpp1 Account Beta', 'cpp1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cpp2 Account T2', 'cpp2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'cpp1-staff');
  perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, v_alpha_member, 'member', v_alpha_admin, 'alpha-admin');
  perform app.accept_customer_portal_invite((select id from app.customer_portal_account_memberships where account_id = v_account_alpha and auth_user_id = v_alpha_member), 1, v_alpha_member);
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'cpp1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'cpp2-staff');

  -- v_impersonator deliberately holds ZERO customer-portal grant of any kind
  -- (used only as a genuinely different `authenticated` session identity in
  -- the actor-identity cross-check block below).

  -- A real contact linked to Account Alpha (COM-145/COM-155's own
  -- polymorphic app.contact_links, related_type='account').
  insert into app.contacts (tenant_id, full_name, title, email, phone, duplicate_fingerprint, org_unit_id, created_by)
  values (v_tenant1, 'Jane Requester', 'Ops Manager', 'jane@cpp1alpha.test', '0811', 'cpp1-jane-fp', v_company1, 'tester')
  returning * into v_contact;
  perform app.link_contact_to_record(v_contact.id, 'account', v_account_alpha, 'primary', true, v_staff, 'cpp1-staff');
end;
$$;

\echo '>> app.submit_customer_profile_change_request: forbidden field_name rejected both at the RPC AND at the raw table CHECK constraint; scope-checked; idempotent'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cpp1 Account Alpha Pte Ltd');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000330010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000330020';
  v_req app.customer_portal_profile_change_requests;
  v_req2 app.customer_portal_profile_change_requests;
  v_count integer;
begin
  -- (1a) RPC-level rejection for a forbidden field.
  begin
    perform app.submit_customer_profile_change_request(v_tenant1, v_account_alpha, 'legal_name', to_jsonb('Forged Legal Name'::text), 'forged-legal-name', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_field_name for legal_name';
  exception
    when others then
      if sqlerrm not like 'invalid_field_name%' then raise; end if;
  end;

  begin
    perform app.submit_customer_profile_change_request(v_tenant1, v_account_alpha, 'tax_id', to_jsonb('99.999.999.9-999.999'::text), 'forged-tax-id', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_field_name for tax_id';
  exception
    when others then
      if sqlerrm not like 'invalid_field_name%' then raise; end if;
  end;

  begin
    perform app.submit_customer_profile_change_request(v_tenant1, v_account_alpha, 'org_unit_id', to_jsonb('00000000-0000-0000-0000-000000000000'::text), 'forged-org-unit', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_field_name for org_unit_id';
  exception
    when others then
      if sqlerrm not like 'invalid_field_name%' then raise; end if;
  end;

  -- (1b) THE KEY REQUIRED TEST -- rejected at the DATABASE level, not just
  -- the RPC's own application-level check: a raw superuser INSERT bypassing
  -- app.submit_customer_profile_change_request entirely still fails the
  -- table's own cppcr_field_name_check CHECK constraint.
  begin
    insert into app.customer_portal_profile_change_requests (tenant_id, account_id, requested_by_actor_auth_user_id, field_name, proposed_value)
    values (v_tenant1, v_account_alpha, v_alpha_admin, 'legal_name', to_jsonb('Forged Legal Name'::text));
    raise exception 'assertion failed: expected a CHECK violation on a raw INSERT naming field_name=legal_name';
  exception
    when check_violation then
      null; -- expected
  end;

  begin
    insert into app.customer_portal_profile_change_requests (tenant_id, account_id, requested_by_actor_auth_user_id, field_name, proposed_value)
    values (v_tenant1, v_account_alpha, v_alpha_admin, 'owner_user_id', to_jsonb('00000000-0000-0000-0000-000000000000'::text));
    raise exception 'assertion failed: expected a CHECK violation on a raw INSERT naming field_name=owner_user_id';
  exception
    when check_violation then
      null; -- expected
  end;

  -- (1c) proposed_value shape mismatch also fails the table CHECK directly.
  begin
    insert into app.customer_portal_profile_change_requests (tenant_id, account_id, requested_by_actor_auth_user_id, field_name, proposed_value)
    values (v_tenant1, v_account_alpha, v_alpha_admin, 'billing_address', to_jsonb('not an object'::text));
    raise exception 'assertion failed: expected a CHECK violation for a non-object billing_address proposed_value';
  exception
    when check_violation then
      null; -- expected
  end;

  -- (2) Scope-checked: Beta's own admin may not propose a change for Account Alpha.
  begin
    perform app.submit_customer_profile_change_request(v_tenant1, v_account_alpha, 'trade_name', to_jsonb('Forged Name'::text), 'submit-beta-forged', v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected account_not_available for beta-admin acting on Account Alpha';
  exception
    when others then
      if sqlerrm not like 'account_not_available%' then raise; end if;
  end;

  -- Now a genuine, allowed submission.
  select * into v_req from app.submit_customer_profile_change_request(
    v_tenant1, v_account_alpha, 'trade_name', to_jsonb('Alpha Logistics Group'::text), 'submit-alpha-tradename-001', v_alpha_admin, 'alpha-admin'
  );
  if v_req.status <> 'pending' or v_req.account_id <> v_account_alpha or v_req.field_name <> 'trade_name' then
    raise exception 'assertion failed: expected a new pending trade_name request on Account Alpha';
  end if;

  -- Idempotent: same key returns the SAME row, no duplicate.
  select * into v_req2 from app.submit_customer_profile_change_request(
    v_tenant1, v_account_alpha, 'trade_name', to_jsonb('DIFFERENT -- must be ignored'::text), 'submit-alpha-tradename-001', v_alpha_admin, 'alpha-admin'
  );
  if v_req2.id <> v_req.id or v_req2.proposed_value <> v_req.proposed_value then
    raise exception 'assertion failed: expected idempotent submit to return the original row unchanged';
  end if;
  select count(*) into v_count from app.customer_portal_profile_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-tradename-001';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one row for idempotency key submit-alpha-tradename-001, found %', v_count;
  end if;

  -- Same key against a DIFFERENT account is a real conflict, never a silent cross-account return.
  begin
    perform app.submit_customer_profile_change_request(v_tenant1, (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cpp1 Account Beta'), 'trade_name', to_jsonb('x'::text), 'submit-alpha-tradename-001', v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected idempotency_key_conflict for a colliding key against a different account';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- invalid_proposed_value: an empty trade_name string.
  begin
    perform app.submit_customer_profile_change_request(v_tenant1, v_account_alpha, 'trade_name', to_jsonb(''::text), 'submit-alpha-empty', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_proposed_value for an empty trade_name';
  exception
    when others then
      if sqlerrm not like 'invalid_proposed_value%' then raise; end if;
  end;

  -- A second, real submission for billing_address (used by the withdraw/decide tests below).
  perform app.submit_customer_profile_change_request(
    v_tenant1, v_account_alpha, 'billing_address', jsonb_build_object('line1', 'Jl. Alpha 2 New', 'city', 'Jakarta', 'country', 'ID'),
    'submit-alpha-billing-001', v_alpha_admin, 'alpha-admin'
  );
end;
$$;

\echo '>> app.withdraw_customer_profile_change_request: pending-only, any active account member may withdraw, optimistic concurrency, out-of-scope is record_not_found'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000330010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000330011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000330020';
  v_req app.customer_portal_profile_change_requests;
  v_withdrawn app.customer_portal_profile_change_requests;
begin
  select * into v_req from app.customer_portal_profile_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-billing-001';

  -- Beta's own admin may not withdraw an Alpha request.
  begin
    perform app.withdraw_customer_profile_change_request(v_req.id, v_req.record_version, v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected record_not_found for beta-admin withdrawing an Alpha request';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  -- A DIFFERENT active member of the SAME account (alpha-member, not the original requester alpha-admin) may withdraw it.
  select * into v_withdrawn from app.withdraw_customer_profile_change_request(v_req.id, v_req.record_version, v_alpha_member, 'alpha-member');
  if v_withdrawn.status <> 'withdrawn' then
    raise exception 'assertion failed: expected pending -> withdrawn';
  end if;

  begin
    perform app.withdraw_customer_profile_change_request(v_withdrawn.id, v_withdrawn.record_version, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_transition -- withdrawn is terminal';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Stale version on the still-pending trade_name request.
  select * into v_req from app.customer_portal_profile_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-tradename-001';
  begin
    perform app.withdraw_customer_profile_change_request(v_req.id, v_req.record_version + 99, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;
end;
$$;

\echo '>> app.list_customer_portal_profile_change_requests: keyset-paginated, deny-by-default, cross-tenant isolated'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cpp2');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000330010';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000331010';
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_portal_profile_change_requests(v_tenant1, v_alpha_admin, null, null, null, null, 50);
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 visible profile change request for alpha-admin, found %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_portal_profile_change_requests(v_tenant1, v_alpha_admin, null, 'pending', null, null, 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 pending request for alpha-admin (trade_name only, billing_address was withdrawn), found %', v_count;
  end if;

  -- Cross-tenant isolation: t2-admin (standing only in cpp2) sees nothing when probing cpp1.
  select count(*) into v_count from app.list_customer_portal_profile_change_requests(v_tenant1, v_t2_admin, null, null, null, null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for t2-admin probing tenant cpp1, found %', v_count;
  end if;

  -- t2-admin's own tenant (cpp2) genuinely has zero requests of any kind.
  select count(*) into v_count from app.list_customer_portal_profile_change_requests(v_tenant2, v_t2_admin, null, null, null, null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for t2-admin in its own (request-free) tenant, found %', v_count;
  end if;
end;
$$;

\echo '>> app.get_customer_portal_account_profile: anti-enumerating, legal_name/tax_id read-only, correct pending-change summary'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cpp1 Account Alpha Pte Ltd');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000330010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000330020';
  v_profile record;
begin
  select * into v_profile from app.get_customer_portal_account_profile(v_tenant1, v_alpha_admin, v_account_alpha);
  if v_profile.legal_name <> 'Cpp1 Account Alpha Pte Ltd' or v_profile.tax_id <> '01.111.222.3-000.000' then
    raise exception 'assertion failed: expected legal_name/tax_id to be readable (read-only) for the account''s own scoped identity';
  end if;
  if v_profile.trade_name <> 'Alpha Logistics' then
    raise exception 'assertion failed: expected the CURRENT (not-yet-approved) trade_name to still read Alpha Logistics';
  end if;
  if v_profile.pending_change_request_count <> 1 or v_profile.latest_pending_change_request_field <> 'trade_name' then
    raise exception 'assertion failed: expected exactly 1 pending change (trade_name) in the summary, got count=% field=%', v_profile.pending_change_request_count, v_profile.latest_pending_change_request_field;
  end if;

  -- Anti-enumeration: a genuinely nonexistent account id and an out-of-scope account id (Beta's own scope, probed by an Alpha-only identity) raise the IDENTICAL record_not_found.
  begin
    perform app.get_customer_portal_account_profile(v_tenant1, v_alpha_admin, gen_random_uuid());
    raise exception 'assertion failed: expected record_not_found for a genuinely nonexistent account';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  begin
    perform app.get_customer_portal_account_profile(v_tenant1, v_beta_admin, v_account_alpha);
    raise exception 'assertion failed: expected record_not_found (not a distinguishable forbidden) for beta-admin probing Account Alpha';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;
end;
$$;

\echo '>> app.list_customer_portal_account_contacts: read-only, only this account''s own contacts, deny-by-default'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cpp1 Account Alpha Pte Ltd');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cpp1 Account Beta');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000330010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000330020';
  v_count integer;
  v_name text;
begin
  select count(*), max(full_name) into v_count, v_name from app.list_customer_portal_account_contacts(v_tenant1, v_alpha_admin, v_account_alpha);
  if v_count <> 1 or v_name <> 'Jane Requester' then
    raise exception 'assertion failed: expected exactly 1 contact (Jane Requester) visible to alpha-admin, found % (%)', v_count, v_name;
  end if;

  -- Beta has no contacts linked -- deny-by-default empty result, never an error.
  select count(*) into v_count from app.list_customer_portal_account_contacts(v_tenant1, v_beta_admin, v_account_beta);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero contacts for Account Beta, found %', v_count;
  end if;

  -- Out-of-scope: beta-admin may not see Alpha's own contacts.
  select count(*) into v_count from app.list_customer_portal_account_contacts(v_tenant1, v_beta_admin, v_account_alpha);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for beta-admin probing Account Alpha''s own contacts, found %', v_count;
  end if;
end;
$$;

\echo '>> app.decide_customer_profile_change_request: staff-only (COM:Approve); approve applies to the REAL app.accounts row in the same transaction; reject leaves app.accounts untouched; a customer cannot decide any request'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cpp1 Account Alpha Pte Ltd');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000330010';
  v_staff uuid := '00000000-0000-0000-0000-000000330001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000330002';
  v_req app.customer_portal_profile_change_requests;
  v_reject_req app.customer_portal_profile_change_requests;
  v_decided app.customer_portal_profile_change_requests;
  v_account_before app.accounts;
  v_account_after app.accounts;
begin
  select * into v_req from app.customer_portal_profile_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-tradename-001';
  select * into v_account_before from app.accounts where id = v_account_alpha;

  -- (8) A customer -- even the account's own admin, Layer-4-only, no COM:Approve -- cannot decide.
  begin
    perform app.decide_customer_profile_change_request(v_req.id, v_req.record_version, 'approve', 'self-serve attempt', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected insufficient_authority for a customer identity attempting to decide a request';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A staff identity with zero standing in this tenant (from cpp2) gets the anti-enumerating not-found, never a tenant-revealing error.
  begin
    perform app.decide_customer_profile_change_request(v_req.id, v_req.record_version, 'approve', 'wrong tenant', '00000000-0000-0000-0000-000000331001', 'cpp2-staff');
    raise exception 'assertion failed: expected profile_change_request_not_found for a staff identity with zero standing in this tenant';
  exception
    when others then
      if sqlerrm not like 'profile_change_request_not_found%' then raise; end if;
  end;

  -- A staff member of the RIGHT tenant but lacking COM:Approve gets an informative insufficient_authority.
  begin
    perform app.decide_customer_profile_change_request(v_req.id, v_req.record_version, 'approve', 'no authority', v_staff_noauth, 'noauth-staff');
    raise exception 'assertion failed: expected insufficient_authority for staff lacking COM:Approve';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Mandatory, non-empty review reason, for approve too (not just reject).
  begin
    perform app.decide_customer_profile_change_request(v_req.id, v_req.record_version, 'approve', '', v_staff, 'cpp1-staff');
    raise exception 'assertion failed: expected reason_required for an empty review reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- (7) The real approval: applies to app.accounts in the SAME transaction.
  select * into v_decided from app.decide_customer_profile_change_request(v_req.id, v_req.record_version, 'approve', 'verified via phone call with customer', v_staff, 'cpp1-staff');
  if v_decided.status <> 'approved' or v_decided.reviewed_by <> 'cpp1-staff' or v_decided.review_reason <> 'verified via phone call with customer' then
    raise exception 'assertion failed: expected approved with reviewer evidence recorded';
  end if;

  select * into v_account_after from app.accounts where id = v_account_alpha;
  if v_account_after.trade_name <> 'Alpha Logistics Group' then
    raise exception 'assertion failed: expected app.accounts.trade_name to be updated to Alpha Logistics Group, got %', v_account_after.trade_name;
  end if;
  if v_account_after.record_version <= v_account_before.record_version then
    raise exception 'assertion failed: expected app.accounts.record_version to advance (effective-versioned), before=% after=%', v_account_before.record_version, v_account_after.record_version;
  end if;
  -- Untouched fields confirm this was a narrow, targeted UPDATE, not a wholesale row rewrite.
  if v_account_after.legal_name <> v_account_before.legal_name or v_account_after.tax_id <> v_account_before.tax_id or v_account_after.billing_address <> v_account_before.billing_address then
    raise exception 'assertion failed: expected only trade_name to change -- legal_name/tax_id/billing_address must be untouched by this approval';
  end if;

  -- Deciding an already-decided (terminal) request is invalid_transition.
  begin
    perform app.decide_customer_profile_change_request(v_decided.id, v_decided.record_version, 'approve', 'again', v_staff, 'cpp1-staff');
    raise exception 'assertion failed: expected invalid_transition -- approved is terminal';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- A REJECT path leaves app.accounts completely untouched.
  select * into v_reject_req from app.submit_customer_profile_change_request(
    v_tenant1, v_account_alpha, 'billing_address', jsonb_build_object('line1', 'Jl. Rejected St', 'city', 'Bandung', 'country', 'ID'),
    'submit-alpha-billing-reject-001', v_alpha_admin, 'alpha-admin'
  );
  select * into v_account_before from app.accounts where id = v_account_alpha;
  select * into v_decided from app.decide_customer_profile_change_request(v_reject_req.id, v_reject_req.record_version, 'reject', 'billing address could not be verified', v_staff, 'cpp1-staff');
  if v_decided.status <> 'rejected' then
    raise exception 'assertion failed: expected rejected';
  end if;
  select * into v_account_after from app.accounts where id = v_account_alpha;
  if v_account_after.billing_address <> v_account_before.billing_address or v_account_after.record_version <> v_account_before.record_version then
    raise exception 'assertion failed: expected app.accounts to be COMPLETELY untouched by a rejection';
  end if;

  -- The decide RPC's own audit trail never persists the free-text review_reason unredacted.
  if exists (
    select 1 from app.audit_logs
    where action = 'decide_customer_profile_change_request'
      and resource_id = v_reject_req.id
      and (before_value::text like '%billing address could not be verified%' or after_value::text like '%billing address could not be verified%')
  ) then
    raise exception 'assertion failed: expected review_reason to NOT be routed into the audit before/after snapshot unredacted';
  end if;
end;
$$;

\echo '>> app.decide_customer_profile_change_request: self-approval guard (design decision 10) -- LIVE, not just TS-mocked. Structurally unreachable via any real front-door flow today (a customer_user identity never holds an active app.tenant_user_identities row, ISS-2026-040), so this deliberately grants ONE identity BOTH a real customer_user membership AND real staff COM:Approve -- mirroring scripts/db-tests/hris-payroll.sql''s own established "same actor as requester AND approver" pattern for the identical class of defense-in-depth guard (HRT-282 C-18) -- to actually execute the SQL branch, not merely trust the code reads correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cpp1 Account Beta');
  v_staff uuid := '00000000-0000-0000-0000-000000330001';
  v_self_req app.customer_portal_profile_change_requests;
begin
  -- v_staff already holds COM:Approve (tenant-wide staff role, granted in
  -- setup) -- additionally seed it a real customer_user account_admin
  -- membership on Beta (a second admin on an already-admin'd account is
  -- explicitly permitted by app.grant_initial_customer_portal_account_admin
  -- itself, not a fixture hack). Nothing in this repository's own schema
  -- prevents one auth_user_id from holding both an active app.tenant_user_
  -- identities row and an active app.customer_portal_account_memberships
  -- row simultaneously -- ISS-2026-040's own "not currently exploitable
  -- under this repository's own current role-assignment discipline"
  -- framing is an operational practice, not a database constraint, which is
  -- exactly why this guard is retained as defense-in-depth rather than
  -- omitted as impossible.
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_staff, v_staff, 'cpp1-staff');

  select * into v_self_req from app.submit_customer_profile_change_request(
    v_tenant1, v_account_beta, 'trade_name', to_jsonb('Self Approval Probe Co'::text),
    'submit-beta-self-approval-001', v_staff, 'cpp1-staff'
  );
  if v_self_req.requested_by_actor_auth_user_id <> v_staff then
    raise exception 'assertion failed (fixture bug): expected v_staff to be requested_by_actor_auth_user_id on its own submission';
  end if;

  begin
    perform app.decide_customer_profile_change_request(v_self_req.id, v_self_req.record_version, 'approve', 'approving my own request', v_staff, 'cpp1-staff');
    raise exception 'SECURITY FAILURE: v_staff (the requester of record) self-approved its own profile change request despite holding real COM:Approve authority';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_permitted%' then raise; end if;
      raise notice 'OK: self-approval (approve) blocked live (%)', sqlerrm;
  end;

  -- The guard is checked BEFORE the approve/reject branch (design decision
  -- 10's own text: "an actor may not decide their own... request", not
  -- "may not approve") -- unconditional, not approve-specific. Re-verified
  -- live rather than assumed from reading the function body alone: a
  -- self-reject attempt by the SAME dual-standing identity is blocked
  -- identically, and app.accounts stays untouched either way (no other
  -- COM:Approve holder without a conflicting standing exists in this
  -- fixture to use as a cleanup decider, so v_self_req is deliberately left
  -- pending -- it affects no other assertion in this file).
  begin
    perform app.decide_customer_profile_change_request(v_self_req.id, v_self_req.record_version, 'reject', 'rejecting my own request', v_staff, 'cpp1-staff');
    raise exception 'SECURITY FAILURE: v_staff self-rejected its own profile change request -- the guard must be unconditional, not approve-only';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_permitted%' then raise; end if;
      raise notice 'OK: self-approval (reject) blocked live (%)', sqlerrm;
  end;
end;
$$;

\echo '>> raw-table RLS/grant defense-in-depth: authenticated holds NO direct table privilege (service_role only); anon holds no EXECUTE on any of the 6 new functions; authenticated/service_role hold EXECUTE'
do $$
declare
  v_fn text;
  v_has_priv boolean;
  v_functions text[] := array[
    'app.submit_customer_profile_change_request(uuid, uuid, text, jsonb, text, uuid, text)',
    'app.withdraw_customer_profile_change_request(uuid, integer, uuid, text)',
    'app.list_customer_portal_profile_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.get_customer_portal_account_profile(uuid, uuid, uuid)',
    'app.list_customer_portal_account_contacts(uuid, uuid, uuid)',
    'app.decide_customer_profile_change_request(uuid, integer, text, text, uuid, text)'
  ];
begin
  if has_table_privilege('authenticated', 'app.customer_portal_profile_change_requests', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT hold SELECT on app.customer_portal_profile_change_requests directly -- the RPC layer is the only sanctioned access path';
  end if;
  if has_table_privilege('authenticated', 'app.customer_portal_profile_change_requests', 'INSERT') then
    raise exception 'assertion failed: authenticated must NOT hold INSERT on app.customer_portal_profile_change_requests directly';
  end if;
  if not has_table_privilege('service_role', 'app.customer_portal_profile_change_requests', 'SELECT') then
    raise exception 'assertion failed: service_role SHOULD hold SELECT on app.customer_portal_profile_change_requests';
  end if;

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

  -- A raw, real authenticated session genuinely cannot read the table at all.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000330010", "role": "authenticated"}';
  begin
    perform count(*) from app.customer_portal_profile_change_requests;
    raise exception 'assertion failed: expected a permission-denied error on a raw authenticated SELECT against app.customer_portal_profile_change_requests';
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
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cpp1 Account Alpha Pte Ltd');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000330050", "role": "authenticated"}';
  begin
    -- Real session is impersonator (330050); this call claims to act as alpha-admin (330010).
    perform app.submit_customer_profile_change_request(v_tenant1, v_account_alpha, 'trade_name', to_jsonb('forged'::text), 'forged-key', '00000000-0000-0000-0000-000000330010', 'forged-label');
    raise exception 'assertion failed: expected actor_identity_mismatch on submit';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_profile_change_requests(v_tenant1, '00000000-0000-0000-0000-000000330010', null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on list (the free actor-identity parameter is the entire scoping mechanism)';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  reset role;
end;
$$;

\echo '>> a real, live authenticated-role positive-path call: alpha-admin''s own real session gets the same real data a direct superuser call would'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_direct_count integer;
  v_session_count integer;
begin
  select count(*) into v_direct_count from app.list_customer_portal_profile_change_requests(v_tenant1, '00000000-0000-0000-0000-000000330010', null, null, null, null, 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000330010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_profile_change_requests(v_tenant1, '00000000-0000-0000-0000-000000330010', null, null, null, null, 200);
  reset role;

  if v_session_count <> v_direct_count or v_session_count = 0 then
    raise exception 'assertion failed: expected the real authenticated session to see the SAME nonzero row count (%) as the direct superuser call (%)', v_session_count, v_direct_count;
  end if;
end;
$$;

\echo '>> CPL-324 Tier C fix regression: optimistic-concurrency NULL-bypass on app.withdraw_customer_profile_change_request/app.decide_customer_profile_change_request -- a NULL p_expected_version is rejected with stale_version, the row proven byte-for-byte unchanged, then the real version succeeds (20260801260000)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpp1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cpp1 Account Alpha Pte Ltd');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000330010';
  v_staff uuid := '00000000-0000-0000-0000-000000330001';
  v_req app.customer_portal_profile_change_requests;
  v_after app.customer_portal_profile_change_requests;
begin
  -- withdraw_customer_profile_change_request
  v_req := app.submit_customer_profile_change_request(v_tenant1, v_account_alpha, 'trade_name', to_jsonb('Null Bypass Withdraw Probe'::text), 'null-bypass-cpp-withdraw', v_alpha_admin, 'alpha-admin');

  begin
    perform app.withdraw_customer_profile_change_request(v_req.id, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on withdraw_customer_profile_change_request';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  select * into v_after from app.customer_portal_profile_change_requests where id = v_req.id;
  if v_after.status <> v_req.status or v_after.record_version <> v_req.record_version then
    raise exception 'assertion failed: expected the profile change request to be byte-for-byte unchanged after a rejected NULL-bypass withdraw attempt, got %', v_after;
  end if;

  v_after := app.withdraw_customer_profile_change_request(v_req.id, v_req.record_version, v_alpha_admin, 'alpha-admin');
  if v_after.status <> 'withdrawn' then
    raise exception 'assertion failed: expected the real-version withdraw call to succeed, got %', v_after;
  end if;

  -- decide_customer_profile_change_request
  v_req := app.submit_customer_profile_change_request(v_tenant1, v_account_alpha, 'trade_name', to_jsonb('Null Bypass Decide Probe'::text), 'null-bypass-cpp-decide', v_alpha_admin, 'alpha-admin');

  begin
    perform app.decide_customer_profile_change_request(v_req.id, null, 'approve', 'forged decision', v_staff, 'cpp1-staff');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on decide_customer_profile_change_request';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  select * into v_after from app.customer_portal_profile_change_requests where id = v_req.id;
  if v_after.status <> v_req.status or v_after.record_version <> v_req.record_version then
    raise exception 'assertion failed: expected the profile change request to be byte-for-byte unchanged after a rejected NULL-bypass decide attempt, got %', v_after;
  end if;

  v_after := app.decide_customer_profile_change_request(v_req.id, v_req.record_version, 'approve', 'real-version decision', v_staff, 'cpp1-staff');
  if v_after.status <> 'approved' then
    raise exception 'assertion failed: expected the real-version decide call to succeed, got %', v_after;
  end if;
end $$;
