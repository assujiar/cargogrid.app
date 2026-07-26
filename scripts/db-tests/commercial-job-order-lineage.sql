-- Real, executable test evidence for COM-160 (Full Lineage into Job Order,
-- CG-S7-COM-019) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/branch/team-a/team-b org hierarchy, a rep (COM:Create/Edit/Approve/View/View selling price/View cost), an editor (COM:Create/Edit/View only -- can prepare a handoff but cannot see prices), a viewer (COM:View only -- no Edit at all), a sibling-team outsider (full grants), and a full lead->prospect->contact->opportunity->costing->rate->margin->quotation chain, submitted, accepted by the customer, and converted to an account'
do $$
declare
  v_tenant1 uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_editor_role uuid;
  v_editor_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_out_role uuid;
  v_out_draft app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc app.margin_calculations;
  v_quote app.quotations;
  v_send record;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009610', 'tenantadmin@acmelineage.test'),
    ('00000000-0000-0000-0000-000000009611', 'rep@acmelineage.test'),
    ('00000000-0000-0000-0000-000000009612', 'viewer@acmelineage.test'),
    ('00000000-0000-0000-0000-000000009613', 'outsider@acmelineage.test'),
    ('00000000-0000-0000-0000-000000009614', 'editor@acmelineage.test');

  perform app.provision_tenant('acmelineage', 'Acme Lineage Co', 'idem-acmelineage', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmelineage');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMELINEAGE-CO', 'Acme Lineage Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELINEAGE-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMELINEAGE-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELINEAGE-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMELINEAGE-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELINEAGE-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMELINEAGE-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELINEAGE-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009610', 'tenantadmin@acmelineage.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmelineage.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009610', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009611', 'rep@acmelineage.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmelineage.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009612', 'viewer@acmelineage.test', 'Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmelineage.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009613', 'outsider@acmelineage.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmelineage.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009614', 'editor@acmelineage.test', 'Editor', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'editor@acmelineage.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Lineage Rep', 'full grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009611', '00000000-0000-0000-0000-000000009610', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Lineage Viewer', 'no Edit, no View selling price', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'),
    '00000000-0000-0000-0000-000000009612', '00000000-0000-0000-0000-000000009610', 'tester');

  v_editor_role := (app.create_role(v_tenant1, 'Lineage Editor', 'COM:Edit, no View selling price', 'tester')).id;
  v_editor_draft := app.create_role_version(v_editor_role, 'tester');
  perform app.set_role_version_permissions(
    v_editor_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_editor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_editor_role and status = 'published'),
    '00000000-0000-0000-0000-000000009614', '00000000-0000-0000-0000-000000009610', 'tester');

  v_out_role := (app.create_role(v_tenant1, 'Lineage Outsider', 'team-b sibling', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000009613', '00000000-0000-0000-0000-000000009610', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Lineage Co', 'Lineage Contact', 'lineage@lineageco.test', '0811',
    '00000000-0000-0000-0000-000000009611', v_team_a, '00000000-0000-0000-0000-000000009611', 'tester');
  select * into v_lead from app.leads where email = 'lineage@lineageco.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009611', 'tester');
  select * into v_lead from app.leads where email = 'lineage@lineageco.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Lineage Co', 'Lineage', '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009611', 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Lineage Co';
  select * into v_contact from app.create_contact(v_tenant1, 'Lineage Contact', 'Procurement', 'lineage@lineageco.test', '0811', '00000000-0000-0000-0000-000000009611', v_team_a, '00000000-0000-0000-0000-000000009611', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Lineage Jakarta-Surabaya quote lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009611', v_team_a, '00000000-0000-0000-0000-000000009611', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009611', 'tester');

  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-LINEAGE-1', 'Lineage Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009610', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009610', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009611', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009611', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009611', 'tester');
  select * into v_calc from app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009611', 'tester');

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009611', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight Jakarta-Surabaya', v_calc.id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009611', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_quote from app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009611', 'tester');

  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, v_contact.id, 'email', '00000000-0000-0000-0000-000000009611', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Lineage Contact', null, null, null, null, null);

  perform app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009611', 'tester');
end;
$$;

\echo '>> app.prepare_job_order_handoff: authority-gated (viewer without COM:Edit denied), builds a complete, correct payload traced to canonical sources, and is idempotent on retry'
do $$
declare
  v_quote_id uuid;
  v_account_id uuid;
  v_first app.job_order_handoffs;
  v_second app.job_order_handoffs;
  v_count integer;
begin
  select id into v_quote_id from app.quotations where customer_snapshot ->> 'legal_name' = 'Lineage Co' order by quote_number asc limit 1;
  select account_id into v_account_id from app.account_conversions where quotation_id = v_quote_id;

  begin
    perform app.prepare_job_order_handoff(v_quote_id, '00000000-0000-0000-0000-000000009612', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the viewer lacks COM:Edit';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_first from app.prepare_job_order_handoff(v_quote_id, '00000000-0000-0000-0000-000000009611', 'tester');
  if v_first.status <> 'prepared' or v_first.account_id <> v_account_id or v_first.purpose <> 'job_order_draft' then
    raise exception 'assertion failed: expected status=prepared account_id=% purpose=job_order_draft, got status=% account_id=% purpose=%', v_account_id, v_first.status, v_first.account_id, v_first.purpose;
  end if;

  if (v_first.payload -> 'pricing' ->> 'totalAmount')::numeric <> 15000000 then
    raise exception 'assertion failed: expected payload.pricing.totalAmount=15000000, got %', v_first.payload -> 'pricing' ->> 'totalAmount';
  end if;
  if jsonb_array_length(v_first.payload -> 'pricing' -> 'lines') <> 1 then
    raise exception 'assertion failed: expected exactly 1 line in payload.pricing.lines, got %', jsonb_array_length(v_first.payload -> 'pricing' -> 'lines');
  end if;
  if (v_first.payload -> 'customer' ->> 'accountId')::uuid <> v_account_id then
    raise exception 'assertion failed: expected payload.customer.accountId=%, got %', v_account_id, v_first.payload -> 'customer' ->> 'accountId';
  end if;
  if v_first.payload -> 'acceptance' ->> 'decidedByName' <> 'Lineage Contact' then
    raise exception 'assertion failed: expected payload.acceptance.decidedByName=Lineage Contact, got %', v_first.payload -> 'acceptance' ->> 'decidedByName';
  end if;
  -- No contract or credit check was ever created against this account -- both sections
  -- must be explicit jsonb null, never a fabricated placeholder.
  if v_first.payload -> 'contract' is distinct from 'null'::jsonb or v_first.payload -> 'credit' is distinct from 'null'::jsonb then
    raise exception 'assertion failed: expected contract and credit sections to both be null (none created), got contract=% credit=%', v_first.payload -> 'contract', v_first.payload -> 'credit';
  end if;

  -- Idempotent retry: same row, same hash, never a second insert.
  select * into v_second from app.prepare_job_order_handoff(v_quote_id, '00000000-0000-0000-0000-000000009611', 'tester');
  if v_first.id <> v_second.id or v_first.payload_hash <> v_second.payload_hash then
    raise exception 'assertion failed: expected the retry to return the identical row (id=%, hash=%), got id=% hash=%', v_first.id, v_first.payload_hash, v_second.id, v_second.payload_hash;
  end if;

  select count(*) into v_count from app.job_order_handoffs where quotation_id = v_quote_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 job_order_handoffs row after two calls, got %', v_count;
  end if;

  -- The editor holds COM:Edit (enough to call prepare_job_order_handoff at all) but not
  -- View selling price -- calling the idempotent-retry path must still mask the
  -- function's own returned payload/payload_hash, even though the stored row itself
  -- (already inserted by the rep above) carries the real payload.
  select * into v_second from app.prepare_job_order_handoff(v_quote_id, '00000000-0000-0000-0000-000000009614', 'tester');
  if v_second.payload is not null or v_second.payload_hash is not null then
    raise exception 'assertion failed: expected the editor (no View selling price) to receive a masked payload/payload_hash from prepare_job_order_handoff itself, got payload=% payload_hash=%', v_second.payload, v_second.payload_hash;
  end if;
  if v_second.id <> v_first.id or v_second.status <> 'prepared' or v_second.account_id <> v_account_id then
    raise exception 'assertion failed: expected the masked response to still carry the correct non-sensitive fields (id=%, status=prepared, account_id=%), got id=% status=% account_id=%', v_first.id, v_account_id, v_second.id, v_second.status, v_second.account_id;
  end if;
end;
$$;

\echo '>> app.prepare_job_order_handoff: precondition failures -- not-yet-accepted quotation, and an accepted-but-not-converted sibling clone, both remain safely retryable with zero rows created'
do $$
declare
  v_opportunity_id uuid;
  v_calc_id uuid;
  v_contact_id uuid;
  v_source_quote_id uuid;
  v_unsent_quote app.quotations;
  v_sibling_quote app.quotations;
  v_send record;
  v_count integer;
begin
  select id into v_opportunity_id from app.opportunities where name = 'Lineage Jakarta-Surabaya quote lane';
  select id into v_contact_id from app.contacts where full_name = 'Lineage Contact';
  select id into v_source_quote_id from app.quotations where customer_snapshot ->> 'legal_name' = 'Lineage Co' order by quote_number asc limit 1;
  select id into v_calc_id from app.margin_calculations where rate_selection_id = (select id from app.rate_selections where costing_request_id = (select id from app.costing_requests where opportunity_id = v_opportunity_id)) and is_current;

  -- A brand-new draft quotation, submitted but never sent/accepted.
  select * into v_unsent_quote from app.create_quotation_draft(
    (select tenant_id from app.opportunities where id = v_opportunity_id), v_opportunity_id, 'IDR', now() + interval '14 days', v_contact_id, null, null,
    '00000000-0000-0000-0000-000000009611', 'tester'
  );
  perform app.add_quotation_line(v_unsent_quote.id, v_unsent_quote.record_version, 'service', 'Ocean freight Jakarta-Surabaya', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009611', 'tester');
  select * into v_unsent_quote from app.quotations where id = v_unsent_quote.id;
  select * into v_unsent_quote from app.submit_quotation(v_unsent_quote.id, v_unsent_quote.record_version, '00000000-0000-0000-0000-000000009611', 'tester');

  begin
    perform app.prepare_job_order_handoff(v_unsent_quote.id, '00000000-0000-0000-0000-000000009611', 'tester');
    raise exception 'assertion failed: expected check_violation (quote_not_accepted) -- never sent for acceptance';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  -- A clone of the already-accepted-and-converted quotation, accepted in its own right,
  -- but never itself passed to app.convert_quotation_to_account -- proves the
  -- precondition is quotation-specific (app.account_conversions.quotation_id), not
  -- account-level, even though the same account already exists from the source clone.
  select * into v_sibling_quote from app.clone_quotation(v_source_quote_id, '00000000-0000-0000-0000-000000009611', 'tester');
  select * into v_sibling_quote from app.submit_quotation(v_sibling_quote.id, v_sibling_quote.record_version, '00000000-0000-0000-0000-000000009611', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_sibling_quote.id, v_contact_id, 'email', '00000000-0000-0000-0000-000000009611', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Lineage Contact', null, null, null, null, null);

  begin
    perform app.prepare_job_order_handoff(v_sibling_quote.id, '00000000-0000-0000-0000-000000009611', 'tester');
    raise exception 'assertion failed: expected check_violation (account_not_converted) -- this exact quotation was never converted, even though its sibling''s account already exists';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select count(*) into v_count from app.job_order_handoffs where quotation_id in (v_unsent_quote.id, v_sibling_quote.id);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero job_order_handoffs rows for either precondition-failing quotation, got %', v_count;
  end if;
end;
$$;

\echo '>> app.job_order_handoffs_directory: payload/payload_hash masked without COM:View selling price, visible with it; sibling-team outsider denied via record-scope; base-table columns withheld from direct select'
do $$
declare
  v_quote_id uuid;
  v_handoff_id uuid;
  v_masked boolean;
  v_payload jsonb;
  v_count integer;
begin
  select id into v_quote_id from app.quotations where customer_snapshot ->> 'legal_name' = 'Lineage Co' order by quote_number asc limit 1;
  select id into v_handoff_id from app.job_order_handoffs where quotation_id = v_quote_id;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009611", "role": "authenticated"}';
  select payload_masked, payload into v_masked, v_payload from app.job_order_handoffs_directory where id = v_handoff_id;
  if v_masked or v_payload is null then
    raise exception 'assertion failed: expected the rep (holds View selling price) to see payload_masked=false with a real payload, got masked=% payload_is_null=%', v_masked, (v_payload is null);
  end if;

  begin
    perform payload from app.job_order_handoffs where id = v_handoff_id;
    raise exception 'assertion failed: expected a real Postgres permission-denied error selecting payload directly from app.job_order_handoffs';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009612", "role": "authenticated"}';
  select payload_masked, payload into v_masked, v_payload from app.job_order_handoffs_directory where id = v_handoff_id;
  if not v_masked or v_payload is not null then
    raise exception 'assertion failed: expected the viewer (no View selling price) to see payload_masked=true and payload=null, got masked=% payload_is_null=%', v_masked, (v_payload is null);
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009613", "role": "authenticated"}';
  select count(*) into v_count from app.job_order_handoffs_directory where id = v_handoff_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to be denied via record-scope, found % row(s)', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> audit trail: prepare_job_order_handoff recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelineage');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and action = 'prepare_job_order_handoff';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 prepare_job_order_handoff audit_logs entry (the successful first call, not the idempotent retry), got %', v_count;
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on app.prepare_job_order_handoff / app.build_job_order_draft_payload (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in ('prepare_job_order_handoff', 'build_job_order_draft_payload')
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on either COM-160 function, found %', v_count;
  end if;
end;
$$;
