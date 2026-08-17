-- Real, executable test evidence for CPL-306 (CG-S13-CPL-008, Prompt 306,
-- "Shipment Monitoring") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Structural convention mirrors
-- scripts/db-tests/customer-shipment-orders.sql (CPL-304) and
-- scripts/db-tests/customer-shipment-tracking.sql (CPL-305) exactly.
--
-- UUID range 00000000-0000-0000-0000-0000311xxx (tenant csa1) /
-- ...312xxx (tenant csa2) -- grep-verified unclaimed (right after CPL-305's
-- own ...309xxx/...310xxx range).
--
-- Covers, live: (1) subscribe/unsubscribe validation, anti-enumerating
-- scope check, natural-key idempotency both ways, reversibility (no
-- terminal state); (2) list_customer_shipment_alert_subscriptions self-only
-- + live rescoping (a suspended account membership immediately hides an
-- otherwise-untouched subscription row); (3) THE DEEPER, LIVE-VERIFIED
-- finding disclosed in the migration header's own design decision 8: a real
-- app.queue_notification call targeting a customer_user recipient is
-- unconditionally rejected (notification_recipient_unauthorized), proving
-- the "no scheduler exists" disclosure is not the only emission blocker;
-- (4) list_customer_shipment_alerts correctly filters/scopes/paginates real
-- app.notifications rows placed directly (the only viable path today, given
-- (3)) -- type-code filtering, self-only isolation, shipment-scope
-- filtering, unread_only, keyset pagination; (5) actor-identity session
-- cross-check on every RPC; (6) raw-function/table grant defense in depth.

\set ON_ERROR_STOP on

\echo '>> setup: tenant csa1 (staff with OPS:Create/Edit/View/Assign + COM:Create/Edit/Approve + CPT:Create, a tenant_admin for Configuration Engine; accounts Alpha/Beta; alpha-admin active on Alpha, beta-admin active on Beta, impersonator with zero relationship); a second, otherwise-empty tenant csa2 (t2-admin on account T2) for cross-tenant isolation; a real Commercial -> Operations pipeline producing one confirmed shipment order each for Account Alpha and Account Beta in csa1 (no leg/telemetry/milestone data needed -- this capability never reads shipment content itself)'
create temporary table csa_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000311001';
  v_supreme uuid := '00000000-0000-0000-0000-000000311003';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000311010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000311020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000311050';
  v_staff2 uuid := '00000000-0000-0000-0000-000000312001';
  v_t2_admin uuid := '00000000-0000-0000-0000-000000312010';
  v_role uuid; v_draft app.role_versions;
  v_role2 uuid; v_draft2 app.role_versions;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_t2 uuid;
  v_alpha_membership app.customer_portal_account_memberships;
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
  v_quotation app.quotations;
  v_handoff app.job_order_handoffs;
  v_job_order app.job_orders;
  v_shipment_alpha app.shipment_orders;
  v_beta_lead app.leads;
  v_beta_prospect app.prospects;
  v_beta_opportunity app.opportunities;
  v_beta_quotation app.quotations;
  v_beta_handoff app.job_order_handoffs;
  v_beta_job_order app.job_orders;
  v_shipment_beta app.shipment_orders;
begin
  insert into auth.users (id, email) values
    (v_staff, 'staff@csa1.test'),
    (v_supreme, 'supreme@csa1.test'),
    (v_alpha_admin, 'alpha-admin@csa1.test'),
    (v_beta_admin, 'beta-admin@csa1.test'),
    (v_impersonator, 'impersonator@csa1.test'),
    (v_staff2, 'staff@csa2.test'),
    (v_t2_admin, 't2-admin@csa2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('csa1', 'Customer Shipment Alerts Tenant One', 'idem-csa1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'csa1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CSA1-CO', 'Csa1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CSA1-CO');

  perform app.provision_tenant('csa2', 'Customer Shipment Alerts Tenant Two', 'idem-csa2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'csa2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  v_company2 := (app.create_org_unit(v_tenant2, 'company', null, 'CSA2-CO', 'Csa2 Co', 'tester')).id;

  perform app.invite_user(v_tenant1, v_staff, 'staff@csa1.test', 'Csa1 Staff', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@csa1.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, v_staff2, 'staff@csa2.test', 'Csa2 Staff', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'staff@csa2.test'), 'active', 'onboarded', 'tester');

  v_role := (app.create_role(v_tenant1, 'Ops Portal Staff', 'OPS Edit/Assign + COM Create/Edit/Approve + CPT Create', 'tester')).id;
  v_draft := app.create_role_version(v_role, 'tester');
  perform app.set_role_version_permissions(
    v_draft.id,
    array(select id from app.permissions where (resource_module_code = 'OPS' and action in ('View', 'Create', 'Edit', 'Assign')) or (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve')) or (resource_module_code = 'CPT' and action = 'Create')),
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
  values (v_tenant1, 'Csa1 Account Alpha', 'csa1-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Csa1 Account Beta', 'csa1-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Csa2 Account T2', 'csa2-t2-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_t2;

  v_alpha_membership := app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_alpha, v_alpha_admin, v_staff, 'csa1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant1, v_account_beta, v_beta_admin, v_staff, 'csa1-staff');
  perform app.grant_initial_customer_portal_account_admin(v_tenant2, v_account_t2, v_t2_admin, v_staff2, 'csa2-staff');

  -- v_impersonator deliberately holds ZERO customer-portal grant of any kind.

  -- A real Commercial -> Operations pipeline for Account Alpha.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Csa1 Alpha Customer Ltd', 'Jane Requester', 'jane@csa1alpha.test', '0811', v_staff, v_company1, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@csa1alpha.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_staff, 'tester');
  select * into v_lead from app.leads where email = 'jane@csa1alpha.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Csa1 Alpha Customer Ltd', 'Csa1 Alpha', '01.111.222.5-000.000',
    jsonb_build_object('line1', 'Jl. Test 1', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Csa1 Alpha Customer Ltd';
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Csa1 alpha test lane',
    jsonb_build_object('service_type', 'land_freight', 'origin', 'Jakarta', 'destination', 'Bandung'),
    v_staff, v_company1, v_staff, 'tester'
  );
  declare
    v_contact app.contacts;
    v_draft_quotation app.quotations;
    v_raw_token text;
  begin
    select * into v_contact from app.create_contact(v_tenant1, 'Csa1 Alpha Contact', 'Ops Manager', 'contact@csa1alpha.test', '0813', v_staff, v_company1, v_staff, 'tester');
    select * into v_draft_quotation from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_draft_quotation from app.add_quotation_line(v_draft_quotation.id, v_draft_quotation.record_version, 'service', 'Land freight base charge', null, 1, 6000000, 0, 0, v_staff, 'csa1-staff');
    select * into v_quotation from app.submit_quotation(v_draft_quotation.id, v_draft_quotation.record_version, v_staff, 'csa1-staff');
    select raw_token into v_raw_token from app.send_quotation_for_acceptance(v_quotation.id, v_contact.id, 'email', v_staff, 'csa1-staff');
    perform app.record_quotation_customer_decision(v_raw_token, 'accepted', 'Jane Requester', 'Ops Manager', 'contact@csa1alpha.test', null, null, null);
    select * into v_quotation from app.quotations where id = v_quotation.id;
    perform app.convert_quotation_to_account(v_quotation.id, v_account_alpha, null, v_staff, 'csa1-staff');
  end;
  select * into v_handoff from app.prepare_job_order_handoff(v_quotation.id, v_staff, 'csa1-staff');
  select * into v_job_order from app.prepare_job_order(v_handoff.id, v_staff, 'csa1-staff');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, v_staff, 'csa1-staff');
  select * into v_shipment_alpha from app.create_shipment_order_from_job(
    v_job_order.id, 'shipment-csa1-alpha-001', jsonb_build_object('name', 'Alpha Consignee'), null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 2000, 2000, 40, 2000, 2000, 40, null, v_staff, 'csa1-staff'
  );
  select * into v_shipment_alpha from app.confirm_shipment_order(v_shipment_alpha.id, v_shipment_alpha.record_version, v_staff, 'csa1-staff');

  -- An independent Account Beta shipment.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Csa1 Beta Customer Ltd', 'Beta Requester', 'beta@csa1beta.test', '0812', v_staff, v_company1, v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@csa1beta.test';
  perform app.qualify_lead(v_beta_lead.id, v_beta_lead.record_version, v_staff, 'tester');
  select * into v_beta_lead from app.leads where email = 'beta@csa1beta.test';
  perform app.convert_lead_to_prospect(v_beta_lead.id, 'Csa1 Beta Customer Ltd', 'Csa1 Beta', '01.111.222.6-000.000',
    jsonb_build_object('line1', 'Jl. Test 2', 'city', 'Jakarta', 'country', 'ID'), v_staff, 'tester');
  select * into v_beta_prospect from app.prospects where legal_name = 'Csa1 Beta Customer Ltd';
  select * into v_beta_opportunity from app.create_opportunity(
    v_tenant1, v_beta_prospect.id, 'Csa1 beta test lane',
    jsonb_build_object('service_type', 'land_freight', 'origin', 'Jakarta', 'destination', 'Bandung'),
    v_staff, v_company1, v_staff, 'tester'
  );
  declare
    v_beta_contact app.contacts;
    v_beta_draft_quotation app.quotations;
    v_beta_raw_token text;
  begin
    select * into v_beta_contact from app.create_contact(v_tenant1, 'Csa1 Beta Contact', 'Ops Manager', 'contact@csa1beta.test', '0814', v_staff, v_company1, v_staff, 'tester');
    select * into v_beta_draft_quotation from app.create_quotation_draft(v_tenant1, v_beta_opportunity.id, 'IDR', now() + interval '14 days', v_beta_contact.id, v_staff, null, v_staff, 'tester');
    select * into v_beta_draft_quotation from app.add_quotation_line(v_beta_draft_quotation.id, v_beta_draft_quotation.record_version, 'service', 'Land freight base charge', null, 1, 3000000, 0, 0, v_staff, 'csa1-staff');
    select * into v_beta_quotation from app.submit_quotation(v_beta_draft_quotation.id, v_beta_draft_quotation.record_version, v_staff, 'csa1-staff');
    select raw_token into v_beta_raw_token from app.send_quotation_for_acceptance(v_beta_quotation.id, v_beta_contact.id, 'email', v_staff, 'csa1-staff');
    perform app.record_quotation_customer_decision(v_beta_raw_token, 'accepted', 'Beta Requester', 'Ops Manager', 'contact@csa1beta.test', null, null, null);
    select * into v_beta_quotation from app.quotations where id = v_beta_quotation.id;
    perform app.convert_quotation_to_account(v_beta_quotation.id, v_account_beta, null, v_staff, 'csa1-staff');
  end;
  select * into v_beta_handoff from app.prepare_job_order_handoff(v_beta_quotation.id, v_staff, 'csa1-staff');
  select * into v_beta_job_order from app.prepare_job_order(v_beta_handoff.id, v_staff, 'csa1-staff');
  select * into v_beta_job_order from app.confirm_job_order(v_beta_job_order.id, v_beta_job_order.record_version, v_staff, 'csa1-staff');
  select * into v_shipment_beta from app.create_shipment_order_from_job(
    v_beta_job_order.id, 'shipment-csa1-beta-001', jsonb_build_object('name', 'Beta Consignee'), null, 'land_freight', 'land', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '2 days', 5, 500, 10, null, null, null, null, v_staff, 'csa1-staff'
  );
  select * into v_shipment_beta from app.confirm_shipment_order(v_shipment_beta.id, v_shipment_beta.record_version, v_staff, 'csa1-staff');

  insert into csa_test_state (key, value) values
    ('tenant1_id', v_tenant1::text), ('tenant2_id', v_tenant2::text),
    ('account_alpha_id', v_account_alpha::text), ('account_beta_id', v_account_beta::text),
    ('shipment_alpha_id', v_shipment_alpha.id::text), ('shipment_beta_id', v_shipment_beta.id::text),
    ('alpha_membership_id', v_alpha_membership.id::text), ('alpha_membership_version', v_alpha_membership.record_version::text);
end;
$$;

\echo '>> app.subscribe_customer_shipment_alert: invalid_alert_type, anti-enumerating shipment_order_not_found (nonexistent AND out-of-scope collapse to the identical error), a real successful subscribe with server-derived account_id, and idempotent re-subscribe'
do $$
declare
  v_tenant1 uuid := (select value from csa_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000311010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000311020';
  v_shipment_alpha uuid := (select value::uuid from csa_test_state where key = 'shipment_alpha_id');
  v_account_alpha uuid := (select value::uuid from csa_test_state where key = 'account_alpha_id');
  v_row app.customer_shipment_alert_subscriptions;
  v_row2 app.customer_shipment_alert_subscriptions;
  v_msg text;
begin
  begin
    perform app.subscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'not_a_real_alert_type', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected invalid_alert_type';
  exception
    when check_violation then
      if sqlerrm not like 'invalid_alert_type%' then raise exception 'assertion failed: expected invalid_alert_type, got %', sqlerrm; end if;
  end;

  begin
    perform app.subscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', v_beta_admin, 'beta-admin');
    raise exception 'assertion failed: expected shipment_order_not_found for beta-admin subscribing to Alpha''s own shipment';
  exception
    when no_data_found then
      v_msg := sqlerrm;
  end;
  if v_msg not like 'shipment_order_not_found%' then
    raise exception 'assertion failed: expected shipment_order_not_found (out-of-scope), got %', v_msg;
  end if;

  begin
    perform app.subscribe_customer_shipment_alert(v_tenant1, gen_random_uuid(), 'milestone_delay', v_alpha_admin, 'alpha-admin');
    raise exception 'assertion failed: expected shipment_order_not_found for a genuinely nonexistent shipment order';
  exception
    when no_data_found then
      v_msg := sqlerrm;
  end;
  if v_msg not like 'shipment_order_not_found%' then
    raise exception 'assertion failed: expected shipment_order_not_found (nonexistent), got %', v_msg;
  end if;

  v_row := app.subscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', v_alpha_admin, 'alpha-admin');
  if v_row.status <> 'active' or v_row.account_id <> v_account_alpha or v_row.shipment_order_id <> v_shipment_alpha or v_row.auth_user_id <> v_alpha_admin or v_row.alert_type <> 'milestone_delay' then
    raise exception 'assertion failed: expected a real active subscription row with server-derived account_id, got %', v_row;
  end if;

  -- Idempotent: a repeated subscribe for the SAME natural key returns the SAME row id, still active.
  v_row2 := app.subscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', v_alpha_admin, 'alpha-admin');
  if v_row2.id <> v_row.id or v_row2.status <> 'active' then
    raise exception 'assertion failed: expected the repeated subscribe to be idempotent on the natural key (same row id, still active), got id % status %', v_row2.id, v_row2.status;
  end if;
  if (select count(*) from app.customer_shipment_alert_subscriptions where shipment_order_id = v_shipment_alpha and auth_user_id = v_alpha_admin and alert_type = 'milestone_delay') <> 1 then
    raise exception 'assertion failed: expected exactly ONE row for this natural key, never a duplicate';
  end if;

  -- A second, independent alert_type subscription for the same shipment.
  perform app.subscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'exception', v_alpha_admin, 'alpha-admin');
end;
$$;

\echo '>> app.unsubscribe_customer_shipment_alert: idempotent both ways (no prior row creates an explicit unsubscribed row; unsubscribing an active row flips it; re-subscribing afterward flips it back -- a genuinely reversible preference, no terminal state)'
do $$
declare
  v_tenant1 uuid := (select value from csa_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000311010';
  v_shipment_alpha uuid := (select value::uuid from csa_test_state where key = 'shipment_alpha_id');
  v_row app.customer_shipment_alert_subscriptions;
begin
  -- Never subscribed to 'delivery' before -- unsubscribe still succeeds, creating an explicit unsubscribed row.
  v_row := app.unsubscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'delivery', v_alpha_admin, 'alpha-admin');
  if v_row.status <> 'unsubscribed' then
    raise exception 'assertion failed: expected status=unsubscribed for a never-subscribed alert_type, got %', v_row.status;
  end if;

  -- Unsubscribing the real 'milestone_delay' row (currently active from the prior block).
  v_row := app.unsubscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', v_alpha_admin, 'alpha-admin');
  if v_row.status <> 'unsubscribed' then
    raise exception 'assertion failed: expected status=unsubscribed after unsubscribe, got %', v_row.status;
  end if;

  -- Re-unsubscribing is a no-op-shaped success (idempotent).
  v_row := app.unsubscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', v_alpha_admin, 'alpha-admin');
  if v_row.status <> 'unsubscribed' then
    raise exception 'assertion failed: expected re-unsubscribe to remain unsubscribed';
  end if;

  -- Re-subscribing flips it back to active -- proves this is a real, reversible two-value toggle, not a terminal state machine.
  v_row := app.subscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', v_alpha_admin, 'alpha-admin');
  if v_row.status <> 'active' then
    raise exception 'assertion failed: expected re-subscribe after unsubscribe to succeed (active), got %', v_row.status;
  end if;
  if (select count(*) from app.customer_shipment_alert_subscriptions where shipment_order_id = v_shipment_alpha and auth_user_id = v_alpha_admin and alert_type = 'milestone_delay') <> 1 then
    raise exception 'assertion failed: expected exactly ONE row across the entire active->unsubscribed->active cycle, never a second row';
  end if;
end;
$$;

\echo '>> app.list_customer_shipment_alert_subscriptions: self-only, deny-by-default for zero-scope/out-of-scope callers, shipment filter, invalid_cursor'
do $$
declare
  v_tenant1 uuid := (select value from csa_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000311010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000311020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000311050';
  v_shipment_alpha uuid := (select value::uuid from csa_test_state where key = 'shipment_alpha_id');
  v_count integer;
begin
  -- 3 rows by this point: milestone_delay (active), exception (active), and
  -- delivery (unsubscribed, from the prior block's idempotent-both-ways
  -- proof) -- list_customer_shipment_alert_subscriptions returns every
  -- subscription row regardless of status, active and unsubscribed alike.
  select count(*) into v_count from app.list_customer_shipment_alert_subscriptions(v_tenant1, v_alpha_admin);
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 subscription rows for alpha-admin (milestone_delay active, exception active, delivery unsubscribed), got %', v_count;
  end if;
  select count(*) into v_count from app.customer_shipment_alert_subscriptions where auth_user_id = v_alpha_admin and status = 'active';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 ACTIVE rows for alpha-admin, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_shipment_alert_subscriptions(v_tenant1, v_alpha_admin, v_shipment_alpha);
  if v_count <> 3 then
    raise exception 'assertion failed: expected the shipment filter to still return all 3 rows for the same shipment, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_shipment_alert_subscriptions(v_tenant1, v_beta_admin);
  if v_count <> 0 then
    raise exception 'assertion failed: expected beta-admin (never subscribed to anything) to see 0, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_shipment_alert_subscriptions(v_tenant1, v_impersonator);
  if v_count <> 0 then
    raise exception 'assertion failed: expected a zero-scope impersonator to see 0 (deny-by-default, never an error), got %', v_count;
  end if;

  begin
    perform app.list_customer_shipment_alert_subscriptions(v_tenant1, v_alpha_admin, null, null, gen_random_uuid());
    raise exception 'assertion failed: expected invalid_cursor for a cursor_id supplied without cursor_updated_at';
  exception
    when invalid_parameter_value then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end;
$$;

\echo '>> Tier C fix (spec-compliance Finding 3, batch review of CPL-305..309): cross-tenant isolation, live-proven against the SECOND tenant (csa2/t2-admin) provisioned in setup for exactly this purpose -- a genuine customer_user identity in an entirely unrelated tenant, probing all 4 RPCs with tenant1''s own id, never sees or affects tenant1''s data'
do $$
declare
  v_tenant1 uuid := (select value from csa_test_state where key = 'tenant1_id')::uuid;
  v_t2_admin uuid := '00000000-0000-0000-0000-000000312010';
  v_shipment_alpha uuid := (select value::uuid from csa_test_state where key = 'shipment_alpha_id');
  v_count integer;
  v_msg text;
begin
  -- t2-admin (real, active customer_user in tenant csa2, on Account T2 --
  -- zero relationship of any kind to csa1) subscribing to csa1's own Alpha
  -- shipment, passing csa1's own tenant id: the identical anti-enumerating
  -- shipment_order_not_found a same-tenant out-of-scope caller (beta-admin,
  -- above) already gets -- never a distinguishable cross-tenant error, never
  -- a successful subscription.
  begin
    perform app.subscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', v_t2_admin, 't2-admin');
    raise exception 'assertion failed: expected shipment_order_not_found for a genuinely cross-tenant identity subscribing to tenant1''s own shipment';
  exception
    when no_data_found then
      v_msg := sqlerrm;
  end;
  if v_msg not like 'shipment_order_not_found%' then
    raise exception 'assertion failed: expected shipment_order_not_found (cross-tenant), got %', v_msg;
  end if;
  if (select count(*) from app.customer_shipment_alert_subscriptions where shipment_order_id = v_shipment_alpha and auth_user_id = v_t2_admin) <> 0 then
    raise exception 'assertion failed: expected ZERO subscription rows created for the rejected cross-tenant attempt';
  end if;

  -- list_customer_shipment_alert_subscriptions: t2-admin, probing with
  -- tenant1's own id, sees 0 rows -- never tenant1's or their own tenant2
  -- data leaking across the tenant boundary via a foreign p_tenant_id.
  select count(*) into v_count from app.list_customer_shipment_alert_subscriptions(v_tenant1, v_t2_admin);
  if v_count <> 0 then
    raise exception 'assertion failed: expected a genuinely cross-tenant identity to see 0 subscription rows when probing with tenant1''s own id, got %', v_count;
  end if;

  -- list_customer_shipment_alerts: same cross-tenant probe, same expectation.
  select count(*) into v_count from app.list_customer_shipment_alerts(v_tenant1, v_t2_admin);
  if v_count <> 0 then
    raise exception 'assertion failed: expected a genuinely cross-tenant identity to see 0 alert rows when probing with tenant1''s own id, got %', v_count;
  end if;

  -- unsubscribe: the same anti-enumerating collapse as subscribe -- a
  -- cross-tenant identity unsubscribing from a shipment it was never
  -- subscribed to (and cannot even see) still raises shipment_order_not_found,
  -- never a silent no-op success that would confirm the shipment's existence.
  begin
    perform app.unsubscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', v_t2_admin, 't2-admin');
    raise exception 'assertion failed: expected shipment_order_not_found for a genuinely cross-tenant identity unsubscribing from tenant1''s own shipment';
  exception
    when no_data_found then
      v_msg := sqlerrm;
  end;
  if v_msg not like 'shipment_order_not_found%' then
    raise exception 'assertion failed: expected shipment_order_not_found (cross-tenant unsubscribe), got %', v_msg;
  end if;
end;
$$;

\echo '>> THE DEEPER FINDING (migration header design decision 8, live-reproduced here as checked-in evidence, not merely asserted): app.queue_notification cannot successfully queue a notification to a customer_user-layer recipient AT ALL -- notification_recipient_unauthorized, unconditionally, because that recipient''s own app.tenant_user_identities.status never reaches active'
do $$
declare
  v_tenant1 uuid := (select value from csa_test_state where key = 'tenant1_id')::uuid;
  v_staff uuid := '00000000-0000-0000-0000-000000311001';
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000311010';
  v_draft app.config_versions;
  v_status text;
  v_msg text;
begin
  select status into v_status from app.tenant_user_identities where tenant_id = v_tenant1 and auth_user_id = v_alpha_admin;
  if v_status is distinct from 'invited' then
    raise exception 'assertion failed: expected the customer_user identity''s own tenant_user_identities.status to be ''invited'' (never transitioned to active by any Phase 8 RPC), got %', v_status;
  end if;
  if app.has_active_tenant_membership(v_tenant1, v_alpha_admin) is distinct from false then
    raise exception 'assertion failed: expected app.has_active_tenant_membership to be false for a customer_user-layer identity';
  end if;

  v_draft := app.create_config_draft('notification:shipment_alert_milestone_delay', v_tenant1, 'tenant', null, v_staff, 'csa1-staff');
  perform app.set_config_items(
    v_draft.id,
    '[
      {"key": "channels", "value": ["in_app"]},
      {"key": "default_locale", "value": "en"},
      {"key": "templates", "value": {"en": {"subject": "Shipment {{shipment_number}} delayed", "body": "A tracked milestone is running behind schedule."}}}
    ]'::jsonb,
    v_staff, 'csa1-staff'
  );
  perform app.publish_notification_template(v_draft.id, v_staff, null, 'csa1-staff');

  begin
    perform app.queue_notification(
      v_draft.id, v_tenant1, 'shipment_alert_milestone_delay', v_alpha_admin, 'in_app', 'en',
      jsonb_build_object('shipment_number', 'shipment-csa1-alpha-001'), 'csa1-attempt-1', v_staff, 'csa1-staff'
    );
    raise exception 'assertion failed: expected notification_recipient_unauthorized -- a customer_user recipient can never satisfy app.queue_notification''s own has_active_tenant_membership recipient-authorization gate today';
  exception
    when insufficient_privilege then
      v_msg := sqlerrm;
  end;
  if v_msg not like 'notification_recipient_unauthorized%' then
    raise exception 'assertion failed: expected notification_recipient_unauthorized, got %', v_msg;
  end if;

  insert into csa_test_state (key, value) values ('notification_config_version_id', v_draft.id::text)
  on conflict (key) do update set value = excluded.value;
end;
$$;

\echo '>> app.list_customer_shipment_alerts: composes app.list_notifications_for_recipient, filtered to this capability''s own 6 notification_type_code values -- proven against rows placed directly (the only viable path today, per the finding above), never a fabricated emission mechanism'
do $$
declare
  v_tenant1 uuid := (select value from csa_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000311010';
  v_beta_admin uuid := '00000000-0000-0000-0000-000000311020';
  v_shipment_alpha uuid := (select value::uuid from csa_test_state where key = 'shipment_alpha_id');
  v_config_version_id uuid := (select value::uuid from csa_test_state where key = 'notification_config_version_id');
  v_alert_id uuid;
  v_unrelated_id uuid;
  v_beta_id uuid;
  v_count integer;
  v_row app.notifications;
begin
  -- A real, capability-owned alert for alpha-admin, linked to Alpha's own shipment via the disclosed context.shipmentOrderId convention.
  insert into app.notifications (id, tenant_id, config_version_id, notification_type_code, recipient_auth_user_id, requested_channel, effective_channel, locale, subject, body, context, status, dedupe_key, triggered_by)
  values (gen_random_uuid(), v_tenant1, v_config_version_id, 'shipment_alert_milestone_delay', v_alpha_admin, 'in_app', 'in_app', 'en', 'Shipment delayed', 'Your shipment is running behind schedule.', jsonb_build_object('shipmentOrderId', v_shipment_alpha::text), 'sent', 'csa-alert-1', 'tester')
  returning id into v_alert_id;

  -- A negative control: an UNRELATED notification_type_code for the SAME recipient -- must never be returned.
  insert into app.notifications (id, tenant_id, config_version_id, notification_type_code, recipient_auth_user_id, requested_channel, effective_channel, locale, subject, body, context, status, dedupe_key, triggered_by)
  values (gen_random_uuid(), v_tenant1, v_config_version_id, 'some_other_unrelated_type', v_alpha_admin, 'in_app', 'in_app', 'en', 'Unrelated', 'Not one of this capability''s 6 types.', '{}'::jsonb, 'sent', 'csa-unrelated-1', 'tester')
  returning id into v_unrelated_id;

  -- A negative control: a real capability-owned alert for a DIFFERENT recipient (beta-admin) -- must never leak to alpha-admin.
  insert into app.notifications (id, tenant_id, config_version_id, notification_type_code, recipient_auth_user_id, requested_channel, effective_channel, locale, subject, body, context, status, dedupe_key, triggered_by)
  values (gen_random_uuid(), v_tenant1, v_config_version_id, 'shipment_alert_exception', v_beta_admin, 'in_app', 'in_app', 'en', 'Beta exception', 'Beta''s own alert.', '{}'::jsonb, 'sent', 'csa-beta-1', 'tester')
  returning id into v_beta_id;

  select count(*) into v_count from app.list_customer_shipment_alerts(v_tenant1, v_alpha_admin);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 alert for alpha-admin (the unrelated type and beta-admin''s own alert both excluded), got %', v_count;
  end if;

  select * into v_row from app.list_customer_shipment_alerts(v_tenant1, v_alpha_admin) limit 1;
  if v_row.id <> v_alert_id then
    raise exception 'assertion failed: expected the returned row to be the capability-owned alert, got %', v_row.id;
  end if;

  select count(*) into v_count from app.list_customer_shipment_alerts(v_tenant1, v_beta_admin);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 alert for beta-admin (their own), got %', v_count;
  end if;

  -- Shipment-scope filter: matches via the disclosed context.shipmentOrderId convention.
  select count(*) into v_count from app.list_customer_shipment_alerts(v_tenant1, v_alpha_admin, v_shipment_alpha);
  if v_count <> 1 then
    raise exception 'assertion failed: expected the shipment filter to match via context.shipmentOrderId, got %', v_count;
  end if;

  -- Shipment-scope filter for a shipment this identity cannot see at all -- deny-by-default, empty, never an error.
  select count(*) into v_count from app.list_customer_shipment_alerts(v_tenant1, v_alpha_admin, gen_random_uuid());
  if v_count <> 0 then
    raise exception 'assertion failed: expected 0 rows for an out-of-scope/nonexistent shipment filter, got %', v_count;
  end if;

  -- unread_only: mark the real alert read, confirm it is excluded.
  perform app.mark_notification_read(v_alert_id, v_alpha_admin, 'alpha-admin');
  select count(*) into v_count from app.list_customer_shipment_alerts(v_tenant1, v_alpha_admin, null, true);
  if v_count <> 0 then
    raise exception 'assertion failed: expected unread_only=true to exclude the now-read alert, got %', v_count;
  end if;

  begin
    perform app.list_customer_shipment_alerts(v_tenant1, v_alpha_admin, null, false, null, gen_random_uuid());
    raise exception 'assertion failed: expected invalid_cursor for a cursor_id supplied without cursor_created_at';
  exception
    when invalid_parameter_value then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end;
$$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity, on every one of the 4 new RPCs'
do $$
declare
  v_tenant1 uuid := (select value from csa_test_state where key = 'tenant1_id')::uuid;
  v_shipment_alpha uuid := (select value::uuid from csa_test_state where key = 'shipment_alpha_id');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000311050", "role": "authenticated"}';

  begin
    perform app.subscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', '00000000-0000-0000-0000-000000311010', 'alpha-admin');
    raise exception 'assertion failed: expected actor_identity_mismatch on subscribe';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.unsubscribe_customer_shipment_alert(v_tenant1, v_shipment_alpha, 'milestone_delay', '00000000-0000-0000-0000-000000311010', 'alpha-admin');
    raise exception 'assertion failed: expected actor_identity_mismatch on unsubscribe';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_shipment_alert_subscriptions(v_tenant1, '00000000-0000-0000-0000-000000311010');
    raise exception 'assertion failed: expected actor_identity_mismatch on list_customer_shipment_alert_subscriptions';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_shipment_alerts(v_tenant1, '00000000-0000-0000-0000-000000311010');
    raise exception 'assertion failed: expected actor_identity_mismatch on list_customer_shipment_alerts';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  reset role;
end;
$$;

\echo '>> a real, live authenticated-role positive-path call: alpha-admin''s own real session sees the same result a direct superuser call returns'
do $$
declare
  v_tenant1 uuid := (select value from csa_test_state where key = 'tenant1_id')::uuid;
  v_direct integer;
  v_session integer;
begin
  select count(*) into v_direct from app.list_customer_shipment_alert_subscriptions(v_tenant1, '00000000-0000-0000-0000-000000311010');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000311010", "role": "authenticated"}';
  select count(*) into v_session from app.list_customer_shipment_alert_subscriptions(v_tenant1, '00000000-0000-0000-0000-000000311010');
  reset role;

  if v_session <> v_direct or v_session = 0 then
    raise exception 'assertion failed: expected the real authenticated session to see the SAME nonzero count a direct superuser call returns (session %, direct %)', v_session, v_direct;
  end if;
end;
$$;

\echo '>> raw-table/raw-function grant defense in depth: authenticated has zero direct grant on the new table; anon holds no EXECUTE on any of the 4 new functions; authenticated/service_role hold EXECUTE on all 4'
do $$
declare
  v_has_priv boolean;
  v_fn text;
begin
  begin
    set local role authenticated;
    perform 1 from app.customer_shipment_alert_subscriptions limit 1;
    raise exception 'assertion failed: expected authenticated to be denied a raw select on app.customer_shipment_alert_subscriptions';
  exception
    when insufficient_privilege then
      null;
  end;
  reset role;

  foreach v_fn in array array[
    'app.subscribe_customer_shipment_alert(uuid, uuid, text, uuid, text)',
    'app.unsubscribe_customer_shipment_alert(uuid, uuid, text, uuid, text)',
    'app.list_customer_shipment_alert_subscriptions(uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.list_customer_shipment_alerts(uuid, uuid, uuid, boolean, timestamptz, uuid, integer)'
  ]
  loop
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

\echo '>> LIVE rescoping (decision 4): a subscription row stops appearing the instant its own account membership is suspended, without the row itself being touched. Run LAST and deliberately never reactivated -- alpha-admin is Account Alpha''s sole account_admin, so self-suspension via app.set_customer_portal_account_membership_status leaves no remaining account_admin able to reactivate it through that same RPC (app.grant_initial_customer_portal_account_admin is a one-time bootstrap that no-ops, never reactivates, on an existing non-revoked row) -- an honest, disclosed consequence of this fixture''s own single-admin shape, not a defect in the RPC under test.'
do $$
declare
  v_tenant1 uuid := (select value from csa_test_state where key = 'tenant1_id')::uuid;
  v_alpha_admin uuid := '00000000-0000-0000-0000-000000311010';
  v_membership_id uuid := (select value::uuid from csa_test_state where key = 'alpha_membership_id');
  v_membership_version integer := (select value::integer from csa_test_state where key = 'alpha_membership_version');
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_shipment_alert_subscriptions(v_tenant1, v_alpha_admin);
  if v_count <> 3 then
    raise exception 'assertion failed: expected 3 rows before suspension, got %', v_count;
  end if;

  -- The actor must be an active account_admin on the SAME account (app.
  -- actor_is_active_customer_portal_account_admin) -- alpha-admin themselves
  -- still qualifies at this point.
  perform app.set_customer_portal_account_membership_status(v_membership_id, v_membership_version, 'suspended', 'live rescoping test', v_alpha_admin, 'alpha-admin');

  select count(*) into v_count from app.list_customer_shipment_alert_subscriptions(v_tenant1, v_alpha_admin);
  if v_count <> 0 then
    raise exception 'assertion failed: expected 0 rows once alpha-admin''s own account membership is suspended (live rescoping), got %', v_count;
  end if;
  if (select count(*) from app.customer_shipment_alert_subscriptions where auth_user_id = v_alpha_admin) <> 3 then
    raise exception 'assertion failed: expected the underlying subscription rows to be COMPLETELY untouched by the membership suspension -- still 3 real rows in the table';
  end if;
end;
$$;
