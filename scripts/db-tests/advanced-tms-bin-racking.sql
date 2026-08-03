-- Real, executable test evidence for ATW-230 (CG-S10-ATW-011, Prompt 230 Bin and
-- Racking) -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants. Tenant1 (acmerack): a company org unit, a rep (OPS:Create/Edit/View), an OPS:View-only viewer, warehouse WH-A (active, one active zone ZONE-ACTIVE, one on_hold zone ZONE-HOLD) and warehouse WH-B (active, no zones) -- both via the already-VERIFIED ATW-229 RPCs. Tenant2 (acmerack2): an isolated rep for cross-tenant leakage checks. A global Supreme Admin.'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_rep2_role uuid;
  v_rep2_draft app.role_versions;
  v_wh_a app.warehouses;
  v_wh_b app.warehouses;
  v_zone_active app.warehouse_zones;
  v_zone_hold app.warehouse_zones;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000071101', 'admin@acmerack.test'),
    ('00000000-0000-0000-0000-000000071102', 'rep@acmerack.test'),
    ('00000000-0000-0000-0000-000000071103', 'viewer@acmerack.test'),
    ('00000000-0000-0000-0000-000000071104', 'supreme@acmerack.test'),
    ('00000000-0000-0000-0000-000000071105', 'rep2@acmerack2.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000071104', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmerack', 'Acme Rack Co', 'idem-acmerack', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmerack');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMERACK-CO', 'Acme Rack Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMERACK-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000071101', 'admin@acmerack.test', 'Rack Admin', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmerack.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000071101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000071102', 'rep@acmerack.test', 'Rack Rep', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmerack.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000071103', 'viewer@acmerack.test', 'Rack Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmerack.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Rack Rep Role', 'OPS create/edit/view', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(v_rep_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000071102', '00000000-0000-0000-0000-000000071101', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000071101', '00000000-0000-0000-0000-000000071101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Rack Viewer Role', 'OPS:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000071103', '00000000-0000-0000-0000-000000071101', 'tester');

  v_wh_a := app.create_warehouse(v_tenant1, v_company, 'WH-A', 'Warehouse A', 'Jl. Rack 1', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000071102', 'rep');
  v_wh_b := app.create_warehouse(v_tenant1, v_company, 'WH-B', 'Warehouse B', 'Jl. Rack 2', 'Asia/Jakarta', null, array['land']::text[], '00000000-0000-0000-0000-000000071102', 'rep');

  v_zone_active := app.create_warehouse_zone(v_wh_a.id, 'ZONE-ACTIVE', 'Active Zone', 'ambient', null, null, null, null, null, null, '00000000-0000-0000-0000-000000071102', 'rep');
  v_zone_hold := app.create_warehouse_zone(v_wh_a.id, 'ZONE-HOLD', 'On-Hold Zone', 'ambient', null, null, null, null, null, null, '00000000-0000-0000-0000-000000071102', 'rep');
  perform app.set_warehouse_zone_status(v_zone_hold.id, 'on_hold', 'not ready yet', v_zone_hold.record_version, '00000000-0000-0000-0000-000000071102', 'rep');

  perform app.provision_tenant('acmerack2', 'Acme Rack Two', 'idem-acmerack2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmerack2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMERACK2-CO', 'Acme Rack Two', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000071105', 'rep2@acmerack2.test', 'Tenant2 Rep', (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMERACK2-CO'), 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep2@acmerack2.test'), 'active', 'onboarded', 'tester');
  v_rep2_role := (app.create_role(v_tenant2, 'Tenant2 Rep Role', 'OPS create/edit/view', 'tester')).id;
  v_rep2_draft := app.create_role_version(v_rep2_role, 'tester');
  perform app.set_role_version_permissions(v_rep2_draft.id, array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')), 'tester');
  perform app.publish_role_version(v_rep2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep2_role and status = 'published'), '00000000-0000-0000-0000-000000071105', '00000000-0000-0000-0000-000000071105', 'tester');
end $$;

\echo '>> app.create_warehouse_location: OPS:View-only viewer rejected; rep succeeds creating a root rack (RACK-A) against the active zone; idempotent replay; duplicate code with a different type conflicts; a nested SHELF-A1/BIN-A1-1 chain computes path/depth correctly; a root-level dock (no rack, no zone) is allowed'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_wh_a_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-A');
  v_zone_active_id uuid := (select id from app.warehouse_zones where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'ZONE-ACTIVE');
  v_rack app.warehouse_locations;
  v_replay app.warehouse_locations;
  v_shelf app.warehouse_locations;
  v_bin app.warehouse_locations;
  v_dock app.warehouse_locations;
begin
  begin
    perform app.create_warehouse_location(v_wh_a_id, v_zone_active_id, null, 'RACK-A', 'Rack A', 'rack', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071103', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority -- viewer holds OPS:View only';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_rack := app.create_warehouse_location(v_wh_a_id, v_zone_active_id, null, 'RACK-A', 'Rack A', 'rack', 1, null, null, null, null, 'BC-RACK-A', false, false, '00000000-0000-0000-0000-000000071102', 'rep');
  if v_rack.status <> 'draft' or v_rack.depth <> 0 or v_rack.path <> '{}'::uuid[] then
    raise exception 'assertion failed: expected a draft root rack at depth 0 with an empty path, got status=% depth=% path=%', v_rack.status, v_rack.depth, v_rack.path;
  end if;

  v_replay := app.create_warehouse_location(v_wh_a_id, v_zone_active_id, null, 'RACK-A', 'Rack A (retry)', 'rack', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');
  if v_replay.id <> v_rack.id or v_replay.name <> 'Rack A' then
    raise exception 'assertion failed: expected the same-code replay to return the identical, unchanged row';
  end if;

  begin
    perform app.create_warehouse_location(v_wh_a_id, v_zone_active_id, null, 'RACK-A', 'Conflicting', 'shelf', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected location_code_conflict -- RACK-A already exists with location_type=rack';
  exception
    when others then
      if sqlerrm not like 'location_code_conflict%' then raise; end if;
  end;

  v_shelf := app.create_warehouse_location(v_wh_a_id, v_zone_active_id, v_rack.id, 'SHELF-A1', 'Shelf A1', 'shelf', 1, null, null, null, null, null, false, true, '00000000-0000-0000-0000-000000071102', 'rep');
  if v_shelf.depth <> 1 or v_shelf.path <> array[v_rack.id] then
    raise exception 'assertion failed: expected shelf depth=1, path=[rack], got depth=% path=%', v_shelf.depth, v_shelf.path;
  end if;

  v_bin := app.create_warehouse_location(v_wh_a_id, v_zone_active_id, v_shelf.id, 'BIN-A1-1', 'Bin A1-1', 'bin', 1, 50, 'units', null, null, 'BC-BIN-A1-1', true, true, '00000000-0000-0000-0000-000000071102', 'rep');
  if v_bin.depth <> 2 or v_bin.path <> array[v_rack.id, v_shelf.id] then
    raise exception 'assertion failed: expected bin depth=2, path=[rack, shelf], got depth=% path=%', v_bin.depth, v_bin.path;
  end if;
  if v_bin.capacity_value <> 50 or v_bin.capacity_uom <> 'units' or not v_bin.pick_enabled or not v_bin.putaway_enabled then
    raise exception 'assertion failed: expected bin capacity/pick/putaway flags to be stored as given';
  end if;

  v_dock := app.create_warehouse_location(v_wh_a_id, null, null, 'DOCK-1', 'Dock 1', 'dock', 1, null, null, null, null, null, false, true, '00000000-0000-0000-0000-000000071102', 'rep');
  if v_dock.zone_id is not null or v_dock.parent_id is not null or v_dock.depth <> 0 then
    raise exception 'assertion failed: expected a root dock with no zone/parent (floor/staging/dock without rack alt flow)';
  end if;
end $$;

\echo '>> app.create_warehouse_location exception flows: incompatible zone (inactive, or belonging to a different warehouse), cross-warehouse parent, invalid capacity pairing, and duplicate barcode are all blocked'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_wh_a_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-A');
  v_wh_b_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-B');
  v_zone_hold_id uuid := (select id from app.warehouse_zones where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'ZONE-HOLD');
  v_rack_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'RACK-A');
begin
  begin
    perform app.create_warehouse_location(v_wh_a_id, v_zone_hold_id, null, 'BAD-ZONE', 'Bad zone', 'rack', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected incompatible_zone -- ZONE-HOLD is on_hold, not active';
  exception
    when others then
      if sqlerrm not like 'incompatible_zone%' then raise; end if;
  end;

  begin
    perform app.create_warehouse_location(v_wh_b_id, (select id from app.warehouse_zones where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'ZONE-ACTIVE'), null, 'BAD-ZONE-2', 'Bad zone 2', 'rack', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected incompatible_zone -- ZONE-ACTIVE belongs to WH-A, not WH-B';
  exception
    when others then
      if sqlerrm not like 'incompatible_zone%' then raise; end if;
  end;

  begin
    perform app.create_warehouse_location(v_wh_b_id, null, v_rack_id, 'BAD-PARENT', 'Bad parent', 'shelf', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected cross_warehouse_parent -- RACK-A belongs to WH-A, not WH-B';
  exception
    when others then
      if sqlerrm not like 'cross_warehouse_parent%' then raise; end if;
  end;

  begin
    perform app.create_warehouse_location(v_wh_a_id, null, null, 'BAD-CAP', 'Bad capacity', 'bin', 1, 10, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected invalid_capacity -- capacity_value without capacity_uom';
  exception
    when others then
      if sqlerrm not like 'invalid_capacity%' then raise; end if;
  end;

  begin
    perform app.create_warehouse_location(v_wh_a_id, null, null, 'BAD-BARCODE', 'Bad barcode', 'bin', 1, null, null, null, null, 'BC-RACK-A', false, false, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected duplicate_barcode -- BC-RACK-A is already assigned to RACK-A';
  exception
    when others then
      if sqlerrm not like 'duplicate_barcode%' then raise; end if;
  end;
end $$;

\echo '>> depth-bounded hierarchy: a chain reaching the governed maximum depth (8) is allowed; one level deeper is rejected with warehouse_location_depth_exceeded'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_wh_a_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-A');
  v_current app.warehouse_locations;
  v_i integer;
begin
  v_current := app.create_warehouse_location(v_wh_a_id, null, null, 'DEEP-0', 'Deep 0', 'rack', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');
  for v_i in 1..8 loop
    v_current := app.create_warehouse_location(v_wh_a_id, null, v_current.id, 'DEEP-' || v_i, 'Deep ' || v_i, 'shelf', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');
  end loop;
  if v_current.depth <> 8 then
    raise exception 'assertion failed: expected the 9th node (DEEP-8) to sit at depth 8 (the governed maximum), got %', v_current.depth;
  end if;

  begin
    perform app.create_warehouse_location(v_wh_a_id, null, v_current.id, 'DEEP-9', 'Deep 9', 'bin', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected warehouse_location_depth_exceeded -- depth 9 exceeds the governed maximum of 8';
  exception
    when others then
      if sqlerrm not like 'warehouse_location_depth_exceeded%' then raise; end if;
  end;
end $$;

\echo '>> app.update_warehouse_location: stale version rejected; mutable fields update; a barcode collision with another location is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_wh_a_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-A');
  v_bin app.warehouse_locations;
begin
  select * into v_bin from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'BIN-A1-1';

  begin
    perform app.update_warehouse_location(v_bin.id, 'Bin A1-1', 1, 50, 'units', null, null, null, true, true, v_bin.record_version + 99, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then raise; end if;
  end;

  begin
    perform app.update_warehouse_location(v_bin.id, 'Bin A1-1', 1, 50, 'units', null, null, 'BC-RACK-A', true, true, v_bin.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected duplicate_barcode -- BC-RACK-A already belongs to RACK-A';
  exception
    when others then
      if sqlerrm not like 'duplicate_barcode%' then raise; end if;
  end;

  v_bin := app.update_warehouse_location(v_bin.id, 'Bin A1-1 (expanded)', 2, 100, 'units', jsonb_build_object('humidity_controlled', true), null, 'BC-BIN-A1-1-V2', true, true, v_bin.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
  if v_bin.name <> 'Bin A1-1 (expanded)' or v_bin.capacity_value <> 100 or v_bin.barcode <> 'BC-BIN-A1-1-V2' then
    raise exception 'assertion failed: expected the mutable fields to reflect the update';
  end if;
end $$;

\echo '>> app.move_warehouse_location: only a draft location may move; a cross-warehouse move and a cycle are both rejected; a legal move cascades path/depth to every descendant'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_wh_a_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-A');
  v_wh_b_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-B');
  v_rack app.warehouse_locations;
  v_dock app.warehouse_locations;
  v_shelf app.warehouse_locations;
  v_bin app.warehouse_locations;
  v_whb_root app.warehouse_locations;
  v_moved app.warehouse_locations;
begin
  select * into v_rack from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'RACK-A';
  select * into v_dock from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'DOCK-1';
  select * into v_shelf from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'SHELF-A1';
  select * into v_bin from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'BIN-A1-1';
  v_whb_root := app.create_warehouse_location(v_wh_b_id, null, null, 'WHB-ROOT', 'WH-B Root', 'floor', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071102', 'rep');

  perform app.set_warehouse_location_status(v_rack.id, 'active', null, v_rack.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
  begin
    perform app.move_warehouse_location(v_rack.id, v_dock.id, v_rack.record_version + 1, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected location_not_draft -- RACK-A was just activated';
  exception
    when others then
      if sqlerrm not like 'location_not_draft%' then raise; end if;
  end;

  begin
    perform app.move_warehouse_location(v_shelf.id, v_whb_root.id, v_shelf.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected cross_warehouse_parent -- WHB-ROOT belongs to WH-B, not WH-A';
  exception
    when others then
      if sqlerrm not like 'cross_warehouse_parent%' then raise; end if;
  end;

  begin
    perform app.move_warehouse_location(v_shelf.id, v_bin.id, v_shelf.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected warehouse_location_cycle -- BIN-A1-1 is SHELF-A1''s own descendant';
  exception
    when others then
      if sqlerrm not like 'warehouse_location_cycle%' then raise; end if;
  end;

  v_moved := app.move_warehouse_location(v_shelf.id, v_dock.id, v_shelf.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
  if v_moved.parent_id <> v_dock.id or v_moved.depth <> 1 or v_moved.path <> array[v_dock.id] then
    raise exception 'assertion failed: expected SHELF-A1 to move under DOCK-1 at depth 1, got parent=% depth=% path=%', v_moved.parent_id, v_moved.depth, v_moved.path;
  end if;

  select * into v_bin from app.warehouse_locations where id = v_bin.id;
  if v_bin.depth <> 2 or v_bin.path <> array[v_dock.id, v_shelf.id] then
    raise exception 'assertion failed: expected BIN-A1-1''s own path/depth to cascade to [dock, shelf]/2 after its parent SHELF-A1 moved, got path=% depth=%', v_bin.path, v_bin.depth;
  end if;
end $$;

\echo '>> app.set_warehouse_location_status / app.get_warehouse_location_deactivation_impact: activation requires an active warehouse; deactivation requires a reason and is blocked while draft/active children exist; the impact preview matches exactly what the mutation blocks on'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_wh_a_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-A');
  v_dock app.warehouse_locations;
  v_impact app.warehouse_location_deactivation_impact;
begin
  select * into v_dock from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'DOCK-1';

  select * into v_impact from app.get_warehouse_location_deactivation_impact(v_dock.id, '00000000-0000-0000-0000-000000071102');
  if v_impact.draft_child_count < 1 then
    raise exception 'assertion failed: expected DOCK-1 to have at least 1 draft child (SHELF-A1, moved under it), got %', v_impact.draft_child_count;
  end if;

  begin
    perform app.set_warehouse_location_status(v_dock.id, 'inactive', 'no longer needed', v_dock.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected location_has_active_children';
  exception
    when others then
      if sqlerrm not like 'location_has_active_children%' then raise; end if;
  end;

  begin
    perform app.set_warehouse_location_status(v_dock.id, 'inactive', null, v_dock.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected reason_required';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then raise; end if;
  end;
end $$;

\echo '>> app.list_warehouse_locations: root nodes only when parent_id is null; children of a specific parent; status filter; cross-tenant rep sees zero'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_wh_a_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-A');
  v_dock_id uuid := (select id from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'DOCK-1');
  v_count integer;
begin
  select count(*) into v_count from app.list_warehouse_locations(v_wh_a_id, '00000000-0000-0000-0000-000000071102', null, null);
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 root locations (RACK-A, DOCK-1, DEEP-0), got %', v_count;
  end if;

  select count(*) into v_count from app.list_warehouse_locations(v_wh_a_id, '00000000-0000-0000-0000-000000071102', v_dock_id, null);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 child under DOCK-1 (SHELF-A1, moved there), got %', v_count;
  end if;

  begin
    perform app.list_warehouse_locations(v_wh_a_id, '00000000-0000-0000-0000-000000071105', null, null);
    raise exception 'assertion failed: expected insufficient_authority -- acmerack2''s rep2 has no membership in acmerack';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> app.resolve_warehouse_location_by_barcode: resolves a known barcode to its location; an unknown barcode is honestly not_found; a foreign-tenant actor is rejected'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_resolved app.warehouse_locations;
begin
  v_resolved := app.resolve_warehouse_location_by_barcode(v_tenant1, 'BC-RACK-A', '00000000-0000-0000-0000-000000071102');
  if v_resolved.code <> 'RACK-A' then
    raise exception 'assertion failed: expected BC-RACK-A to resolve to RACK-A, got %', v_resolved.code;
  end if;

  begin
    perform app.resolve_warehouse_location_by_barcode(v_tenant1, 'BC-DOES-NOT-EXIST', '00000000-0000-0000-0000-000000071102');
    raise exception 'assertion failed: expected location_not_found for an unknown barcode';
  exception
    when others then
      if sqlerrm not like 'location_not_found%' then raise; end if;
  end;

  begin
    perform app.resolve_warehouse_location_by_barcode(v_tenant1, 'BC-RACK-A', '00000000-0000-0000-0000-000000071105');
    raise exception 'assertion failed: expected insufficient_authority -- acmerack2''s rep2 has no membership in acmerack';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> cross-tenant isolation: tenant2''s rep cannot create/mutate a location under tenant1''s warehouse'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_wh_a_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-A');
begin
  begin
    perform app.create_warehouse_location(v_wh_a_id, null, null, 'HIJACK', 'Hijack', 'rack', 1, null, null, null, null, null, false, false, '00000000-0000-0000-0000-000000071105', 'rep2');
    raise exception 'assertion failed: expected insufficient_authority -- acmerack2''s rep2 has no membership in acmerack';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> hardening (inserted alongside ATW-011A): app.set_warehouse_zone_status/app.set_warehouse_status now block deactivation while draft/active app.warehouse_locations still reference them -- ZONE-ACTIVE still has an active child (RACK-A) and WH-B still has a draft root location (WHB-ROOT) from earlier in this fixture, so both guards are exercised against real, already-existing dependents, not a fabricated new fixture'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmerack');
  v_wh_a_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-A');
  v_wh_b_id uuid := (select id from app.warehouses where tenant_id = v_tenant1 and code = 'WH-B');
  v_zone_active_id uuid := (select id from app.warehouse_zones where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'ZONE-ACTIVE');
  v_rack app.warehouse_locations;
  v_shelf app.warehouse_locations;
  v_bin app.warehouse_locations;
  v_whb_root app.warehouse_locations;
  v_zone app.warehouse_zones;
  v_wh app.warehouses;
begin
  select * into v_rack from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'RACK-A';
  select * into v_shelf from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'SHELF-A1';
  select * into v_bin from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_a_id and code = 'BIN-A1-1';
  select * into v_whb_root from app.warehouse_locations where tenant_id = v_tenant1 and warehouse_id = v_wh_b_id and code = 'WHB-ROOT';
  if v_rack.status <> 'active' or v_shelf.status <> 'draft' or v_bin.status <> 'draft' or v_whb_root.status <> 'draft' then
    raise exception 'assertion failed: fixture precondition -- expected RACK-A active, SHELF-A1/BIN-A1-1/WHB-ROOT draft going into the hardening test, got RACK-A=%/SHELF-A1=%/BIN-A1-1=%/WHB-ROOT=%', v_rack.status, v_shelf.status, v_bin.status, v_whb_root.status;
  end if;
  -- SHELF-A1/BIN-A1-1 were moved under DOCK-1 earlier in this file, but a move never
  -- changes zone_id (confirmed by direct inspection of app.move_warehouse_location) --
  -- both still reference ZONE-ACTIVE, so the zone's own dependent count is 3
  -- (RACK-A + SHELF-A1 + BIN-A1-1), not just the one obviously-still-attached RACK-A.
  if v_shelf.zone_id <> v_zone_active_id or v_bin.zone_id <> v_zone_active_id then
    raise exception 'assertion failed: fixture precondition -- expected SHELF-A1/BIN-A1-1 to still carry zone_id=ZONE-ACTIVE after their earlier move to a new parent';
  end if;

  select * into v_zone from app.warehouse_zones where id = v_zone_active_id;
  begin
    perform app.set_warehouse_zone_status(v_zone_active_id, 'inactive', 'attempting to deactivate', v_zone.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected zone_has_active_locations -- ZONE-ACTIVE still has 3 draft/active dependents (RACK-A/SHELF-A1/BIN-A1-1)';
  exception
    when others then
      if sqlerrm not like 'zone_has_active_locations%' then raise; end if;
  end;

  select * into v_wh from app.warehouses where id = v_wh_b_id;
  begin
    perform app.set_warehouse_status(v_wh_b_id, 'inactive', 'attempting to deactivate', v_wh.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
    raise exception 'assertion failed: expected warehouse_has_active_locations -- WH-B still has draft root location WHB-ROOT (no zone)';
  exception
    when others then
      if sqlerrm not like 'warehouse_has_active_locations%' then raise; end if;
  end;

  -- Wind every dependent down (leaf-first: BIN-A1-1, then its parent SHELF-A1, then
  -- the standalone RACK-A), then confirm the guard reopens exactly like
  -- app.warehouse_zones'/app.warehouses' own pre-existing zone-count guards do.
  perform app.set_warehouse_location_status(v_bin.id, 'inactive', 'wound down for hardening test', v_bin.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
  select * into v_shelf from app.warehouse_locations where id = v_shelf.id;
  perform app.set_warehouse_location_status(v_shelf.id, 'inactive', 'wound down for hardening test', v_shelf.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
  perform app.set_warehouse_location_status(v_rack.id, 'inactive', 'wound down for hardening test', v_rack.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
  select * into v_zone from app.warehouse_zones where id = v_zone_active_id;
  v_zone := app.set_warehouse_zone_status(v_zone_active_id, 'inactive', 'no active locations remain', v_zone.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
  if v_zone.status <> 'inactive' then
    raise exception 'assertion failed: expected ZONE-ACTIVE to deactivate once every dependent location was wound down';
  end if;

  perform app.set_warehouse_location_status(v_whb_root.id, 'inactive', 'wound down for hardening test', v_whb_root.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
  select * into v_wh from app.warehouses where id = v_wh_b_id;
  v_wh := app.set_warehouse_status(v_wh_b_id, 'inactive', 'no active locations remain', v_wh.record_version, '00000000-0000-0000-0000-000000071102', 'rep');
  if v_wh.status <> 'inactive' then
    raise exception 'assertion failed: expected WH-B to deactivate once WHB-ROOT was wound down';
  end if;
end $$;

\echo '>> schema-privilege defense in depth (ERR-2026-004): anon holds no direct table/EXECUTE access; authenticated has RLS-scoped SELECT but no direct INSERT/UPDATE/DELETE; only service_role may write directly'
do $$
begin
  if has_table_privilege('anon', 'app.warehouse_locations', 'SELECT') then
    raise exception 'assertion failed: anon must not have direct SELECT on app.warehouse_locations';
  end if;
  if has_function_privilege('anon', 'app.create_warehouse_location(uuid, uuid, uuid, text, text, text, integer, numeric, text, jsonb, jsonb, text, boolean, boolean, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: anon must not have EXECUTE on app.create_warehouse_location';
  end if;
  if not has_table_privilege('authenticated', 'app.warehouse_locations', 'SELECT') then
    raise exception 'assertion failed: authenticated must have RLS-scoped SELECT on app.warehouse_locations';
  end if;
  if has_table_privilege('authenticated', 'app.warehouse_locations', 'INSERT') then
    raise exception 'assertion failed: authenticated must not have direct INSERT on app.warehouse_locations -- mutation must go through the SECURITY DEFINER RPCs only';
  end if;
  if not has_table_privilege('service_role', 'app.warehouse_locations', 'INSERT') then
    raise exception 'assertion failed: service_role must retain direct table access';
  end if;
end $$;
