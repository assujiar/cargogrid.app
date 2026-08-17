-- Real, executable test evidence for CPL-309 (CG-S13-CPL-011, Prompt 309,
-- "Warehouse Inventory Visibility") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Structural convention mirrors scripts/db-tests/
-- advanced-tms-customer-inventory-access.sql (ATW-023) and scripts/db-tests/
-- customer-portal-scope.sql (CPL-300): a single Supreme Admin actor performs all
-- staff-side setup plumbing (this contract has no staff RBAC dependency at all --
-- that is the entire point being tested), plus one tenant-admin staff identity
-- with `CPT:Create` for the one bootstrap RPC (app.grant_initial_customer_portal_
-- account_admin) this fixture needs to seed a NEW-grant-table-only membership.
--
-- UUID range 00000000-0000-0000-0000-000000317xxx (tenant cwi1) /
-- 00000000-0000-0000-0000-000000318xxx (tenant cwi2), grep-verified unclaimed
-- (right after CPL-308's own ...315xxx/...316xxx range).
--
-- Covers, live: (a) cross-tenant and cross-customer isolation; (b) revoking
-- warehouse eligibility immediately blocks access (a live query, never cached);
-- (c) a legacy single-account customer_account_ref actor still resolves
-- correctly through the new resolver (regression against ATW-023's existing
-- behavior); (d) THE KEY REGRESSION TEST -- an actor granted a SECOND account
-- ONLY through CPL-300's new app.customer_portal_account_memberships table,
-- never through the legacy customer_account_ref marker, CAN see that second
-- account's inventory through this migration's new RPCs, side-by-side with the
-- SAME actor calling ATW-023's own app.list_customer_inventory_balances/app.
-- list_customer_warehouse_eligibility and seeing NOTHING for that account --
-- live proof the ISS-2026-117 scope gap is actually closed, not just
-- structurally plausible; (e) anti-enumeration -- a forged/foreign balance id
-- and a genuinely nonexistent one raise the identical error; (f) pagination
-- correctness. Also: direct unit coverage of app.evaluate_customer_portal_
-- inventory_access; all-zero-row exclusion; the actor-identity session
-- cross-check (assert_actor_is_session_identity) on every new RPC; raw-table
-- RLS defense-in-depth on app.inventory_balances/app.warehouse_customer_
-- eligibility (both already denied a customer_user actor by their own,
-- untouched-by-this-migration RLS policy); app.record_customer_inventory_
-- access_denial reuse (ATW-023, unmodified) durably auditing a denial from this
-- migration's own get RPC.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cwi1 (accounts Alpha/Beta/Gamma, warehouses WH-CWI-1/2/REVOKE/GAMMA), tenant cwi2 (account Delta, warehouse WH-CWI-T2); customer-legacy (Alpha, legacy marker only), customer-multi (Alpha via legacy marker + Gamma via the NEW CPL-300 grant table ONLY -- the key regression fixture), customer-beta (Beta, legacy only), customer-badref (non-uuid ref), impersonator (zero grants)'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_account_alpha app.accounts;
  v_account_beta app.accounts;
  v_account_gamma app.accounts;
  v_account_delta app.accounts;
  v_wh1 app.warehouses;
  v_wh2 app.warehouses;
  v_wh_revoke app.warehouses;
  v_wh_gamma app.warehouses;
  v_wh_t2 app.warehouses;
  v_rack1 app.warehouse_locations;
  v_rack1b app.warehouse_locations;
  v_rack1c app.warehouse_locations;
  v_rack2 app.warehouse_locations;
  v_rack_revoke app.warehouse_locations;
  v_rack_gamma app.warehouse_locations;
  v_rack_t2 app.warehouse_locations;
  v_item_alpha uuid;
  v_item_beta uuid;
  v_item_gamma uuid;
  v_item_delta uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000000317001';
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@cwi.test'),
    ('00000000-0000-0000-0000-000000317010', 'customer-legacy@cwi1.test'),
    ('00000000-0000-0000-0000-000000317011', 'customer-multi@cwi1.test'),
    ('00000000-0000-0000-0000-000000317020', 'customer-beta@cwi1.test'),
    ('00000000-0000-0000-0000-000000317030', 'customer-badref@cwi1.test'),
    ('00000000-0000-0000-0000-000000317050', 'impersonator@cwi1.test'),
    ('00000000-0000-0000-0000-000000318010', 'customer-t2@cwi2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cwi1', 'Customer Warehouse Inventory Visibility Tenant One', 'idem-cwi1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cwi1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CWI1-CO', 'Cwi1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CWI1-CO');

  perform app.provision_tenant('cwi2', 'Customer Warehouse Inventory Visibility Tenant Two', 'idem-cwi2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cwi2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CWI2-CO', 'Cwi2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CWI2-CO');

  -- Direct fixture inserts (bypasses the full lead->prospect->quotation->convert
  -- Commercial pipeline, out of scope for this capability's own test -- mirrors
  -- advanced-tms-customer-inventory-access.sql/customer-portal-scope.sql's own
  -- established convention).
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cwi Account Alpha', 'cwi-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning * into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cwi Account Beta', 'cwi-beta-fp', '{}'::jsonb, v_company1, 'tester') returning * into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cwi Account Gamma', 'cwi-gamma-fp', '{}'::jsonb, v_company1, 'tester') returning * into v_account_gamma;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cwi Account Delta', 'cwi-delta-fp', '{}'::jsonb, v_company2, 'tester') returning * into v_account_delta;

  -- customer-legacy: Alpha via the LEGACY app.principal_memberships.
  -- customer_account_ref marker ONLY -- no row of any kind in app.
  -- customer_portal_account_memberships. Proves item (c): a pre-CPL-300 style
  -- grant still resolves correctly through the new resolver.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000317010', 'customer-legacy@cwi1.test', 'Cwi Customer Legacy', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-legacy@cwi1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000317010', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');

  -- customer-multi: Alpha via the SAME legacy marker AS ABOVE, PLUS Gamma via
  -- a DIRECT insert into the NEW app.customer_portal_account_memberships
  -- table ONLY -- never a legacy app.principal_memberships row for Gamma.
  --
  -- Both of CPL-300's own real write RPCs (app.grant_initial_customer_portal_
  -- account_admin, and app.invite_customer_portal_user + app.accept_
  -- customer_portal_invite) deliberately ALSO call app.grant_principal_
  -- membership for the SAME account when they create a new-table row (CPL-300
  -- design: "the point at which the identity first becomes entitled to live
  -- WMS/inventory... access through the legacy resolver") -- confirmed live
  -- against this exact fixture (this test's own first draft called app.grant_
  -- initial_customer_portal_account_admin here and it failed the very next
  -- assertion below with "expected ZERO legacy row, got 1"). So a genuinely
  -- new-table-only grant, with no legacy marker at all for that account, is
  -- not reachable through either shipped write RPC today -- it is reachable
  -- through a service-role-level direct table write (a future capability,
  -- a migration backfill, or a support/reconciliation action), which is
  -- exactly what this direct fixture insert simulates, mirroring the
  -- established "direct fixture insert, bypasses the full pipeline"
  -- convention already used throughout this file and its siblings for
  -- setup plumbing that does not need to re-prove an already-VERIFIED RPC's
  -- own behavior.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000317011', 'customer-multi@cwi1.test', 'Cwi Customer Multi', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-multi@cwi1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000317011', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  insert into app.customer_portal_account_memberships
    (tenant_id, auth_user_id, account_id, role, status, invited_by, invited_at, granted_by, granted_at, accepted_at)
  values
    (v_tenant1, '00000000-0000-0000-0000-000000317011', v_account_gamma.id, 'account_admin', 'active', 'tester', now(), 'tester', now(), now());

  -- customer-beta: Beta via the legacy marker only -- isolation fixture.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000317020', 'customer-beta@cwi1.test', 'Cwi Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@cwi1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000317020', 'customer_user', v_tenant1, v_account_beta.id::text, 'tester');

  -- customer-badref: a non-uuid-shaped legacy customer_account_ref -- must
  -- resolve to an EMPTY scope, never an error and never another owner's data
  -- (mirrors ATW-023's own identical fixture).
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000317030', 'customer-badref@cwi1.test', 'Cwi Customer Badref', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-badref@cwi1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000317030', 'customer_user', v_tenant1, 'LEGACY-CWI-0007', 'tester');

  -- impersonator: a real, active tenant1 identity with ZERO customer_user
  -- grant of any kind -- used only for the actor-identity session cross-check.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000317050', 'impersonator@cwi1.test', 'Cwi Impersonator', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@cwi1.test'), 'active', 'onboarded', 'tester');

  -- customer-t2: Delta via the legacy marker, in the ISOLATED tenant cwi2.
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000318010', 'customer-t2@cwi2.test', 'Cwi Customer T2', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-t2@cwi2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000318010', 'customer_user', v_tenant2, v_account_delta.id::text, 'tester');

  -- Warehouses in tenant1: WH-CWI-1 (Alpha), WH-CWI-2 (Beta), WH-CWI-REVOKE
  -- (Alpha, revoked mid-test), WH-CWI-GAMMA (Gamma -- the key regression
  -- warehouse). One warehouse in tenant2: WH-CWI-T2 (Delta).
  v_wh1 := app.create_warehouse(v_tenant1, v_company1, 'WH-CWI-1', 'Cwi Warehouse 1 (Alpha)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh2 := app.create_warehouse(v_tenant1, v_company1, 'WH-CWI-2', 'Cwi Warehouse 2 (Beta)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh_revoke := app.create_warehouse(v_tenant1, v_company1, 'WH-CWI-REVOKE', 'Cwi Warehouse Revoke (Alpha, later revoked)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh_gamma := app.create_warehouse(v_tenant1, v_company1, 'WH-CWI-GAMMA', 'Cwi Warehouse Gamma (new-grant-table-only)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh_t2 := app.create_warehouse(v_tenant2, v_company2, 'WH-CWI-T2', 'Cwi Tenant2 Warehouse', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');

  v_rack1 := app.create_warehouse_location(v_wh1.id, null, null, 'RACK-CWI-1A', 'Rack 1A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack1.id, 'active', null, v_rack1.record_version, v_supreme, 'admin');
  v_rack1b := app.create_warehouse_location(v_wh1.id, null, null, 'RACK-CWI-1B', 'Rack 1B', 'rack', 2, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack1b.id, 'active', null, v_rack1b.record_version, v_supreme, 'admin');
  v_rack1c := app.create_warehouse_location(v_wh1.id, null, null, 'RACK-CWI-1C', 'Rack 1C', 'rack', 3, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack1c.id, 'active', null, v_rack1c.record_version, v_supreme, 'admin');
  v_rack2 := app.create_warehouse_location(v_wh2.id, null, null, 'RACK-CWI-2A', 'Rack 2A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack2.id, 'active', null, v_rack2.record_version, v_supreme, 'admin');
  v_rack_revoke := app.create_warehouse_location(v_wh_revoke.id, null, null, 'RACK-CWI-RA', 'Rack Revoke A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack_revoke.id, 'active', null, v_rack_revoke.record_version, v_supreme, 'admin');
  v_rack_gamma := app.create_warehouse_location(v_wh_gamma.id, null, null, 'RACK-CWI-GA', 'Rack Gamma A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack_gamma.id, 'active', null, v_rack_gamma.record_version, v_supreme, 'admin');
  v_rack_t2 := app.create_warehouse_location(v_wh_t2.id, null, null, 'RACK-CWI-T2A', 'Rack T2 A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack_t2.id, 'active', null, v_rack_t2.record_version, v_supreme, 'admin');

  -- Warehouse eligibility grants -- Alpha eligible for WH-CWI-1/WH-CWI-REVOKE,
  -- Beta eligible for WH-CWI-2, Gamma eligible for WH-CWI-GAMMA, Delta
  -- eligible for WH-CWI-T2.
  perform app.grant_warehouse_customer_eligibility(v_wh1.id, v_account_alpha.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh2.id, v_account_beta.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_revoke.id, v_account_alpha.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_gamma.id, v_account_gamma.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_t2.id, v_account_delta.id, v_supreme, 'admin');

  -- Items (untracked -- lot/serial control not needed for this capability's own test).
  v_item_alpha := (app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CWI-ALPHA', 'Cwi Alpha Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;
  v_item_beta := (app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-CWI-BETA', 'Cwi Beta Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;
  v_item_gamma := (app.create_item_master(v_tenant1, v_account_gamma.id, 'SKU-CWI-GAMMA', 'Cwi Gamma Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;
  v_item_delta := (app.create_item_master(v_tenant2, v_account_delta.id, 'SKU-CWI-DELTA', 'Cwi Delta Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;

  -- Alpha balances in WH-CWI-1 -- THREE distinct rows (three locations), to
  -- prove cursor pagination actually advances across pages (item f).
  perform app.post_inventory_movement(
    v_tenant1, v_wh1.id, 'opening_balance', 'opening_balance', null, 'idem-cwi-open-a1-1', 'cwi fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1.id, 'uom_code', 'PCS', 'signed_quantity', 10)),
    v_supreme, 'admin'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_wh1.id, 'opening_balance', 'opening_balance', null, 'idem-cwi-open-a1-2', 'cwi fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1b.id, 'uom_code', 'PCS', 'signed_quantity', 1)),
    v_supreme, 'admin'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_wh1.id, 'opening_balance', 'opening_balance', null, 'idem-cwi-open-a1-3', 'cwi fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1c.id, 'uom_code', 'PCS', 'signed_quantity', 30)),
    v_supreme, 'admin'
  );

  -- A FOURTH Alpha/WH-CWI-1 dimension that nets to all-zero (receive then
  -- fully consume) -- proves the list RPC excludes it exactly as ATW-023's
  -- own app.list_customer_inventory_balances already does (design decision 3
  -- of the migration's own header: "same all-zero-row exclusion").
  perform app.post_inventory_movement(
    v_tenant1, v_wh1.id, 'opening_balance', 'opening_balance', null, 'idem-cwi-open-a1-zero', 'cwi fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1c.id, 'uom_code', 'PCS', 'signed_quantity', 5, 'status', 'damaged')),
    v_supreme, 'admin'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_wh1.id, 'adjustment', 'manual', null, 'idem-cwi-open-a1-zero-out', 'zero out for exclusion test',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1c.id, 'uom_code', 'PCS', 'signed_quantity', -5, 'status', 'damaged')),
    v_supreme, 'admin'
  );

  -- Beta balance in WH-CWI-2 -- isolation fixture (item a).
  perform app.post_inventory_movement(
    v_tenant1, v_wh2.id, 'opening_balance', 'opening_balance', null, 'idem-cwi-open-b1', 'cwi fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta.id, 'item_master_id', v_item_beta, 'location_id', v_rack2.id, 'uom_code', 'PCS', 'signed_quantity', 15)),
    v_supreme, 'admin'
  );

  -- Alpha balance in WH-CWI-REVOKE -- the revocation-immediate-effect fixture (item b).
  perform app.post_inventory_movement(
    v_tenant1, v_wh_revoke.id, 'opening_balance', 'opening_balance', null, 'idem-cwi-open-revoke-a', 'cwi fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack_revoke.id, 'uom_code', 'PCS', 'signed_quantity', 3)),
    v_supreme, 'admin'
  );

  -- Gamma balance in WH-CWI-GAMMA -- THE KEY REGRESSION FIXTURE (item d):
  -- owner_account_id=Gamma, only reachable through customer-multi's NEW-
  -- grant-table-only membership.
  perform app.post_inventory_movement(
    v_tenant1, v_wh_gamma.id, 'opening_balance', 'opening_balance', null, 'idem-cwi-open-gamma', 'cwi fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_gamma.id, 'item_master_id', v_item_gamma, 'location_id', v_rack_gamma.id, 'uom_code', 'PCS', 'signed_quantity', 20)),
    v_supreme, 'admin'
  );

  -- Delta balance in tenant2's own WH-CWI-T2 -- cross-tenant isolation fixture (item a).
  perform app.post_inventory_movement(
    v_tenant2, v_wh_t2.id, 'opening_balance', 'opening_balance', null, 'idem-cwi-open-t2-delta', 'cwi fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_delta.id, 'item_master_id', v_item_delta, 'location_id', v_rack_t2.id, 'uom_code', 'PCS', 'signed_quantity', 4)),
    v_supreme, 'admin'
  );
end $$;

\echo '>> app.evaluate_customer_portal_inventory_access: direct unit coverage -- true only when BOTH the widened scope check and the warehouse-eligibility check hold'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000317011';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Beta');
  v_account_gamma uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Gamma');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWI-1');
  v_wh2 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWI-2');
  v_wh_gamma uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWI-GAMMA');
begin
  if not app.evaluate_customer_portal_inventory_access(v_customer_multi, v_tenant1, v_wh1, v_account_alpha) then
    raise exception 'assertion failed: expected customer-multi to be granted access to Alpha (their own legacy-marker scope) in WH-CWI-1 (eligible)';
  end if;
  if not app.evaluate_customer_portal_inventory_access(v_customer_multi, v_tenant1, v_wh_gamma, v_account_gamma) then
    raise exception 'assertion failed: expected customer-multi to be granted access to Gamma (NEW-grant-table-only scope) in WH-CWI-GAMMA (eligible) -- the core ISS-2026-117 fix';
  end if;
  if app.evaluate_customer_portal_inventory_access(v_customer_multi, v_tenant1, v_wh2, v_account_beta) then
    raise exception 'assertion failed: expected customer-multi to be DENIED for Beta''s own owner_account_id (out of scope)';
  end if;
  if app.evaluate_customer_portal_inventory_access(v_customer_multi, v_tenant1, v_wh2, v_account_alpha) then
    raise exception 'assertion failed: expected customer-multi to be DENIED for WH-CWI-2 with Alpha''s own owner_account_id (Alpha has no eligibility grant there)';
  end if;
end $$;

\echo '>> app.get_customer_portal_inventory_balance: own row succeeds; forbidden and genuinely-nonexistent ids raise the IDENTICAL record_not_found shape (item e, anti-enumeration); app.record_customer_inventory_access_denial (ATW-023, reused as-is) durably records a denial for either cause'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000317011';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Beta');
  v_account_gamma uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Gamma');
  v_alpha_balance_id uuid := (select id from app.inventory_balances where tenant_id = v_tenant1 and owner_account_id = v_account_alpha and on_hand = 10);
  v_gamma_balance_id uuid := (select id from app.inventory_balances where tenant_id = v_tenant1 and owner_account_id = v_account_gamma and on_hand = 20);
  v_beta_balance_id uuid := (select id from app.inventory_balances where tenant_id = v_tenant1 and owner_account_id = v_account_beta and on_hand = 15);
  v_fake_id uuid := '99999999-9999-9999-9999-999999999999';
  v_forbidden_msg text;
  v_missing_msg text;
  v_audit_count integer;
  v_row record;
begin
  select * into v_row from app.get_customer_portal_inventory_balance(v_tenant1, v_customer_multi, v_alpha_balance_id);
  if v_row.id <> v_alpha_balance_id or v_row.on_hand <> 10 then
    raise exception 'assertion failed: expected customer-multi to read their own Alpha (legacy-marker) balance, got %', v_row;
  end if;

  -- THE KEY REGRESSION PROOF at the single-row level: Gamma, reachable ONLY
  -- through the new grant table, is readable via this migration's own get RPC.
  select * into v_row from app.get_customer_portal_inventory_balance(v_tenant1, v_customer_multi, v_gamma_balance_id);
  if v_row.id <> v_gamma_balance_id or v_row.on_hand <> 20 then
    raise exception 'assertion failed: expected customer-multi to read their own Gamma (NEW-grant-table-only) balance -- ISS-2026-117 fix, got %', v_row;
  end if;

  begin
    perform app.get_customer_portal_inventory_balance(v_tenant1, v_customer_multi, v_beta_balance_id);
    raise exception 'assertion failed: expected record_not_found -- customer-multi must not read Beta''s balance';
  exception
    when others then
      v_forbidden_msg := sqlerrm;
      if v_forbidden_msg not like 'record_not_found%' then raise; end if;
  end;

  begin
    perform app.get_customer_portal_inventory_balance(v_tenant1, v_customer_multi, v_fake_id);
    raise exception 'assertion failed: expected record_not_found -- a genuinely nonexistent id';
  exception
    when others then
      v_missing_msg := sqlerrm;
      if v_missing_msg not like 'record_not_found%' then raise; end if;
  end;

  if left(v_forbidden_msg, 16) <> left(v_missing_msg, 16) then
    raise exception 'assertion failed: expected the forbidden-but-existing and genuinely-nonexistent errors to share the identical message prefix (anti-enumeration), got % vs %', v_forbidden_msg, v_missing_msg;
  end if;

  -- app.record_customer_inventory_access_denial (ATW-023, reused exactly
  -- as-is, item 5 of the prompt) -- the TS service layer's own follow-up
  -- call, durably records both denials without leaking which cause applied.
  --
  -- Tier C fix (cross-prompt-integration/correctness-concurrency/security-rls
  -- Finding 1, batch review of CPL-305..309): this precondition query MUST be
  -- scoped by tenant_id (and, matching the very next query 3 lines below,
  -- resource_type) -- v_fake_id ('99999999-9999-9999-9999-999999999999') is
  -- the SAME hardcoded "genuinely nonexistent balance id" literal scripts/
  -- db-tests/advanced-tms-customer-inventory-access.sql (ATW-023's own
  -- sibling test, which sorts alphabetically BEFORE this file and runs
  -- earlier against the SAME shared disposable database) already uses for
  -- its own identical assertion, and that earlier file's own final block
  -- durably commits a real app.audit_logs row for that exact resource_id
  -- under ATW-023's OWN tenant before this file ever runs. An unscoped count
  -- here therefore counts a different tenant's leftover fixture row and
  -- fails deterministically on every full `pnpm run db:test` run, not a
  -- flake -- live-reproduced by three of the four Tier C review lenses.
  -- Scoping by this fixture's own tenant_id (cwi1) makes the assertion mean
  -- what it says: zero rows for THIS test's own actor/tenant/resource, never
  -- a claim about the entire, shared, cross-file app.audit_logs table.
  select count(*) into v_audit_count from app.audit_logs where action = 'customer_inventory_access_denied' and tenant_id = v_tenant1 and resource_type = 'inventory_balance' and resource_id in (v_beta_balance_id, v_fake_id);
  if v_audit_count <> 0 then
    raise exception 'assertion failed: expected ZERO customer_inventory_access_denied audit rows before app.record_customer_inventory_access_denial is ever called, got %', v_audit_count;
  end if;
  perform app.record_customer_inventory_access_denial(v_tenant1, v_customer_multi, 'inventory_balance', v_beta_balance_id, 'customer-multi');
  perform app.record_customer_inventory_access_denial(v_tenant1, v_customer_multi, 'inventory_balance', v_fake_id, 'customer-multi');
  -- Tier C fix (same root cause as the precondition query above): scoped by
  -- tenant_id too -- v_fake_id is the SAME shared literal ATW-023's own
  -- sibling test (scripts/db-tests/advanced-tms-customer-inventory-access.sql)
  -- also records a denial against, under its OWN tenant. Without the
  -- tenant_id scope this count would silently include that unrelated row
  -- too (3, not 2) whenever both files run against the same shared database,
  -- which is exactly how `pnpm run db:test` always runs them.
  select count(*) into v_audit_count from app.audit_logs where action = 'customer_inventory_access_denied' and tenant_id = v_tenant1 and resource_type = 'inventory_balance' and resource_id in (v_beta_balance_id, v_fake_id);
  if v_audit_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 durable customer_inventory_access_denied audit rows after 2 real calls to app.record_customer_inventory_access_denial, got %', v_audit_count;
  end if;
end $$;

\echo '>> app.list_customer_portal_inventory_balances: owner+eligibility scoped, excludes all-zero rows, cursor pagination advances and terminates (item f), forged warehouse id yields zero rows not an error'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000317011';
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Beta');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWI-1');
  v_fake_wh uuid := '88888888-8888-8888-8888-888888888888';
  v_count integer;
  v_row record;
  v_seen_ids uuid[] := array[]::uuid[];
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page_count integer;
  v_total_pages integer := 0;
begin
  -- Owner scope: customer-multi never sees Beta's rows anywhere.
  select count(*) into v_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, null, null, null, null, 200) v where v.owner_account_id = v_account_beta;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero of Beta''s balances in customer-multi''s own list, got %', v_count;
  end if;

  -- Alpha sees exactly 3 non-zero balances in WH-CWI-1 (the zeroed-out 4th
  -- dimension is excluded).
  select count(*) into v_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, v_wh1, null, null, null, 200);
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 non-zero balances for customer-multi in WH-CWI-1 (the zeroed-out dimension must be excluded), got %', v_count;
  end if;

  -- Forged/foreign warehouse id -- zero rows, never an error.
  select count(*) into v_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, v_fake_wh, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a forged warehouse id, got %', v_count;
  end if;

  -- Cursor pagination: p_limit=1 across the 3 WH-CWI-1 rows must yield 3
  -- distinct pages that together cover all 3 rows exactly once, then
  -- terminate (4th page empty).
  loop
    v_page_count := 0;
    for v_row in
      select * from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, v_wh1, null, v_cursor_updated_at, v_cursor_id, 1)
    loop
      v_page_count := v_page_count + 1;
      if v_row.id = any(v_seen_ids) then
        raise exception 'assertion failed: cursor pagination returned a duplicate row %, seen so far %', v_row.id, v_seen_ids;
      end if;
      v_seen_ids := v_seen_ids || v_row.id;
      v_cursor_updated_at := v_row.updated_at;
      v_cursor_id := v_row.id;
    end loop;
    exit when v_page_count = 0;
    v_total_pages := v_total_pages + 1;
    if v_total_pages > 10 then
      raise exception 'assertion failed: cursor pagination did not terminate within 10 pages -- possible infinite loop';
    end if;
  end loop;

  if v_total_pages <> 3 then
    raise exception 'assertion failed: expected exactly 3 pages of 1 row each, got % pages', v_total_pages;
  end if;
  if array_length(v_seen_ids, 1) <> 3 then
    raise exception 'assertion failed: expected exactly 3 distinct rows seen across all pages, got %', array_length(v_seen_ids, 1);
  end if;

  -- Half-supplied cursor fails loud (mirrors ATW-023's own identical validation).
  begin
    perform app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, null, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_updated_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> THE KEY REGRESSION TEST (item d): customer-multi''s Gamma access comes ONLY from CPL-300''s new app.customer_portal_account_memberships table -- proven by direct query, and by the SAME identity calling ATW-023''s OLD app.list_customer_inventory_balances/app.list_customer_warehouse_eligibility (unmodified, still gated by app.resolve_customer_owner_account_scope) and seeing NOTHING for Gamma, side-by-side with this migration''s NEW RPCs seeing it correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000317011';
  v_account_gamma uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Gamma');
  v_wh_gamma uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWI-GAMMA');
  v_legacy_row_count integer;
  v_new_row_count integer;
  v_old_balance_count integer;
  v_new_balance_count integer;
  v_old_eligibility_count integer;
  v_new_eligibility_count integer;
begin
  -- Structural precondition: confirm the fixture itself is shaped as claimed --
  -- zero legacy app.principal_memberships row for (customer-multi, Gamma), and
  -- exactly one ACTIVE row in the new grant table for the same pair.
  select count(*) into v_legacy_row_count
  from app.principal_memberships
  where auth_user_id = v_customer_multi and tenant_id = v_tenant1 and layer = 'customer_user' and customer_account_ref = v_account_gamma::text;
  if v_legacy_row_count <> 0 then
    raise exception 'assertion failed: fixture precondition violated -- expected ZERO legacy app.principal_memberships row for customer-multi/Gamma, got %', v_legacy_row_count;
  end if;

  select count(*) into v_new_row_count
  from app.customer_portal_account_memberships
  where auth_user_id = v_customer_multi and tenant_id = v_tenant1 and account_id = v_account_gamma and status = 'active';
  if v_new_row_count <> 1 then
    raise exception 'assertion failed: fixture precondition violated -- expected exactly 1 ACTIVE app.customer_portal_account_memberships row for customer-multi/Gamma, got %', v_new_row_count;
  end if;

  -- OLD (ATW-023, unmodified, still applied and VERIFIED): gated by
  -- app.resolve_customer_owner_account_scope, which reads ONLY the legacy
  -- marker -- must see ZERO of Gamma's rows for customer-multi.
  select count(*) into v_old_balance_count from app.list_customer_inventory_balances(v_tenant1, v_customer_multi, v_wh_gamma, null, null, null, 200) v where v.owner_account_id = v_account_gamma;
  if v_old_balance_count <> 0 then
    raise exception 'assertion failed: expected ATW-023''s OLD app.list_customer_inventory_balances to see ZERO of Gamma''s balances for customer-multi (Gamma is only in the NEW grant table) -- if this is nonzero, the fixture or the old RPC''s own behavior has changed unexpectedly, got %', v_old_balance_count;
  end if;

  select count(*) into v_old_eligibility_count from app.list_customer_warehouse_eligibility(v_tenant1, v_customer_multi) v where v.customer_account_id = v_account_gamma;
  if v_old_eligibility_count <> 0 then
    raise exception 'assertion failed: expected ATW-023''s OLD app.list_customer_warehouse_eligibility to see ZERO of Gamma''s eligibility grants for customer-multi, got %', v_old_eligibility_count;
  end if;

  -- NEW (this migration, CPL-309): gated by app.resolve_customer_account_scope,
  -- the CPL-300 widened resolver -- MUST see Gamma's balance and eligibility
  -- grant. This is the live proof the scope gap is actually closed.
  select count(*) into v_new_balance_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, v_wh_gamma, null, null, null, 200) v where v.owner_account_id = v_account_gamma;
  if v_new_balance_count <> 1 then
    raise exception 'assertion failed: expected this migration''s NEW app.list_customer_portal_inventory_balances to see EXACTLY 1 of Gamma''s balances for customer-multi (ISS-2026-117 fix), got %', v_new_balance_count;
  end if;

  select count(*) into v_new_eligibility_count from app.list_customer_portal_warehouse_eligibility(v_tenant1, v_customer_multi) v where v.customer_account_id = v_account_gamma;
  if v_new_eligibility_count <> 1 then
    raise exception 'assertion failed: expected this migration''s NEW app.list_customer_portal_warehouse_eligibility to see EXACTLY 1 of Gamma''s eligibility grants for customer-multi, got %', v_new_eligibility_count;
  end if;

  raise notice 'KEY REGRESSION TEST PASSED: customer-multi''s Gamma access exists ONLY in the new grant table (0 legacy rows, 1 new-table row); ATW-023''s OLD RPCs see 0 Gamma rows; this migration''s NEW RPCs see exactly 1 -- the ISS-2026-117 scope gap is live-proven closed, not merely structurally plausible';
end $$;

\echo '>> item (c): a legacy single-account customer_account_ref actor (customer-legacy, ZERO rows in the new grant table) still resolves correctly through the new resolver -- regression against ATW-023''s existing behavior'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_customer_legacy uuid := '00000000-0000-0000-0000-000000317010';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Alpha');
  v_new_row_count integer;
  v_count integer;
begin
  select count(*) into v_new_row_count from app.customer_portal_account_memberships where auth_user_id = v_customer_legacy;
  if v_new_row_count <> 0 then
    raise exception 'assertion failed: fixture precondition violated -- customer-legacy must hold ZERO rows in the new grant table, got %', v_new_row_count;
  end if;

  select count(*) into v_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_legacy, null, null, null, null, 200) v where v.owner_account_id = v_account_alpha;
  if v_count = 0 then
    raise exception 'assertion failed: expected customer-legacy (legacy marker only) to still see their own Alpha balances through the new RPC';
  end if;

  select count(*) into v_count from app.list_customer_portal_warehouse_eligibility(v_tenant1, v_customer_legacy) v where v.customer_account_id = v_account_alpha;
  if v_count = 0 then
    raise exception 'assertion failed: expected customer-legacy (legacy marker only) to still see their own Alpha warehouse eligibility grants through the new RPC';
  end if;
end $$;

\echo '>> item (a): cross-customer and cross-tenant isolation -- an out-of-scope, cross-tenant, and fabricated owner id are all indistinguishable (zero rows, no error); customer-badref (non-uuid legacy ref) resolves to an empty scope'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cwi2');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000317011';
  v_customer_t2 uuid := '00000000-0000-0000-0000-000000318010';
  v_customer_badref uuid := '00000000-0000-0000-0000-000000317030';
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Beta');
  v_account_delta uuid := (select id from app.accounts where tenant_id = v_tenant2 and legal_name = 'Cwi Account Delta');
  v_fake_owner uuid := '66666666-6666-6666-6666-666666666666';
  v_count_beta integer;
  v_count_delta integer;
  v_count_fake integer;
  v_count integer;
begin
  select count(*) into v_count_beta from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, null, null, null, null, 200) v where v.owner_account_id = v_account_beta;
  select count(*) into v_count_delta from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, null, null, null, null, 200) v where v.owner_account_id = v_account_delta;
  select count(*) into v_count_fake from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, null, null, null, null, 200) v where v.owner_account_id = v_fake_owner;
  if v_count_beta <> 0 or v_count_delta <> 0 or v_count_fake <> 0 then
    raise exception 'assertion failed: expected identical zero-row outcomes for an out-of-scope, cross-tenant, and fabricated owner id, got % / % / %', v_count_beta, v_count_delta, v_count_fake;
  end if;

  -- Cross-tenant identity, real membership, unrelated tenant: customer-t2
  -- (a genuine tenant2 customer_user) has no membership in tenant1 at all --
  -- passing tenant1's own id must still yield zero rows, not another
  -- tenant's data.
  select count(*) into v_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_t2, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a genuinely cross-tenant identity probing tenant1 with tenant1''s own id, got %', v_count;
  end if;

  -- customer-badref: non-uuid-shaped legacy ref, zero rows in the new table
  -- either -- must resolve to an empty scope, never an error.
  select count(*) into v_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_badref, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for the empty-scope (non-uuid customer_account_ref) actor, got %', v_count;
  end if;
end $$;

\echo '>> item (b): revocation takes immediate effect -- the very next get/list call for the revoked warehouse excludes/denies, a live query, never cached'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000317011';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwi Account Alpha');
  v_wh_revoke uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWI-REVOKE');
  v_supreme uuid := '00000000-0000-0000-0000-000000317001';
  v_eligibility_id uuid;
  v_eligibility_version integer;
  v_balance_id uuid := (select id from app.inventory_balances where tenant_id = v_tenant1 and warehouse_id = v_wh_revoke and owner_account_id = v_account_alpha);
  v_count integer;
  v_row record;
begin
  -- Before revoke: customer-multi can see it (Alpha's own legacy-marker scope).
  select * into v_row from app.get_customer_portal_inventory_balance(v_tenant1, v_customer_multi, v_balance_id);
  if v_row.id <> v_balance_id then
    raise exception 'assertion failed: expected customer-multi to see the WH-CWI-REVOKE balance BEFORE revocation';
  end if;

  select id, record_version into v_eligibility_id, v_eligibility_version from app.warehouse_customer_eligibility
    where tenant_id = v_tenant1 and warehouse_id = v_wh_revoke and customer_account_id = v_account_alpha;
  perform app.revoke_warehouse_customer_eligibility(v_eligibility_id, 'cwi revocation-immediate-effect test', v_eligibility_version, v_supreme, 'admin');

  -- Immediately after: the new RPC layer excludes/denies -- no cache, no
  -- delay, a live query against the current row every time.
  begin
    perform app.get_customer_portal_inventory_balance(v_tenant1, v_customer_multi, v_balance_id);
    raise exception 'assertion failed: expected record_not_found -- revocation must take immediate effect';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  select count(*) into v_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, v_wh_revoke, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero WH-CWI-REVOKE balances immediately after revocation, got %', v_count;
  end if;

  -- The revoked grant itself is still visible via app.list_customer_portal_
  -- warehouse_eligibility (status=revoked, with its own revoked_reason) --
  -- "so they can see why a warehouse disappeared."
  select * into v_row from app.list_customer_portal_warehouse_eligibility(v_tenant1, v_customer_multi) v where v.id = v_eligibility_id;
  if v_row.status <> 'revoked' or v_row.revoked_reason <> 'cwi revocation-immediate-effect test' then
    raise exception 'assertion failed: expected the revoked grant to still be listed with status=revoked and its own real revoked_reason, got %', v_row;
  end if;
end $$;

\echo '>> app.list_customer_portal_warehouse_eligibility: no OPS RBAC gate at all -- customer-multi holds zero OPS/COM/FIN role anywhere, yet this succeeds; shows active AND revoked grants across BOTH legacy-marker and new-grant-table scope'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000317011';
  v_count integer;
begin
  -- customer-multi: Alpha (legacy, eligible for WH-CWI-1 active + WH-CWI-REVOKE
  -- revoked) + Gamma (new table, eligible for WH-CWI-GAMMA active) = 3 rows.
  select count(*) into v_count from app.list_customer_portal_warehouse_eligibility(v_tenant1, v_customer_multi);
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 of customer-multi''s own eligibility grants (WH-CWI-1 active, WH-CWI-REVOKE revoked, WH-CWI-GAMMA active), got %', v_count;
  end if;
end $$;

\echo '>> raw-table RLS defense-in-depth: app.inventory_balances/app.warehouse_customer_eligibility are UNTOUCHED by this migration. authenticated DOES hold a table-level SELECT grant on both (20260730190000/20260730140000) -- so a raw read is not blocked at the grant level, but their own pre-existing RLS SELECT policy passes NULL as the owner-scope argument (no owner-scope branch at all -- confirmed by direct read of both policies before this migration was written), so a customer_user actor (no org_unit_id) is silently filtered to ZERO rows by RLS, never a permission-denied error and never another owner''s row'
do $$
declare
  v_raw_balance_count integer;
  v_raw_eligibility_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000317011", "role": "authenticated"}';

  select count(*) into v_raw_balance_count from app.inventory_balances;
  if v_raw_balance_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.inventory_balances to be RLS-filtered to ZERO rows for a customer_user actor, got %', v_raw_balance_count;
  end if;

  select count(*) into v_raw_eligibility_count from app.warehouse_customer_eligibility;
  if v_raw_eligibility_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.warehouse_customer_eligibility to be RLS-filtered to ZERO rows for a customer_user actor, got %', v_raw_eligibility_count;
  end if;

  reset role;
end $$;

\echo '>> raw-function grant defense in depth: anon holds no EXECUTE on any new function; authenticated/service_role both do'
do $$
declare
  v_fn text;
  v_has_priv boolean;
begin
  foreach v_fn in array array[
    'app.evaluate_customer_portal_inventory_access(uuid, uuid, uuid, uuid)',
    'app.get_customer_portal_inventory_balance(uuid, uuid, uuid)',
    'app.list_customer_portal_inventory_balances(uuid, uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.list_customer_portal_warehouse_eligibility(uuid, uuid)'
  ] loop
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
end $$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity, on every new RPC (ATW-031/032 discipline, applied here from the first draft)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000317011';
  v_impersonator uuid := '00000000-0000-0000-0000-000000317050';
  v_balance_id uuid := (select b.id from app.inventory_balances b join app.accounts a on a.id = b.owner_account_id where a.legal_name = 'Cwi Account Alpha' and b.on_hand = 10);
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000317050", "role": "authenticated"}';

  begin
    perform app.get_customer_portal_inventory_balance(v_tenant1, v_customer_multi, v_balance_id);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_portal_inventory_balance -- the impersonator session may not claim to act as customer-multi';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_inventory_balances';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_warehouse_eligibility(v_tenant1, v_customer_multi);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_warehouse_eligibility';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (no relationship to
  -- customer-multi's own accounts) is not rejected by the identity check --
  -- it is correctly denied by the SCOPE check instead (zero rows/record_not_found),
  -- proving the identity check and the scope check are two independent gates.
  begin
    perform app.get_customer_portal_inventory_balance(v_tenant1, v_impersonator, v_balance_id);
    raise exception 'assertion failed: expected record_not_found -- the impersonator, acting as themselves, has no scope over Alpha''s balance';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  reset role;
end $$;

\echo '>> a real, live authenticated-role positive path: customer-multi''s own real authenticated session sees the exact same result a direct superuser call returns, for BOTH legacy-marker (Alpha) and new-grant-table-only (Gamma) scope'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwi1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000317011';
  v_superuser_count integer;
  v_session_count integer;
begin
  select count(*) into v_superuser_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, null, null, null, null, 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000317011", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_inventory_balances(v_tenant1, v_customer_multi, null, null, null, null, 200);
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero row count (% ) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
end $$;
