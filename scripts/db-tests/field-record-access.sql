-- Real, executable test evidence for PLT-114 (Field-Level and Record-Level Access,
-- CG-S6-PLT-011).

\set ON_ERROR_STOP on

\echo '>> setup: a tenant, an owner, a shared-org-unit teammate, an outsider, a customer contact, and a Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000601', 'ownerfra@example.test'),
    ('00000000-0000-0000-0000-000000000602', 'teammate@example.test'),
    ('00000000-0000-0000-0000-000000000603', 'outsider@example.test'),
    ('00000000-0000-0000-0000-000000000604', 'customercontact@example.test'),
    ('00000000-0000-0000-0000-000000000605', 'supremefra@example.test'),
    ('00000000-0000-0000-0000-000000000606', 'hrviewer@example.test');

  perform app.provision_tenant('acmefra', 'Acme Field/Record Co', 'idem-acmefra', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmefra');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEFRA-CO', 'Acme Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEFRA-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000601', 'ownerfra@example.test', 'Owner', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'ownerfra@example.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000602', 'teammate@example.test', 'Teammate', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'teammate@example.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000603', 'outsider@example.test', 'Outsider', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@example.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000606', 'hrviewer@example.test', 'HR Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'hrviewer@example.test'), 'active', 'onboarded', 'tester');

  perform app.link_auth_identity('00000000-0000-0000-0000-000000000604', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000604', 'customer_user', v_tenant_id, 'CUST-FRA-01', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000605', 'supreme_admin', null, null, 'tester');
end;
$$;

\echo '>> app.can_access_record: the record owner is always granted access'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmefra');
  if not app.can_access_record('00000000-0000-0000-0000-000000000601', v_tenant_id, '00000000-0000-0000-0000-000000000601') then
    raise exception 'assertion failed: expected the record owner to be granted access';
  end if;
end;
$$;

\echo '>> app.can_access_record: a teammate sharing the owner''s org unit is granted access; an outsider in the same tenant is not'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmefra');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEFRA-CO');

  if not app.can_access_record('00000000-0000-0000-0000-000000000602', v_tenant_id, '00000000-0000-0000-0000-000000000601', array[v_org_unit_id]) then
    raise exception 'assertion failed: expected the shared-org-unit teammate to be granted access';
  end if;

  if app.can_access_record('00000000-0000-0000-0000-000000000603', v_tenant_id, '00000000-0000-0000-0000-000000000601', array[v_org_unit_id]) then
    raise exception 'assertion failed: expected the outsider (not the owner, not in the shared org unit) to be denied';
  end if;
end;
$$;

\echo '>> app.can_access_record: a customer_user is granted access only when their own customer_account_ref matches'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmefra');

  if not app.can_access_record('00000000-0000-0000-0000-000000000604', v_tenant_id, '00000000-0000-0000-0000-000000000601', '{}', 'CUST-FRA-01') then
    raise exception 'assertion failed: expected the matching customer_user to be granted access to their own account''s record';
  end if;

  if app.can_access_record('00000000-0000-0000-0000-000000000604', v_tenant_id, '00000000-0000-0000-0000-000000000601', '{}', 'CUST-FRA-99') then
    raise exception 'assertion failed: expected a customer_user to be denied access to a different customer account''s record';
  end if;
end;
$$;

\echo '>> app.can_access_record: tenant membership is a hard prerequisite -- fails closed even for the record owner, in the wrong tenant'
do $$
declare
  v_other_tenant_id uuid;
begin
  perform app.provision_tenant('gizmofra', 'Gizmo Field/Record Co', 'idem-gizmofra', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmofra');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');

  if app.can_access_record('00000000-0000-0000-0000-000000000601', v_other_tenant_id, '00000000-0000-0000-0000-000000000601') then
    raise exception 'assertion failed: expected the "owner" to be denied when evaluated against a tenant they are not a member of (IDOR-style cross-tenant guess)';
  end if;
end;
$$;

\echo '>> app.can_access_record: the Supreme Admin exception bypasses ownership/sharing/customer-scope entirely'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmefra');
  if not app.can_access_record('00000000-0000-0000-0000-000000000605', v_tenant_id, '00000000-0000-0000-0000-000000000601') then
    raise exception 'assertion failed: expected the Supreme Admin to be granted access regardless of ownership/sharing';
  end if;
end;
$$;

\echo '>> field masking: the raw email column is unreachable by authenticated -- a column-level REVOKE, not a convention'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000601", "role": "authenticated"}';
  begin
    perform email from app.users limit 1;
    raise exception 'assertion failed: authenticated must be denied SELECT on app.users.email directly, but the query succeeded';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;
end;
$$;

\echo '>> field masking: app.users_directory masks the email for a caller without View personal data, and reveals it for one who has it'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_draft app.role_versions;
  v_permission_id uuid;
  v_masked_email text;
  v_masked_flag boolean;
  v_unmasked_email text;
  v_unmasked_flag boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmefra');

  select id into v_role_id from app.create_role(v_tenant_id, 'HR Viewer Role', null, 'tester');
  select * into v_draft from app.create_role_version(v_role_id, 'tester');
  select id into v_permission_id from app.permissions where resource_module_code = 'HRS' and action = 'View personal data';
  perform app.set_role_version_permissions(v_draft.id, array[v_permission_id], 'tester');
  perform app.publish_role_version(v_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_role_id and status = 'published'), '00000000-0000-0000-0000-000000000606', '00000000-0000-0000-0000-000000000605', 'tester');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000603", "role": "authenticated"}';
  select email, email_masked into v_masked_email, v_masked_flag from app.users_directory where auth_user_id = '00000000-0000-0000-0000-000000000601';
  reset role;
  if v_masked_flag is not true or v_masked_email <> 'o***@example.test' then
    raise exception 'assertion failed: expected the outsider to see a masked email (o***@example.test, email_masked=true), got email=% masked=%', v_masked_email, v_masked_flag;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000606", "role": "authenticated"}';
  select email, email_masked into v_unmasked_email, v_unmasked_flag from app.users_directory where auth_user_id = '00000000-0000-0000-0000-000000000601';
  reset role;
  if v_unmasked_flag is not false or v_unmasked_email <> 'ownerfra@example.test' then
    raise exception 'assertion failed: expected the HR viewer to see the real email (email_masked=false), got email=% masked=%', v_unmasked_email, v_unmasked_flag;
  end if;
end;
$$;

\echo '>> field masking: app.users_directory itself still respects the tenant-boundary RLS on the underlying app.users row'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000603", "role": "authenticated"}';
  select count(*) into v_count from app.users_directory;
  reset role;
  if v_count <> 4 then
    raise exception 'assertion failed: expected the outsider to see exactly 4 directory rows (their own tenant''s active users), saw %', v_count;
  end if;
end;
$$;

\echo '>> defense in depth: anon still denied entirely; service_role still bypasses everything, including the mask (its own direct query, not the view)'
do $$
begin
  set local role anon;
  begin
    perform count(*) from app.users_directory;
    raise exception 'assertion failed: anon must be denied on app.users_directory';
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
  select count(*) into v_count from app.users;
  if v_count < 4 then
    raise exception 'assertion failed: service_role must still see every user row directly, unaffected by the column-level REVOKE on authenticated, saw %', v_count;
  end if;
  reset role;
end;
$$;

\echo 'ALL PLT-114 db-test assertions passed.'
