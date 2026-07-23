-- Real, executable test evidence for COM-146 (CRM Sales Plan and Pipeline,
-- CG-S7-COM-005) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a company/branch/team-a/team-b org hierarchy, a rep, a branch manager, a sibling-team outsider, and leads/prospects to reconcile against'
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
  v_t2_role uuid;
  v_t2_draft app.role_versions;
  v_lead app.leads;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000008301', 'rep@acmepipeline.test'),
    ('00000000-0000-0000-0000-000000008302', 'manager@acmepipeline.test'),
    ('00000000-0000-0000-0000-000000008303', 'outsider@acmepipeline.test'),
    ('00000000-0000-0000-0000-000000008304', 'other-tenant-rep@betapipeline.test');

  perform app.provision_tenant('acmepipeline', 'Acme Pipeline Co', 'idem-acmepipeline', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmepipeline');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betapipeline', 'Beta Pipeline Co', 'idem-betapipeline', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betapipeline');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEPIPE-CO', 'Acme Pipeline Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPIPE-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEPIPE-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPIPE-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEPIPE-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPIPE-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEPIPE-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPIPE-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008301', 'rep@acmepipeline.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmepipeline.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008302', 'manager@acmepipeline.test', 'Branch Manager', v_branch, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmepipeline.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000008303', 'outsider@acmepipeline.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmepipeline.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000008304', 'other-tenant-rep@betapipeline.test', 'Other Tenant Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'other-tenant-rep@betapipeline.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Sales Rep', 'pipeline capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008301', '00000000-0000-0000-0000-000000008301', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000008303', '00000000-0000-0000-0000-000000008301', 'tester');

  v_mgr_role := (app.create_role(v_tenant1, 'Sales Manager', 'pipeline governance', 'tester')).id;
  v_mgr_draft := app.create_role_version(v_mgr_role, 'tester');
  perform app.set_role_version_permissions(
    v_mgr_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'Approve')),
    'tester'
  );
  perform app.publish_role_version(v_mgr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_mgr_role and status = 'published'),
    '00000000-0000-0000-0000-000000008302', '00000000-0000-0000-0000-000000008301', 'tester');

  v_t2_role := (app.create_role(v_tenant2, 'Sales Rep', 'pipeline capture', 'tester')).id;
  v_t2_draft := app.create_role_version(v_t2_role, 'tester');
  perform app.set_role_version_permissions(
    v_t2_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'View', 'Edit', 'Approve')),
    'tester'
  );
  perform app.publish_role_version(v_t2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_t2_role and status = 'published'),
    '00000000-0000-0000-0000-000000008304', '00000000-0000-0000-0000-000000008304', 'tester');

  -- Two team-A leads (rep's own scope), one team-B lead (sibling scope -- must never
  -- count toward a team-A-scoped target or appear in a team-A pipeline drill-down).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Pipeline Ltd', 'Jane Doe', 'jane@contosopipeline.test', '0811',
    '00000000-0000-0000-0000-000000008301', v_team_a, '00000000-0000-0000-0000-000000008301', 'tester');
  perform app.capture_lead(v_tenant1, 'manual', null, 'Fabrikam Pipeline Ltd', 'John Roe', 'john@fabrikampipeline.test', '0812',
    '00000000-0000-0000-0000-000000008301', v_team_a, '00000000-0000-0000-0000-000000008301', 'tester');
  perform app.capture_lead(v_tenant1, 'manual', null, 'Team B Prospect Co', 'Sibling Contact', 'sibling@teamb.test', '0813',
    '00000000-0000-0000-0000-000000008303', v_team_b, '00000000-0000-0000-0000-000000008303', 'tester');

  select * into v_lead from app.leads where email = 'jane@contosopipeline.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000008301', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosopipeline.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Contoso Pipeline Ltd', null, '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000008301', 'tester');

  perform app.capture_lead(v_tenant2, 'manual', null, 'Other Tenant Co', 'Other Tenant', 'other@tenant-pipeline.test', '0822',
    '00000000-0000-0000-0000-000000008304', null, '00000000-0000-0000-0000-000000008304', 'tester');
end;
$$;

\echo '>> disqualify the converted prospect (gives us a real prospects_disqualified data point)'
do $$
declare
  v_prospect app.prospects;
begin
  select * into v_prospect from app.prospects where legal_name = 'Contoso Pipeline Ltd';
  perform app.disqualify_prospect(v_prospect.id, v_prospect.record_version, 'Budget frozen this quarter', '00000000-0000-0000-0000-000000008301', 'tester');

  select * into v_prospect from app.prospects where legal_name = 'Contoso Pipeline Ltd';
  if v_prospect.status <> 'disqualified' or v_prospect.disqualified_at is null then
    raise exception 'assertion failed: expected disqualified with disqualified_at set, got status=% disqualified_at=%', v_prospect.status, v_prospect.disqualified_at;
  end if;
end;
$$;

\echo '>> pipeline_categories / win_loss_reasons: create, unique code, optimistic-concurrency update'
do $$
declare
  v_tenant1 uuid;
  v_category app.pipeline_categories;
  v_reason_lost app.win_loss_reasons;
  v_reason_won app.win_loss_reasons;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmepipeline');

  select * into v_category from app.create_pipeline_category(v_tenant1, 'TOP_FUNNEL', 'Top of Funnel', 1, '00000000-0000-0000-0000-000000008302', 'tester');
  if v_category.code <> 'TOP_FUNNEL' or not v_category.is_active then
    raise exception 'assertion failed: expected an active TOP_FUNNEL category, got code=% is_active=%', v_category.code, v_category.is_active;
  end if;

  begin
    perform app.create_pipeline_category(v_tenant1, 'TOP_FUNNEL', 'Duplicate', 2, '00000000-0000-0000-0000-000000008302', 'tester');
    raise exception 'assertion failed: expected unique_violation for a duplicate category code';
  exception
    when unique_violation then
      null; -- expected
  end;

  select * into v_category from app.update_pipeline_category(v_category.id, v_category.record_version, 'Top of the Funnel', 5, true, '00000000-0000-0000-0000-000000008302', 'tester');
  if v_category.label <> 'Top of the Funnel' or v_category.sort_order <> 5 or v_category.record_version <> 2 then
    raise exception 'assertion failed: expected updated label/sort_order/record_version=2, got label=% sort_order=% record_version=%', v_category.label, v_category.sort_order, v_category.record_version;
  end if;

  begin
    perform app.update_pipeline_category(v_category.id, 1, 'Stale', null, null, '00000000-0000-0000-0000-000000008302', 'tester');
    raise exception 'assertion failed: expected serialization_failure for a stale expected_version';
  exception
    when serialization_failure then
      null; -- expected
  end;

  select * into v_reason_lost from app.create_win_loss_reason(v_tenant1, 'NO_BUDGET', 'No budget', 'lost', '00000000-0000-0000-0000-000000008302', 'tester');
  select * into v_reason_won from app.create_win_loss_reason(v_tenant1, 'BEST_FIT', 'Best fit', 'won', '00000000-0000-0000-0000-000000008302', 'tester');
  if v_reason_lost.outcome <> 'lost' or v_reason_won.outcome <> 'won' then
    raise exception 'assertion failed: expected reasons scoped to lost/won respectively';
  end if;

  begin
    perform app.create_win_loss_reason(v_tenant1, 'NO_BUDGET', 'Dup', 'lost', '00000000-0000-0000-0000-000000008302', 'tester');
    raise exception 'assertion failed: expected unique_violation for a duplicate reason code';
  exception
    when unique_violation then
      null; -- expected
  end;
end;
$$;

\echo '>> sales plan lifecycle: create (draft), targets, publish, overlap rejection, supersede chain'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_category_id uuid;
  v_plan_a app.sales_plans;
  v_plan_b app.sales_plans;
  v_plan_c app.sales_plans;
  v_plan_d app.sales_plans;
  v_target_captured app.sales_targets;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmepipeline');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPIPE-TEAM-A');
  v_category_id := (select id from app.pipeline_categories where tenant_id = v_tenant1 and code = 'TOP_FUNNEL');

  select * into v_plan_a from app.create_sales_plan(v_tenant1, v_team_a, 'Team A Current Plan', current_date - 1, current_date + 1, null, '00000000-0000-0000-0000-000000008302', 'tester');
  if v_plan_a.status <> 'draft' then
    raise exception 'assertion failed: expected a new plan to start in draft, got %', v_plan_a.status;
  end if;

  select * into v_target_captured from app.create_sales_target(v_plan_a.id, v_category_id, 'leads_captured', v_team_a, null, 2, '00000000-0000-0000-0000-000000008302', 'tester');
  perform app.create_sales_target(v_plan_a.id, v_category_id, 'leads_qualified', v_team_a, null, 1, '00000000-0000-0000-0000-000000008302', 'tester');
  perform app.create_sales_target(v_plan_a.id, v_category_id, 'prospects_created', v_team_a, null, 1, '00000000-0000-0000-0000-000000008302', 'tester');
  perform app.create_sales_target(v_plan_a.id, v_category_id, 'prospects_disqualified', v_team_a, null, 1, '00000000-0000-0000-0000-000000008302', 'tester');

  begin
    perform app.create_sales_target(v_plan_a.id, v_category_id, 'leads_captured', v_team_a, null, 99, '00000000-0000-0000-0000-000000008302', 'tester');
    raise exception 'assertion failed: expected unique_violation for a duplicate metric/scope target';
  exception
    when unique_violation then
      null; -- expected
  end;

  select * into v_target_captured from app.update_sales_target(v_target_captured.id, v_target_captured.record_version, 3, '00000000-0000-0000-0000-000000008302', 'tester');
  if v_target_captured.target_value <> 3 or v_target_captured.record_version <> 2 then
    raise exception 'assertion failed: expected target_value=3 record_version=2 after update, got %/%', v_target_captured.target_value, v_target_captured.record_version;
  end if;

  begin
    perform app.publish_sales_plan(v_plan_a.id, v_plan_a.record_version, null, '00000000-0000-0000-0000-000000008301', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- rep lacks COM:Approve';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_plan_a from app.publish_sales_plan(v_plan_a.id, v_plan_a.record_version, null, '00000000-0000-0000-0000-000000008302', 'tester');
  if v_plan_a.status <> 'published' then
    raise exception 'assertion failed: expected plan A to be published, got %', v_plan_a.status;
  end if;

  select * into v_plan_c from app.create_sales_plan(v_tenant1, v_team_a, 'Overlapping Plan', current_date, current_date + 5, null, '00000000-0000-0000-0000-000000008302', 'tester');
  begin
    perform app.publish_sales_plan(v_plan_c.id, v_plan_c.record_version, null, '00000000-0000-0000-0000-000000008302', 'tester');
    raise exception 'assertion failed: expected overlapping_plan (check_violation) publishing a second overlapping published plan';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_plan_b from app.create_sales_plan(v_tenant1, v_team_a, 'Team A Next Period', current_date + 30, current_date + 60, null, '00000000-0000-0000-0000-000000008302', 'tester');
  select * into v_plan_b from app.publish_sales_plan(v_plan_b.id, v_plan_b.record_version, null, '00000000-0000-0000-0000-000000008302', 'tester');
  if v_plan_b.status <> 'published' then
    raise exception 'assertion failed: expected plan B (non-overlapping period) to publish cleanly, got %', v_plan_b.status;
  end if;

  select * into v_plan_d from app.create_sales_plan(v_tenant1, v_team_a, 'Team A Next Period Revised', current_date + 30, current_date + 60, null, '00000000-0000-0000-0000-000000008302', 'tester');
  select * into v_plan_d from app.publish_sales_plan(v_plan_d.id, v_plan_d.record_version, v_plan_b.id, '00000000-0000-0000-0000-000000008302', 'tester');
  if v_plan_d.status <> 'published' or v_plan_d.supersedes_plan_id <> v_plan_b.id then
    raise exception 'assertion failed: expected plan D published and supersedes plan B, got status=% supersedes=%', v_plan_d.status, v_plan_d.supersedes_plan_id;
  end if;

  select * into v_plan_b from app.sales_plans where id = v_plan_b.id;
  if v_plan_b.status <> 'archived' then
    raise exception 'assertion failed: expected superseded plan B to be archived, got %', v_plan_b.status;
  end if;
end;
$$;

\echo '>> forecast reconciliation: computed values match canonical Lead/Prospect counts, override requires a reason'
do $$
declare
  v_plan_a app.sales_plans;
  v_target_captured app.sales_targets;
  v_target_qualified app.sales_targets;
  v_target_created app.sales_targets;
  v_target_disqualified app.sales_targets;
  v_actual integer;
  v_snapshot app.forecast_snapshots;
begin
  select * into v_plan_a from app.sales_plans where name = 'Team A Current Plan';
  select * into v_target_captured from app.sales_targets where sales_plan_id = v_plan_a.id and metric_type = 'leads_captured';
  select * into v_target_qualified from app.sales_targets where sales_plan_id = v_plan_a.id and metric_type = 'leads_qualified';
  select * into v_target_created from app.sales_targets where sales_plan_id = v_plan_a.id and metric_type = 'prospects_created';
  select * into v_target_disqualified from app.sales_targets where sales_plan_id = v_plan_a.id and metric_type = 'prospects_disqualified';

  v_actual := app.get_sales_target_actual(v_target_captured.id, '00000000-0000-0000-0000-000000008301');
  if v_actual <> 2 then
    raise exception 'assertion failed: expected 2 leads_captured (team A only, team B excluded), got %', v_actual;
  end if;

  v_actual := app.get_sales_target_actual(v_target_qualified.id, '00000000-0000-0000-0000-000000008301');
  if v_actual <> 1 then
    raise exception 'assertion failed: expected 1 leads_qualified, got %', v_actual;
  end if;

  v_actual := app.get_sales_target_actual(v_target_created.id, '00000000-0000-0000-0000-000000008301');
  if v_actual <> 1 then
    raise exception 'assertion failed: expected 1 prospects_created, got %', v_actual;
  end if;

  v_actual := app.get_sales_target_actual(v_target_disqualified.id, '00000000-0000-0000-0000-000000008301');
  if v_actual <> 1 then
    raise exception 'assertion failed: expected 1 prospects_disqualified, got %', v_actual;
  end if;

  select * into v_snapshot from app.capture_forecast_snapshot(v_target_captured.id, null, null, '00000000-0000-0000-0000-000000008302', 'tester');
  if v_snapshot.computed_value <> 2 or v_snapshot.override_value is not null then
    raise exception 'assertion failed: expected computed_value=2 with no override, got computed_value=% override_value=%', v_snapshot.computed_value, v_snapshot.override_value;
  end if;

  begin
    perform app.capture_forecast_snapshot(v_target_captured.id, 5, null, '00000000-0000-0000-0000-000000008302', 'tester');
    raise exception 'assertion failed: expected check_violation -- an override value requires a non-empty reason';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_snapshot from app.capture_forecast_snapshot(v_target_captured.id, 5, 'Manual adjustment for known year-end backlog', '00000000-0000-0000-0000-000000008302', 'tester');
  if v_snapshot.computed_value <> 2 or v_snapshot.override_value <> 5 then
    raise exception 'assertion failed: expected computed_value=2 override_value=5, got computed_value=% override_value=%', v_snapshot.computed_value, v_snapshot.override_value;
  end if;

  begin
    perform app.get_sales_target_actual(v_target_captured.id, '00000000-0000-0000-0000-000000008303');
    raise exception 'assertion failed: expected insufficient_privilege -- sibling-team outsider cannot access a team-A target';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> get_pipeline_summary: SECURITY INVOKER read-model respects RLS exactly like a direct drill-down query'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_branch uuid;
  v_total integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmepipeline');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPIPE-TEAM-A');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEPIPE-BR');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008301", "role": "authenticated"}';
  select coalesce(sum(record_count), 0) into v_total from app.get_pipeline_summary(v_tenant1, v_team_a);
  if v_total <> 3 then
    raise exception 'assertion failed: expected rep to see 3 team-A rows (2 leads + 1 prospect), got %', v_total;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008302", "role": "authenticated"}';
  select coalesce(sum(record_count), 0) into v_total from app.get_pipeline_summary(v_tenant1, v_branch);
  if v_total <> 4 then
    raise exception 'assertion failed: expected branch manager to see 4 rows (2 team-A leads + 1 team-A prospect + 1 team-B lead), got %', v_total;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008303", "role": "authenticated"}';
  select coalesce(sum(record_count), 0) into v_total from app.get_pipeline_summary(v_tenant1, v_team_a);
  if v_total <> 0 then
    raise exception 'assertion failed: expected sibling-team outsider to see 0 team-A rows (RLS hides them regardless of the business filter), got %', v_total;
  end if;
  reset role;
end;
$$;

\echo '>> sales_plans/sales_targets RLS: owner/ancestor-manager see the plan, sibling-team outsider does not'
do $$
declare
  v_plan_id uuid;
  v_count integer;
begin
  v_plan_id := (select id from app.sales_plans where name = 'Team A Current Plan');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008301", "role": "authenticated"}';
  select count(*) into v_count from app.sales_plans where id = v_plan_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the team-A rep to see the team-A plan'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008302", "role": "authenticated"}';
  select count(*) into v_count from app.sales_plans where id = v_plan_id;
  if v_count <> 1 then raise exception 'assertion failed: expected the branch manager (ancestor org unit) to see the team-A plan'; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008303", "role": "authenticated"}';
  select count(*) into v_count from app.sales_plans where id = v_plan_id;
  if v_count <> 0 then raise exception 'assertion failed: expected the sibling-team outsider to be denied, found % row(s)', v_count; end if;
  reset role;
end;
$$;

\echo '>> pipeline_categories/win_loss_reasons RLS: any tenant member reads the reference list, cross-tenant denied'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmepipeline');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008303", "role": "authenticated"}';
  select count(*) into v_count from app.pipeline_categories where tenant_id = v_tenant1;
  if v_count <> 1 then raise exception 'assertion failed: expected the sibling-team outsider (still a tenant member) to see the reference category, found %', v_count; end if;
  select count(*) into v_count from app.win_loss_reasons where tenant_id = v_tenant1;
  if v_count <> 2 then raise exception 'assertion failed: expected 2 win/loss reasons visible tenant-wide, found %', v_count; end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008304", "role": "authenticated"}';
  select count(*) into v_count from app.pipeline_categories where tenant_id = v_tenant1;
  if v_count <> 0 then raise exception 'assertion failed: expected a different-tenant actor to see 0 rows, found %', v_count; end if;
  reset role;
end;
$$;

\echo '>> record_pipeline_outcome: reason/outcome match enforced, supersede chain preserves history, cross-tenant reason denied'
do $$
declare
  v_prospect app.prospects;
  v_reason_lost app.win_loss_reasons;
  v_reason_won app.win_loss_reasons;
  v_tenant2_reason app.win_loss_reasons;
  v_first app.pipeline_outcomes;
  v_second app.pipeline_outcomes;
begin
  select * into v_prospect from app.prospects where legal_name = 'Contoso Pipeline Ltd';
  select * into v_reason_lost from app.win_loss_reasons where code = 'NO_BUDGET';
  select * into v_reason_won from app.win_loss_reasons where code = 'BEST_FIT';

  begin
    perform app.record_pipeline_outcome('prospect', v_prospect.id, 'lost', v_reason_won.id, 'Mismatched outcome', '00000000-0000-0000-0000-000000008301', 'tester');
    raise exception 'assertion failed: expected check_violation -- outcome lost does not match reason scoped to won';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  begin
    perform app.record_pipeline_outcome('prospect', v_prospect.id, 'lost', v_reason_lost.id, 'Denied', '00000000-0000-0000-0000-000000008303', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- sibling-team outsider cannot access this prospect';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_first from app.record_pipeline_outcome('prospect', v_prospect.id, 'lost', v_reason_lost.id, 'Client had no budget this cycle', '00000000-0000-0000-0000-000000008301', 'tester');
  if not v_first.is_current or v_first.outcome <> 'lost' then
    raise exception 'assertion failed: expected a current lost outcome, got is_current=% outcome=%', v_first.is_current, v_first.outcome;
  end if;

  select * into v_tenant2_reason from app.create_win_loss_reason(
    (select id from app.tenants where slug = 'betapipeline'), 'OTHER_TENANT_REASON', 'Other tenant reason', 'lost',
    '00000000-0000-0000-0000-000000008304', 'tester'
  );
  begin
    perform app.record_pipeline_outcome('prospect', v_prospect.id, 'lost', v_tenant2_reason.id, 'Cross tenant', '00000000-0000-0000-0000-000000008301', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- cross-tenant reason denied';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_second from app.record_pipeline_outcome('prospect', v_prospect.id, 'lost', v_reason_lost.id, 'Reconfirmed after follow-up', '00000000-0000-0000-0000-000000008301', 'tester');

  select * into v_first from app.pipeline_outcomes where id = v_first.id;
  if v_first.is_current or v_first.superseded_by_id <> v_second.id then
    raise exception 'assertion failed: expected the first outcome to be superseded by the second, got is_current=% superseded_by_id=%', v_first.is_current, v_first.superseded_by_id;
  end if;
  if not v_second.is_current then
    raise exception 'assertion failed: expected the second outcome to be the current one';
  end if;
end;
$$;

\echo '>> archive_sales_plan: valid transition, cannot archive twice'
do $$
declare
  v_plan app.sales_plans;
begin
  select * into v_plan from app.sales_plans where name = 'Overlapping Plan';
  select * into v_plan from app.archive_sales_plan(v_plan.id, v_plan.record_version, '00000000-0000-0000-0000-000000008302', 'tester');
  if v_plan.status <> 'archived' then
    raise exception 'assertion failed: expected the draft plan to archive directly, got %', v_plan.status;
  end if;

  begin
    perform app.archive_sales_plan(v_plan.id, v_plan.record_version, '00000000-0000-0000-0000-000000008302', 'tester');
    raise exception 'assertion failed: expected check_violation archiving an already-archived plan';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> audit trail: plan/target/category/reason/forecast/outcome mutations all recorded real app.audit_logs events'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs where resource_type = 'app.sales_plans' and action = 'create_sales_plan';
  if v_count < 1 then raise exception 'assertion failed: expected at least 1 create_sales_plan audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.sales_plans' and action = 'publish_sales_plan';
  if v_count < 1 then raise exception 'assertion failed: expected at least 1 publish_sales_plan audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.sales_targets' and action = 'create_sales_target';
  if v_count < 1 then raise exception 'assertion failed: expected at least 1 create_sales_target audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.pipeline_categories' and action = 'create_pipeline_category';
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 create_pipeline_category audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.win_loss_reasons' and action = 'create_win_loss_reason';
  if v_count < 2 then raise exception 'assertion failed: expected at least 2 create_win_loss_reason audit events, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.forecast_snapshots' and action = 'capture_forecast_snapshot';
  if v_count < 2 then raise exception 'assertion failed: expected at least 2 capture_forecast_snapshot audit events, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.pipeline_outcomes' and action = 'record_pipeline_outcome';
  if v_count <> 2 then raise exception 'assertion failed: expected exactly 2 record_pipeline_outcome audit events, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.prospects' and action = 'disqualify_prospect';
  if v_count < 1 then raise exception 'assertion failed: expected at least 1 disqualify_prospect audit event, found %', v_count; end if;
end;
$$;
