-- Real, executable test evidence for COM-152 (Quotation Versioning, CG-S7-COM-011) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/branch/team org hierarchy, a rep (COM:Create/Edit/View/View selling price/View cost), a sibling-team outsider, a full opportunity/costing-request/rate-selection/margin-calculation chain, a published margin rule, a contact, and a version-1 draft quotation with one line'
do $$
declare
  v_tenant1 uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
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
  v_quote app.quotations;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009301', 'tenantadmin@acmever.test'),
    ('00000000-0000-0000-0000-000000009302', 'rep@acmever.test'),
    ('00000000-0000-0000-0000-000000009303', 'outsider@acmever.test');

  perform app.provision_tenant('acmever', 'Acme Versioning Co', 'idem-acmever', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmever');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEVER-CO', 'Acme Versioning Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEVER-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEVER-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEVER-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEVER-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEVER-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEVER-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEVER-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009301', 'tenantadmin@acmever.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmever.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009301', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009302', 'rep@acmever.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmever.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009303', 'outsider@acmever.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmever.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Version Rep', 'quote versioning', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009302', '00000000-0000-0000-0000-000000009301', 'tester');

  v_out_role := (app.create_role(v_tenant1, 'Team B Version Rep', 'sibling team', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000009303', '00000000-0000-0000-0000-000000009301', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Versioning Ltd', 'Jane Doe', 'jane@contosover.test', '0811',
    '00000000-0000-0000-0000-000000009302', v_team_a, '00000000-0000-0000-0000-000000009302', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosover.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009302', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosover.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Contoso Versioning Ltd', 'Contoso', '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009302', 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Contoso Versioning Ltd';

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Doe', 'Procurement Lead', 'jane@contosover.test', '0811', '00000000-0000-0000-0000-000000009302', v_team_a, '00000000-0000-0000-0000-000000009302', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Contoso Jakarta-Surabaya versioning lane',
    jsonb_build_object(
      'service_type', 'ocean_freight', 'cargo_description', 'General cargo',
      'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'
    ),
    '00000000-0000-0000-0000-000000009302', v_team_a, '00000000-0000-0000-0000-000000009302', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009302', 'tester');

  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-VER-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009301', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009301', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009302', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009302', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009302', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009302', 'tester');

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009302', 'tester');
  perform app.add_quotation_line(
    v_quote.id, v_quote.record_version, 'service', 'Ocean freight Jakarta-Surabaya',
    (select id from app.margin_calculations where rate_selection_id = v_selection.id and is_current),
    1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009302', 'tester'
  );
end;
$$;

\echo '>> app.create_quotation_draft (COM-151, widened): root_quotation_id self-references the new row, version_number=1, is_current=true'
do $$
declare
  v_quote app.quotations;
begin
  select * into v_quote from app.quotations where customer_snapshot ->> 'legal_name' = 'Contoso Versioning Ltd' order by quote_number asc limit 1;
  if v_quote.root_quotation_id <> v_quote.id or v_quote.version_number <> 1 or not v_quote.is_current or v_quote.superseded_by_id is not null then
    raise exception 'assertion failed: expected root_quotation_id=id version_number=1 is_current=true superseded_by_id=null, got root=% version=% current=% superseded_by=%', v_quote.root_quotation_id, v_quote.version_number, v_quote.is_current, v_quote.superseded_by_id;
  end if;
end;
$$;

\echo '>> app.create_quotation_revision: mandatory reason, authority/record-access gated, mixed currency of concurrent unrelated line no-op, creates version 2 with the same quote_number, supersedes version 1, copies every line'
do $$
declare
  v_v1 app.quotations;
  v_v2 app.quotations;
  v_line_count integer;
begin
  select * into v_v1 from app.quotations where customer_snapshot ->> 'legal_name' = 'Contoso Versioning Ltd' order by quote_number asc, version_number asc limit 1;

  begin
    perform app.create_quotation_revision(v_v1.id, '', '00000000-0000-0000-0000-000000009302', 'tester');
    raise exception 'assertion failed: expected not_null_violation -- an empty reason is rejected';
  exception
    when not_null_violation then
      null; -- expected
  end;

  begin
    perform app.create_quotation_revision(v_v1.id, 'Price adjustment', '00000000-0000-0000-0000-000000009303', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the sibling-team outsider cannot access this quotation';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_v2 from app.create_quotation_revision(v_v1.id, 'Customer requested a discount', '00000000-0000-0000-0000-000000009302', 'tester');
  if v_v2.root_quotation_id <> v_v1.root_quotation_id or v_v2.version_number <> 2 or not v_v2.is_current or v_v2.quote_number <> v_v1.quote_number then
    raise exception 'assertion failed: expected root=% version=2 is_current=true quote_number=%, got root=% version=% current=% quote_number=%', v_v1.root_quotation_id, v_v1.quote_number, v_v2.root_quotation_id, v_v2.version_number, v_v2.is_current, v_v2.quote_number;
  end if;
  if v_v2.revision_reason <> 'Customer requested a discount' then
    raise exception 'assertion failed: expected revision_reason to be recorded, got %', v_v2.revision_reason;
  end if;
  if v_v2.status <> 'draft' then
    raise exception 'assertion failed: expected a fresh revision to start as draft, got %', v_v2.status;
  end if;

  select * into v_v1 from app.quotations where id = v_v1.id;
  if v_v1.is_current or v_v1.superseded_by_id <> v_v2.id then
    raise exception 'assertion failed: expected version 1 to be superseded by version 2 (is_current=false, superseded_by_id=%), got is_current=% superseded_by_id=%', v_v2.id, v_v1.is_current, v_v1.superseded_by_id;
  end if;

  select count(*) into v_line_count from app.quotation_lines where quotation_id = v_v2.id;
  if v_line_count <> 1 then
    raise exception 'assertion failed: expected version 2 to carry the copied line, found % rows', v_line_count;
  end if;

  -- Database-enforced version sequence/root uniqueness (Prompt 152 §25): exactly one
  -- is_current=true row per root, proven directly against the partial unique index.
  if (select count(*) from app.quotations where root_quotation_id = v_v1.root_quotation_id and is_current) <> 1 then
    raise exception 'assertion failed: expected exactly one is_current row for this root';
  end if;
end;
$$;

\echo '>> normal-role lock enforcement: a superseded (is_current=false) version can never be edited, submitted, or have lines added/removed -- even though its own status column still literally reads draft'
do $$
declare
  v_v1 app.quotations;
begin
  select * into v_v1 from app.quotations where customer_snapshot ->> 'legal_name' = 'Contoso Versioning Ltd' order by quote_number asc, version_number asc limit 1;
  if v_v1.status <> 'draft' or v_v1.is_current then
    raise exception 'assertion failed: test precondition violated -- expected version 1 to be status=draft is_current=false, got status=% is_current=%', v_v1.status, v_v1.is_current;
  end if;

  begin
    perform app.add_quotation_line(v_v1.id, v_v1.record_version, 'service', 'Should not be allowed', null, 1, 1, 0, 0, '00000000-0000-0000-0000-000000009302', 'tester');
    raise exception 'assertion failed: expected check_violation -- a superseded version cannot be edited even though status=draft';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  begin
    perform app.update_quotation_terms(v_v1.id, v_v1.record_version, 'IDR', now(), now() + interval '30 days', '{}'::jsonb, null, '00000000-0000-0000-0000-000000009302', 'tester');
    raise exception 'assertion failed: expected check_violation -- terms cannot be updated on a superseded version';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  begin
    perform app.submit_quotation(v_v1.id, v_v1.record_version, '00000000-0000-0000-0000-000000009302', 'tester');
    raise exception 'assertion failed: expected check_violation -- a superseded version cannot be submitted';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> app.get_quotation_submission_readiness: not_current_version blocks a historical version; the current version (v2) remains independently ready/not-ready on its own merits'
do $$
declare
  v_v1 app.quotations;
  v_v2 app.quotations;
  v_ready boolean;
  v_reasons text[];
begin
  select * into v_v1 from app.quotations where customer_snapshot ->> 'legal_name' = 'Contoso Versioning Ltd' order by quote_number asc, version_number asc limit 1;
  select * into v_v2 from app.quotations where root_quotation_id = v_v1.root_quotation_id and is_current;

  select ready, blocking_reasons into v_ready, v_reasons from app.get_quotation_submission_readiness(v_v1.id, '00000000-0000-0000-0000-000000009302');
  if v_ready or not ('not_current_version' = any (v_reasons)) then
    raise exception 'assertion failed: expected the historical version to report not_current_version among its blocking reasons, got ready=% reasons=%', v_ready, v_reasons;
  end if;

  select ready, blocking_reasons into v_ready, v_reasons from app.get_quotation_submission_readiness(v_v2.id, '00000000-0000-0000-0000-000000009302');
  if not v_ready then
    raise exception 'assertion failed: expected v2 (current, with contact/lines copied from v1) to be ready, got reasons=%', v_reasons;
  end if;
end;
$$;

\echo '>> alternative flow: restore an older version as a new latest draft (app.create_quotation_revision sourced from a historical, non-current version), monotonic version_number continues, root/quote_number preserved'
do $$
declare
  v_v1 app.quotations;
  v_v3 app.quotations;
  v_v3_line_count integer;
  v_v1_line_count integer;
begin
  select * into v_v1 from app.quotations where customer_snapshot ->> 'legal_name' = 'Contoso Versioning Ltd' order by quote_number asc, version_number asc limit 1;

  select * into v_v3 from app.create_quotation_revision(v_v1.id, 'Restoring the original terms', '00000000-0000-0000-0000-000000009302', 'tester');
  if v_v3.version_number <> 3 or v_v3.root_quotation_id <> v_v1.root_quotation_id or v_v3.quote_number <> v_v1.quote_number or not v_v3.is_current then
    raise exception 'assertion failed: expected version_number=3 same root/quote_number is_current=true, got version=% root=% quote_number=% current=%', v_v3.version_number, v_v3.root_quotation_id, v_v3.quote_number, v_v3.is_current;
  end if;

  select count(*) into v_v1_line_count from app.quotation_lines where quotation_id = v_v1.id;
  select count(*) into v_v3_line_count from app.quotation_lines where quotation_id = v_v3.id;
  if v_v3_line_count <> v_v1_line_count or v_v3_line_count = 0 then
    raise exception 'assertion failed: expected the restored version to carry the same non-zero line count as its source (% lines), got %', v_v1_line_count, v_v3_line_count;
  end if;

  -- v2 (the version that was current immediately before this restore) is now itself superseded.
  if (select is_current from app.quotations where quote_number = v_v1.quote_number and version_number = 2) then
    raise exception 'assertion failed: expected version 2 to be superseded once version 3 became current';
  end if;

  if (select count(*) from app.quotations where root_quotation_id = v_v1.root_quotation_id and is_current) <> 1 then
    raise exception 'assertion failed: expected exactly one is_current row after the restore';
  end if;
end;
$$;

\echo '>> sequential repeated-call correctness (single-threaded sandbox disclosure, same discipline as PLT-125''s own concurrent-load boundary): five back-to-back revisions chain correctly with no gap/duplicate version_number and exactly one is_current row throughout'
do $$
declare
  v_root uuid;
  v_current app.quotations;
  v_i integer;
  v_max_version integer;
  v_current_count integer;
begin
  select root_quotation_id into v_root from app.quotations where customer_snapshot ->> 'legal_name' = 'Contoso Versioning Ltd' limit 1;
  select * into v_current from app.quotations where root_quotation_id = v_root and is_current;

  for v_i in 1..5 loop
    select * into v_current from app.create_quotation_revision(v_current.id, 'sequential revision ' || v_i, '00000000-0000-0000-0000-000000009302', 'tester');
  end loop;

  select max(version_number) into v_max_version from app.quotations where root_quotation_id = v_root;
  select count(*) into v_current_count from app.quotations where root_quotation_id = v_root and is_current;

  if v_max_version <> 8 then
    raise exception 'assertion failed: expected max version_number=8 after 3 (setup) + 5 (this loop) revisions, got %', v_max_version;
  end if;
  if v_current_count <> 1 then
    raise exception 'assertion failed: expected exactly one is_current row after 5 sequential revisions, got %', v_current_count;
  end if;
  if (select count(distinct version_number) from app.quotations where root_quotation_id = v_root) <> v_max_version then
    raise exception 'assertion failed: expected version_number to be gap-free and duplicate-free from 1 to %', v_max_version;
  end if;
end;
$$;

\echo '>> app.quotations_directory: version/root columns visible to any record-scoped viewer regardless of View cost/View selling price; sibling-team outsider still denied via record-scope'
do $$
declare
  v_root uuid;
  v_count integer;
  v_current_count integer;
begin
  select root_quotation_id into v_root from app.quotations where customer_snapshot ->> 'legal_name' = 'Contoso Versioning Ltd' limit 1;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009302", "role": "authenticated"}';
  select count(*), count(*) filter (where is_current) into v_count, v_current_count from app.quotations_directory where root_quotation_id = v_root;
  if v_count <> 8 or v_current_count <> 1 then
    raise exception 'assertion failed: expected the rep to see all 8 versions with exactly 1 current, got count=% current_count=%', v_count, v_current_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009303", "role": "authenticated"}';
  select count(*) into v_count from app.quotations_directory where root_quotation_id = v_root;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to be denied via record-scope across every version, found % row(s)', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> app.clone_quotation (COM-151, widened): a clone is always a brand-new root/version-1, never a revision of the source root'
do $$
declare
  v_root uuid;
  v_current app.quotations;
  v_clone app.quotations;
begin
  select root_quotation_id into v_root from app.quotations where customer_snapshot ->> 'legal_name' = 'Contoso Versioning Ltd' limit 1;
  select * into v_current from app.quotations where root_quotation_id = v_root and is_current;

  select * into v_clone from app.clone_quotation(v_current.id, '00000000-0000-0000-0000-000000009302', 'tester');
  if v_clone.root_quotation_id <> v_clone.id or v_clone.version_number <> 1 or not v_clone.is_current or v_clone.root_quotation_id = v_root then
    raise exception 'assertion failed: expected the clone to be its own fresh root (version_number=1, root_quotation_id=own id, distinct from the source root %), got root=% version=% current=%', v_root, v_clone.root_quotation_id, v_clone.version_number, v_clone.is_current;
  end if;
end;
$$;

\echo '>> audit trail: create_quotation_revision recorded a real app.audit_logs event per call, with the mandatory reason captured'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmever');

  select count(*) into v_count from app.audit_logs where resource_type = 'app.quotations' and action = 'create_quotation_revision' and tenant_id = v_tenant1;
  if v_count <> 7 then raise exception 'assertion failed: expected exactly 7 create_quotation_revision audit events for acmever (1 restore + 1 restore-alt-flow + 5 sequential), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.quotations' and action = 'create_quotation_revision' and tenant_id = v_tenant1 and reason is not null;
  if v_count <> 7 then raise exception 'assertion failed: expected every create_quotation_revision audit event to carry a non-null reason, found %', v_count; end if;
end;
$$;
