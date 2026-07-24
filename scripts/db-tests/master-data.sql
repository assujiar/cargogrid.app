-- Real, executable test evidence for PLT-120 (Master Data Foundation, CG-S6-PLT-017).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001201', 'tenantadminmdm@example.test'),
    ('00000000-0000-0000-0000-000000001202', 'regularusermdm@example.test'),
    ('00000000-0000-0000-0000-000000001203', 'suprememdm@example.test'),
    ('00000000-0000-0000-0000-000000001204', 'othertenantadminmdm@example.test');

  perform app.provision_tenant('acmemdm', 'Acme Master Data Co', 'idem-acmemdm', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001201', 'tenantadminmdm@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminmdm@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001201', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001202', 'regularusermdm@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularusermdm@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001202', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001203', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmomdm', 'Gizmo Master Data Co', 'idem-gizmomdm', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmomdm');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001204', 'othertenantadminmdm@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminmdm@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001204', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.master_types: vendor_rate is seeded (sourced from 05_DATABASE_SCHEMA_WORKSTREAM.md §4/§11); app.register_master_type is idempotent and Supreme-Admin-only'
do $$
declare
  v_seeded app.master_types;
  v_registered1 app.master_types;
  v_registered2 app.master_types;
begin
  select * into v_seeded from app.master_types where code = 'vendor_rate';
  if v_seeded.scope <> 'tenant' or v_seeded.owner_module_code <> 'PRC' then
    raise exception 'assertion failed: expected the seeded vendor_rate type to be tenant-scoped, owned by PRC';
  end if;

  begin
    perform app.register_master_type('some_type', 'Some Type', 'global', null, '00000000-0000-0000-0000-000000001201', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering a master type';
  exception
    when insufficient_privilege then
      null;
  end;

  v_registered1 := app.register_master_type('cargo_type', 'Cargo Type', 'global', null, '00000000-0000-0000-0000-000000001203', 'supreme admin');
  v_registered2 := app.register_master_type('cargo_type', 'Cargo Type', 'global', null, '00000000-0000-0000-0000-000000001203', 'supreme admin');
  if v_registered1.code <> v_registered2.code then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;
end;
$$;

\echo '>> app.master_records CHECK/trigger validation: scope mismatch, unsafe attributes, unsafe aliases are all rejected structurally'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');

  begin
    insert into app.master_records (master_type_code, tenant_id, code, name) values ('vendor_rate', null, 'X-1', 'X');
    raise exception 'assertion failed: expected a tenant-scoped type with a null tenant_id to be rejected';
  exception
    when foreign_key_violation then
      raise exception 'assertion failed: unexpected foreign_key_violation instead of scope check_violation';
    when check_violation then
      null;
  end;

  begin
    insert into app.master_records (master_type_code, tenant_id, code, name) values ('cargo_type', v_tenant_id, 'X-2', 'X');
    raise exception 'assertion failed: expected a global-scoped type with a non-null tenant_id to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.master_records (master_type_code, tenant_id, code, name) values ('nonexistent_type', v_tenant_id, 'X-3', 'X');
    raise exception 'assertion failed: expected an unregistered master_type_code to be rejected';
  exception
    when foreign_key_violation then
      null;
  end;

  begin
    insert into app.master_records (master_type_code, tenant_id, code, name, attributes)
    values ('vendor_rate', v_tenant_id, 'X-4', 'X', '{"note": "<script>alert(1)</script>"}'::jsonb);
    raise exception 'assertion failed: expected an angle-bracket attribute value to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.master_records (master_type_code, tenant_id, code, name, aliases)
    values ('vendor_rate', v_tenant_id, 'X-5', 'X', '["<b>alias</b>"]'::jsonb);
    raise exception 'assertion failed: expected an angle-bracket alias to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.create_master_record: idempotent, authority-gated per scope (Supreme for global, tenant_admin/Supreme for tenant-scoped)'
do $$
declare
  v_tenant_id uuid;
  v_record1 app.master_records;
  v_record2 app.master_records;
  v_global_record app.master_records;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');

  begin
    perform app.create_master_record('vendor_rate', v_tenant_id, 'VR-001', 'Sea Freight FCL', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000001202', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied';
  exception
    when insufficient_privilege then
      null;
  end;

  v_record1 := app.create_master_record('vendor_rate', v_tenant_id, 'VR-001', 'Sea Freight FCL', '["Ocean FCL"]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000001201', 'tenant admin');
  if v_record1.canonical_status <> 'active' or v_record1.tenant_id <> v_tenant_id then
    raise exception 'assertion failed: expected a fresh active tenant-scoped record';
  end if;

  v_record2 := app.create_master_record('vendor_rate', v_tenant_id, 'VR-001', 'Sea Freight FCL', '["Ocean FCL"]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000001201', 'tenant admin');
  if v_record2.id <> v_record1.id then
    raise exception 'assertion failed: expected a repeated create to return the same existing record, not a duplicate';
  end if;

  begin
    perform app.create_master_record('cargo_type', null, 'CT-001', 'Dry Van', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000001201', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied creating a global-scoped record';
  exception
    when insufficient_privilege then
      null;
  end;

  v_global_record := app.create_master_record('cargo_type', null, 'CT-001', 'Dry Van', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000001203', 'supreme admin');
  if v_global_record.tenant_id is not null then
    raise exception 'assertion failed: expected the global-scoped record to have tenant_id=null';
  end if;
end;
$$;

\echo '>> uniqueness: the same code is rejected for the same (type, tenant) as a real unique-index violation, but the identical code is independently claimable by a different tenant'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_cross_tenant_record app.master_records;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmomdm');

  begin
    insert into app.master_records (master_type_code, tenant_id, code, name) values ('vendor_rate', v_tenant_id, 'VR-001', 'A Duplicate');
    raise exception 'assertion failed: expected a duplicate (type, tenant, code) to violate the unique index';
  exception
    when unique_violation then
      null;
  end;

  -- The identical code string is independently valid for a different tenant -- tenant
  -- isolation, not a global namespace collision.
  v_cross_tenant_record := app.create_master_record('vendor_rate', v_other_tenant_id, 'VR-001', 'Gizmo''s Own VR-001', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000001204', 'other tenant admin');
  if v_cross_tenant_record.tenant_id <> v_other_tenant_id then
    raise exception 'assertion failed: expected the cross-tenant record to belong to gizmomdm';
  end if;
end;
$$;

\echo '>> app.update_master_record: optimistic concurrency rejects a stale expected_version; only an active record may be updated'
do $$
declare
  v_tenant_id uuid;
  v_record app.master_records;
  v_updated app.master_records;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');
  select * into v_record from app.master_records where tenant_id = v_tenant_id and code = 'VR-001';

  v_updated := app.update_master_record(v_record.id, v_record.record_version, 'Sea Freight FCL (Updated)', null, '{"uom": "TEU"}'::jsonb, '00000000-0000-0000-0000-000000001201', 'tenant admin');
  if v_updated.name <> 'Sea Freight FCL (Updated)' or v_updated.attributes ->> 'uom' <> 'TEU' then
    raise exception 'assertion failed: expected the name/attributes to update';
  end if;

  begin
    perform app.update_master_record(v_record.id, v_record.record_version, 'Stale Update', null, null, '00000000-0000-0000-0000-000000001201', 'tenant admin');
    raise exception 'assertion failed: expected a stale expected_version to be rejected, never silently overwritten';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.update_master_record(v_record.id, v_updated.record_version, 'x', null, null, '00000000-0000-0000-0000-000000001202', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> app.deactivate_master_record: active -> deactivated; only an active record may be deactivated'
do $$
declare
  v_tenant_id uuid;
  v_record app.master_records;
  v_deactivated app.master_records;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');
  v_record := app.create_master_record('vendor_rate', v_tenant_id, 'VR-002', 'Air Freight Express', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000001201', 'tenant admin');

  v_deactivated := app.deactivate_master_record(v_record.id, '00000000-0000-0000-0000-000000001201', 'no longer offered', 'tenant admin');
  if v_deactivated.canonical_status <> 'deactivated' or v_deactivated.deactivated_reason <> 'no longer offered' then
    raise exception 'assertion failed: expected the record to be deactivated with the given reason';
  end if;

  begin
    perform app.deactivate_master_record(v_deactivated.id, '00000000-0000-0000-0000-000000001201', 'x', 'tenant admin');
    raise exception 'assertion failed: expected deactivating an already-deactivated record to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.merge_master_records: the source is never deleted, only marked merged and pointed at the target; aliases/code fold into the target; unsafe merges are rejected'
do $$
declare
  v_tenant_id uuid;
  v_source app.master_records;
  v_target app.master_records;
  v_updated_target app.master_records;
  v_source_after app.master_records;
  v_other_type_record app.master_records;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');
  v_source := app.create_master_record('vendor_rate', v_tenant_id, 'VR-DUP', 'Sea Freight FCL (dup entry)', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000001201', 'tenant admin');
  select * into v_target from app.master_records where tenant_id = v_tenant_id and code = 'VR-001';

  begin
    perform app.merge_master_records(v_source.id, v_source.id, '00000000-0000-0000-0000-000000001201', 'x', 'tenant admin');
    raise exception 'assertion failed: expected merging a record into itself to be rejected';
  exception
    when check_violation then
      null;
  end;

  v_other_type_record := app.create_master_record('cargo_type', null, 'CT-999', 'Reefer', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000001203', 'supreme admin');
  begin
    perform app.merge_master_records(v_source.id, v_other_type_record.id, '00000000-0000-0000-0000-000000001201', 'x', 'tenant admin');
    raise exception 'assertion failed: expected a cross-master-type merge to be rejected';
  exception
    when check_violation then
      null;
  end;

  v_updated_target := app.merge_master_records(v_source.id, v_target.id, '00000000-0000-0000-0000-000000001201', 'duplicate entry, same vendor rate', 'tenant admin');
  if not (v_updated_target.aliases @> to_jsonb(array['VR-DUP'])) then
    raise exception 'assertion failed: expected the target''s aliases to now include the source''s former code (VR-DUP)';
  end if;

  select * into v_source_after from app.master_records where id = v_source.id;
  if v_source_after.canonical_status <> 'merged' or v_source_after.merged_into_id <> v_target.id then
    raise exception 'assertion failed: expected the source to be marked merged and pointed at the target, not deleted';
  end if;

  begin
    perform app.merge_master_records(v_source.id, v_target.id, '00000000-0000-0000-0000-000000001201', 'x', 'tenant admin');
    raise exception 'assertion failed: expected merging an already-merged source again to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.resolve_master_record: resolves by code or alias, follows a merge chain transparently, never ambiguous, never cross-tenant'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_resolved app.master_records;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmomdm');

  v_resolved := app.resolve_master_record('vendor_rate', v_tenant_id, 'VR-001');
  if v_resolved.code <> 'VR-001' then
    raise exception 'assertion failed: expected a direct code match to resolve';
  end if;

  v_resolved := app.resolve_master_record('vendor_rate', v_tenant_id, 'Ocean FCL');
  if v_resolved.code <> 'VR-001' then
    raise exception 'assertion failed: expected the alias ''Ocean FCL'' to resolve to VR-001';
  end if;

  -- VR-DUP was merged into VR-001 above -- resolving the now-merged code must
  -- transparently follow the chain to the live survivor, not return the merged row.
  v_resolved := app.resolve_master_record('vendor_rate', v_tenant_id, 'VR-DUP');
  if v_resolved.code <> 'VR-001' or v_resolved.canonical_status <> 'active' then
    raise exception 'assertion failed: expected resolving a merged code to follow the chain to the live survivor, got code=% status=%', v_resolved.code, v_resolved.canonical_status;
  end if;

  if app.resolve_master_record('vendor_rate', v_tenant_id, 'NO-SUCH-CODE') is not null then
    raise exception 'assertion failed: expected no match to resolve to null, not raise or guess';
  end if;

  -- Cross-tenant isolation: acmemdm's VR-001 must never resolve under gizmomdm's scope.
  if app.resolve_master_record('vendor_rate', v_other_tenant_id, 'VR-001') is not null then
    raise exception 'assertion failed: expected acmemdm''s VR-001 to never resolve under gizmomdm''s tenant scope';
  end if;
end;
$$;

\echo '>> app.search_master_records: substring match on code/name, keyset pagination, tenant-scoped'
do $$
declare
  v_tenant_id uuid;
  v_results app.master_records[];
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');

  select count(*) into v_count from app.search_master_records('vendor_rate', v_tenant_id, 'Sea Freight');
  if v_count < 1 then
    raise exception 'assertion failed: expected at least one substring match for ''Sea Freight''';
  end if;

  select count(*) into v_count from app.search_master_records('vendor_rate', v_tenant_id, 'NO-SUCH-QUERY-XYZ');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero matches for a nonexistent query string';
  end if;

  -- A different tenant's search never returns acmemdm's records.
  select count(*) into v_count from app.search_master_records('vendor_rate', (select id from app.tenants where slug = 'gizmomdm'), 'Sea Freight');
  if v_count <> 0 then
    raise exception 'assertion failed: expected gizmomdm''s search to never return acmemdm''s vendor_rate records';
  end if;
end;
$$;

\echo '>> app.v_active_vendor_rates: queryable, empty for this file''s own tenants (no vendor_rate_versions row -- that is COM-149''s own scope) -- superseded by app.master_records rows alone'
do $$
declare
  v_tenant_id uuid;
  v_active_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');

  -- COM-149 (docs/adr/ADR-0015-...) redefined this view (drop + create, same name) to be
  -- validity/approval-aware, joined against app.vendor_rate_versions (a table this
  -- PLT-120 migration does not create) -- it is empty here since this fixture seeds only
  -- master_type/master_record identity rows, never a priced version. Scoped to this
  -- file's own tenant (not a bare global count) since
  -- scripts/db-tests/commercial-rate-cost-lookup.sql (COM-149's own test file) sorts
  -- alphabetically *before* this file and legitimately creates real approved rows in its
  -- own, different tenant -- the same cross-file audit-log-count fragility class COM-145/
  -- COM-148 already found, applied proactively here rather than rediscovered a third
  -- time. Real, populated coverage of this view's own approved-and-current filtering
  -- lives in that other file.
  select count(*) into v_active_count from app.v_active_vendor_rates where tenant_id = v_tenant_id;
  if v_active_count <> 0 then
    raise exception 'assertion failed: expected 0 rows for tenant acmemdm (no vendor_rate_versions row exists in this fixture), found %', v_active_count;
  end if;
end;
$$;

\echo '>> every lifecycle mutation self-captures a canonical app.audit_logs entry (no bespoke *_history table exists for this capability)'
do $$
declare
  v_tenant_id uuid;
  v_actions text[] := array['create_master_record', 'update_master_record', 'deactivate_master_record', 'merge_master_records'];
  v_action text;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmemdm');

  foreach v_action in array v_actions loop
    select count(*) into v_count
    from app.audit_logs
    where tenant_id = v_tenant_id and action = v_action and resource_type = 'app.master_records';
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;

  select count(*) into v_count
  from app.audit_logs
  where action = 'register_master_type' and tenant_id is null and resource_type = 'app.master_types';
  if v_count = 0 then
    raise exception 'assertion failed: expected a platform-wide (null tenant_id) audit entry for register_master_type';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has RLS-governed SELECT but no write privilege; anon is denied entirely'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.master_records', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold RLS-governed SELECT on app.master_records';
  end if;

  select has_table_privilege('authenticated', 'app.master_records', 'INSERT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no INSERT privilege on app.master_records (writes are RPC-only)';
  end if;

  select has_table_privilege('anon', 'app.master_records', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no privilege on app.master_records at all (no pre-authentication use case)';
  end if;

  select has_function_privilege('anon', 'app.create_master_record(text, uuid, text, text, jsonb, jsonb, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.create_master_record (ERR-2026-004 regression guard)';
  end if;
end;
$$;
