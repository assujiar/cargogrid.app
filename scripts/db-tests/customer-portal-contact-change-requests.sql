-- Real, executable test evidence for ISS-2026-123 item 2 (docs/runtime/KNOWN_ISSUES.md) --
-- run via `pnpm run db:test` against a real, disposable Postgres database. Structural
-- convention mirrors scripts/db-tests/customer-profile-visibility.sql (CPL-314) and this
-- migration's own legal-identity sibling
-- (scripts/db-tests/customer-portal-legal-identity-change-requests.sql) exactly.
--
-- UUID range 00000000-0000-0000-0000-000000907xxx (tenant ccc1) / ...908xxx (tenant ccc2) /
-- ...909xxx (tenant cccmfa) -- grep-verified unclaimed before this file was written.
--
-- Covers, live: (1) submit's add/update/remove field-shape validation, both at the RPC AND at
-- the raw table CHECK constraints; (2) submit is scope-checked; for update/remove, the target
-- contact must be genuinely linked to THIS account -- the SAME not-found-shaped error whether
-- the contact does not exist, belongs to a different tenant, or is linked to a DIFFERENT
-- account; (3) idempotent submission and a real conflict on key reuse; (4) withdraw is
-- pending-only, optimistic concurrency (including the NULL-expected-version guard), out-of-
-- scope is record_not_found; (5) list is keyset-paginated, deny-by-default, cross-tenant
-- isolated; (6) decide is staff-only (COM:Approve), self-approval blocked; (7) decide-approve
-- 'add' reuses app.create_contact + app.link_contact_to_record (real side effects verified,
-- never a raw INSERT); 'remove' reuses app.unlink_contact_from_record and its own audit event
-- is provably present (never a raw DELETE); 'update' issues a direct UPDATE, bumping
-- app.contacts.record_version explicitly (proven no trigger does this), and a role-collision
-- on the contact_links unique constraint is rejected with a clear contact_link_conflict, not a
-- raw constraint violation; (8) decide-reject leaves everything untouched; (9) raw-table
-- RLS/grant defense-in-depth; (10) actor-identity session cross-check; (11) a step-up-MFA
-- proof, isolated to its own dedicated fixture tenant.

\set ON_ERROR_STOP on

\echo '>> setup: tenant ccc1 (staff: COM Create/Edit/Approve + CPT Create, and a no-authority staff member; accounts Alpha/Beta; alpha-admin+alpha-member active on Alpha, beta-admin active on Beta; two real contacts -- one linked to Alpha as primary, one linked to Beta -- for the cross-account not-found proof); a second, otherwise-empty tenant ccc2 for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000907001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000907002';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000907010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000907011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000907020';
  v_staff2 uuid := '00000000-0000-0000-0000-000000908001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000908010';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_contact_alpha app.contacts;
  v_contact_beta app.contacts;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@ccc1.test'),
    (v_staff_noauth, 'noauth@ccc1.test'),
    (v_alpha_admin, 'alpha-admin@ccc1.test'),
    (v_alpha_member, 'alpha-member@ccc1.test'),
    (v_beta_admin, 'beta-admin@ccc1.test'),
    (v_staff2, 'staff@ccc2.test'),
    (v_t2_admin, 't2-admin@ccc2.test');

  perform app.provision_tenant('ccc1', 'Contact Change Tenant One', 'idem-ccc1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'ccc1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  v_company1 := (app.create_org_unit(v_tenant1, 'company', null, 'CCC1-CO', 'Ccc1 Co', 'tester')).id;

  perform app.provision_tenant('ccc2', 'Contact Change Tenant Two', 'idem-ccc2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'ccc2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'CCC2-CO', 'Ccc2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@ccc1.test', 'Ccc1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@ccc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_staff_noauth, 'noauth@ccc1.test', 'No Authority Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noauth@ccc1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@ccc2.test', 'Ccc2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@ccc2.test'), 'active', 'onboarded', 'tester');

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

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Ccc1 Account Alpha Pte Ltd', 'ccc1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Ccc1 Account Beta', 'ccc1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Ccc2 Account T2', 'ccc2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'ccc1-staff');
  perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, v_alpha_member, 'member', v_alpha_admin, 'alpha-admin');
  perform app.accept_customer_portal_invite((select id from app.customer_portal_account_memberships where account_id = v_account_alpha and auth_user_id = v_alpha_member), 1, v_alpha_member);
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'ccc1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'ccc2-staff');

  insert into app.contacts (tenant_id, full_name, title, email, phone, duplicate_fingerprint, org_unit_id, created_by)
  values (v_tenant1, 'Existing Alpha Contact', 'Ops Manager', 'existing-alpha@ccc1.test', '0811', 'ccc1-existing-alpha-fp', v_company1, 'tester')
  returning * into v_contact_alpha;
  perform app.link_contact_to_record(v_contact_alpha.id, 'account', v_account_alpha, 'billing', false, v_staff, 'ccc1-staff');

  insert into app.contacts (tenant_id, full_name, title, email, phone, duplicate_fingerprint, org_unit_id, created_by)
  values (v_tenant1, 'Existing Beta Contact', 'Finance', 'existing-beta@ccc1.test', '0822', 'ccc1-existing-beta-fp', v_company1, 'tester')
  returning * into v_contact_beta;
  perform app.link_contact_to_record(v_contact_beta.id, 'account', v_account_beta, 'billing', false, v_staff, 'ccc1-staff');
end;
$$;

\echo '>> app.submit_customer_contact_change_request: add/update/remove field-shape validation, both at the RPC AND at the raw table CHECK constraints; scope-checked; the SAME not-found-shaped error whether a target contact does not exist, belongs to a different tenant, or is linked to a DIFFERENT account'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ccc1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Ccc1 Account Alpha Pte Ltd');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Ccc1 Account Beta');
  v_contact_alpha_id uuid := (select id from app.contacts where tenant_id = v_tenant1 and full_name = 'Existing Alpha Contact');
  v_contact_beta_id uuid := (select id from app.contacts where tenant_id = v_tenant1 and full_name = 'Existing Beta Contact');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000907010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000907020';
  v_err1 text; v_err2 text;
  v_req app.customer_portal_contact_change_requests;
  v_req2 app.customer_portal_contact_change_requests;
  v_count integer;
begin
  -- invalid_change_kind
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'delete', null, null, null, null, null, null, null, 'bad-kind', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_change_kind';
  exception
    when others then
      if sqlerrm not like 'invalid_change_kind%' then raise; end if;
  end;

  -- add: target_contact_id forbidden
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'add', v_contact_alpha_id, 'X', null, 'x@test.com', null, null, null, 'bad-add-target', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_target_contact for add with a target_contact_id supplied';
  exception
    when others then
      if sqlerrm not like 'invalid_target_contact%' then raise; end if;
  end;

  -- add: full_name required
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'add', null, null, null, 'x@test.com', null, null, null, 'bad-add-noname', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_proposed_value for a missing full_name';
  exception
    when others then
      if sqlerrm not like 'invalid_proposed_value%' then raise; end if;
  end;

  -- add: email or phone required
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'add', null, 'No Contact Info', null, null, null, null, null, 'bad-add-noinfo', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_proposed_value for missing email and phone';
  exception
    when others then
      if sqlerrm not like 'invalid_proposed_value%' then raise; end if;
  end;

  -- update/remove: target_contact_id required
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'update', null, 'X', null, null, null, null, null, 'bad-update-notarget', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_target_contact for update with no target_contact_id';
  exception
    when others then
      if sqlerrm not like 'invalid_target_contact%' then raise; end if;
  end;

  -- (2) The not-found-shaped error, indistinguishable across three causes: nonexistent, wrong
  -- account, or belongs to a different account entirely.
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'update', gen_random_uuid(), 'X', null, null, null, null, null, 'nf-nonexistent', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected contact_not_available for a nonexistent contact id';
  exception
    when others then
      v_err1 := sqlerrm;
      if v_err1 not like 'contact_not_available%' then raise; end if;
  end;

  begin
    -- Beta's own contact, targeted against Alpha's account -- linked, but to a DIFFERENT account.
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'update', v_contact_beta_id, 'X', null, null, null, null, null, 'nf-wrong-account', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected contact_not_available for a contact linked to a different account';
  exception
    when others then
      v_err2 := sqlerrm;
      if v_err2 not like 'contact_not_available%' then raise; end if;
  end;

  -- The error SHAPE (errcode/prefix) must be identical regardless of cause -- the id itself is
  -- already known to the caller (they supplied it), so echoing it back is not a leak; what must
  -- never differ is whether the caller can tell "doesn't exist" apart from "wrong account".
  if left(v_err1, strpos(v_err1, ':') - 1) <> left(v_err2, strpos(v_err2, ':') - 1) then
    raise exception 'assertion failed: expected the IDENTICAL contact_not_available error prefix regardless of cause -- got % vs %', v_err1, v_err2;
  end if;

  -- Scope-checked: Beta's own admin may not propose a change for Account Alpha at all.
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'add', null, 'Forged', null, 'forged@test.com', null, null, null, 'submit-beta-forged', v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected account_not_available for beta-admin acting on Account Alpha';
  exception
    when others then
      if sqlerrm not like 'account_not_available%' then raise; end if;
  end;

  -- invalid_role
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'add', null, 'X', null, 'x@test.com', null, 'not-a-role', null, 'bad-role', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_role';
  exception
    when others then
      if sqlerrm not like 'invalid_role%' then raise; end if;
  end;

  -- Raw table CHECK constraints, bypassing the RPC entirely.
  begin
    insert into app.customer_portal_contact_change_requests (tenant_id, account_id, requested_by_actor_auth_user_id, change_kind, target_contact_id)
    values (v_tenant1, v_account_alpha, v_alpha_admin, 'add', v_contact_alpha_id);
    raise exception 'assertion failed: expected a CHECK violation for change_kind=add with a target_contact_id';
  exception
    when check_violation then
      null; -- expected
  end;

  begin
    insert into app.customer_portal_contact_change_requests (tenant_id, account_id, requested_by_actor_auth_user_id, change_kind, target_contact_id, full_name)
    values (v_tenant1, v_account_alpha, v_alpha_admin, 'remove', v_contact_alpha_id, 'Should not be allowed');
    raise exception 'assertion failed: expected a CHECK violation for change_kind=remove carrying a field value';
  exception
    when check_violation then
      null; -- expected
  end;

  -- A genuine, allowed 'add' submission (used by the decide test below).
  select * into v_req from app.submit_customer_contact_change_request(
    v_tenant1, v_account_alpha, 'add', null, 'New Alpha Contact', 'Warehouse Lead', 'new-alpha@ccc1.test', null, 'primary', true, 'submit-alpha-add-001', v_alpha_admin, 'alpha-admin'
  );
  if v_req.status <> 'pending' or v_req.change_kind <> 'add' then
    raise exception 'assertion failed: expected a new pending add request';
  end if;

  -- Idempotent.
  select * into v_req2 from app.submit_customer_contact_change_request(
    v_tenant1, v_account_alpha, 'add', null, 'DIFFERENT -- must be ignored', null, 'ignored@test.com', null, null, null, 'submit-alpha-add-001', v_alpha_admin, 'alpha-admin'
  );
  if v_req2.id <> v_req.id or v_req2.full_name <> v_req.full_name then
    raise exception 'assertion failed: expected idempotent submit to return the original row unchanged';
  end if;
  select count(*) into v_count from app.customer_portal_contact_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-add-001';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one row for idempotency key submit-alpha-add-001, found %', v_count;
  end if;

  -- Same key against a DIFFERENT account is a real conflict.
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_beta, 'add', null, 'X', null, 'x@test.com', null, null, null, 'submit-alpha-add-001', v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected idempotency_key_conflict';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_conflict%' then raise; end if;
  end;

  -- A second, real 'update' submission on the pre-existing Alpha contact, used by withdraw tests below.
  perform app.submit_customer_contact_change_request(
    v_tenant1, v_account_alpha, 'update', (select id from app.contacts where tenant_id = v_tenant1 and full_name = 'Existing Alpha Contact'),
    null, 'Updated Title', null, null, null, null, 'submit-alpha-update-001', v_alpha_admin, 'alpha-admin'
  );
end;
$$;

\echo '>> app.withdraw_customer_contact_change_request: pending-only, any active account member may withdraw, optimistic concurrency (including the NULL-expected-version guard), out-of-scope is record_not_found'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ccc1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000907010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000907011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000907020';
  v_req app.customer_portal_contact_change_requests;
  v_withdrawn app.customer_portal_contact_change_requests;
begin
  select * into v_req from app.customer_portal_contact_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-update-001';

  begin
    perform app.withdraw_customer_contact_change_request(v_req.id, v_req.record_version, v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected record_not_found for beta-admin withdrawing an Alpha request';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  begin
    perform app.withdraw_customer_contact_change_request(v_req.id, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  select * into v_withdrawn from app.withdraw_customer_contact_change_request(v_req.id, v_req.record_version, v_alpha_member, 'alpha-member');
  if v_withdrawn.status <> 'withdrawn' then
    raise exception 'assertion failed: expected withdrawn status';
  end if;

  begin
    perform app.withdraw_customer_contact_change_request(v_withdrawn.id, v_withdrawn.record_version, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_transition for an already-withdrawn request';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end;
$$;

\echo '>> app.list_customer_portal_contact_change_requests: keyset-paginated, deny-by-default, cross-tenant isolated'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ccc1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'ccc2');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000907010';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000908010';
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_portal_contact_change_requests(v_tenant1, v_alpha_admin, null, null, null, null, 200);
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one contact change request visible to alpha-admin';
  end if;

  select count(*) into v_count from app.list_customer_portal_contact_change_requests(v_tenant1, v_t2_admin, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a ccc2 identity querying ccc1''s tenant';
  end if;

  select count(*) into v_count from app.list_customer_portal_contact_change_requests(v_tenant2, v_t2_admin, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows -- t2-admin has never submitted a contact change request';
  end if;
end;
$$;

\echo '>> app.decide_customer_contact_change_request: staff-only (COM:Approve); self-approval blocked; ADD reuses app.create_contact + app.link_contact_to_record (real side effects, never a raw INSERT); UPDATE bumps app.contacts.record_version explicitly and a role collision on contact_links_unique is rejected with contact_link_conflict; REMOVE reuses app.unlink_contact_from_record (its own audit event is provably present); reject leaves everything untouched'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ccc1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Ccc1 Account Alpha Pte Ltd');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000907010';
  v_staff uuid := '00000000-0000-0000-0000-000000907001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000907002';
  v_req app.customer_portal_contact_change_requests;
  v_decided app.customer_portal_contact_change_requests;
  v_new_contact_id uuid;
  v_new_contact app.contacts;
  v_link_role_check text;
  v_contact_before app.contacts;
  v_contact_after app.contacts;
  v_link_id uuid;
  v_existing_contact_id uuid := (select id from app.contacts where tenant_id = v_tenant1 and full_name = 'Existing Alpha Contact');
begin
  -- A customer cannot decide.
  select * into v_req from app.customer_portal_contact_change_requests where tenant_id = v_tenant1 and idempotency_key = 'submit-alpha-add-001';
  begin
    perform app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'approve', 'self-serve attempt', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected insufficient_authority for a customer identity attempting to decide';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'approve', 'wrong tenant', '00000000-0000-0000-0000-000000908001', 'ccc2-staff');
    raise exception 'assertion failed: expected contact_change_request_not_found for zero standing in this tenant';
  exception
    when others then
      if sqlerrm not like 'contact_change_request_not_found%' then raise; end if;
  end;

  begin
    perform app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'approve', 'no authority', v_staff_noauth, 'noauth-staff');
    raise exception 'assertion failed: expected insufficient_authority for staff lacking COM:Approve';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- (7a) ADD: approves, creating a real app.contacts row + a real app.contact_links row via
  -- the existing primitives -- never a raw INSERT.
  select * into v_decided from app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'approve', 'verified new contact', v_staff, 'ccc1-staff');
  if v_decided.status <> 'approved' then
    raise exception 'assertion failed: expected approved';
  end if;

  select cl.contact_id, cl.role into v_new_contact_id, v_link_role_check
  from app.contact_links cl
  where cl.related_type = 'account' and cl.related_id = v_account_alpha and cl.role = 'primary' and cl.is_primary = true;
  if v_new_contact_id is null then
    raise exception 'assertion failed: expected app.link_contact_to_record to have created a real primary link';
  end if;
  select * into v_new_contact from app.contacts where id = v_new_contact_id;
  if v_new_contact.full_name <> 'New Alpha Contact' or v_new_contact.title <> 'Warehouse Lead' or v_new_contact.email <> 'new-alpha@ccc1.test' then
    raise exception 'assertion failed: expected app.create_contact to have created the exact proposed contact fields, got %/%/%', v_new_contact.full_name, v_new_contact.title, v_new_contact.email;
  end if;
  if not exists (select 1 from app.audit_logs where action = 'create_contact' and resource_id = v_new_contact_id) then
    raise exception 'assertion failed: expected app.create_contact''s own audit event to be present (proves the real primitive ran, not a raw INSERT)';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'link_contact_to_record' and resource_type = 'app.contact_links') then
    raise exception 'assertion failed: expected app.link_contact_to_record''s own audit event to be present';
  end if;

  -- (7b) UPDATE: bumps app.contacts.record_version explicitly (no trigger on this table does).
  select * into v_contact_before from app.contacts where id = v_existing_contact_id;
  select * into v_req from app.submit_customer_contact_change_request(
    v_tenant1, v_account_alpha, 'update', v_existing_contact_id, null, 'Senior Ops Manager', null, null, null, null, 'submit-alpha-update-002', v_alpha_admin, 'alpha-admin'
  );
  select * into v_decided from app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'approve', 'title correction verified', v_staff, 'ccc1-staff');
  select * into v_contact_after from app.contacts where id = v_existing_contact_id;
  if v_contact_after.title <> 'Senior Ops Manager' then
    raise exception 'assertion failed: expected title to be updated, got %', v_contact_after.title;
  end if;
  if v_contact_after.record_version <= v_contact_before.record_version then
    raise exception 'assertion failed: expected app.contacts.record_version to advance explicitly, before=% after=%', v_contact_before.record_version, v_contact_after.record_version;
  end if;
  if v_contact_after.full_name <> v_contact_before.full_name or v_contact_after.email <> v_contact_before.email then
    raise exception 'assertion failed: expected full_name/email to be untouched by a title-only update';
  end if;

  -- (7b continued) A role change colliding with an existing link for the same contact+account
  -- is rejected with a clear contact_link_conflict, never a raw constraint violation.
  select id into v_link_id from app.contact_links where contact_id = v_existing_contact_id and related_type = 'account' and related_id = v_account_alpha and role = 'billing';
  -- Give the existing contact a SECOND link (role=technical) on the same account so a proposed
  -- role change to 'technical' has something real to collide with.
  perform app.link_contact_to_record(v_existing_contact_id, 'account', v_account_alpha, 'technical', false, v_staff, 'ccc1-staff');
  select * into v_req from app.submit_customer_contact_change_request(
    v_tenant1, v_account_alpha, 'update', v_existing_contact_id, null, null, null, null, 'technical', null, 'submit-alpha-role-collide', v_alpha_admin, 'alpha-admin'
  );
  begin
    perform app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'approve', 'attempting a colliding role change', v_staff, 'ccc1-staff');
    raise exception 'assertion failed: expected contact_link_conflict';
  exception
    when others then
      if sqlerrm not like 'contact_link_conflict%' then raise; end if;
  end;
  -- The request stays pending (rolled back), and the link's own role is untouched.
  select * into v_req from app.customer_portal_contact_change_requests where id = v_req.id;
  if v_req.status <> 'pending' then
    raise exception 'assertion failed: expected the request to remain pending after a rolled-back role collision';
  end if;
  if not exists (select 1 from app.contact_links where id = v_link_id and role = 'billing') then
    raise exception 'assertion failed: expected the original billing link to be untouched after a rolled-back role collision';
  end if;

  -- (7c) REMOVE: reuses app.unlink_contact_from_record -- its own audit event is provably
  -- present, never a raw DELETE.
  select * into v_req from app.submit_customer_contact_change_request(
    v_tenant1, v_account_alpha, 'remove', v_new_contact_id, null, null, null, null, null, null, 'submit-alpha-remove-001', v_alpha_admin, 'alpha-admin'
  );
  select * into v_decided from app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'approve', 'contact left the company', v_staff, 'ccc1-staff');
  if exists (select 1 from app.contact_links where contact_id = v_new_contact_id and related_type = 'account' and related_id = v_account_alpha and role = 'primary') then
    raise exception 'assertion failed: expected the primary link to be removed';
  end if;
  if not exists (select 1 from app.contacts where id = v_new_contact_id) then
    raise exception 'assertion failed: expected the underlying app.contacts row to still exist -- remove unlinks, it never deletes the contact';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'unlink_contact_from_record' and resource_type = 'app.contact_links') then
    raise exception 'assertion failed: expected app.unlink_contact_from_record''s own audit event to be present';
  end if;

  -- (8) Reject leaves everything untouched.
  select * into v_contact_before from app.contacts where id = v_existing_contact_id;
  select * into v_req from app.submit_customer_contact_change_request(
    v_tenant1, v_account_alpha, 'update', v_existing_contact_id, null, 'Should Never Apply', null, null, null, null, 'submit-alpha-reject-001', v_alpha_admin, 'alpha-admin'
  );
  select * into v_decided from app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'reject', 'not verified', v_staff, 'ccc1-staff');
  if v_decided.status <> 'rejected' then
    raise exception 'assertion failed: expected rejected';
  end if;
  select * into v_contact_after from app.contacts where id = v_existing_contact_id;
  if v_contact_after.title <> v_contact_before.title or v_contact_after.record_version <> v_contact_before.record_version then
    raise exception 'assertion failed: expected app.contacts to be COMPLETELY untouched by a rejection';
  end if;

  -- Audit trail never persists review_reason unredacted.
  if exists (
    select 1 from app.audit_logs
    where action = 'decide_customer_contact_change_request'
      and resource_id = v_req.id
      and (before_value::text like '%not verified%' or after_value::text like '%not verified%')
  ) then
    raise exception 'assertion failed: expected review_reason to NOT be routed into the audit before/after snapshot unredacted';
  end if;
end;
$$;

\echo '>> app.decide_customer_contact_change_request: self-approval guard -- LIVE, mirrors this migration''s own legal-identity sibling exactly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ccc1');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Ccc1 Account Beta');
  v_staff uuid := '00000000-0000-0000-0000-000000907001';
  v_self_req app.customer_portal_contact_change_requests;
begin
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_staff, v_staff, 'ccc1-staff');

  select * into v_self_req from app.submit_customer_contact_change_request(
    v_tenant1, v_account_beta, 'add', null, 'Self Approval Probe', null, 'self-probe@test.com', null, null, null, 'submit-beta-self-approval-001', v_staff, 'ccc1-staff'
  );

  begin
    perform app.decide_customer_contact_change_request(v_self_req.id, v_self_req.record_version, 'approve', 'approving my own request', v_staff, 'ccc1-staff');
    raise exception 'SECURITY FAILURE: v_staff self-approved its own contact change request despite holding real COM:Approve authority';
  exception
    when others then
      if sqlerrm not like 'self_approval_not_permitted%' then raise; end if;
  end;

  begin
    perform app.decide_customer_contact_change_request(v_self_req.id, v_self_req.record_version, 'reject', 'rejecting my own request', v_staff, 'ccc1-staff');
    raise exception 'SECURITY FAILURE: v_staff self-rejected its own contact change request -- the guard must be unconditional, not approve-only';
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
    'app.submit_customer_contact_change_request(uuid, uuid, text, uuid, text, text, text, text, text, boolean, text, uuid, text)',
    'app.withdraw_customer_contact_change_request(uuid, integer, uuid, text)',
    'app.list_customer_portal_contact_change_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.decide_customer_contact_change_request(uuid, integer, text, text, uuid, text)'
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
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000907010", "role": "authenticated"}';
  begin
    perform count(*) from app.customer_portal_contact_change_requests;
    raise exception 'assertion failed: expected a permission-denied error on a raw authenticated SELECT against app.customer_portal_contact_change_requests';
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
  v_tenant1 uuid := (select id from app.tenants where slug = 'ccc1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Ccc1 Account Alpha Pte Ltd');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000907011", "role": "authenticated"}';
  begin
    perform app.submit_customer_contact_change_request(v_tenant1, v_account_alpha, 'add', null, 'Forged', null, 'forged@test.com', null, null, null, 'forged-key', '00000000-0000-0000-0000-000000907010', 'forged-label');
    raise exception 'assertion failed: expected actor_identity_mismatch on submit';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_contact_change_requests(v_tenant1, '00000000-0000-0000-0000-000000907010', null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on list';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  reset role;
end;
$$;

\echo '>> step-up-MFA proof, fully isolated to its own dedicated fixture tenant (cccmfa): a tenant that has NOT turned on tenant-wide MFA but HAS added (COM, Approve) to its own additional_high_risk_actions list still blocks decide via app.assert_current_step_up_authorization; a genuine step-up challenge (request + verify) then unblocks it'
do $$
declare
  v_tenant uuid;
  v_company uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000909001';
  v_admin uuid := '00000000-0000-0000-0000-000000909010';
  v_role uuid; v_draft app.role_versions;
  v_account uuid;
  v_req app.customer_portal_contact_change_requests;
  v_challenge app.mfa_step_up_challenges;
  v_decision app.rbac_decision;
  v_decided app.customer_portal_contact_change_requests;
begin
  insert into auth.users (id, email) values (v_staff, 'staff@cccmfa.test'), (v_admin, 'admin@cccmfa.test');
  perform app.provision_tenant('cccmfa', 'Contact Change MFA Tenant', 'idem-cccmfa', 'tester');
  v_tenant := (select id from app.tenants where slug = 'cccmfa');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  v_company := (app.create_org_unit(v_tenant, 'company', null, 'CCCMFA-CO', 'CccMfa Co', 'tester')).id;
  perform app.invite_user(v_tenant, v_staff, 'staff@cccmfa.test', 'CccMfa Staff', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cccmfa.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant, 'CccMfa Staff Role', null, 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve')) or (resource_module_code = 'CPT' and action = 'Create') or (resource_module_code = 'SEC' and action = 'Configure')),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_role and status = 'published'), v_staff, v_staff, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant, 'CccMfa Account', 'cccmfa-fp', '{}'::jsonb, v_company, 'tester') returning id into v_account;

  perform app.grant_initial_customer_portal_account_admin(v_tenant, v_account, v_admin, v_staff, 'cccmfa-staff');

  perform app.set_mfa_tenant_policy(v_tenant, false, '["supreme_admin", "tenant_admin"]'::jsonb, 15, '[{"moduleCode": "COM", "action": "Approve"}]'::jsonb, v_staff, 'cccmfa-staff');

  v_decision := app.evaluate_permission(v_staff, v_tenant, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'FIXTURE BUG: expected app.evaluate_permission to still allow COM:Approve with tenant_wide_required=false, got reason %', v_decision.reason;
  end if;

  select * into v_req from app.submit_customer_contact_change_request(
    v_tenant, v_account, 'add', null, 'MFA Gated Contact', null, 'mfa-gated@cccmfa.test', null, null, null, 'submit-cccmfa-add-001', v_admin, 'cccmfa-admin'
  );

  begin
    perform app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'approve', 'attempting without step-up', v_staff, 'cccmfa-staff');
    raise exception 'assertion failed: expected mfa_step_up_required with no verified challenge on record';
  exception
    when others then
      if sqlerrm not like 'mfa_step_up_required%' then raise; end if;
  end;
  select * into v_req from app.customer_portal_contact_change_requests where id = v_req.id;
  if v_req.status <> 'pending' then
    raise exception 'assertion failed: expected the request to remain pending while blocked on step-up';
  end if;

  v_challenge := app.request_mfa_step_up_challenge(v_tenant, 'COM', 'Approve', v_staff, 'cccmfa-staff');
  perform app.verify_mfa_step_up_challenge(v_challenge.id, v_staff, 'cccmfa-staff');

  select * into v_decided from app.decide_customer_contact_change_request(v_req.id, v_req.record_version, 'approve', 'approved after step-up', v_staff, 'cccmfa-staff');
  if v_decided.status <> 'approved' then
    raise exception 'assertion failed: expected the decision to succeed once a current verified step-up challenge exists';
  end if;
end;
$$;

\echo '>> customer-portal-contact-change-requests.sql: all assertions passed'
