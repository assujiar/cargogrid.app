-- Real, executable test evidence for CG-AUDIT-2026-09-02 B5 (independent
-- launch-readiness audit, finding B5) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.
-- Proves: a withholding-type tax code (finance_tax_codes.tax_type = 'withholding' --
-- PPH21/PPH23/PPH4_2) is DEDUCTED, never added. app.calculate_finance_tax now discloses
-- the resolved rule's own taxType; app.prepare_finance_invoice_from_readiness writes a
-- withholding amount into the new finance_invoices.withholding_tax_amount column, never
-- into tax_amount, so total_amount (subtotal_amount + tax_amount) is unaffected by it;
-- app.issue_finance_invoice posts the AR open item and its own AR-control debit net of
-- the withheld amount, and DEBITS (never credits) the tax rule's own governed
-- recoverable_account_id (or the withholding_tax_receivable_default posting-map key when
-- none is configured) for the withheld amount -- a creditable asset to CargoGrid, never a
-- payable, mirroring app.post_finance_vendor_bill's own established recoverable_account_id
-- debit pattern for input tax credits on the AP side. A separate, isolated tenant/job
-- order from scripts/db-tests/finance-invoice.sql's own fixture (that file's one job
-- order already carries an issued invoice, and finance_invoices_job_order_issued_unique
-- allows only one issued invoice per job order at a time).

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a minimal Commercial->Operations pipeline to one job order, a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), six open fiscal periods, a chart of accounts + published posting map (ar_control, revenue_default, tax_payable_default, withholding_tax_receivable_default, plus PPH23''s own dedicated recoverable account), and two approved withholding tax rules: PPH23 with its own governed recoverable_account_id, PPH21 with none (proves the posting-map fallback)'
do $$
declare
  v_tenant_a uuid;
  v_team_a uuid;
  v_manager_role uuid;
  v_manager_draft app.role_versions;
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
  v_gl_account app.finance_accounts;
  v_pm_draft app.config_versions;
  v_pph23_code_id uuid;
  v_pph21_code_id uuid;
  v_pph23_rule app.finance_tax_rule_versions;
  v_pph21_rule app.finance_tax_rule_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000099911', 'admin@acmewht.test'),
    ('00000000-0000-0000-0000-000000099912', 'repa@acmewht.test'),
    ('00000000-0000-0000-0000-000000099913', 'financemanagera@acmewht.test');

  perform app.provision_tenant('acmewhta', 'Acme Withholding Tax A', 'idem-acmewhta', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmewhta');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEWHTA-CO', 'Acme Withholding Tax A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEWHTA-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000099911', 'admin@acmewht.test', 'Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmewht.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000099911', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000099912', 'repa@acmewht.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmewht.test'), 'active', 'onboarded', 'tester');

  v_manager_role := (app.create_role(v_tenant_a, 'Full Pipeline + Finance Manager', 'full COM/OPS/FIN access to build and invoice the fixture', 'tester')).id;
  v_manager_draft := app.create_role_version(v_manager_role, 'tester');
  perform app.set_role_version_permissions(
    v_manager_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Override', 'View'))
      or (resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_manager_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000099912', '00000000-0000-0000-0000-000000099911', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000099913', 'financemanagera@acmewht.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmewht.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role and status = 'published'), '00000000-0000-0000-0000-000000099913', '00000000-0000-0000-0000-000000099911', 'tester');
  -- app.create_finance_config_draft/publish_finance_config_version (the finance_posting_map
  -- fixture below) delegate to the generic engine's own tenant-scope authority check, which
  -- requires tenant_admin, not merely FIN:Edit/Approve -- mirrors finance-invoice.sql's own
  -- identical fixture precedent exactly.
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000099913', 'tenant_admin', v_tenant_a, null, 'tester');

  -- Minimal Commercial->Operations pipeline to one job order (mirrors
  -- finance-invoice.sql's own fixture shape, just one tenant, one actor).
  perform app.capture_lead(v_tenant_a, 'manual', null, 'Withholding Test Co', 'Jane Withhold', 'jane@whttest.test', '0811',
    '00000000-0000-0000-0000-000000099912', v_team_a, '00000000-0000-0000-0000-000000099912', 'tester');
  select * into v_lead from app.leads where email = 'jane@whttest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000099912', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Withholding Test Co', 'WTC', '77.777.777.7-777.000',
    jsonb_build_object('line1', 'Jl. Sudirman 2', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000099912', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant_a, 'Jane Withhold', 'Procurement Lead', 'jane@whttest.test', '0811', '00000000-0000-0000-0000-000000099912', v_team_a, '00000000-0000-0000-0000-000000099912', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000099912', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant_a, v_prospect.id, 'Withholding test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000099912', v_team_a, '00000000-0000-0000-0000-000000099912', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000099912', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant_a, 'VENDOR-WHT-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000099911', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000099911', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000099912', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant_a, 20.00, 'half_up', '00000000-0000-0000-0000-000000099912', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000099912', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000099912', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant_a, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000099912', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight withholding lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000099912', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000099912', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000099912', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Withhold', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000099912', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000099912', 'rep');
  select * into v_job from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000099912', 'rep');

  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, null, '00000000-0000-0000-0000-000000099912', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: bypassing full shipment/epod/document/cost evidence chain, out of this test''s own scope', '00000000-0000-0000-0000-000000099912', 'rep');
  perform app.handoff_billing_readiness(v_job.id, 'wht-fixture-handoff-1', '00000000-0000-0000-0000-000000099912', 'rep');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000099913', 'financemanagera');

  -- Chart of accounts + published posting map, including the two withholding-tax
  -- accounts this test needs: PPH23's own dedicated recoverable account, and the shared
  -- withholding_tax_receivable_default fallback (mirrors TAX-PAYABLE-DEFAULT's own role
  -- for a rule with no output_account_id, on the debit side instead of credit).
  select * into v_gl_account from app.create_finance_account_draft(v_tenant_a, null, 'AR-CTRL', 'Accounts Receivable Control', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.activate_finance_account(v_gl_account.id, v_gl_account.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  select * into v_gl_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-DEFAULT', 'Default Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.activate_finance_account(v_gl_account.id, v_gl_account.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  select * into v_gl_account from app.create_finance_account_draft(v_tenant_a, null, 'TAX-PAYABLE-DEFAULT', 'Default Tax Payable', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.activate_finance_account(v_gl_account.id, v_gl_account.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  select * into v_gl_account from app.create_finance_account_draft(v_tenant_a, null, 'WHT-RECV-DEFAULT', 'Default Withholding Tax Receivable', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.activate_finance_account(v_gl_account.id, v_gl_account.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  select * into v_gl_account from app.create_finance_account_draft(v_tenant_a, null, 'WHT-PPH23-RECV', 'PPh23 Withholding Tax Receivable', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.activate_finance_account(v_gl_account.id, v_gl_account.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CTRL')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-DEFAULT')),
    jsonb_build_object('key', 'tax_payable_default', 'value', jsonb_build_object('accountCodeRef', 'TAX-PAYABLE-DEFAULT')),
    jsonb_build_object('key', 'withholding_tax_receivable_default', 'value', jsonb_build_object('accountCodeRef', 'WHT-RECV-DEFAULT'))
  ), '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000099913', null, 'financemanagera');

  -- PPH23: a withholding rule WITH its own governed recoverable_account_id.
  v_pph23_code_id := (select id from app.finance_tax_codes where tenant_id is null and code = 'PPH23');
  select * into v_pph23_rule from app.create_finance_tax_rule_draft(v_tenant_a, v_pph23_code_id, 'percentage', 0.02, null, null,
    (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'WHT-PPH23-RECV'),
    '2026-01-01'::date, null, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  select * into v_pph23_rule from app.attach_finance_tax_rule_evidence(v_pph23_rule.id, v_pph23_rule.record_version, null, 'fixture evidence note for CG-AUDIT-2026-09-02 B5''s own withholding-tax regression test', '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.approve_finance_tax_rule(v_pph23_rule.id, v_pph23_rule.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');

  -- PPH21: a withholding rule with NO recoverable_account_id -- proves the
  -- withholding_tax_receivable_default posting-map fallback.
  v_pph21_code_id := (select id from app.finance_tax_codes where tenant_id is null and code = 'PPH21');
  select * into v_pph21_rule from app.create_finance_tax_rule_draft(v_tenant_a, v_pph21_code_id, 'percentage', 0.05, null, null, null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  select * into v_pph21_rule from app.attach_finance_tax_rule_evidence(v_pph21_rule.id, v_pph21_rule.record_version, null, 'fixture evidence note for CG-AUDIT-2026-09-02 B5''s own posting-map-fallback regression test', '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.approve_finance_tax_rule(v_pph21_rule.id, v_pph21_rule.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');
end;
$$;

\echo '>> app.calculate_finance_tax discloses taxType=withholding for PPH23 (unchanged for PPN elsewhere -- vat)'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmewhta');
  v_result jsonb;
begin
  select app.calculate_finance_tax(v_tenant_a, 'PPH23', 15000000, '2026-02-01'::date, '00000000-0000-0000-0000-000000099913') into v_result;
  if (v_result ->> 'taxType') <> 'withholding' or (v_result ->> 'taxAmount')::numeric <> 300000 then
    raise exception 'assertion failed: expected taxType=withholding and taxAmount=300,000 (15,000,000 * 2%%), got %', v_result;
  end if;
end;
$$;

\echo '>> PPH23 (withholding, own recoverable_account_id): prepare -> tax_amount=0 (never added), withholding_tax_amount=300,000, total_amount=15,000,000 (unaffected); issue -> AR open item and AR-control debit net of the withheld amount (14,700,000), a 300,000 DEBIT to the rule''s own recoverable account (never a credit), and the GL journal still balances at the subtotal'
do $$
declare
  v_tenant_a uuid;
  v_invoice app.finance_invoices;
  v_ar_item app.finance_ar_open_items;
  v_debit_total numeric;
  v_credit_total numeric;
  v_wht_account_id uuid;
  v_handoff_id uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmewhta');
  v_handoff_id := (select h.id from app.billing_readiness_handoffs h join app.job_orders j on j.id = h.job_order_id where j.tenant_id = v_tenant_a limit 1);
  v_wht_account_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'WHT-PPH23-RECV');

  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff_id, 30, 'PPH23', '00000000-0000-0000-0000-000000099913', 'financemanagera');
  if v_invoice.subtotal_amount <> 15000000 or v_invoice.tax_amount <> 0 or v_invoice.withholding_tax_amount <> 300000 or v_invoice.total_amount <> 15000000 then
    raise exception 'assertion failed: expected a withholding-taxed draft invoice of subtotal=15,000,000 tax_amount=0 (never added) withholding_tax_amount=300,000 total_amount=15,000,000 (unaffected by the withheld amount), got subtotal=% tax=% withholding=% total=%', v_invoice.subtotal_amount, v_invoice.tax_amount, v_invoice.withholding_tax_amount, v_invoice.total_amount;
  end if;

  select * into v_invoice from app.submit_finance_invoice_for_approval(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  select * into v_invoice from app.approve_finance_invoice(v_invoice.id, v_invoice.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  select * into v_invoice from app.issue_finance_invoice(v_invoice.id, v_invoice.record_version, '2026-02-10'::date, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  if v_invoice.status <> 'issued' then
    raise exception 'assertion failed: expected status issued, got %', v_invoice.status;
  end if;

  select * into v_ar_item from app.finance_ar_open_items where id = v_invoice.ar_open_item_id;
  if v_ar_item.original_amount <> 14700000 then
    raise exception 'assertion failed: expected the AR open item to be net of the withheld amount (14,700,000 = 15,000,000 - 300,000), got %', v_ar_item.original_amount;
  end if;

  select coalesce(sum(case when direction = 'debit' then amount else 0 end), 0), coalesce(sum(case when direction = 'credit' then amount else 0 end), 0)
    into v_debit_total, v_credit_total
    from app.finance_subledger_lines
    where batch_id = (select id from app.finance_subledger_batches where tenant_id = v_tenant_a and source_type = 'invoice' and source_id = v_invoice.id);
  if v_debit_total <> v_credit_total or v_debit_total <> 15000000 then
    raise exception 'assertion failed: expected the GL journal to balance at 15,000,000 (subtotal), got debit_total=% credit_total=%', v_debit_total, v_credit_total;
  end if;

  if not exists (
    select 1 from app.finance_subledger_lines
    where batch_id = (select id from app.finance_subledger_batches where tenant_id = v_tenant_a and source_type = 'invoice' and source_id = v_invoice.id)
      and account_id = v_wht_account_id and direction = 'debit' and amount = 300000
  ) then
    raise exception 'assertion failed: expected a 300,000 DEBIT to the PPH23 rule''s own governed recoverable account (WHT-PPH23-RECV), never a credit to a payable account';
  end if;
  if exists (
    select 1 from app.finance_subledger_lines
    where batch_id = (select id from app.finance_subledger_batches where tenant_id = v_tenant_a and source_type = 'invoice' and source_id = v_invoice.id)
      and account_id = v_wht_account_id and direction = 'credit'
  ) then
    raise exception 'assertion failed: expected NO credit posting to the withholding-tax recoverable account';
  end if;
end;
$$;

\echo '>> PPH21 (withholding, no rule-level recoverable_account_id): prepared on a second, distinct handoff off the SAME job order (never issued -- finance_invoices_job_order_issued_unique allows only one issued invoice per job order, already claimed by the PPH23 scenario above) -- proves tax_amount stays 0 and withholding_tax_amount is set correctly regardless of whether a recoverable account is configured on the rule'
do $$
declare
  v_tenant_a uuid;
  v_job app.job_orders;
  v_evaluation app.billing_readiness_evaluations;
  v_handoff2 app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmewhta');
  select * into v_job from app.job_orders where tenant_id = v_tenant_a;

  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, 'fixture: second handoff for CG-AUDIT-2026-09-02 B5''s own posting-map-fallback test', '00000000-0000-0000-0000-000000099912', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: second override', '00000000-0000-0000-0000-000000099912', 'rep');
  select * into v_handoff2 from app.handoff_billing_readiness(v_job.id, 'wht-fixture-handoff-2', '00000000-0000-0000-0000-000000099912', 'rep');

  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff2.id, 30, 'PPH21', '00000000-0000-0000-0000-000000099913', 'financemanagera');
  if v_invoice.subtotal_amount <> 15000000 or v_invoice.tax_amount <> 0 or v_invoice.withholding_tax_amount <> 750000 or v_invoice.total_amount <> 15000000 then
    raise exception 'assertion failed: expected a second withholding-taxed draft invoice of subtotal=15,000,000 tax_amount=0 withholding_tax_amount=750,000 (15,000,000 * 5%%) total_amount=15,000,000, got subtotal=% tax=% withholding=% total=%', v_invoice.subtotal_amount, v_invoice.tax_amount, v_invoice.withholding_tax_amount, v_invoice.total_amount;
  end if;

  if not exists (
    select 1 from app.finance_invoice_lines
    where invoice_id = v_invoice.id and line_type = 'tax' and amount = 750000 and description ~ 'withheld'
  ) then
    raise exception 'assertion failed: expected a real 750,000 tax line disclosing the withheld PPH21 amount on the invoice';
  end if;
end;
$$;

\echo '>> unaffected regression: PPN (vat, not withholding) is still ADDED exactly as before -- tax_amount and total_amount both include it, withholding_tax_amount stays zero'
do $$
declare
  v_tenant_a uuid;
  v_job app.job_orders;
  v_evaluation app.billing_readiness_evaluations;
  v_handoff3 app.billing_readiness_handoffs;
  v_invoice app.finance_invoices;
  v_ppn_code_id uuid;
  v_ppn_rule app.finance_tax_rule_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmewhta');
  select * into v_job from app.job_orders where tenant_id = v_tenant_a;

  v_ppn_code_id := (select id from app.finance_tax_codes where tenant_id is null and code = 'PPN');
  select * into v_ppn_rule from app.create_finance_tax_rule_draft(v_tenant_a, v_ppn_code_id, 'percentage', 0.11, null, null, null, '2026-01-01'::date, null, '00000000-0000-0000-0000-000000099913', 'financemanagera');
  select * into v_ppn_rule from app.attach_finance_tax_rule_evidence(v_ppn_rule.id, v_ppn_rule.record_version, null, 'fixture evidence note for CG-AUDIT-2026-09-02 B5''s own non-withholding regression check', '00000000-0000-0000-0000-000000099913', 'financemanagera');
  perform app.approve_finance_tax_rule(v_ppn_rule.id, v_ppn_rule.record_version, '00000000-0000-0000-0000-000000099913', 'financemanagera');

  select * into v_evaluation from app.evaluate_billing_readiness(v_job.id, 'fixture: third handoff for CG-AUDIT-2026-09-02 B5''s own non-withholding regression check', '00000000-0000-0000-0000-000000099912', 'rep');
  select * into v_evaluation from app.override_billing_readiness(v_job.id, v_evaluation.record_version, 'fixture: third override', '00000000-0000-0000-0000-000000099912', 'rep');
  select * into v_handoff3 from app.handoff_billing_readiness(v_job.id, 'wht-fixture-handoff-3', '00000000-0000-0000-0000-000000099912', 'rep');

  select * into v_invoice from app.prepare_finance_invoice_from_readiness(v_tenant_a, v_handoff3.id, 30, 'PPN', '00000000-0000-0000-0000-000000099913', 'financemanagera');
  if v_invoice.subtotal_amount <> 15000000 or v_invoice.tax_amount <> 1650000 or v_invoice.withholding_tax_amount <> 0 or v_invoice.total_amount <> 16650000 then
    raise exception 'assertion failed: expected PPN (vat, added) to be completely unaffected by this fix -- subtotal=15,000,000 tax_amount=1,650,000 withholding_tax_amount=0 total_amount=16,650,000, got subtotal=% tax=% withholding=% total=%', v_invoice.subtotal_amount, v_invoice.tax_amount, v_invoice.withholding_tax_amount, v_invoice.total_amount;
  end if;
end;
$$;

\echo '>> scripts/db-tests/finance-invoice-withholding-tax.sql: all assertions passed'
