-- Real, executable test evidence for COM-150 (Margin Calculation, CG-S7-COM-009) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a company/branch/team-a/team-b org hierarchy, a tenant_admin (rate authority), a manager (COM:Create/Edit/Approve/View selling price, no View cost), a rep (COM:Create/Edit/View selling price/View cost), a sibling-team outsider, and a full opportunity/costing-request/rate-selection chain'
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
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009101', 'tenantadmin@acmemargin.test'),
    ('00000000-0000-0000-0000-000000009102', 'manager@acmemargin.test'),
    ('00000000-0000-0000-0000-000000009103', 'rep@acmemargin.test'),
    ('00000000-0000-0000-0000-000000009104', 'outsider@acmemargin.test');

  perform app.provision_tenant('acmemargin', 'Acme Margin Co', 'idem-acmemargin', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmemargin');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betamargin', 'Beta Margin Co', 'idem-betamargin', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betamargin');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEMARGIN-CO', 'Acme Margin Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMARGIN-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEMARGIN-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMARGIN-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEMARGIN-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMARGIN-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEMARGIN-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEMARGIN-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009101', 'tenantadmin@acmemargin.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmemargin.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009102', 'manager@acmemargin.test', 'Branch Manager', v_branch, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmemargin.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009103', 'rep@acmemargin.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmemargin.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009104', 'outsider@acmemargin.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmemargin.test'), 'active', 'onboarded', 'tester');

  v_mgr_role := (app.create_role(v_tenant1, 'Margin Manager', 'margin governance', 'tester')).id;
  v_mgr_draft := app.create_role_version(v_mgr_role, 'tester');
  perform app.set_role_version_permissions(
    v_mgr_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price')),
    'tester'
  );
  perform app.publish_role_version(v_mgr_draft.id, now(), 'tester');
  -- The manager's own role carries a protected permission ('View selling price') --
  -- self-assignment would trip app.assign_role's self-escalation guard (actor=grantee AND
  -- the role version carries a protected permission), so the tenant_admin (a distinct
  -- actor) assigns it instead, mirroring COM-147/148/149's own established fixture
  -- pattern for this exact guard.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_mgr_role and status = 'published'),
    '00000000-0000-0000-0000-000000009102', '00000000-0000-0000-0000-000000009101', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Margin Rep', 'margin capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009103', '00000000-0000-0000-0000-000000009102', 'tester');

  v_out_role := (app.create_role(v_tenant1, 'Team B Margin Rep', 'sibling team', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000009104', '00000000-0000-0000-0000-000000009102', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Margin Ltd', 'Jane Doe', 'jane@contosomargin.test', '0811',
    '00000000-0000-0000-0000-000000009103', v_team_a, '00000000-0000-0000-0000-000000009103', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosomargin.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009103', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosomargin.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Contoso Margin Ltd', null, '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009103', 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Contoso Margin Ltd';

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Contoso Jakarta-Surabaya margin lane',
    jsonb_build_object(
      'service_type', 'ocean_freight', 'cargo_description', 'General cargo',
      'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'
    ),
    '00000000-0000-0000-0000-000000009103', v_team_a, '00000000-0000-0000-0000-000000009103', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009103', 'tester');

  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-MARGIN-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009101', 'tester');

  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009103', 'tester');
end;
$$;

\echo '>> calculate_margin: no_active_margin_rule before any rule is published'
do $$
declare
  v_selection_id uuid;
begin
  v_selection_id := (select id from app.rate_selections where costing_request_id = (select id from app.costing_requests where opportunity_id = (select id from app.opportunities where name = 'Contoso Jakarta-Surabaya margin lane')));

  begin
    perform app.calculate_margin(v_selection_id, 12000000, 'IDR', 0, '00000000-0000-0000-0000-000000009103', 'tester');
    raise exception 'assertion failed: expected check_violation -- no published margin rule exists yet';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> create_margin_rule_version / publish_margin_rule_version: authority-gated (COM:Create / COM:Approve), at most one published rule per tenant, supersede archives the prior one'
do $$
declare
  v_tenant1 uuid;
  v_rule1 app.margin_rule_versions;
  v_rule2 app.margin_rule_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmemargin');

  select * into v_rule1 from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009102', 'tester');
  if v_rule1.status <> 'draft' or v_rule1.minimum_margin_pct <> 20.00 then
    raise exception 'assertion failed: expected status=draft minimum_margin_pct=20.00, got status=% minimum=%', v_rule1.status, v_rule1.minimum_margin_pct;
  end if;

  begin
    perform app.publish_margin_rule_version(v_rule1.id, v_rule1.record_version, null, '00000000-0000-0000-0000-000000009103', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the rep lacks COM:Approve';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_rule1 from app.publish_margin_rule_version(v_rule1.id, v_rule1.record_version, null, '00000000-0000-0000-0000-000000009102', 'tester');
  if v_rule1.status <> 'published' then
    raise exception 'assertion failed: expected status=published, got %', v_rule1.status;
  end if;

  select * into v_rule2 from app.create_margin_rule_version(v_tenant1, 25.00, 'half_up', '00000000-0000-0000-0000-000000009102', 'tester');

  begin
    perform app.publish_margin_rule_version(v_rule2.id, v_rule2.record_version, null, '00000000-0000-0000-0000-000000009102', 'tester');
    raise exception 'assertion failed: expected check_violation -- a second published rule without supersedes_version_id must be rejected';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  select * into v_rule2 from app.publish_margin_rule_version(v_rule2.id, v_rule2.record_version, v_rule1.id, '00000000-0000-0000-0000-000000009102', 'tester');
  if v_rule2.status <> 'published' then
    raise exception 'assertion failed: expected the second rule to publish once superseding the first, got status=%', v_rule2.status;
  end if;

  select * into v_rule1 from app.margin_rule_versions where id = v_rule1.id;
  if v_rule1.status <> 'archived' then
    raise exception 'assertion failed: expected the first rule to be archived once superseded, got %', v_rule1.status;
  end if;

  -- Restore a 20.00 minimum for the remaining scenarios below (the concrete numbers in
  -- this test file's own calculations are chosen against a 20% threshold).
  perform app.publish_margin_rule_version(
    (app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009102', 'tester')).id,
    1, v_rule2.id, '00000000-0000-0000-0000-000000009102', 'tester'
  );
end;
$$;

\echo '>> calculate_margin: requires COM:Edit + COM:View cost, fails closed on mixed currency and out-of-range discount, computes exact decimal margin/markup, recalculation supersedes the prior current row'
do $$
declare
  v_selection_id uuid;
  v_calc1 app.margin_calculations;
  v_calc2 app.margin_calculations;
begin
  v_selection_id := (select id from app.rate_selections where costing_request_id = (select id from app.costing_requests where opportunity_id = (select id from app.opportunities where name = 'Contoso Jakarta-Surabaya margin lane')));

  begin
    perform app.calculate_margin(v_selection_id, 12000000, 'IDR', 0, '00000000-0000-0000-0000-000000009102', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the manager lacks COM:View cost';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  begin
    perform app.calculate_margin(v_selection_id, 12000000, 'USD', 0, '00000000-0000-0000-0000-000000009103', 'tester');
    raise exception 'assertion failed: expected check_violation -- USD does not match the pinned IDR cost snapshot';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  begin
    perform app.calculate_margin(v_selection_id, 12000000, 'IDR', 150, '00000000-0000-0000-0000-000000009103', 'tester');
    raise exception 'assertion failed: expected check_violation -- discount_pct 150 is out of the 0..100 range';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  -- cost 10,000,000; sell 12,000,000; no discount -> margin 2,000,000; margin_pct 16.67% (< 20% minimum -> requires_approval); markup_pct 20.00%.
  select * into v_calc1 from app.calculate_margin(v_selection_id, 12000000, 'IDR', 0, '00000000-0000-0000-0000-000000009103', 'tester');
  if v_calc1.margin_amount <> 2000000 or v_calc1.margin_pct <> 16.67 or v_calc1.markup_pct <> 20.00 or v_calc1.threshold_outcome <> 'requires_approval' then
    raise exception 'assertion failed: expected margin_amount=2000000 margin_pct=16.67 markup_pct=20.00 threshold_outcome=requires_approval, got amount=% pct=% markup=% outcome=%', v_calc1.margin_amount, v_calc1.margin_pct, v_calc1.markup_pct, v_calc1.threshold_outcome;
  end if;
  if not v_calc1.is_current then
    raise exception 'assertion failed: expected the first calculation to be is_current=true';
  end if;

  -- cost 10,000,000; sell 15,000,000; no discount -> margin 5,000,000; margin_pct 33.33% (>= 20% -> pass); markup_pct 50.00%. Recalculates the same rate_selection_id.
  select * into v_calc2 from app.calculate_margin(v_selection_id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009103', 'tester');
  if v_calc2.margin_amount <> 5000000 or v_calc2.margin_pct <> 33.33 or v_calc2.markup_pct <> 50.00 or v_calc2.threshold_outcome <> 'pass' then
    raise exception 'assertion failed: expected margin_amount=5000000 margin_pct=33.33 markup_pct=50.00 threshold_outcome=pass, got amount=% pct=% markup=% outcome=%', v_calc2.margin_amount, v_calc2.margin_pct, v_calc2.markup_pct, v_calc2.threshold_outcome;
  end if;

  select * into v_calc1 from app.margin_calculations where id = v_calc1.id;
  if v_calc1.is_current or v_calc1.superseded_by_id <> v_calc2.id then
    raise exception 'assertion failed: expected the first calculation to be superseded by the second (is_current=false, superseded_by_id=%), got is_current=% superseded_by_id=%', v_calc2.id, v_calc1.is_current, v_calc1.superseded_by_id;
  end if;
end;
$$;

\echo '>> override_margin_threshold: COM:Approve-gated, mandatory reason, only valid against an un-overridden requires_approval result'
do $$
declare
  v_calc1_id uuid;
  v_calc1_version integer;
  v_calc2_id uuid;
  v_calc2_version integer;
  v_calc app.margin_calculations;
begin
  -- v_calc1 (the requires_approval result) was already touched once by the recalculation
  -- in the prior scenario group (its is_current flag flipped to false), bumping
  -- record_version to 2 -- fetched fresh here rather than assumed to still be 1.
  select id, record_version into v_calc1_id, v_calc1_version from app.margin_calculations where margin_pct = 16.67;
  select id, record_version into v_calc2_id, v_calc2_version from app.margin_calculations where margin_pct = 33.33;

  begin
    perform app.override_margin_threshold(v_calc1_id, v_calc1_version, '', '00000000-0000-0000-0000-000000009102', 'tester');
    raise exception 'assertion failed: expected not_null_violation -- overriding requires a non-empty reason';
  exception
    when not_null_violation then
      null; -- expected
  end;

  begin
    perform app.override_margin_threshold(v_calc1_id, v_calc1_version, 'Strategic account, approved by sales director', '00000000-0000-0000-0000-000000009103', 'tester');
    raise exception 'assertion failed: expected insufficient_privilege -- the rep lacks COM:Approve';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_calc from app.override_margin_threshold(v_calc1_id, v_calc1_version, 'Strategic account, approved by sales director', '00000000-0000-0000-0000-000000009102', 'tester');
  if not v_calc.is_overridden or v_calc.override_reason <> 'Strategic account, approved by sales director' then
    raise exception 'assertion failed: expected is_overridden=true with the reason set, got overridden=% reason=%', v_calc.is_overridden, v_calc.override_reason;
  end if;

  begin
    perform app.override_margin_threshold(v_calc1_id, v_calc.record_version, 'Second attempt', '00000000-0000-0000-0000-000000009102', 'tester');
    raise exception 'assertion failed: expected check_violation -- an already-overridden calculation cannot be overridden again';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;

  begin
    perform app.override_margin_threshold(v_calc2_id, v_calc2_version, 'Should not apply to a passing result', '00000000-0000-0000-0000-000000009102', 'tester');
    raise exception 'assertion failed: expected check_violation -- a passing (not requires_approval) calculation cannot be overridden';
  exception
    when sqlstate '23514' then
      null; -- expected
  end;
end;
$$;

\echo '>> app.margin_calculations_directory: cost/margin/markup masked without COM:View cost, sell/discount masked without COM:View selling price, base-table columns withheld from direct select, sibling-team outsider denied via record-scope'
do $$
declare
  v_calc_id uuid;
  v_cost_masked boolean;
  v_sell_masked boolean;
  v_margin_pct numeric;
  v_sell_amount numeric;
  v_count integer;
begin
  select id into v_calc_id from app.margin_calculations where margin_pct = 33.33;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009102", "role": "authenticated"}';
  select cost_masked, sell_masked, margin_pct, sell_amount into v_cost_masked, v_sell_masked, v_margin_pct, v_sell_amount from app.margin_calculations_directory where id = v_calc_id;
  if not v_cost_masked or v_sell_masked or v_margin_pct is not null or v_sell_amount <> 15000000 then
    raise exception 'assertion failed: expected the manager (no View cost, holds View selling price) to see cost_masked=true sell_masked=false margin_pct=null sell_amount=15000000, got cost_masked=% sell_masked=% margin_pct=% sell_amount=%', v_cost_masked, v_sell_masked, v_margin_pct, v_sell_amount;
  end if;

  begin
    perform cost_amount from app.margin_calculations where id = v_calc_id;
    raise exception 'assertion failed: expected a real Postgres permission-denied error selecting cost_amount directly from app.margin_calculations';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009103", "role": "authenticated"}';
  select cost_masked, sell_masked, margin_pct into v_cost_masked, v_sell_masked, v_margin_pct from app.margin_calculations_directory where id = v_calc_id;
  if v_cost_masked or v_sell_masked or v_margin_pct <> 33.33 then
    raise exception 'assertion failed: expected the rep (holds both) to see cost_masked=false sell_masked=false margin_pct=33.33, got cost_masked=% sell_masked=% margin_pct=%', v_cost_masked, v_sell_masked, v_margin_pct;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009104", "role": "authenticated"}';
  select count(*) into v_count from app.margin_calculations_directory where id = v_calc_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to be denied via record-scope, found % row(s)', v_count;
  end if;
  reset role;
end;
$$;

\echo '>> audit trail: create/publish/calculate/override all recorded real app.audit_logs events (tenant-scoped counts, applying the COM-145/148/149 cross-file-fragility lesson from the start)'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmemargin');

  select count(*) into v_count from app.audit_logs where resource_type = 'app.margin_rule_versions' and action = 'create_margin_rule_version' and tenant_id = v_tenant1;
  if v_count <> 3 then raise exception 'assertion failed: expected exactly 3 create_margin_rule_version audit events for acmemargin, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.margin_rule_versions' and action = 'publish_margin_rule_version' and tenant_id = v_tenant1;
  if v_count <> 3 then raise exception 'assertion failed: expected exactly 3 publish_margin_rule_version audit events for acmemargin (one denied-by-privilege attempt and one denied-by-unique-constraint attempt inserted nothing), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.margin_calculations' and action = 'calculate_margin' and tenant_id = v_tenant1;
  if v_count <> 2 then raise exception 'assertion failed: expected exactly 2 calculate_margin audit events for acmemargin, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.margin_calculations' and action = 'override_margin_threshold' and tenant_id = v_tenant1;
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 override_margin_threshold audit event for acmemargin, found %', v_count; end if;
end;
$$;
