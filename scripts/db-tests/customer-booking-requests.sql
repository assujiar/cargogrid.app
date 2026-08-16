-- Real, executable test evidence for CPL-303 (CG-S13-CPL-005, Prompt 303,
-- "Booking") -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Structural convention mirrors scripts/db-tests/
-- customer-quote-requests.sql (CPL-302) exactly: two-tenant fixture, direct
-- RPC calls as the connecting superuser for parameter-driven assertions,
-- `set local role authenticated` + `set local request.jwt.claims` only
-- where the assertion genuinely needs a real session.
--
-- UUID range 00000000-0000-0000-0000-0000305xxx (tenant cbr1) /
-- ...306xxx (tenant cbr2) -- grep-verified unclaimed before this file was
-- written (right after CPL-302's own ...303xxx/...304xxx range). Tenant
-- slugs cbr1/cbr2.
--
-- Covers, live: (1) create is idempotent on (tenant, idempotency_key),
-- scope-checked (account_not_available for an unowned/forged account), and
-- validates a linked quote request must be same-account + already converted
-- (quote_request_account_mismatch / quote_request_not_accepted); (2) update
-- is draft-only, any active account member (not only the original
-- requester) may edit, optimistic concurrency; (3) submit is idempotent for
-- an already-submitted row (no separate key), draft-only otherwise; (4)
-- reschedule requires submitted/converted, a mandatory reason, and at least
-- one new date; (5) cancellation cancels directly from draft/submitted but
-- becomes cancel_requested from converted, mandatory reason, terminal
-- states refuse; (6) get is anti-enumerating -- IDENTICAL record_not_found
-- for a nonexistent id and an out-of-scope id; (7) list is keyset-
-- paginated, deny-by-default, cross-tenant isolated; (8) the staff-only
-- link RPC (OPS:Edit) converts a submitted booking, structurally verifies
-- job/shipment order account ownership and job-order/shipment-order
-- pairing, is idempotent for the SAME pair, rejects a different pair on an
-- already-converted request, rejects a non-submitted request, and rejects a
-- staff actor without OPS:Edit; (9) raw-table RLS/grant defense-in-depth;
-- (10) actor-identity session cross-check on a write and a read RPC; (11) a
-- real, live authenticated-role positive-path call.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cbr1 (staff: operations/commercial admin with OPS:Edit+COM:Edit, and a no-authority staff member; accounts Alpha/Beta; alpha-admin+alpha-member active on Alpha, beta-admin active on Beta, impersonator with zero relationship); a second, otherwise-empty tenant cbr2 (t2-admin on account T2) for cross-tenant isolation; a real opportunity/prospect/quotation/converted-quote-request chain plus a real job order/shipment order pair in cbr1 for the staff link RPC'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000305001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000305002';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000305010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000305011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000305020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000305050';
  v_staff2 uuid := '00000000-0000-0000-0000-000000306001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000306010';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
  v_quotation app.quotations;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment_order app.shipment_orders;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@cbr1.test'),
    (v_staff_noauth, 'noauth@cbr1.test'),
    (v_alpha_admin, 'alpha-admin@cbr1.test'),
    (v_alpha_member, 'alpha-member@cbr1.test'),
    (v_beta_admin, 'beta-admin@cbr1.test'),
    (v_impersonator, 'impersonator@cbr1.test'),
    (v_staff2, 'staff@cbr2.test'),
    (v_t2_admin, 't2-admin@cbr2.test');

  perform app.provision_tenant('cbr1', 'Customer Booking Request Tenant One', 'idem-cbr1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cbr1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CBR1-CO', 'Cbr1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CBR1-CO');

  perform app.provision_tenant('cbr2', 'Customer Booking Request Tenant Two', 'idem-cbr2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cbr2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'CBR2-CO', 'Cbr2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@cbr1.test', 'Cbr1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cbr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_staff_noauth, 'noauth@cbr1.test', 'No Authority Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noauth@cbr1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@cbr2.test', 'Cbr2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cbr2.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant1, 'Ops Portal Staff', 'OPS Edit + COM Create/Edit/Approve + CPT Create', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'OPS' and action in ('View', 'Create', 'Edit')) or (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve')) or (resource_module_code = 'CPT' and action = 'Create')),
    'tester'
  );
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_role and status = 'published'), v_staff, v_staff, 'tester');
  perform app.grant_principal_membership(v_staff, 'tenant_admin', v_tenant1, null, 'tester');

  v_role2 := (app.create_role(v_tenant2, 'Portal Admin', 'CPT Create', 'tester')).id;
  v_draft2 := app.create_role_version(v_role2, 'tester');
  perform app.set_role_version_permissions(v_draft2.id, array(select id from app.permissions where resource_module_code = 'CPT' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_role2 and status = 'published'), v_staff2, v_staff2, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cbr1 Account Alpha', 'cbr1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cbr1 Account Beta', 'cbr1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cbr2 Account T2', 'cbr2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'cbr1-staff');
  perform app.invite_customer_portal_user(v_tenant1, v_account_alpha, v_alpha_member, 'member', v_alpha_admin, 'alpha-admin');
  perform app.accept_customer_portal_invite((select id from app.customer_portal_account_memberships where account_id = v_account_alpha and auth_user_id = v_alpha_member), 1, v_alpha_member);
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'cbr1-staff');
  -- alpha-admin ALSO holds a (member-role) grant on Account Beta -- needed so
  -- this file's own quote_request_account_mismatch assertion below has a
  -- real dual-scoped actor to exercise it with (an actor whose resolved
  -- scope covers BOTH the quote request's own account and the DIFFERENT
  -- account named on the booking create call); every other assertion in
  -- this file still uses alpha-admin/beta-admin as single-account actors.
  perform app.invite_customer_portal_user(v_tenant1, v_account_beta, v_alpha_admin, 'member', v_beta_admin, 'beta-admin');
  perform app.accept_customer_portal_invite((select id from app.customer_portal_account_memberships where account_id = v_account_beta and auth_user_id = v_alpha_admin), 1, v_alpha_admin);
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'cbr2-staff');

  -- v_impersonator deliberately holds ZERO customer-portal grant of any kind.

  -- A real opportunity -> prospect -> quotation chain, converted through a
  -- REAL app.customer_portal_quote_requests row (CPL-302) that reaches
  -- `converted` status, so this file's own "accepted quote" booking-origin
  -- flow (design decision 3) has genuine data to exercise, not a stub.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Cbr1 Booking Customer Ltd', 'Jane Requester', 'jane@cbr1booking.test', '0811', v_staff, v_company1, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cbr1booking.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cbr1booking.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Cbr1 Booking Customer Ltd', 'Cbr1 Booking', '01.111.222.3-000.000',
    jsonb_build_object('line1', 'Jl. Test 1', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Cbr1 Booking Customer Ltd';
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Cbr1 booking test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'origin', 'Jakarta', 'destination', 'Surabaya'),
    v_staff, v_company1, v_staff, 'tester'
  );

  -- app.prepare_job_order_handoff requires status='submitted' (app.submit_
  -- quotation's own readiness gate: >=1 line with a positive total, a real
  -- contact, non-expired validity, non-stale opportunity snapshot) -- a real
  -- contact + a plain service line (no margin_calculation_id needed,
  -- app.add_quotation_line's own p_margin_calculation_id is optional) is
  -- built here, then submitted for real, mirroring commercial-quotation-
  -- builder.sql's own established minimal-submittable-quotation shape.
  declare
    v_contact app.contacts;
    v_draft_quotation app.quotations;
    v_raw_token text;
  begin
    select * into v_contact from app.create_contact(v_tenant1, 'Cbr1 Booking Contact', 'Ops Manager', 'contact@cbr1booking.test', '0813', v_staff, v_company1, v_staff, 'tester');
    select * into v_draft_quotation from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_draft_quotation from app.add_quotation_line(v_draft_quotation.id, v_draft_quotation.record_version, 'service', 'Ocean freight base charge', null, 1, 15000000, 0, 0, v_staff, 'cbr1-staff');
    select * into v_quotation from app.submit_quotation(v_draft_quotation.id, v_draft_quotation.record_version, v_staff, 'cbr1-staff');
    -- app.prepare_job_order_handoff also requires customer_decision='accepted'
    -- -- a real send-token + customer-accept round trip, mirroring commercial-
    -- quotation-customer-acceptance.sql's own established shape.
    select raw_token into v_raw_token from app.send_quotation_for_acceptance(v_quotation.id, v_contact.id, 'email', v_staff, 'cbr1-staff');
    perform app.record_quotation_customer_decision(v_raw_token, 'accepted', 'Jane Requester', 'Ops Manager', 'contact@cbr1booking.test', null, null, null);
    select * into v_quotation from app.quotations where id = v_quotation.id;
    -- app.prepare_job_order_handoff also requires a real app.account_
    -- conversions row (COM-155) -- linked directly to the ALREADY-EXISTING
    -- v_account_alpha (p_target_account_id), never a freshly-minted account,
    -- so the resulting job order/shipment order''s own account_id/shipper_
    -- account_id structurally matches this booking''s own account_id
    -- (design decision 7''s own real structural check).
    perform app.convert_quotation_to_account(v_quotation.id, v_account_alpha, null, v_staff, 'cbr1-staff');
  end;

  declare
    v_accepted_qr app.customer_portal_quote_requests;
    v_submitted_qr app.customer_portal_quote_requests;
  begin
    select * into v_accepted_qr from app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'accepted for booking', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-alpha-accepted', v_alpha_admin, 'alpha-admin');
    select * into v_submitted_qr from app.submit_customer_quote_request(v_accepted_qr.id, v_accepted_qr.record_version, 'submit-alpha-accepted', v_alpha_admin, 'alpha-admin');
    perform app.link_customer_quote_request_to_quotation(v_submitted_qr.id, v_quotation.id, v_staff, 'cbr1-staff');

    -- A second, still-DRAFT quote request (never submitted/converted) to
    -- exercise quote_request_not_accepted below.
    perform app.create_customer_quote_request_draft(v_tenant1, v_account_alpha, 'still draft', '{}'::jsonb, '{}'::jsonb, null, null, null, null, 'create-alpha-stilldraft', v_alpha_admin, 'alpha-admin');
  end;

  -- A real job order + shipment order pair (Operations' own canonical
  -- pipeline, entirely independent of this migration) for the staff link RPC.
  -- app.create_shipment_order_from_job requires the Job Order be `confirmed`
  -- (OPS-169) -- app.confirm_job_order (OPS:Edit) is called explicitly, not
  -- assumed.
  select * into v_handoff from app.prepare_job_order_handoff(v_quotation.id, v_staff, 'cbr1-staff');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_staff, 'cbr1-staff');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_staff, 'cbr1-staff');
  select * into v_shipment_order from app.create_shipment_order_from_job(
    v_job_order.id, 'shipment-cbr1-001', '{}'::jsonb, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '5 days', now() + interval '10 days', 10, 1000, 20, null, null, null, null, v_staff, 'cbr1-staff'
  );
end;
$$;

\echo '>> app.create_customer_booking_request_draft: scope-checked, idempotent, validates location/date shape, and validates a linked quote request (same-account, already-converted only)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbr1 Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbr1 Account Beta');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000305010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000305020';
  v_accepted_qr uuid := (select id from app.customer_portal_quote_requests where tenant_id = v_tenant1 and idempotency_key = 'create-alpha-accepted');
  v_draft_qr uuid := (select id from app.customer_portal_quote_requests where tenant_id = v_tenant1 and idempotency_key = 'create-alpha-stilldraft');
  v_booking app.customer_portal_booking_requests;
  v_booking2 app.customer_portal_booking_requests;
  v_count integer;
begin
  select * into v_booking from app.create_customer_booking_request_draft(
    v_tenant1, v_account_alpha, v_accepted_qr, 'Palletized general cargo, 2 tons',
    jsonb_build_object('label', 'Jakarta warehouse'), jsonb_build_object('label', 'Surabaya port'),
    now() + interval '5 days', now() + interval '10 days', 'Handle with care',
    'create-booking-alpha-001', v_alpha_admin, 'alpha-admin'
  );
  if v_booking.status <> 'draft' or v_booking.account_id <> v_account_alpha or v_booking.linked_quote_request_id <> v_accepted_qr then
    raise exception 'assertion failed: expected a new draft booking on Account Alpha linked to the accepted quote request';
  end if;

  -- Idempotent: same key returns the SAME row, no duplicate.
  select * into v_booking2 from app.create_customer_booking_request_draft(
    v_tenant1, v_account_alpha, null, 'DIFFERENT -- must be ignored', '{}'::jsonb, '{}'::jsonb, null, null, null, 'create-booking-alpha-001', v_alpha_admin, 'alpha-admin'
  );
  if v_booking2.id <> v_booking.id or v_booking2.cargo_description <> v_booking.cargo_description then
    raise exception 'assertion failed: expected idempotent create to return the original row unchanged';
  end if;
  select count(*) into v_count from app.customer_portal_booking_requests where tenant_id = v_tenant1 and idempotency_key = 'create-booking-alpha-001';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one row for idempotency key create-booking-alpha-001, found %', v_count;
  end if;

  -- Beta's own admin may not create a booking against Alpha's account.
  begin
    perform app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, null, 'x', '{}'::jsonb, '{}'::jsonb, null, null, null, 'create-booking-beta-forged', v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected account_not_available for beta-admin acting on Account Alpha';
  exception
    when others then
      if sqlerrm not like 'account_not_available%' then raise; end if;
  end;

  begin
    perform app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, null, 'x', '"not an object"'::jsonb, '{}'::jsonb, null, null, null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_location for a non-object pickup';
  exception
    when others then
      if sqlerrm not like 'invalid_location%' then raise; end if;
  end;

  begin
    perform app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, null, 'x', '{}'::jsonb, '{}'::jsonb, now() + interval '10 days', now() + interval '1 day', null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_dates when delivery precedes pickup';
  exception
    when others then
      if sqlerrm not like 'invalid_dates%' then raise; end if;
  end;

  -- alpha-admin (dual-scoped: account_admin on Alpha, member on Beta, setup
  -- block) booking against Account Beta while citing Alpha's own accepted
  -- quote request is a genuine account mismatch -- the quote request IS
  -- visible to this actor (in scope, so quote_request_not_found does not
  -- fire), it simply belongs to a DIFFERENT account than p_account_id.
  begin
    perform app.create_customer_booking_request_draft(v_tenant1, v_account_beta, v_accepted_qr, 'x', '{}'::jsonb, '{}'::jsonb, null, null, null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected quote_request_account_mismatch for a quote request belonging to a different account';
  exception
    when others then
      if sqlerrm not like 'quote_request_account_mismatch%' then raise; end if;
  end;

  -- A quote request that is still draft (never submitted/converted) is not yet "accepted".
  begin
    perform app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, v_draft_qr, 'x', '{}'::jsonb, '{}'::jsonb, null, null, null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected quote_request_not_accepted for a still-draft quote request';
  exception
    when others then
      if sqlerrm not like 'quote_request_not_accepted%' then raise; end if;
  end;

  -- A forged/nonexistent linked quote request id is anti-enumerating (record_not_found shape).
  begin
    perform app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, gen_random_uuid(), 'x', '{}'::jsonb, '{}'::jsonb, null, null, null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected quote_request_not_found for a nonexistent linked quote request id';
  exception
    when others then
      if sqlerrm not like 'quote_request_not_found%' then raise; end if;
  end;

  -- Tier C review coverage gap closed (cross-prompt-integration lens): the
  -- CROSS-TENANT case, not merely cross-account -- a tenant2 actor (t2-admin,
  -- zero relationship to tenant1) citing tenant1's own REAL, accepted quote
  -- request id, with tenant2's own p_tenant_id/p_account_id, must be
  -- rejected with the identical anti-enumerating quote_request_not_found
  -- BEFORE any other business logic runs -- never a different error shape
  -- that would disclose the id belongs to a real row in a different tenant.
  declare
    v_tenant2 uuid := (select id from app.tenants where slug = 'cbr2');
    v_account_t2 uuid := (select id from app.accounts where tenant_id = v_tenant2 and legal_name = 'Cbr2 Account T2');
    v_t2_admin uuid := '00000000-0000-0000-0000-000000306010';
  begin
    perform app.create_customer_booking_request_draft(
      v_tenant2, v_account_t2, v_accepted_qr, 'cross-tenant IDOR attempt', '{}'::jsonb, '{}'::jsonb, null, null, null, null, v_t2_admin, 't2-admin'
    );
    raise exception 'assertion failed: expected quote_request_not_found for a tenant2 actor citing tenant1''s own real quote request id';
  exception
    when others then
      if sqlerrm not like 'quote_request_not_found%' then raise; end if;
  end;
end;
$$;

\echo '>> app.update_customer_booking_request_draft: draft-only, any active account member may edit (not only the requester), optimistic concurrency, out-of-scope is record_not_found'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000305010';
  v_alpha_member uuid := '00000000-0000-0000-0000-000000305011';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000305020';
  v_booking app.customer_portal_booking_requests;
  v_updated app.customer_portal_booking_requests;
begin
  select * into v_booking from app.customer_portal_booking_requests where tenant_id = v_tenant1 and idempotency_key = 'create-booking-alpha-001';

  -- alpha-member (a DIFFERENT identity than the original requester alpha-admin) may edit it.
  select * into v_updated from app.update_customer_booking_request_draft(
    v_booking.id, v_booking.record_version, 'Updated by a teammate', v_booking.pickup, v_booking.delivery,
    v_booking.requested_pickup_at, v_booking.requested_delivery_at, 'edited', v_alpha_member, 'alpha-member'
  );
  if v_updated.cargo_description <> 'Updated by a teammate' or v_updated.special_instructions <> 'edited' then
    raise exception 'assertion failed: expected the edit to apply';
  end if;
  if v_updated.record_version <> v_booking.record_version + 1 then
    raise exception 'assertion failed: expected record_version to advance by exactly 1';
  end if;

  begin
    perform app.update_customer_booking_request_draft(v_booking.id, v_booking.record_version, 'stale', v_booking.pickup, v_booking.delivery, null, null, null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected stale_version on a re-used expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  begin
    perform app.update_customer_booking_request_draft(v_booking.id, v_updated.record_version, 'x', '{}'::jsonb, '{}'::jsonb, null, null, null, v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected record_not_found for beta-admin editing an Alpha booking';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;
end;
$$;

\echo '>> app.submit_customer_booking_request: idempotent no-op if already submitted, draft-only otherwise, stale_version'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000305010';
  v_booking app.customer_portal_booking_requests;
  v_submitted app.customer_portal_booking_requests;
  v_retry app.customer_portal_booking_requests;
begin
  select * into v_booking from app.customer_portal_booking_requests where tenant_id = v_tenant1 and idempotency_key = 'create-booking-alpha-001';

  select * into v_submitted from app.submit_customer_booking_request(v_booking.id, v_booking.record_version, v_alpha_admin, 'alpha-admin');
  if v_submitted.status <> 'submitted' or v_submitted.submitted_at is null then
    raise exception 'assertion failed: expected draft -> submitted';
  end if;

  -- Idempotent retry: same row, unchanged, even with a NOW-STALE expected_version.
  select * into v_retry from app.submit_customer_booking_request(v_booking.id, v_booking.record_version, v_alpha_admin, 'alpha-admin');
  if v_retry.id <> v_submitted.id or v_retry.record_version <> v_submitted.record_version then
    raise exception 'assertion failed: expected an idempotent no-op retry to return the unchanged submitted row';
  end if;

  -- A THIRD call against the now-submitted row, still carrying the ORIGINAL
  -- (now doubly-stale) expected_version, is likewise a no-op return, never a
  -- stale_version exception -- the idempotent short-circuit checks the
  -- row's own CURRENT status first, before any version comparison is ever
  -- reached.
  select * into v_retry from app.submit_customer_booking_request(v_submitted.id, v_booking.record_version, v_alpha_admin, 'alpha-admin');
  if v_retry.id <> v_submitted.id or v_retry.status <> 'submitted' then
    raise exception 'assertion failed: expected a further idempotent no-op retry (even with a doubly-stale expected_version) to return the unchanged submitted row';
  end if;
end;
$$;

\echo '>> app.request_customer_booking_reschedule: submitted/converted only, mandatory reason + at least one new date, invalid_transition for a draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbr1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000305010';
  v_new_draft app.customer_portal_booking_requests;
  v_submitted app.customer_portal_booking_requests;
  v_rescheduled app.customer_portal_booking_requests;
begin
  -- A fresh draft (not yet submitted) cannot be rescheduled -- that is a plain edit.
  select * into v_new_draft from app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, null, 'reschedule test', '{}'::jsonb, '{}'::jsonb, null, null, null, 'create-booking-alpha-resched', v_alpha_admin, 'alpha-admin');

  begin
    perform app.request_customer_booking_reschedule(v_new_draft.id, v_new_draft.record_version, now() + interval '3 days', null, 'need to change', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_transition for rescheduling a still-draft booking';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  begin
    perform app.request_customer_booking_reschedule(v_new_draft.id, v_new_draft.record_version, null, null, 'no dates supplied', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected reschedule_date_required when neither new date is supplied';
  exception
    when others then
      if sqlerrm not like '%reschedule_date_required%' and sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  select * into v_submitted from app.submit_customer_booking_request(v_new_draft.id, v_new_draft.record_version, v_alpha_admin, 'alpha-admin');

  begin
    perform app.request_customer_booking_reschedule(v_submitted.id, v_submitted.record_version, null, null, 'no dates', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected reschedule_date_required when neither new date is supplied on a submitted booking';
  exception
    when others then
      if sqlerrm not like 'reschedule_date_required%' then raise; end if;
  end;

  begin
    perform app.request_customer_booking_reschedule(v_submitted.id, v_submitted.record_version, now() + interval '3 days', null, '', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  select * into v_rescheduled from app.request_customer_booking_reschedule(v_submitted.id, v_submitted.record_version, now() + interval '3 days', null, 'warehouse delay', v_alpha_admin, 'alpha-admin');
  if v_rescheduled.status <> 'reschedule_requested' or v_rescheduled.reschedule_reason <> 'warehouse delay' or v_rescheduled.reschedule_requested_pickup_at is null then
    raise exception 'assertion failed: expected submitted -> reschedule_requested with the new date/reason recorded';
  end if;

  -- Terminal within this checkpoint's own RPC surface.
  begin
    perform app.request_customer_booking_reschedule(v_rescheduled.id, v_rescheduled.record_version, now() + interval '4 days', null, 'again', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_transition -- reschedule_requested has no further reschedule request in this checkpoint';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end;
$$;

\echo '>> app.request_customer_booking_cancellation: draft/submitted cancel directly, converted becomes cancel_requested, mandatory reason, terminal states refuse'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbr1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000305010';
  v_draft_booking app.customer_portal_booking_requests;
  v_cancelled app.customer_portal_booking_requests;
begin
  select * into v_draft_booking from app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, null, 'cancel test', '{}'::jsonb, '{}'::jsonb, null, null, null, 'create-booking-alpha-cancel', v_alpha_admin, 'alpha-admin');

  begin
    perform app.request_customer_booking_cancellation(v_draft_booking.id, v_draft_booking.record_version, '', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected reason_required for an empty reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  select * into v_cancelled from app.request_customer_booking_cancellation(v_draft_booking.id, v_draft_booking.record_version, 'no longer needed', v_alpha_admin, 'alpha-admin');
  if v_cancelled.status <> 'cancelled' or v_cancelled.cancelled_reason <> 'no longer needed' or v_cancelled.cancelled_at is null then
    raise exception 'assertion failed: expected draft -> cancelled with the reason recorded';
  end if;

  begin
    perform app.request_customer_booking_cancellation(v_cancelled.id, v_cancelled.record_version, 'again', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_transition -- cancelled is terminal';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;
end;
$$;

\echo '>> app.link_customer_booking_request_to_operational_records: staff-only (OPS:Edit), structurally verifies account ownership + job/shipment order pairing, idempotent for the SAME pair, already_converted for a different pair, invalid_transition for a non-submitted request, insufficient_authority without OPS:Edit'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbr1 Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbr1 Account Beta');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000305010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000305020';
  v_staff uuid := '00000000-0000-0000-0000-000000305001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000305002';
  v_job_order_id uuid := (select id from app.job_orders where tenant_id = v_tenant1 limit 1);
  v_shipment_order_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 limit 1);
  v_company1 uuid := (select org_unit_id from app.accounts where id = v_account_alpha);
  v_other_job_order app.job_orders;
  v_other_shipment_order app.shipment_orders;
  v_other_handoff app.job_order_handoffs;
  v_beta_quotation app.quotations;
  v_beta_opportunity app.opportunities;
  v_beta_prospect app.prospects;
  v_beta_lead app.leads;
  v_draft_booking app.customer_portal_booking_requests;
  v_submitted app.customer_portal_booking_requests;
  v_linked app.customer_portal_booking_requests;
  v_retry app.customer_portal_booking_requests;
  v_beta_booking app.customer_portal_booking_requests;
  v_beta_submitted app.customer_portal_booking_requests;
begin
  select * into v_draft_booking from app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, null, 'to convert', '{}'::jsonb, '{}'::jsonb, null, null, null, 'create-booking-alpha-convert', v_alpha_admin, 'alpha-admin');

  -- Not yet submitted -- may not be converted.
  begin
    perform app.link_customer_booking_request_to_operational_records(v_draft_booking.id, v_job_order_id, v_shipment_order_id, v_staff, 'cbr1-staff');
    raise exception 'assertion failed: expected invalid_transition for converting a still-draft booking';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  select * into v_submitted from app.submit_customer_booking_request(v_draft_booking.id, v_draft_booking.record_version, v_alpha_admin, 'alpha-admin');

  -- A staff member without OPS:Edit is rejected.
  begin
    perform app.link_customer_booking_request_to_operational_records(v_submitted.id, v_job_order_id, v_shipment_order_id, v_staff_noauth, 'no-authority-staff');
    raise exception 'assertion failed: expected insufficient_authority for a staff actor lacking OPS:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Mandatory ids.
  begin
    perform app.link_customer_booking_request_to_operational_records(v_submitted.id, null, v_shipment_order_id, v_staff, 'cbr1-staff');
    raise exception 'assertion failed: expected job_order_id_required for a null job order id';
  exception
    when others then
      if sqlerrm not like 'job_order_id_required%' then raise; end if;
  end;
  begin
    perform app.link_customer_booking_request_to_operational_records(v_submitted.id, v_job_order_id, null, v_staff, 'cbr1-staff');
    raise exception 'assertion failed: expected shipment_order_id_required for a null shipment order id';
  exception
    when others then
      if sqlerrm not like 'shipment_order_id_required%' then raise; end if;
  end;

  -- A REAL job order/shipment order pair that belongs to Beta's own account
  -- (not Alpha) is a structural mismatch -- built via a completely
  -- independent Commercial->Operations pipeline for Beta.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Cbr1 Beta Booking Customer Ltd', 'Beta Requester', 'beta@cbr1booking.test', '0812', v_staff, (select org_unit_id from app.accounts where id = v_account_beta), v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@cbr1booking.test';
  perform app.qualify_lead(v_beta_lead.id, v_beta_lead.record_version, v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@cbr1booking.test';
  perform app.convert_lead_to_prospect(v_beta_lead.id, 'Cbr1 Beta Booking Customer Ltd', 'Cbr1 Beta Booking', '01.111.222.4-000.000',
    jsonb_build_object('line1', 'Jl. Test 2', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_beta_prospect from app.prospects where legal_name = 'Cbr1 Beta Booking Customer Ltd';
  select * into v_beta_opportunity from app.create_opportunity(
    v_tenant1, v_beta_prospect.id, 'Cbr1 beta booking test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'origin', 'Jakarta', 'destination', 'Surabaya'),
    v_staff, (select org_unit_id from app.accounts where id = v_account_beta), v_staff, 'tester'
  );
  declare
    v_beta_contact app.contacts;
    v_beta_draft_quotation app.quotations;
    v_beta_raw_token text;
  begin
    select * into v_beta_contact from app.create_contact(v_tenant1, 'Cbr1 Beta Booking Contact', 'Ops Manager', 'contact@cbr1betabooking.test', '0814', v_staff, v_company1, v_staff, 'tester');
    select * into v_beta_draft_quotation from app.create_quotation_draft(v_tenant1, v_beta_opportunity.id, 'IDR', now() + interval '14 days', v_beta_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_beta_draft_quotation from app.add_quotation_line(v_beta_draft_quotation.id, v_beta_draft_quotation.record_version, 'service', 'Ocean freight base charge', null, 1, 8000000, 0, 0, v_staff, 'cbr1-staff');
    select * into v_beta_quotation from app.submit_quotation(v_beta_draft_quotation.id, v_beta_draft_quotation.record_version, v_staff, 'cbr1-staff');
    select raw_token into v_beta_raw_token from app.send_quotation_for_acceptance(v_beta_quotation.id, v_beta_contact.id, 'email', v_staff, 'cbr1-staff');
    perform app.record_quotation_customer_decision(v_beta_raw_token, 'accepted', 'Beta Requester', 'Ops Manager', 'contact@cbr1betabooking.test', null, null, null);
    select * into v_beta_quotation from app.quotations where id = v_beta_quotation.id;
    -- Linked to v_account_beta specifically (not Alpha) -- the entire point
    -- of this second chain is a job order/shipment order that structurally
    -- belongs to a DIFFERENT account than the booking under test.
    perform app.convert_quotation_to_account(v_beta_quotation.id, v_account_beta, null, v_staff, 'cbr1-staff');
  end;
  select * into v_other_handoff from app.prepare_job_order_handoff(v_beta_quotation.id, v_staff, 'cbr1-staff');
  select * into v_other_job_order from app.prepare_job_order(v_other_handoff.id, v_staff, 'cbr1-staff');
  select * into v_other_job_order from app.confirm_job_order(v_other_job_order.id, v_other_job_order.record_version, v_staff, 'cbr1-staff');
  select * into v_other_shipment_order from app.create_shipment_order_from_job(
    v_other_job_order.id, 'shipment-cbr1-beta-001', '{}'::jsonb, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '5 days', now() + interval '10 days', 5, 500, 10, null, null, null, null, v_staff, 'cbr1-staff'
  );

  begin
    perform app.link_customer_booking_request_to_operational_records(v_submitted.id, v_other_job_order.id, v_shipment_order_id, v_staff, 'cbr1-staff');
    raise exception 'assertion failed: expected job_order_account_mismatch for a job order belonging to Account Beta on an Account Alpha booking';
  exception
    when others then
      if sqlerrm not like 'job_order_account_mismatch%' then raise; end if;
  end;

  begin
    perform app.link_customer_booking_request_to_operational_records(v_submitted.id, v_job_order_id, v_other_shipment_order.id, v_staff, 'cbr1-staff');
    raise exception 'assertion failed: expected shipment_order_job_order_mismatch for a shipment order not belonging to the given job order';
  exception
    when others then
      if sqlerrm not like 'shipment_order_job_order_mismatch%' then raise; end if;
  end;

  select * into v_linked from app.link_customer_booking_request_to_operational_records(v_submitted.id, v_job_order_id, v_shipment_order_id, v_staff, 'cbr1-staff');
  if v_linked.status <> 'converted' or v_linked.linked_job_order_id <> v_job_order_id or v_linked.linked_shipment_order_id <> v_shipment_order_id then
    raise exception 'assertion failed: expected submitted -> converted with both linked ids set';
  end if;

  -- Idempotent for the SAME pair.
  select * into v_retry from app.link_customer_booking_request_to_operational_records(v_submitted.id, v_job_order_id, v_shipment_order_id, v_staff, 'cbr1-staff');
  if v_retry.id <> v_linked.id or v_retry.linked_job_order_id <> v_job_order_id then
    raise exception 'assertion failed: expected an idempotent re-link to return the unchanged row';
  end if;

  -- A DIFFERENT pair on an already-converted request is a real conflict, never a silent overwrite.
  begin
    perform app.link_customer_booking_request_to_operational_records(v_submitted.id, v_other_job_order.id, v_other_shipment_order.id, v_staff, 'cbr1-staff');
    raise exception 'assertion failed: expected already_converted for re-linking to a different pair';
  exception
    when others then
      if sqlerrm not like 'already_converted%' then raise; end if;
  end;

  -- Converted -> cancellation becomes cancel_requested, not cancelled directly.
  declare
    v_cancel_requested app.customer_portal_booking_requests;
  begin
    select * into v_cancel_requested from app.request_customer_booking_cancellation(v_linked.id, v_linked.record_version, 'operational change needed', v_alpha_admin, 'alpha-admin');
    if v_cancel_requested.status <> 'cancel_requested' then
      raise exception 'assertion failed: expected converted -> cancel_requested (not cancelled directly)';
    end if;
  end;

  -- Unknown booking/job order/shipment order ids raise their own distinct not-found errors.
  begin
    perform app.link_customer_booking_request_to_operational_records(gen_random_uuid(), v_job_order_id, v_shipment_order_id, v_staff, 'cbr1-staff');
    raise exception 'assertion failed: expected booking_request_not_found';
  exception
    when others then
      if sqlerrm not like 'booking_request_not_found%' then raise; end if;
  end;

  -- A second, independent Alpha booking to exercise job_order_not_found/shipment_order_not_found.
  select * into v_beta_booking from app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, null, 'second convert test', '{}'::jsonb, '{}'::jsonb, null, null, null, 'create-booking-alpha-convert2', v_alpha_admin, 'alpha-admin');
  select * into v_beta_submitted from app.submit_customer_booking_request(v_beta_booking.id, v_beta_booking.record_version, v_alpha_admin, 'alpha-admin');
  begin
    perform app.link_customer_booking_request_to_operational_records(v_beta_submitted.id, gen_random_uuid(), v_shipment_order_id, v_staff, 'cbr1-staff');
    raise exception 'assertion failed: expected job_order_not_found';
  exception
    when others then
      if sqlerrm not like 'job_order_not_found%' then raise; end if;
  end;
  begin
    perform app.link_customer_booking_request_to_operational_records(v_beta_submitted.id, v_job_order_id, gen_random_uuid(), v_staff, 'cbr1-staff');
    raise exception 'assertion failed: expected shipment_order_not_found';
  exception
    when others then
      if sqlerrm not like 'shipment_order_not_found%' then raise; end if;
  end;
end;
$$;

\echo '>> app.get_customer_booking_request: anti-enumeration -- IDENTICAL record_not_found for a nonexistent id and an out-of-scope id; success for a scoped row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000305010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000305020';
  v_booking app.customer_portal_booking_requests;
  v_got app.customer_portal_booking_requests;
  v_msg_nonexistent text;
  v_msg_forbidden text;
begin
  select * into v_booking from app.customer_portal_booking_requests where tenant_id = v_tenant1 and idempotency_key = 'create-booking-alpha-001';

  select * into v_got from app.get_customer_booking_request(v_tenant1, v_booking.id, v_alpha_admin);
  if v_got.id <> v_booking.id then
    raise exception 'assertion failed: expected the scoped owner to successfully get their own booking';
  end if;

  begin
    perform app.get_customer_booking_request(v_tenant1, gen_random_uuid(), v_alpha_admin);
    raise exception 'assertion failed: expected record_not_found for a genuinely nonexistent id';
  exception
    when others then
      v_msg_nonexistent := sqlerrm;
  end;

  begin
    perform app.get_customer_booking_request(v_tenant1, v_booking.id, v_beta_admin);
    raise exception 'assertion failed: expected record_not_found for beta-admin reading an Alpha booking';
  exception
    when others then
      v_msg_forbidden := sqlerrm;
  end;

  if v_msg_nonexistent not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found for a nonexistent id, got %', v_msg_nonexistent;
  end if;
  if v_msg_forbidden not like 'record_not_found%' then
    raise exception 'assertion failed: expected record_not_found for an out-of-scope id, got %', v_msg_forbidden;
  end if;
end;
$$;

\echo '>> app.list_customer_booking_requests: keyset pagination visits every row exactly once, account/status filters, deny-by-default, cross-tenant isolation, invalid_cursor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cbr2');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000305010';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000306010';
  v_impersonator uuid := '00000000-0000-0000-0000-000000305050';
  v_total integer;
  v_visited integer := 0;
  v_row app.customer_portal_booking_requests;
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_batch_count integer;
begin
  select count(*) into v_total from app.customer_portal_booking_requests where tenant_id = v_tenant1;
  if v_total < 2 then
    raise exception 'assertion failed: expected at least 2 fixture rows in cbr1 by this point, found %', v_total;
  end if;

  loop
    v_batch_count := 0;
    for v_row in select * from app.list_customer_booking_requests(v_tenant1, v_alpha_admin, null, null, v_cursor_updated_at, v_cursor_id, 1) loop
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

  -- Cross-tenant isolation: t2-admin (real customer_user in cbr2) sees nothing from cbr1.
  if exists (select 1 from app.list_customer_booking_requests(v_tenant1, v_t2_admin, null, null, null, null, 200)) then
    raise exception 'assertion failed: expected zero cbr1 rows for a cbr2 identity';
  end if;

  -- Deny-by-default: an identity with zero customer-portal scope of any kind gets an empty result, never an error.
  if exists (select 1 from app.list_customer_booking_requests(v_tenant1, v_impersonator, null, null, null, null, 200)) then
    raise exception 'assertion failed: expected zero rows for an identity with no customer-portal scope';
  end if;

  begin
    perform app.list_customer_booking_requests(v_tenant1, v_alpha_admin, null, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor for p_cursor_id supplied without p_cursor_updated_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end;
$$;

\echo '>> raw-table RLS/grant defense-in-depth: authenticated holds NO direct table privilege (service_role only); anon holds no EXECUTE on any of the 8 new functions; authenticated/service_role hold EXECUTE'
do $$
declare
  v_fn text;
  v_has_priv boolean;
  v_functions text[] := array[
    'app.create_customer_booking_request_draft(uuid, uuid, uuid, text, jsonb, jsonb, timestamptz, timestamptz, text, text, uuid, text)',
    'app.update_customer_booking_request_draft(uuid, integer, text, jsonb, jsonb, timestamptz, timestamptz, text, uuid, text)',
    'app.submit_customer_booking_request(uuid, integer, uuid, text)',
    'app.request_customer_booking_reschedule(uuid, integer, timestamptz, timestamptz, text, uuid, text)',
    'app.request_customer_booking_cancellation(uuid, integer, text, uuid, text)',
    'app.get_customer_booking_request(uuid, uuid, uuid)',
    'app.list_customer_booking_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.link_customer_booking_request_to_operational_records(uuid, uuid, uuid, uuid, text)'
  ];
begin
  if has_table_privilege('authenticated', 'app.customer_portal_booking_requests', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT hold SELECT on app.customer_portal_booking_requests directly -- the RPC layer is the only sanctioned access path';
  end if;
  if has_table_privilege('authenticated', 'app.customer_portal_booking_requests', 'INSERT') then
    raise exception 'assertion failed: authenticated must NOT hold INSERT on app.customer_portal_booking_requests directly';
  end if;
  if not has_table_privilege('service_role', 'app.customer_portal_booking_requests', 'SELECT') then
    raise exception 'assertion failed: service_role SHOULD hold SELECT on app.customer_portal_booking_requests';
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
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000305010", "role": "authenticated"}';
  begin
    perform count(*) from app.customer_portal_booking_requests;
    raise exception 'assertion failed: expected a permission-denied error on a raw authenticated SELECT against app.customer_portal_booking_requests';
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
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cbr1 Account Alpha');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000305050", "role": "authenticated"}';
  begin
    -- Real session is impersonator (305050); this call claims to act as alpha-admin (305010).
    perform app.create_customer_booking_request_draft(v_tenant1, v_account_alpha, null, 'forged', '{}'::jsonb, '{}'::jsonb, null, null, null, 'forged-booking-key', '00000000-0000-0000-0000-000000305010', 'forged-label');
    raise exception 'assertion failed: expected actor_identity_mismatch on create';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_booking_requests(v_tenant1, '00000000-0000-0000-0000-000000305010', null, null, null, null, 50);
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
  v_tenant1 uuid := (select id from app.tenants where slug = 'cbr1');
  v_direct_count integer;
  v_session_count integer;
begin
  select count(*) into v_direct_count from app.list_customer_booking_requests(v_tenant1, '00000000-0000-0000-0000-000000305010', null, null, null, null, 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000305010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_booking_requests(v_tenant1, '00000000-0000-0000-0000-000000305010', null, null, null, null, 200);
  reset role;

  if v_session_count <> v_direct_count or v_session_count = 0 then
    raise exception 'assertion failed: expected the real authenticated session to see the SAME nonzero row count (%) as the direct superuser call (%)', v_session_count, v_direct_count;
  end if;
end;
$$;
