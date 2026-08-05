-- CG-S10-ATW-024 (Prompt 243) load-test seed fixture -- closes the "populated-
-- database" half of ISS-2026-014. Run once, by scripts/load-tests/run.sh, against
-- a fresh disposable database that already has every supabase/migrations/*.sql
-- applied (via the same shared scripts/db-tests/lib/setup-disposable-db.sh this
-- migration-apply logic already uses for scripts/db-tests/run.sh -- never
-- duplicated).
--
-- Seeded volume (real counts, not a toy 3-row fixture -- exact figures re-verified
-- by the harness's own post-seed row-count query, printed to the results file):
--   1 tenant, 1 company org unit, 1 admin actor (full OPS+COM authority),
--   1 supreme admin actor, 2 owner accounts (Alpha/Beta), 1 warehouse, 1 zone,
--   300 warehouse_locations (200 rack pick+putaway-enabled, 50 dock, 50 staging),
--   400 item_masters (250 Alpha, 150 Beta), ~800 general inventory_balances rows
--   plus 1 dedicated high-volume "hot" balance (via a REAL app.post_inventory_
--   movement opening_balance call, on_hand = 1,000,000) used by the concurrent-
--   posting load scenario, 500 confirmed wms_outbound_orders/lines with 500
--   matching real app.inventory_reservations + unclaimed app.wms_pick_tasks rows,
--   500 confirmed wms_inbound_orders/committed wms_receipt_lines + unclaimed
--   app.wms_putaway_tasks rows, 5,000 pending app.jobs rows spread across every
--   generic job_type, 60 vehicles (app.master_records + app.vehicle_operational_
--   profiles), 300 app.lot_identities + 200 app.serial_identities rows, one
--   customer_user principal granted warehouse eligibility on Account Alpha (for
--   the ATW-023 pagination EXPLAIN scenario).
--
-- Design note (disclosed): identity/permission/warehouse/zone setup goes through
-- the REAL RPCs (app.provision_tenant, app.create_warehouse, app.create_warehouse_
-- zone, etc.) exactly like every scripts/db-tests/*.sql fixture already does --
-- these are cheap, one-time, non-measured setup calls. The high-VOLUME rows
-- (locations/items/balances/pick-and-putaway-task preconditions/jobs/vehicles/lot-
-- serial identities) are bulk INSERT...SELECT (never a per-row RPC loop -- would
-- take minutes-to-hours at this volume and is not itself what any load scenario
-- measures) directly into the already-migrated tables, using the exact same
-- columns/defaults/status values the real RPCs that normally write these tables
-- would produce. The one exception, disclosed per scenario: the "hot" shared
-- balance used by the concurrent-posting scenario IS created via a real app.
-- post_inventory_movement call (not bulk-inserted) since that RPC's own
-- correctness under concurrency is exactly what that scenario measures, and its
-- pre-state must be established through the real code path for the proof to mean
-- anything. wms_pick_tasks/wms_putaway_tasks are bulk-seeded as the real
-- generation RPCs (app.generate_wms_pick_task/app.generate_wms_putaway_task)
-- would have left them (status='unclaimed', a real linked reservation for pick
-- tasks); the actual claim step every load scenario measures always goes through
-- the real app.claim_wms_pick_task/app.claim_wms_putaway_task RPCs, never a
-- bulk-seeded shortcut -- bulk-seeding only the PRECONDITION rows, never the
-- thing being measured, is the same principle scripts/db-tests/*.sql fixtures
-- already apply when they insert directly into auth.users to bootstrap identities
-- the real app.invite_user flow would otherwise mint via email.
-- Putaway rows do not additionally seed a matching received-stock balance row at
-- the dock/receiving location (a real app.commit_wms_receipt_line call would
-- create one) since no load scenario in this checkpoint reads app.inventory_
-- balances for those dock locations -- disclosed, not silently omitted.

\set ON_ERROR_STOP on

\echo '>> load-test seed: identity, tenant, warehouse, zone, accounts (real RPCs)'
create temporary table load_test_state (key text primary key, value text not null);
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_edit_role uuid;
  v_edit_draft app.role_versions;
  v_warehouse app.warehouses;
  v_zone app.warehouse_zones;
  v_account_alpha app.accounts;
  v_account_beta app.accounts;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000090001', 'admin@loadtest.test'),
    ('00000000-0000-0000-0000-000000090002', 'supreme@loadtest.test'),
    ('00000000-0000-0000-0000-000000090003', 'customer@loadtest.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000090002', 'supreme_admin', null, null, 'loadtest');

  perform app.provision_tenant('loadtest', 'Load Test Co', 'idem-loadtest', 'loadtest');
  v_tenant1 := (select id from app.tenants where slug = 'loadtest');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'loadtest');
  perform app.create_org_unit(v_tenant1, 'company', null, 'LOADTEST-CO', 'Load Test Co', 'loadtest');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'LOADTEST-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000090001', 'admin@loadtest.test', 'Load Admin', v_team_a, 'loadtest', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@loadtest.test'), 'active', 'onboarded', 'loadtest');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000090001', 'tenant_admin', v_tenant1, null, 'loadtest');

  v_edit_role := (app.create_role(v_tenant1, 'Load Test Full Access', 'full commercial + ops for load-test seeding', 'loadtest')).id;
  v_edit_draft := app.create_role_version(v_edit_role, 'loadtest');
  perform app.set_role_version_permissions(
    v_edit_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View', 'Assign', 'Override', 'Close'))),
    'loadtest'
  );
  perform app.publish_role_version(v_edit_draft.id, now(), 'loadtest');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_edit_role and status = 'published'), '00000000-0000-0000-0000-000000090001', '00000000-0000-0000-0000-000000090002', 'loadtest');

  select * into v_warehouse from app.create_warehouse(v_tenant1, v_team_a, 'WH-LOAD-1', 'Load Test Warehouse 1', 'Jl. Load Test 1, Jakarta', 'Asia/Jakarta', null, array['land_freight'], '00000000-0000-0000-0000-000000090001', 'loadtest');
  select * into v_zone from app.create_warehouse_zone(v_warehouse.id, 'ZONE-LOAD-1', 'Load Zone 1', 'ambient', '{}'::jsonb, null, null, '{}'::jsonb, now(), null, '00000000-0000-0000-0000-000000090001', 'loadtest');

  -- Two owner accounts, direct insert -- a load-test fixture does not need the
  -- full CRM lead->prospect->quotation->conversion pipeline scripts/db-tests/*.sql
  -- exercises for correctness elsewhere; the load scenarios below only need real,
  -- valid app.accounts rows to hang item_masters/inventory_balances off of.
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, customer_status, status, created_by)
  values (v_tenant1, 'Load Test Owner Alpha', 'loadtest-alpha-fingerprint', 'active', 'active', 'loadtest')
  returning * into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, customer_status, status, created_by)
  values (v_tenant1, 'Load Test Owner Beta', 'loadtest-beta-fingerprint', 'active', 'active', 'loadtest')
  returning * into v_account_beta;

  -- A customer_user principal scoped to Account Alpha, plus warehouse eligibility
  -- -- used only by the ATW-023 pagination EXPLAIN scenario. app.grant_principal_
  -- membership requires a real app.tenant_user_identities row to already exist
  -- for (auth_user_id, tenant_id) -- app.invite_user is the real path that
  -- creates one (with a null org_unit_id, the same "customer portal actor has no
  -- OPS org-unit membership" convention advanced-tms-customer-inventory-access.sql
  -- already establishes).
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000090003', 'customer@loadtest.test', 'Load Customer Portal', null, 'loadtest', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer@loadtest.test'), 'active', 'onboarded', 'loadtest');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000090003', 'customer_user', v_tenant1, v_account_alpha.id::text, 'loadtest');
  perform app.grant_warehouse_customer_eligibility(v_warehouse.id, v_account_alpha.id, '00000000-0000-0000-0000-000000090001', 'loadtest');

  insert into load_test_state (key, value) values
    ('tenant_id', v_tenant1::text),
    ('team_a_org_unit_id', v_team_a::text),
    ('warehouse_id', v_warehouse.id::text),
    ('zone_id', v_zone.id::text),
    ('account_alpha_id', v_account_alpha.id::text),
    ('account_beta_id', v_account_beta.id::text),
    ('admin_actor_id', '00000000-0000-0000-0000-000000090001'),
    ('supreme_actor_id', '00000000-0000-0000-0000-000000090002'),
    ('customer_actor_id', '00000000-0000-0000-0000-000000090003');
end $$;

\echo '>> load-test seed: 300 warehouse_locations (200 rack, 50 dock, 50 staging), bulk INSERT...SELECT'
do $$
declare
  v_tenant1 uuid := (select value::uuid from load_test_state where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from load_test_state where key = 'warehouse_id');
  v_zone_id uuid := (select value::uuid from load_test_state where key = 'zone_id');
begin
  insert into app.warehouse_locations (tenant_id, warehouse_id, zone_id, code, name, location_type, pick_enabled, putaway_enabled, status, created_by)
  select v_tenant1, v_warehouse_id, v_zone_id, 'RACK-LOAD-' || lpad(g::text, 5, '0'), 'Load Rack ' || g, 'bin', true, true, 'active', 'loadtest'
  from generate_series(1, 200) g;

  insert into app.warehouse_locations (tenant_id, warehouse_id, zone_id, code, name, location_type, pick_enabled, putaway_enabled, status, created_by)
  select v_tenant1, v_warehouse_id, v_zone_id, 'DOCK-LOAD-' || lpad(g::text, 5, '0'), 'Load Dock ' || g, 'dock', false, false, 'active', 'loadtest'
  from generate_series(1, 50) g;

  insert into app.warehouse_locations (tenant_id, warehouse_id, zone_id, code, name, location_type, pick_enabled, putaway_enabled, status, created_by)
  select v_tenant1, v_warehouse_id, v_zone_id, 'STAGE-LOAD-' || lpad(g::text, 5, '0'), 'Load Staging ' || g, 'staging', false, false, 'active', 'loadtest'
  from generate_series(1, 50) g;
end $$;

\echo '>> load-test seed: 400 item_masters (250 Alpha, 150 Beta), bulk INSERT...SELECT'
do $$
declare
  v_tenant1 uuid := (select value::uuid from load_test_state where key = 'tenant_id');
  v_account_alpha_id uuid := (select value::uuid from load_test_state where key = 'account_alpha_id');
  v_account_beta_id uuid := (select value::uuid from load_test_state where key = 'account_beta_id');
begin
  insert into app.item_masters (tenant_id, owner_account_id, code, name, base_uom_code, status, created_by)
  select v_tenant1, v_account_alpha_id, 'SKU-ALPHA-' || lpad(g::text, 5, '0'), 'Alpha Load Item ' || g, 'PCS', 'active', 'loadtest'
  from generate_series(1, 250) g;

  insert into app.item_masters (tenant_id, owner_account_id, code, name, base_uom_code, status, created_by)
  select v_tenant1, v_account_beta_id, 'SKU-BETA-' || lpad(g::text, 5, '0'), 'Beta Load Item ' || g, 'PCS', 'active', 'loadtest'
  from generate_series(1, 150) g;
end $$;

\echo '>> load-test seed: ~800 general inventory_balances rows spread across items/rack locations'
do $$
declare
  v_tenant1 uuid := (select value::uuid from load_test_state where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from load_test_state where key = 'warehouse_id');
begin
  -- Two balance rows per item (400 items * 2 = 800), each at a deterministic
  -- rack location so the dimension-uniqueness index is never violated.
  insert into app.inventory_balances (tenant_id, warehouse_id, owner_account_id, item_master_id, location_id, status, on_hand)
  select v_tenant1, v_warehouse_id, im.owner_account_id, im.id, loc.id, 'on_hand', 100 + (row_number() over (order by im.id) % 50)
  from app.item_masters im
  join lateral (
    select id from app.warehouse_locations where warehouse_id = v_warehouse_id and location_type = 'bin'
    order by code offset (('x' || substr(md5(im.id::text), 1, 6))::bit(24)::int % 200) limit 1
  ) loc on true
  where im.tenant_id = v_tenant1;

  insert into app.inventory_balances (tenant_id, warehouse_id, owner_account_id, item_master_id, location_id, status, on_hand)
  select v_tenant1, v_warehouse_id, im.owner_account_id, im.id, loc.id, 'on_hand', 50 + (row_number() over (order by im.id) % 30)
  from app.item_masters im
  join lateral (
    select id from app.warehouse_locations where warehouse_id = v_warehouse_id and location_type = 'bin'
    order by code offset ((('x' || substr(md5(im.id::text), 1, 6))::bit(24)::int + 77) % 200) limit 1
  ) loc on true
  where im.tenant_id = v_tenant1;
end $$;

\echo '>> load-test seed: the dedicated "hot" shared balance dimension for the concurrent-posting scenario, via a REAL app.post_inventory_movement opening_balance call (on_hand = 1,000,000)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from load_test_state where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from load_test_state where key = 'warehouse_id');
  v_account_alpha_id uuid := (select value::uuid from load_test_state where key = 'account_alpha_id');
  v_admin_id uuid := (select value::uuid from load_test_state where key = 'admin_actor_id');
  v_hot_item app.item_masters;
  v_hot_location_id uuid;
  v_movement app.inventory_movements;
  v_balance_id uuid;
begin
  insert into app.item_masters (tenant_id, owner_account_id, code, name, base_uom_code, status, created_by)
  values (v_tenant1, v_account_alpha_id, 'SKU-HOT-CONTENTION', 'Hot Contention Item', 'PCS', 'active', 'loadtest')
  returning * into v_hot_item;

  select id into v_hot_location_id from app.warehouse_locations where warehouse_id = v_warehouse_id and code = 'RACK-LOAD-00001';

  v_movement := app.post_inventory_movement(
    v_tenant1, v_warehouse_id, 'opening_balance', 'manual', null, 'idem-loadtest-hot-opening', 'load-test hot balance seed',
    jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_account_alpha_id, 'item_master_id', v_hot_item.id, 'location_id', v_hot_location_id,
      'uom_code', 'PCS', 'signed_quantity', 1000000, 'status', 'on_hand'
    )),
    v_admin_id, 'loadtest'
  );

  select id into v_balance_id from app.inventory_balances
    where tenant_id = v_tenant1 and warehouse_id = v_warehouse_id and owner_account_id = v_account_alpha_id
      and item_master_id = v_hot_item.id and location_id = v_hot_location_id and status = 'on_hand';

  insert into load_test_state (key, value) values
    ('hot_item_master_id', v_hot_item.id::text),
    ('hot_location_id', v_hot_location_id::text),
    ('hot_balance_id', v_balance_id::text);
end $$;

\echo '>> load-test seed: 500 confirmed wms_outbound_orders/lines + 500 real inventory_reservations + 500 unclaimed wms_pick_tasks (the actual claim step is never bulk-seeded -- see this file''s own header)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from load_test_state where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from load_test_state where key = 'warehouse_id');
begin
  -- 100 outbound orders, 5 lines each = 500 lines.
  insert into app.wms_outbound_orders (tenant_id, warehouse_id, owner_account_id, outbound_number, source_type, source_reason, status, created_by)
  select v_tenant1, v_warehouse_id, b.owner_account_id, 'OUT-LOAD-' || lpad(o::text, 5, '0'), 'manual', 'load test seed', 'confirmed', 'loadtest'
  from generate_series(1, 100) o
  join lateral (select owner_account_id from app.inventory_balances where tenant_id = v_tenant1 and item_master_id <> (select hot_item.id from (select id from app.item_masters where code = 'SKU-HOT-CONTENTION') hot_item) order by md5(o::text || id::text) limit 1) b on true;

  insert into app.wms_outbound_order_lines (tenant_id, outbound_order_id, line_number, item_master_id, requested_uom_code, requested_quantity)
  select v_tenant1, oo.id, ln, bal.item_master_id, 'PCS', 10
  from app.wms_outbound_orders oo
  cross join generate_series(1, 5) ln
  join lateral (
    select item_master_id from app.inventory_balances
    where tenant_id = v_tenant1 and owner_account_id = oo.owner_account_id and on_hand >= 20
      and item_master_id <> (select id from app.item_masters where code = 'SKU-HOT-CONTENTION')
    order by md5(oo.id::text || ln::text) limit 1
  ) bal on true
  where oo.tenant_id = v_tenant1 and oo.outbound_number like 'OUT-LOAD-%';

  -- One real reservation per line -- a LATERAL subquery with LIMIT 1 (not a plain
  -- join) since two balance rows exist per item (the earlier ~800-row general
  -- seed step), and a plain join would fan out to two reservation candidates per
  -- line, tripping the (tenant_id, idempotency_key) unique index.
  insert into app.inventory_reservations (tenant_id, balance_id, reserved_quantity, status, source_type, source_id, idempotency_key, created_by)
  select v_tenant1, bal.id, 10, 'active', 'wms_outbound_order', ol.outbound_order_id, 'idem-loadtest-reserve-' || ol.id::text, 'loadtest'
  from app.wms_outbound_order_lines ol
  join app.wms_outbound_orders oo on oo.id = ol.outbound_order_id
  join lateral (
    select id from app.inventory_balances
    where tenant_id = v_tenant1 and owner_account_id = oo.owner_account_id and item_master_id = ol.item_master_id
    order by id limit 1
  ) bal on true
  where oo.outbound_number like 'OUT-LOAD-%';

  -- Multiple lines can land on the same (owner, item) balance row (deterministic
  -- LATERAL pick above) -- on_hand is raised to comfortably cover the SUM of every
  -- reservation against that row (never just incremented), so the reserved+held
  -- <= on_hand invariant holds regardless of how many lines fan into one balance.
  update app.inventory_balances b
  set on_hand = greatest(b.on_hand, sub.total_reserved + 50),
      reserved = sub.total_reserved,
      record_version = record_version + 1
  from (
    select bal.id as balance_id, sum(r.reserved_quantity) as total_reserved
    from app.inventory_reservations r
    join app.inventory_balances bal on bal.id = r.balance_id
    where r.idempotency_key like 'idem-loadtest-reserve-%'
    group by bal.id
  ) sub
  where b.id = sub.balance_id;

  insert into app.wms_pick_tasks (
    tenant_id, warehouse_id, outbound_order_id, outbound_order_line_id, owner_account_id, item_master_id, uom_code,
    source_location_id, reservation_id, task_quantity, status, idempotency_key, created_by
  )
  select v_tenant1, v_warehouse_id, oo.id, ol.id, oo.owner_account_id, ol.item_master_id, 'PCS',
    bal.location_id, r.id, 10, 'unclaimed', 'idem-loadtest-picktask-' || ol.id::text, 'loadtest'
  from app.wms_outbound_order_lines ol
  join app.wms_outbound_orders oo on oo.id = ol.outbound_order_id
  join app.inventory_reservations r on r.idempotency_key = 'idem-loadtest-reserve-' || ol.id::text
  join app.inventory_balances bal on bal.id = r.balance_id
  where oo.outbound_number like 'OUT-LOAD-%';
end $$;

\echo '>> load-test seed: 500 confirmed wms_inbound_orders/committed receipt lines + 500 unclaimed wms_putaway_tasks'
do $$
declare
  v_tenant1 uuid := (select value::uuid from load_test_state where key = 'tenant_id');
  v_warehouse_id uuid := (select value::uuid from load_test_state where key = 'warehouse_id');
begin
  insert into app.wms_inbound_orders (tenant_id, warehouse_id, owner_account_id, inbound_number, source_type, source_reason, status, created_by)
  select v_tenant1, v_warehouse_id, im.owner_account_id, 'IN-LOAD-' || lpad(o::text, 5, '0'), 'manual', 'load test seed', 'confirmed', 'loadtest'
  from generate_series(1, 100) o
  join lateral (select owner_account_id from app.item_masters where tenant_id = v_tenant1 and code <> 'SKU-HOT-CONTENTION' order by md5(o::text || id::text) limit 1) im on true;

  insert into app.wms_inbound_order_lines (tenant_id, inbound_order_id, line_number, item_master_id, expected_uom_code, expected_quantity)
  select v_tenant1, io.id, ln, im.id, 'PCS', 20
  from app.wms_inbound_orders io
  cross join generate_series(1, 5) ln
  join lateral (
    select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = io.owner_account_id and code <> 'SKU-HOT-CONTENTION'
    order by md5(io.id::text || ln::text) limit 1
  ) im on true
  where io.tenant_id = v_tenant1 and io.inbound_number like 'IN-LOAD-%';

  insert into app.wms_receipt_sessions (tenant_id, warehouse_id, inbound_order_id, receiving_location_id, idempotency_key, status, started_by)
  select v_tenant1, v_warehouse_id, io.id, dock.id, 'idem-loadtest-receiptsession-' || io.id::text, 'in_progress', 'loadtest'
  from app.wms_inbound_orders io
  join lateral (select id from app.warehouse_locations where warehouse_id = v_warehouse_id and location_type = 'dock' order by md5(io.id::text) limit 1) dock on true
  where io.inbound_number like 'IN-LOAD-%';

  insert into app.wms_receipt_lines (
    tenant_id, receipt_session_id, inbound_order_line_id, line_number, item_master_id, owner_account_id,
    expected_uom_code, expected_quantity, counted_quantity, accepted_quantity, status
  )
  select v_tenant1, rs.id, iol.id, iol.line_number, iol.item_master_id, io.owner_account_id, 'PCS', 20, 20, 20, 'committed'
  from app.wms_inbound_order_lines iol
  join app.wms_inbound_orders io on io.id = iol.inbound_order_id
  join app.wms_receipt_sessions rs on rs.inbound_order_id = io.id
  where io.inbound_number like 'IN-LOAD-%';

  insert into app.wms_putaway_tasks (
    tenant_id, warehouse_id, receipt_line_id, source_location_id, item_master_id, owner_account_id, uom_code,
    task_quantity, status, idempotency_key, created_by
  )
  select v_tenant1, v_warehouse_id, rl.id, rs.receiving_location_id, rl.item_master_id, rl.owner_account_id, 'PCS',
    rl.accepted_quantity, 'unclaimed', 'idem-loadtest-putawaytask-' || rl.id::text, 'loadtest'
  from app.wms_receipt_lines rl
  join app.wms_receipt_sessions rs on rs.id = rl.receipt_session_id
  where rs.idempotency_key like 'idem-loadtest-receiptsession-%';
end $$;

\echo '>> load-test seed: 5,000 pending app.jobs rows spread across every generic job_type, staggered priority/created_at'
do $$
declare
  v_tenant1 uuid := (select value::uuid from load_test_state where key = 'tenant_id');
  v_job_types text[] := array['report_generation', 'notification_batch', 'webhook_retry', 'document_generation', 'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync'];
begin
  insert into app.jobs (tenant_id, job_type, status, priority, payload, max_attempts, created_by, requested_by_auth_user_id)
  select v_tenant1, v_job_types[1 + (g % array_length(v_job_types, 1))], 'pending', (g % 5), jsonb_build_object('seed_seq', g), 3, 'loadtest', null
  from generate_series(1, 5000) g;
end $$;

\echo '>> load-test seed: 60 vehicles (app.master_records + app.vehicle_operational_profiles) -- volume-completeness only, not directly exercised by a measured scenario this checkpoint (the GPS load scenario uses an in-process TCP simulator, not this seeded database)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from load_test_state where key = 'tenant_id');
begin
  insert into app.master_records (master_type_code, tenant_id, code, name, canonical_status, created_by)
  select 'vehicle', v_tenant1, 'VEH-LOAD-' || lpad(g::text, 4, '0'), 'Load Vehicle ' || g, 'active', 'loadtest'
  from generate_series(1, 60) g;

  insert into app.vehicle_operational_profiles (tenant_id, vehicle_master_id, ownership_type, capacity_weight_kg, capacity_volume_cbm, status, created_by)
  select v_tenant1, mr.id, 'owned', 2000, 20, 'active', 'loadtest'
  from app.master_records mr
  where mr.tenant_id = v_tenant1 and mr.master_type_code = 'vehicle' and mr.code like 'VEH-LOAD-%';
end $$;

\echo '>> load-test seed: 300 lot_identities + 200 serial_identities (ATW-023 pagination EXPLAIN scenario coverage)'
do $$
declare
  v_tenant1 uuid := (select value::uuid from load_test_state where key = 'tenant_id');
  v_account_alpha_id uuid := (select value::uuid from load_test_state where key = 'account_alpha_id');
begin
  insert into app.lot_identities (tenant_id, owner_account_id, item_master_id, lot_number, status, source_type, created_by)
  select v_tenant1, v_account_alpha_id, im.id, 'LOT-LOAD-' || lpad(g::text, 5, '0'), 'active', 'receipt', 'loadtest'
  from generate_series(1, 300) g
  join lateral (select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_alpha_id order by md5(g::text || id::text) limit 1) im on true;

  insert into app.serial_identities (tenant_id, owner_account_id, item_master_id, serial_number, status, source_type, idempotency_key, created_by)
  select v_tenant1, v_account_alpha_id, im.id, 'SN-LOAD-' || lpad(g::text, 5, '0'), 'active', 'receipt', 'idem-loadtest-serial-' || g::text, 'loadtest'
  from generate_series(1, 200) g
  join lateral (select id from app.item_masters where tenant_id = v_tenant1 and owner_account_id = v_account_alpha_id order by md5(g::text || id::text) limit 1) im on true;
end $$;

\echo '>> load-test seed: row-count summary'
select 'tenants' as entity, count(*) from app.tenants where slug = 'loadtest'
union all select 'warehouse_locations', count(*) from app.warehouse_locations wl join app.warehouses w on w.id = wl.warehouse_id join app.tenants t on t.id = w.tenant_id where t.slug = 'loadtest'
union all select 'item_masters', count(*) from app.item_masters im join app.tenants t on t.id = im.tenant_id where t.slug = 'loadtest'
union all select 'inventory_balances', count(*) from app.inventory_balances b join app.tenants t on t.id = b.tenant_id where t.slug = 'loadtest'
union all select 'wms_outbound_orders', count(*) from app.wms_outbound_orders o join app.tenants t on t.id = o.tenant_id where t.slug = 'loadtest'
union all select 'wms_pick_tasks (unclaimed)', count(*) from app.wms_pick_tasks p join app.tenants t on t.id = p.tenant_id where t.slug = 'loadtest' and p.status = 'unclaimed'
union all select 'wms_inbound_orders', count(*) from app.wms_inbound_orders o join app.tenants t on t.id = o.tenant_id where t.slug = 'loadtest'
union all select 'wms_putaway_tasks (unclaimed)', count(*) from app.wms_putaway_tasks p join app.tenants t on t.id = p.tenant_id where t.slug = 'loadtest' and p.status = 'unclaimed'
union all select 'jobs (pending)', count(*) from app.jobs j join app.tenants t on t.id = j.tenant_id where t.slug = 'loadtest' and j.status = 'pending'
union all select 'vehicles', count(*) from app.vehicle_operational_profiles v join app.tenants t on t.id = v.tenant_id where t.slug = 'loadtest'
union all select 'lot_identities', count(*) from app.lot_identities l join app.tenants t on t.id = l.tenant_id where t.slug = 'loadtest'
union all select 'serial_identities', count(*) from app.serial_identities s join app.tenants t on t.id = s.tenant_id where t.slug = 'loadtest';
