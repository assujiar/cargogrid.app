-- Real, executable regression evidence for OPS-186 (Operations Security and Financial
-- Hardening, CG-S8-OPS-020) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. One targeted root-cause test per finding fixed in
-- supabase/migrations/20260728190000_harden_operations_security_financial.sql.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM+OPS full incl Create/Override, team A), a sibling-team outsider (identical grants incl Create/Override, team B), a global Supreme Admin -- one accepted-quote handoff owned by the rep in team A'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_outsider_role uuid;
  v_outsider_draft app.role_versions;
  v_approver_role uuid;
  v_approver_draft app.role_versions;
  v_config_draft app.config_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_profile app.credit_profiles;
  v_step_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000024101', 'admin@acmeopshardening.test'),
    ('00000000-0000-0000-0000-000000024102', 'rep@acmeopshardening.test'),
    ('00000000-0000-0000-0000-000000024104', 'outsider@acmeopshardening.test'),
    ('00000000-0000-0000-0000-000000024105', 'approver@acmeopshardening.test'),
    ('00000000-0000-0000-0000-000000024106', 'supreme@acmeopshardening.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024106', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmeopshardening', 'Acme Ops Hardening Co', 'idem-acmeopshardening', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeopshardening');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEOPSHARDENING-CO', 'Acme Ops Hardening Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSHARDENING-CO'), 'ACMEOPSHARDENING-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSHARDENING-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSHARDENING-CO'), 'ACMEOPSHARDENING-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPSHARDENING-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000024101', 'admin@acmeopshardening.test', 'Hardening Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeopshardening.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024101', 'tenant_admin', v_tenant1, null, 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000024102', 'rep@acmeopshardening.test', 'Hardening Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeopshardening.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000024104', 'outsider@acmeopshardening.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeopshardening.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000024105', 'approver@acmeopshardening.test', 'Credit Approver', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'approver@acmeopshardening.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Hardening Rep', 'full commercial + ops grants incl Create/Override', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'View margin', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000024102', '00000000-0000-0000-0000-000000024101', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Hardening Outsider', 'sibling team, identical grants incl Create/Override', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View', 'View cost', 'View margin', 'Override'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000024104', '00000000-0000-0000-0000-000000024101', 'tester');

  v_approver_role := (app.create_role(v_tenant1, 'Hardening Credit Approver', 'decides the routed credit-profile approval request', 'tester')).id;
  v_approver_draft := app.create_role_version(v_approver_role, 'tester');
  perform app.set_role_version_permissions(v_approver_draft.id, array(select id from app.permissions where resource_module_code = 'COM' and action in ('Approve', 'View')), 'tester');
  perform app.publish_role_version(v_approver_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_approver_role and status = 'published'), '00000000-0000-0000-0000-000000024105', '00000000-0000-0000-0000-000000024101', 'tester');

  select * into v_config_draft from app.create_config_draft('approval', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000024101', 'tenant admin');
  perform app.set_config_items(v_config_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'pattern', 'value', 'sequential'),
    jsonb_build_object('key', 'steps', 'value', jsonb_build_array(
      jsonb_build_object('step_order', 1, 'approver_type', 'role', 'role_id', v_approver_role::text, 'required_approvals', 1)
    )),
    jsonb_build_object('key', 'allow_self_approval', 'value', false)
  ), '00000000-0000-0000-0000-000000024101', 'tenant admin');
  perform app.publish_approval_definition(v_config_draft.id, '00000000-0000-0000-0000-000000024101', null, 'tenant admin');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Hardening Test Co', 'Jane Hardening', 'jane@opshardeningtest.test', '0811',
    '00000000-0000-0000-0000-000000024102', v_team_a, '00000000-0000-0000-0000-000000024102', 'tester');
  select * into v_lead from app.leads where email = 'jane@opshardeningtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000024102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Hardening Test Co', 'HRD', '11.111.111.10-101.000',
    jsonb_build_object('line1', 'Jl. Sudirman 10', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000024102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Hardening Ops', 'Procurement Lead', 'jane@opshardeningtest.test', '0811', '00000000-0000-0000-0000-000000024102', v_team_a, '00000000-0000-0000-0000-000000024102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000024102', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Hardening test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Semarang', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000024102', v_team_a, '00000000-0000-0000-0000-000000024102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000024102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-HARDENING-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Semarang', '20ft',
    null, null, null, null, 'IDR', 8000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000024101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000024101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000024102', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000024102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000024102', 'tester');
  perform app.calculate_margin(v_selection.id, 12000000, 'IDR', 0, '00000000-0000-0000-0000-000000024102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000024102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight hardening lane', v_calc_id, 1, 12000000, 0, 0, '00000000-0000-0000-0000-000000024102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000024102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000024102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Hardening Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000024102', 'rep');

  v_profile := app.request_customer_credit_profile(v_tenant1, v_account.id, 'IDR', 20000000, '00000000-0000-0000-0000-000000024102', 'rep');
  select rs.id into v_step_id from app.approval_request_steps rs where rs.request_id = v_profile.approval_request_id and rs.step_order = 1;
  v_profile := app.decide_credit_profile_approval_step(v_step_id, 'approved', 'Approved for hardening fixture', now(), '00000000-0000-0000-0000-000000024105', 'approver');

  perform app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000024102', 'rep');
end $$;

\echo '>> Finding 1 fix: app.prepare_job_order is now record-scope-checked against the source handoff -- the sibling-team outsider (full grants incl OPS:Create, wrong record scope) is denied; the owning rep succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopshardening');
  v_handoff_id uuid := (select id from app.job_order_handoffs where tenant_id = v_tenant1);
  v_job_order app.job_orders;
begin
  begin
    perform app.prepare_job_order(v_handoff_id, '00000000-0000-0000-0000-000000024104', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider denied by record scope on app.prepare_job_order (OPS-186 Finding 1)';
  exception
    when insufficient_privilege then null;
  end;

  v_job_order := app.prepare_job_order(v_handoff_id, '00000000-0000-0000-0000-000000024102', 'rep');
  if v_job_order.source_handoff_id <> v_handoff_id then
    raise exception 'assertion failed: expected the owning rep to succeed and create a real Job Order';
  end if;
end $$;

\echo '>> Finding 2 fix: app.create_shipment_order_from_job is now record-scope-checked against the source Job Order -- the outsider is denied even after the Job Order is confirmed; the owning rep succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopshardening');
  v_job_order app.job_orders;
  v_shipment app.shipment_orders;
begin
  select jo.* into v_job_order from app.job_orders jo where jo.tenant_id = v_tenant1;
  v_job_order := app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000024102', 'rep');

  begin
    perform app.create_shipment_order_from_job(
      v_job_order.id, 'idem-hardening-outsider', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Semarang',
      now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000024104', 'outsider'
    );
    raise exception 'assertion failed: expected the sibling-team outsider denied by record scope on app.create_shipment_order_from_job (OPS-186 Finding 2)';
  exception
    when insufficient_privilege then null;
  end;

  select * into v_shipment from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-hardening-rep', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Semarang',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000024102', 'rep'
  );
  if v_shipment.job_order_id <> v_job_order.id then
    raise exception 'assertion failed: expected the owning rep to succeed and create a real Shipment Order';
  end if;
end $$;

\echo '>> Finding 3 fix: app.detect_transaction_lineage_anomalies is now record-scope-filtered -- after simulating data loss (deleting the auto-captured job_to_shipment edge), the owning rep sees the orphan anomaly, the sibling-team outsider (identical grants incl OPS:Override, wrong record scope) does not, and a Supreme Admin sees it regardless via the can_access_record bypass'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopshardening');
  v_shipment_id uuid := (select id from app.shipment_orders where tenant_id = v_tenant1 and idempotency_key = 'idem-hardening-rep');
  v_rep_count integer;
  v_outsider_count integer;
  v_supreme_count integer;
begin
  delete from app.transaction_lineage_edges where relation_type = 'job_to_shipment' and target_id = v_shipment_id;

  select count(*) into v_rep_count from app.detect_transaction_lineage_anomalies(v_tenant1, '00000000-0000-0000-0000-000000024102') a
  where a.anomaly_type = 'orphan_shipment_order' and a.target_id = v_shipment_id;
  if v_rep_count <> 1 then
    raise exception 'assertion failed: expected the owning rep to see exactly 1 orphan_shipment_order anomaly for their own shipment, got %', v_rep_count;
  end if;

  select count(*) into v_outsider_count from app.detect_transaction_lineage_anomalies(v_tenant1, '00000000-0000-0000-0000-000000024104') a
  where a.anomaly_type = 'orphan_shipment_order' and a.target_id = v_shipment_id;
  if v_outsider_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider (wrong record scope, despite holding OPS:Override) to see zero rows for this anomaly (OPS-186 Finding 3), got %', v_outsider_count;
  end if;

  select count(*) into v_supreme_count from app.detect_transaction_lineage_anomalies(v_tenant1, '00000000-0000-0000-0000-000000024106') a
  where a.anomaly_type = 'orphan_shipment_order' and a.target_id = v_shipment_id;
  if v_supreme_count <> 1 then
    raise exception 'assertion failed: expected Supreme Admin to see the anomaly regardless of record scope via the can_access_record bypass, got %', v_supreme_count;
  end if;

  perform app.backfill_transaction_lineage(v_tenant1, '00000000-0000-0000-0000-000000024102', 'rep');
end $$;

\echo '>> Finding 4 fix: app.job_profitability_snapshots.revenue_amount/cost_amount now reject a negative value at the database boundary -- margin_amount remains legitimately unconstrained (a real loss)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'acmeopshardening');
  v_job_order_id uuid := (select jo.id from app.job_orders jo where jo.tenant_id = v_tenant1);
begin
  begin
    insert into app.job_profitability_snapshots (tenant_id, job_order_id, status, revenue_amount, cost_amount, margin_amount, calculated_by_auth_user_id, is_current)
    values (v_tenant1, v_job_order_id, 'calculated', -1, 100, -101, '00000000-0000-0000-0000-000000024102', false);
    raise exception 'assertion failed: expected a check_violation for a negative revenue_amount (OPS-186 Finding 4)';
  exception
    when check_violation then null;
  end;

  begin
    insert into app.job_profitability_snapshots (tenant_id, job_order_id, status, revenue_amount, cost_amount, margin_amount, calculated_by_auth_user_id, is_current)
    values (v_tenant1, v_job_order_id, 'calculated', 100, -1, 101, '00000000-0000-0000-0000-000000024102', false);
    raise exception 'assertion failed: expected a check_violation for a negative cost_amount (OPS-186 Finding 4)';
  exception
    when check_violation then null;
  end;

  -- A genuine loss (cost exceeds revenue) still inserts cleanly -- margin_amount is
  -- correctly never constrained to >= 0.
  insert into app.job_profitability_snapshots (tenant_id, job_order_id, status, revenue_amount, cost_amount, margin_amount, calculated_by_auth_user_id, is_current)
  values (v_tenant1, v_job_order_id, 'calculated', 100, 150, -50, '00000000-0000-0000-0000-000000024102', false);
end $$;

\echo '>> regression: schema-privilege defense in depth -- anon still holds zero EXECUTE on the three hardened functions after CREATE OR REPLACE FUNCTION (grants are preserved across a function-body replacement, ERR-2026-004 regression guard)'
do $$
declare
  v_denied_count integer;
begin
  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in ('prepare_job_order', 'create_shipment_order_from_job', 'detect_transaction_lineage_anomalies');
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants on the 3 hardened functions post-replace, found %', v_denied_count;
  end if;
end $$;
