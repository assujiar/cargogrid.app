-- Real, executable test evidence for CPL-302 (CG-S13-CPL-004, Prompt 302,
-- "Request Quotation") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Structural convention mirrors
-- scripts/db-tests/customer-portal-scope.sql (CPL-300) and scripts/db-tests/
-- customer-portal-dashboard.sql (CPL-301): two-tenant fixture, direct RPC
-- calls as the connecting superuser for parameter-driven assertions, `set
-- local role authenticated` + `set local request.jwt.claims` only where the
-- assertion genuinely needs a real session.
--
-- UUID range 00000000-0000-0000-0000-0000003030xx (tenant cqr1) /
-- ...3040xx (tenant cqr2) -- grep-verified unclaimed before this file was
-- written (right after CPL-301's own ...3010xx/...3020xx range). Tenant
-- slugs cqr1/cqr2.
--
-- Covers, live: (1) create is idempotent on (tenant, idempotency_key) and
-- scope-checked (account_not_available for an unowned/forged account); (2)
-- update is draft-only, any active account member (not only the original
-- requester) may edit, optimistic concurrency; (3) submit requires a
-- mandatory idempotency_key, is idempotent for a genuine retry (SAME key,
-- SAME row), rejects a colliding key against a DIFFERENT row on the same
-- account (idempotency_conflict), and is draft-only; (4) cancel is
-- draft-or-submitted-only, mandatory reason, and correctly refuses a
-- terminal (cancelled/converted) row; (5) get is anti-enumerating --
-- IDENTICAL record_not_found for a genuinely nonexistent id and an
-- out-of-scope id; (6) list is keyset-paginated, deny-by-default, and
-- cross-tenant isolated; (7) the staff-only link RPC (COM:Edit) converts a
-- submitted request, is idempotent for the SAME (request, quotation) pair,
-- rejects a different quotation on an already-converted request
-- (already_converted), rejects a non-submitted request, and rejects a
-- staff actor without COM:Edit; (8) attachments -- app.check_file_action_
-- authority's widening genuinely lets a customer_user actor call app.
-- initiate_file_upload (proven false before this migration would have
-- rejected it), and app.list_customer_quote_request_files returns real
-- metadata to any scoped account member and an empty result for an
-- out-of-scope caller/request; (9) raw-table RLS/grant defense-in-depth;
-- (10) actor-identity session cross-check on a write and a read RPC; (11) a
-- real, live `authenticated`-role positive-path call.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cqr1 (staff: portal/commercial admin with CPT:Create+COM:Create+COM:Edit, and a no-authority staff member; accounts Alpha/Beta; alpha-admin+alpha-member active on Alpha, beta-admin active on Beta, impersonator with zero relationship); a second, otherwise-empty tenant cqr2 (t2-admin on account T2) for cross-tenant isolation; a real opportunity/prospect/quotation chain in cqr1 for the staff link RPC'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000303001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000303002';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000303011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000303020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000303050';
  v_staff2 uuid := '00000000-0000-0000-0000-000000304001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000304010';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@cqr1.test'),
    (v_staff_noauth, 'noauth@cqr1.test'),
    (v_alpha_admin, 'alpha-admin@cqr1.test'),
    (v_alpha_member, 'alpha-member@cqr1.test'),
    (v_beta_admin, 'beta-admin@cqr1.test'),
    (v_impersonator, 'impersonator@cqr1.test'),
    (v_staff2, 'staff@cqr2.test'),
    (v_t2_admin, 't2-admin@cqr2.test');

  perform app.provision_tenant('cqr1', 'Customer Quote Request Tenant One', 'idem-cqr1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cqr1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CQR1-CO', 'Cqr1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CQR1-CO');

  perform app.provision_tenant('cqr2', 'Customer Quote Request Tenant Two', 'idem-cqr2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cqr2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'CQR2-CO', 'Cqr2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@cqr1.test', 'Cqr1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cqr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_staff_noauth, 'noauth@cqr1.test', 'No Authority Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noauth@cqr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@cqr2.test', 'Cqr2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cqr2.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant1, 'Commercial Portal Staff', 'CPT Create + COM Create/Edit', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'CPT' and action = 'Create') or (resource_module_code = 'COM' and action in ('Create', 'Edit'))),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), v_staff, v_staff, 'tester');
  -- Also a tenant_admin principal (PLT-108/PLT-115) -- distinct from the RBAC
  -- role above -- so this same staff identity can draft/publish the
  -- 'quote_request_attachment' document type definition below (app.
  -- create_config_draft's own authority gate, PLT-121, is app.is_support_
  -- grant_authority, never app.evaluate_permission).
  perform app.grant_principal_membership(v_staff, 'tenant_admin', v_tenant1, null, 'tester');

  v_role2 := (app.create_role(v_tenant2, 'Portal Admin', 'CPT Create', 'tester')).id;
  v_draft2 := app.create_role_version(v_role2, 'tester');
  perform app.set_role_version_permissions(v_draft2.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_role2 and status = 'published'), v_staff2, v_staff2, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cqr1 Account Alpha', 'cqr1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cqr1 Account Beta', 'cqr1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cqr2 Account T2', 'cqr2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'cqr1-staff');
  perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, v_alpha_member, 'member', v_alpha_admin, 'alpha-admin');
  perform app.accept_customer_portal_invite((select id from app.customer_portal_account_memberships where account_id = v_account_alpha and auth_user_id = v_alpha_member), 1, v_alpha_member);
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'cqr1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'cqr2-staff');

  -- v_impersonator deliberately holds ZERO customer-portal grant of any kind
  -- (used only as a genuinely different `authenticated` session identity in
  -- the actor-identity cross-check block below).

  -- Minimal real opportunity/prospect chain (no costing/rate/margin needed --
  -- this file never touches app.quotation_lines) so app.create_quotation_
  -- draft has a real opportunity to build from for the staff link RPC.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Cqr1 Quote Customer Ltd', 'Jane Requester', 'jane@cqr1quote.test', '0811', v_staff, v_company1, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cqr1quote.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cqr1quote.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Cqr1 Quote Customer Ltd', 'Cqr1 Quote', '01.111.222.3-000.000',
    jsonb_build_object('line1', 'Jl. Test 1', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Cqr1 Quote Customer Ltd';
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Cqr1 quote request test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'origin', 'Jakarta', 'destination', 'Surabaya'),
    v_staff, v_company1, v_staff, 'tester'
  );
end;
$$;

\echo '>> app.create_customer_quote_request_draft: scope-checked, idempotent, validates location/date shape'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Beta');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000303020';
  v_req app.customer_portal_quote_requests;
  v_req2 app.customer_portal_quote_requests;
  v_count integer;
begin
  select * into v_req from app.create_customer_quote_request_draft(
    v_tenant1, v_account_alpha, 'Palletized general cargo, 2 tons',
    jsonb_build_object('label', 'Jakarta warehouse'), jsonb_build_object('label', 'Surabaya port'),
    'ocean_freight', '2026-09-01'::date, '2026-09-10'::date, 'Handle with care',
    'create-alpha-001', v_alpha_admin, 'alpha-admin'
  );
  if v_req.status <> 'draft' or v_req.account_id <> v_account_alpha then
    raise exception 'assertion failed: expected a new draft request on Account Alpha';
  end if;

  -- Idempotent: same key returns the SAME row, no duplicate.
  select * into v_req2 from app.create_customer_quote_request_draft(
    v_tenant1, v_account_alpha, 'DIFFERENT description -- must be ignored',
    '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-alpha-001', v_alpha_admin, 'alpha-admin'
  );
  if v_req2.id <> v_req.id or v_req2.cargo_description <> v_req.cargo_description then
    raise exception 'assertion failed: expected idempotent create to return the original row unchanged';
  end if;
  select count(*) into v_count from app.customer_portal_quote_requests where tenant_id = v_tenant1 and idempotency_key = 'create-alpha-001';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one row for idempotency key create-alpha-001, found %', v_count;
  end if;

  -- Beta's own admin may not create a request against Alpha's account.
  begin
    perform app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'x', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-beta-forged', v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected account_not_available for beta-admin acting on Account Alpha';
  exception
    when others then
      if sqlerrm not like 'account_not_available%' then raise; end if;
  end;

  begin
    perform app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'x', '"not an object"'::jsonb, '{}'::jsonb, null, null, null, null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_location for a non-object origin';
  exception
    when others then
      if sqlerrm not like 'invalid_location%' then raise; end if;
  end;

  begin
    perform app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'x', '{}'::jsonb, '{}'::jsonb, null, '2026-09-10'::date, '2026-09-01'::date, null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_dates when delivery precedes pickup';
  exception
    when others then
      if sqlerrm not like 'invalid_dates%' then raise; end if;
  end;
end;
$$;

\echo '>> app.update_customer_quote_request_draft: draft-only, any active account member may edit (not only the requester), optimistic concurrency, out-of-scope is record_not_found'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000303011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000303020';
  v_req app.customer_portal_quote_requests;
  v_updated app.customer_portal_quote_requests;
begin
  select * into v_req from app.customer_portal_quote_requests where tenant_id = v_tenant1 and idempotency_key = 'create-alpha-001';

  -- alpha-member (a DIFFERENT identity than the original requester alpha-admin) may edit it.
  select * into v_updated from app.update_customer_quote_request_draft(
    v_req.id, v_req.record_version, 'Updated by a teammate', v_req.origin, v_req.destination,
    'air_freight', v_req.requested_pickup_date, v_req.requested_delivery_date, 'edited', v_alpha_member, 'alpha-member'
  );
  if v_updated.cargo_description <> 'Updated by a teammate' or v_updated.service_type <> 'air_freight' then
    raise exception 'assertion failed: expected the edit to apply';
  end if;
  if v_updated.record_version <> v_req.record_version + 1 then
    raise exception 'assertion failed: expected record_version to advance by exactly 1';
  end if;

  begin
    perform app.update_customer_quote_request_draft(v_req.id, v_req.record_version, 'stale', v_req.origin, v_req.destination, null, null, null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected stale_version on a re-used expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  begin
    perform app.update_customer_quote_request_draft(v_req.id, v_updated.record_version, 'x', '{}'::jsonb, '{}'::jsonb, null, null, null, null, v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected record_not_found for beta-admin editing an Alpha request';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;
end;
$$;

\echo '>> app.submit_customer_quote_request: mandatory idempotency key, idempotent retry, idempotency_conflict against a different row, draft-only'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_req app.customer_portal_quote_requests;
  v_other app.customer_portal_quote_requests;
  v_submitted app.customer_portal_quote_requests;
  v_retry app.customer_portal_quote_requests;
begin
  select * into v_req from app.customer_portal_quote_requests where tenant_id = v_tenant1 and idempotency_key = 'create-alpha-001';

  begin
    perform app.submit_customer_quote_request(v_req.id, v_req.record_version, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected idempotency_key_required for a null submit key';
  exception
    when others then
      if sqlerrm not like 'idempotency_key_required%' then raise; end if;
  end;

  select * into v_submitted from app.submit_customer_quote_request(v_req.id, v_req.record_version, 'submit-alpha-001', v_alpha_admin, 'alpha-admin');
  if v_submitted.status <> 'submitted' or v_submitted.submitted_at is null then
    raise exception 'assertion failed: expected draft -> submitted';
  end if;

  -- Idempotent retry: same row, same key, even with a NOW-STALE expected_version.
  select * into v_retry from app.submit_customer_quote_request(v_req.id, v_req.record_version, 'submit-alpha-001', v_alpha_admin, 'alpha-admin');
  if v_retry.id <> v_submitted.id or v_retry.record_version <> v_submitted.record_version then
    raise exception 'assertion failed: expected an idempotent no-op retry to return the unchanged submitted row';
  end if;

  -- A second, DIFFERENT draft using the SAME submit idempotency key on the same account is a real conflict.
  select * into v_other from app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'second', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-alpha-002', v_alpha_admin, 'alpha-admin');
  begin
    perform app.submit_customer_quote_request(v_other.id, v_other.record_version, 'submit-alpha-001', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected idempotency_conflict for a colliding submit key against a different request';
  exception
    when others then
      if sqlerrm not like 'idempotency_conflict%' then raise; end if;
  end;

  -- Now genuinely submitted -- a further submit attempt (fresh key) is invalid_transition.
  begin
    perform app.submit_customer_quote_request(v_submitted.id, v_submitted.record_version, 'submit-alpha-001-again', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_transition for re-submitting an already-submitted request with a fresh key';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end;
$$;

\echo '>> app.cancel_customer_quote_request: mandatory reason, draft or submitted only, terminal states refuse'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_draft_req app.customer_portal_quote_requests;
  v_cancelled app.customer_portal_quote_requests;
begin
  select * into v_draft_req from app.customer_portal_quote_requests where tenant_id = v_tenant1 and idempotency_key = 'create-alpha-002';

  begin
    perform app.cancel_customer_quote_request(v_draft_req.id, v_draft_req.record_version, '', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  select * into v_cancelled from app.cancel_customer_quote_request(v_draft_req.id, v_draft_req.record_version, 'no longer needed', v_alpha_admin, 'alpha-admin');
  if v_cancelled.status <> 'cancelled' or v_cancelled.cancelled_reason <> 'no longer needed' then
    raise exception 'assertion failed: expected draft -> cancelled with the reason recorded';
  end if;

  begin
    perform app.cancel_customer_quote_request(v_cancelled.id, v_cancelled.record_version, 'again', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_transition -- cancelled is terminal';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end;
$$;

\echo '>> app.get_customer_quote_request: anti-enumeration -- IDENTICAL record_not_found for a nonexistent id and an out-of-scope id; success for a scoped row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000303020';
  v_req app.customer_portal_quote_requests;
  v_got app.customer_portal_quote_requests;
  v_msg_nonexistent text;
  v_msg_forbidden text;
begin
  select * into v_req from app.customer_portal_quote_requests where tenant_id = v_tenant1 and idempotency_key = 'create-alpha-001';

  select * into v_got from app.get_customer_quote_request(v_tenant1, v_req.id, v_alpha_admin);
  if v_got.id <> v_req.id then
    raise exception 'assertion failed: expected the scoped owner to successfully get their own request';
  end if;

  begin
    perform app.get_customer_quote_request(v_tenant1, gen_random_uuid(), v_alpha_admin);
    raise exception 'assertion failed: expected record_not_found for a genuinely nonexistent id';
  exception
    when others then
      v_msg_nonexistent := sqlerrm;
  end;

  begin
    perform app.get_customer_quote_request(v_tenant1, v_req.id, v_beta_admin);
    raise exception 'assertion failed: expected record_not_found for beta-admin reading an Alpha request';
  exception
    when others then
      v_msg_forbidden := sqlerrm;
  end;

  -- Anti-enumeration is a shared MESSAGE-PREFIX/errcode shape, not literal
  -- string identity (each message still embeds the differing id) -- mirrors
  -- scripts/db-tests/advanced-tms-customer-inventory-access.sql's own
  -- identical assertion technique exactly.
  if v_msg_nonexistent not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found for a nonexistent id, got %', v_msg_nonexistent;
  end if;
  if v_msg_forbidden not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found for an out-of-scope id, got %', v_msg_forbidden;
  end if;
end;
$$;

\echo '>> app.list_customer_quote_requests: keyset pagination visits every row exactly once, account/status filters, deny-by-default, cross-tenant isolation, invalid_cursor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cqr2');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000304010';
  v_impersonator uuid := '00000000-0000-0000-0000-000000303050';
  v_total integer;
  v_visited integer := 0;
  v_row app.customer_portal_quote_requests;
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_batch_count integer;
begin
  select count(*) into v_total from app.customer_portal_quote_requests where tenant_id = v_tenant1;
  if v_total < 2 then
    raise exception 'assertion failed: expected at least 2 fixture rows in cqr1 by this point, found %', v_total;
  end if;

  loop
    v_batch_count := 0;
    for v_row in select * from app.list_customer_quote_requests(v_tenant1, v_alpha_admin, null, null, v_cursor_updated_at, v_cursor_id, 1) loop
      v_visited := v_visited + 1;
      v_batch_count := v_batch_count + 1;
      v_cursor_updated_at := v_row.updated_at;
      v_cursor_id := v_row.id;
    end loop;
    exit when v_batch_count = 0;
  end loop;
  if v_visited <> v_total then
    raise exception 'assertion failed: keyset pagination at limit=1 visited % rows, expected %', v_visited, v_total;
  end if;

  -- Cross-tenant isolation: t2-admin (real customer_user in cqr2) sees nothing from cqr1.
  if exists (select 1 from app.list_customer_quote_requests(v_tenant1, v_t2_admin, null, null, null, null, 200)) then
    raise exception 'assertion failed: expected zero cqr1 rows for a cqr2 identity';
  end if;

  -- Deny-by-default: an identity with zero customer-portal scope of any kind gets an empty result, never an error.
  if exists (select 1 from app.list_customer_quote_requests(v_tenant1, v_impersonator, null, null, null, null, 200)) then
    raise exception 'assertion failed: expected zero rows for an identity with no customer-portal scope';
  end if;

  begin
    perform app.list_customer_quote_requests(v_tenant1, v_alpha_admin, null, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor for p_cursor_id supplied without p_cursor_updated_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end;
$$;

\echo '>> app.link_customer_quote_request_to_quotation: staff-only (COM:Edit), idempotent for the SAME pair, already_converted for a different quotation, invalid_transition for a non-submitted request, insufficient_authority without COM:Edit'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_staff uuid := '00000000-0000-0000-0000-000000303001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000303002';
  v_opportunity_id uuid := (select id from app.opportunities where name = 'Cqr1 quote request test lane');
  v_quotation app.quotations;
  v_quotation2 app.quotations;
  v_draft_req app.customer_portal_quote_requests;
  v_submitted app.customer_portal_quote_requests;
  v_linked app.customer_portal_quote_requests;
  v_retry app.customer_portal_quote_requests;
begin
  select * into v_quotation from app.create_quotation_draft(v_tenant1, v_opportunity_id, 'IDR', now() + interval '14 days', null, v_staff, null, v_staff, 'tester');
  select * into v_quotation2 from app.create_quotation_draft(v_tenant1, v_opportunity_id, 'IDR', now() + interval '14 days', null, v_staff, null, v_staff, 'tester');

  select * into v_draft_req from app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'to convert', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-alpha-convert', v_alpha_admin, 'alpha-admin');

  -- Not yet submitted -- may not be converted.
  begin
    perform app.link_customer_quote_request_to_quotation(v_draft_req.id, v_quotation.id, v_staff, 'cqr1-staff');
    raise exception 'assertion failed: expected invalid_transition for converting a still-draft request';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  select * into v_submitted from app.submit_customer_quote_request(v_draft_req.id, v_draft_req.record_version, 'submit-alpha-convert', v_alpha_admin, 'alpha-admin');

  -- A staff member without COM:Edit is rejected.
  begin
    perform app.link_customer_quote_request_to_quotation(v_submitted.id, v_quotation.id, v_staff_noauth, 'no-authority-staff');
    raise exception 'assertion failed: expected insufficient_authority for a staff actor lacking COM:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select * into v_linked from app.link_customer_quote_request_to_quotation(v_submitted.id, v_quotation.id, v_staff, 'cqr1-staff');
  if v_linked.status <> 'converted' or v_linked.linked_quotation_id <> v_quotation.id then
    raise exception 'assertion failed: expected submitted -> converted with linked_quotation_id set';
  end if;

  -- Idempotent for the SAME pair.
  select * into v_retry from app.link_customer_quote_request_to_quotation(v_submitted.id, v_quotation.id, v_staff, 'cqr1-staff');
  if v_retry.id <> v_linked.id or v_retry.linked_quotation_id <> v_quotation.id then
    raise exception 'assertion failed: expected an idempotent re-link to return the unchanged row';
  end if;

  -- A DIFFERENT quotation on an already-converted request is a real conflict, never a silent overwrite.
  begin
    perform app.link_customer_quote_request_to_quotation(v_submitted.id, v_quotation2.id, v_staff, 'cqr1-staff');
    raise exception 'assertion failed: expected already_converted for re-linking to a different quotation';
  exception
    when others then
      if sqlerrm not like 'already_converted%' then raise; end if;
  end;

  -- Terminal: a converted request may no longer be cancelled.
  begin
    perform app.cancel_customer_quote_request(v_linked.id, v_linked.record_version, 'too late', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_transition -- converted is terminal';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Unknown request/quotation ids raise their own distinct not-found errors (staff-facing, not a customer anti-enumeration boundary).
  begin
    perform app.link_customer_quote_request_to_quotation(gen_random_uuid(), v_quotation.id, v_staff, 'cqr1-staff');
    raise exception 'assertion failed: expected quote_request_not_found';
  exception
    when others then
      if sqlerrm not like 'quote_request_not_found%' then raise; end if;
  end;
  begin
    perform app.link_customer_quote_request_to_quotation(v_draft_req.id, gen_random_uuid(), v_staff, 'cqr1-staff');
    raise exception 'assertion failed: expected quotation_not_found';
  exception
    when others then
      if sqlerrm not like 'quotation_not_found%' then raise; end if;
  end;
end;
$$;

\echo '>> attachments: app.check_file_action_authority widening genuinely enables a customer_user actor; app.list_customer_quote_request_files is the sanctioned read path, scoped correctly, empty for an out-of-scope caller/request'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000303011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000303020';
  v_staff uuid := '00000000-0000-0000-0000-000000303001';
  v_req app.customer_portal_quote_requests;
  v_draft app.config_versions;
  v_file app.files;
  v_listed record;
  v_count integer;
begin
  select * into v_req from app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'with attachment', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-alpha-attach', v_alpha_admin, 'alpha-admin');

  -- Before this migration's own widening, this predicate was unconditionally
  -- false for every customer_user identity (design decision 4(b)) -- assert
  -- it is genuinely true now, not merely assumed.
  if not app.check_file_action_authority(v_tenant1, v_alpha_admin) then
    raise exception 'assertion failed: expected app.check_file_action_authority to recognize an active customer_user identity after this migration''s widening';
  end if;
  if app.check_file_action_authority(v_tenant1, '00000000-0000-0000-0000-000000303050') then
    raise exception 'assertion failed: expected app.check_file_action_authority to remain false for an identity with no standing in this tenant at all';
  end if;

  -- A tenant must still separately publish a real document type definition
  -- before any upload succeeds -- standing PLT-128 precondition, not unique
  -- to this capability (design decision 4(a)).
  v_draft := app.create_config_draft('document:quote_request_attachment', v_tenant1, 'tenant', null, v_staff, 'cqr1-staff');
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', to_jsonb(10485760)),
    jsonb_build_object('key', 'retention_class', 'value', to_jsonb('operational_contract_plus_90d'::text)),
    jsonb_build_object('key', 'default_classification', 'value', to_jsonb('internal'::text)),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', to_jsonb(false))
  ), v_staff, 'cqr1-staff');
  perform app.publish_document_type_definition(v_draft.id, v_staff, now(), 'cqr1-staff');

  -- A genuine, customer-attributed upload against this capability's own record_type/record_id.
  select * into v_file from app.initiate_file_upload(
    v_tenant1, 'quote_request_attachment', 'customer_portal_quote_request', v_req.id,
    'cargo-photo.jpg', 'image/jpeg', 204800, null, false, null, '{}', null, 'upload-alpha-attach-1', v_alpha_admin, 'alpha-admin'
  );
  if v_file.record_id <> v_req.id or v_file.uploaded_by_auth_user_id <> v_alpha_admin then
    raise exception 'assertion failed: expected a real file row attributed to the customer actor';
  end if;

  select count(*) into v_count from app.list_customer_quote_request_files(v_tenant1, v_req.id, v_alpha_admin);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 attachment visible to alpha-admin, found %', v_count;
  end if;

  -- A DIFFERENT member of the SAME account also sees it (account-level scope, design decision 9) --
  -- the exact case app.authorize_file_access's own can_access_record composition cannot correctly serve today (design decision 4(b)).
  select count(*) into v_count from app.list_customer_quote_request_files(v_tenant1, v_req.id, v_alpha_member);
  if v_count <> 1 then
    raise exception 'assertion failed: expected a co-worker on the same account to also see the attachment, found %', v_count;
  end if;

  -- A different account's admin sees nothing for this request.
  select count(*) into v_count from app.list_customer_quote_request_files(v_tenant1, v_req.id, v_beta_admin);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero attachments visible to beta-admin on an Alpha request, found %', v_count;
  end if;

  -- A nonexistent request id returns an empty result, never an error (list convention).
  select count(*) into v_count from app.list_customer_quote_request_files(v_tenant1, gen_random_uuid(), v_alpha_admin);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a nonexistent request id';
  end if;
end;
$$;

\echo '>> raw-table RLS/grant defense-in-depth: authenticated holds NO direct table privilege (service_role only); anon holds no EXECUTE on any of the 8 new functions; authenticated/service_role hold EXECUTE'
do $$
declare
  v_fn text;
  v_has_priv boolean;
  v_functions text[] := array[
    'app.create_customer_quote_request_draft(uuid, uuid, text, jsonb, jsonb, text, date, date, text, text, uuid, text)',
    'app.update_customer_quote_request_draft(uuid, integer, text, jsonb, jsonb, text, date, date, text, uuid, text)',
    'app.submit_customer_quote_request(uuid, integer, text, uuid, text)',
    'app.cancel_customer_quote_request(uuid, integer, text, uuid, text)',
    'app.get_customer_quote_request(uuid, uuid, uuid)',
    'app.list_customer_quote_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.link_customer_quote_request_to_quotation(uuid, uuid, uuid, text)',
    'app.list_customer_quote_request_files(uuid, uuid, uuid)'
  ];
begin
  if has_table_privilege('authenticated', 'app.customer_portal_quote_requests', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT hold SELECT on app.customer_portal_quote_requests directly -- the RPC layer is the only sanctioned access path';
  end if;
  if has_table_privilege('authenticated', 'app.customer_portal_quote_requests', 'INSERT') then
    raise exception 'assertion failed: authenticated must NOT hold INSERT on app.customer_portal_quote_requests directly';
  end if;
  if not has_table_privilege('service_role', 'app.customer_portal_quote_requests', 'SELECT') then
    raise exception 'assertion failed: service_role SHOULD hold SELECT on app.customer_portal_quote_requests';
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
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000303010", "role": "authenticated"}';
  begin
    perform count(*) from app.customer_portal_quote_requests;
    raise exception 'assertion failed: expected a permission-denied error on a raw authenticated SELECT against app.customer_portal_quote_requests';
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
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Alpha');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000303050", "role": "authenticated"}';
  begin
    -- Real session is impersonator (303050); this call claims to act as alpha-admin (303010).
    perform app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'forged', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'forged-key', '00000000-0000-0000-0000-000000303010', 'forged-label');
    raise exception 'assertion failed: expected actor_identity_mismatch on create';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_quote_requests(v_tenant1, '00000000-0000-0000-0000-000000303010', null, null, null, null, 50);
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
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_direct_count integer;
  v_session_count integer;
begin
  select count(*) into v_direct_count from app.list_customer_quote_requests(v_tenant1, '00000000-0000-0000-0000-000000303010', null, null, null, null, 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000303010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_quote_requests(v_tenant1, '00000000-0000-0000-0000-000000303010', null, null, null, null, 200);
  reset role;

  if v_session_count <> v_direct_count or v_session_count = 0 then
    raise exception 'assertion failed: expected the real authenticated session to see the SAME nonzero row count (%) as the direct superuser call (%)', v_session_count, v_direct_count;
  end if;
end;
$$;

\echo '>> CPL-324 Tier C fix regression: optimistic-concurrency NULL-bypass on app.update_customer_quote_request_draft/app.submit_customer_quote_request/app.cancel_customer_quote_request -- a NULL p_expected_version is rejected with stale_version, the row proven byte-for-byte unchanged, then the real version succeeds (20260801260000)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cqr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cqr1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000303010';
  v_draft app.customer_portal_quote_requests;
  v_after app.customer_portal_quote_requests;
begin
  -- update_customer_quote_request_draft
  v_draft := app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'null-bypass probe', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'null-bypass-cqr-update', v_alpha_admin, 'alpha-admin');

  begin
    perform app.update_customer_quote_request_draft(v_draft.id, null, 'forged-update', '{}'::jsonb, '{}'::jsonb, null, null, null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on update_customer_quote_request_draft';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  select * into v_after from app.customer_portal_quote_requests where id = v_draft.id;
  if v_after.cargo_description <> v_draft.cargo_description or v_after.record_version <> v_draft.record_version then
    raise exception 'assertion failed: expected the quote request to be byte-for-byte unchanged after a rejected NULL-bypass update attempt, got %', v_after;
  end if;

  v_after := app.update_customer_quote_request_draft(v_draft.id, v_draft.record_version, 'real-version update', '{}'::jsonb, '{}'::jsonb, null, null, null, null, v_alpha_admin, 'alpha-admin');
  if v_after.cargo_description <> 'real-version update' then
    raise exception 'assertion failed: expected the real-version update call to succeed, got %', v_after;
  end if;

  -- submit_customer_quote_request
  begin
    perform app.submit_customer_quote_request(v_after.id, null, 'null-bypass-cqr-submit', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on submit_customer_quote_request';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  if not exists (select 1 from app.customer_portal_quote_requests where id = v_after.id and status = 'draft' and record_version = v_after.record_version) then
    raise exception 'assertion failed: expected the quote request to be byte-for-byte unchanged after a rejected NULL-bypass submit attempt';
  end if;

  v_after := app.submit_customer_quote_request(v_after.id, v_after.record_version, 'real-version-cqr-submit', v_alpha_admin, 'alpha-admin');
  if v_after.status <> 'submitted' then
    raise exception 'assertion failed: expected the real-version submit call to succeed, got %', v_after;
  end if;

  -- cancel_customer_quote_request
  begin
    perform app.cancel_customer_quote_request(v_after.id, null, 'null-bypass probe', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected stale_version for a NULL p_expected_version on cancel_customer_quote_request';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  if not exists (select 1 from app.customer_portal_quote_requests where id = v_after.id and status = 'submitted' and record_version = v_after.record_version) then
    raise exception 'assertion failed: expected the quote request to be byte-for-byte unchanged after a rejected NULL-bypass cancel attempt';
  end if;

  v_after := app.cancel_customer_quote_request(v_after.id, v_after.record_version, 'real-version cancel', v_alpha_admin, 'alpha-admin');
  if v_after.status <> 'cancelled' then
    raise exception 'assertion failed: expected the real-version cancel call to succeed, got %', v_after;
  end if;
end $$;
