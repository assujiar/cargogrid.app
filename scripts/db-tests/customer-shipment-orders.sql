-- Real, executable test evidence for CPL-304 (CG-S13-CPL-006, Prompt 304,
-- "Shipment Order") -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Structural convention mirrors scripts/db-tests/
-- customer-booking-requests.sql (CPL-303) exactly: two-tenant fixture,
-- direct RPC calls as the connecting superuser for parameter-driven
-- assertions, `set local role authenticated` + `set local request.jwt.claims`
-- only where the assertion genuinely needs a real session.
--
-- UUID range 00000000-0000-0000-0000-0000307xxx (tenant cso1) /
-- ...308xxx (tenant cso2) -- grep-verified unclaimed before this file was
-- written (right after CPL-303's own ...305xxx/...306xxx range). Tenant
-- slugs cso1/cso2.
--
-- Covers, live: (1) get is anti-enumerating (IDENTICAL record_not_found for
-- a nonexistent id and an out-of-scope id) and returns ONLY the
-- customer-safe projection (no idempotency_key/owner_user_id/org_unit_id/
-- created_by/split_reason/basis_* columns); (2) list is keyset-paginated,
-- account/status filterable, deny-by-default, cross-tenant isolated; (3)
-- request_customer_shipment_order_change validates request_type/details,
-- is scope-checked (anti-enumerating shipment_order_not_found), derives
-- account_id from the shipment order itself (never customer-supplied), and
-- is idempotent on (tenant_id, idempotency_key); (4)
-- list_customer_shipment_order_change_requests is scope-checked and
-- deny-by-default; (5) respond_to_customer_shipment_order_change_request is
-- staff-only (OPS:Edit), validates status/response, transitions
-- submitted -> acknowledged|resolved|rejected and
-- acknowledged -> resolved|rejected (resolved/rejected terminal), is
-- idempotent for an exact-match retry, and enforces optimistic concurrency;
-- (6) app.confirm_shipment_order/app.cancel_shipment_order are never called
-- by anything in the new migration (grep, not a live assertion -- confirmed
-- separately); (7) app.shipment_orders' own RLS is untouched -- a real
-- authenticated session still cannot read it directly; (8) raw-table
-- RLS/grant defense-in-depth on the new change-request table; (9)
-- actor-identity session cross-check on a write and a read RPC; (10) a
-- real, live authenticated-role positive-path call.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cso1 (staff: operations admin with OPS:Edit, and a no-authority staff member; accounts Alpha/Beta; alpha-admin active on Alpha, beta-admin active on Beta, impersonator with zero relationship); a second, otherwise-empty tenant cso2 (t2-admin on account T2) for cross-tenant isolation; a real job order/shipment order pair in cso1 for Account Alpha, and a second pair for Account Beta'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000307001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000307002';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000307010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000307020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000307050';
  v_staff2 uuid := '00000000-0000-0000-0000-000000308001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000308010';
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
  v_beta_lead app.leads;
  v_beta_prospect app.prospects;
  v_beta_opportunity app.opportunities;
  v_beta_quotation app.quotations;
  v_beta_handoff app.job_order_handoffs;
  v_beta_job_order app.job_orders;
  v_beta_shipment_order app.shipment_orders;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@cso1.test'),
    (v_staff_noauth, 'noauth@cso1.test'),
    (v_alpha_admin, 'alpha-admin@cso1.test'),
    (v_beta_admin, 'beta-admin@cso1.test'),
    (v_impersonator, 'impersonator@cso1.test'),
    (v_staff2, 'staff@cso2.test'),
    (v_t2_admin, 't2-admin@cso2.test');

  perform app.provision_tenant('cso1', 'Customer Shipment Order Tenant One', 'idem-cso1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cso1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CSO1-CO', 'Cso1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CSO1-CO');

  perform app.provision_tenant('cso2', 'Customer Shipment Order Tenant Two', 'idem-cso2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cso2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'CSO2-CO', 'Cso2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@cso1.test', 'Cso1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cso1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_staff_noauth, 'noauth@cso1.test', 'No Authority Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'noauth@cso1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@cso2.test', 'Cso2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@cso2.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant1, 'Ops Portal Staff', 'OPS Edit + COM Create/Edit/Approve', 'tester')).id;
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
  values (v_tenant1, 'Cso1 Account Alpha', 'cso1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cso1 Account Beta', 'cso1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cso2 Account T2', 'cso2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'cso1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'cso1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'cso2-staff');

  -- v_impersonator deliberately holds ZERO customer-portal grant of any kind.

  -- A real Commercial -> Operations pipeline for Account Alpha: opportunity ->
  -- prospect -> quotation -> accepted -> converted to the ALREADY-EXISTING
  -- v_account_alpha -> job order -> confirmed -> shipment order, exactly the
  -- established shape from customer-booking-requests.sql (CPL-303).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Cso1 Alpha Customer Ltd', 'Jane Requester', 'jane@cso1alpha.test', '0811', v_staff, v_company1, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cso1alpha.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@cso1alpha.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Cso1 Alpha Customer Ltd', 'Cso1 Alpha', '01.111.222.3-000.000',
    jsonb_build_object('line1', 'Jl. Test 1', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Cso1 Alpha Customer Ltd';
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Cso1 alpha test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'origin', 'Jakarta', 'destination', 'Surabaya'),
    v_staff, v_company1, v_staff, 'tester'
  );
  declare
    v_contact app.contacts;
    v_draft_quotation app.quotations;
    v_raw_token text;
  begin
    select * into v_contact from app.create_contact(v_tenant1, 'Cso1 Alpha Contact', 'Ops Manager', 'contact@cso1alpha.test', '0813', v_staff, v_company1, v_staff, 'tester');
    select * into v_draft_quotation from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_draft_quotation from app.add_quotation_line(v_draft_quotation.id, v_draft_quotation.record_version, 'service', 'Ocean freight base charge', null, 1, 15000000, 0, 0, v_staff, 'cso1-staff');
    select * into v_quotation from app.submit_quotation(v_draft_quotation.id, v_draft_quotation.record_version, v_staff, 'cso1-staff');
    select raw_token into v_raw_token from app.send_quotation_for_acceptance(v_quotation.id, v_contact.id, 'email', v_staff, 'cso1-staff');
    perform app.record_quotation_customer_decision(v_raw_token, 'accepted', 'Jane Requester', 'Ops Manager', 'contact@cso1alpha.test', null, null, null);
    select * into v_quotation from app.quotations where id = v_quotation.id;
    perform app.convert_quotation_to_account(v_quotation.id, v_account_alpha, null, v_staff, 'cso1-staff');
  end;
  select * into v_handoff from app.prepare_job_order_handoff(v_quotation.id, v_staff, 'cso1-staff');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_staff, 'cso1-staff');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_staff, 'cso1-staff');
  select * into v_shipment_order from app.create_shipment_order_from_job(
    v_job_order.id, 'shipment-cso1-alpha-001', jsonb_build_object('name', 'Alpha Consignee'), null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '5 days', now() + interval '10 days', 10, 1000, 20, null, null, null, null, v_staff, 'cso1-staff'
  );
  -- app.confirm_shipment_order (OPS:Edit, staff-only, byte-for-byte
  -- untouched by CPL-304's own migration) -- proves a real, canonically-
  -- confirmed shipment for the "confirmed status renders plainly" assertion.
  select * into v_shipment_order from app.confirm_shipment_order(v_shipment_order.id, v_shipment_order.record_version, v_staff, 'cso1-staff');

  -- An independent Beta pipeline (a completely different account) for
  -- cross-account/cross-scope negative assertions.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Cso1 Beta Customer Ltd', 'Beta Requester', 'beta@cso1beta.test', '0812', v_staff, v_company1, v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@cso1beta.test';
  perform app.qualify_lead(v_beta_lead.id, v_beta_lead.record_version, v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@cso1beta.test';
  perform app.convert_lead_to_prospect(v_beta_lead.id, 'Cso1 Beta Customer Ltd', 'Cso1 Beta', '01.111.222.4-000.000',
    jsonb_build_object('line1', 'Jl. Test 2', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_beta_prospect from app.prospects where legal_name = 'Cso1 Beta Customer Ltd';
  select * into v_beta_opportunity from app.create_opportunity(
    v_tenant1, v_beta_prospect.id, 'Cso1 beta test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'origin', 'Jakarta', 'destination', 'Surabaya'),
    v_staff, v_company1, v_staff, 'tester'
  );
  declare
    v_beta_contact app.contacts;
    v_beta_draft_quotation app.quotations;
    v_beta_raw_token text;
  begin
    select * into v_beta_contact from app.create_contact(v_tenant1, 'Cso1 Beta Contact', 'Ops Manager', 'contact@cso1beta.test', '0814', v_staff, v_company1, v_staff, 'tester');
    select * into v_beta_draft_quotation from app.create_quotation_draft(v_tenant1, v_beta_opportunity.id, 'IDR', now() + interval '14 days', v_beta_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_beta_draft_quotation from app.add_quotation_line(v_beta_draft_quotation.id, v_beta_draft_quotation.record_version, 'service', 'Ocean freight base charge', null, 1, 8000000, 0, 0, v_staff, 'cso1-staff');
    select * into v_beta_quotation from app.submit_quotation(v_beta_draft_quotation.id, v_beta_draft_quotation.record_version, v_staff, 'cso1-staff');
    select raw_token into v_beta_raw_token from app.send_quotation_for_acceptance(v_beta_quotation.id, v_beta_contact.id, 'email', v_staff, 'cso1-staff');
    perform app.record_quotation_customer_decision(v_beta_raw_token, 'accepted', 'Beta Requester', 'Ops Manager', 'contact@cso1beta.test', null, null, null);
    select * into v_beta_quotation from app.quotations where id = v_beta_quotation.id;
    perform app.convert_quotation_to_account(v_beta_quotation.id, v_account_beta, null, v_staff, 'cso1-staff');
  end;
  select * into v_beta_handoff from app.prepare_job_order_handoff(v_beta_quotation.id, v_staff, 'cso1-staff');
  select * into v_beta_job_order from app.prepare_job_order(v_beta_handoff.id, v_staff, 'cso1-staff');
  select * into v_beta_job_order from app.confirm_job_order(v_beta_job_order.id, v_beta_job_order.record_version, v_staff, 'cso1-staff');
  select * into v_beta_shipment_order from app.create_shipment_order_from_job(
    v_beta_job_order.id, 'shipment-cso1-beta-001', jsonb_build_object('name', 'Beta Consignee'), null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '5 days', now() + interval '10 days', 5, 500, 10, null, null, null, null, v_staff, 'cso1-staff'
  );
end;
$$;

\echo '>> app.get_customer_shipment_order: anti-enumeration -- IDENTICAL record_not_found for a nonexistent id and an out-of-scope id; success returns ONLY the customer-safe projection'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cso1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000307010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000307020';
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'shipment-cso1-alpha-001');
  v_row record;
  v_msg_nonexistent text;
  v_msg_forbidden text;
begin
  select * into v_row from app.get_customer_shipment_order(v_tenant1, v_alpha_admin, v_shipment_id);
  if v_row.id <> v_shipment_id then
    raise exception 'assertion failed: expected the returned row''s own id to match the requested shipment order';
  end if;
  if v_row.status <> 'confirmed' then
    raise exception 'assertion failed: expected the fixture shipment to be confirmed, got %', v_row.status;
  end if;
  -- shipment_number is server-generated (SHP-<year>-<seq>) -- not asserted
  -- verbatim, only that a real, non-empty value came back.
  if v_row.shipment_number is null or v_row.shipment_number = '' then
    raise exception 'assertion failed: expected a real, non-empty shipment_number';
  end if;
  if v_row.allocated_weight_kg <> 1000 or v_row.mode <> 'sea' or v_row.origin <> 'Jakarta' or v_row.destination <> 'Surabaya' then
    raise exception 'assertion failed: expected the fixture''s own real allocated_weight_kg/mode/origin/destination to come back unchanged';
  end if;

  begin
    perform app.get_customer_shipment_order(v_tenant1, v_alpha_admin, gen_random_uuid());
    raise exception 'assertion failed: expected record_not_found for a genuinely nonexistent id';
  exception
    when others then
      v_msg_nonexistent := sqlerrm;
  end;

  begin
    perform app.get_customer_shipment_order(v_tenant1, v_beta_admin, v_shipment_id);
    raise exception 'assertion failed: expected record_not_found for beta-admin reading an Alpha shipment order';
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

\echo '>> app.get_customer_shipment_order: the returned row genuinely carries no staff-internal column (idempotency_key, owner_user_id, org_unit_id, created_by, split_reason, basis_*)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cso1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000307010';
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'shipment-cso1-alpha-001');
  v_col_count integer;
begin
  select count(*) into v_col_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.proname = 'get_customer_shipment_order';
  if v_col_count <> 1 then
    raise exception 'assertion failed: expected exactly one app.get_customer_shipment_order function, found %', v_col_count;
  end if;

  -- Structural proof: the function's own declared return column list (from
  -- the catalog, not the migration source text) is exactly the 21
  -- customer-safe columns -- never idempotency_key/owner_user_id/
  -- org_unit_id/created_by/split_reason/basis_quantity/basis_weight_kg/
  -- basis_volume_cbm.
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'get_customer_shipment_order'
      and (
        pg_get_function_result(p.oid) like '%idempotency_key%'
        or pg_get_function_result(p.oid) like '%owner_user_id%'
        or pg_get_function_result(p.oid) like '%org_unit_id%'
        or pg_get_function_result(p.oid) like '%created_by%'
        or pg_get_function_result(p.oid) like '%split_reason%'
        or pg_get_function_result(p.oid) like '%basis_%'
      )
  ) then
    raise exception 'assertion failed: app.get_customer_shipment_order''s own return shape leaks a staff-internal column';
  end if;

  -- Same structural check on the list RPC.
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'list_customer_shipment_orders'
      and (
        pg_get_function_result(p.oid) like '%idempotency_key%'
        or pg_get_function_result(p.oid) like '%owner_user_id%'
        or pg_get_function_result(p.oid) like '%org_unit_id%'
        or pg_get_function_result(p.oid) like '%created_by%'
        or pg_get_function_result(p.oid) like '%split_reason%'
        or pg_get_function_result(p.oid) like '%basis_%'
      )
  ) then
    raise exception 'assertion failed: app.list_customer_shipment_orders'' own return shape leaks a staff-internal column';
  end if;
end;
$$;

\echo '>> app.list_customer_shipment_orders: keyset pagination visits every row exactly once, account/status filters, deny-by-default, cross-tenant isolation, invalid_cursor'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cso1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cso2');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000307010';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cso1 Account Alpha');
  v_t2_admin uuid := '00000000-0000-0000-0000-000000308010';
  v_impersonator uuid := '00000000-0000-0000-0000-000000307050';
  v_total integer;
  v_visited integer := 0;
  v_row record;
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_batch_count integer;
  v_alpha_only_count integer;
begin
  select count(*) into v_total from app.shipment_orders where tenant_id = v_tenant1;
  if v_total < 2 then
    raise exception 'assertion failed: expected at least 2 fixture shipment orders in cso1 by this point, found %', v_total;
  end if;

  loop
    v_batch_count := 0;
    for v_row in select * from app.list_customer_shipment_orders(v_tenant1, v_alpha_admin, null, null, v_cursor_updated_at, v_cursor_id, 1) loop
      v_visited := v_visited + 1;
      v_batch_count := v_batch_count + 1;
      v_cursor_updated_at := v_row.updated_at;
      v_cursor_id := v_row.id;
    end loop;
    exit when v_batch_count = 0;
  end loop;
  -- alpha-admin only sees the Alpha shipment (Beta is a different account, out of scope).
  if v_visited <> 1 then
    raise exception 'assertion failed: keyset pagination at limit=1 for alpha-admin visited % rows, expected exactly 1 (Beta''s shipment is out of scope)', v_visited;
  end if;

  select count(*) into v_alpha_only_count from app.list_customer_shipment_orders(v_tenant1, v_alpha_admin, v_account_alpha, null, null, null, 200);
  if v_alpha_only_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row filtered to Account Alpha, got %', v_alpha_only_count;
  end if;

  if exists (select 1 from app.list_customer_shipment_orders(v_tenant1, v_alpha_admin, null, 'draft', null, null, 200)) then
    raise exception 'assertion failed: expected zero draft-status rows for alpha-admin (fixture shipment is confirmed)';
  end if;

  -- Cross-tenant isolation: t2-admin (real customer_user in cso2) sees nothing from cso1.
  if exists (select 1 from app.list_customer_shipment_orders(v_tenant1, v_t2_admin, null, null, null, null, 200)) then
    raise exception 'assertion failed: expected zero cso1 rows for a cso2 identity';
  end if;

  -- Deny-by-default: an identity with zero customer-portal scope of any kind gets an empty result, never an error.
  if exists (select 1 from app.list_customer_shipment_orders(v_tenant1, v_impersonator, null, null, null, null, 200)) then
    raise exception 'assertion failed: expected zero rows for an identity with no customer-portal scope';
  end if;

  begin
    perform app.list_customer_shipment_orders(v_tenant1, v_alpha_admin, null, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor for p_cursor_id supplied without p_cursor_updated_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end;
$$;

\echo '>> app.request_customer_shipment_order_change: validates request_type/details, scope-checked (anti-enumerating shipment_order_not_found), derives account_id from the shipment order itself, idempotent on (tenant_id, idempotency_key)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cso1');
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cso1 Account Alpha');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000307010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000307020';
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'shipment-cso1-alpha-001');
  v_request app.customer_portal_shipment_change_requests;
  v_request2 app.customer_portal_shipment_change_requests;
  v_count integer;
begin
  select * into v_request from app.request_customer_shipment_order_change(
    v_tenant1, v_shipment_id, 'reschedule', 'Please move pickup one day later', 'change-cso1-alpha-001', v_alpha_admin, 'alpha-admin'
  );
  if v_request.status <> 'submitted' or v_request.account_id <> v_account_alpha or v_request.shipment_order_id <> v_shipment_id or v_request.requested_by_auth_user_id <> v_alpha_admin then
    raise exception 'assertion failed: expected a new submitted change request on Account Alpha, with account_id derived from the shipment order itself';
  end if;

  -- Idempotent: same key returns the SAME row, no duplicate.
  select * into v_request2 from app.request_customer_shipment_order_change(
    v_tenant1, v_shipment_id, 'cancel', 'DIFFERENT -- must be ignored', 'change-cso1-alpha-001', v_alpha_admin, 'alpha-admin'
  );
  if v_request2.id <> v_request.id or v_request2.request_type <> v_request.request_type then
    raise exception 'assertion failed: expected idempotent create to return the original row unchanged';
  end if;
  select count(*) into v_count from app.customer_portal_shipment_change_requests where tenant_id = v_tenant1 and idempotency_key = 'change-cso1-alpha-001';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly one row for idempotency key change-cso1-alpha-001, found %', v_count;
  end if;

  -- Invalid request type.
  begin
    perform app.request_customer_shipment_order_change(v_tenant1, v_shipment_id, 'not_a_real_type', 'x', null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_request_type';
  exception
    when others then
      if sqlerrm not like 'invalid_request_type%' then raise; end if;
  end;

  -- Empty details.
  begin
    perform app.request_customer_shipment_order_change(v_tenant1, v_shipment_id, 'other', '   ', null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected details_required for whitespace-only details';
  exception
    when others then
      if sqlerrm not like 'details_required%' then raise; end if;
  end;

  -- Beta's own admin may not request a change against Alpha's shipment order --
  -- combined anti-enumerating error (design decision 3b).
  begin
    perform app.request_customer_shipment_order_change(v_tenant1, v_shipment_id, 'other', 'x', null, v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected shipment_order_not_found for beta-admin acting on an Alpha shipment order';
  exception
    when others then
      if sqlerrm not like 'shipment_order_not_found%' then raise; end if;
  end;

  -- A genuinely nonexistent shipment order id produces the SAME error shape.
  begin
    perform app.request_customer_shipment_order_change(v_tenant1, gen_random_uuid(), 'other', 'x', null, v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected shipment_order_not_found for a nonexistent shipment order id';
  exception
    when others then
      if sqlerrm not like 'shipment_order_not_found%' then raise; end if;
  end;
end;
$$;

\echo '>> app.list_customer_shipment_order_change_requests: scope-checked, optional shipment filter, deny-by-default, cross-tenant isolation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cso1');
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000307010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000307020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000307050';
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'shipment-cso1-alpha-001');
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_shipment_order_change_requests(v_tenant1, v_alpha_admin, v_shipment_id, null, null, 50);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 change request visible to alpha-admin for this shipment, got %', v_count;
  end if;

  if exists (select 1 from app.list_customer_shipment_order_change_requests(v_tenant1, v_beta_admin, null, null, null, 50)) then
    raise exception 'assertion failed: expected zero change requests visible to beta-admin (Beta has never submitted one, and Alpha''s own row is out of scope)';
  end if;

  if exists (select 1 from app.list_customer_shipment_order_change_requests(v_tenant1, v_impersonator, null, null, null, 50)) then
    raise exception 'assertion failed: expected zero rows for an identity with no customer-portal scope';
  end if;
end;
$$;

\echo '>> app.respond_to_customer_shipment_order_change_request: staff-only (OPS:Edit), validates status/response, real transitions, idempotent exact-match retry, optimistic concurrency'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cso1');
  v_staff uuid := '00000000-0000-0000-0000-000000307001';
  v_staff_noauth uuid := '00000000-0000-0000-0000-000000307002';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000307010';
  v_request app.customer_portal_shipment_change_requests;
  v_acked app.customer_portal_shipment_change_requests;
  v_retry app.customer_portal_shipment_change_requests;
  v_resolved app.customer_portal_shipment_change_requests;
begin
  select * into v_request from app.customer_portal_shipment_change_requests where tenant_id = v_tenant1 and idempotency_key = 'change-cso1-alpha-001';

  -- Invalid target status.
  begin
    perform app.respond_to_customer_shipment_order_change_request(v_request.id, v_request.record_version, 'submitted', 'x', v_staff, 'cso1-staff');
    raise exception 'assertion failed: expected invalid_status for p_to_status=submitted';
  exception
    when others then
      if sqlerrm not like 'invalid_status%' then raise; end if;
  end;

  -- Empty staff response.
  begin
    perform app.respond_to_customer_shipment_order_change_request(v_request.id, v_request.record_version, 'acknowledged', '', v_staff, 'cso1-staff');
    raise exception 'assertion failed: expected staff_response_required for an empty response';
  exception
    when others then
      if sqlerrm not like 'staff_response_required%' then raise; end if;
  end;

  -- A staff member without OPS:Edit is rejected.
  begin
    perform app.respond_to_customer_shipment_order_change_request(v_request.id, v_request.record_version, 'acknowledged', 'Looking into it', v_staff_noauth, 'no-authority-staff');
    raise exception 'assertion failed: expected insufficient_authority for a staff actor lacking OPS:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- A customer (Layer 4, not staff) may not respond at all.
  begin
    perform app.respond_to_customer_shipment_order_change_request(v_request.id, v_request.record_version, 'acknowledged', 'Looking into it', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected insufficient_authority for a customer_user-layer actor with no OPS:Edit';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- Real submitted -> acknowledged.
  select * into v_acked from app.respond_to_customer_shipment_order_change_request(v_request.id, v_request.record_version, 'acknowledged', 'Looking into it', v_staff, 'cso1-staff');
  if v_acked.status <> 'acknowledged' or v_acked.staff_response <> 'Looking into it' or v_acked.staff_responded_by <> 'cso1-staff' or v_acked.staff_responded_at is null then
    raise exception 'assertion failed: expected submitted -> acknowledged with staff_response/staff_responded_by/staff_responded_at recorded';
  end if;
  if v_acked.record_version <> v_request.record_version + 1 then
    raise exception 'assertion failed: expected record_version to advance by exactly 1';
  end if;

  -- Idempotent retry: SAME target status + SAME response text, even with the now-stale version, is a no-op.
  select * into v_retry from app.respond_to_customer_shipment_order_change_request(v_request.id, v_request.record_version, 'acknowledged', 'Looking into it', v_staff, 'cso1-staff');
  if v_retry.id <> v_acked.id or v_retry.record_version <> v_acked.record_version then
    raise exception 'assertion failed: expected an idempotent no-op retry to return the unchanged acknowledged row';
  end if;

  -- A DIFFERENT response text on the SAME already-acknowledged status is a real conflict (invalid_transition), never a silent overwrite.
  begin
    perform app.respond_to_customer_shipment_order_change_request(v_acked.id, v_acked.record_version, 'acknowledged', 'A different response', v_staff, 'cso1-staff');
    raise exception 'assertion failed: expected invalid_transition for a same-status, different-response call';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Stale version.
  begin
    perform app.respond_to_customer_shipment_order_change_request(v_acked.id, v_request.record_version, 'resolved', 'Resolved now', v_staff, 'cso1-staff');
    raise exception 'assertion failed: expected stale_version for a re-used expected_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  -- Real acknowledged -> resolved.
  select * into v_resolved from app.respond_to_customer_shipment_order_change_request(v_acked.id, v_acked.record_version, 'resolved', 'Rescheduled as requested', v_staff, 'cso1-staff');
  if v_resolved.status <> 'resolved' then
    raise exception 'assertion failed: expected acknowledged -> resolved';
  end if;

  -- resolved is terminal.
  begin
    perform app.respond_to_customer_shipment_order_change_request(v_resolved.id, v_resolved.record_version, 'rejected', 'too late', v_staff, 'cso1-staff');
    raise exception 'assertion failed: expected invalid_transition -- resolved is terminal';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- Unknown change request id.
  begin
    perform app.respond_to_customer_shipment_order_change_request(gen_random_uuid(), 1, 'acknowledged', 'x', v_staff, 'cso1-staff');
    raise exception 'assertion failed: expected change_request_not_found';
  exception
    when others then
      if sqlerrm not like 'change_request_not_found%' then raise; end if;
  end;
end;
$$;

\echo '>> app.confirm_shipment_order/app.cancel_shipment_order remain byte-for-byte untouched and unreachable from this migration -- no function this migration adds calls either'
do $$
declare
  v_bad_callers text[];
begin
  select array_agg(p.proname order by p.proname) into v_bad_callers
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'get_customer_shipment_order', 'list_customer_shipment_orders',
      'request_customer_shipment_order_change', 'list_customer_shipment_order_change_requests',
      'respond_to_customer_shipment_order_change_request'
    )
    -- Matches an actual CALL (name immediately followed by `(`), never a
    -- prose mention inside a comment -- this migration's own functions
    -- legitimately discuss app.confirm_shipment_order/app.cancel_shipment_
    -- order by name in their own header comments (e.g. explaining they
    -- reuse the same OPS:Edit action those two functions also require),
    -- which must not itself trip this structural check.
    and (p.prosrc ~ 'confirm_shipment_order\s*\(' or p.prosrc ~ 'cancel_shipment_order\s*\(');

  if v_bad_callers is not null then
    raise exception 'assertion failed: % of this migration''s own functions call app.confirm_shipment_order/app.cancel_shipment_order, which must stay staff-only and unreachable from any customer RPC: %', array_length(v_bad_callers, 1), v_bad_callers;
  end if;
end;
$$;

\echo '>> app.shipment_orders'' own RLS remains untouched -- a real authenticated session still cannot read it directly (CG-S10-ATW-032 default-deny, unaffected by this migration)'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000307010", "role": "authenticated"}';
  begin
    perform count(*) from app.shipment_orders;
    -- app.shipment_orders' own select policy (app.can_access_record) does
    -- not necessarily raise permission-denied for `authenticated` (unlike a
    -- zero-grant table) -- but it must return ZERO rows for a customer_user
    -- with no staff org-unit/owner relationship, never the fixture's real
    -- shipment orders.
    if exists (select 1 from app.shipment_orders) then
      raise exception 'assertion failed: expected a customer_user-layer session to see zero rows directly against app.shipment_orders (its own RLS is untouched by this migration and already denies by default)';
    end if;
  exception
    when insufficient_privilege then
      null; -- also an acceptable, even stricter, outcome
  end;
  reset role;
end;
$$;

\echo '>> raw-table RLS/grant defense-in-depth on the new change-request table: authenticated holds NO direct table privilege (service_role only); anon holds no EXECUTE on any of the 5 new functions; authenticated/service_role hold EXECUTE'
do $$
declare
  v_fn text;
  v_has_priv boolean;
  v_functions text[] := array[
    'app.get_customer_shipment_order(uuid, uuid, uuid)',
    'app.list_customer_shipment_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.request_customer_shipment_order_change(uuid, uuid, text, text, text, uuid, text)',
    'app.list_customer_shipment_order_change_requests(uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.respond_to_customer_shipment_order_change_request(uuid, integer, text, text, uuid, text)'
  ];
begin
  if has_table_privilege('authenticated', 'app.customer_portal_shipment_change_requests', 'SELECT') then
    raise exception 'assertion failed: authenticated must NOT hold SELECT on app.customer_portal_shipment_change_requests directly -- the RPC layer is the only sanctioned access path';
  end if;
  if has_table_privilege('authenticated', 'app.customer_portal_shipment_change_requests', 'INSERT') then
    raise exception 'assertion failed: authenticated must NOT hold INSERT on app.customer_portal_shipment_change_requests directly';
  end if;
  if not has_table_privilege('service_role', 'app.customer_portal_shipment_change_requests', 'SELECT') then
    raise exception 'assertion failed: service_role SHOULD hold SELECT on app.customer_portal_shipment_change_requests';
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

  -- A raw, real authenticated session genuinely cannot read the new table at all.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000307010", "role": "authenticated"}';
  begin
    perform count(*) from app.customer_portal_shipment_change_requests;
    raise exception 'assertion failed: expected a permission-denied error on a raw authenticated SELECT against app.customer_portal_shipment_change_requests';
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
  v_tenant1 uuid := (select id from app.tenants where slug = 'cso1');
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'shipment-cso1-alpha-001');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000307050", "role": "authenticated"}';
  begin
    -- Real session is impersonator (307050); this call claims to act as alpha-admin (307010).
    perform app.request_customer_shipment_order_change(v_tenant1, v_shipment_id, 'other', 'forged', 'forged-change-key', '00000000-0000-0000-0000-000000307010', 'forged-label');
    raise exception 'assertion failed: expected actor_identity_mismatch on request_customer_shipment_order_change';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_shipment_orders(v_tenant1, '00000000-0000-0000-0000-000000307010', null, null, null, null, 50);
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
  v_tenant1 uuid := (select id from app.tenants where slug = 'cso1');
  v_direct_count integer;
  v_session_count integer;
begin
  select count(*) into v_direct_count from app.list_customer_shipment_orders(v_tenant1, '00000000-0000-0000-0000-000000307010', null, null, null, null, 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000307010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_shipment_orders(v_tenant1, '00000000-0000-0000-0000-000000307010', null, null, null, null, 200);
  reset role;

  if v_session_count <> v_direct_count or v_session_count = 0 then
    raise exception 'assertion failed: expected the real authenticated session to see the SAME nonzero row count (%) as the direct superuser call (%)', v_session_count, v_direct_count;
  end if;
end;
$$;
