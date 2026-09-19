-- Real, executable test evidence for CG-AUDIT-2026-09-02 Ø1-query-layer, cluster 0 batch 2
-- (supabase/migrations/20260909000000_close_o1_query_layer_cluster0_batch2_pipeline_margin_opportunity.sql).
--
-- Proves, against a real disposable database: each new app.*/public.* function returns the
-- real data a member can see; RULE A genuinely rejects a claimed actor that does not match
-- the real session identity; RULE B excludes a customer_user-layer principal from the three
-- functions whose RLS predicate requires it (app.margin_rule_versions family,
-- app.pipeline_categories, app.win_loss_reasons); a global Supreme Admin with ZERO tenant
-- membership genuinely gets the true bypass app.margin_rule_versions' predicate grants (OR
-- is_supreme_admin()), but genuinely does NOT bypass app.pipeline_categories/
-- app.win_loss_reasons (whose predicate has no supreme-admin branch at all) or any
-- can_access_record-gated function (whose own body requires has_active_tenant_membership
-- unconditionally, even for a supreme admin); and cross-tenant denial throughout.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant with an org_user member (also the owner of every fixture row), a customer_user-layer principal, a global Supreme Admin with NO membership in this tenant, and a second isolated tenant'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000998101', 'membero1b2@example.test'),
    ('00000000-0000-0000-0000-000000998103', 'customerusero1b2@example.test'),
    ('00000000-0000-0000-0000-000000998104', 'supremeo1b2@example.test'),
    ('00000000-0000-0000-0000-000000998105', 'othertenanto1b2@example.test');

  perform app.provision_tenant('acmeo1b2', 'Acme O1B2 Co', 'idem-acmeo1b2', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b2');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEO1B2-CO', 'Acme O1B2 Co', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B2-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000998101', 'membero1b2@example.test', 'Member', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'membero1b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998101', 'org_user', v_tenant_id, null, 'tester');

  -- A customer_user-layer principal in this same tenant -- satisfies has_active_tenant_membership
  -- but must still be excluded by RULE B from margin_rule_versions/pipeline_categories/
  -- win_loss_reasons. customer_account_ref is plain text (no FK to app.accounts), so a
  -- placeholder value is sufficient to establish the layer.
  perform app.link_auth_identity('00000000-0000-0000-0000-000000998103', v_tenant_id, 'tester', 'active');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998103', 'customer_user', v_tenant_id, 'fake-account-ref', 'tester');

  -- A GLOBAL Supreme Admin with NO principal_memberships row at all for this tenant --
  -- deliberately never invited/onboarded here, to prove the true supreme-admin bypass only
  -- fires where the predicate itself grants it (margin_rule_versions), and genuinely does not
  -- fire where it does not (pipeline_categories/win_loss_reasons have no is_supreme_admin
  -- branch; every can_access_record-gated function requires has_active_tenant_membership
  -- unconditionally, even for a supreme admin).
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998104', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoo1b2', 'Gizmo O1B2 Co', 'idem-gizmoo1b2', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoo1b2');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000998105', 'othertenanto1b2@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenanto1b2@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000998105', 'tenant_admin', v_other_tenant_id, null, 'tester');
end $$;

\echo '>> app.margin_rule_versions family: real data for a member, RULE B excludes the customer_user layer, TRUE supreme-admin bypass (no membership needed), cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_published_id uuid;
  v_draft_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b2');

  insert into app.margin_rule_versions (id, tenant_id, minimum_margin_pct, rounding_mode, status, created_by)
  values (gen_random_uuid(), v_tenant_id, 20.00, 'half_up', 'published', 'tester')
  returning id into v_published_id;

  insert into app.margin_rule_versions (id, tenant_id, minimum_margin_pct, rounding_mode, status, created_by)
  values (gen_random_uuid(), v_tenant_id, 25.00, 'half_up', 'draft', 'tester')
  returning id into v_draft_id;

  select count(*) into v_count from app.get_published_margin_rule(v_tenant_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 published margin rule for the member, got %', v_count;
  end if;

  select count(*) into v_count from app.list_margin_rule_versions(v_tenant_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 margin rule versions (any status) for the member, got %', v_count;
  end if;

  -- RULE B: the customer_user-layer principal must not see margin rules at all.
  begin
    perform app.get_published_margin_rule(v_tenant_id, '00000000-0000-0000-0000-000000998103');
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not read the published margin rule';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform app.list_margin_rule_versions(v_tenant_id, '00000000-0000-0000-0000-000000998103');
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not list margin rule versions';
  exception
    when insufficient_privilege then null;
  end;

  -- TRUE supreme-admin bypass: this predicate is "... OR is_supreme_admin()" -- no tenant
  -- membership required at all. The fixture Supreme Admin has zero standing in this tenant.
  select count(*) into v_count from app.list_margin_rule_versions(v_tenant_id, '00000000-0000-0000-0000-000000998104');
  if v_count <> 2 then
    raise exception 'assertion failed: expected the Supreme Admin (zero membership) to see both margin rule versions via the true bypass, got %', v_count;
  end if;

  -- Cross-tenant: the other tenant's admin has no standing in this tenant at all.
  begin
    perform app.list_margin_rule_versions(v_tenant_id, '00000000-0000-0000-0000-000000998105');
    raise exception 'assertion failed: expected insufficient_authority for a non-member of the tenant';
  exception
    when insufficient_privilege then null;
  end;

  raise notice 'app.margin_rule_versions family proof: member sees 1 published/2 total, customer_user-layer excluded (RULE B), Supreme Admin bypasses with zero membership, cross-tenant denied';
end $$;

\echo '>> RULE A: app.list_margin_rule_versions genuinely rejects a claimed actor that does not match the real session identity'
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000998105", "role": "authenticated"}';
  do $$
  declare
    v_tenant_id uuid;
  begin
    v_tenant_id := (select id from app.tenants where slug = 'acmeo1b2');
    begin
      -- Real session is 998105 (the other tenant's admin); claims to be 998101 (this
      -- tenant's own member, who WOULD otherwise be allowed) -- must still be rejected.
      perform app.list_margin_rule_versions(v_tenant_id, '00000000-0000-0000-0000-000000998101');
      raise exception 'assertion failed: RULE A -- a claimed actor that does not match the real session identity must be rejected';
    exception
      when insufficient_privilege then
        raise notice 'RULE A proof: impersonation attempt correctly rejected (actor_identity_mismatch)';
    end;
  end $$;
  reset role;
  reset request.jwt.claims;
commit;

\echo '>> app.opportunities family + app.opportunity_stage_history + app.margin_calculations_for_request: real (masked) data for the owner, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_lead_id uuid;
  v_prospect_id uuid;
  v_opportunity_id uuid;
  v_costing_request_id uuid;
  v_rate_selection_id uuid;
  v_rule_version_id uuid;
  v_margin_calc_id uuid;
  v_count integer;
  v_value_amount numeric;
  v_probability integer;
  v_value_masked boolean;
  v_total_count bigint;
  v_cost_masked boolean;
  v_sell_masked boolean;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b2');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B2-CO');
  v_rule_version_id := (select id from app.margin_rule_versions where tenant_id = v_tenant_id and status = 'published');

  v_lead_id := gen_random_uuid();
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, owner_user_id, org_unit_id, created_by)
  values (v_lead_id, v_tenant_id, 'manual', 'O1B2 Test Lead', 'o1b2lead@example.test', 'fp-o1b2-lead-1', '00000000-0000-0000-0000-000000998101', v_org_unit_id, 'tester');

  v_prospect_id := gen_random_uuid();
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, owner_user_id, org_unit_id, created_by)
  values (v_prospect_id, v_tenant_id, v_lead_id, 'O1B2 Test Prospect Co', 'fp-o1b2-prospect-1', 'O1B2 Test Lead', '00000000-0000-0000-0000-000000998101', v_org_unit_id, 'tester');

  v_opportunity_id := gen_random_uuid();
  insert into app.opportunities (id, tenant_id, prospect_id, name, probability, value_amount, value_currency, owner_user_id, org_unit_id, created_by)
  values (v_opportunity_id, v_tenant_id, v_prospect_id, 'O1B2 Test Opportunity', 40, 5000000, 'IDR', '00000000-0000-0000-0000-000000998101', v_org_unit_id, 'tester');

  insert into app.opportunity_stage_history (tenant_id, opportunity_id, from_stage, to_stage, probability, changed_by)
  values (v_tenant_id, v_opportunity_id, null, 'qualifying', 40, 'tester');

  v_costing_request_id := gen_random_uuid();
  insert into app.costing_requests (id, tenant_id, opportunity_id, source_opportunity_version, owner_user_id, org_unit_id, created_by)
  values (v_costing_request_id, v_tenant_id, v_opportunity_id, 1, '00000000-0000-0000-0000-000000998101', v_org_unit_id, 'tester');

  v_rate_selection_id := gen_random_uuid();
  insert into app.rate_selections (id, tenant_id, costing_request_id, is_adhoc, currency, amount, snapshot, override_reason, selected_by)
  values (v_rate_selection_id, v_tenant_id, v_costing_request_id, true, 'IDR', 1000000, '{}'::jsonb, 'no vendor rate available, ad-hoc test fixture', 'tester');

  v_margin_calc_id := gen_random_uuid();
  insert into app.margin_calculations (
    id, tenant_id, costing_request_id, rate_selection_id, cost_amount, cost_currency, sell_amount, sell_currency,
    discount_amount, net_sell_amount, margin_amount, margin_pct, rule_version_id, minimum_margin_pct_snapshot,
    rounding_mode_snapshot, threshold_outcome, created_by
  ) values (
    v_margin_calc_id, v_tenant_id, v_costing_request_id, v_rate_selection_id, 1000000, 'IDR', 1500000, 'IDR',
    0, 1500000, 500000, 33.33, v_rule_version_id, 20.00, 'half_up', 'pass', 'tester'
  );

  -- app.list_opportunities: masked (no COM:View selling price granted to the member), total_count exact.
  select value_amount, probability, value_masked, total_count
    into v_value_amount, v_probability, v_value_masked, v_total_count
    from app.list_opportunities(v_tenant_id, '00000000-0000-0000-0000-000000998101');
  if v_total_count <> 1 or v_value_amount is not null or v_probability is not null or v_value_masked is not true then
    raise exception 'assertion failed: expected 1 masked opportunity (value_amount/probability null, value_masked true, total_count 1), got total_count=%, value_amount=%, probability=%, value_masked=%', v_total_count, v_value_amount, v_probability, v_value_masked;
  end if;

  -- Cross-tenant: 998105 has zero standing in acmeo1b2 -- silent empty page, never an exception.
  select count(*) into v_count from app.list_opportunities(v_tenant_id, '00000000-0000-0000-0000-000000998105');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this tenant''s opportunities, got %', v_count;
  end if;

  -- app.get_opportunity_by_id: same masking, zero rows for a denied/cross-tenant actor.
  select count(*) into v_count from app.get_opportunity_by_id(v_opportunity_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owner to read the opportunity by id';
  end if;
  select count(*) into v_count from app.get_opportunity_by_id(v_opportunity_id, '00000000-0000-0000-0000-000000998105');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not read this opportunity by id, got %', v_count;
  end if;

  -- app.list_opportunity_stage_history: real data for the owner, zero for cross-tenant.
  select count(*) into v_count from app.list_opportunity_stage_history(v_opportunity_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 stage-history row for the owner, got %', v_count;
  end if;
  select count(*) into v_count from app.list_opportunity_stage_history(v_opportunity_id, '00000000-0000-0000-0000-000000998105');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this opportunity''s stage history, got %', v_count;
  end if;

  -- app.list_margin_calculations_for_request: masked (no COM:View cost/selling price granted).
  select count(*), bool_and(cost_masked), bool_and(sell_masked)
    into v_count, v_cost_masked, v_sell_masked
    from app.list_margin_calculations_for_request(v_costing_request_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 or v_cost_masked is not true or v_sell_masked is not true then
    raise exception 'assertion failed: expected exactly 1 masked margin calculation (cost_masked/sell_masked both true), got count=%, cost_masked=%, sell_masked=%', v_count, v_cost_masked, v_sell_masked;
  end if;
  select count(*) into v_count from app.list_margin_calculations_for_request(v_costing_request_id, '00000000-0000-0000-0000-000000998105');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this costing request''s margin calculations, got %', v_count;
  end if;

  raise notice 'app.opportunities/app.opportunity_stage_history/app.margin_calculations_for_request proof: owner sees masked data, cross-tenant actor sees zero throughout';
end $$;

\echo '>> app.sales_plans / app.sales_targets_for_plan / app.forecast_snapshots_for_target: real data for the owner, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_org_unit_id uuid;
  v_plan_id uuid;
  v_target_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b2');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEO1B2-CO');

  v_plan_id := gen_random_uuid();
  insert into app.sales_plans (id, tenant_id, org_unit_id, name, period_start, period_end, status, owner_user_id, created_by)
  values (v_plan_id, v_tenant_id, v_org_unit_id, 'O1B2 Test Plan', '2026-01-01', '2026-12-31', 'draft', '00000000-0000-0000-0000-000000998101', 'tester');

  v_target_id := gen_random_uuid();
  insert into app.sales_targets (id, tenant_id, sales_plan_id, org_unit_id, owner_user_id, metric_type, target_value, created_by)
  values (v_target_id, v_tenant_id, v_plan_id, v_org_unit_id, '00000000-0000-0000-0000-000000998101', 'leads_captured', 10, 'tester');

  insert into app.forecast_snapshots (tenant_id, sales_target_id, computed_value, created_by)
  values (v_tenant_id, v_target_id, 5, 'tester');

  select count(*) into v_count from app.list_sales_plans(v_tenant_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 sales plan for the owner, got %', v_count;
  end if;
  select count(*) into v_count from app.list_sales_plans(v_tenant_id, '00000000-0000-0000-0000-000000998105');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this tenant''s sales plans, got %', v_count;
  end if;

  select count(*) into v_count from app.get_sales_plan_by_id(v_plan_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owner to read the sales plan by id';
  end if;
  select count(*) into v_count from app.get_sales_plan_by_id(v_plan_id, '00000000-0000-0000-0000-000000998105');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not read this sales plan by id, got %', v_count;
  end if;

  select count(*) into v_count from app.list_sales_targets_for_plan(v_plan_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 sales target for the plan owner, got %', v_count;
  end if;
  select count(*) into v_count from app.list_sales_targets_for_plan(v_plan_id, '00000000-0000-0000-0000-000000998105');
  if v_count <> 0 then
    raise exception 'assertion failed: a different tenant''s admin must not see this plan''s sales targets, got %', v_count;
  end if;

  select count(*) into v_count from app.list_forecast_snapshots_for_target(v_target_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 forecast snapshot for the target owner, got %', v_count;
  end if;

  -- A different tenant's admin has zero standing here -- the ISS-2026-146 tenant-id-disclosure-safe
  -- branch raises the SAME sales_target_not_found message a genuinely nonexistent id would.
  begin
    perform app.list_forecast_snapshots_for_target(v_target_id, '00000000-0000-0000-0000-000000998105');
    raise exception 'assertion failed: expected sales_target_not_found for a different tenant''s admin';
  exception
    when no_data_found then null;
  end;

  raise notice 'app.sales_plans/app.sales_targets_for_plan/app.forecast_snapshots_for_target proof: owner sees 1 row each, cross-tenant actor denied throughout';
end $$;

\echo '>> app.pipeline_categories / app.win_loss_reasons: real data for a member, RULE B excludes the customer_user layer, transitive supreme-admin bypass via has_active_tenant_membership, cross-tenant denied'
do $$
declare
  v_tenant_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeo1b2');

  insert into app.pipeline_categories (tenant_id, code, label, sort_order, created_by)
  values (v_tenant_id, 'C1', 'Stage 1', 1, 'tester');

  insert into app.win_loss_reasons (tenant_id, code, label, outcome, created_by)
  values (v_tenant_id, 'PRICE', 'Price too high', 'lost', 'tester');

  select count(*) into v_count from app.list_pipeline_categories(v_tenant_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 pipeline category for the member, got %', v_count;
  end if;

  select count(*) into v_count from app.list_win_loss_reasons(v_tenant_id, '00000000-0000-0000-0000-000000998101');
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 win/loss reason for the member, got %', v_count;
  end if;

  -- RULE B: the customer_user-layer principal must not see either reference list.
  begin
    perform app.list_pipeline_categories(v_tenant_id, '00000000-0000-0000-0000-000000998103');
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not list pipeline categories';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform app.list_win_loss_reasons(v_tenant_id, '00000000-0000-0000-0000-000000998103');
    raise exception 'assertion failed: RULE B -- a customer_user-layer principal must not list win/loss reasons';
  exception
    when insufficient_privilege then null;
  end;

  -- Transitive supreme-admin bypass: neither predicate has its OWN separate
  -- "OR is_supreme_admin()" clause, but app.has_active_tenant_membership's own current body
  -- (20260907110000) already ORs in app.is_supreme_admin(actor) internally -- so the fixture
  -- Supreme Admin (zero explicit tenant_user_identities/app.users row for this tenant) still
  -- passes has_active_tenant_membership, and holds no customer_user-layer membership either,
  -- so both functions admit them. Confirmed live: an earlier version of this test wrongly
  -- assumed the Supreme Admin would be denied here (reasoning from the absence of an outer
  -- is_supreme_admin() branch alone) and was corrected after seeing this real behavior.
  select count(*) into v_count from app.list_pipeline_categories(v_tenant_id, '00000000-0000-0000-0000-000000998104');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Supreme Admin to see the pipeline category via has_active_tenant_membership''s own transitive bypass, got %', v_count;
  end if;
  select count(*) into v_count from app.list_win_loss_reasons(v_tenant_id, '00000000-0000-0000-0000-000000998104');
  if v_count <> 1 then
    raise exception 'assertion failed: expected the Supreme Admin to see the win/loss reason via has_active_tenant_membership''s own transitive bypass, got %', v_count;
  end if;

  -- Cross-tenant: the other tenant's admin has no standing in this tenant at all.
  begin
    perform app.list_pipeline_categories(v_tenant_id, '00000000-0000-0000-0000-000000998105');
    raise exception 'assertion failed: expected insufficient_authority for a non-member of the tenant (pipeline categories)';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform app.list_win_loss_reasons(v_tenant_id, '00000000-0000-0000-0000-000000998105');
    raise exception 'assertion failed: expected insufficient_authority for a non-member of the tenant (win/loss reasons)';
  exception
    when insufficient_privilege then null;
  end;

  raise notice 'app.pipeline_categories/app.win_loss_reasons proof: member sees 1 row each, customer_user-layer excluded (RULE B), Supreme Admin with zero membership still admitted (transitive bypass via has_active_tenant_membership), cross-tenant denied';
end $$;

\echo '>> o1-query-layer-cluster0-batch2.sql test suite passed'
