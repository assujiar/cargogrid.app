-- Real, executable test evidence for COM-144 (Prospect Lifecycle, CG-S7-COM-003) -- run
-- via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/branch/department org hierarchy, a rep, a branch manager, an outsider, and pre-captured leads in various states'
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
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000008101', 'rep@acmeprospect.test'),
    ('00000000-0000-0000-0000-000000008102', 'manager@acmeprospect.test'),
    ('00000000-0000-0000-0000-000000008103', 'outsider@acmeprospect.test'),
    ('00000000-0000-0000-0000-000000008104', 'other-tenant-rep@betaprospect.test');

  perform app.provision_tenant('acmeprospect', 'Acme Prospect Co', 'idem-acmeprospect', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeprospect');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betaprospect', 'Beta Prospect Co', 'idem-betaprospect', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betaprospect');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEPROSPECT-CO', 'Acme Prospect Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROSPECT-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEPROSPECT-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROSPECT-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEPROSPECT-TEAM-A', 'Sales Team A', 'tester');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROSPECT-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEPROSPECT-TEAM-B', 'Sales Team B', 'tester');
  v_other_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROSPECT-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008101', 'rep@acmeprospect.test', 'Rep', v_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeprospect.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008102', 'manager@acmeprospect.test', 'Branch Manager', v_branch, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmeprospect.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008103', 'outsider@acmeprospect.test', 'Outsider', v_other_team, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeprospect.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000008104', 'other-tenant-rep@betaprospect.test', 'Other Tenant Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'other-tenant-rep@betaprospect.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Sales Rep', 'lead/prospect capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Assign')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008101', '00000000-0000-0000-0000-000000008101', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008102', '00000000-0000-0000-0000-000000008101', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008103', '00000000-0000-0000-0000-000000008101', 'tester');

  v_rep_role := (app.create_role(v_tenant2, 'Sales Rep', 'lead/prospect capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Assign')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008104', '00000000-0000-0000-0000-000000008104', 'tester');

  -- Pre-captured leads in various states this suite's own scenario groups need.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Prospect Ltd', 'Jane Prospect', 'jane@contosoprospect.test', '0811',
    '00000000-0000-0000-0000-000000008101', v_team, '00000000-0000-0000-0000-000000008101', 'tester');
  perform app.capture_lead(v_tenant1, 'manual', null, 'New Status Co', 'New Status', 'new@status.test', '0822',
    '00000000-0000-0000-0000-000000008101', v_team, '00000000-0000-0000-0000-000000008101', 'tester');
  perform app.capture_lead(v_tenant1, 'manual', null, 'Second Qualified Co', 'Second Qualified', 'second@qualified.test', '0833',
    '00000000-0000-0000-0000-000000008101', v_team, '00000000-0000-0000-0000-000000008101', 'tester');
  perform app.capture_lead(v_tenant2, 'manual', null, 'Other Tenant Co', 'Other Tenant', 'other@tenant.test', '0844',
    '00000000-0000-0000-0000-000000008104', null, '00000000-0000-0000-0000-000000008104', 'tester');
end;
$$;

\echo '>> qualify the leads this suite needs qualified'
do $$
declare
  v_lead app.leads;
begin
  select * into v_lead from app.leads where email = 'jane@contosoprospect.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008101', 'tester');

  select * into v_lead from app.leads where email = 'second@qualified.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008101', 'tester');

  select * into v_lead from app.leads where email = 'other@tenant.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008104', 'tester');
end;
$$;

\echo '>> convert_lead_to_prospect: idempotent, requires qualified status, requires access'
do $$
declare
  v_lead app.leads;
  v_first app.prospects;
  v_second app.prospects;
  v_count integer;
begin
  select * into v_lead from app.leads where email = 'jane@contosoprospect.test';

  select * into v_first from app.convert_lead_to_prospect(
    v_lead.id, 'Contoso Prospect Ltd', 'Contoso', '01.234.567.8-901.000', '{"city": "Jakarta"}'::jsonb,
    '00000000-0000-0000-0000-000000008101', 'tester'
  );
  if v_first.status <> 'active' then
    raise exception 'assertion failed: expected status=active, got %', v_first.status;
  end if;
  if v_first.contact_email <> 'jane@contosoprospect.test' then
    raise exception 'assertion failed: expected contact snapshot from the lead, got %', v_first.contact_email;
  end if;

  -- Retry: idempotent on lead_id, never a second prospect.
  select * into v_second from app.convert_lead_to_prospect(
    v_lead.id, 'Different Name Entirely', null, null, '{}'::jsonb,
    '00000000-0000-0000-0000-000000008101', 'tester'
  );
  if v_second.id <> v_first.id or v_second.legal_name <> 'Contoso Prospect Ltd' then
    raise exception 'assertion failed: retry with the same lead_id must return the original prospect unchanged, got id=% legal_name=%', v_second.id, v_second.legal_name;
  end if;

  select count(*) into v_count from app.prospects where lead_id = v_lead.id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 prospect for lead %, found %', v_lead.id, v_count;
  end if;

  -- The source lead itself is now converted, with a real lineage pointer.
  select * into v_lead from app.leads where id = v_lead.id;
  if v_lead.status <> 'converted' or v_lead.converted_prospect_id <> v_first.id then
    raise exception 'assertion failed: expected lead status=converted with converted_prospect_id set, got status=% converted_prospect_id=%', v_lead.status, v_lead.converted_prospect_id;
  end if;
end;
$$;

\echo '>> convert_lead_to_prospect: an unqualified (status=new) lead is rejected'
do $$
declare
  v_lead app.leads;
begin
  select * into v_lead from app.leads where email = 'new@status.test';
  begin
    perform app.convert_lead_to_prospect(v_lead.id, 'New Status Co', null, null, '{}'::jsonb, '00000000-0000-0000-0000-000000008101', 'tester');
    raise exception 'assertion failed: expected check_violation converting a non-qualified lead';
  exception
    when sqlstate '23514' then
      null; -- expected (check_violation)
  end;
end;
$$;

\echo '>> get_prospect_conversion_readiness: fixed deterministic rule set'
do $$
declare
  v_lead app.leads;
  v_prospect app.prospects;
  v_ready boolean;
  v_missing text[];
begin
  select * into v_lead from app.leads where email = 'second@qualified.test';
  select * into v_prospect from app.convert_lead_to_prospect(
    v_lead.id, 'Second Qualified Co', null, null, '{}'::jsonb, '00000000-0000-0000-0000-000000008101', 'tester'
  );

  select ready, missing into v_ready, v_missing from app.get_prospect_conversion_readiness(v_prospect.id);
  if v_ready then
    raise exception 'assertion failed: expected not-ready (no tax_id/billing_address), got ready=true';
  end if;
  if not ('tax_id' = any(v_missing) and 'billing_address' = any(v_missing)) then
    raise exception 'assertion failed: expected tax_id and billing_address in missing list, got %', v_missing;
  end if;

  update app.prospects set tax_id = '99.888.777.6-000.000', billing_address = '{"city": "Bandung"}'::jsonb where id = v_prospect.id;
  select ready, missing into v_ready, v_missing from app.get_prospect_conversion_readiness(v_prospect.id);
  if not v_ready then
    raise exception 'assertion failed: expected ready=true once all fixed fields are present, got missing=%', v_missing;
  end if;
end;
$$;

\echo '>> find_duplicate_prospects: tenant-scoped, fails closed on missing membership'
do $$
declare
  v_dupe_count integer;
begin
  select count(*) into v_dupe_count from app.find_duplicate_prospects(
    (select id from app.tenants where slug = 'acmeprospect'), '00000000-0000-0000-0000-000000008101', 'Contoso Prospect Ltd', '01.234.567.8-901.000'
  );
  if v_dupe_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 duplicate candidate, found %', v_dupe_count;
  end if;

  begin
    perform app.find_duplicate_prospects(
      (select id from app.tenants where slug = 'acmeprospect'), '00000000-0000-0000-0000-000000008104', 'Contoso Prospect Ltd', null
    );
    raise exception 'assertion failed: expected insufficient_privilege for an actor with no membership in this tenant';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> record-scope read: owner and ancestor-org-unit manager see the prospect; a sibling-team outsider does not'
do $$
declare
  v_prospect_id uuid;
  v_count integer;
begin
  v_prospect_id := (select id from app.prospects where legal_name = 'Contoso Prospect Ltd');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008101", "role": "authenticated"}';
  select count(*) into v_count from app.prospects where id = v_prospect_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owning rep to see their own prospect';
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008102", "role": "authenticated"}';
  select count(*) into v_count from app.prospects where id = v_prospect_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the branch manager (ancestor org unit) to see a team member''s prospect';
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008103", "role": "authenticated"}';
  select count(*) into v_count from app.prospects where id = v_prospect_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to be denied, found % row(s)', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> disqualify_prospect / archive_prospect: optimistic concurrency, mandatory disqualify reason, distinct transitions'
do $$
declare
  v_prospect app.prospects;
begin
  select * into v_prospect from app.prospects where legal_name = 'Second Qualified Co';

  begin
    perform app.disqualify_prospect(v_prospect.id, v_prospect.record_version, '  ', '00000000-0000-0000-0000-000000008101', 'tester');
    raise exception 'assertion failed: expected not_null_violation for a blank disqualify reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  select * into v_prospect from app.disqualify_prospect(v_prospect.id, v_prospect.record_version, 'No budget this cycle', '00000000-0000-0000-0000-000000008101', 'tester');
  if v_prospect.status <> 'disqualified' or v_prospect.disqualify_reason <> 'No budget this cycle' then
    raise exception 'assertion failed: expected status=disqualified with reason set, got status=% reason=%', v_prospect.status, v_prospect.disqualify_reason;
  end if;

  begin
    perform app.archive_prospect(v_prospect.id, v_prospect.record_version, '00000000-0000-0000-0000-000000008101', 'tester');
    raise exception 'assertion failed: expected check_violation archiving an already-disqualified prospect';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> merge_prospects: lineage preserved, cross-tenant denied, re-merge rejected'
do $$
declare
  v_tenant1 uuid;
  v_team uuid;
  v_survivor app.prospects;
  v_duplicate_lead app.leads;
  v_duplicate app.prospects;
  v_cross_tenant app.prospects;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeprospect');
  v_team := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPROSPECT-TEAM-A');
  select * into v_survivor from app.prospects where legal_name = 'Contoso Prospect Ltd';

  select * into v_cross_tenant from app.convert_lead_to_prospect(
    (select id from app.leads where email = 'other@tenant.test'), 'Other Tenant Co', null, null, '{}'::jsonb,
    '00000000-0000-0000-0000-000000008104', 'tester'
  );

  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Prospect Duplicate', 'Dup Contact', 'dup-contoso@contosoprospect.test', '0855',
    '00000000-0000-0000-0000-000000008101', v_team, '00000000-0000-0000-0000-000000008101', 'tester');
  select * into v_duplicate_lead from app.leads where email = 'dup-contoso@contosoprospect.test';
  perform app.qualify_lead(v_duplicate_lead.id, v_duplicate_lead.record_version, '00000000-0000-0000-0000-000000008101', 'tester');
  select * into v_duplicate from app.convert_lead_to_prospect(
    v_duplicate_lead.id, 'Contoso Prospect Ltd', null, null, '{}'::jsonb, '00000000-0000-0000-0000-000000008101', 'tester'
  );

  begin
    perform app.merge_prospects(v_survivor.id, v_cross_tenant.id, '00000000-0000-0000-0000-000000008101', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege merging prospects across two different tenants';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  perform app.merge_prospects(v_survivor.id, v_duplicate.id, '00000000-0000-0000-0000-000000008101', 'tester');

  select * into v_duplicate from app.prospects where id = v_duplicate.id;
  if v_duplicate.status <> 'merged' or v_duplicate.merged_into_id <> v_survivor.id then
    raise exception 'assertion failed: expected the duplicate to be status=merged with merged_into_id=survivor, got status=% merged_into_id=%', v_duplicate.status, v_duplicate.merged_into_id;
  end if;

  begin
    perform app.merge_prospects(v_survivor.id, v_duplicate.id, '00000000-0000-0000-0000-000000008101', 'tester');
    raise exception 'assertion failed: expected check_violation re-merging an already-merged prospect';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> audit trail: convert/disqualify/archive/merge all recorded real app.audit_logs events'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.prospects' and action = 'convert_lead_to_prospect';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 convert_lead_to_prospect audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.prospects' and action = 'disqualify_prospect';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 disqualify_prospect audit event, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.prospects' and action = 'merge_prospects';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 merge_prospects audit event, found %', v_count;
  end if;
end;
$$;
