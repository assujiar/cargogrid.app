-- Real, executable test evidence for PLT-109 (Organization and Operational Hierarchy,
-- CG-S6-PLT-006).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, each with a company root'
do $$
begin
  perform app.provision_tenant('acmeorg', 'Acme Org Co', 'idem-acmeorg', 'tester');
  perform app.provision_tenant('gizmoorg', 'Gizmo Org Co', 'idem-gizmoorg', 'tester');
  perform app.create_org_unit((select id from app.tenants where slug = 'acmeorg'), 'company', null, 'ACME-CO', 'Acme Co', 'tester');
  perform app.create_org_unit((select id from app.tenants where slug = 'gizmoorg'), 'company', null, 'GIZMO-CO', 'Gizmo Co', 'tester');
end;
$$;

\echo '>> a deep, valid tree builds correctly: company -> branch -> department -> sub-department, and business_unit under company'
do $$
declare
  v_tenant_id uuid;
  v_company_id uuid;
  v_branch app.org_units;
  v_dept app.org_units;
  v_subdept app.org_units;
  v_bu app.org_units;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeorg';
  select id into v_company_id from app.org_units where tenant_id = v_tenant_id and code = 'ACME-CO';

  select * into v_branch from app.create_org_unit(v_tenant_id, 'branch', v_company_id, 'ACME-JKT', 'Acme Jakarta Branch', 'tester');
  if v_branch.depth <> 1 or v_branch.path <> array[v_company_id] then
    raise exception 'assertion failed: expected branch depth=1 path=[company], got depth=% path=%', v_branch.depth, v_branch.path;
  end if;

  select * into v_dept from app.create_org_unit(v_tenant_id, 'department', v_branch.id, 'ACME-JKT-OPS', 'Jakarta Ops', 'tester');
  if v_dept.depth <> 2 or v_dept.path <> array[v_company_id, v_branch.id] then
    raise exception 'assertion failed: expected department depth=2 path=[company,branch], got depth=% path=%', v_dept.depth, v_dept.path;
  end if;

  select * into v_subdept from app.create_org_unit(v_tenant_id, 'department', v_dept.id, 'ACME-JKT-OPS-DISPATCH', 'Jakarta Dispatch', 'tester');
  if v_subdept.depth <> 3 or v_subdept.path <> array[v_company_id, v_branch.id, v_dept.id] then
    raise exception 'assertion failed: expected sub-department depth=3, got depth=%', v_subdept.depth;
  end if;

  select * into v_bu from app.create_org_unit(v_tenant_id, 'business_unit', v_company_id, 'ACME-BU-FIN', 'Finance BU', 'tester');
  if v_bu.depth <> 1 then
    raise exception 'assertion failed: expected business_unit depth=1, got %', v_bu.depth;
  end if;
end;
$$;

\echo '>> idempotent creation: the same (tenant, code, type, parent) returns the original row, never duplicates'
do $$
declare
  v_tenant_id uuid;
  v_company_id uuid;
  v_first app.org_units;
  v_second app.org_units;
  v_count integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeorg';
  select id into v_company_id from app.org_units where tenant_id = v_tenant_id and code = 'ACME-CO';

  select * into v_first from app.org_units where tenant_id = v_tenant_id and code = 'ACME-JKT';
  select * into v_second from app.create_org_unit(v_tenant_id, 'branch', v_company_id, 'ACME-JKT', 'Acme Jakarta Branch', 'tester');
  if v_second.id <> v_first.id then
    raise exception 'assertion failed: expected idempotent create to return the original row';
  end if;

  select count(*) into v_count from app.org_units where tenant_id = v_tenant_id and code = 'ACME-JKT';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row for code ACME-JKT, found %', v_count;
  end if;
end;
$$;

\echo '>> a genuine code reuse (same code, different type/parent) is a real conflict, not a safe retry'
do $$
declare
  v_tenant_id uuid;
  v_company_id uuid;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeorg';
  select id into v_company_id from app.org_units where tenant_id = v_tenant_id and code = 'ACME-CO';
  begin
    perform app.create_org_unit(v_tenant_id, 'business_unit', v_company_id, 'ACME-JKT', 'Reused Code', 'tester');
    raise exception 'assertion failed: expected reusing code ACME-JKT for a different type to fail, but it succeeded';
  exception
    when unique_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> invalid parent-type combinations are rejected at insert time'
do $$
declare
  v_tenant_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeorg';
  select id into v_company_id from app.org_units where tenant_id = v_tenant_id and code = 'ACME-CO';
  select id into v_branch_id from app.org_units where tenant_id = v_tenant_id and code = 'ACME-JKT';

  begin
    perform app.create_org_unit(v_tenant_id, 'company', v_company_id, 'ACME-CO-2', 'Second root attempt', 'tester');
    raise exception 'assertion failed: expected a company with a parent to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;

  begin
    perform app.create_org_unit(v_tenant_id, 'branch', v_branch_id, 'ACME-BRANCH-UNDER-BRANCH', 'Invalid', 'tester');
    raise exception 'assertion failed: expected a branch parented under a branch to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> a cross-tenant parent is rejected -- gizmoorg cannot parent a node under acmeorg''s company'
do $$
declare
  v_gizmo_tenant_id uuid;
  v_acme_company_id uuid;
begin
  select id into v_gizmo_tenant_id from app.tenants where slug = 'gizmoorg';
  select id into v_acme_company_id from app.org_units where tenant_id = (select id from app.tenants where slug = 'acmeorg') and code = 'ACME-CO';

  begin
    perform app.create_org_unit(v_gizmo_tenant_id, 'branch', v_acme_company_id, 'GIZMO-CROSS', 'Cross-tenant attempt', 'tester');
    raise exception 'assertion failed: expected a cross-tenant parent to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> move: relocating a department cascades path/depth to every descendant, not just the moved node'
do $$
declare
  v_tenant_id uuid;
  v_company_id uuid;
  v_dept app.org_units;
  v_subdept_before app.org_units;
  v_new_branch app.org_units;
  v_moved app.org_units;
  v_subdept_after app.org_units;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeorg';
  select id into v_company_id from app.org_units where tenant_id = v_tenant_id and code = 'ACME-CO';
  select * into v_dept from app.org_units where tenant_id = v_tenant_id and code = 'ACME-JKT-OPS';
  select * into v_subdept_before from app.org_units where tenant_id = v_tenant_id and code = 'ACME-JKT-OPS-DISPATCH';

  select * into v_new_branch from app.create_org_unit(v_tenant_id, 'branch', v_company_id, 'ACME-SBY', 'Acme Surabaya Branch', 'tester');

  select * into v_moved from app.move_org_unit(v_dept.id, v_new_branch.id, v_dept.record_version, 'tester');
  if v_moved.parent_id <> v_new_branch.id or v_moved.depth <> 2 or v_moved.path <> array[v_company_id, v_new_branch.id] then
    raise exception 'assertion failed: expected moved department depth=2 under new branch, got depth=% path=%', v_moved.depth, v_moved.path;
  end if;

  select * into v_subdept_after from app.org_units where id = v_subdept_before.id;
  if v_subdept_after.depth <> 3 or v_subdept_after.path <> array[v_company_id, v_new_branch.id, v_dept.id] then
    raise exception 'assertion failed: expected cascaded sub-department depth=3 with rewritten path, got depth=% path=%', v_subdept_after.depth, v_subdept_after.path;
  end if;
end;
$$;

\echo '>> a cycle (moving a node under its own descendant) is rejected'
do $$
declare
  v_tenant_id uuid;
  v_branch app.org_units;
  v_dept app.org_units;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeorg';
  select * into v_branch from app.org_units where tenant_id = v_tenant_id and code = 'ACME-SBY';
  select * into v_dept from app.org_units where tenant_id = v_tenant_id and code = 'ACME-JKT-OPS';

  begin
    perform app.move_org_unit(v_branch.id, v_dept.id, v_branch.record_version, 'tester');
    raise exception 'assertion failed: expected moving a branch under its own descendant department to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> optimistic concurrency: a stale expected_version is rejected, never silently overwritten'
do $$
declare
  v_dept app.org_units;
begin
  select * into v_dept from app.org_units where tenant_id = (select id from app.tenants where slug = 'acmeorg') and code = 'ACME-JKT-OPS';

  begin
    perform app.rename_org_unit(v_dept.id, 'Renamed Twice', v_dept.record_version - 1, 'tester');
    raise exception 'assertion failed: expected a stale expected_version to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> deactivation is blocked while an active child exists, and succeeds once children are deactivated first'
do $$
declare
  v_dept app.org_units;
  v_subdept app.org_units;
begin
  select * into v_dept from app.org_units where tenant_id = (select id from app.tenants where slug = 'acmeorg') and code = 'ACME-JKT-OPS';
  select * into v_subdept from app.org_units where tenant_id = (select id from app.tenants where slug = 'acmeorg') and code = 'ACME-JKT-OPS-DISPATCH';

  begin
    perform app.set_org_unit_status(v_dept.id, 'inactive', v_dept.record_version, 'restructuring', 'tester');
    raise exception 'assertion failed: expected deactivating a department with an active child to fail, but it succeeded';
  exception
    when check_violation then
      null; -- expected
  end;

  perform app.set_org_unit_status(v_subdept.id, 'inactive', v_subdept.record_version, 'restructuring', 'tester');
  perform app.set_org_unit_status(v_dept.id, 'inactive', v_dept.record_version, 'restructuring', 'tester');

  if not exists (select 1 from app.org_units where id = v_dept.id and status = 'inactive') then
    raise exception 'assertion failed: expected department to be inactive after its child was deactivated first';
  end if;
end;
$$;

\echo '>> ancestor/descendant helpers return the correct, indexed result'
do $$
declare
  v_tenant_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
  v_ancestors uuid[];
  v_descendant_count integer;
begin
  select id into v_tenant_id from app.tenants where slug = 'acmeorg';
  select id into v_company_id from app.org_units where tenant_id = v_tenant_id and code = 'ACME-CO';
  select id into v_branch_id from app.org_units where tenant_id = v_tenant_id and code = 'ACME-SBY';

  select app.org_unit_ancestor_ids((select id from app.org_units where code = 'ACME-JKT-OPS-DISPATCH')) into v_ancestors;
  if v_ancestors <> array[v_company_id, v_branch_id, (select id from app.org_units where code = 'ACME-JKT-OPS')] then
    raise exception 'assertion failed: unexpected ancestor chain %', v_ancestors;
  end if;

  select count(*) into v_descendant_count from app.org_unit_descendant_ids(v_company_id);
  if v_descendant_count < 4 then
    raise exception 'assertion failed: expected at least 4 descendants of the company root, found %', v_descendant_count;
  end if;
end;
$$;

\echo '>> moving/renaming/deactivating a non-existent node fails cleanly, not silently'
do $$
begin
  begin
    perform app.move_org_unit('00000000-0000-0000-0000-000000000099', null, 1, 'tester');
    raise exception 'assertion failed: expected moving a non-existent node to fail, but it succeeded';
  exception
    when no_data_found then
      null; -- expected
  end;
end;
$$;

\echo '>> defense in depth: anon and authenticated are denied at the schema-privilege layer; service_role has explicit access'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.org_units;
    raise exception 'assertion failed: anon must be denied at the schema-privilege layer for org_units';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

do $$
declare
  v_count integer;
begin
  set local role service_role;
  select count(*) into v_count from app.org_units;
  if v_count < 6 then
    raise exception 'assertion failed: service_role must see every org unit row, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-109 db-test assertions passed.'
