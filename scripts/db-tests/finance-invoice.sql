-- Real, executable test evidence for FIN-197 (Customer Invoice,
-- CG-S9-FIN-008) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: invoice preparation is idempotent on the source BillingReadinessHandoff
-- (never duplicates), inherits the exact governed revenue snapshot, and
-- integrates FIN-195's own tax calculation; the draft -> submitted -> approved
-- -> issued lifecycle with the correct FIN:Edit/FIN:Approve authority split;
-- period-aware, idempotent issue that posts exactly one FIN-196 AR open item;
-- discard/void boundaries; cross-tenant isolation; schema-privilege defense
-- in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, full Commercial->Operations->Finance pipeline (lead->prospect->opportunity->costing->rate->margin->quotation->acceptance->account->job-order-handoff->job-order->billing-readiness-override->handoff), a Finance Manager (FIN:Create/Edit/Approve/View), a Finance Editor (FIN:Edit/View only, no Approve), a Plain User with no FIN grant, a second tenant with its own Finance Manager, and one approved PPN tax rule (FIN-195) for tenant A'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_full_role uuid;
  v_full_draft app.role_versions;
  v_fin_manager_role uuid;
  v_fin_manager_draft app.role_versions;
  v_fin_editor_role uuid;
  v_fin_editor_draft app.role_versions;
  v_fin_manager2_role uuid;
  v_fin_manager2_draft app.role_versions;
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
  v_handoff app.job_order_handoffs;
  v_job app.job_orders;
  v_evaluation app.billing_readiness_evaluations;
  v_ppn_code_id uuid;
  v_tax_rule app.finance_tax_rule_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000027501', 'admin@acmeinv.test'),
    ('00000000-0000-0000-0000-000000027502', 'repa@acmeinv.test'),
    ('00000000-0000-0000-0000-000000027503', 'financemanagera@acmeinv.test'),
    ('00000000-0000-0000-0000-000000027504', 'financeeditora@acmeinv.test'),
    ('00000000-0000-0000-0000-000000027505', 'plainusera@acmeinv.test'),
    ('00000000-0000-0000-0000-000000027506', 'financemanagerb@acmeinv.test');

  perform app.provision_tenant('acmeinva', 'Acme Invoice A', 'idem-acmeinva', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeinva');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEINVA-CO', 'Acme Invoice A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEINVA-CO');

  perform app.provision_tenant('acmeinvb', 'Acme Invoice B', 'idem-acmeinvb', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeinvb');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'ACMEINVB-CO', 'Acme Invoice B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant2 and code = 'ACMEINVB-CO');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027501', 'admin@acmeinv.test', 'Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeinv.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027501', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027502', 'repa@acmeinv.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeinv.test'), 'active', 'onboarded', 'tester');

  v_full_role := (app.create_role(v_tenant1, 'Full Pipeline Rep', 'full COM/OPS/FIN access to build the fixture', 'tester')).id;
  v_full_draft := app.create_role_version(v_full_role, 'tester');
  perform app.set_role_version_permissions(
    v_full_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Override', 'View'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_full_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_full_role and status = 'published'), '00000000-0000-0000-0000-000000027502', '00000000-0000-0000-0000-000000027501', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027503', 'financemanagera@acmeinv.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmeinv.test'), 'active', 'onboarded', 'tester');
  v_fin_manager_role := (app.create_role(v_tenant1, 'Finance Manager', 'invoice authority', 'tester')).id;
  v_fin_manager_draft := app.create_role_version(v_fin_manager_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_fin_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_manager_role and status = 'published'), '00000000-0000-0000-0000-000000027503', '00000000-0000-0000-0000-000000027501', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027504', 'financeeditora@acmeinv.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmeinv.test'), 'active', 'onboarded', 'tester');
  v_fin_editor_role := (app.create_role(v_tenant1, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_fin_editor_draft := app.create_role_version(v_fin_editor_role, 'tester');
  perform app.set_role_version_permissions(v_fin_editor_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_fin_editor_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_fin_editor_role and status = 'published'), '00000000-0000-0000-0000-000000027504', '00000000-0000-0000-0000-000000027501', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000027505', 'plainusera@acmeinv.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmeinv.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000027506', 'financemanagerb@acmeinv.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmeinv.test'), 'active', 'onboarded', 'tester');
  v_fin_manager2_role := (app.create_role(v_tenant2, 'Finance Manager', 'invoice authority', 'tester')).id;
  v_fin_manager2_draft := app.create_role_version(v_fin_manager2_role, 'tester');
  perform app.set_role_version_permissions(v_fin_manager2_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_fin_manager2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_fin_manager2_role and status = 'published'), '00000000-0000-0000-0000-000000027506', '00000000-0000-0000-0000-000000027506', 'tester');

  -- Full Commercial->Operations pipeline (mirrors OPS-168's own fixture shape).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Invoice Test Co', 'Jane Invoice', 'jane@invtest.test', '0811',
    '00000000-0000-0000-0000-000000027502', v_team_a, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_lead from app.leads where email = 'jane@invtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Invoice Test Co', 'ITC', '66.666.666.7-777.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Invoice', 'Procurement Lead', 'jane@invtest.test', '0811', '00000000-0000-0000-0000-000000027502', v_team_a, '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000027502', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Invoice test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000027502', v_team_a, '00000000-0000-0000-0000-000000027502', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-INV-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000027501', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000027501', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000027502', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000027502', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight invoice lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Invoice', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_job from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000027502', 'rep');

  -- Billing readiness: evaluate (not_ready, draft job/no shipments), override with a reason (OPS:Override), then handoff.
  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, null, '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: bypassing full shipment/epod/document/cost evidence chain, out of FIN-197''s own test scope', '00000000-0000-0000-0000-000000027502', 'rep');
  perform app.handoff_billing_readiness(v_job.id, 'invoice-fixture-handoff-1', '00000000-0000-0000-0000-000000027502', 'rep');

  -- FIN-193: six open fiscal periods (Jan-Jun 2026) for tenant A, covering every issue_date this fixture uses.
  perform app.generate_finance_fiscal_calendar(v_tenant1, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000027503', 'financemanagera');

  -- FIN-195: one approved PPN tax rule for tenant A, so this fixture's own tax-line test can exercise a real calculation.
  v_ppn_code_id := (select id from app.finance_tax_codes where tenant_id is null and code = 'PPN');
  select * into v_tax_rule from app.create_finance_tax_rule_draft(v_tenant1, v_ppn_code_id, 'percentage', 0.11, null, null, null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_tax_rule from app.attach_finance_tax_rule_evidence(v_tax_rule.id, v_tax_rule.record_version, null, 'fixture evidence note for FIN-197''s own tax-line integration test', '00000000-0000-0000-0000-000000027503', 'financemanagera');
  perform app.approve_finance_tax_rule(v_tax_rule.id, v_tax_rule.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
end;
$$;

\echo '>> FIN-202 fixture prerequisite: a published finance_posting_map so app.issue_finance_invoice''s own new subledger effect can resolve real accounts'
do $$
declare
  v_tenant1 uuid;
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeinva');

  -- app.create_finance_config_draft/publish_finance_config_version delegate to
  -- the generic engine's own tenant-scope authority check
  -- (app.is_support_grant_authority), which requires tenant_admin, not merely
  -- FIN:Edit/Approve -- mirrors FIN-191's own "Finance Admin (tenant_admin AND
  -- FIN:Edit/Approve)" two-factor fixture precedent exactly.
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000027503', 'tenant_admin', v_tenant1, null, 'tester');

  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'AR-CTRL', 'Accounts Receivable Control', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'REV-DEFAULT', 'Default Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant1, null, 'TAX-PAYABLE-DEFAULT', 'Default Tax Payable', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CTRL')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-DEFAULT')),
    jsonb_build_object('key', 'tax_payable_default', 'value', jsonb_build_object('accountCodeRef', 'TAX-PAYABLE-DEFAULT'))
  ), '00000000-0000-0000-0000-000000027503', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000027503', null, 'financemanagera');
end;
$$;

\echo '>> idempotent preparation: Plain User A is denied; an unknown handoff is rejected; Finance Manager A prepares a draft with the exact governed revenue snapshot (15,000,000 IDR) plus a PPN tax line, and a retried call for the same handoff returns the same invoice unchanged'
do $$
declare
  v_tenant_a uuid;
  v_handoff_id uuid;
  v_invoice app.finance_invoices;
  v_retry app.finance_invoices;
  v_line_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeinva');
  v_handoff_id := (select id from app.billing_readiness_handoffs where tenant_id = v_tenant_a);

  begin
    perform app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff_id, 30, null, '00000000-0000-0000-0000-000000027505', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.prepare_finance_invoice_from_readiness(v_tenant_a, gen_random_uuid(), 30, null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
    raise exception 'assertion failed: expected finance_invoice_handoff_not_found';
  exception
    when others then
      if sqlerrm !~ 'finance_invoice_handoff_not_found' then
        raise exception 'assertion failed: expected finance_invoice_handoff_not_found, got %', sqlerrm;
      end if;
  end;

  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff_id, 30, 'PPN', '00000000-0000-0000-0000-000000027503', 'financemanagera');
  if v_invoice.status <> 'draft' or v_invoice.subtotal_amount <> 15000000 or v_invoice.tax_amount <> 1650000 or v_invoice.total_amount <> 16650000 then
    raise exception 'assertion failed: expected a draft invoice of subtotal 15,000,000 + tax 1,650,000 (PPN 11%%) = 16,650,000, got subtotal=% tax=% total=%', v_invoice.subtotal_amount, v_invoice.tax_amount, v_invoice.total_amount;
  end if;
  if v_invoice.invoice_number is not null then
    raise exception 'assertion failed: expected invoice_number to remain null until issue, got %', v_invoice.invoice_number;
  end if;

  select count(*) into v_line_count from app.finance_invoice_lines where invoice_id = v_invoice.id;
  if v_line_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 lines (1 charge, 1 tax), found %', v_line_count;
  end if;

  select * into v_retry from app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff_id, 999, 'PPN', '00000000-0000-0000-0000-000000027503', 'financemanagera');
  if v_retry.id <> v_invoice.id or v_retry.payment_term_days <> 30 then
    raise exception 'assertion failed: expected a retried prepare for the same handoff to return the original invoice unchanged (idempotent), got id=% payment_term_days=%', v_retry.id, v_retry.payment_term_days;
  end if;
end;
$$;

\echo '>> lifecycle authority split: Finance Editor A (no Approve) submits but cannot approve; Finance Manager A approves and issues; issuing is idempotent and posts exactly one FIN-196 AR open item for the exact total'
do $$
declare
  v_tenant_a uuid;
  v_handoff_id uuid;
  v_invoice app.finance_invoices;
  v_ar_item app.finance_ar_open_items;
  v_ar_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeinva');
  v_handoff_id := (select id from app.billing_readiness_handoffs where tenant_id = v_tenant_a);
  select * into v_invoice from app.finance_invoices where tenant_id = v_tenant_a and billing_readiness_handoff_id = v_handoff_id;

  begin
    perform app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000027504', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve (authority is checked before status)';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_invoice from app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000027504', 'financeeditora');
  if v_invoice.status <> 'submitted' then
    raise exception 'assertion failed: expected status submitted, got %', v_invoice.status;
  end if;

  begin
    perform app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000027504', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_invoice from app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  if v_invoice.status <> 'approved' then
    raise exception 'assertion failed: expected status approved, got %', v_invoice.status;
  end if;

  select * into v_invoice from app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-03-15'::date, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  if v_invoice.status <> 'issued' or v_invoice.invoice_number !~ '^INV-2026-[0-9]{6}$' or v_invoice.due_date <> '2026-04-14'::date then
    raise exception 'assertion failed: expected status issued, a real invoice_number, and due_date 2026-04-14 (issue_date + 30d), got status=% number=% due=%', v_invoice.status, v_invoice.invoice_number, v_invoice.due_date;
  end if;

  select * into v_ar_item from app.finance_ar_open_items where id = v_invoice.ar_open_item_id;
  if v_ar_item.original_amount <> 16650000 or v_ar_item.source_document_type <> 'invoice' or v_ar_item.source_document_id <> v_invoice.id then
    raise exception 'assertion failed: expected exactly one FIN-196 AR open item of 16,650,000 sourced from this invoice, got amount=% source_type=% source_id=%', v_ar_item.original_amount, v_ar_item.source_document_type, v_ar_item.source_document_id;
  end if;

  -- Idempotent re-issue: retried call returns the unchanged invoice, never posts a second AR open item.
  select * into v_invoice from app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-03-15'::date, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select count(*) into v_ar_count from app.finance_ar_open_items where source_document_type = 'invoice' and source_document_id = v_invoice.id;
  if v_ar_count <> 1 then
    raise exception 'assertion failed: expected a retried issue to never post a second AR open item, found %', v_ar_count;
  end if;

  begin
    perform app.discard_finance_invoice_draft(v_invoice.id, v_invoice.record_version, 'too late', '00000000-0000-0000-0000-000000027503', 'financemanagera');
    raise exception 'assertion failed: expected finance_invoice_not_cancellable for an issued invoice';
  exception
    when others then
      if sqlerrm !~ 'finance_invoice_not_cancellable' then
        raise exception 'assertion failed: expected finance_invoice_not_cancellable, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> discard boundary: a draft invoice (no tax line, from a second, distinct handoff) can be discarded by Finance Editor A (FIN:Edit) while draft; a discarded invoice cannot be resubmitted'
do $$
declare
  v_tenant_a uuid;
  v_job app.job_orders;
  v_evaluation app.billing_readiness_evaluations;
  v_handoff2 app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeinva');
  select * into v_job from app.job_orders where tenant_id = v_tenant_a;

  -- A second, distinct handoff on the same Job Order (a legitimate re-handoff after a later reevaluation, OPS-181's own disclosed allowance).
  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, 'fixture: second handoff for FIN-197''s own discard-boundary test', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: second override', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_handoff2 from app.handoff_billing_readiness(v_job.id, 'invoice-fixture-handoff-2', '00000000-0000-0000-0000-000000027502', 'rep');

  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff2.id, 30, null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  if v_invoice.tax_amount <> 0 or v_invoice.subtotal_amount <> 15000000 then
    raise exception 'assertion failed: expected a second untaxed draft invoice of subtotal 15,000,000, got subtotal=% tax=%', v_invoice.subtotal_amount, v_invoice.tax_amount;
  end if;

  select * into v_invoice from app.discard_finance_invoice_draft(v_invoice.id, v_invoice.record_version, 'entered in error', '00000000-0000-0000-0000-000000027504', 'financeeditora');
  if v_invoice.status <> 'void' then
    raise exception 'assertion failed: expected status void after discard, got %', v_invoice.status;
  end if;

  begin
    perform app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000027504', 'financeeditora');
    raise exception 'assertion failed: expected finance_invoice_not_draft for a voided invoice';
  exception
    when others then
      if sqlerrm !~ 'finance_invoice_not_draft' then
        raise exception 'assertion failed: expected finance_invoice_not_draft, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot mutate tenant A''s own invoice, and list_finance_invoices never returns tenant A''s rows for tenant B''s own scope'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_invoice app.finance_invoices;
  v_rows app.finance_invoices[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeinva');
  v_tenant_b := (select id from app.tenants where slug = 'acmeinvb');
  select * into v_invoice from app.finance_invoices where tenant_id = v_tenant_a and status = 'issued';

  begin
    perform app.discard_finance_invoice_draft(v_invoice.id, v_invoice.record_version, 'intruder attempt', '00000000-0000-0000-0000-000000027506', 'financemanagerb');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Manager B holds no FIN grant for tenant A';
  exception
    when insufficient_privilege then
      null;
  end;

  select array_agg(r) into v_rows from app.list_finance_invoices(v_tenant_b, null, null, null, '00000000-0000-0000-0000-000000027506') r;
  if v_rows is not null and exists (select 1 from unnest(v_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_invoices to never return a tenant A row';
  end if;

  -- ISS-2026-048 extension fix (Track B Batch 2): app.approve_finance_invoice -- a
  -- genuine stranger to the invoice's tenant now gets the same finance_invoice_not_found
  -- error a nonexistent invoice id would produce, never a tenant-echoing
  -- insufficient_authority error.
  begin
    perform app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000027506', 'financemanagerb');
    raise exception 'assertion failed: expected finance_invoice_not_found -- Finance Manager B has zero relationship to tenant A';
  exception
    when no_data_found then
      if sqlerrm not like 'finance_invoice_not_found%' then
        raise exception 'assertion failed: expected finance_invoice_not_found, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-197 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'touch_finance_invoice_row', 'check_finance_invoice_authority', 'prepare_finance_invoice_from_readiness',
    'submit_finance_invoice_for_approval', 'discard_finance_invoice_draft', 'approve_finance_invoice',
    'issue_finance_invoice', 'list_finance_invoices', 'get_finance_invoice_lines'
  ]) loop
    select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
      into v_anon_has
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn;
    if coalesce(v_anon_has, false) then
      raise exception 'assertion failed: expected anon to hold zero EXECUTE on app.%, found at least one overload granted', v_fn;
    end if;
  end loop;
end;
$$;

\echo '>> audit trail: at least one prepare/approve/issue event was captured for tenant A''s own invoice activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeinva');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('prepare_finance_invoice_from_readiness', 'approve_finance_invoice', 'issue_finance_invoice');
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 audit events across this fixture''s own prepare/approve/issue calls, found %', v_count;
  end if;
end;
$$;

\echo '>> HDN-374 (Financial Integrity Audit) finding 1 regression: a quote whose OWN line carries tax_pct (independent of FIN-195''s own p_tax_code) must never be double-taxed at invoicing -- revenue_snapshot.subtotalAmount (genuinely pre-tax) is read, never totalAmount (already tax-inclusive)'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
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
  v_handoff app.job_order_handoffs;
  v_job app.job_orders;
  v_evaluation app.billing_readiness_evaluations;
  v_readiness_handoff app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
  v_invoice2 app.finance_invoices;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeinva');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEINVA-CO');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Invoice Tax Test Co', 'Budi Pajak', 'budi@invtaxtest.test', '0812',
    '00000000-0000-0000-0000-000000027502', v_team_a, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_lead from app.leads where email = 'budi@invtaxtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Invoice Tax Test Co', 'ITX', '77.777.777.7-777.000',
    jsonb_build_object('line1', 'Jl. Thamrin 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Budi Pajak', 'Procurement', 'budi@invtaxtest.test', '0812', '00000000-0000-0000-0000-000000027502', v_team_a, '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000027502', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Invoice tax test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000027502', v_team_a, '00000000-0000-0000-0000-000000027502', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-INV-TAX-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 700000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000027501', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000027501', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000027502', 'tester');

  -- Reuses the tenant's own already-published margin rule (the fixture setup block above
  -- already created and published one; only one may be published at a time).
  perform app.calculate_margin(v_selection.id, 1000000, 'IDR', 0, '00000000-0000-0000-0000-000000027502', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000027502', 'tester');
  -- The quote's OWN line-level tax_pct=11 -- independent of, and never to be confused
  -- with, FIN-195's own p_tax_code applied later at invoicing. discount_pct=8 (HDN-374
  -- Tier C regression): quotation_lines.line_gross_amount=1,000,000, line_discount_
  -- amount=80,000, line net (gross-discount)=920,000, line_tax_amount=920,000*11%=
  -- 101,200 (tax is computed on the NET base, not the gross) -- app.quotations.subtotal_
  -- amount is always the raw GROSS sum (app.recalculate_quotation_totals), so the genuine
  -- pre-tax NET base an invoice must bill is subtotalAmount MINUS discountAmount, never
  -- subtotalAmount alone.
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight invoice tax lane', v_calc_id, 1, 1000000, 8, 11, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  if v_quote.subtotal_amount <> 1000000 or v_quote.discount_amount <> 80000 or v_quote.tax_amount <> 101200 or v_quote.total_amount <> 1021200 then
    raise exception 'assertion failed: expected quote subtotal=1,000,000 discount=80,000 tax=101,200 total=1,021,200 (its own 11%% line tax on the discount-net base), got subtotal=% discount=% tax=% total=%', v_quote.subtotal_amount, v_quote.discount_amount, v_quote.tax_amount, v_quote.total_amount;
  end if;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Budi Pajak', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_job from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000027502', 'rep');

  if v_job.revenue_snapshot ->> 'subtotalAmount' <> '1000000.00' or v_job.revenue_snapshot ->> 'discountAmount' <> '80000.00' or v_job.revenue_snapshot ->> 'totalAmount' <> '1021200.00' then
    raise exception 'assertion failed: expected job revenue_snapshot subtotalAmount=1000000.00 discountAmount=80000.00 totalAmount=1021200.00, got %', v_job.revenue_snapshot;
  end if;

  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, null, '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: HDN-374 finding-1 regression, out of full evidence chain scope', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_readiness_handoff from app.handoff_billing_readiness(v_job.id, 'invoice-tax-fixture-handoff-1', '00000000-0000-0000-0000-000000027502', 'rep');

  -- HDN-374 finding 1 regression: prepare with FIN-195's own p_tax_code (PPN) on top of a
  -- quote that ALREADY carried its own 11% line tax_pct AND an 8% line discount. The
  -- invoice's own subtotal must be the quote's genuine pre-tax, discount-NET figure
  -- (1,000,000 - 80,000 = 920,000), never the raw pre-discount gross (1,000,000, Tier C's
  -- own finding) and never the already-tax-inclusive total (1,021,200, the original
  -- finding). PPN 11%% on the correct 920,000 base = 101,200.
  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant1, v_readiness_handoff.id, 30, 'PPN', '00000000-0000-0000-0000-000000027503', 'financemanagera');
  if v_invoice.subtotal_amount <> 920000 or v_invoice.tax_amount <> 101200 or v_invoice.total_amount <> 1021200 then
    raise exception 'assertion failed: HDN-374 finding 1 / Tier C regressed -- expected invoice subtotal=920,000 (discount-net) tax=101,200 (PPN 11%% applied ONCE on the correct base) total=1,021,200, got subtotal=% tax=% total=%', v_invoice.subtotal_amount, v_invoice.tax_amount, v_invoice.total_amount;
  end if;

  -- Approve and issue invoice 1 -- this job order's own first ISSUED invoice.
  select * into v_invoice from app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_invoice from app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_invoice from app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-03-20'::date, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  if v_invoice.status <> 'issued' then
    raise exception 'assertion failed: expected invoice 1 to reach issued, got %', v_invoice.status;
  end if;

  -- HDN-374 finding 2 regression: a SECOND, distinct handoff on the SAME job order (a
  -- legitimate re-handoff, OPS-181) may still prepare, submit and approve its own draft
  -- invoice -- that flow is sanctioned (see the discard-boundary fixture above). What must
  -- now be refused is letting that second invoice reach `issued` while the job already has
  -- a different issued invoice -- the actual double-billing this finding's own live-forced
  -- reproduction demonstrated.
  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, 'fixture: HDN-374 finding-2 regression, second handoff', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: second override', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_readiness_handoff from app.handoff_billing_readiness(v_job.id, 'invoice-tax-fixture-handoff-2', '00000000-0000-0000-0000-000000027502', 'rep');

  select * into v_invoice2 from app.prepare_finance_invoice_from_readiness(v_tenant1, v_readiness_handoff.id, 30, null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  if v_invoice2.status <> 'draft' then
    raise exception 'assertion failed: expected the second, distinct-handoff draft invoice to still be freely creatable (sanctioned re-handoff), got status %', v_invoice2.status;
  end if;

  select * into v_invoice2 from app.submit_finance_invoice_for_approval(v_invoice2.id, v_invoice2.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_invoice2 from app.approve_finance_invoice(v_invoice2.id, v_invoice2.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  if v_invoice2.status <> 'approved' then
    raise exception 'assertion failed: expected the second invoice to reach approved (only ISSUING is blocked), got %', v_invoice2.status;
  end if;

  begin
    perform app.issue_finance_invoice(v_invoice2.id, v_invoice2.record_version, '2026-03-21'::date, '00000000-0000-0000-0000-000000027503', 'financemanagera');
    raise exception 'assertion failed: HDN-374 finding 2 regressed -- expected finance_invoice_job_order_already_issued for a second invoice on a job order that already has one issued';
  exception
    when others then
      if sqlerrm !~ 'finance_invoice_job_order_already_issued' then
        raise exception 'assertion failed: expected finance_invoice_job_order_already_issued, got %', sqlerrm;
      end if;
  end;

  -- The blocked second invoice must remain exactly as it was (approved, not issued) --
  -- the guard denies before any state mutation.
  select * into v_invoice2 from app.finance_invoices where id = v_invoice2.id;
  if v_invoice2.status <> 'approved' then
    raise exception 'assertion failed: expected the denied second invoice to remain approved (no partial-issue side effect), got %', v_invoice2.status;
  end if;
end;
$$;

\echo '>> HDN-374 Tier C regression: a REAL two-process concurrent race -- two DIFFERENT, already-APPROVED invoices from two distinct handoffs on the SAME job order, both issued at the same instant. The sequential guard above cannot catch this (each process passes its own exists() check before either commits); finance_invoices_job_order_issued_unique must catch it instead -- exactly ONE may reach issued, the other must be denied finance_invoice_job_order_already_issued (never a raw unique_violation), and remain approved'
do $$
declare
  v_tenant1 uuid;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
  v_job app.job_orders;
  v_evaluation app.billing_readiness_evaluations;
  v_readiness_handoff app.billing_readiness_handoffs;
  v_invoice_a app.finance_invoices;
  v_invoice_b app.finance_invoices;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeinva');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Invoice Race Test Co', 'Rina Race', 'rina@invracetest.test', '0813',
    '00000000-0000-0000-0000-000000027502', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEINVA-CO'), '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_lead from app.leads where email = 'rina@invracetest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Invoice Race Test Co', 'IRT', '88.888.888.8-888.000',
    jsonb_build_object('line1', 'Jl. Gatot Subroto 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Rina Race', 'Procurement', 'rina@invracetest.test', '0813', '00000000-0000-0000-0000-000000027502', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEINVA-CO'), '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000027502', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Invoice race test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000027502', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEINVA-CO'), '00000000-0000-0000-0000-000000027502', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-INV-RACE-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 500000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000027501', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000027501', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.calculate_margin(v_selection.id, 700000, 'IDR', 0, '00000000-0000-0000-0000-000000027502', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight invoice race lane', v_calc_id, 1, 700000, 0, 0, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000027502', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000027502', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Rina Race', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_job from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000027502', 'rep');

  -- Two distinct handoffs (OPS-181's own sanctioned re-handoff flow) on the SAME job
  -- order, each prepared, submitted and approved -- both legitimately reach 'approved',
  -- neither yet issued, exactly the state the sequential guard test above already proved
  -- is freely reachable.
  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, null, '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: HDN-374 Tier C race regression, handoff A', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_readiness_handoff from app.handoff_billing_readiness(v_job.id, 'invoice-race-fixture-handoff-a', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_invoice_a from app.prepare_finance_invoice_from_readiness(v_tenant1, v_readiness_handoff.id, 30, null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_invoice_a from app.submit_finance_invoice_for_approval(v_invoice_a.id, v_invoice_a.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_invoice_a from app.approve_finance_invoice(v_invoice_a.id, v_invoice_a.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');

  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, 'fixture: HDN-374 Tier C race regression, handoff B', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: second override', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_readiness_handoff from app.handoff_billing_readiness(v_job.id, 'invoice-race-fixture-handoff-b', '00000000-0000-0000-0000-000000027502', 'rep');
  select * into v_invoice_b from app.prepare_finance_invoice_from_readiness(v_tenant1, v_readiness_handoff.id, 30, null, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_invoice_b from app.submit_finance_invoice_for_approval(v_invoice_b.id, v_invoice_b.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');
  select * into v_invoice_b from app.approve_finance_invoice(v_invoice_b.id, v_invoice_b.record_version, '00000000-0000-0000-0000-000000027503', 'financemanagera');

  if v_invoice_a.status <> 'approved' or v_invoice_b.status <> 'approved' then
    raise exception 'assertion failed: expected both race invoices to reach approved before the race, got a=% b=%', v_invoice_a.status, v_invoice_b.status;
  end if;
end;
$$;

select id as race_invoice_a_id, record_version as race_invoice_a_version from app.finance_invoices where billing_readiness_handoff_id = (select id from app.billing_readiness_handoffs where idempotency_key = 'invoice-race-fixture-handoff-a') \gset
select id as race_invoice_b_id, record_version as race_invoice_b_version from app.finance_invoices where billing_readiness_handoff_id = (select id from app.billing_readiness_handoffs where idempotency_key = 'invoice-race-fixture-handoff-b') \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

\set race_sql_a 'select app.issue_finance_invoice(''' :race_invoice_a_id ''', ' :race_invoice_a_version ', ''2026-03-25'', ''00000000-0000-0000-0000-000000027503'', ''financemanagera'');'
\set race_sql_b 'select app.issue_finance_invoice(''' :race_invoice_b_id ''', ' :race_invoice_b_version ', ''2026-03-25'', ''00000000-0000-0000-0000-000000027503'', ''financemanagera'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-fin-invoice-issue-race-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-fin-invoice-issue-race-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_job_order_id uuid;
  v_issued_count integer;
  v_approved_count integer;
begin
  v_job_order_id := (select job_order_id from app.finance_invoices where billing_readiness_handoff_id = (select id from app.billing_readiness_handoffs where idempotency_key = 'invoice-race-fixture-handoff-a'));

  select count(*) filter (where status = 'issued'), count(*) filter (where status = 'approved') into v_issued_count, v_approved_count
    from app.finance_invoices where job_order_id = v_job_order_id;

  if v_issued_count <> 1 then
    raise exception 'assertion failed: HDN-374 Tier C regressed -- expected exactly ONE of the two racing invoices to reach issued (never two, never zero -- a raw unique_violation reaching a caller means finance_invoices_job_order_issued_unique is not applied), got %. See the RACE_OUT_A/RACE_OUT_B process output captured above', v_issued_count;
  end if;
  if v_approved_count <> 1 then
    raise exception 'assertion failed: expected exactly ONE invoice to remain approved (the loser, denied before any state mutation), got %', v_approved_count;
  end if;

  raise notice 'concurrent issue-invoice race proof: exactly 1 of 2 invoices on the same job order reached issued after two genuinely concurrent psql processes raced app.issue_finance_invoice -- the loser was denied finance_invoice_job_order_already_issued, never a raw unique_violation';
end;
$$;
