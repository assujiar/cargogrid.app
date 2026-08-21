-- Real, executable test evidence for IAE-004 (Saved View and Configurable
-- Report, Prompt 332, CG-S14-IAE-004) -- run via `pnpm run db:test` against a
-- real, disposable Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000006000001..005.
-- Tier C fix pass (Batch 1 IAE-002..006 review): 000006000005 added -- a
-- customer_user-layer portal actor in iaesavedco, feeding the two new
-- regression blocks this Tier C pass added after the original
-- list_saved_report_views test.
-- Grep-verified unclaimed against every other *.sql fixture in this directory
-- before use. Registers its own distinct test report type
-- (`iae_saved_view_test_report`) rather than depending on
-- reporting-engine.sql's own `iae_test_report` having already run in this
-- session (this file must pass standalone, not only as part of a full
-- cumulative db:test run). Uses `finance_billing_summary` (empty schema,
-- never retired by any fixture -- grep-verified) as the baseline dataset, and
-- registers/retires its own dedicated `iae_saved_view_retired_report` code to
-- prove the retired-code rejection path -- `lead_aging`'s own retired status
-- is only true inside commercial-reports.sql's own fixture run, not standalone.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (iaesavedco), a global Supreme Admin, a configurer (REP:Configure), a viewer (tenant member, no REP:Configure), a second tenant (iaesavedco2) with one lone member, and a fresh versioned test report type'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_configurer_role uuid;
  v_configurer_draft app.role_versions;
  v_t2_role uuid;
  v_t2_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000006000001', 'supreme@iaesavedco.test'),
    ('00000000-0000-0000-0000-000006000002', 'configurer@iaesavedco.test'),
    ('00000000-0000-0000-0000-000006000003', 'viewer@iaesavedco.test'),
    ('00000000-0000-0000-0000-000006000004', 'member@iaesavedco2.test'),
    ('00000000-0000-0000-0000-000006000005', 'portal@iaesavedco.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000006000001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('iaesavedco', 'IAE Saved View Co', 'idem-iaesavedco', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaesavedco');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('iaesavedco2', 'IAE Saved View Co 2', 'idem-iaesavedco2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaesavedco2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000006000002', 'configurer@iaesavedco.test', 'Configurer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configurer@iaesavedco.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000006000003', 'viewer@iaesavedco.test', 'Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaesavedco.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000006000004', 'member@iaesavedco2.test', 'Beta Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@iaesavedco2.test'), 'active', 'onboarded', 'tester');

  -- Tier C fix regression fixture: a genuine customer_user-layer (portal)
  -- principal in tenant1, with real active tenant membership -- used to
  -- prove app.create_saved_report_view/app.list_saved_report_views both now
  -- exclude this layer.
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000006000005', 'portal@iaesavedco.test', 'Portal Customer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'portal@iaesavedco.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000006000005', 'customer_user', v_tenant1, 'iae-saved-portal-ref', 'tester');

  v_configurer_role := (app.create_role(v_tenant1, 'View Configurer', 'REP:Configure', 'tester')).id;
  v_configurer_draft := app.create_role_version(v_configurer_role, 'tester');
  perform app.set_role_version_permissions(
    v_configurer_draft.id,
    array(select id from app.permissions where resource_module_code = 'REP' and action = 'Configure'),
    'tester'
  );
  perform app.publish_role_version(v_configurer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_configurer_role and status = 'published'),
    '00000000-0000-0000-0000-000006000002', '00000000-0000-0000-0000-000006000001', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'Beta Configurer', 'REP:Configure, tenant 2', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(
    v_t2_draft.id,
    array(select id from app.permissions where resource_module_code = 'REP' and action = 'Configure'),
    'tester'
  );
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'),
    '00000000-0000-0000-0000-000006000004', '00000000-0000-0000-0000-000006000004', 'tester');

  perform app.register_report_type(
    'iae_saved_view_test_report', 'IAE Saved View Test Report', 'a synthetic report for IAE-004 testing only',
    'get_dashboard_lead_aging', '00000000-0000-0000-0000-000006000001', 'tester'
  );
  perform app.publish_report_type_version(
    'iae_saved_view_test_report', 'get_dashboard_lead_aging',
    jsonb_build_object('ownerUserId', jsonb_build_object('type', 'string', 'required', true)),
    'v2: requires ownerUserId', '00000000-0000-0000-0000-000006000001', 'tester'
  );

  -- a second, dedicated test report type this file retires itself -- never
  -- depends on another *.sql fixture's own incidental retirement of a shared
  -- code like lead_aging, which only holds true inside a full cumulative run.
  perform app.register_report_type(
    'iae_saved_view_retired_report', 'IAE Saved View Retired Report', 'retired for IAE-004 testing only',
    'get_dashboard_lead_aging', '00000000-0000-0000-0000-000006000001', 'tester'
  );
  perform app.retire_report_type('iae_saved_view_retired_report', '00000000-0000-0000-0000-000006000001', 'tester');
end;
$$;

\echo '>> app.create_saved_report_view: a private view needs only active membership; a tenant-shared view needs REP:Configure; unknown/retired codes and unsafe columns/filters are all rejected'
do $$
declare
  v_tenant1 uuid;
  v_view app.saved_report_views;
  v_v2_id uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaesavedco');
  v_v2_id := (select id from app.report_type_versions where report_type_code = 'iae_saved_view_test_report' and version_number = 2);

  -- viewer (no REP:Configure) may create a PRIVATE view
  select * into v_view from app.create_saved_report_view(
    v_tenant1, 'finance_billing_summary', 'My Billing View', 'a private view',
    '["invoiceNumber", "amount"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'private', 'idem-viewer-private-1',
    '00000000-0000-0000-0000-000006000003', 'tester'
  );
  if v_view.sharing_scope <> 'private' or v_view.owner_auth_user_id <> '00000000-0000-0000-0000-000006000003' then
    raise exception 'assertion failed: expected a private view owned by the viewer';
  end if;

  -- viewer lacks REP:Configure -- a tenant-shared view must be denied
  begin
    perform app.create_saved_report_view(
      v_tenant1, 'finance_billing_summary', 'Should be denied', null,
      '["invoiceNumber"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'tenant', null,
      '00000000-0000-0000-0000-000006000003', 'tester'
    );
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks REP:Configure for a tenant-shared view';
  exception
    when insufficient_privilege then null;
  end;

  -- configurer may create a tenant-shared view
  select * into v_view from app.create_saved_report_view(
    v_tenant1, 'finance_billing_summary', 'Team Billing View', 'shared with the tenant',
    '["invoiceNumber", "amount", "dueDate"]'::jsonb, '{}'::jsonb, jsonb_build_object('field', 'dueDate', 'direction', 'asc'), '{}'::jsonb,
    'tenant', 'idem-configurer-shared-1',
    '00000000-0000-0000-0000-000006000002', 'tester'
  );
  if v_view.sharing_scope <> 'tenant' then
    raise exception 'assertion failed: expected a tenant-shared view';
  end if;

  -- unknown report code
  begin
    perform app.create_saved_report_view(
      v_tenant1, 'not_a_real_report', 'x', null, '["a"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'private', null,
      '00000000-0000-0000-0000-000006000003', 'tester'
    );
    raise exception 'assertion failed: expected report_type_unknown';
  exception
    when no_data_found then null;
  end;

  -- retired report code (this file's own dedicated, self-retired test type)
  begin
    perform app.create_saved_report_view(
      v_tenant1, 'iae_saved_view_retired_report', 'x', null, '["a"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'private', null,
      '00000000-0000-0000-0000-000006000003', 'tester'
    );
    raise exception 'assertion failed: expected report_type_retired';
  exception
    when check_violation then null;
  end;

  -- empty columns
  begin
    perform app.create_saved_report_view(
      v_tenant1, 'finance_billing_summary', 'x', null, '[]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'private', null,
      '00000000-0000-0000-0000-000006000003', 'tester'
    );
    raise exception 'assertion failed: expected saved_view_columns_required for empty columns';
  exception
    when check_violation then null;
  end;

  -- filters missing the schema's own required ownerUserId
  begin
    perform app.create_saved_report_view(
      v_tenant1, 'iae_saved_view_test_report', 'x', null, '["a"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'private', null,
      '00000000-0000-0000-0000-000006000003', 'tester'
    );
    raise exception 'assertion failed: expected saved_view_unsafe_filters -- ownerUserId is required by v2';
  exception
    when check_violation then null;
  end;

  -- filters satisfying the schema succeed and stamp the CURRENT (v2) version id
  select * into v_view from app.create_saved_report_view(
    v_tenant1, 'iae_saved_view_test_report', 'Versioned View', null,
    '["ownerUserId"]'::jsonb, jsonb_build_object('ownerUserId', 'u-1'), '{}'::jsonb, '{}'::jsonb, 'private', null,
    '00000000-0000-0000-0000-000006000003', 'tester'
  );
  if v_view.report_type_version_id <> v_v2_id then
    raise exception 'assertion failed: expected the new view to stamp the report''s own CURRENT (v2) version id, got %', v_view.report_type_version_id;
  end if;

  -- invalid sharing scope
  begin
    perform app.create_saved_report_view(
      v_tenant1, 'finance_billing_summary', 'x', null, '["a"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'public', null,
      '00000000-0000-0000-0000-000006000003', 'tester'
    );
    raise exception 'assertion failed: expected saved_view_invalid_sharing_scope for an unknown scope';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> idempotency (C-01/C-02): a repeated create with the SAME key and tuple replays to the identical row; a repeated key with a DIFFERENT tuple conflicts'
do $$
declare
  v_tenant1 uuid;
  v_first app.saved_report_views;
  v_replay app.saved_report_views;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaesavedco');

  select * into v_first from app.create_saved_report_view(
    v_tenant1, 'finance_billing_summary', 'Idempotent View', null,
    '["invoiceNumber"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'private', 'idem-repeat-1',
    '00000000-0000-0000-0000-000006000003', 'tester'
  );

  select * into v_replay from app.create_saved_report_view(
    v_tenant1, 'finance_billing_summary', 'Idempotent View', null,
    '["invoiceNumber"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'private', 'idem-repeat-1',
    '00000000-0000-0000-0000-000006000003', 'tester'
  );
  if v_replay.id <> v_first.id then
    raise exception 'assertion failed: expected the identical row to be returned on idempotency-key replay';
  end if;

  begin
    perform app.create_saved_report_view(
      v_tenant1, 'finance_billing_summary', 'A Different Name', null,
      '["invoiceNumber"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'private', 'idem-repeat-1',
      '00000000-0000-0000-0000-000006000003', 'tester'
    );
    raise exception 'assertion failed: expected idempotency_key_conflict for a different tuple under the same key';
  exception
    when unique_violation then null;
  end;
end;
$$;

\echo '>> app.update_saved_report_view: owner-only (sharing never grants write access), stale-version guarded, re-validates on every save'
do $$
declare
  v_tenant1 uuid;
  v_view app.saved_report_views;
  v_updated app.saved_report_views;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaesavedco');
  select * into v_view from app.saved_report_views where tenant_id = v_tenant1 and name = 'Team Billing View';

  -- the viewer (not the owning configurer) may not edit a shared view
  begin
    perform app.update_saved_report_view(
      v_view.id, v_view.record_version, 'Hijacked', null, '["invoiceNumber"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
      '00000000-0000-0000-0000-000006000003', 'tester'
    );
    raise exception 'assertion failed: expected saved_report_view_not_found -- sharing does not grant write access';
  exception
    when no_data_found then null;
  end;

  select * into v_updated from app.update_saved_report_view(
    v_view.id, v_view.record_version, 'Team Billing View (renamed)', 'updated', '["invoiceNumber", "amount"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
    '00000000-0000-0000-0000-000006000002', 'tester'
  );
  if v_updated.name <> 'Team Billing View (renamed)' or v_updated.record_version <> v_view.record_version + 1 then
    raise exception 'assertion failed: expected the owner''s own edit to succeed and bump record_version';
  end if;

  -- stale version (the ORIGINAL record_version has since moved on)
  begin
    perform app.update_saved_report_view(
      v_view.id, v_view.record_version, 'Stale Edit', null, '["invoiceNumber"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
      '00000000-0000-0000-0000-000006000002', 'tester'
    );
    raise exception 'assertion failed: expected stale_version for the now-outdated expected version';
  exception
    when check_violation then null;
  end;

  -- re-validation on update: unsafe (empty) columns
  begin
    perform app.update_saved_report_view(
      v_view.id, v_updated.record_version, 'x', null, '[]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
      '00000000-0000-0000-0000-000006000002', 'tester'
    );
    raise exception 'assertion failed: expected saved_view_columns_required to be re-checked on update';
  exception
    when check_violation then null;
  end;
end;
$$;

\echo '>> app.delete_saved_report_view: owner-only, stale-version guarded'
do $$
declare
  v_tenant1 uuid;
  v_view app.saved_report_views;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaesavedco');
  select * into v_view from app.saved_report_views where tenant_id = v_tenant1 and name = 'Idempotent View';

  -- non-owner may not delete
  begin
    perform app.delete_saved_report_view(v_view.id, v_view.record_version, '00000000-0000-0000-0000-000006000002', 'tester');
    raise exception 'assertion failed: expected saved_report_view_not_found for a non-owner delete attempt';
  exception
    when no_data_found then null;
  end;

  if not app.delete_saved_report_view(v_view.id, v_view.record_version, '00000000-0000-0000-0000-000006000003', 'tester') then
    raise exception 'assertion failed: expected the owner''s own delete to succeed';
  end if;

  if exists (select 1 from app.saved_report_views where id = v_view.id) then
    raise exception 'assertion failed: expected the row to be gone after delete';
  end if;
end;
$$;

\echo '>> app.list_saved_report_views: an actor sees their own views (any scope) plus every tenant-shared view; cross-tenant access is denied outright'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_rows app.saved_report_views[];
  v_names text[];
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaesavedco');
  v_tenant2 := (select id from app.tenants where slug = 'iaesavedco2');

  select array_agg(name) into v_names from app.list_saved_report_views(v_tenant1, null, '00000000-0000-0000-0000-000006000003', 25, null);
  if not (v_names @> array['My Billing View']) then
    raise exception 'assertion failed: expected the viewer''s own private view in their own list';
  end if;
  if not (v_names @> array['Team Billing View (renamed)']) then
    raise exception 'assertion failed: expected the configurer''s tenant-shared view visible to the viewer too';
  end if;

  -- cross-tenant: a tenant-2 actor has no membership in tenant-1
  begin
    perform app.list_saved_report_views(v_tenant1, null, '00000000-0000-0000-0000-000006000004', 25, null);
    raise exception 'assertion failed: expected insufficient_authority for a cross-tenant list attempt';
  exception
    when insufficient_privilege then null;
  end;

  select array_agg(name) into v_names from app.list_saved_report_views(v_tenant2, null, '00000000-0000-0000-0000-000006000004', 25, null);
  if v_names is not null and (v_names @> array['My Billing View'] or v_names @> array['Team Billing View (renamed)']) then
    raise exception 'assertion failed: tenant-2''s own list must never contain tenant-1''s rows';
  end if;

  -- Tier C fix regression (finding 8, spec-compliance): a customer_user-layer
  -- (portal) principal, with real active tenant1 membership, must NOT
  -- receive tenant1's own tenant-shared saved view configuration through
  -- this RPC -- mirrors the table's own RLS policy, which already denied
  -- this on a direct SELECT.
  select array_agg(name) into v_names from app.list_saved_report_views(v_tenant1, null, '00000000-0000-0000-0000-000006000005', 25, null);
  if v_names is not null and v_names @> array['Team Billing View (renamed)'] then
    raise exception 'assertion failed: a customer_user-layer principal must never receive a tenant-shared saved view through app.list_saved_report_views -- the Tier C fix has regressed';
  end if;
end;
$$;

\echo '>> Tier C fix regression (finding 9, spec-compliance): app.create_saved_report_view''s own private-view branch now actually enforces its own always-documented "active, non-customer_user-layer tenant membership" contract'
do $$
begin
  begin
    perform app.create_saved_report_view(
      (select id from app.tenants where slug = 'iaesavedco'), 'finance_billing_summary', 'Portal Should Be Denied', null,
      '["invoiceNumber"]'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'private', null,
      '00000000-0000-0000-0000-000006000005', 'tester'
    );
    raise exception 'assertion failed: expected insufficient_privilege -- a customer_user-layer principal has real active tenant membership but this function''s own comment always documented that a private view requires the NON-customer_user-layer half too';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any new IAE-004 function; authenticated has no direct INSERT/UPDATE/DELETE on the new table'
do $$
declare
  v_bad_grant record;
begin
  for v_bad_grant in
    select routine_name from information_schema.routine_privileges
    where routine_schema = 'app'
      and routine_name in ('create_saved_report_view', 'update_saved_report_view', 'delete_saved_report_view', 'list_saved_report_views')
      and grantee = 'anon'
  loop
    raise exception 'assertion failed: anon must not hold EXECUTE on app.%', v_bad_grant.routine_name;
  end loop;

  for v_bad_grant in
    select privilege_type from information_schema.role_table_grants
    where table_schema = 'app' and table_name = 'saved_report_views'
      and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  loop
    raise exception 'assertion failed: authenticated must not hold direct % on app.saved_report_views', v_bad_grant.privilege_type;
  end loop;
end;
$$;

\echo '>> audit trail: create/update/delete each recorded a real app.audit_logs event'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'iaesavedco');

  select count(*) into v_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.saved_report_views' and action = 'create_saved_report_view';
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one create_saved_report_view audit event';
  end if;

  select count(*) into v_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.saved_report_views' and action = 'update_saved_report_view';
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one update_saved_report_view audit event';
  end if;

  select count(*) into v_count from app.audit_logs
  where tenant_id = v_tenant1 and resource_type = 'app.saved_report_views' and action = 'delete_saved_report_view';
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one delete_saved_report_view audit event';
  end if;
end;
$$;

\echo 'ALL IAE-004 (Saved View and Configurable Report) db-test assertions passed.'
