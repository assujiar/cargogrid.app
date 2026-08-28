-- Real, executable test evidence for ATW-023 (CG-S10-ATW-023, Prompt 242 Customer
-- Inventory Access Contract) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Structural convention mirrors scripts/db-tests/advanced-tms-
-- warehouse-billing-events.sql.
--
-- Setup convenience note: every staff-side fixture action below (warehouse/item/lot/
-- serial/order/movement creation) is performed by a single Supreme Admin actor rather
-- than a purpose-built OPS role -- this migration's own new contract has NO staff RBAC
-- dependency at all (that is the entire point being tested), so the staff-side setup
-- plumbing is deliberately not the focus here, unlike ATW-016/ATW-022's own fixtures.

\set ON_ERROR_STOP on

\echo '>> setup: tenant cia1 with two owner accounts (Alpha, Beta), four warehouses (WH-CIA-1 Alpha-only, WH-CIA-2 Beta-only, WH-CIA-SHARED both, WH-CIA-REVOKE Alpha-only-later-revoked), three customer_user actors (customer-alpha, customer-beta, customer-badref with a non-uuid-shaped customer_account_ref), items/lots/serials/balances/outbound orders/movements for each owner; a second isolated tenant cia2 (owner Gamma, warehouse WH-CIA-T2, customer-gamma) for cross-tenant checks'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_wh1 app.warehouses;
  v_wh2 app.warehouses;
  v_wh_shared app.warehouses;
  v_wh_revoke app.warehouses;
  v_wh_t2 app.warehouses;
  v_rack1 app.warehouse_locations;
  v_rack2 app.warehouse_locations;
  v_rack_shared app.warehouse_locations;
  v_rack_revoke app.warehouse_locations;
  v_rack_t2 app.warehouse_locations;
  v_account_alpha app.accounts;
  v_account_beta app.accounts;
  v_account_gamma app.accounts;
  v_item_alpha uuid;
  v_item_beta uuid;
  v_item_gamma uuid;
  v_order app.wms_outbound_orders;
  v_supreme uuid := '00000000-0000-0000-0000-000000230001';
begin
  insert into auth.users (id, email) values
    (v_supreme, 'admin@cia1.test'),
    ('00000000-0000-0000-0000-000000230002', 'customer-alpha@cia1.test'),
    ('00000000-0000-0000-0000-000000230003', 'customer-beta@cia1.test'),
    ('00000000-0000-0000-0000-000000230004', 'customer-badref@cia1.test'),
    ('00000000-0000-0000-0000-000000230005', 'customer-gamma@cia2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cia1', 'Customer Inventory Access Tenant One', 'idem-cia1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cia1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CIA1-CO', 'Cia1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CIA1-CO');

  perform app.provision_tenant('cia2', 'Customer Inventory Access Tenant Two', 'idem-cia2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cia2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CIA2-CO', 'Cia2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CIA2-CO');

  -- Direct fixture inserts (bypasses the full lead->prospect->quotation->convert
  -- Commercial pipeline, out of scope for this capability's own test -- mirrors
  -- scripts/db-tests/finance-accounts-receivable.sql's own established convention).
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cia Customer Alpha', 'cia-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning * into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cia Customer Beta', 'cia-beta-fp', '{}'::jsonb, v_company1, 'tester') returning * into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cia Customer Gamma', 'cia-gamma-fp', '{}'::jsonb, v_company2, 'tester') returning * into v_account_gamma;

  -- customer_user actors -- invited with a NULL org_unit_id (app.invite_user allows
  -- this, mirrors ATW-016's own "outsider" fixture convention): the ONLY path any of
  -- them can ever pass this migration's own gate is the real customer_account_ref
  -- match + an active warehouse eligibility grant, never incidental org-unit sharing
  -- or any OPS role (none is ever assigned to any of these four actors).
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000230002', 'customer-alpha@cia1.test', 'Cia Customer Alpha Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@cia1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000230002', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000230003', 'customer-beta@cia1.test', 'Cia Customer Beta Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@cia1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000230003', 'customer_user', v_tenant1, v_account_beta.id::text, 'tester');

  -- A customer_user membership whose own customer_account_ref is NOT uuid-shaped (a
  -- legacy free-text label, e.g. surviving from an unrelated capability) -- must
  -- resolve to an EMPTY scope, never an error and never another owner's data.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000230004', 'customer-badref@cia1.test', 'Cia Customer Badref Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-badref@cia1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000230004', 'customer_user', v_tenant1, 'LEGACY-CUST-0007', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000230005', 'customer-gamma@cia2.test', 'Cia Customer Gamma Portal', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-gamma@cia2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000230005', 'customer_user', v_tenant2, v_account_gamma.id::text, 'tester');

  -- Four warehouses in tenant1 (shared and different -- Prompt 242 §27).
  v_wh1 := app.create_warehouse(v_tenant1, v_company1, 'WH-CIA-1', 'Cia Warehouse 1 (Alpha only)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh2 := app.create_warehouse(v_tenant1, v_company1, 'WH-CIA-2', 'Cia Warehouse 2 (Beta only)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh_shared := app.create_warehouse(v_tenant1, v_company1, 'WH-CIA-SHARED', 'Cia Warehouse Shared (Alpha+Beta)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh_revoke := app.create_warehouse(v_tenant1, v_company1, 'WH-CIA-REVOKE', 'Cia Warehouse Revoke (Alpha, later revoked)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh_t2 := app.create_warehouse(v_tenant2, v_company2, 'WH-CIA-T2', 'Cia Tenant2 Warehouse', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');

  v_rack1 := app.create_warehouse_location(v_wh1.id, null, null, 'RACK-CIA-1A', 'Rack 1A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack1.id, 'active', null, v_rack1.record_version, v_supreme, 'admin');
  v_rack2 := app.create_warehouse_location(v_wh2.id, null, null, 'RACK-CIA-2A', 'Rack 2A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack2.id, 'active', null, v_rack2.record_version, v_supreme, 'admin');
  v_rack_shared := app.create_warehouse_location(v_wh_shared.id, null, null, 'RACK-CIA-SA', 'Rack Shared A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack_shared.id, 'active', null, v_rack_shared.record_version, v_supreme, 'admin');
  v_rack_revoke := app.create_warehouse_location(v_wh_revoke.id, null, null, 'RACK-CIA-RA', 'Rack Revoke A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack_revoke.id, 'active', null, v_rack_revoke.record_version, v_supreme, 'admin');
  v_rack_t2 := app.create_warehouse_location(v_wh_t2.id, null, null, 'RACK-CIA-T2A', 'Rack T2 A', 'rack', 1, null, null, null, null, null, true, true, v_supreme, 'admin');
  perform app.set_warehouse_location_status(v_rack_t2.id, 'active', null, v_rack_t2.record_version, v_supreme, 'admin');

  -- Eligibility grants (active/revoked -- app.warehouse_customer_eligibility's own
  -- status CHECK only supports these two states; there is no distinct "expired"
  -- status on this already-applied table, so this fixture covers active/revoked, the
  -- full set that actually exists).
  perform app.grant_warehouse_customer_eligibility(v_wh1.id, v_account_alpha.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh2.id, v_account_beta.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_shared.id, v_account_alpha.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_shared.id, v_account_beta.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_revoke.id, v_account_alpha.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_t2.id, v_account_gamma.id, v_supreme, 'admin');

  -- Items.
  v_item_alpha := (app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CIA-ALPHA', 'Cia Alpha Widget', null, 'PCS', true, true, true, v_supreme, 'admin')).id;
  v_item_beta := (app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-CIA-BETA', 'Cia Beta Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;
  v_item_gamma := (app.create_item_master(v_tenant2, v_account_gamma.id, 'SKU-CIA-GAMMA', 'Cia Gamma Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;

  -- Lot/serial identities for Alpha's item (lot_controlled/serial_controlled=true).
  perform app.register_lot_identity(v_item_alpha, 'LOT-CIA-A1', current_date - 10, current_date + 300, 'receipt', null, null, v_supreme, 'admin');
  perform app.set_lot_identity_status((select id from app.lot_identities where item_master_id = v_item_alpha and lot_number = 'LOT-CIA-A1'), 'held', 'quality hold pending inspection', 1, v_supreme, 'admin');
  perform app.register_serial_identity(v_item_alpha, 'SN-CIA-A1', null, null, null, 'receipt', null, 'idem-cia-sn-a1', v_supreme, 'admin');

  -- Alpha balances in WH-CIA-1 -- THREE distinct rows (three locations) to prove
  -- cursor pagination actually advances across pages.
  declare
    v_rack1b app.warehouse_locations;
    v_rack1c app.warehouse_locations;
  begin
    v_rack1b := app.create_warehouse_location(v_wh1.id, null, null, 'RACK-CIA-1B', 'Rack 1B', 'rack', 2, null, null, null, null, null, true, true, v_supreme, 'admin');
    perform app.set_warehouse_location_status(v_rack1b.id, 'active', null, v_rack1b.record_version, v_supreme, 'admin');
    v_rack1c := app.create_warehouse_location(v_wh1.id, null, null, 'RACK-CIA-1C', 'Rack 1C', 'rack', 3, null, null, null, null, null, true, true, v_supreme, 'admin');
    perform app.set_warehouse_location_status(v_rack1c.id, 'active', null, v_rack1c.record_version, v_supreme, 'admin');

    perform app.post_inventory_movement(
      v_tenant1, v_wh1.id, 'opening_balance', 'opening_balance', null, 'idem-cia-open-a1-1', 'cia fixture',
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1.id, 'uom_code', 'PCS', 'signed_quantity', 10, 'lot_number', 'LOT-CIA-A1')),
      v_supreme, 'admin'
    );
    perform app.post_inventory_movement(
      v_tenant1, v_wh1.id, 'opening_balance', 'opening_balance', null, 'idem-cia-open-a1-2', 'cia fixture',
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1b.id, 'uom_code', 'PCS', 'signed_quantity', 1, 'serial_number', 'SN-CIA-A1')),
      v_supreme, 'admin'
    );
    perform app.post_inventory_movement(
      v_tenant1, v_wh1.id, 'opening_balance', 'opening_balance', null, 'idem-cia-open-a1-3', 'cia fixture',
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1c.id, 'uom_code', 'PCS', 'signed_quantity', 30)),
      v_supreme, 'admin'
    );

    -- A FOURTH Alpha/WH-CIA-1 dimension that nets to all-zero (receive then fully
    -- consume) -- proves the customer list RPC excludes it exactly as app.list_
    -- inventory_balances (ATW-015) already does for the staff-facing list.
    perform app.post_inventory_movement(
      v_tenant1, v_wh1.id, 'opening_balance', 'opening_balance', null, 'idem-cia-open-a1-zero', 'cia fixture',
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1c.id, 'uom_code', 'PCS', 'signed_quantity', 5, 'status', 'damaged')),
      v_supreme, 'admin'
    );
    perform app.post_inventory_movement(
      v_tenant1, v_wh1.id, 'adjustment', 'manual', null, 'idem-cia-open-a1-zero-out', 'zero out for exclusion test',
      jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack1c.id, 'uom_code', 'PCS', 'signed_quantity', -5, 'status', 'damaged')),
      v_supreme, 'admin'
    );
  end;

  -- Beta balance in WH-CIA-2.
  perform app.post_inventory_movement(
    v_tenant1, v_wh2.id, 'opening_balance', 'opening_balance', null, 'idem-cia-open-b1', 'cia fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta.id, 'item_master_id', v_item_beta, 'location_id', v_rack2.id, 'uom_code', 'PCS', 'signed_quantity', 15)),
    v_supreme, 'admin'
  );

  -- Alpha and Beta balances in WH-CIA-SHARED.
  perform app.post_inventory_movement(
    v_tenant1, v_wh_shared.id, 'opening_balance', 'opening_balance', null, 'idem-cia-open-shared-a', 'cia fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack_shared.id, 'uom_code', 'PCS', 'signed_quantity', 7)),
    v_supreme, 'admin'
  );
  perform app.post_inventory_movement(
    v_tenant1, v_wh_shared.id, 'opening_balance', 'opening_balance', null, 'idem-cia-open-shared-b', 'cia fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_beta.id, 'item_master_id', v_item_beta, 'location_id', v_rack_shared.id, 'uom_code', 'PCS', 'signed_quantity', 9)),
    v_supreme, 'admin'
  );

  -- Alpha balance in WH-CIA-REVOKE -- the revocation-immediate-effect fixture.
  perform app.post_inventory_movement(
    v_tenant1, v_wh_revoke.id, 'opening_balance', 'opening_balance', null, 'idem-cia-open-revoke-a', 'cia fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_alpha.id, 'item_master_id', v_item_alpha, 'location_id', v_rack_revoke.id, 'uom_code', 'PCS', 'signed_quantity', 3)),
    v_supreme, 'admin'
  );

  -- Gamma balance in tenant2's own WH-CIA-T2.
  perform app.post_inventory_movement(
    v_tenant2, v_wh_t2.id, 'opening_balance', 'opening_balance', null, 'idem-cia-open-t2-g', 'cia fixture',
    jsonb_build_array(jsonb_build_object('owner_account_id', v_account_gamma.id, 'item_master_id', v_item_gamma, 'location_id', v_rack_t2.id, 'uom_code', 'PCS', 'signed_quantity', 4)),
    v_supreme, 'admin'
  );

  -- Outbound orders: Alpha in WH-CIA-1 (confirmed, one line), Beta in WH-CIA-2, Alpha
  -- in WH-CIA-REVOKE (for the revocation fixture), Gamma in tenant2.
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_wh1.id, v_account_alpha.id, 'cia alpha order', 'idem-cia-outbound-a1', current_date + 3, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order.id, v_item_alpha, 'PCS', 5, null, v_supreme, 'admin');

  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_wh2.id, v_account_beta.id, 'cia beta order', 'idem-cia-outbound-b1', current_date + 3, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order.id, v_item_beta, 'PCS', 4, null, v_supreme, 'admin');

  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_wh_revoke.id, v_account_alpha.id, 'cia alpha revoke-warehouse order', 'idem-cia-outbound-arevoke', current_date + 3, v_supreme, 'admin');

  v_order := app.create_manual_wms_outbound_order(v_tenant2, v_wh_t2.id, v_account_gamma.id, 'cia gamma order', 'idem-cia-outbound-g1', current_date + 3, v_supreme, 'admin');
end $$;

\echo '>> app.resolve_customer_owner_account_scope / app.evaluate_customer_inventory_access: direct unit coverage'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000230003';
  v_customer_badref uuid := '00000000-0000-0000-0000-000000230004';
  v_supreme uuid := '00000000-0000-0000-0000-000000230001';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Beta');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CIA-1');
  v_wh2 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CIA-2');
  v_wh_shared uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CIA-SHARED');
  v_scope uuid[];
begin
  v_scope := app.resolve_customer_owner_account_scope(v_customer_alpha, v_tenant1);
  if v_scope <> array[v_account_alpha] then
    raise exception 'assertion failed: expected customer-alpha''s scope to be exactly [Alpha], got %', v_scope;
  end if;

  v_scope := app.resolve_customer_owner_account_scope(v_customer_badref, v_tenant1);
  if v_scope is null or array_length(v_scope, 1) is not null then
    raise exception 'assertion failed: expected a non-uuid-shaped customer_account_ref to resolve to a REAL EMPTY array, got %', v_scope;
  end if;

  -- Contrast with ATW-016's own app.resolve_actor_owner_account_scope (which returns
  -- NULL/"unrestricted" for a staff/no-membership actor) -- design decision 2: this
  -- migration's own resolver NEVER returns an unrestricted signal, even for Supreme
  -- Admin (who holds no customer_user membership at all).
  v_scope := app.resolve_customer_owner_account_scope(v_supreme, v_tenant1);
  if v_scope is null or array_length(v_scope, 1) is not null then
    raise exception 'assertion failed: expected Supreme Admin (no customer_user membership) to resolve to a REAL EMPTY array, never NULL/unrestricted, got %', v_scope;
  end if;

  if not app.evaluate_customer_inventory_access(v_customer_alpha, v_tenant1, v_wh1, v_account_alpha) then
    raise exception 'assertion failed: expected customer-alpha to be granted access to their own owner+eligible-warehouse combination';
  end if;
  if app.evaluate_customer_inventory_access(v_customer_alpha, v_tenant1, v_wh2, v_account_alpha) then
    raise exception 'assertion failed: expected customer-alpha to be DENIED for WH-CIA-2 (Alpha has no eligibility grant there)';
  end if;
  if app.evaluate_customer_inventory_access(v_customer_alpha, v_tenant1, v_wh1, v_account_beta) then
    raise exception 'assertion failed: expected customer-alpha to be DENIED for Beta''s own owner_account_id (out of scope)';
  end if;
  if app.evaluate_customer_inventory_access(v_customer_beta, v_tenant1, v_wh1, v_account_beta) then
    raise exception 'assertion failed: expected customer-beta to be DENIED for WH-CIA-1 (Beta has no eligibility grant there, even though owner scope matches)';
  end if;
  if not app.evaluate_customer_inventory_access(v_customer_alpha, v_tenant1, v_wh_shared, v_account_alpha) then
    raise exception 'assertion failed: expected customer-alpha to be granted access in the SHARED warehouse';
  end if;
  if not app.evaluate_customer_inventory_access(v_customer_beta, v_tenant1, v_wh_shared, v_account_beta) then
    raise exception 'assertion failed: expected customer-beta to be granted access in the SHARED warehouse';
  end if;
end $$;

\echo '>> app.get_customer_inventory_balance: own row succeeds; forbidden and genuinely-nonexistent ids raise the IDENTICAL record_not_found shape (anti-enumeration); the RPC itself never self-audits the denial branch (design note 9 -- an audit insert cannot survive the subsequent RAISE within the same transaction); app.record_customer_inventory_access_denial (the separate, follow-up RPC the TS service layer calls in a NEW transaction after catching that error) DOES durably record a denial for either cause, identically, without leaking which cause applied'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Beta');
  v_alpha_balance_id uuid := (select id from app.inventory_balances where tenant_id = v_tenant1 and owner_account_id = v_account_alpha and on_hand = 10);
  v_beta_balance_id uuid := (select id from app.inventory_balances where tenant_id = v_tenant1 and owner_account_id = v_account_beta and on_hand = 15);
  v_fake_id uuid := '99999999-9999-9999-9999-999999999999';
  v_forbidden_msg text;
  v_missing_msg text;
  v_audit_count integer;
  v_row record;
begin
  select * into v_row from app.get_customer_inventory_balance(v_tenant1, v_customer_alpha, v_alpha_balance_id);
  if v_row.id <> v_alpha_balance_id or v_row.on_hand <> 10 then
    raise exception 'assertion failed: expected customer-alpha to read their own permitted balance, got %', v_row;
  end if;

  begin
    perform app.get_customer_inventory_balance(v_tenant1, v_customer_alpha, v_beta_balance_id);
    raise exception 'assertion failed: expected record_not_found -- customer-alpha must not read Beta''s balance';
  exception
    when others then
      v_forbidden_msg := sqlerrm;
      if v_forbidden_msg not like 'record_not_found%' then raise; end if;
  end;

  begin
    perform app.get_customer_inventory_balance(v_tenant1, v_customer_alpha, v_fake_id);
    raise exception 'assertion failed: expected record_not_found -- a genuinely nonexistent id';
  exception
    when others then
      v_missing_msg := sqlerrm;
      if v_missing_msg not like 'record_not_found%' then raise; end if;
  end;

  if left(v_forbidden_msg, 16) <> left(v_missing_msg, 16) then
    raise exception 'assertion failed: expected the forbidden-but-existing and genuinely-nonexistent errors to share the identical message prefix (anti-enumeration), got % vs %', v_forbidden_msg, v_missing_msg;
  end if;

  -- The get RPC itself never self-audits (design note 9) -- confirmed zero rows
  -- exist yet from the two denials above, neither of which called the separate
  -- follow-up audit RPC.
  select count(*) into v_audit_count from app.audit_logs where action = 'customer_inventory_access_denied';
  if v_audit_count <> 0 then
    raise exception 'assertion failed: expected ZERO customer_inventory_access_denied audit rows before app.record_customer_inventory_access_denial is ever called (design note 9 -- the get RPC itself cannot durably self-audit), got %', v_audit_count;
  end if;

  -- app.record_customer_inventory_access_denial: the TS service layer's own
  -- follow-up call (design note 9 resolution, Prompt 242 section 18). Durable,
  -- succeeds identically for both a forbidden-but-existing and a genuinely
  -- nonexistent id, never leaks row content.
  perform app.record_customer_inventory_access_denial(v_tenant1, v_customer_alpha, 'inventory_balance', v_beta_balance_id, 'customer-alpha');
  perform app.record_customer_inventory_access_denial(v_tenant1, v_customer_alpha, 'inventory_balance', v_fake_id, 'customer-alpha');

  select count(*) into v_audit_count from app.audit_logs where action = 'customer_inventory_access_denied' and resource_type = 'inventory_balance';
  if v_audit_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 durable customer_inventory_access_denied audit rows after 2 real calls to app.record_customer_inventory_access_denial, got %', v_audit_count;
  end if;

  if exists (
    select 1 from app.audit_logs
    where action = 'customer_inventory_access_denied' and resource_type = 'inventory_balance'
      and (result <> 'failure' or resource_id not in (v_beta_balance_id, v_fake_id) or before_value is not null or after_value is not null)
  ) then
    raise exception 'assertion failed: expected every denial audit row to record result=failure (app.audit_logs.result only allows success/failure), the requested resource_id, and never any row payload (before_value/after_value)';
  end if;
end $$;

\echo '>> app.list_customer_inventory_balances: owner+eligibility scoped, excludes all-zero rows, cursor pagination advances and terminates, forged warehouse id yields zero rows not an error'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_customer_badref uuid := '00000000-0000-0000-0000-000000230004';
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Beta');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CIA-1');
  v_fake_wh uuid := '88888888-8888-8888-8888-888888888888';
  v_count integer;
  v_row record;
  v_seen_ids uuid[] := array[]::uuid[];
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page_count integer;
  v_total_pages integer := 0;
begin
  -- Owner scope: customer-alpha never sees Beta's rows anywhere.
  select count(*) into v_count from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, null, null, null, null, 200) v where v.owner_account_id = v_account_beta;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero of Beta''s balances in customer-alpha''s own list, got %', v_count;
  end if;

  -- Alpha sees exactly 4 non-zero balances total: 3 in WH-CIA-1 + 1 in WH-CIA-SHARED
  -- (the zeroed-out 4th WH-CIA-1 dimension and the WH-CIA-REVOKE row are separate
  -- checks below/elsewhere).
  select count(*) into v_count from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, v_wh1, null, null, null, 200);
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 non-zero balances for customer-alpha in WH-CIA-1 (the zeroed-out dimension must be excluded), got %', v_count;
  end if;

  -- Forged/foreign warehouse id -- zero rows, never an error.
  select count(*) into v_count from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, v_fake_wh, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a forged warehouse id, got %', v_count;
  end if;

  -- Empty-scope actor (non-uuid customer_account_ref) -- zero rows, never an error.
  select count(*) into v_count from app.list_customer_inventory_balances(v_tenant1, v_customer_badref, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for the empty-scope (non-uuid customer_account_ref) actor, got %', v_count;
  end if;

  -- Cursor pagination: p_limit=1 across the 3 WH-CIA-1 rows must yield 3 distinct
  -- pages that together cover all 3 rows exactly once, then terminate (4th page empty).
  loop
    v_page_count := 0;
    for v_row in
      select * from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, v_wh1, null, v_cursor_updated_at, v_cursor_id, 1)
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
end $$;

\echo '>> cursor tampering (Prompt 242 section 28, explicitly named): a forged cursor built from ANOTHER customer''s own row values changes only the pagination window, never the scope filter -- cannot be used to skip scoping or leak another owner''s row count/existence'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Beta');
  v_beta_balance app.inventory_balances;
  v_count integer;
  v_row record;
begin
  -- A real Beta-owned balance row's own (updated_at, id) -- customer-alpha could
  -- plausibly observe/guess a syntactically valid uuid+timestamp pair like this one.
  select * into v_beta_balance from app.inventory_balances where tenant_id = v_tenant1 and owner_account_id = v_account_beta and on_hand = 15;

  -- Forged cursor as customer-alpha's OWN cursor for their OWN (Alpha-scoped) list --
  -- the row-comparison predicate is ANDed after the mandatory owner+eligibility scope
  -- filter, so this can only narrow customer-alpha's own already-scoped result set to
  -- "rows older than Beta's row," never substitute for or widen the scope itself.
  select count(*) into v_count from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, null, null, v_beta_balance.updated_at, v_beta_balance.id, 200) v where v.owner_account_id = v_account_beta;
  if v_count <> 0 then
    raise exception 'assertion failed: a forged cursor built from Beta''s own row must never surface Beta''s own rows to customer-alpha, got %', v_count;
  end if;

  -- Passing Beta's own id as p_cursor_id verbatim (attempting to use the RPC itself
  -- as an oracle for "does a balance with this id exist for some other owner") never
  -- errors and never behaves differently from any other syntactically valid forged
  -- cursor -- no exception, no distinguishable timing/shape signal.
  begin
    select * into v_row from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, null, null, v_beta_balance.updated_at, v_beta_balance.id, 1) limit 1;
  exception
    when others then
      raise exception 'assertion failed: a forged cursor must never raise -- it is a pure pagination-window value, not a scope credential, got %', sqlerrm;
  end;

  -- Same proof against the outbound-order list''s own cursor (a second, independently
  -- implemented cursor predicate -- design note 7''s per-RPC decomposition means this
  -- is not automatically covered by the balance list''s own proof above).
  select count(*) into v_count from app.list_customer_outbound_orders(v_tenant1, v_customer_alpha, null, null, now(), (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-cia-outbound-b1'), 200) v where v.owner_account_id = v_account_beta;
  if v_count <> 0 then
    raise exception 'assertion failed: a forged cursor built from Beta''s own outbound order must never surface Beta''s own rows to customer-alpha, got %', v_count;
  end if;
end $$;

\echo '>> aggregate inference (Prompt 242 sections 16/28, explicitly named): a foreign-tenant owner''s id, a genuinely nonexistent id, and a real-but-out-of-scope owner''s id are all indistinguishable -- zero rows, no error, no count/shape difference a caller could use to infer whether a given owner/item/warehouse combination exists at all'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Beta');
  v_account_gamma uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'cia2') and legal_name = 'Cia Customer Gamma');
  v_fake_owner uuid := '66666666-6666-6666-6666-666666666666';
  v_count_beta integer;
  v_count_gamma integer;
  v_count_fake integer;
begin
  -- Filtering customer-alpha's own list by a real, in-tenant but out-of-scope owner
  -- (Beta), a real but cross-tenant owner (Gamma, from cia2), and a wholly fabricated
  -- owner id must all yield the identical zero-row, no-error outcome -- no signal
  -- distinguishes "exists but forbidden" from "exists in another tenant" from
  -- "does not exist anywhere," which is exactly what would let a caller infer real
  -- account/tenant topology purely from this RPC's own response shape.
  select count(*) into v_count_beta from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, null, null, null, null, 200) v where v.owner_account_id = v_account_beta;
  select count(*) into v_count_gamma from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, null, null, null, null, 200) v where v.owner_account_id = v_account_gamma;
  select count(*) into v_count_fake from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, null, null, null, null, 200) v where v.owner_account_id = v_fake_owner;
  if v_count_beta <> 0 or v_count_gamma <> 0 or v_count_fake <> 0 then
    raise exception 'assertion failed: expected identical zero-row outcomes for an out-of-scope, cross-tenant, and fabricated owner id (aggregate-inference resistance), got % / % / %', v_count_beta, v_count_gamma, v_count_fake;
  end if;

  -- The lot-identity list's own p_owner_account_id filter (an explicit narrowing
  -- parameter, design decision 2 above) exhibits the identical non-distinguishing
  -- behavior -- confirms the same guarantee holds on a second, independently
  -- filtered RPC, not just the unfiltered case above.
  select count(*) into v_count_beta from app.list_customer_lot_identities(v_tenant1, v_customer_alpha, null, null, v_account_beta, null, null, null, 200);
  select count(*) into v_count_fake from app.list_customer_lot_identities(v_tenant1, v_customer_alpha, null, null, v_fake_owner, null, null, null, 200);
  if v_count_beta <> 0 or v_count_fake <> 0 then
    raise exception 'assertion failed: expected identical zero-row outcomes filtering by an out-of-scope vs. fabricated owner id on app.list_customer_lot_identities, got % / %', v_count_beta, v_count_fake;
  end if;
end $$;

\echo '>> app.list_customer_lot_identities / app.list_customer_serial_identities: owner+warehouse-eligibility scoped tracked-stock attributes, hold_reason surfaced, empty-scope actor gets zero rows'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_customer_badref uuid := '00000000-0000-0000-0000-000000230004';
  v_item_alpha uuid := (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CIA-ALPHA');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CIA-1');
  v_row record;
  v_count integer;
begin
  select * into v_row from app.list_customer_lot_identities(v_tenant1, v_customer_alpha, v_wh1, v_item_alpha, null, null, null, null, 50) limit 1;
  if v_row.lot_number <> 'LOT-CIA-A1' or v_row.status <> 'held' or v_row.hold_reason is null then
    raise exception 'assertion failed: expected customer-alpha to see their own held lot with a real hold_reason, got %', v_row;
  end if;

  select count(*) into v_count from app.list_customer_serial_identities(v_tenant1, v_customer_alpha, v_wh1, v_item_alpha, null, null, null, null, 50) v where v.serial_number = 'SN-CIA-A1';
  if v_count <> 1 then
    raise exception 'assertion failed: expected customer-alpha to see their own serial SN-CIA-A1, got % rows', v_count;
  end if;

  select count(*) into v_count from app.list_customer_lot_identities(v_tenant1, v_customer_badref, null, null, null, null, null, null, 50);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero lot rows for the empty-scope actor, got %', v_count;
  end if;
end $$;

\echo '>> app.get_customer_outbound_order / app.list_customer_outbound_order_lines / app.list_customer_outbound_orders: owner+eligibility scoped, anti-enumerating, line reuse'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cia2');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_order_alpha_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-cia-outbound-a1');
  v_order_beta_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-cia-outbound-b1');
  v_order_gamma_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant2 and idempotency_key = 'idem-cia-outbound-g1');
  v_fake_id uuid := '77777777-7777-7777-7777-777777777777';
  v_row record;
  v_count integer;
  v_msg1 text;
  v_msg2 text;
begin
  select * into v_row from app.get_customer_outbound_order(v_tenant1, v_customer_alpha, v_order_alpha_id);
  if v_row.id <> v_order_alpha_id or v_row.status <> 'draft' then
    raise exception 'assertion failed: expected customer-alpha to read their own outbound order, got %', v_row;
  end if;

  select count(*) into v_count from app.list_customer_outbound_order_lines(v_order_alpha_id, v_customer_alpha);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 line on customer-alpha''s own order, got %', v_count;
  end if;

  begin
    perform app.get_customer_outbound_order(v_tenant1, v_customer_alpha, v_order_beta_id);
    raise exception 'assertion failed: expected record_not_found -- customer-alpha must not read Beta''s order';
  exception
    when others then
      v_msg1 := sqlerrm;
      if v_msg1 not like 'record_not_found%' then raise; end if;
  end;
  begin
    perform app.get_customer_outbound_order(v_tenant1, v_customer_alpha, v_fake_id);
    raise exception 'assertion failed: expected record_not_found -- genuinely nonexistent order';
  exception
    when others then
      v_msg2 := sqlerrm;
      if v_msg2 not like 'record_not_found%' then raise; end if;
  end;
  if left(v_msg1, 16) <> left(v_msg2, 16) then
    raise exception 'assertion failed: expected identical anti-enumeration message prefixes, got % vs %', v_msg1, v_msg2;
  end if;

  -- list_customer_outbound_order_lines on a forbidden order raises the same shape.
  begin
    perform app.list_customer_outbound_order_lines(v_order_beta_id, v_customer_alpha);
    raise exception 'assertion failed: expected record_not_found from list_customer_outbound_order_lines on Beta''s own order';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  -- Cross-tenant: customer-alpha (a real, active tenant1 customer_user) has no
  -- membership in tenant2 at all -- Gamma's own order is unreachable, forged tenant
  -- id or not, same anti-enumerating shape.
  begin
    perform app.get_customer_outbound_order(v_tenant2, v_customer_alpha, v_order_gamma_id);
    raise exception 'assertion failed: expected record_not_found -- cross-tenant access must be denied';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  select count(*) into v_count from app.list_customer_outbound_orders(v_tenant1, v_customer_alpha, null, null, null, null, 200) v where v.owner_account_id = (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Beta');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero of Beta''s orders in customer-alpha''s own list, got %', v_count;
  end if;

  -- app.record_customer_inventory_access_denial mirrors the balance RPC's own proof
  -- above for the outbound-order resource type -- durable, identical for both
  -- causes, never leaks row content.
  perform app.record_customer_inventory_access_denial(v_tenant1, v_customer_alpha, 'outbound_order', v_order_beta_id, 'customer-alpha');
  perform app.record_customer_inventory_access_denial(v_tenant1, v_customer_alpha, 'outbound_order', v_fake_id, 'customer-alpha');
  select count(*) into v_count from app.audit_logs where action = 'customer_inventory_access_denied' and resource_type = 'outbound_order';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 durable customer_inventory_access_denied audit rows for outbound_order, got %', v_count;
  end if;
end $$;

\echo '>> app.list_customer_inventory_movement_summary: owner+eligibility scoped movement lineage, no internal source_type/posted_by columns'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Beta');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CIA-1');
  v_count integer;
begin
  select count(*) into v_count from app.list_customer_inventory_movement_summary(v_tenant1, v_customer_alpha, v_wh1, null, null, null, 200) v where v.movement_type = 'opening_balance';
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one opening_balance movement summary row for customer-alpha in WH-CIA-1';
  end if;

  select count(*) into v_count from app.list_customer_inventory_movement_summary(v_tenant1, v_customer_alpha, null, null, null, null, 200) v where v.warehouse_id = (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CIA-2');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows in WH-CIA-2 (owned by Beta, not eligible for customer-alpha), got %', v_count;
  end if;
end $$;

\echo '>> app.export_customer_inventory_snapshot: same scope as the list RPC, bounded at its own cap, audited every call with an accurate result_count and no row payload'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CIA-1');
  v_count integer;
  v_audit_row app.audit_logs;
begin
  -- Bounded export at its own cap: 3 real matching rows in WH-CIA-1, p_limit=2 must
  -- return exactly 2.
  select count(*) into v_count from app.export_customer_inventory_snapshot(v_tenant1, v_customer_alpha, v_wh1, null, 2, 'customer-alpha');
  if v_count <> 2 then
    raise exception 'assertion failed: expected the export to cap at p_limit=2, got % rows', v_count;
  end if;

  select * into v_audit_row from app.audit_logs where action = 'export_customer_inventory_snapshot' order by occurred_at desc limit 1;
  if v_audit_row.result <> 'success' then
    raise exception 'assertion failed: expected the export audit row to record result=success';
  end if;
  if (v_audit_row.after_value->>'result_count')::integer <> 2 then
    raise exception 'assertion failed: expected the export audit row''s own result_count to be 2, got %', v_audit_row.after_value->>'result_count';
  end if;
  if v_audit_row.after_value ? 'on_hand' or v_audit_row.after_value ? 'lot_number' then
    raise exception 'assertion failed: the export audit payload must never carry actual row data';
  end if;

  -- A generous p_limit (above the hard cap of 1000) must not error.
  select count(*) into v_count from app.export_customer_inventory_snapshot(v_tenant1, v_customer_alpha, v_wh1, null, 50000, 'customer-alpha');
  if v_count <> 3 then
    raise exception 'assertion failed: expected all 3 real matching rows when p_limit exceeds available data, got %', v_count;
  end if;
end $$;

\echo '>> app.list_customer_warehouse_eligibility: own grants only (active and revoked), no OPS RBAC gate at all'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Beta');
  v_count integer;
begin
  -- customer-alpha holds zero OPS/COM/FIN permission anywhere -- confirmed no role
  -- was ever assigned to this actor above -- yet this RPC still succeeds.
  select count(*) into v_count from app.list_customer_warehouse_eligibility(v_tenant1, v_customer_alpha);
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 of customer-alpha''s own eligibility grants (WH-CIA-1, WH-CIA-SHARED, WH-CIA-REVOKE), got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_warehouse_eligibility(v_tenant1, v_customer_alpha) v where v.customer_account_id = v_account_beta;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero of Beta''s own eligibility grants visible to customer-alpha, got %', v_count;
  end if;
end $$;

\echo '>> revocation takes immediate effect: the very next get/list call for the revoked warehouse excludes/denies; the raw-RLS path on wms_outbound_orders is denied outright for a customer_user actor (20260730311000 hardening), so it does not surface the row either, before or after revocation'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cia Customer Alpha');
  v_wh_revoke uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CIA-REVOKE');
  v_supreme uuid := '00000000-0000-0000-0000-000000230001';
  v_eligibility_id uuid;
  v_eligibility_version integer;
  v_balance_id uuid := (select id from app.inventory_balances where tenant_id = v_tenant1 and warehouse_id = v_wh_revoke and owner_account_id = v_account_alpha);
  v_order_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-cia-outbound-arevoke');
  v_count integer;
  v_row record;
begin
  -- Before revoke: customer-alpha can see it.
  select * into v_row from app.get_customer_inventory_balance(v_tenant1, v_customer_alpha, v_balance_id);
  if v_row.id <> v_balance_id then
    raise exception 'assertion failed: expected customer-alpha to see the WH-CIA-REVOKE balance BEFORE revocation';
  end if;
  select count(*) into v_count from app.list_customer_outbound_orders(v_tenant1, v_customer_alpha, v_wh_revoke, null, null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected customer-alpha to see the WH-CIA-REVOKE order BEFORE revocation, got %', v_count;
  end if;

  select id, record_version into v_eligibility_id, v_eligibility_version from app.warehouse_customer_eligibility
    where tenant_id = v_tenant1 and warehouse_id = v_wh_revoke and customer_account_id = v_account_alpha;
  perform app.revoke_warehouse_customer_eligibility(v_eligibility_id, 'cia revocation-immediate-effect test', v_eligibility_version, v_supreme, 'admin');

  -- Immediately after: the new RPC layer excludes/denies.
  begin
    perform app.get_customer_inventory_balance(v_tenant1, v_customer_alpha, v_balance_id);
    raise exception 'assertion failed: expected record_not_found -- revocation must take immediate effect on the RPC layer';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;
  select count(*) into v_count from app.list_customer_outbound_orders(v_tenant1, v_customer_alpha, v_wh_revoke, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero WH-CIA-REVOKE orders immediately after revocation, got %', v_count;
  end if;
  select count(*) into v_count from app.list_customer_inventory_balances(v_tenant1, v_customer_alpha, v_wh_revoke, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero WH-CIA-REVOKE balances immediately after revocation, got %', v_count;
  end if;

  -- 20260730311000 hardening proof: a customer_user-layer actor's raw RLS read on
  -- app.wms_outbound_orders is now denied outright (app.actor_holds_customer_user_
  -- layer narrows the policy), regardless of eligibility state -- the RPC layer
  -- above is genuinely the ONLY sanctioned read path, not merely by convention.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000230002", "role": "authenticated"}';
  select count(*) into v_count from app.wms_outbound_orders where id = v_order_id;
  reset role;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the raw-RLS path on app.wms_outbound_orders to deny a customer_user-layer actor entirely (20260730311000 hardening) -- got % rows, meaning the RLS isolation fix regressed', v_count;
  end if;
end $$;

\echo '>> confirm RLS on every table this migration reads directly is now genuinely staff-only for a customer_user actor: app.inventory_balances/app.inventory_movements/app.inventory_movement_lines block outright (no owner-scope branch at all, pre-existing); app.lot_identities/app.serial_identities/app.wms_outbound_orders/app.wms_outbound_order_lines ALSO now block outright, per the 20260730311000 hardening migration that closes design note 6''s own disclosed gap (a live-reproduced adversarial security-review finding against this checkpoint) -- a customer_user actor''s ONLY read path for any of these seven tables is the SECURITY DEFINER RPC layer above. A genuine staff actor (Supreme Admin, not customer_user-layer) is unaffected -- positive control below.'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_supreme uuid := '00000000-0000-0000-0000-000000230001';
  v_order_alpha_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-cia-outbound-a1');
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000230002", "role": "authenticated"}';

  select count(*) into v_count from app.inventory_balances;
  if v_count <> 0 then
    raise exception 'assertion failed: expected app.inventory_balances RLS to fully block a customer_user actor (no owner-scope branch exists in its own SELECT policy) -- got % rows', v_count;
  end if;

  select count(*) into v_count from app.inventory_movements;
  if v_count <> 0 then
    raise exception 'assertion failed: expected app.inventory_movements RLS to fully block a customer_user actor -- got % rows', v_count;
  end if;

  select count(*) into v_count from app.inventory_movement_lines;
  if v_count <> 0 then
    raise exception 'assertion failed: expected app.inventory_movement_lines RLS to fully block a customer_user actor -- got % rows', v_count;
  end if;

  -- 20260730311000 hardening: these four previously-bypassable tables must now be
  -- fully blocked too, for a customer_user actor who legitimately owns matching rows
  -- (customer-alpha holds a real, non-revoked eligibility grant and real Alpha-owned
  -- rows on all four -- if the hardening migration regressed, these would return >0).
  select count(*) into v_count from app.lot_identities;
  if v_count <> 0 then
    raise exception 'assertion failed: expected app.lot_identities raw-RLS read to be fully denied for a customer_user actor (20260730311000 hardening) -- got % rows', v_count;
  end if;

  select count(*) into v_count from app.serial_identities;
  if v_count <> 0 then
    raise exception 'assertion failed: expected app.serial_identities raw-RLS read to be fully denied for a customer_user actor (20260730311000 hardening) -- got % rows', v_count;
  end if;

  select count(*) into v_count from app.wms_outbound_orders;
  if v_count <> 0 then
    raise exception 'assertion failed: expected app.wms_outbound_orders raw-RLS read to be fully denied for a customer_user actor (20260730311000 hardening) -- got % rows', v_count;
  end if;

  select count(*) into v_count from app.wms_outbound_order_lines where outbound_order_id = v_order_alpha_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected app.wms_outbound_order_lines raw-RLS read to be fully denied for a customer_user actor (20260730311000 hardening), even for their own order''s lines -- got % rows', v_count;
  end if;

  reset role;

  -- Positive control: a genuine staff actor (Supreme Admin, never customer_user-
  -- layer) is completely unaffected by the hardening -- the narrowing only ever
  -- removes a customer_user-layer actor's own raw-table access, never anyone else's.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000230001", "role": "authenticated"}';

  select count(*) into v_count from app.wms_outbound_orders where id = v_order_alpha_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected Supreme Admin (staff, not customer_user-layer) to still read app.wms_outbound_orders via raw RLS unaffected by the hardening -- got % rows', v_count;
  end if;

  select count(*) into v_count from app.lot_identities where lot_number = 'LOT-CIA-A1';
  if v_count <> 1 then
    raise exception 'assertion failed: expected Supreme Admin to still read app.lot_identities via raw RLS unaffected by the hardening -- got % rows', v_count;
  end if;

  reset role;
end $$;

\echo '>> full ERR-2026-004 schema-privilege defense-in-depth: anon holds no EXECUTE on any of the 14 new functions; authenticated holds EXECUTE on all 14'
do $$
declare
  v_fn text;
  v_has_priv boolean;
  v_functions text[] := array[
    'app.customer_warehouse_eligibility_active(uuid, uuid, uuid)',
    'app.resolve_customer_owner_account_scope(uuid, uuid)',
    'app.evaluate_customer_inventory_access(uuid, uuid, uuid, uuid)',
    'app.get_customer_inventory_balance(uuid, uuid, uuid)',
    'app.list_customer_inventory_balances(uuid, uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.list_customer_lot_identities(uuid, uuid, uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.list_customer_serial_identities(uuid, uuid, uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.get_customer_outbound_order(uuid, uuid, uuid)',
    'app.list_customer_outbound_order_lines(uuid, uuid)',
    'app.list_customer_outbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.list_customer_inventory_movement_summary(uuid, uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.export_customer_inventory_snapshot(uuid, uuid, uuid, uuid, integer, text)',
    'app.list_customer_warehouse_eligibility(uuid, uuid)',
    'app.record_customer_inventory_access_denial(uuid, uuid, text, uuid, text)'
  ];
begin
  foreach v_fn in array v_functions loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has_priv;
    if v_has_priv then
      raise exception 'assertion failed: anon must NOT hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on % (every function here is customer-portal-reachable)', v_fn;
    end if;
    select has_function_privilege('service_role', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: service_role SHOULD hold EXECUTE on %', v_fn;
    end if;
  end loop;
end $$;

\echo '>> ISS-2026-117 Track B Batch 4 regression: a genuinely different authenticated session (customer-beta, 230003) may not claim to act as customer-alpha (230002) on any of the ten actor-taking RPCs in this migration -- every call now raises actor_identity_mismatch before ever reaching app.resolve_customer_owner_account_scope/app.evaluate_customer_inventory_access, closing the gap this migration file predated (app.assert_actor_is_session_identity, ATW-031, was introduced by a later migration and never retrofitted here until 20260828040000_harden_advanced_tms_customer_inventory_access_actor_identity.sql)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cia1');
  v_alpha uuid := '00000000-0000-0000-0000-000000230002';
  v_impersonator uuid := '00000000-0000-0000-0000-000000230003';
  v_random_id uuid := gen_random_uuid();
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000230003", "role": "authenticated"}';

  begin
    perform app.get_customer_inventory_balance(v_tenant1, v_alpha, v_random_id);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_inventory_balance';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_inventory_balances(v_tenant1, v_alpha, null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_inventory_balances';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_lot_identities(v_tenant1, v_alpha, null, null, null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_lot_identities';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_serial_identities(v_tenant1, v_alpha, null, null, null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_serial_identities';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.get_customer_outbound_order(v_tenant1, v_alpha, v_random_id);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_outbound_order';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_outbound_order_lines(v_random_id, v_alpha);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_outbound_order_lines';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_outbound_orders(v_tenant1, v_alpha, null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_outbound_orders';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_inventory_movement_summary(v_tenant1, v_alpha, null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_inventory_movement_summary';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.export_customer_inventory_snapshot(v_tenant1, v_alpha, null, null, 500, 'forged-label');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.export_customer_inventory_snapshot';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_warehouse_eligibility(v_tenant1, v_alpha);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_warehouse_eligibility';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  reset role;
end $$;
