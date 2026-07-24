-- Real, executable test evidence for COM-145 (Contact and Activity Management,
-- CG-S7-COM-004) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/branch/department org hierarchy, a rep, a branch manager, an outsider, a qualified lead and a prospect'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_branch uuid;
  v_team uuid;
  v_other_team uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_lead app.leads;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000008201', 'rep@acmecontact.test'),
    ('00000000-0000-0000-0000-000000008202', 'manager@acmecontact.test'),
    ('00000000-0000-0000-0000-000000008203', 'outsider@acmecontact.test'),
    ('00000000-0000-0000-0000-000000008204', 'other-tenant-rep@betacontact.test');

  perform app.provision_tenant('acmecontact', 'Acme Contact Co', 'idem-acmecontact', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmecontact');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betacontact', 'Beta Contact Co', 'idem-betacontact', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betacontact');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMECONTACT-CO', 'Acme Contact Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONTACT-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMECONTACT-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONTACT-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMECONTACT-TEAM-A', 'Sales Team A', 'tester');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONTACT-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMECONTACT-TEAM-B', 'Sales Team B', 'tester');
  v_other_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONTACT-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008201', 'rep@acmecontact.test', 'Rep', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmecontact.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008202', 'manager@acmecontact.test', 'Branch Manager', v_branch, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmecontact.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008203', 'outsider@acmecontact.test', 'Outsider', v_other_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmecontact.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000008204', 'other-tenant-rep@betacontact.test', 'Other Tenant Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'other-tenant-rep@betacontact.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Sales Rep', 'contact/activity capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008201', '00000000-0000-0000-0000-000000008201', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008202', '00000000-0000-0000-0000-000000008201', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008203', '00000000-0000-0000-0000-000000008201', 'tester');

  v_rep_role := (app.create_role(v_tenant2, 'Sales Rep', 'contact/activity capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008204', '00000000-0000-0000-0000-000000008204', 'tester');

  -- Deliberately left status=new -- app.link_contact_to_record/app.log_activity have no
  -- qualified-status precondition (unlike app.convert_lead_to_prospect, COM-144), and
  -- calling app.qualify_lead here would pollute the shared audit_logs table other
  -- db-test files' own "exactly N qualify_lead events" assertions rely on (all db-test
  -- files run against one continuous disposable database, not isolated per file).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Contact Ltd', 'Jane Doe', 'jane@contosocontact.test', '0811',
    '00000000-0000-0000-0000-000000008201', v_team, '00000000-0000-0000-0000-000000008201', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosocontact.test';

  perform app.capture_lead(v_tenant2, 'manual', null, 'Other Tenant Co', 'Other Tenant', 'other@tenant-contact.test', '0822',
    '00000000-0000-0000-0000-000000008204', null, '00000000-0000-0000-0000-000000008204', 'tester');
end;
$$;

\echo '>> create_contact: requires tenant membership and COM:Create'
do $$
declare
  v_tenant1 uuid;
  v_team uuid;
  v_contact app.contacts;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmecontact');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECONTACT-TEAM-A');

  select * into v_contact from app.create_contact(
    v_tenant1, 'Budi Santoso', 'Procurement Manager', 'budi@contosocontact.test', '0812-3456-7890',
    '00000000-0000-0000-0000-000000008201', v_team, '00000000-0000-0000-0000-000000008201', 'tester'
  );
  if v_contact.full_name <> 'Budi Santoso' or v_contact.status <> 'active' then
    raise exception 'assertion failed: expected an active contact named Budi Santoso, got name=% status=%', v_contact.full_name, v_contact.status;
  end if;

  begin
    perform app.create_contact(
      (select id from app.tenants where slug = 'betacontact'), 'Cross Tenant', null, 'x@y.test', null,
      '00000000-0000-0000-0000-000000008201', null, '00000000-0000-0000-0000-000000008201', 'tester'
    );
    raise exception 'assertion failed: expected insufficient_privilege for an actor with no membership in betacontact';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> find_duplicate_contacts: matches by normalized email/phone, tenant-scoped, fails closed'
do $$
declare
  v_tenant1 uuid;
  v_dupe_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmecontact');

  select count(*) into v_dupe_count from app.find_duplicate_contacts(
    v_tenant1, '00000000-0000-0000-0000-000000008201', 'BUDI@ContosoContact.test', '081234567890'
  );
  if v_dupe_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 duplicate candidate, found %', v_dupe_count;
  end if;

  begin
    perform app.find_duplicate_contacts(v_tenant1, '00000000-0000-0000-0000-000000008204', 'budi@contosocontact.test', null);
    raise exception 'assertion failed: expected insufficient_privilege for an actor with no membership in this tenant';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> link_contact_to_record: idempotent, requires access to both contact and record, cross-tenant denied'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_contact app.contacts;
  v_lead app.leads;
  v_other_lead app.leads;
  v_first app.contact_links;
  v_second app.contact_links;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmecontact');
  v_tenant2 := (select id from app.tenants where slug = 'betacontact');
  select * into v_contact from app.contacts where full_name = 'Budi Santoso';
  select * into v_lead from app.leads where email = 'jane@contosocontact.test';
  select * into v_other_lead from app.leads where email = 'other@tenant-contact.test';

  select * into v_first from app.link_contact_to_record(v_contact.id, 'lead', v_lead.id, 'decision_maker', true, '00000000-0000-0000-0000-000000008201', 'tester');
  if v_first.role <> 'decision_maker' or not v_first.is_primary then
    raise exception 'assertion failed: expected role=decision_maker is_primary=true, got role=% is_primary=%', v_first.role, v_first.is_primary;
  end if;

  select * into v_second from app.link_contact_to_record(v_contact.id, 'lead', v_lead.id, 'decision_maker', true, '00000000-0000-0000-0000-000000008201', 'tester');
  if v_second.id <> v_first.id then
    raise exception 'assertion failed: expected the retry to return the same link row, got a different id';
  end if;

  select count(*) into v_count from app.contact_links where contact_id = v_contact.id and related_type = 'lead' and related_id = v_lead.id and role = 'decision_maker';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 link row, found %', v_count;
  end if;

  begin
    perform app.link_contact_to_record(v_contact.id, 'lead', v_other_lead.id, 'billing', false, '00000000-0000-0000-0000-000000008201', 'tester');
    raise exception 'assertion failed: expected cross_tenant_link_denied linking a tenant1 contact to a tenant2 lead';
  exception
    when insufficient_privilege then
      null; -- expected (cross_tenant_link_denied raises with this errcode)
  end;

  begin
    perform app.link_contact_to_record(v_contact.id, 'lead', v_lead.id, 'billing', false, '00000000-0000-0000-0000-000000008204', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege for an actor with no access to the contact/lead';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> log_activity: requires access to the linked record, contact tenant-checked, produces a real timeline row'
do $$
declare
  v_lead app.leads;
  v_contact app.contacts;
  v_activity app.activities;
begin
  select * into v_lead from app.leads where email = 'jane@contosocontact.test';
  select * into v_contact from app.contacts where full_name = 'Budi Santoso';

  select * into v_activity from app.log_activity(
    'lead', v_lead.id, v_contact.id, 'call', 'Intro call', 'Discussed requirements', 'completed', null, now(), 'Positive, will send quote',
    null, null, '00000000-0000-0000-0000-000000008201', 'tester'
  );
  if v_activity.status <> 'completed' or v_activity.completed_at is null then
    raise exception 'assertion failed: expected status=completed with completed_at set, got status=% completed_at=%', v_activity.status, v_activity.completed_at;
  end if;

  select * into v_activity from app.log_activity(
    'lead', v_lead.id, null, 'follow_up', 'Send quotation', null, 'scheduled', now() + interval '3 days', null, null,
    null, null, '00000000-0000-0000-0000-000000008201', 'tester'
  );
  if v_activity.status <> 'scheduled' or v_activity.due_at is null then
    raise exception 'assertion failed: expected status=scheduled with due_at set, got status=% due_at=%', v_activity.status, v_activity.due_at;
  end if;

  begin
    perform app.log_activity('lead', v_lead.id, null, 'call', 'Denied', null, 'completed', null, now(), null, null, null, '00000000-0000-0000-0000-000000008204', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege for an actor with no access to this lead';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> record-scope read: owner and ancestor-org-unit manager see the contact/activity; a sibling-team outsider does not'
do $$
declare
  v_contact_id uuid;
  v_activity_id uuid;
  v_count integer;
begin
  v_contact_id := (select id from app.contacts where full_name = 'Budi Santoso');
  v_activity_id := (select id from app.activities where subject = 'Intro call');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008201", "role": "authenticated"}';
  select count(*) into v_count from app.contacts where id = v_contact_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the owning rep to see their own contact'; end if;
  select count(*) into v_count from app.activities where id = v_activity_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the owning rep to see their own activity'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008202", "role": "authenticated"}';
  select count(*) into v_count from app.contacts where id = v_contact_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the branch manager (ancestor org unit) to see a team member''s contact'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008203", "role": "authenticated"}';
  select count(*) into v_count from app.contacts where id = v_contact_id;
  if v_count <> 0 then raise exception 'assertion failed: expected the sibling-team outsider to be denied, found % row(s)', v_count; end if;
  select count(*) into v_count from app.activities where id = v_activity_id;
  if v_count <> 0 then raise exception 'assertion failed: expected the sibling-team outsider to be denied for the activity, found % row(s)', v_count; end if;
  reset role;
end;
$$;

\echo '>> complete_activity / reschedule_activity / cancel_activity: optimistic concurrency and transition validity'
do $$
declare
  v_activity app.activities;
begin
  select * into v_activity from app.activities where subject = 'Send quotation';

  begin
    perform app.complete_activity(v_activity.id, v_activity.record_version + 1, 'done', '00000000-0000-0000-0000-000000008201', 'tester');
    raise exception 'assertion failed: expected serialization_failure for a stale expected_version';
  exception
    when serialization_failure then
      null; -- expected
  end;

  select * into v_activity from app.reschedule_activity(v_activity.id, v_activity.record_version, now() + interval '7 days', '00000000-0000-0000-0000-000000008201', 'tester');
  if v_activity.record_version <> 2 then
    raise exception 'assertion failed: expected record_version=2 after reschedule, got %', v_activity.record_version;
  end if;

  select * into v_activity from app.complete_activity(v_activity.id, v_activity.record_version, 'Quote sent', '00000000-0000-0000-0000-000000008201', 'tester');
  if v_activity.status <> 'completed' or v_activity.outcome <> 'Quote sent' then
    raise exception 'assertion failed: expected status=completed with outcome set, got status=% outcome=%', v_activity.status, v_activity.outcome;
  end if;

  begin
    perform app.cancel_activity(v_activity.id, v_activity.record_version, '00000000-0000-0000-0000-000000008201', 'tester');
    raise exception 'assertion failed: expected check_violation cancelling an already-completed activity';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> unlink_contact_from_record: requires access, removes the link row'
do $$
declare
  v_link app.contact_links;
  v_count integer;
begin
  select * into v_link from app.contact_links where role = 'decision_maker';
  perform app.unlink_contact_from_record(v_link.id, '00000000-0000-0000-0000-000000008201', 'tester');

  select count(*) into v_count from app.contact_links where id = v_link.id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the link row to be removed, found %', v_count;
  end if;
end;
$$;

\echo '>> audit trail: create/link/log/complete/unlink all recorded real app.audit_logs events'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.contacts' and action = 'create_contact';
  if v_count < 1 then raise exception 'assertion failed: expected at least 1 create_contact audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.contact_links' and action = 'link_contact_to_record';
  if v_count < 1 then raise exception 'assertion failed: expected at least 1 link_contact_to_record audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.activities' and action = 'log_activity';
  if v_count < 2 then raise exception 'assertion failed: expected at least 2 log_activity audit events, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.activities' and action = 'complete_activity';
  if v_count < 1 then raise exception 'assertion failed: expected at least 1 complete_activity audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.contact_links' and action = 'unlink_contact_from_record';
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 unlink_contact_from_record audit event, found %', v_count; end if;
end;
$$;
