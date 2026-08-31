-- Real, executable test evidence for CPL-310 (CG-S13-CPL-012, Prompt 310,
-- "Warehouse Order and Order Fulfillment Visibility") -- run via
-- `pnpm run db:test` against a real, disposable Postgres database. Structural
-- convention mirrors scripts/db-tests/customer-warehouse-inventory-
-- visibility.sql (CPL-309) and scripts/db-tests/advanced-tms-customer-
-- inventory-access.sql (ATW-023): a single Supreme Admin actor performs all
-- staff-side setup plumbing (this contract has no staff RBAC dependency at
-- all for the customer-facing RPCs themselves -- that is the entire point
-- being tested; Supreme Admin is only used to CREATE/CONFIRM/CANCEL the
-- orders as staff/WMS setup, never as the customer-facing caller).
--
-- UUID range 00000000-0000-0000-0000-000000319xxx (tenant cwo1) /
-- 00000000-0000-0000-0000-000000321xxx (tenant cwo2), grep-verified unclaimed
-- (320xxx is already claimed by scripts/db-tests/finance-period-lock.sql).
--
-- Covers, live: (a) cross-tenant/cross-account isolation; (b) revoking
-- warehouse eligibility immediately blocks access; (c) a legacy single-
-- account customer_account_ref actor still resolves correctly through the
-- new resolver; (d) THE KEY REGRESSION TEST -- an actor granted a SECOND
-- account ONLY through CPL-300's new app.customer_portal_account_memberships
-- table sees that account's own orders through this migration's new RPCs,
-- side-by-side with the SAME actor calling ATW-023's own app.list_customer_
-- outbound_orders and seeing NOTHING for that account; (e) anti-enumeration
-- -- a forged/foreign order id and a genuinely nonexistent one raise the
-- identical error, on both the get RPC and the line-list RPC (which
-- delegates its own gate to the get RPC); (f) pagination correctness; (g)
-- hidden internal pick/pack worker/productivity/task-queue fields never
-- appear in the customer projection, both structurally (the three new
-- functions' own compiled source never references app.wms_pick_tasks/app.
-- wms_packages/app.wms_outbound_shipments or their own internal columns) and
-- functionally (the actual returned row never carries those keys); (h) a
-- stale/degraded freshness case -- a real, backdated updated_at is surfaced
-- verbatim, never fabricated as "just now"; (i) status-filter correctness
-- (only real database status values, never an invented one); (j) the actor-
-- identity session cross-check on every new RPC; (k) raw-table RLS
-- defense-in-depth (app.wms_outbound_orders/app.wms_outbound_order_lines
-- already denied a customer_user actor outright by the pre-existing
-- 20260730311000 hardening migration, untouched by this one); (l) app.
-- record_customer_inventory_access_denial (ATW-023, reused as-is) durably
-- auditing a denial from this migration's own get RPC, with resource_type =
-- 'outbound_order' (the same literal ATW-023's own sibling db-test already
-- uses for this resource type), scoped by tenant_id from the very first
-- draft (the CPL-309 Tier C lesson, applied here proactively rather than
-- retrofitted after a collision).

\set ON_ERROR_STOP on

\echo '>> setup: tenant cwo1 (accounts Alpha/Beta/Gamma, warehouses WH-CWO-1/2/REVOKE/GAMMA), tenant cwo2 (account Delta, warehouse WH-CWO-T2); customer-legacy (Alpha, legacy marker only), customer-multi (Alpha via legacy marker + Gamma via the NEW CPL-300 grant table ONLY -- the key regression fixture), customer-beta (Beta, legacy only), customer-badref (non-uuid ref), impersonator (zero grants); orders A1 (draft), A2 (confirmed), A3 (cancelled) all in WH-CWO-1 for pagination + status-diversity, B1/AR/G1/T2D isolation and regression fixtures'
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
  v_item_alpha uuid;
  v_item_beta uuid;
  v_item_gamma uuid;
  v_item_delta uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000000319001';
  v_order app.wms_outbound_orders;
  v_inbound app.wms_inbound_orders;
  v_line app.wms_outbound_order_lines;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@cwo.test'),
    ('00000000-0000-0000-0000-000000319010', 'customer-legacy@cwo1.test'),
    ('00000000-0000-0000-0000-000000319011', 'customer-multi@cwo1.test'),
    ('00000000-0000-0000-0000-000000319020', 'customer-beta@cwo1.test'),
    ('00000000-0000-0000-0000-000000319030', 'customer-badref@cwo1.test'),
    ('00000000-0000-0000-0000-000000319050', 'impersonator@cwo1.test'),
    ('00000000-0000-0000-0000-000000321010', 'customer-t2@cwo2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cwo1', 'Customer Warehouse Order Visibility Tenant One', 'idem-cwo1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cwo1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CWO1-CO', 'Cwo1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CWO1-CO');

  perform app.provision_tenant('cwo2', 'Customer Warehouse Order Visibility Tenant Two', 'idem-cwo2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cwo2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CWO2-CO', 'Cwo2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CWO2-CO');

  -- Direct fixture inserts (bypasses the full lead->prospect->quotation->convert
  -- Commercial pipeline, out of scope for this capability's own test -- mirrors
  -- customer-warehouse-inventory-visibility.sql's own established convention).
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cwo Account Alpha', 'cwo-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning * into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cwo Account Beta', 'cwo-beta-fp', '{}'::jsonb, v_company1, 'tester') returning * into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cwo Account Gamma', 'cwo-gamma-fp', '{}'::jsonb, v_company1, 'tester') returning * into v_account_gamma;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cwo Account Delta', 'cwo-delta-fp', '{}'::jsonb, v_company2, 'tester') returning * into v_account_delta;

  -- customer-legacy: Alpha via the LEGACY app.principal_memberships.
  -- customer_account_ref marker ONLY.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000319010', 'customer-legacy@cwo1.test', 'Cwo Customer Legacy', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-legacy@cwo1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000319010', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');

  -- customer-multi: Alpha via the SAME legacy marker AS ABOVE, PLUS Gamma via
  -- a DIRECT insert into the NEW app.customer_portal_account_memberships
  -- table ONLY -- never a legacy app.principal_memberships row for Gamma.
  -- Mirrors customer-warehouse-inventory-visibility.sql's own established
  -- "direct fixture insert, bypasses the full pipeline" convention for
  -- setup plumbing that does not need to re-prove an already-VERIFIED RPC's
  -- own behavior (neither of CPL-300's own shipped write RPCs can produce a
  -- genuinely new-grant-table-only membership -- both also grant the legacy
  -- marker for the same account, as that migration's own CPL-309 sibling
  -- discovered and documented).
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000319011', 'customer-multi@cwo1.test', 'Cwo Customer Multi', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-multi@cwo1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000319011', 'customer_user', v_tenant1, v_account_alpha.id::text, 'tester');
  insert into app.customer_portal_account_memberships
    (tenant_id, auth_user_id, account_id, role, status, invited_by, invited_at, granted_by, granted_at, accepted_at)
  values
    (v_tenant1, '00000000-0000-0000-0000-000000319011', v_account_gamma.id, 'account_admin', 'active', 'tester', now(), 'tester', now(), now());

  -- customer-beta: Beta via the legacy marker only -- isolation fixture.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000319020', 'customer-beta@cwo1.test', 'Cwo Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@cwo1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000319020', 'customer_user', v_tenant1, v_account_beta.id::text, 'tester');

  -- customer-badref: a non-uuid-shaped legacy customer_account_ref -- must
  -- resolve to an EMPTY scope, never an error.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000319030', 'customer-badref@cwo1.test', 'Cwo Customer Badref', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-badref@cwo1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000319030', 'customer_user', v_tenant1, 'LEGACY-CWO-0007', 'tester');

  -- impersonator: a real, active tenant1 identity with ZERO customer_user
  -- grant of any kind -- used only for the actor-identity session cross-check.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000319050', 'impersonator@cwo1.test', 'Cwo Impersonator', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@cwo1.test'), 'active', 'onboarded', 'tester');

  -- customer-t2: Delta via the legacy marker, in the ISOLATED tenant cwo2.
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000321010', 'customer-t2@cwo2.test', 'Cwo Customer T2', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-t2@cwo2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000321010', 'customer_user', v_tenant2, v_account_delta.id::text, 'tester');

  -- Warehouses in tenant1: WH-CWO-1 (Alpha), WH-CWO-2 (Beta), WH-CWO-REVOKE
  -- (Alpha, revoked mid-test), WH-CWO-GAMMA (Gamma -- key regression
  -- warehouse). One warehouse in tenant2: WH-CWO-T2 (Delta).
  v_wh1 := app.create_warehouse(v_tenant1, v_company1, 'WH-CWO-1', 'Cwo Warehouse 1 (Alpha)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh2 := app.create_warehouse(v_tenant1, v_company1, 'WH-CWO-2', 'Cwo Warehouse 2 (Beta)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh_revoke := app.create_warehouse(v_tenant1, v_company1, 'WH-CWO-REVOKE', 'Cwo Warehouse Revoke (Alpha, later revoked)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh_gamma := app.create_warehouse(v_tenant1, v_company1, 'WH-CWO-GAMMA', 'Cwo Warehouse Gamma (new-grant-table-only)', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');
  v_wh_t2 := app.create_warehouse(v_tenant2, v_company2, 'WH-CWO-T2', 'Cwo Tenant2 Warehouse', null, 'Asia/Jakarta', null, array['land']::text[], v_supreme, 'admin');

  -- Warehouse eligibility grants -- Alpha eligible for WH-CWO-1/WH-CWO-REVOKE,
  -- Beta eligible for WH-CWO-2, Gamma eligible for WH-CWO-GAMMA, Delta
  -- eligible for WH-CWO-T2.
  perform app.grant_warehouse_customer_eligibility(v_wh1.id, v_account_alpha.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh2.id, v_account_beta.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_revoke.id, v_account_alpha.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_gamma.id, v_account_gamma.id, v_supreme, 'admin');
  perform app.grant_warehouse_customer_eligibility(v_wh_t2.id, v_account_delta.id, v_supreme, 'admin');

  -- Items (untracked -- lot/serial control not needed for this capability's own test).
  v_item_alpha := (app.create_item_master(v_tenant1, v_account_alpha.id, 'SKU-CWO-ALPHA', 'Cwo Alpha Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;
  v_item_beta := (app.create_item_master(v_tenant1, v_account_beta.id, 'SKU-CWO-BETA', 'Cwo Beta Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;
  v_item_gamma := (app.create_item_master(v_tenant1, v_account_gamma.id, 'SKU-CWO-GAMMA', 'Cwo Gamma Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;
  v_item_delta := (app.create_item_master(v_tenant2, v_account_delta.id, 'SKU-CWO-DELTA', 'Cwo Delta Widget', null, 'PCS', false, false, false, v_supreme, 'admin')).id;

  -- Order A1 (WH-CWO-1, Alpha) -- stays DRAFT. 1 line, qty 5. Used for
  -- get/line-list/anti-enumeration/hidden-field checks and pagination page 1.
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_wh1.id, v_account_alpha.id, 'cwo alpha order 1', 'idem-cwo-outbound-a1', current_date + 3, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order.id, v_item_alpha, 'PCS', 5, null, v_supreme, 'admin');

  -- Order A2 (WH-CWO-1, Alpha) -- CONFIRMED (draft -> confirmed) after adding
  -- one line. Used for pagination page 2, status-diversity, and the
  -- live-mutation-visible-immediately freshness proof.
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_wh1.id, v_account_alpha.id, 'cwo alpha order 2', 'idem-cwo-outbound-a2', current_date + 5, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order.id, v_item_alpha, 'PCS', 3, null, v_supreme, 'admin');
  perform app.confirm_wms_outbound_order(v_order.id, v_order.record_version, v_supreme, 'admin');

  -- Order A3 (WH-CWO-1, Alpha) -- CONFIRMED then CANCELLED. Used for
  -- pagination page 3, cancelled_reason display, and the backdated-
  -- updated_at stale/degraded freshness proof.
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_wh1.id, v_account_alpha.id, 'cwo alpha order 3', 'idem-cwo-outbound-a3', current_date + 7, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order.id, v_item_alpha, 'PCS', 1, null, v_supreme, 'admin');
  v_order := app.confirm_wms_outbound_order(v_order.id, v_order.record_version, v_supreme, 'admin');
  perform app.cancel_wms_outbound_order(v_order.id, 'cwo fixture cancellation', v_order.record_version, v_supreme, 'admin');

  -- Order B1 (WH-CWO-2, Beta) -- isolation fixture (item a).
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_wh2.id, v_account_beta.id, 'cwo beta order', 'idem-cwo-outbound-b1', current_date + 3, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order.id, v_item_beta, 'PCS', 4, null, v_supreme, 'admin');

  -- Order AR (WH-CWO-REVOKE, Alpha) -- the revocation-immediate-effect fixture (item b).
  perform app.create_manual_wms_outbound_order(v_tenant1, v_wh_revoke.id, v_account_alpha.id, 'cwo alpha revoke-warehouse order', 'idem-cwo-outbound-arevoke', current_date + 3, v_supreme, 'admin');

  -- Order G1 (WH-CWO-GAMMA, Gamma) -- THE KEY REGRESSION FIXTURE (item d):
  -- owner_account_id=Gamma, only reachable through customer-multi's NEW-
  -- grant-table-only membership.
  v_order := app.create_manual_wms_outbound_order(v_tenant1, v_wh_gamma.id, v_account_gamma.id, 'cwo gamma order', 'idem-cwo-outbound-g1', current_date + 3, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order.id, v_item_gamma, 'PCS', 2, null, v_supreme, 'admin');

  -- Order T2D (tenant2, WH-CWO-T2, Delta) -- cross-tenant isolation fixture (item a).
  v_order := app.create_manual_wms_outbound_order(v_tenant2, v_wh_t2.id, v_account_delta.id, 'cwo delta order', 'idem-cwo-outbound-t2d', current_date + 3, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_order.id, v_item_delta, 'PCS', 6, null, v_supreme, 'admin');

  -- ===================================================================
  -- ISS-2026-120 inbound fixtures. Deliberately reuse the SAME accounts,
  -- warehouses, eligibility grants and customer identities the outbound
  -- fixtures above already established -- if the inbound RPCs resolved scope
  -- through anything other than the same resolver and the same eligibility
  -- predicate, these rows would come out differently, which is the point.
  -- ===================================================================

  -- Inbound IA1 (WH-CWO-1, Alpha) -- stays DRAFT. Used for get/line-list/
  -- anti-enumeration and as page 1 of the inbound pagination proof.
  v_inbound := app.create_manual_wms_inbound(v_tenant1, v_wh1.id, v_account_alpha.id, 'cwo alpha inbound 1', 'idem-cwo-inbound-a1', v_supreme, 'admin');
  perform app.add_wms_inbound_order_line(v_inbound.id, v_item_alpha, 'PCS', 9, null, v_supreme, 'admin');

  -- Inbound IA2 (WH-CWO-1, Alpha) -- SCHEDULED. This is the state that has no
  -- outbound counterpart at all, and the only fixture that carries a real
  -- appointment window and expected_date, so the projection of both is proven
  -- against real data rather than nulls.
  v_inbound := app.create_manual_wms_inbound(v_tenant1, v_wh1.id, v_account_alpha.id, 'cwo alpha inbound 2', 'idem-cwo-inbound-a2', v_supreme, 'admin');
  perform app.add_wms_inbound_order_line(v_inbound.id, v_item_alpha, 'PCS', 7, null, v_supreme, 'admin');
  select * into v_inbound from app.wms_inbound_orders where id = v_inbound.id;
  perform app.schedule_wms_inbound_appointment(v_inbound.id, date_trunc('hour', now()) + interval '2 days', date_trunc('hour', now()) + interval '2 days 3 hours', v_inbound.record_version, v_supreme, 'admin');

  -- Inbound IA3 (WH-CWO-1, Alpha) -- CANCELLED, for cancelled_reason display
  -- and status-filter diversity.
  v_inbound := app.create_manual_wms_inbound(v_tenant1, v_wh1.id, v_account_alpha.id, 'cwo alpha inbound 3', 'idem-cwo-inbound-a3', v_supreme, 'admin');
  perform app.add_wms_inbound_order_line(v_inbound.id, v_item_alpha, 'PCS', 2, null, v_supreme, 'admin');
  select * into v_inbound from app.wms_inbound_orders where id = v_inbound.id;
  perform app.cancel_wms_inbound(v_inbound.id, 'cwo inbound fixture cancellation', v_inbound.record_version, v_supreme, 'admin');

  -- Inbound IB1 (WH-CWO-2, Beta) -- cross-account isolation fixture.
  v_inbound := app.create_manual_wms_inbound(v_tenant1, v_wh2.id, v_account_beta.id, 'cwo beta inbound', 'idem-cwo-inbound-b1', v_supreme, 'admin');
  perform app.add_wms_inbound_order_line(v_inbound.id, v_item_beta, 'PCS', 4, null, v_supreme, 'admin');

  -- Inbound IAR (WH-CWO-REVOKE, Alpha) -- the revocation-immediate-effect
  -- fixture. WH-CWO-REVOKE's eligibility is revoked later in this file.
  perform app.create_manual_wms_inbound(v_tenant1, v_wh_revoke.id, v_account_alpha.id, 'cwo alpha revoke-warehouse inbound', 'idem-cwo-inbound-arevoke', v_supreme, 'admin');

  -- Inbound IG1 (WH-CWO-GAMMA, Gamma) -- THE KEY REGRESSION FIXTURE, the
  -- inbound twin of order G1: reachable ONLY through customer-multi's
  -- new-grant-table-only membership.
  v_inbound := app.create_manual_wms_inbound(v_tenant1, v_wh_gamma.id, v_account_gamma.id, 'cwo gamma inbound', 'idem-cwo-inbound-g1', v_supreme, 'admin');
  perform app.add_wms_inbound_order_line(v_inbound.id, v_item_gamma, 'PCS', 2, null, v_supreme, 'admin');

  -- Inbound IT2D (tenant2, WH-CWO-T2, Delta) -- cross-tenant isolation fixture.
  v_inbound := app.create_manual_wms_inbound(v_tenant2, v_wh_t2.id, v_account_delta.id, 'cwo delta inbound', 'idem-cwo-inbound-t2d', v_supreme, 'admin');
  perform app.add_wms_inbound_order_line(v_inbound.id, v_item_delta, 'PCS', 6, null, v_supreme, 'admin');
end $$;

\echo '>> app.get_customer_portal_outbound_order: own row succeeds (via legacy marker AND via the NEW grant table -- item d), forbidden and genuinely-nonexistent ids raise the IDENTICAL record_not_found shape (item e, anti-enumeration); returned row carries none of ATW-023''s own disclosed internal-only fields (item g, functional check); app.record_customer_inventory_access_denial (ATW-023, reused as-is, resource_type=outbound_order) durably records a denial for either cause, scoped by tenant_id from the first draft'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Alpha');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Beta');
  v_account_gamma uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Gamma');
  v_order_a1_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-cwo-outbound-a1');
  v_order_b1_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-cwo-outbound-b1');
  v_order_g1_id uuid := (select id from app.wms_outbound_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-cwo-outbound-g1');
  v_fake_id uuid := '77777777-7777-7777-7777-777777777777';
  v_forbidden_msg text;
  v_missing_msg text;
  v_audit_count integer;
  v_row record;
  v_row_json jsonb;
  v_internal_only_fields text[] := array['source_shipment_order_id', 'source_reason', 'idempotency_key', 'created_by', 'notes', 'tenant_id', 'wave_id', 'reservation_id', 'claimed_by_auth_user_id', 'claimed_by_label', 'picked_quantity', 'task_quantity', 'qc_by_auth_user_id', 'qc_by_label'];
begin
  select * into v_row from app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_order_a1_id);
  if v_row.id <> v_order_a1_id or v_row.owner_account_id <> v_account_alpha or v_row.status <> 'draft' then
    raise exception 'assertion failed: expected customer-multi to read their own Alpha (legacy-marker) draft order, got %', v_row;
  end if;

  -- THE KEY REGRESSION PROOF at the single-row level: Gamma, reachable ONLY
  -- through the new grant table, is readable via this migration's own get RPC.
  select * into v_row from app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_order_g1_id);
  if v_row.id <> v_order_g1_id or v_row.owner_account_id <> v_account_gamma then
    raise exception 'assertion failed: expected customer-multi to read their own Gamma (NEW-grant-table-only) order -- ISS-2026-117 fix, got %', v_row;
  end if;

  -- Item (g), functional check: the actual returned row never carries any of
  -- ATW-023's own already-disclosed internal-only fields, nor any pick/pack
  -- worker/productivity field -- a to_jsonb(record) key check, not merely a
  -- static read of the migration's own column list.
  v_row_json := to_jsonb(v_row);
  if v_row_json ?| v_internal_only_fields then
    raise exception 'assertion failed: app.get_customer_portal_outbound_order leaked an internal-only field, got keys %', (select array_agg(k) from jsonb_object_keys(v_row_json) k);
  end if;

  begin
    perform app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_order_b1_id);
    raise exception 'assertion failed: expected record_not_found -- customer-multi must not read Beta''s order';
  exception
    when others then
      v_forbidden_msg := sqlerrm;
      if v_forbidden_msg not like 'record_not_found%' then raise; end if;
  end;

  begin
    perform app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_fake_id);
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
  -- as-is, resource_type='outbound_order' -- the SAME literal ATW-023's own
  -- sibling db-test already uses). Scoped by tenant_id AND resource_type
  -- from the FIRST draft (the CPL-309 Tier C lesson: a shared v_fake_id
  -- literal collides across db-test files running against the same shared
  -- database, so every audit-log count in this file is scoped, never a bare
  -- resource_id-only filter).
  select count(*) into v_audit_count from app.audit_logs where action = 'customer_inventory_access_denied' and tenant_id = v_tenant1 and resource_type = 'outbound_order' and resource_id in (v_order_b1_id, v_fake_id);
  if v_audit_count <> 0 then
    raise exception 'assertion failed: expected ZERO customer_inventory_access_denied audit rows before app.record_customer_inventory_access_denial is ever called, got %', v_audit_count;
  end if;
  perform app.record_customer_inventory_access_denial(v_tenant1, v_customer_multi, 'outbound_order', v_order_b1_id, 'customer-multi');
  perform app.record_customer_inventory_access_denial(v_tenant1, v_customer_multi, 'outbound_order', v_fake_id, 'customer-multi');
  select count(*) into v_audit_count from app.audit_logs where action = 'customer_inventory_access_denied' and tenant_id = v_tenant1 and resource_type = 'outbound_order' and resource_id in (v_order_b1_id, v_fake_id);
  if v_audit_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 durable customer_inventory_access_denied audit rows after 2 real calls, got %', v_audit_count;
  end if;
end $$;

\echo '>> app.list_customer_portal_outbound_order_lines: delegates its own gate to app.get_customer_portal_outbound_order -- own order''s lines succeed, a forbidden order''s lines raise the IDENTICAL record_not_found (item e); returned line rows never carry notes or any pick/pack internal field (item g)'
do $$
declare
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_order_a1_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-cwo-outbound-a1');
  v_order_b1_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-cwo-outbound-b1');
  v_count integer;
  v_row record;
  v_row_json jsonb;
begin
  select count(*) into v_count from app.list_customer_portal_outbound_order_lines(v_order_a1_id, v_customer_multi);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 line for customer-multi''s own order A1, got %', v_count;
  end if;

  select * into v_row from app.list_customer_portal_outbound_order_lines(v_order_a1_id, v_customer_multi) limit 1;
  if v_row.requested_quantity <> 5 then
    raise exception 'assertion failed: expected order A1''s own line to carry requested_quantity=5, got %', v_row;
  end if;
  v_row_json := to_jsonb(v_row);
  if v_row_json ? 'notes' then
    raise exception 'assertion failed: app.list_customer_portal_outbound_order_lines leaked the internal notes field';
  end if;

  begin
    perform app.list_customer_portal_outbound_order_lines(v_order_b1_id, v_customer_multi);
    raise exception 'assertion failed: expected record_not_found from list_customer_portal_outbound_order_lines on Beta''s own order';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.list_customer_portal_outbound_orders: owner+eligibility scoped, cursor pagination advances and terminates across the 3 real WH-CWO-1 orders (item f), status filter matches only real database values, forged warehouse id yields zero rows not an error'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Beta');
  v_wh1 uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWO-1');
  v_fake_wh uuid := '55555555-5555-5555-5555-555555555555';
  v_count integer;
  v_row record;
  v_seen_ids uuid[] := array[]::uuid[];
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page_count integer;
  v_total_pages integer := 0;
begin
  -- Owner scope: customer-multi never sees Beta's orders anywhere.
  select count(*) into v_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200) v where v.owner_account_id = v_account_beta;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero of Beta''s orders in customer-multi''s own list, got %', v_count;
  end if;

  -- Alpha sees exactly 3 orders in WH-CWO-1 (A1 draft, A2 confirmed, A3 cancelled).
  select count(*) into v_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, v_wh1, null, null, null, 200);
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 orders for customer-multi in WH-CWO-1 (draft+confirmed+cancelled), got %', v_count;
  end if;

  -- Status filter: exactly 1 confirmed order (A2).
  select count(*) into v_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, v_wh1, 'confirmed', null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 confirmed order in WH-CWO-1, got %', v_count;
  end if;

  -- An unrecognized status value simply matches zero rows, never an error
  -- (migration design decision 10 -- mirrors ATW-023's own non-validating
  -- filter shape). "shipped" is a REAL app.wms_outbound_shipments status
  -- but never a real app.wms_outbound_orders.status value (design decision
  -- 9) -- deliberately chosen to prove the filter is not silently widened to
  -- accept the sibling ship-execution table's own vocabulary.
  select count(*) into v_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, v_wh1, 'shipped', null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for an unrecognized status value, got %', v_count;
  end if;

  -- Forged/foreign warehouse id -- zero rows, never an error.
  select count(*) into v_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, v_fake_wh, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a forged warehouse id, got %', v_count;
  end if;

  -- Cursor pagination: p_limit=1 across the 3 WH-CWO-1 orders must yield 3
  -- distinct pages that together cover all 3 rows exactly once, then
  -- terminate (4th page empty).
  loop
    v_page_count := 0;
    for v_row in
      select * from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, v_wh1, null, v_cursor_updated_at, v_cursor_id, 1)
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
    perform app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, null, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_updated_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> item (h): a real, backdated updated_at is surfaced VERBATIM, never fabricated as "just now" -- proves the no-cache/no-fabrication freshness design decision; and a live status transition (draft -> confirmed) is immediately visible through the RPC with a genuinely bumped record_version/updated_at'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_supreme uuid := '00000000-0000-0000-0000-000000319001';
  v_order_a3_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-cwo-outbound-a3');
  v_backdated timestamptz := now() - interval '5 days';
  v_row record;
  v_before_version integer;
  v_before_updated_at timestamptz;
  v_new_order app.wms_outbound_orders;
begin
  -- Backdate A3's own real updated_at, bypassing the touch trigger (it
  -- already IS cancelled -- this only manipulates the timestamp itself, not
  -- the status, to isolate the freshness claim from the status claim).
  alter table app.wms_outbound_orders disable trigger wms_outbound_orders_touch_row;
  update app.wms_outbound_orders set updated_at = v_backdated where id = v_order_a3_id;
  alter table app.wms_outbound_orders enable trigger wms_outbound_orders_touch_row;

  select * into v_row from app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_order_a3_id);
  if v_row.updated_at <> v_backdated then
    raise exception 'assertion failed: expected the RPC to surface the REAL, backdated updated_at (%) verbatim -- no cache, no fabrication -- got %', v_backdated, v_row.updated_at;
  end if;
  if v_row.status <> 'cancelled' or v_row.cancelled_reason <> 'cwo fixture cancellation' then
    raise exception 'assertion failed: expected order A3 to still be cancelled with its own real cancelled_reason, got %', v_row;
  end if;

  -- Live status transition, immediately visible -- a fresh manual order is
  -- created here, read once (draft) via the RPC. The confirm step is a
  -- DELIBERATELY SEPARATE top-level PL/pgSQL block below (not nested in this
  -- same one): now() is fixed for the duration of a single Postgres
  -- transaction, and this whole block IS one transaction, so a
  -- confirm-then-reread inside the SAME block would trivially observe the
  -- byte-identical updated_at regardless of whether the touch trigger fired
  -- correctly -- not a real freshness proof. A genuinely separate statement
  -- (psql's own default autocommit boundary) gets its own real, later
  -- now(), so the record_version/updated_at delta asserted in the next
  -- block is a live, wall-clock-real proof, not an artifact of same-
  -- transaction timestamp freezing.
  v_new_order := app.create_manual_wms_outbound_order(v_tenant1, (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWO-1'), (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Alpha'), 'cwo freshness live-transition order', 'idem-cwo-outbound-freshness', current_date + 2, v_supreme, 'admin');
  perform app.add_wms_outbound_order_line(v_new_order.id, (select id from app.item_masters where tenant_id = v_tenant1 and code = 'SKU-CWO-ALPHA'), 'PCS', 2, null, v_supreme, 'admin');

  select * into v_row from app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_new_order.id);
  v_before_version := v_row.record_version;
  v_before_updated_at := v_row.updated_at;
  if v_row.status <> 'draft' then
    raise exception 'assertion failed: expected the freshness fixture order to start draft, got %', v_row.status;
  end if;
end $$;

do $$
declare
  v_order_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-cwo-outbound-freshness');
  v_supreme uuid := '00000000-0000-0000-0000-000000319001';
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_before_version integer;
  v_before_updated_at timestamptz;
  v_row record;
begin
  select record_version, updated_at into v_before_version, v_before_updated_at from app.wms_outbound_orders where id = v_order_id;
  perform app.confirm_wms_outbound_order(v_order_id, v_before_version, v_supreme, 'admin');

  select * into v_row from app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_order_id);
  if v_row.status <> 'confirmed' then
    raise exception 'assertion failed: expected the freshness fixture order to be confirmed immediately after app.confirm_wms_outbound_order, got %', v_row.status;
  end if;
  if v_row.record_version <= v_before_version then
    raise exception 'assertion failed: expected record_version to genuinely bump after confirm (before %, after %)', v_before_version, v_row.record_version;
  end if;
  if v_row.updated_at <= v_before_updated_at then
    raise exception 'assertion failed: expected updated_at to genuinely advance after confirm (before %, after %) -- live, never cached', v_before_updated_at, v_row.updated_at;
  end if;
end $$;

\echo '>> THE KEY REGRESSION TEST (item d): customer-multi''s Gamma access comes ONLY from CPL-300''s new app.customer_portal_account_memberships table -- proven by direct query, and by the SAME identity calling ATW-023''s OLD app.list_customer_outbound_orders (unmodified, still gated by app.resolve_customer_owner_account_scope) and seeing NOTHING for Gamma, side-by-side with this migration''s NEW RPCs seeing it correctly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_account_gamma uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Gamma');
  v_wh_gamma uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWO-GAMMA');
  v_legacy_row_count integer;
  v_new_row_count integer;
  v_old_order_count integer;
  v_new_order_count integer;
begin
  -- Structural precondition: zero legacy app.principal_memberships row for
  -- (customer-multi, Gamma), exactly one ACTIVE row in the new grant table.
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
  -- marker -- must see ZERO of Gamma's orders for customer-multi.
  select count(*) into v_old_order_count from app.list_customer_outbound_orders(v_tenant1, v_customer_multi, v_wh_gamma, null, null, null, 200) v where v.owner_account_id = v_account_gamma;
  if v_old_order_count <> 0 then
    raise exception 'assertion failed: expected ATW-023''s OLD app.list_customer_outbound_orders to see ZERO of Gamma''s orders for customer-multi (Gamma is only in the NEW grant table) -- if this is nonzero, the fixture or the old RPC''s own behavior has changed unexpectedly, got %', v_old_order_count;
  end if;

  -- NEW (this migration, CPL-310): gated by app.resolve_customer_account_scope,
  -- the CPL-300 widened resolver -- MUST see Gamma's order. This is the live
  -- proof the scope gap is actually closed for warehouse orders.
  select count(*) into v_new_order_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, v_wh_gamma, null, null, null, 200) v where v.owner_account_id = v_account_gamma;
  if v_new_order_count <> 1 then
    raise exception 'assertion failed: expected this migration''s NEW app.list_customer_portal_outbound_orders to see EXACTLY 1 of Gamma''s orders for customer-multi (ISS-2026-117 fix), got %', v_new_order_count;
  end if;

  raise notice 'KEY REGRESSION TEST PASSED: customer-multi''s Gamma access exists ONLY in the new grant table (0 legacy rows, 1 new-table row); ATW-023''s OLD app.list_customer_outbound_orders sees 0 Gamma rows; this migration''s NEW app.list_customer_portal_outbound_orders sees exactly 1 -- the ISS-2026-117 scope gap is live-proven closed for warehouse orders, not merely structurally plausible';
end $$;

\echo '>> item (c): a legacy single-account customer_account_ref actor (customer-legacy, ZERO rows in the new grant table) still resolves correctly through the new resolver -- regression against ATW-023''s existing behavior'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_legacy uuid := '00000000-0000-0000-0000-000000319010';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Alpha');
  v_new_row_count integer;
  v_count integer;
begin
  select count(*) into v_new_row_count from app.customer_portal_account_memberships where auth_user_id = v_customer_legacy;
  if v_new_row_count <> 0 then
    raise exception 'assertion failed: fixture precondition violated -- customer-legacy must hold ZERO rows in the new grant table, got %', v_new_row_count;
  end if;

  select count(*) into v_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_legacy, null, null, null, null, 200) v where v.owner_account_id = v_account_alpha;
  if v_count = 0 then
    raise exception 'assertion failed: expected customer-legacy (legacy marker only) to still see their own Alpha orders through the new RPC';
  end if;
end $$;

\echo '>> item (a): cross-customer and cross-tenant isolation -- an out-of-scope, cross-tenant, and fabricated owner id are all indistinguishable (zero rows, no error); customer-badref (non-uuid legacy ref) resolves to an empty scope'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cwo2');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_customer_t2 uuid := '00000000-0000-0000-0000-000000321010';
  v_customer_badref uuid := '00000000-0000-0000-0000-000000319030';
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Beta');
  v_account_delta uuid := (select id from app.accounts where tenant_id = v_tenant2 and legal_name = 'Cwo Account Delta');
  v_fake_owner uuid := '44444444-4444-4444-4444-444444444444';
  v_count_beta integer;
  v_count_delta integer;
  v_count_fake integer;
  v_count integer;
begin
  select count(*) into v_count_beta from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200) v where v.owner_account_id = v_account_beta;
  select count(*) into v_count_delta from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200) v where v.owner_account_id = v_account_delta;
  select count(*) into v_count_fake from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200) v where v.owner_account_id = v_fake_owner;
  if v_count_beta <> 0 or v_count_delta <> 0 or v_count_fake <> 0 then
    raise exception 'assertion failed: expected identical zero-row outcomes for an out-of-scope, cross-tenant, and fabricated owner id, got % / % / %', v_count_beta, v_count_delta, v_count_fake;
  end if;

  -- Cross-tenant identity, real membership, unrelated tenant: customer-t2
  -- (a genuine tenant2 customer_user) has no membership in tenant1 at all --
  -- passing tenant1's own id must still yield zero rows, not another
  -- tenant's data.
  select count(*) into v_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_t2, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a genuinely cross-tenant identity probing tenant1 with tenant1''s own id, got %', v_count;
  end if;

  -- customer-badref: non-uuid-shaped legacy ref -- must resolve to an empty
  -- scope, never an error.
  select count(*) into v_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_badref, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for the empty-scope (non-uuid customer_account_ref) actor, got %', v_count;
  end if;
end $$;

\echo '>> item (b): revocation takes immediate effect -- the very next get/list call for the revoked warehouse excludes/denies, a live query, never cached'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_wh_revoke uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-CWO-REVOKE');
  v_supreme uuid := '00000000-0000-0000-0000-000000319001';
  v_eligibility_id uuid;
  v_eligibility_version integer;
  v_order_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-cwo-outbound-arevoke');
  v_count integer;
  v_row record;
begin
  -- Before revoke: customer-multi can see it (Alpha's own legacy-marker scope).
  select * into v_row from app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_order_id);
  if v_row.id <> v_order_id then
    raise exception 'assertion failed: expected customer-multi to see the WH-CWO-REVOKE order BEFORE revocation';
  end if;

  select id, record_version into v_eligibility_id, v_eligibility_version from app.warehouse_customer_eligibility
    where tenant_id = v_tenant1 and warehouse_id = v_wh_revoke and customer_account_id = (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Alpha');
  perform app.revoke_warehouse_customer_eligibility(v_eligibility_id, 'cwo revocation-immediate-effect test', v_eligibility_version, v_supreme, 'admin');

  -- Immediately after: the new RPC layer excludes/denies -- no cache, no
  -- delay, a live query against the current row every time.
  begin
    perform app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_order_id);
    raise exception 'assertion failed: expected record_not_found -- revocation must take immediate effect';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  select count(*) into v_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, v_wh_revoke, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero WH-CWO-REVOKE orders immediately after revocation, got %', v_count;
  end if;
end $$;

\echo '>> item (g), structural check: the three new functions'' own compiled source never references app.wms_pick_tasks/app.wms_packages/app.wms_outbound_shipments/app.wms_pick_waves/app.wms_packing_tasks or any of their own internal worker/productivity/task-queue columns'
do $$
declare
  v_fn text;
  v_src text;
  v_forbidden text;
  v_forbidden_terms text[] := array[
    'wms_pick_tasks', 'wms_packages', 'wms_outbound_shipments', 'wms_pick_waves', 'wms_packing_tasks',
    'claimed_by_auth_user_id', 'claimed_by_label', 'picked_quantity', 'task_quantity', 'remaining_quantity',
    'qc_by_auth_user_id', 'qc_by_label', 'qc_override_by_auth_user_id'
  ];
begin
  foreach v_fn in array array[
    'app.get_customer_portal_outbound_order',
    'app.list_customer_portal_outbound_order_lines',
    'app.list_customer_portal_outbound_orders'
  ] loop
    select prosrc into v_src from pg_proc where oid = v_fn::regproc;
    foreach v_forbidden in array v_forbidden_terms loop
      if v_src ilike '%' || v_forbidden || '%' then
        raise exception 'assertion failed: % must never reference internal pick/pack field/table %, but its own compiled source contains it', v_fn, v_forbidden;
      end if;
    end loop;
  end loop;
end $$;

\echo '>> raw-table RLS defense-in-depth: app.wms_outbound_orders/app.wms_outbound_order_lines are UNTOUCHED by this migration -- already denied outright to a customer_user actor by the pre-existing 20260730311000 hardening migration (a companion to ATW-023 itself), re-confirmed live here rather than assumed from that migration''s own text'
do $$
declare
  v_raw_order_count integer;
  v_raw_line_count integer;
  v_order_a1_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-cwo-outbound-a1');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000319011", "role": "authenticated"}';

  select count(*) into v_raw_order_count from app.wms_outbound_orders;
  if v_raw_order_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.wms_outbound_orders to be denied outright for a customer_user actor, got %', v_raw_order_count;
  end if;

  select count(*) into v_raw_line_count from app.wms_outbound_order_lines where outbound_order_id = v_order_a1_id;
  if v_raw_line_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.wms_outbound_order_lines to be denied outright for a customer_user actor, even for their own order''s lines, got %', v_raw_line_count;
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
    'app.get_customer_portal_outbound_order(uuid, uuid, uuid)',
    'app.list_customer_portal_outbound_order_lines(uuid, uuid)',
    'app.list_customer_portal_outbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer)'
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

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity, on every new RPC (ATW-031/032 discipline, applied here from the first draft -- the single most common Critical defect class across Phase 8 so far)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_impersonator uuid := '00000000-0000-0000-0000-000000319050';
  v_order_a1_id uuid := (select id from app.wms_outbound_orders where idempotency_key = 'idem-cwo-outbound-a1');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000319050", "role": "authenticated"}';

  begin
    perform app.get_customer_portal_outbound_order(v_tenant1, v_customer_multi, v_order_a1_id);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_portal_outbound_order -- the impersonator session may not claim to act as customer-multi';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_outbound_order_lines(v_order_a1_id, v_customer_multi);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_outbound_order_lines';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_outbound_orders';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (no relationship to
  -- customer-multi's own accounts) is not rejected by the identity check --
  -- it is correctly denied by the SCOPE check instead (record_not_found),
  -- proving the identity check and the scope check are two independent gates.
  begin
    perform app.get_customer_portal_outbound_order(v_tenant1, v_impersonator, v_order_a1_id);
    raise exception 'assertion failed: expected record_not_found -- the impersonator, acting as themselves, has no scope over Alpha''s order';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  reset role;
end $$;

\echo '>> a real, live authenticated-role positive path: customer-multi''s own real authenticated session sees the exact same result a direct superuser call returns, for BOTH legacy-marker (Alpha) and new-grant-table-only (Gamma) scope'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_superuser_count integer;
  v_session_count integer;
begin
  select count(*) into v_superuser_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000319011", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_outbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200);
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero row count (% ) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
end $$;

-- ===========================================================================
-- ISS-2026-120 -- the inbound half. Everything below exercises
-- app.get_customer_portal_inbound_order / app.list_customer_portal_inbound_
-- order_lines / app.list_customer_portal_inbound_orders against the SAME
-- fixtures the outbound assertions above already used, so a divergence in
-- scope, eligibility, anti-enumeration or identity handling between the two
-- halves shows up as a failure here rather than as a quiet asymmetry nobody
-- reads. Ordered after the revocation block on purpose: by this point
-- WH-CWO-REVOKE's eligibility is already gone, which lets the inbound list
-- prove it reads live eligibility rather than a snapshot taken at any earlier
-- moment.
-- ===========================================================================

\echo '>> ISS-2026-120 item (a/d): cross-tenant + cross-account isolation, and THE KEY REGRESSION -- an account granted ONLY through CPL-300''s new grant table is visible to the inbound RPCs, exactly as it is to the outbound ones'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cwo2');
  v_customer_legacy uuid := '00000000-0000-0000-0000-000000319010';
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_customer_t2 uuid := '00000000-0000-0000-0000-000000321010';
  v_account_gamma uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Gamma');
  v_account_beta uuid := (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Cwo Account Beta');
  v_count integer;
begin
  -- customer-legacy holds Alpha only, through the legacy marker. Alpha owns
  -- exactly three inbound orders in an eligible warehouse (IA1/IA2/IA3);
  -- IAR's warehouse eligibility was revoked above, so it must not appear.
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, null, null, null, 200);
  if v_count <> 3 then
    raise exception 'assertion failed: expected customer-legacy to see exactly 3 inbound orders (IA1/IA2/IA3, NOT the revoked-warehouse IAR), got %', v_count;
  end if;

  -- Never another account's inbound order, even inside the same tenant.
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, null, null, null, 200) r
    where r.owner_account_id = v_account_beta;
  if v_count <> 0 then
    raise exception 'assertion failed: customer-legacy must never see Beta''s inbound orders, got % rows', v_count;
  end if;

  -- THE KEY REGRESSION: customer-multi reaches Gamma ONLY through
  -- app.customer_portal_account_memberships. If the inbound list resolved
  -- scope through the legacy resolver, this count would be 3, not 4.
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200);
  if v_count <> 4 then
    raise exception 'assertion failed: expected customer-multi to see 4 inbound orders (Alpha''s 3 + Gamma''s 1 via the NEW grant table only), got %', v_count;
  end if;
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200) r
    where r.owner_account_id = v_account_gamma;
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 Gamma inbound order via the new grant table, got %', v_count;
  end if;

  -- Cross-tenant: tenant2's own customer sees only tenant2's inbound order,
  -- and tenant1's customers never see it.
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant2, v_customer_t2, null, null, null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected customer-t2 to see exactly 1 inbound order, got %', v_count;
  end if;
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant2, v_customer_legacy, null, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: a tenant1 customer must see zero tenant2 inbound orders, got %', v_count;
  end if;
end $$;

\echo '>> ISS-2026-120 item (e): anti-enumeration -- a foreign inbound id and a genuinely nonexistent one raise the IDENTICAL record_not_found, on the get RPC and on the line-list RPC that delegates to it'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_legacy uuid := '00000000-0000-0000-0000-000000319010';
  v_inbound_ia1 uuid := (select id from app.wms_inbound_orders where idempotency_key = 'idem-cwo-inbound-a1');
  v_inbound_ib1 uuid := (select id from app.wms_inbound_orders where idempotency_key = 'idem-cwo-inbound-b1');
  v_inbound_it2d uuid := (select id from app.wms_inbound_orders where idempotency_key = 'idem-cwo-inbound-t2d');
  v_ghost uuid := '00000000-0000-0000-0000-0000003190ff';
  v_row record;
  v_line_count integer;
  v_msg_foreign text;
  v_msg_ghost text;
begin
  -- Positive path first, so a uniformly-denying function cannot pass this block.
  select * into v_row from app.get_customer_portal_inbound_order(v_tenant1, v_customer_legacy, v_inbound_ia1);
  if v_row.id <> v_inbound_ia1 or v_row.status <> 'draft' or v_row.source_type <> 'manual' then
    raise exception 'assertion failed: expected IA1 back as a draft/manual inbound order';
  end if;
  select count(*) into v_line_count from app.list_customer_portal_inbound_order_lines(v_inbound_ia1, v_customer_legacy);
  if v_line_count <> 1 then
    raise exception 'assertion failed: expected 1 line on IA1, got %', v_line_count;
  end if;

  -- A same-tenant, different-account order and a nonexistent id must be
  -- indistinguishable from each other in the error the caller sees.
  begin
    perform app.get_customer_portal_inbound_order(v_tenant1, v_customer_legacy, v_inbound_ib1);
    raise exception 'assertion failed: expected record_not_found for Beta''s inbound order';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
      v_msg_foreign := replace(sqlerrm, v_inbound_ib1::text, '<id>');
  end;
  begin
    perform app.get_customer_portal_inbound_order(v_tenant1, v_customer_legacy, v_ghost);
    raise exception 'assertion failed: expected record_not_found for a nonexistent inbound id';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
      v_msg_ghost := replace(sqlerrm, v_ghost::text, '<id>');
  end;
  if v_msg_foreign is distinct from v_msg_ghost then
    raise exception 'assertion failed: anti-enumeration broken -- forbidden (%) and nonexistent (%) must produce the identical message', v_msg_foreign, v_msg_ghost;
  end if;

  -- Cross-tenant id through the tenant the caller DOES belong to: still the
  -- same shape, never a "wrong tenant" hint.
  begin
    perform app.get_customer_portal_inbound_order(v_tenant1, v_customer_legacy, v_inbound_it2d);
    raise exception 'assertion failed: expected record_not_found for a cross-tenant inbound id';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  -- The line-list RPC inherits the same denial by delegating its gate.
  begin
    perform app.list_customer_portal_inbound_order_lines(v_inbound_ib1, v_customer_legacy);
    raise exception 'assertion failed: expected record_not_found from the inbound line-list RPC for a forbidden order';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;
  begin
    perform app.list_customer_portal_inbound_order_lines(v_ghost, v_customer_legacy);
    raise exception 'assertion failed: expected record_not_found from the inbound line-list RPC for a nonexistent order';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;
end $$;

\echo '>> ISS-2026-120: the two genuinely inbound-only projections -- the `scheduled` status outbound has no counterpart for, and the appointment window / expected_date, all returned as real values rather than nulls'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_legacy uuid := '00000000-0000-0000-0000-000000319010';
  v_inbound_ia2 uuid := (select id from app.wms_inbound_orders where idempotency_key = 'idem-cwo-inbound-a2');
  v_inbound_ia3 uuid := (select id from app.wms_inbound_orders where idempotency_key = 'idem-cwo-inbound-a3');
  v_row record;
  v_count integer;
begin
  select * into v_row from app.get_customer_portal_inbound_order(v_tenant1, v_customer_legacy, v_inbound_ia2);
  if v_row.status <> 'scheduled' then
    raise exception 'assertion failed: expected IA2 to be scheduled, got %', v_row.status;
  end if;
  if v_row.appointment_window_start is null or v_row.appointment_window_end is null then
    raise exception 'assertion failed: a scheduled inbound order must project its real appointment window, got start=% end=%', v_row.appointment_window_start, v_row.appointment_window_end;
  end if;
  if v_row.appointment_window_end <= v_row.appointment_window_start then
    raise exception 'assertion failed: appointment window projected out of order';
  end if;
  if v_row.expected_date is distinct from v_row.appointment_window_start::date then
    raise exception 'assertion failed: expected_date must be the window start''s own date, got % vs %', v_row.expected_date, v_row.appointment_window_start::date;
  end if;

  -- Cancellation reason is projected verbatim, the same way outbound does it.
  select * into v_row from app.get_customer_portal_inbound_order(v_tenant1, v_customer_legacy, v_inbound_ia3);
  if v_row.status <> 'cancelled' or v_row.cancelled_reason is distinct from 'cwo inbound fixture cancellation' then
    raise exception 'assertion failed: expected IA3 cancelled with its real reason, got status=% reason=%', v_row.status, v_row.cancelled_reason;
  end if;

  -- Status filter reaches every one of the four real values, and an invented
  -- one matches zero rows rather than raising -- the same non-validating shape
  -- the outbound list uses.
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, 'scheduled', null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 scheduled inbound order, got %', v_count;
  end if;
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, 'draft', null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 draft inbound order, got %', v_count;
  end if;
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, 'cancelled', null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 cancelled inbound order, got %', v_count;
  end if;
  select count(*) into v_count from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, 'teleported', null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: an unrecognized status filter must match zero rows without raising, got %', v_count;
  end if;
end $$;

\echo '>> ISS-2026-120: pagination is a real keyset walk (updated_at desc, id desc) with no overlap and no gap, and a half-supplied cursor fails loud rather than silently returning an empty page'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_legacy uuid := '00000000-0000-0000-0000-000000319010';
  v_page record;
  v_seen uuid[] := array[]::uuid[];
  v_cursor_updated timestamptz := null;
  v_cursor_id uuid := null;
  v_total integer;
begin
  for i in 1..3 loop
    select * into v_page from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, null, v_cursor_updated, v_cursor_id, 1);
    if v_page.id is null then
      raise exception 'assertion failed: expected a row on inbound pagination step %', i;
    end if;
    if v_page.id = any(v_seen) then
      raise exception 'assertion failed: inbound pagination returned a duplicate row on step %', i;
    end if;
    v_seen := array_append(v_seen, v_page.id);
    v_cursor_updated := v_page.updated_at;
    v_cursor_id := v_page.id;
  end loop;

  select count(*) into v_total from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, null, v_cursor_updated, v_cursor_id, 200);
  if v_total <> 0 then
    raise exception 'assertion failed: expected the inbound keyset walk to be exhausted after 3 pages, got % more rows', v_total;
  end if;

  begin
    perform app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, null, null, v_seen[1], 50);
    raise exception 'assertion failed: expected invalid_cursor when p_cursor_id is supplied without p_cursor_updated_at';
  exception
    when others then
      if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

\echo '>> ISS-2026-120: the actor-identity session cross-check applies to all three inbound RPCs, and a real session acting as ITSELF is denied by scope instead -- two independent gates'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_impersonator uuid := '00000000-0000-0000-0000-000000319050';
  v_inbound_ia1 uuid := (select id from app.wms_inbound_orders where idempotency_key = 'idem-cwo-inbound-a1');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000319050", "role": "authenticated"}';

  begin
    perform app.get_customer_portal_inbound_order(v_tenant1, v_customer_multi, v_inbound_ia1);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_portal_inbound_order';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_inbound_order_lines(v_inbound_ia1, v_customer_multi);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_inbound_order_lines';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_inbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_inbound_orders';
  exception
    when others then
      if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.get_customer_portal_inbound_order(v_tenant1, v_impersonator, v_inbound_ia1);
    raise exception 'assertion failed: expected record_not_found -- the impersonator, acting as themselves, has no scope over Alpha''s inbound order';
  exception
    when others then
      if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  reset role;
end $$;

\echo '>> ISS-2026-120: raw-table RLS defense-in-depth -- this migration extends 20260730311000''s customer_user-layer denial to app.wms_inbound_orders/app.wms_inbound_order_lines, which were outside that migration''s own scope; a real customer session reads zero rows raw while the RPC surface returns its real rows'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_legacy uuid := '00000000-0000-0000-0000-000000319010';
  v_raw_orders integer;
  v_raw_lines integer;
  v_rpc_rows integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000319010", "role": "authenticated"}';

  select count(*) into v_raw_orders from app.wms_inbound_orders;
  select count(*) into v_raw_lines from app.wms_inbound_order_lines;
  -- Same session, same instant: the sanctioned SECURITY DEFINER path works.
  select count(*) into v_rpc_rows from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_legacy, null, null, null, null, 200);

  reset role;

  if v_raw_orders <> 0 then
    raise exception 'assertion failed: a customer_user-layer session must read ZERO rows from app.wms_inbound_orders raw, got %', v_raw_orders;
  end if;
  if v_raw_lines <> 0 then
    raise exception 'assertion failed: a customer_user-layer session must read ZERO rows from app.wms_inbound_order_lines raw, got %', v_raw_lines;
  end if;
  if v_rpc_rows <> 3 then
    raise exception 'assertion failed: the RPC path must still return the caller''s own 3 inbound orders in the same session, got % -- a denial that also breaks the sanctioned path proves nothing', v_rpc_rows;
  end if;
end $$;

\echo '>> ISS-2026-120: grants -- anon holds EXECUTE on none of the three new app.* functions nor their public.* wrappers; authenticated and service_role hold it on all six'
do $$
declare
  v_fn text;
  v_has_priv boolean;
begin
  foreach v_fn in array array[
    'app.get_customer_portal_inbound_order(uuid, uuid, uuid)',
    'app.list_customer_portal_inbound_order_lines(uuid, uuid)',
    'app.list_customer_portal_inbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'public.get_customer_portal_inbound_order(uuid, uuid, uuid)',
    'public.list_customer_portal_inbound_order_lines(uuid, uuid)',
    'public.list_customer_portal_inbound_orders(uuid, uuid, uuid, text, timestamptz, uuid, integer)'
  ] loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has_priv;
    if v_has_priv then
      raise exception 'assertion failed: anon must NOT hold EXECUTE on % (ISS-2026-309: revoking from PUBLIC alone does not remove Supabase''s explicit default-privilege grant)', v_fn;
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

\echo '>> ISS-2026-120: the public.* wrappers are pass-throughs, not reimplementations -- each returns byte-identical rows to its app.* original for the same caller'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cwo1');
  v_customer_multi uuid := '00000000-0000-0000-0000-000000319011';
  v_inbound_ia1 uuid := (select id from app.wms_inbound_orders where idempotency_key = 'idem-cwo-inbound-a1');
  v_app_rows integer;
  v_pub_rows integer;
  v_app_row record;
  v_pub_row record;
begin
  select count(*) into v_app_rows from app.list_customer_portal_inbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200);
  select count(*) into v_pub_rows from public.list_customer_portal_inbound_orders(v_tenant1, v_customer_multi, null, null, null, null, 200);
  if v_app_rows <> v_pub_rows then
    raise exception 'assertion failed: public wrapper returned % rows vs app''s % -- a wrapper that disagrees with its original is a second implementation', v_pub_rows, v_app_rows;
  end if;

  select * into v_app_row from app.get_customer_portal_inbound_order(v_tenant1, v_customer_multi, v_inbound_ia1);
  select * into v_pub_row from public.get_customer_portal_inbound_order(v_tenant1, v_customer_multi, v_inbound_ia1);
  if v_app_row.id is distinct from v_pub_row.id
    or v_app_row.warehouse_id is distinct from v_pub_row.warehouse_id
    or v_app_row.owner_account_id is distinct from v_pub_row.owner_account_id
    or v_app_row.inbound_number is distinct from v_pub_row.inbound_number
    or v_app_row.source_type is distinct from v_pub_row.source_type
    or v_app_row.expected_date is distinct from v_pub_row.expected_date
    or v_app_row.appointment_window_start is distinct from v_pub_row.appointment_window_start
    or v_app_row.appointment_window_end is distinct from v_pub_row.appointment_window_end
    or v_app_row.status is distinct from v_pub_row.status
    or v_app_row.cancelled_reason is distinct from v_pub_row.cancelled_reason
    or v_app_row.record_version is distinct from v_pub_row.record_version
    or v_app_row.created_at is distinct from v_pub_row.created_at
    or v_app_row.updated_at is distinct from v_pub_row.updated_at
  then
    raise exception 'assertion failed: public.get_customer_portal_inbound_order disagrees with app.get_customer_portal_inbound_order on at least one column';
  end if;

  select count(*) into v_app_rows from app.list_customer_portal_inbound_order_lines(v_inbound_ia1, v_customer_multi);
  select count(*) into v_pub_rows from public.list_customer_portal_inbound_order_lines(v_inbound_ia1, v_customer_multi);
  if v_app_rows <> v_pub_rows then
    raise exception 'assertion failed: public.list_customer_portal_inbound_order_lines returned % rows vs app''s %', v_pub_rows, v_app_rows;
  end if;
end $$;

\echo '>> ISS-2026-120: the inbound RPCs expose no internal pick/pack/receiving worker or productivity field -- structural check against the compiled source, mirroring the outbound check above'
do $$
declare
  v_fn text;
  v_src text;
  v_forbidden text;
  v_forbidden_terms text[] := array[
    'wms_pick_tasks', 'wms_packages', 'wms_outbound_shipments', 'wms_pick_waves', 'wms_packing_tasks',
    'claimed_by_auth_user_id', 'claimed_by_label', 'picked_quantity', 'task_quantity', 'remaining_quantity',
    'qc_by_auth_user_id', 'qc_by_label', 'qc_override_by_auth_user_id',
    'source_shipment_order_id', 'idempotency_key', 'source_reason'
  ];
begin
  foreach v_fn in array array['get_customer_portal_inbound_order', 'list_customer_portal_inbound_order_lines', 'list_customer_portal_inbound_orders'] loop
    select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = v_fn;
    if v_src is null then
      raise exception 'assertion failed: app.% not found', v_fn;
    end if;
    foreach v_forbidden in array v_forbidden_terms loop
      if v_src like '%' || v_forbidden || '%' then
        raise exception 'assertion failed: app.%''s compiled source references the internal/excluded term "%"', v_fn, v_forbidden;
      end if;
    end loop;
  end loop;
end $$;
