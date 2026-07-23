-- Real, executable test evidence for COM-143 (Lead Management, CG-S7-COM-002) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database. The first
-- business-domain (Commercial) capability to exercise app.can_access_record() (PLT-114)
-- and app.org_unit_ancestor_ids() (PLT-109) against a real table, composed together.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a company/branch/team org hierarchy, a rep, a branch manager, an outsider, and a Supreme Admin'
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
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000008001', 'rep@acmelead.test'),
    ('00000000-0000-0000-0000-000000008002', 'manager@acmelead.test'),
    ('00000000-0000-0000-0000-000000008003', 'outsider@acmelead.test'),
    ('00000000-0000-0000-0000-000000008004', 'supreme@acmelead.test'),
    ('00000000-0000-0000-0000-000000008005', 'viewer@acmelead.test'),
    ('00000000-0000-0000-0000-000000008006', 'other-tenant-rep@betalead.test');

  perform app.provision_tenant('acmelead', 'Acme Lead Co', 'idem-acmelead', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmelead');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betalead', 'Beta Lead Co', 'idem-betalead', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betalead');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMELEAD-CO', 'Acme Lead Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMELEAD-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMELEAD-TEAM-A', 'Sales Team A', 'tester');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMELEAD-TEAM-B', 'Sales Team B', 'tester');
  v_other_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008001', 'rep@acmelead.test', 'Rep', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmelead.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008002', 'manager@acmelead.test', 'Branch Manager', v_branch, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmelead.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008003', 'outsider@acmelead.test', 'Outsider', v_other_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmelead.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008005', 'viewer@acmelead.test', 'View Only', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmelead.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000008006', 'other-tenant-rep@betalead.test', 'Other Tenant Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'other-tenant-rep@betalead.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000008004', 'supreme_admin', null, null, 'tester');

  -- Sales Rep role: COM:Create, COM:View, COM:Assign.
  v_rep_role := (app.create_role(v_tenant1, 'Sales Rep', 'lead capture/assign', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Assign')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008001', '00000000-0000-0000-0000-000000008001', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008002', '00000000-0000-0000-0000-000000008001', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008003', '00000000-0000-0000-0000-000000008001', 'tester');

  -- View-only role: COM:View only -- no Create/Assign.
  v_viewer_role := (app.create_role(v_tenant1, 'Lead Viewer', 'read only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action = 'View'),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'),
    '00000000-0000-0000-0000-000000008005', '00000000-0000-0000-0000-000000008001', 'tester');

  -- Tenant 2's own Sales Rep role (a fully independent tenant -- never reuses tenant 1's role/version).
  v_rep_role := (app.create_role(v_tenant2, 'Sales Rep', 'lead capture/assign', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Assign')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008006', '00000000-0000-0000-0000-000000008006', 'tester');
end;
$$;

\echo '>> capture_lead: idempotent on (tenant, source, external_reference) -- a retry never creates a second row'
do $$
declare
  v_tenant1 uuid;
  v_team uuid;
  v_first app.leads;
  v_second app.leads;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelead');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-A');

  select * into v_first from app.capture_lead(
    v_tenant1, 'api', 'ext-ref-001', 'Contoso Ltd', 'Jane Doe', 'jane@contoso.test', '+62 812-0000-0001',
    '00000000-0000-0000-0000-000000008001', v_team, '00000000-0000-0000-0000-000000008001', 'tester'
  );
  if v_first.status <> 'new' then
    raise exception 'assertion failed: expected status=new, got %', v_first.status;
  end if;

  select * into v_second from app.capture_lead(
    v_tenant1, 'api', 'ext-ref-001', 'Different Co', 'Different Name', 'different@contoso.test', '000',
    '00000000-0000-0000-0000-000000008001', v_team, '00000000-0000-0000-0000-000000008001', 'tester'
  );
  if v_second.id <> v_first.id or v_second.company_name <> 'Contoso Ltd' then
    raise exception 'assertion failed: retry with same external_reference must return the original row unchanged, got id=% company=%', v_second.id, v_second.company_name;
  end if;

  select count(*) into v_count from app.leads where tenant_id = v_tenant1 and external_reference = 'ext-ref-001';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 row for external_reference=ext-ref-001, found %', v_count;
  end if;
end;
$$;

\echo '>> capture_lead: an actor lacking COM:Create is denied'
do $$
declare
  v_tenant1 uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelead');
  begin
    perform app.capture_lead(
      v_tenant1, 'manual', null, 'Denied Co', 'No Access', 'no-access@denied.test', null,
      '00000000-0000-0000-0000-000000008005', null, '00000000-0000-0000-0000-000000008005', 'tester'
    );
    raise exception 'assertion failed: expected insufficient_privilege for a view-only actor, but capture succeeded';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> compute_lead_score: deterministic, explainable, capped at 100'
do $$
declare
  v_tenant1 uuid;
  v_team uuid;
  v_lead app.leads;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelead');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-A');

  select * into v_lead from app.capture_lead(
    v_tenant1, 'referral', null, 'Fully Scored Inc', 'Full Score', 'full@score.test', '+62 812-0000-0002',
    '00000000-0000-0000-0000-000000008001', v_team, '00000000-0000-0000-0000-000000008001', 'tester'
  );
  -- email(20) + phone(20) + company(15) + referral(15) = 70, no external_reference.
  if v_lead.score <> 70 then
    raise exception 'assertion failed: expected score=70 for email+phone+company+referral, got %', v_lead.score;
  end if;
  if jsonb_array_length(v_lead.score_explanation -> 'rules') <> 4 then
    raise exception 'assertion failed: expected 4 contributing rules in the explanation, got %', jsonb_array_length(v_lead.score_explanation -> 'rules');
  end if;

  select * into v_lead from app.capture_lead(
    v_tenant1, 'campaign', 'ext-ref-max', 'Max Score Inc', 'Max Score', 'max@score.test', '+62 812-0000-0003',
    '00000000-0000-0000-0000-000000008001', v_team, '00000000-0000-0000-0000-000000008001', 'tester'
  );
  -- email(20) + phone(20) + company(15) + campaign(15) + external_reference(30) = 100 exactly.
  if v_lead.score <> 100 then
    raise exception 'assertion failed: expected score=100 (capped), got %', v_lead.score;
  end if;
end;
$$;

\echo '>> find_duplicate_leads: matches within tenant by normalized email/phone/company, never leaks across tenants'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team uuid;
  v_dupe_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelead');
  v_tenant2 := (select id from app.tenants where slug = 'betalead');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-A');

  perform app.capture_lead(
    v_tenant1, 'manual', null, 'Dup Target Co', 'Dup Target', 'DUP@Target.Test', '(0812) 0000-0009',
    '00000000-0000-0000-0000-000000008001', v_team, '00000000-0000-0000-0000-000000008001', 'tester'
  );
  perform app.capture_lead(
    v_tenant2, 'manual', null, 'Dup Target Co', 'Dup Target', 'dup@target.test', '08120000009',
    '00000000-0000-0000-0000-000000008006', null, '00000000-0000-0000-0000-000000008006', 'tester'
  );

  select count(*) into v_dupe_count from app.find_duplicate_leads(
    v_tenant1, '00000000-0000-0000-0000-000000008001', 'dup@target.test', '0812-0000-0009', 'Dup Target Co'
  );
  if v_dupe_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 duplicate candidate within tenant1 (case/format-insensitive match), found %', v_dupe_count;
  end if;

  begin
    perform app.find_duplicate_leads(
      v_tenant1, '00000000-0000-0000-0000-000000008006', 'dup@target.test', '0812-0000-0009', 'Dup Target Co'
    );
    raise exception 'assertion failed: expected insufficient_privilege for an actor with no membership in tenant1';
  exception
    when insufficient_privilege then
      null; -- expected -- proves search cannot be used to probe another tenant
  end;
end;
$$;

\echo '>> record-scope read: owner, ancestor-org-unit manager, and Supreme Admin see the lead; a same-tenant outsider on a sibling team does not'
do $$
declare
  v_tenant1 uuid;
  v_team uuid;
  v_lead_id uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelead');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-A');
  v_lead_id := (select id from app.leads where tenant_id = v_tenant1 and email = 'jane@contoso.test');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008001", "role": "authenticated"}';
  select count(*) into v_count from app.leads where id = v_lead_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owning rep to see their own lead';
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008002", "role": "authenticated"}';
  select count(*) into v_count from app.leads where id = v_lead_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the branch manager (ancestor org unit) to see a team member''s lead';
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008003", "role": "authenticated"}';
  select count(*) into v_count from app.leads where id = v_lead_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to be denied, found % row(s)', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008004", "role": "authenticated"}';
  select count(*) into v_count from app.leads where id = v_lead_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected Supreme Admin to see every lead';
  end if;
  reset role;
end;
$$;

\echo '>> assign_lead: optimistic concurrency, RBAC, and record-scope are all enforced'
do $$
declare
  v_tenant1 uuid;
  v_team uuid;
  v_other_team uuid;
  v_lead app.leads;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelead');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-A');
  v_other_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-B');
  select l.* into v_lead from app.leads l where l.tenant_id = v_tenant1 and l.email = 'jane@contoso.test';

  -- Stale version is rejected.
  begin
    perform app.assign_lead(v_lead.id, v_lead.record_version + 1, '00000000-0000-0000-0000-000000008002', v_team, '00000000-0000-0000-0000-000000008001', 'tester');
    raise exception 'assertion failed: expected serialization_failure for a stale expected_version';
  exception
    when serialization_failure then
      null; -- expected
  end;

  -- A view-only actor (no COM:Assign) is denied.
  begin
    perform app.assign_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008005', v_team, '00000000-0000-0000-0000-000000008005', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege for an actor lacking COM:Assign';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  -- Correct expected_version, authorized actor: reassign to the branch manager, new org unit.
  select * into v_lead from app.assign_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008002', v_other_team, '00000000-0000-0000-0000-000000008001', 'tester');
  if v_lead.owner_user_id <> '00000000-0000-0000-0000-000000008002' or v_lead.org_unit_id <> v_other_team then
    raise exception 'assertion failed: expected ownership/org_unit to transfer, got owner=% org_unit=%', v_lead.owner_user_id, v_lead.org_unit_id;
  end if;
  if v_lead.record_version <> 2 then
    raise exception 'assertion failed: expected record_version=2 after one successful assignment, got %', v_lead.record_version;
  end if;
end;
$$;

\echo '>> qualify_lead / disqualify_lead: transition validity and mandatory disqualify reason'
do $$
declare
  v_tenant1 uuid;
  v_team uuid;
  v_lead app.leads;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelead');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-A');

  select * into v_lead from app.capture_lead(
    v_tenant1, 'manual', null, 'Qualify Co', 'Q Test', 'q@test.test', '0812',
    '00000000-0000-0000-0000-000000008001', v_team, '00000000-0000-0000-0000-000000008001', 'tester'
  );

  select * into v_lead from app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008001', 'tester');
  if v_lead.status <> 'qualified' or v_lead.qualified_at is null then
    raise exception 'assertion failed: expected status=qualified with qualified_at set, got status=% qualified_at=%', v_lead.status, v_lead.qualified_at;
  end if;

  -- Cannot re-qualify an already-qualified lead (not in the allowed-from set).
  begin
    perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008001', 'tester');
    raise exception 'assertion failed: expected check_violation re-qualifying an already-qualified lead';
  exception
    when check_violation then
      null; -- expected
  end;

  -- Disqualify without a reason is rejected before any row is touched.
  begin
    perform app.disqualify_lead(v_lead.id, v_lead.record_version, '   ', '00000000-0000-0000-0000-000000008001', 'tester');
    raise exception 'assertion failed: expected not_null_violation for a blank disqualify reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  select * into v_lead from app.disqualify_lead(v_lead.id, v_lead.record_version, 'Budget frozen this quarter', '00000000-0000-0000-0000-000000008001', 'tester');
  if v_lead.status <> 'disqualified' or v_lead.disqualify_reason <> 'Budget frozen this quarter' then
    raise exception 'assertion failed: expected status=disqualified with the given reason, got status=% reason=%', v_lead.status, v_lead.disqualify_reason;
  end if;
end;
$$;

\echo '>> merge_leads: survivor preserved, duplicate marked merged with lineage; cross-tenant and re-merge are denied'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team uuid;
  v_survivor app.leads;
  v_duplicate app.leads;
  v_cross_tenant app.leads;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelead');
  v_tenant2 := (select id from app.tenants where slug = 'betalead');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELEAD-TEAM-A');

  select * into v_survivor from app.capture_lead(
    v_tenant1, 'manual', null, 'Merge Survivor Co', 'Survivor', 'survivor@merge.test', '0811',
    '00000000-0000-0000-0000-000000008001', v_team, '00000000-0000-0000-0000-000000008001', 'tester'
  );
  select * into v_duplicate from app.capture_lead(
    v_tenant1, 'manual', null, 'Merge Survivor Co', 'Survivor Dup', 'survivor-dup@merge.test', '0822',
    '00000000-0000-0000-0000-000000008001', v_team, '00000000-0000-0000-0000-000000008001', 'tester'
  );
  select * into v_cross_tenant from app.capture_lead(
    v_tenant2, 'manual', null, 'Other Tenant Co', 'Other', 'other@merge.test', '0833',
    '00000000-0000-0000-0000-000000008006', null, '00000000-0000-0000-0000-000000008006', 'tester'
  );

  begin
    perform app.merge_leads(v_survivor.id, v_cross_tenant.id, '00000000-0000-0000-0000-000000008001', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege merging leads across two different tenants';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  perform app.merge_leads(v_survivor.id, v_duplicate.id, '00000000-0000-0000-0000-000000008001', 'tester');

  select * into v_duplicate from app.leads where id = v_duplicate.id;
  if v_duplicate.status <> 'merged' or v_duplicate.merged_into_id <> v_survivor.id then
    raise exception 'assertion failed: expected the duplicate to be status=merged with merged_into_id=survivor, got status=% merged_into_id=%', v_duplicate.status, v_duplicate.merged_into_id;
  end if;

  begin
    perform app.merge_leads(v_survivor.id, v_duplicate.id, '00000000-0000-0000-0000-000000008001', 'tester');
    raise exception 'assertion failed: expected check_violation re-merging an already-merged lead';
  exception
    when check_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> audit trail: capture/assign/qualify/disqualify/merge all recorded real app.audit_logs events'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.leads' and action = 'capture_lead';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 capture_lead audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.leads' and action = 'assign_lead';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 assign_lead audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.leads' and action = 'qualify_lead';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 qualify_lead audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.leads' and action = 'disqualify_lead';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 disqualify_lead audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.leads' and action = 'merge_leads';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 merge_leads audit event, found %', v_count;
  end if;
end;
$$;
