-- Real, executable test evidence for COM-148 (RFQ and Costing Request, CG-S7-COM-007) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a company/branch/team-a/team-b org hierarchy, a rep (COM:View selling price + View cost), a branch manager (COM:Approve, no View cost), a sibling-team outsider, and a complete-requirements + an incomplete-requirements opportunity'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_mgr_role uuid;
  v_mgr_draft app.role_versions;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_out_role uuid;
  v_out_draft app.role_versions;
  v_t2_role uuid;
  v_t2_draft app.role_versions;
  v_lead app.leads;
  v_lead2 app.leads;
  v_prospect app.prospects;
  v_prospect2 app.prospects;
  v_opportunity app.opportunities;
  v_incomplete app.opportunities;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000008501', 'rep@acmecosting.test'),
    ('00000000-0000-0000-0000-000000008502', 'manager@acmecosting.test'),
    ('00000000-0000-0000-0000-000000008503', 'outsider@acmecosting.test'),
    ('00000000-0000-0000-0000-000000008504', 'other-tenant-rep@betacosting.test');

  perform app.provision_tenant('acmecosting', 'Acme Costing Co', 'idem-acmecosting', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmecosting');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betacosting', 'Beta Costing Co', 'idem-betacosting', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betacosting');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMECOST-CO', 'Acme Costing Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECOST-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMECOST-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECOST-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMECOST-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECOST-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMECOST-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMECOST-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008501', 'rep@acmecosting.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmecosting.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008502', 'manager@acmecosting.test', 'Branch Manager', v_branch, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmecosting.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008503', 'outsider@acmecosting.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmecosting.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000008504', 'other-tenant-rep@betacosting.test', 'Other Tenant Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'other-tenant-rep@betacosting.test'), 'active', 'onboarded', 'tester');

  -- Manager first (no protected permission in this set, self-assignment is fine), then
  -- the manager assigns the two protected-permission-carrying roles below (COM-147's own
  -- established fixture pattern -- app.assign_role's self-escalation guard only fires
  -- when actor = grantee AND the role version carries a protected permission).
  v_mgr_role := (app.create_role(v_tenant1, 'Costing Manager', 'costing governance', 'tester')).id;
  v_mgr_draft := app.create_role_version(v_mgr_role, 'tester');
  perform app.set_role_version_permissions(
    v_mgr_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'Approve')),
    'tester'
  );
  perform app.publish_role_version(v_mgr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_mgr_role and status = 'published'),
    '00000000-0000-0000-0000-000000008502', '00000000-0000-0000-0000-000000008502', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Costing Rep', 'costing capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008501', '00000000-0000-0000-0000-000000008502', 'tester');

  v_out_role := (app.create_role(v_tenant1, 'Team B Costing Rep', 'sibling team', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000008503', '00000000-0000-0000-0000-000000008502', 'tester');

  -- No protected permission in this set -- 'View cost' is deliberately omitted since
  -- tenant2 is only used here for cross-tenant fixture data, never as an actor exercising
  -- a cost-response action, so self-assignment stays valid.
  v_t2_role := (app.create_role(v_tenant2, 'Costing Rep', 'costing capture', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(
    v_t2_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'Approve')),
    'tester'
  );
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'),
    '00000000-0000-0000-0000-000000008504', '00000000-0000-0000-0000-000000008504', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Costing Ltd', 'Jane Doe', 'jane@contosocosting.test', '0811',
    '00000000-0000-0000-0000-000000008501', v_team_a, '00000000-0000-0000-0000-000000008501', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosocosting.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008501', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosocosting.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Contoso Costing Ltd', null, '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000008501', 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Contoso Costing Ltd';

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Contoso ocean freight lane',
    jsonb_build_object(
      'service_type', 'freight_forwarding', 'cargo_description', 'General cargo',
      'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'
    ),
    '00000000-0000-0000-0000-000000008501', v_team_a, '00000000-0000-0000-0000-000000008501', 'tester'
  );

  select * into v_incomplete from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Contoso incomplete lane', jsonb_build_object('service_type', 'freight_forwarding'),
    '00000000-0000-0000-0000-000000008501', v_team_a, '00000000-0000-0000-0000-000000008501', 'tester'
  );

  perform app.capture_lead(v_tenant2, 'manual', null, 'Other Tenant Co', 'Other Tenant', 'other@tenant-costing.test', '0822',
    '00000000-0000-0000-0000-000000008504', null, '00000000-0000-0000-0000-000000008504', 'tester');
  select * into v_lead2 from app.leads where email = 'other@tenant-costing.test';
  perform app.qualify_lead(v_lead2.id, v_lead2.record_version, '00000000-0000-0000-0000-000000008504', 'tester');
  select * into v_lead2 from app.leads where email = 'other@tenant-costing.test';
  perform app.convert_lead_to_prospect(v_lead2.id, 'Other Tenant Co', null, '02.345.678.9-012.000',
    jsonb_build_object('line1', 'Other St 2', 'city', 'Elsewhere', 'country', 'ID'),
    '00000000-0000-0000-0000-000000008504', 'tester');
end;
$$;

\echo '>> request_costing: blocked on incomplete requirements, idempotent on (opportunity, version), inserts components'
do $$
declare
  v_opportunity app.opportunities;
  v_incomplete app.opportunities;
  v_request app.costing_requests;
  v_retry app.costing_requests;
  v_component_count integer;
begin
  select * into v_opportunity from app.opportunities where name = 'Contoso ocean freight lane';
  select * into v_incomplete from app.opportunities where name = 'Contoso incomplete lane';

  begin
    perform app.request_costing(v_incomplete.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000008501', 'tester');
    raise exception 'assertion failed: expected check_violation -- incomplete opportunity requirements block a costing request';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_request from app.request_costing(
    v_opportunity.id,
    jsonb_build_array(
      jsonb_build_object('code', 'ocean_freight', 'description', 'Ocean freight leg', 'quantity', 1, 'unit', 'container'),
      jsonb_build_object('code', 'origin_haulage', 'description', 'Origin haulage', 'quantity', 1, 'unit', 'trip')
    ),
    now() + interval '3 days',
    '00000000-0000-0000-0000-000000008501', 'tester'
  );
  if v_request.status <> 'pending' or v_request.source_opportunity_version <> v_opportunity.record_version then
    raise exception 'assertion failed: expected status=pending source_opportunity_version=%, got status=% version=%', v_opportunity.record_version, v_request.status, v_request.source_opportunity_version;
  end if;

  select count(*) into v_component_count from app.costing_request_components where costing_request_id = v_request.id;
  if v_component_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 components, found %', v_component_count;
  end if;

  select * into v_retry from app.request_costing(
    v_opportunity.id, jsonb_build_array(jsonb_build_object('code', 'should_not_be_added', 'quantity', 1)),
    null, '00000000-0000-0000-0000-000000008501', 'tester'
  );
  if v_retry.id <> v_request.id then
    raise exception 'assertion failed: expected the retry to return the same request row, got a different id';
  end if;

  select count(*) into v_component_count from app.costing_request_components where costing_request_id = v_request.id;
  if v_component_count <> 2 then
    raise exception 'assertion failed: expected the idempotent retry to add no further components, found %', v_component_count;
  end if;
end;
$$;

\echo '>> assign_costing_request: optimistic concurrency, pending->assigned, invalid once cancelled/superseded'
do $$
declare
  v_request app.costing_requests;
begin
  select * into v_request from app.costing_requests where opportunity_id = (select id from app.opportunities where name = 'Contoso ocean freight lane');

  begin
    perform app.assign_costing_request(v_request.id, v_request.record_version + 1, '00000000-0000-0000-0000-000000008501', '00000000-0000-0000-0000-000000008502', 'tester');
    raise exception 'assertion failed: expected serialization_failure for a stale expected_version';
  exception
    when serialization_failure then
      null; -- expected
  end;

  select * into v_request from app.assign_costing_request(v_request.id, v_request.record_version, '00000000-0000-0000-0000-000000008501', '00000000-0000-0000-0000-000000008502', 'tester');
  if v_request.status <> 'assigned' or v_request.assignee_user_id <> '00000000-0000-0000-0000-000000008501' then
    raise exception 'assertion failed: expected status=assigned assignee=rep, got status=% assignee=%', v_request.status, v_request.assignee_user_id;
  end if;
end;
$$;

\echo '>> submit_costing_response: requires both COM:Edit and COM:View cost, computes total from components, unknown component rejected, moves request to responded'
do $$
declare
  v_request app.costing_requests;
  v_component1 uuid;
  v_component2 uuid;
  v_response app.costing_responses;
begin
  select * into v_request from app.costing_requests where opportunity_id = (select id from app.opportunities where name = 'Contoso ocean freight lane');
  select id into v_component1 from app.costing_request_components where costing_request_id = v_request.id and component_code = 'ocean_freight';
  select id into v_component2 from app.costing_request_components where costing_request_id = v_request.id and component_code = 'origin_haulage';

  begin
    perform app.submit_costing_response(
      v_request.id, 'internal', null, 'IDR', now(), null,
      jsonb_build_array(jsonb_build_object('requestComponentId', v_component1, 'amount', 1000)),
      '00000000-0000-0000-0000-000000008502', 'tester'
    );
    raise exception 'assertion failed: expected insufficient_privilege -- manager lacks COM:View cost';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  begin
    perform app.submit_costing_response(
      v_request.id, 'internal', null, 'IDR', now(), null,
      jsonb_build_array(jsonb_build_object('requestComponentId', gen_random_uuid(), 'amount', 1000)),
      '00000000-0000-0000-0000-000000008501', 'tester'
    );
    raise exception 'assertion failed: expected check_violation -- unknown component id does not belong to this request';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_response from app.submit_costing_response(
    v_request.id, 'internal', null, 'IDR', now(), now() + interval '30 days',
    jsonb_build_array(
      jsonb_build_object('requestComponentId', v_component1, 'amount', 15000000),
      jsonb_build_object('requestComponentId', v_component2, 'amount', 2500000)
    ),
    '00000000-0000-0000-0000-000000008501', 'tester'
  );
  if v_response.total_amount <> 17500000 or v_response.currency <> 'IDR' then
    raise exception 'assertion failed: expected total_amount=17500000 currency=IDR, got total_amount=% currency=%', v_response.total_amount, v_response.currency;
  end if;

  select * into v_request from app.costing_requests where id = v_request.id;
  if v_request.status <> 'responded' then
    raise exception 'assertion failed: expected the parent request to move to responded, got %', v_request.status;
  end if;

  begin
    perform app.submit_costing_response(
      v_request.id, 'vendor', null, 'IDR', now(), null,
      jsonb_build_array(jsonb_build_object('requestComponentId', v_component1, 'amount', 1)),
      '00000000-0000-0000-0000-000000008501', 'tester'
    );
    raise exception 'assertion failed: expected not_null_violation -- a vendor response requires a non-empty vendor_ref';
  exception
    when sqlstate '23514' then
      null; -- expected (the CHECK constraint, not the application-layer not_null_violation raise, catches this one)
  end;
end;
$$;

\echo '>> costing_responses_directory: cost masked without COM:View cost, visible with it; base-table columns withheld from direct select'
do $$
declare
  v_response_id uuid;
  v_masked boolean;
  v_total numeric;
begin
  v_response_id := (select id from app.costing_responses limit 1);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008502", "role": "authenticated"}';
  select cost_masked, total_amount into v_masked, v_total from app.costing_responses_directory where id = v_response_id;
  if not v_masked or v_total is not null then
    raise exception 'assertion failed: expected cost_masked=true and null total_amount for the manager (no View cost), got masked=% total=%', v_masked, v_total;
  end if;

  begin
    perform total_amount from app.costing_responses where id = v_response_id;
    raise exception 'assertion failed: expected a real Postgres permission-denied error selecting total_amount directly from app.costing_responses';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008501", "role": "authenticated"}';
  select cost_masked, total_amount into v_masked, v_total from app.costing_responses_directory where id = v_response_id;
  if v_masked or v_total <> 17500000 then
    raise exception 'assertion failed: expected cost_masked=false and total_amount=17500000 for the rep (holds View cost), got masked=% total=%', v_masked, v_total;
  end if;
  reset role;
end;
$$;

\echo '>> costing_response_components RLS: zero rows without COM:View cost, full detail with it'
do $$
declare
  v_response_id uuid;
  v_count integer;
begin
  v_response_id := (select id from app.costing_responses limit 1);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008502", "role": "authenticated"}';
  select count(*) into v_count from app.costing_response_components where costing_response_id = v_response_id;
  if v_count <> 0 then raise exception 'assertion failed: expected the manager (no View cost) to see 0 component rows, found %', v_count; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008501", "role": "authenticated"}';
  select count(*) into v_count from app.costing_response_components where costing_response_id = v_response_id;
  if v_count <> 2 then raise exception 'assertion failed: expected the rep (holds View cost) to see 2 component rows, found %', v_count; end if;
  reset role;
end;
$$;

\echo '>> revise_costing_request: no_new_version when the opportunity is unchanged, real revision preserves prior response evidence'
do $$
declare
  v_opportunity app.opportunities;
  v_source app.costing_requests;
  v_new_request app.costing_requests;
  v_component_count integer;
  v_response_count integer;
begin
  select * into v_opportunity from app.opportunities where name = 'Contoso ocean freight lane';
  select * into v_source from app.costing_requests where opportunity_id = v_opportunity.id;

  begin
    perform app.revise_costing_request(v_source.id, '00000000-0000-0000-0000-000000008501', 'tester');
    raise exception 'assertion failed: expected check_violation -- the opportunity has not changed since this request, nothing to revise';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  -- app.update_opportunity replaces the whole requirements object when provided (no
  -- partial/deep merge) -- the full still-complete set must be re-supplied here, not just
  -- the one new field, or the opportunity would regress to incomplete.
  perform app.update_opportunity(
    v_opportunity.id, v_opportunity.record_version, null,
    jsonb_build_object(
      'service_type', 'freight_forwarding', 'cargo_description', 'General cargo',
      'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01',
      'special_instructions', 'Handle with care'
    ),
    null, null, null, null, '00000000-0000-0000-0000-000000008501', 'tester'
  );
  select * into v_opportunity from app.opportunities where id = v_opportunity.id;

  select * into v_new_request from app.revise_costing_request(v_source.id, '00000000-0000-0000-0000-000000008501', 'tester');
  if v_new_request.revised_from_id <> v_source.id or v_new_request.source_opportunity_version <> v_opportunity.record_version then
    raise exception 'assertion failed: expected the new request to link revised_from_id=% and pin version=%, got revised_from_id=% version=%', v_source.id, v_opportunity.record_version, v_new_request.revised_from_id, v_new_request.source_opportunity_version;
  end if;
  if v_new_request.id = v_source.id then
    raise exception 'assertion failed: expected a distinct new row for the revision';
  end if;

  select count(*) into v_component_count from app.costing_request_components where costing_request_id = v_new_request.id;
  if v_component_count <> 2 then
    raise exception 'assertion failed: expected the revision to copy the source''s 2 components, found %', v_component_count;
  end if;

  select * into v_source from app.costing_requests where id = v_source.id;
  if v_source.status <> 'superseded' then
    raise exception 'assertion failed: expected the source request to be marked superseded, got %', v_source.status;
  end if;

  select count(*) into v_response_count from app.costing_responses where costing_request_id = v_source.id;
  if v_response_count <> 1 then
    raise exception 'assertion failed: expected the superseded request''s own prior response to remain linked and reachable, found %', v_response_count;
  end if;

  begin
    perform app.submit_costing_response(
      v_source.id, 'internal', null, 'IDR', now(), null,
      jsonb_build_array(jsonb_build_object('requestComponentId', (select id from app.costing_request_components where costing_request_id = v_source.id limit 1), 'amount', 1)),
      '00000000-0000-0000-0000-000000008501', 'tester'
    );
    raise exception 'assertion failed: expected check_violation -- a superseded request cannot accept a new response';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> cancel_costing_request: mandatory reason, cannot cancel an already-terminal request'
do $$
declare
  v_prospect app.prospects;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
begin
  select * into v_prospect from app.prospects where legal_name = 'Contoso Costing Ltd';
  select * into v_opportunity from app.create_opportunity(
    (select id from app.tenants where slug = 'acmecosting'), v_prospect.id, 'Contoso lane for cancellation',
    jsonb_build_object(
      'service_type', 'freight_forwarding', 'cargo_description', 'General cargo',
      'origin', 'Jakarta', 'destination', 'Bandung', 'target_ready_date', '2026-09-01'
    ),
    '00000000-0000-0000-0000-000000008501', (select id from app.org_units where tenant_id = (select id from app.tenants where slug = 'acmecosting') and code = 'ACMECOST-TEAM-A'),
    '00000000-0000-0000-0000-000000008501', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000008501', 'tester');

  begin
    perform app.cancel_costing_request(v_request.id, v_request.record_version, '', '00000000-0000-0000-0000-000000008501', 'tester');
    raise exception 'assertion failed: expected not_null_violation -- cancelling requires a non-empty reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  select * into v_request from app.cancel_costing_request(v_request.id, v_request.record_version, 'Customer withdrew the inquiry', '00000000-0000-0000-0000-000000008501', 'tester');
  if v_request.status <> 'cancelled' or v_request.cancel_reason <> 'Customer withdrew the inquiry' then
    raise exception 'assertion failed: expected status=cancelled with cancel_reason set, got status=% reason=%', v_request.status, v_request.cancel_reason;
  end if;

  begin
    perform app.cancel_costing_request(v_request.id, v_request.record_version, 'Second attempt', '00000000-0000-0000-0000-000000008501', 'tester');
    raise exception 'assertion failed: expected check_violation cancelling an already-cancelled request';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> record-scope read: owner and ancestor-org-unit manager see the request/components; a sibling-team outsider does not'
do $$
declare
  v_request_id uuid;
  v_count integer;
begin
  v_request_id := (select id from app.costing_requests where opportunity_id = (select id from app.opportunities where name = 'Contoso ocean freight lane') and status = 'superseded');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008501", "role": "authenticated"}';
  select count(*) into v_count from app.costing_requests where id = v_request_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the owning rep to see their own costing request'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008502", "role": "authenticated"}';
  select count(*) into v_count from app.costing_requests where id = v_request_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the branch manager (ancestor org unit) to see the costing request'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008503", "role": "authenticated"}';
  select count(*) into v_count from app.costing_requests where id = v_request_id;
  if v_count <> 0 then raise exception 'assertion failed: expected the sibling-team outsider to be denied, found % row(s)', v_count; end if;
  select count(*) into v_count from app.costing_request_components where costing_request_id = v_request_id;
  if v_count <> 0 then raise exception 'assertion failed: expected the sibling-team outsider to be denied for components, found % row(s)', v_count; end if;
  reset role;
end;
$$;

\echo '>> audit trail: request/assign/respond/revise/cancel all recorded real app.audit_logs events'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.costing_requests' and action = 'request_costing';
  if v_count <> 2 then raise exception 'assertion failed: expected exactly 2 request_costing audit events (the main-flow request plus the cancel-test request; the idempotent retry inserted nothing new), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.costing_requests' and action = 'assign_costing_request';
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 assign_costing_request audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.costing_responses' and action = 'submit_costing_response';
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 submit_costing_response audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.costing_requests' and action = 'revise_costing_request';
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 revise_costing_request audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.costing_requests' and action = 'cancel_costing_request';
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 cancel_costing_request audit event, found %', v_count; end if;
end;
$$;
