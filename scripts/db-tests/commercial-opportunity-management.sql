-- Real, executable test evidence for COM-147 (Opportunity Management, CG-S7-COM-006) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a company/branch/team-a/team-b org hierarchy, a rep (COM:View selling price), a branch manager (COM:Approve, no selling price), a sibling-team outsider, and a team-A prospect'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_mgr_role uuid;
  v_mgr_draft app.role_versions;
  v_out_role uuid;
  v_out_draft app.role_versions;
  v_t2_role uuid;
  v_t2_draft app.role_versions;
  v_lead app.leads;
  v_lead2 app.leads;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000008401', 'rep@acmeopp.test'),
    ('00000000-0000-0000-0000-000000008402', 'manager@acmeopp.test'),
    ('00000000-0000-0000-0000-000000008403', 'outsider@acmeopp.test'),
    ('00000000-0000-0000-0000-000000008404', 'other-tenant-rep@betaopp.test');

  perform app.provision_tenant('acmeopp', 'Acme Opportunity Co', 'idem-acmeopp', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeopp');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betaopp', 'Beta Opportunity Co', 'idem-betaopp', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betaopp');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEOPP-CO', 'Acme Opportunity Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPP-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEOPP-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPP-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEOPP-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPP-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEOPP-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPP-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008401', 'rep@acmeopp.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeopp.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008402', 'manager@acmeopp.test', 'Branch Manager', v_branch, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmeopp.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008403', 'outsider@acmeopp.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeopp.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000008404', 'other-tenant-rep@betaopp.test', 'Other Tenant Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'other-tenant-rep@betaopp.test'), 'active', 'onboarded', 'tester');

  -- Manager first: Create/View/Edit/Approve, deliberately WITHOUT 'View selling price' --
  -- no protected permission in this set, so self-assignment is fine, and the manager can
  -- then act as the assigning actor for the two protected-permission grants below
  -- (app.assign_role's self-escalation guard only fires when actor = grantee AND the role
  -- version carries a protected permission -- 'View selling price' is protected=true).
  v_mgr_role := (app.create_role(v_tenant1, 'Sales Manager', 'opportunity governance', 'tester')).id;
  v_mgr_draft := app.create_role_version(v_mgr_role, 'tester');
  perform app.set_role_version_permissions(
    v_mgr_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'Approve')),
    'tester'
  );
  perform app.publish_role_version(v_mgr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_mgr_role and status = 'published'),
    '00000000-0000-0000-0000-000000008402', '00000000-0000-0000-0000-000000008402', 'tester');

  -- Rep: Create/View/Edit plus the seeded, protected 'View selling price' -- assigned by
  -- the manager (a distinct actor), not self-assigned.
  v_rep_role := (app.create_role(v_tenant1, 'Sales Rep', 'opportunity capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'View selling price')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008401', '00000000-0000-0000-0000-000000008402', 'tester');

  -- Outsider: same Sales Rep permission set as rep (Create/View/Edit/View selling price),
  -- different org unit -- also assigned by the manager.
  v_out_role := (app.create_role(v_tenant1, 'Team B Rep', 'sibling team', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'View selling price')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000008403', '00000000-0000-0000-0000-000000008402', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'Sales Rep', 'opportunity capture', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(
    v_t2_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'Approve')),
    'tester'
  );
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'),
    '00000000-0000-0000-0000-000000008404', '00000000-0000-0000-0000-000000008404', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Opportunity Ltd', 'Jane Doe', 'jane@contosoopp.test', '0811',
    '00000000-0000-0000-0000-000000008401', v_team_a, '00000000-0000-0000-0000-000000008401', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosoopp.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008401', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosoopp.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Contoso Opportunity Ltd', null, '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000008401', 'tester');

  perform app.capture_lead(v_tenant2, 'manual', null, 'Other Tenant Co', 'Other Tenant', 'other@tenant-opp.test', '0822',
    '00000000-0000-0000-0000-000000008404', null, '00000000-0000-0000-0000-000000008404', 'tester');
  select * into v_lead2 from app.leads where email = 'other@tenant-opp.test';
  perform app.qualify_lead(v_lead2.id, v_lead2.record_version, '00000000-0000-0000-0000-000000008404', 'tester');
  select * into v_lead2 from app.leads where email = 'other@tenant-opp.test';
  perform app.convert_lead_to_prospect(v_lead2.id, 'Other Tenant Co', null, '02.345.678.9-012.000',
    jsonb_build_object('line1', 'Other St 2', 'city', 'Elsewhere', 'country', 'ID'),
    '00000000-0000-0000-0000-000000008404', 'tester');
end;
$$;

\echo '>> create_opportunity: requires prospect access and COM:Create, starts qualifying/probability=10, cross-tenant prospect denied'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_prospect app.prospects;
  v_other_prospect app.prospects;
  v_opportunity app.opportunities;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeopp');
  v_tenant2 := (select id from app.tenants where slug = 'betaopp');
  select * into v_prospect from app.prospects where legal_name = 'Contoso Opportunity Ltd';
  select * into v_other_prospect from app.prospects where legal_name = 'Other Tenant Co';

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Contoso freight lane', jsonb_build_object('service_type', 'freight_forwarding'),
    '00000000-0000-0000-0000-000000008401', null, '00000000-0000-0000-0000-000000008401', 'tester'
  );
  if v_opportunity.stage <> 'qualifying' or v_opportunity.probability <> 10 then
    raise exception 'assertion failed: expected stage=qualifying probability=10, got stage=% probability=%', v_opportunity.stage, v_opportunity.probability;
  end if;

  begin
    perform app.create_opportunity(
      v_tenant1, v_other_prospect.id, 'Cross tenant attempt', '{}'::jsonb,
      '00000000-0000-0000-0000-000000008401', null, '00000000-0000-0000-0000-000000008401', 'tester'
    );
    raise exception 'assertion failed: expected cross_tenant_prospect_denied for a tenant2 prospect under tenant1';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> update_opportunity: setting value requires COM:View selling price in addition to Edit; blocked once closed'
do $$
declare
  v_opportunity app.opportunities;
begin
  select * into v_opportunity from app.opportunities where name = 'Contoso freight lane';

  select * into v_opportunity from app.update_opportunity(
    v_opportunity.id, v_opportunity.record_version, null, null, 'Send initial proposal', now() + interval '3 days',
    15000000.00, 'IDR', '00000000-0000-0000-0000-000000008401', 'tester'
  );
  if v_opportunity.value_amount <> 15000000.00 or v_opportunity.value_currency <> 'IDR' then
    raise exception 'assertion failed: expected value_amount=15000000.00 value_currency=IDR, got %/%', v_opportunity.value_amount, v_opportunity.value_currency;
  end if;

  begin
    perform app.update_opportunity(
      v_opportunity.id, v_opportunity.record_version, null, null, null, null,
      99999999.00, 'USD', '00000000-0000-0000-0000-000000008402', 'tester'
    );
    raise exception 'assertion failed: expected insufficient_privilege -- manager lacks COM:View selling price';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> transition_opportunity_stage: forward moves, invalid stage rejected, stale version rejected, close requires reason + COM:Approve'
do $$
declare
  v_opportunity app.opportunities;
begin
  select * into v_opportunity from app.opportunities where name = 'Contoso freight lane';

  select * into v_opportunity from app.transition_opportunity_stage(
    v_opportunity.id, v_opportunity.record_version, 'requirements_gathering', null, null,
    '00000000-0000-0000-0000-000000008401', 'tester'
  );
  if v_opportunity.stage <> 'requirements_gathering' or v_opportunity.probability <> 30 then
    raise exception 'assertion failed: expected stage=requirements_gathering probability=30, got %/%', v_opportunity.stage, v_opportunity.probability;
  end if;

  begin
    perform app.transition_opportunity_stage(v_opportunity.id, v_opportunity.record_version + 1, 'ready_for_costing', null, null, '00000000-0000-0000-0000-000000008401', 'tester');
    raise exception 'assertion failed: expected serialization_failure for a stale expected_version';
  exception
    when serialization_failure then
      null; -- expected
  end;

  begin
    perform app.transition_opportunity_stage(v_opportunity.id, v_opportunity.record_version, 'teleported', null, null, '00000000-0000-0000-0000-000000008401', 'tester');
    raise exception 'assertion failed: expected check_violation for a non-canonical stage';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_opportunity from app.transition_opportunity_stage(
    v_opportunity.id, v_opportunity.record_version, 'ready_for_costing', null, null,
    '00000000-0000-0000-0000-000000008401', 'tester'
  );

  begin
    perform app.transition_opportunity_stage(v_opportunity.id, v_opportunity.record_version, 'lost', null, null, '00000000-0000-0000-0000-000000008401', 'tester');
    raise exception 'assertion failed: expected not_null_violation -- closing requires a non-empty reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  begin
    perform app.transition_opportunity_stage(v_opportunity.id, v_opportunity.record_version, 'won', null, 'Client signed', '00000000-0000-0000-0000-000000008401', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- closing requires COM:Approve, rep does not hold it';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_opportunity from app.transition_opportunity_stage(
    v_opportunity.id, v_opportunity.record_version, 'won', null, 'Client signed the deal',
    '00000000-0000-0000-0000-000000008402', 'tester'
  );
  if v_opportunity.stage <> 'won' or v_opportunity.probability <> 100 or v_opportunity.close_reason <> 'Client signed the deal' then
    raise exception 'assertion failed: expected stage=won probability=100 with close_reason set, got stage=% probability=% reason=%', v_opportunity.stage, v_opportunity.probability, v_opportunity.close_reason;
  end if;

  begin
    perform app.transition_opportunity_stage(v_opportunity.id, v_opportunity.record_version, 'lost', null, 'Reopen attempt', '00000000-0000-0000-0000-000000008402', 'tester');
    raise exception 'assertion failed: expected check_violation -- a closed (won) opportunity cannot change stage again';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  begin
    perform app.update_opportunity(v_opportunity.id, v_opportunity.record_version, 'Renamed after close', null, null, null, null, null, '00000000-0000-0000-0000-000000008401', 'tester');
    raise exception 'assertion failed: expected check_violation -- a closed opportunity cannot be edited';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> clone_opportunity: new row, cloned_from_id set, stage/probability reset, requires access to source'
do $$
declare
  v_source app.opportunities;
  v_clone app.opportunities;
begin
  select * into v_source from app.opportunities where name = 'Contoso freight lane';

  select * into v_clone from app.clone_opportunity(v_source.id, 'Contoso freight lane (renewal)', '00000000-0000-0000-0000-000000008401', 'tester');
  if v_clone.cloned_from_id <> v_source.id or v_clone.stage <> 'qualifying' or v_clone.probability <> 10 then
    raise exception 'assertion failed: expected a fresh qualifying/probability=10 clone linked to the source, got cloned_from_id=% stage=% probability=%', v_clone.cloned_from_id, v_clone.stage, v_clone.probability;
  end if;
  if v_clone.id = v_source.id then
    raise exception 'assertion failed: expected a distinct new row for the clone';
  end if;

  begin
    perform app.clone_opportunity(v_source.id, 'Denied clone', '00000000-0000-0000-0000-000000008403', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- sibling-team outsider cannot access the source opportunity';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> get_opportunity_costing_readiness: fixed deterministic rule set over the requirements snapshot'
do $$
declare
  v_clone app.opportunities;
  v_ready boolean;
  v_missing text[];
begin
  select * into v_clone from app.opportunities where name = 'Contoso freight lane (renewal)';

  select ready, missing into v_ready, v_missing from app.get_opportunity_costing_readiness(v_clone.id, '00000000-0000-0000-0000-000000008401');
  if v_ready then
    raise exception 'assertion failed: expected not ready (only service_type is set)';
  end if;
  if not (v_missing @> array['cargo_description', 'origin', 'destination', 'target_ready_date']) then
    raise exception 'assertion failed: expected 4 missing fields, got %', v_missing;
  end if;

  perform app.update_opportunity(
    v_clone.id, v_clone.record_version, null,
    jsonb_build_object('service_type', 'freight_forwarding', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    null, null, null, null, '00000000-0000-0000-0000-000000008401', 'tester'
  );

  select ready, missing into v_ready, v_missing from app.get_opportunity_costing_readiness(v_clone.id, '00000000-0000-0000-0000-000000008401');
  if not v_ready or array_length(v_missing, 1) is not null then
    raise exception 'assertion failed: expected ready=true with zero missing fields, got ready=% missing=%', v_ready, v_missing;
  end if;
end;
$$;

\echo '>> opportunities_directory: value/probability masked without COM:View selling price, visible with it'
do $$
declare
  v_opportunity_id uuid;
  v_masked boolean;
  v_value numeric;
  v_probability integer;
begin
  v_opportunity_id := (select id from app.opportunities where name = 'Contoso freight lane (renewal)');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008402", "role": "authenticated"}';
  select value_masked, value_amount, probability into v_masked, v_value, v_probability from app.opportunities_directory where id = v_opportunity_id;
  if not v_masked or v_value is not null or v_probability is not null then
    raise exception 'assertion failed: expected value_masked=true and null value/probability for the manager (no View selling price), got masked=% value=% probability=%', v_masked, v_value, v_probability;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008401", "role": "authenticated"}';
  select value_masked, probability into v_masked, v_probability from app.opportunities_directory where id = v_opportunity_id;
  if v_masked or v_probability is null then
    raise exception 'assertion failed: expected value_masked=false and a real probability for the rep (holds View selling price), got masked=% probability=%', v_masked, v_probability;
  end if;
  reset role;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has no direct column access to value_amount/value_currency/probability on app.opportunities itself'
do $$
declare
  v_opportunity_id uuid;
begin
  v_opportunity_id := (select id from app.opportunities where name = 'Contoso freight lane (renewal)');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008401", "role": "authenticated"}';
  begin
    perform value_amount from app.opportunities where id = v_opportunity_id;
    raise exception 'assertion failed: expected a real Postgres permission-denied error selecting value_amount directly from app.opportunities';
  exception
    when insufficient_privilege then
      null; -- expected (Postgres 42501, undefined_column-shaped denial for the missing column grant)
  end;
  reset role;
end;
$$;

\echo '>> record-scope read: owner and ancestor-org-unit manager see the opportunity/stage-history; a sibling-team outsider does not'
do $$
declare
  v_opportunity_id uuid;
  v_count integer;
begin
  v_opportunity_id := (select id from app.opportunities where name = 'Contoso freight lane (renewal)');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008401", "role": "authenticated"}';
  select count(*) into v_count from app.opportunities where id = v_opportunity_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the owning rep to see their own opportunity'; end if;
  select count(*) into v_count from app.opportunity_stage_history where opportunity_id = v_opportunity_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the owning rep to see the stage history row'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008402", "role": "authenticated"}';
  select count(*) into v_count from app.opportunities where id = v_opportunity_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the branch manager (ancestor org unit) to see the opportunity'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008403", "role": "authenticated"}';
  select count(*) into v_count from app.opportunities where id = v_opportunity_id;
  if v_count <> 0 then raise exception 'assertion failed: expected the sibling-team outsider to be denied, found % row(s)', v_count; end if;
  select count(*) into v_count from app.opportunity_stage_history where opportunity_id = v_opportunity_id;
  if v_count <> 0 then raise exception 'assertion failed: expected the sibling-team outsider to be denied for stage history, found % row(s)', v_count; end if;
  reset role;
end;
$$;

\echo '>> resolve_commercial_record_ref extension: opportunity is a valid related_type for contact_links/activities'
do $$
declare
  v_opportunity app.opportunities;
  v_contact app.contacts;
  v_link app.contact_links;
  v_activity app.activities;
begin
  select * into v_opportunity from app.opportunities where name = 'Contoso freight lane (renewal)';

  select * into v_contact from app.create_contact(
    v_opportunity.tenant_id, 'Budi Santoso', 'Procurement Manager', 'budi@contosoopp.test', '0812-3456-7890',
    '00000000-0000-0000-0000-000000008401', v_opportunity.org_unit_id, '00000000-0000-0000-0000-000000008401', 'tester'
  );

  select * into v_link from app.link_contact_to_record(v_contact.id, 'opportunity', v_opportunity.id, 'decision_maker', true, '00000000-0000-0000-0000-000000008401', 'tester');
  if v_link.related_type <> 'opportunity' then
    raise exception 'assertion failed: expected a contact_links row with related_type=opportunity, got %', v_link.related_type;
  end if;

  select * into v_activity from app.log_activity(
    'opportunity', v_opportunity.id, v_contact.id, 'call', 'Discuss freight lane', 'Reviewed requirements', 'completed', null, now(), 'Positive',
    null, null, '00000000-0000-0000-0000-000000008401', 'tester'
  );
  if v_activity.related_type <> 'opportunity' then
    raise exception 'assertion failed: expected an activities row with related_type=opportunity, got %', v_activity.related_type;
  end if;
end;
$$;

\echo '>> audit trail: create/update/transition/clone all recorded real app.audit_logs events'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.opportunities' and action = 'create_opportunity';
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 create_opportunity audit event (the denied cross-tenant attempt never inserted a row), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.opportunities' and action = 'update_opportunity';
  if v_count < 1 then raise exception 'assertion failed: expected at least 1 update_opportunity audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.opportunities' and action = 'transition_opportunity_stage';
  if v_count <> 3 then raise exception 'assertion failed: expected exactly 3 transition_opportunity_stage audit events (requirements_gathering, ready_for_costing, won -- every denied/invalid attempt inserted nothing), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.opportunities' and action = 'clone_opportunity';
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 clone_opportunity audit event, found %', v_count; end if;
end;
$$;
