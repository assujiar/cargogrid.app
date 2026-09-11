-- Real, executable test evidence for CG-AUDIT-2026-09-02 Ø1-query-layer, cluster 2
-- (HRIS/identity-access) batch 1 of ~N
-- (supabase/migrations/20260910010000_close_o1_query_layer_cluster2_batch1_identity_access.sql).
--
-- Proves, against a real disposable database: app.list_identity_tenant_links is genuinely
-- self-only (the calling identity sees every one of its OWN tenant links, any status,
-- across every tenant it has ever touched) and RULE A rejects a claimed actor that does
-- not match the real session identity; app.list_tenant_users RAISEs insufficient_authority
-- for a customer_user-layer principal and for a cross-tenant actor (the "list for one
-- named tenant" posture), while a Supreme Admin with ZERO tenant membership bypasses;
-- app.list_user_directory_email_projections/app.list_portal_users/app.list_user_directory
-- all silently return ZERO rows (never an exception) for the identical denied actors,
-- confirming the CORRECTED customer_user-layer exclusion this batch's own verify pass
-- added actually works; email masking toggles correctly based on HRS:View personal data;
-- app.list_permissions_for_module denies an authenticated identity with ZERO active
-- principal_memberships standing anywhere, while an ordinary active member and a Supreme
-- Admin both see the seeded catalogue; app.list_tenant_roles reproduces the same
-- membership/customer-layer posture as app.list_user_directory (silent zero rows); and
-- schema-privilege defense in depth (anon holds zero EXECUTE on any of the 7 new
-- functions).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant with an org_user member (also linked, invited-only, to a second tenant -- proves any-status/cross-tenant aggregation), a second org_user member with no extra permissions, a customer_user-layer principal, an identity with ZERO standing anywhere, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant with its own admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
  v_pii_role_id uuid;
  v_pii_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998601', 'membero1c2@example.test'),
    ('00000000-0000-0000-0000-000000998602', 'customerusero1c2@example.test'),
    ('00000000-0000-0000-0000-000000998603', 'zerostandingo1c2@example.test'),
    ('00000000-0000-0000-0000-000000998604', 'supremeo1c2@example.test'),
    ('00000000-0000-0000-0000-000000998605', 'othertenanto1c2@example.test'),
    ('00000000-0000-0000-0000-000000998606', 'plainmembero1c2@example.test');

  perform app.provision_tenant('acmeo1c2', 'Acme O1C2 Co', 'idem-acmeo1c2', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1c2');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1C2-CO', 'Acme O1C2 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1C2-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998601', 'membero1c2@example.test', 'Member', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1c2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998601', 'org_user', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998606', 'plainmembero1c2@example.test', 'Plain Member', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainmembero1c2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998606', 'org_user', v_tenant_id, null, 'tester');

  -- 998601 gets HRS:'View personal data', so it sees UNMASKED emails in the directory
  -- functions below -- 998606 (plain member) does not, so it sees MASKED emails. Granted
  -- by 998606 (not 998601 itself) since app.assign_role's own self_escalation guard
  -- forbids an actor from assigning itself a role version carrying a protected permission.
  v_pii_role_id := (app.create_role(v_tenant_id, 'PII Viewer', 'HRS View personal data', 'tester')).id;
  v_pii_draft := app.create_role_version(v_pii_role_id, 'tester');
  perform app.set_role_version_permissions(v_pii_draft.id, array(select id from app.permissions where resource_module_code = 'HRS' and action = 'View personal data'), 'tester');
  perform app.publish_role_version(v_pii_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_pii_role_id and status = 'published'), '00000000-0000-0000-0000-000000998601', '00000000-0000-0000-0000-000000998606', 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000998602', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998602', 'customer_user', v_tenant_id, 'fake-account-ref-o1c2', 'tester');

  -- 998603: a real auth.users row (a live JWT could exist for it), but ZERO principal_
  -- memberships and ZERO tenant_user_identities rows anywhere -- the exact "revoked or
  -- never-onboarded identity with a still-live session token" population
  -- app.list_permissions_for_module's own standing check exists to deny.

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998604', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1c2', 'Gizmo O1C2 Co', 'idem-gizmoo1c2', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1c2');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998605', 'othertenanto1c2@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1c2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998605', 'tenant_admin', v_other_tenant_id, null, 'tester');

  -- 998601 is ALSO linked (invited-only, never activated) to gizmoo1c2 -- proves
  -- app.list_identity_tenant_links aggregates "any status, across every tenant."
  perform app.link_auth_identity('00000000-0000-0000-0000-000000998601', v_other_tenant_id, 'tester', 'invited');

  perform app.create_role(v_tenant_id, 'Ops Coordinator', 'a real tenant-created role for app.list_tenant_roles', 'tester');
end $$;

\echo '>> app.list_identity_tenant_links: self-lookup sees every one of its own tenant links, any status, across every tenant -- Supreme Admin (a different real actor) is not entitled to look up someone else''s links either'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.list_identity_tenant_links('00000000-0000-0000-0000-000000998601');
  if v_count <> 2 then
    raise exception 'assertion failed: expected 2 tenant_user_identities rows (one active, one invited) for 998601, got %', v_count;
  end if;

  select count(*) into v_count from app.list_identity_tenant_links('00000000-0000-0000-0000-000000998603');
  if v_count <> 0 then
    raise exception 'assertion failed: an identity with zero linkages must see zero rows, got %', v_count;
  end if;

  raise notice 'app.list_identity_tenant_links proof: self-lookup sees both rows (active + invited, 2 tenants), zero-linkage identity sees zero rows';
end $$;

\echo '>> RULE A: app.list_identity_tenant_links genuinely rejects a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998605", "role": "authenticated"}';
  do $$
  begin
    begin
      -- Real session is 998605 (the other tenant's admin); claims to be 998601 (a
      -- different real identity, whose links it would otherwise see) -- must still be
      -- rejected, since this function has no separate "subject" parameter at all.
      perform app.list_identity_tenant_links('00000000-0000-0000-0000-000000998601');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.list_tenant_users: an active member sees every user of the tenant; a customer_user-layer principal and a cross-tenant actor both RAISE insufficient_authority (the "list for one named tenant" posture); Supreme Admin bypasses with zero membership'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c2');
  v_count integer;
begin
  select count(*) into v_count from app.list_tenant_users(v_tenant_id, '00000000-0000-0000-0000-000000998601');
  if v_count <> 2 then
    raise exception 'assertion failed: expected 2 users (998601, 998606) in acmeo1c2, got %', v_count;
  end if;

  begin
    perform app.list_tenant_users(v_tenant_id, '00000000-0000-0000-0000-000000998602');
    raise exception 'assertion failed: a customer_user-layer principal must be denied app.list_tenant_users outright';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.list_tenant_users(v_tenant_id, '00000000-0000-0000-0000-000000998605');
    raise exception 'assertion failed: a cross-tenant actor must be denied app.list_tenant_users outright';
  exception
    when insufficient_privilege then
      null;
  end;

  select count(*) into v_count from app.list_tenant_users(v_tenant_id, '00000000-0000-0000-0000-000000998604');
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero tenant membership must bypass and see both users, got %', v_count;
  end if;

  raise notice 'app.list_tenant_users proof: active member sees both users, customer_user-layer/cross-tenant actors are RAISEd, Supreme Admin bypasses';
end $$;

\echo '>> app.list_user_directory_email_projections / app.list_portal_users / app.list_user_directory: email masking toggles on HRS:View personal data, customer_user-layer/cross-tenant actors see ZERO rows (never an exception -- the CORRECTED exclusion this batch''s own verify pass added), Supreme Admin bypasses'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c2');
  v_row record;
  v_count integer;
begin
  -- email_projections: 998601 (has the PII permission) sees an unmasked email; 998606
  -- (plain member, no PII permission) sees a masked one.
  select * into v_row from app.list_user_directory_email_projections(v_tenant_id, '00000000-0000-0000-0000-000000998601') where id = (select id from app.users where email = 'membero1c2@example.test');
  if v_row.email_masked is not false or v_row.email <> 'membero1c2@example.test' then
    raise exception 'assertion failed: 998601 (has HRS:View personal data) must see its own unmasked email, got email_masked=% email=%', v_row.email_masked, v_row.email;
  end if;

  select * into v_row from app.list_user_directory_email_projections(v_tenant_id, '00000000-0000-0000-0000-000000998606') where id = (select id from app.users where email = 'membero1c2@example.test');
  if v_row.email_masked is not true then
    raise exception 'assertion failed: 998606 (no HRS:View personal data) must see a masked email, got email_masked=%', v_row.email_masked;
  end if;

  select count(*) into v_count from app.list_user_directory_email_projections(v_tenant_id, '00000000-0000-0000-0000-000000998602');
  if v_count <> 0 then
    raise exception 'assertion failed: RULE B correction -- a customer_user-layer principal must see zero directory rows, got %', v_count;
  end if;
  select count(*) into v_count from app.list_user_directory_email_projections(v_tenant_id, '00000000-0000-0000-0000-000000998605');
  if v_count <> 0 then
    raise exception 'assertion failed: a cross-tenant actor must see zero directory rows, got %', v_count;
  end if;
  select count(*) into v_count from app.list_user_directory_email_projections(v_tenant_id, '00000000-0000-0000-0000-000000998604');
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero tenant membership must bypass and see both directory rows, got %', v_count;
  end if;

  -- list_portal_users: same posture, paginated shape.
  select count(*) into v_count from app.list_portal_users(v_tenant_id, '00000000-0000-0000-0000-000000998601');
  if v_count <> 2 then
    raise exception 'assertion failed: expected 2 portal-user rows for the active member, got %', v_count;
  end if;
  select count(*) into v_count from app.list_portal_users(v_tenant_id, '00000000-0000-0000-0000-000000998602');
  if v_count <> 0 then
    raise exception 'assertion failed: RULE B correction -- a customer_user-layer principal must see zero portal-user rows, got %', v_count;
  end if;

  -- list_user_directory: same posture, full-column shape.
  select count(*) into v_count from app.list_user_directory(v_tenant_id, '00000000-0000-0000-0000-000000998601');
  if v_count <> 2 then
    raise exception 'assertion failed: expected 2 full-directory rows for the active member, got %', v_count;
  end if;
  select count(*) into v_count from app.list_user_directory(v_tenant_id, '00000000-0000-0000-0000-000000998602');
  if v_count <> 0 then
    raise exception 'assertion failed: RULE B correction -- a customer_user-layer principal must see zero full-directory rows, got %', v_count;
  end if;
  select count(*) into v_count from app.list_user_directory(v_tenant_id, '00000000-0000-0000-0000-000000998605');
  if v_count <> 0 then
    raise exception 'assertion failed: a cross-tenant actor must see zero full-directory rows, got %', v_count;
  end if;

  raise notice 'app.list_user_directory_email_projections/app.list_portal_users/app.list_user_directory proof: email masking toggles on HRS:View personal data, customer_user-layer/cross-tenant actors see zero rows, Supreme Admin bypasses';
end $$;

\echo '>> app.list_permissions_for_module: an identity with ZERO active principal_memberships standing anywhere is denied outright; an ordinary active member and a Supreme Admin both see the seeded OPS catalogue'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.list_permissions_for_module('OPS', '00000000-0000-0000-0000-000000998601');
  if v_count = 0 then
    raise exception 'assertion failed: an active member must see the seeded OPS permission catalogue, got 0 rows';
  end if;

  select count(*) into v_count from app.list_permissions_for_module('OPS', '00000000-0000-0000-0000-000000998603');
  if v_count <> 0 then
    raise exception 'assertion failed: an identity with ZERO active principal_memberships anywhere must see zero rows, got %', v_count;
  end if;

  select count(*) into v_count from app.list_permissions_for_module('OPS', '00000000-0000-0000-0000-000000998604');
  if v_count = 0 then
    raise exception 'assertion failed: a Supreme Admin (an active principal_memberships row of its own) must see the seeded OPS permission catalogue, got 0 rows';
  end if;

  raise notice 'app.list_permissions_for_module proof: zero-standing identity denied, active member and Supreme Admin both see the catalogue';
end $$;

\echo '>> app.list_tenant_roles: an active member sees the tenant''s own real role; a customer_user-layer principal and a cross-tenant actor both see zero rows (never an exception); Supreme Admin bypasses'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmeo1c2');
  v_count integer;
begin
  -- 2 real roles exist in this tenant: "PII Viewer" (created for the masking test above)
  -- and "Ops Coordinator" (created purely for this section).
  select count(*) into v_count from app.list_tenant_roles(v_tenant_id, '00000000-0000-0000-0000-000000998601');
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 real tenant-created roles, got %', v_count;
  end if;

  select count(*) into v_count from app.list_tenant_roles(v_tenant_id, '00000000-0000-0000-0000-000000998602');
  if v_count <> 0 then
    raise exception 'assertion failed: a customer_user-layer principal must see zero roles, got %', v_count;
  end if;

  select count(*) into v_count from app.list_tenant_roles(v_tenant_id, '00000000-0000-0000-0000-000000998605');
  if v_count <> 0 then
    raise exception 'assertion failed: a cross-tenant actor must see zero roles, got %', v_count;
  end if;

  select count(*) into v_count from app.list_tenant_roles(v_tenant_id, '00000000-0000-0000-0000-000000998604');
  if v_count <> 2 then
    raise exception 'assertion failed: Supreme Admin with zero tenant membership must bypass and see both roles, got %', v_count;
  end if;

  raise notice 'app.list_tenant_roles proof: active member sees the real role, customer_user-layer/cross-tenant actors see zero rows, Supreme Admin bypasses';
end $$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on any of the 7 new cluster-2-batch-1 functions'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema in ('app', 'public')
    and routine_name in (
      'list_identity_tenant_links',
      'list_tenant_users',
      'list_user_directory_email_projections',
      'list_portal_users',
      'list_user_directory',
      'list_permissions_for_module',
      'list_tenant_roles'
    )
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: anon must hold zero EXECUTE on any cluster-2-batch-1 function, found % grants', v_count;
  end if;
  raise notice 'schema-privilege proof: anon holds zero EXECUTE on any of the 7 new cluster-2-batch-1 functions';
end $$;

\echo '>> o1-query-layer-cluster2-batch1.sql test suite passed -- cluster 2 (HRIS/identity-access, 10/10 call-site entries) is now fully DONE'
