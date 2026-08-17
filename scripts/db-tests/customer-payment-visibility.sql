-- Real, executable test evidence for CPL-312 (CG-S13-CPL-014, Prompt 312,
-- "Payment Visibility") -- run via `pnpm run db:test` against a real,
-- disposable Postgres database. Structural convention mirrors
-- scripts/db-tests/customer-invoice-billing-visibility.sql (CPL-311): a
-- single Supreme Admin actor performs all staff-side setup plumbing (direct
-- fixture inserts through the Commercial->Operations->Finance chain,
-- bypassing staff RBAC plumbing not under test here -- only the customer-
-- portal READ layer is).
--
-- UUID range 00000000-0000-0000-0000-000000325xxx (tenant cpv1) /
-- 00000000-0000-0000-0000-000000326xxx (tenant cpv2), grep-verified
-- unclaimed against every other file in this directory before writing this
-- fixture.
--
-- Covers, live: (a) cross-tenant/cross-account isolation on both new RPCs;
-- (b) bank_account_label AND payer_name never appear in any returned row,
-- structurally (key-check) AND textually (grep-provable substring search
-- against a distinctive sentinel value set on every fixture receipt); (c) a
-- held AR open item correctly surfaces as is_held=true (the "blocked/on
-- hold" UI state), and its own hold_reason never leaks even though the
-- fixture sets a real, distinctive one; (d) allocation-to-invoice linkage is
-- correct -- two receipts applied to the SAME AR open item both appear on
-- that invoice's own payment status, a third receipt applied to a
-- DIFFERENT AR open item never does, and a reversed-style exclusion is
-- honored by construction (only status='applied' rows are ever composed,
-- proved by the fixture's own exact allocated_amount totals); (e) anti-
-- enumeration -- a genuinely nonexistent invoice, a real cross-account
-- invoice, and a real cross-tenant probe all raise the identical
-- record_not_found app._resolve_customer_portal_invoice (CPL-311) already
-- raises; (f) cursor pagination correctness across Alpha's own 5 receipts;
-- (g) status-filter correctness on the receipts list, including both real
-- statuses (captured/void) being portal-visible; (h) raw-table RLS defense-
-- in-depth (app.finance_receipts/app.finance_receipt_allocations/app.
-- finance_ar_open_items are UNCHANGED by this migration, already denied a
-- customer_user actor outright); (i) raw-function grant defense in depth;
-- (j) the actor-identity session cross-check on both new RPCs; (k) a real,
-- live authenticated-role positive path.

\set ON_ERROR_STOP on

-- A plain, top-level, temporary test helper -- mirrors scripts/db-tests/
-- customer-invoice-billing-visibility.sql's own app._cib_test_make_chain
-- (itself mirroring scripts/db-tests/ticketing-escalation.sql's own
-- established "create a real app.* function for this file's own fixture
-- need, drop it once the fixture is built" convention). Reduces the
-- lead->prospect->opportunity->quotation->job_order_handoff->job_order->
-- billing_readiness_evaluation chain to one call per account.
create function app._cpv_test_make_chain(p_tenant uuid, p_company uuid, p_account uuid, p_tag text, p_actor uuid)
returns table (job_order_id uuid, eval_id uuid)
language plpgsql
as $$
declare
  v_lead uuid;
  v_prospect uuid;
  v_opportunity uuid;
  v_quotation uuid;
  v_handoff uuid;
  v_job_order uuid;
  v_eval uuid;
begin
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  values (gen_random_uuid(), p_tenant, 'referral', p_tag || ' Lead', p_tag || '-lead@cpv.test', 'fp-cpv-' || p_tag || '-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), p_tenant, v_lead, p_tag || ' Prospect Co', 'fp-cpv-' || p_tag || '-prospect', p_tag || ' Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), p_tenant, v_prospect, p_tag || ' Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, p_tenant, 'QUO-CPV-' || p_tag, v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), p_tenant, v_quotation, p_account, '{"note": "cpv fixture"}'::jsonb, 'hash-cpv-' || p_tag, p_actor, p_company, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot,
    status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, 'JOB-CPV-' || p_tag, v_handoff, v_quotation, p_account,
    '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb,
    'confirmed', p_actor, p_company, 'tester'
  )
  returning id into v_job_order;
  insert into app.billing_readiness_evaluations (id, tenant_id, job_order_id, evaluated_status, blockers, evidence, evaluated_by_auth_user_id)
  values (gen_random_uuid(), p_tenant, v_job_order, 'ready', '[]'::jsonb, '{}'::jsonb, p_actor)
  returning id into v_eval;
  return query select v_job_order, v_eval;
end;
$$;

\echo '>> setup: tenant cpv1 (accounts Alpha/Beta, company Cpv1 Co), tenant cpv2 (account Delta) -- one issued invoice + AR open item per fixture case, receipts/allocations with a distinctive, grep-able sentinel on every bank_account_label/payer_name/hold_reason value'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_account_alpha uuid := '00000000-0000-0000-0000-000000325100';
  v_account_beta uuid := '00000000-0000-0000-0000-000000325200';
  v_account_delta uuid := '00000000-0000-0000-0000-000000326100';
  v_supreme uuid := '00000000-0000-0000-0000-000000325001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000325010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000325020';
  v_impersonator uuid := '00000000-0000-0000-0000-000000325050';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000326010';
  v_job_order_alpha uuid;
  v_job_order_beta uuid;
  v_job_order_delta uuid;
  v_eval_alpha uuid;
  v_eval_beta uuid;
  v_eval_delta uuid;
  v_batch uuid;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@cpv.test'),
    (v_customer_alpha, 'customer-alpha@cpv1.test'),
    (v_customer_beta, 'customer-beta@cpv1.test'),
    (v_impersonator, 'impersonator@cpv1.test'),
    (v_customer_delta, 'customer-delta@cpv2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cpv1', 'Customer Payment Visibility Tenant One', 'idem-cpv1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cpv1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CPV1-CO', 'Cpv1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CPV1-CO');

  perform app.provision_tenant('cpv2', 'Customer Payment Visibility Tenant Two', 'idem-cpv2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cpv2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CPV2-CO', 'Cpv2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CPV2-CO');

  insert into app.accounts (id, tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_account_alpha, v_tenant1, 'Cpv Account Alpha', 'cpv-alpha-fp', '{}'::jsonb, v_company1, 'tester');
  insert into app.accounts (id, tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_account_beta, v_tenant1, 'Cpv Account Beta', 'cpv-beta-fp', '{}'::jsonb, v_company1, 'tester');
  insert into app.accounts (id, tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_account_delta, v_tenant2, 'Cpv Account Delta', 'cpv-delta-fp', '{}'::jsonb, v_company2, 'tester');

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@cpv1.test', 'Cpv Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@cpv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@cpv1.test', 'Cpv Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@cpv1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  -- impersonator: a real, active tenant1 identity with ZERO customer_user
  -- grant of any kind -- used only for the actor-identity session cross-check.
  perform app.invite_user(v_tenant1, v_impersonator, 'impersonator@cpv1.test', 'Cpv Impersonator', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@cpv1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_customer_delta, 'customer-delta@cpv2.test', 'Cpv Customer Delta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-delta@cpv2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_delta, 'customer_user', v_tenant2, v_account_delta::text, 'tester');

  select job_order_id, eval_id into v_job_order_alpha, v_eval_alpha from app._cpv_test_make_chain(v_tenant1, v_company1, v_account_alpha, 'ALPHA', v_supreme);
  select job_order_id, eval_id into v_job_order_beta, v_eval_beta from app._cpv_test_make_chain(v_tenant1, v_company1, v_account_beta, 'BETA', v_supreme);
  select job_order_id, eval_id into v_job_order_delta, v_eval_delta from app._cpv_test_make_chain(v_tenant2, v_company2, v_account_delta, 'DELTA', v_supreme);

  -- One billing_readiness_handoff per invoice fixture case.
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by) values
    ('00000000-0000-0000-0000-000000325201', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cpv-br-a1', v_supreme, 'tester'),
    ('00000000-0000-0000-0000-000000325202', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cpv-br-a2', v_supreme, 'tester'),
    ('00000000-0000-0000-0000-000000325203', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cpv-br-a3', v_supreme, 'tester'),
    ('00000000-0000-0000-0000-000000325204', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cpv-br-a4', v_supreme, 'tester');
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by) values
    ('00000000-0000-0000-0000-000000325220', v_tenant1, v_job_order_beta, v_eval_beta, 'idem-cpv-br-b1', v_supreme, 'tester');
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by) values
    ('00000000-0000-0000-0000-000000326201', v_tenant2, v_job_order_delta, v_eval_delta, 'idem-cpv-br-d1', v_supreme, 'tester');

  -- AR open items -- inserted BEFORE their own referencing invoice row (no
  -- FK from finance_ar_open_items.source_document_id to any table).
  -- AR-A1 (paid, two applied allocations 700+300=1000); AR-A2 (partial,
  -- one applied allocation 200 of 500); AR-A3 (open, HELD, zero
  -- allocations -- must surface as blocked/on-hold, hold_reason NEVER leaks).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000325301', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000325101', 'USD', 1000, 1000, 'paid', false, '2026-07-01', '2026-07-31', 'tester'),
    ('00000000-0000-0000-0000-000000325302', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000325102', 'USD', 500, 200, 'partial', false, '2026-08-01', '2026-08-31', 'tester'),
    ('00000000-0000-0000-0000-000000325303', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000325103', 'USD', 300, 0, 'open', true, '2026-08-05', '2026-09-04', 'tester');
  update app.finance_ar_open_items set hold_reason = 'HOLD-REASON-SECRET-CPV-internal collections escalation', held_by = 'tester', held_at = now() where id = '00000000-0000-0000-0000-000000325303';
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000325320', v_tenant1, v_account_beta, 'invoice', '00000000-0000-0000-0000-000000325120', 'USD', 400, 400, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000326301', v_tenant2, v_account_delta, 'invoice', '00000000-0000-0000-0000-000000326101', 'USD', 250, 100, 'partial', false, '2026-08-01', '2026-08-31', 'tester');

  -- Alpha's 4 invoices -- 3 issued (paid/partial/open+held), 1 void-before-
  -- ever-issued (ar_open_item_id null -- payment_status must resolve to
  -- not_posted with an empty allocations array).
  insert into app.finance_invoices (id, tenant_id, company_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, status, subtotal_amount, tax_amount, issue_date, due_date, ar_open_item_id, issued_by, issued_at, created_by) values
    ('00000000-0000-0000-0000-000000325101', v_tenant1, v_company1, 'INV-CPV-000001', v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000325201', 'USD', 'issued', 1000, 0, '2026-07-01', '2026-07-31', '00000000-0000-0000-0000-000000325301', 'tester', now(), 'tester'),
    ('00000000-0000-0000-0000-000000325102', v_tenant1, v_company1, 'INV-CPV-000002', v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000325202', 'USD', 'issued', 500, 0, '2026-08-01', '2026-08-31', '00000000-0000-0000-0000-000000325302', 'tester', now(), 'tester'),
    ('00000000-0000-0000-0000-000000325103', v_tenant1, v_company1, 'INV-CPV-000003', v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000325203', 'USD', 'issued', 300, 0, '2026-08-05', '2026-09-04', '00000000-0000-0000-0000-000000325303', 'tester', now(), 'tester');
  insert into app.finance_invoices (id, tenant_id, company_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, status, subtotal_amount, tax_amount, void_reason, voided_by, voided_at, created_by) values
    ('00000000-0000-0000-0000-000000325104', v_tenant1, v_company1, null, v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000325204', 'USD', 'void', 150, 0, 'cpv fixture void before issuance', 'tester', now(), 'tester');

  insert into app.finance_invoices (id, tenant_id, company_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, status, subtotal_amount, tax_amount, issue_date, due_date, ar_open_item_id, issued_by, issued_at, created_by) values
    ('00000000-0000-0000-0000-000000325120', v_tenant1, v_company1, 'INV-CPV-BETA-0001', v_account_beta, v_job_order_beta, '00000000-0000-0000-0000-000000325220', 'USD', 'issued', 400, 0, '2026-08-01', '2026-08-31', '00000000-0000-0000-0000-000000325320', 'tester', now(), 'tester');

  insert into app.finance_invoices (id, tenant_id, company_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, status, subtotal_amount, tax_amount, issue_date, due_date, ar_open_item_id, issued_by, issued_at, created_by) values
    ('00000000-0000-0000-0000-000000326101', v_tenant2, v_company2, 'INV-CPV-DELTA-0001', v_account_delta, v_job_order_delta, '00000000-0000-0000-0000-000000326201', 'USD', 'issued', 250, 0, '2026-08-01', '2026-08-31', '00000000-0000-0000-0000-000000326301', 'tester', now(), 'tester');

  -- Receipts -- every bank_account_label AND payer_name carries a
  -- distinctive, grep-able sentinel substring. R-A4 is captured but fully
  -- UNAPPLIED (unapplied_amount=150, the closest honest "pending
  -- reconciliation"-shaped signal this schema has). R-A5 is VOID -- both
  -- real receipt statuses must remain portal-visible on the list.
  insert into app.finance_receipts (id, tenant_id, company_id, customer_account_id, receipt_reference, receipt_date, payer_name, bank_account_label, currency, amount, allocated_amount, status, idempotency_key, created_by) values
    ('00000000-0000-0000-0000-000000325401', v_tenant1, v_company1, v_account_alpha, 'RCPT-CPV-A1', '2026-08-01', 'PAYER-SECRET-CPV-alpha-self', 'BANK-LABEL-SECRET-CPV-0001', 'USD', 700, 700, 'captured', 'idem-cpv-r-a1', 'tester'),
    ('00000000-0000-0000-0000-000000325402', v_tenant1, v_company1, v_account_alpha, 'RCPT-CPV-A2', '2026-08-02', 'PAYER-SECRET-CPV-third-party', 'BANK-LABEL-SECRET-CPV-0002', 'USD', 300, 300, 'captured', 'idem-cpv-r-a2', 'tester'),
    ('00000000-0000-0000-0000-000000325403', v_tenant1, v_company1, v_account_alpha, 'RCPT-CPV-A3', '2026-08-10', null, 'BANK-LABEL-SECRET-CPV-0003', 'USD', 200, 200, 'captured', 'idem-cpv-r-a3', 'tester'),
    ('00000000-0000-0000-0000-000000325404', v_tenant1, v_company1, v_account_alpha, 'RCPT-CPV-A4', '2026-08-12', null, 'BANK-LABEL-SECRET-CPV-0004', 'USD', 150, 0, 'captured', 'idem-cpv-r-a4', 'tester'),
    ('00000000-0000-0000-0000-000000325405', v_tenant1, v_company1, v_account_alpha, 'RCPT-CPV-A5', '2026-08-13', null, 'BANK-LABEL-SECRET-CPV-0005', 'USD', 50, 0, 'void', 'idem-cpv-r-a5', 'tester'),
    ('00000000-0000-0000-0000-000000325420', v_tenant1, v_company1, v_account_beta, 'RCPT-CPV-B1', '2026-08-01', 'PAYER-SECRET-CPV-beta-self', 'BANK-LABEL-SECRET-CPV-0006', 'USD', 400, 400, 'captured', 'idem-cpv-r-b1', 'tester');
  insert into app.finance_receipts (id, tenant_id, company_id, customer_account_id, receipt_reference, receipt_date, payer_name, bank_account_label, currency, amount, allocated_amount, status, idempotency_key, created_by) values
    ('00000000-0000-0000-0000-000000326401', v_tenant2, v_company2, v_account_delta, 'RCPT-CPV-D1', '2026-08-01', 'PAYER-SECRET-CPV-delta-self', 'BANK-LABEL-SECRET-CPV-0007', 'USD', 100, 100, 'captured', 'idem-cpv-r-d1', 'tester');

  -- Allocations -- one batch per allocation. Only 'applied' status exists in
  -- this fixture (proving the exclusion filter is exercised honestly, not
  -- vacuously, needs a genuinely reversed row too -- see the dedicated
  -- reversed-allocation block further below).
  insert into app.finance_receipt_allocation_batches (id, tenant_id, receipt_id, idempotency_key, created_by) values (gen_random_uuid(), v_tenant1, '00000000-0000-0000-0000-000000325401', 'idem-cpv-batch-a1', 'tester') returning id into v_batch;
  insert into app.finance_receipt_allocations (tenant_id, receipt_id, batch_id, ar_open_item_id, amount, status, created_by) values (v_tenant1, '00000000-0000-0000-0000-000000325401', v_batch, '00000000-0000-0000-0000-000000325301', 700, 'applied', 'tester');

  insert into app.finance_receipt_allocation_batches (id, tenant_id, receipt_id, idempotency_key, created_by) values (gen_random_uuid(), v_tenant1, '00000000-0000-0000-0000-000000325402', 'idem-cpv-batch-a2', 'tester') returning id into v_batch;
  insert into app.finance_receipt_allocations (tenant_id, receipt_id, batch_id, ar_open_item_id, amount, status, created_by) values (v_tenant1, '00000000-0000-0000-0000-000000325402', v_batch, '00000000-0000-0000-0000-000000325301', 300, 'applied', 'tester');

  insert into app.finance_receipt_allocation_batches (id, tenant_id, receipt_id, idempotency_key, created_by) values (gen_random_uuid(), v_tenant1, '00000000-0000-0000-0000-000000325403', 'idem-cpv-batch-a3', 'tester') returning id into v_batch;
  insert into app.finance_receipt_allocations (tenant_id, receipt_id, batch_id, ar_open_item_id, amount, status, created_by) values (v_tenant1, '00000000-0000-0000-0000-000000325403', v_batch, '00000000-0000-0000-0000-000000325302', 200, 'applied', 'tester');

  insert into app.finance_receipt_allocation_batches (id, tenant_id, receipt_id, idempotency_key, created_by) values (gen_random_uuid(), v_tenant1, '00000000-0000-0000-0000-000000325420', 'idem-cpv-batch-b1', 'tester') returning id into v_batch;
  insert into app.finance_receipt_allocations (tenant_id, receipt_id, batch_id, ar_open_item_id, amount, status, created_by) values (v_tenant1, '00000000-0000-0000-0000-000000325420', v_batch, '00000000-0000-0000-0000-000000325320', 400, 'applied', 'tester');

  insert into app.finance_receipt_allocation_batches (id, tenant_id, receipt_id, idempotency_key, created_by) values (gen_random_uuid(), v_tenant2, '00000000-0000-0000-0000-000000326401', 'idem-cpv-batch-d1', 'tester') returning id into v_batch;
  insert into app.finance_receipt_allocations (tenant_id, receipt_id, batch_id, ar_open_item_id, amount, status, created_by) values (v_tenant2, '00000000-0000-0000-0000-000000326401', v_batch, '00000000-0000-0000-0000-000000326301', 100, 'applied', 'tester');

  -- A genuinely REVERSED allocation on AR-A2 (INV-CPV-000002) -- a THIRD
  -- receipt (R-A2-reversed-source, reusing R-A2's own id is not possible
  -- since one allocation row is enough; a distinct receipt is inserted for
  -- this specific proof) whose own allocation is reversed and must NEVER
  -- appear in app.get_customer_portal_payment_status' own allocations
  -- array for INV-CPV-000002, even though it is a real row referencing the
  -- exact right ar_open_item_id (migration design decision 8 -- proving the
  -- status='applied' filter is exercised, not merely present in the SQL text).
  insert into app.finance_receipts (id, tenant_id, company_id, customer_account_id, receipt_reference, receipt_date, payer_name, bank_account_label, currency, amount, allocated_amount, status, idempotency_key, created_by) values
    ('00000000-0000-0000-0000-000000325406', v_tenant1, v_company1, v_account_alpha, 'RCPT-CPV-A6-REVERSED', '2026-08-15', null, 'BANK-LABEL-SECRET-CPV-0008', 'USD', 999, 0, 'captured', 'idem-cpv-r-a6', 'tester');
  insert into app.finance_receipt_allocation_batches (id, tenant_id, receipt_id, idempotency_key, created_by) values (gen_random_uuid(), v_tenant1, '00000000-0000-0000-0000-000000325406', 'idem-cpv-batch-a6', 'tester') returning id into v_batch;
  insert into app.finance_receipt_allocations (tenant_id, receipt_id, batch_id, ar_open_item_id, amount, status, reason, reversed_by, reversed_at, created_by) values
    (v_tenant1, '00000000-0000-0000-0000-000000325406', v_batch, '00000000-0000-0000-0000-000000325302', 999, 'reversed', 'cpv fixture reversal proof', 'tester', now(), 'tester');
end $$;

-- Fixture-only helper, no longer needed once the chain rows above exist.
drop function if exists app._cpv_test_make_chain(uuid, uuid, uuid, text, uuid);

\echo '>> app.get_customer_portal_payment_status: paid (two applied allocations, amounts and receipt references correct), partial (one applied allocation, the REVERSED sibling on the SAME ar_open_item_id never appears), open+held (is_held=true, zero allocations, hold_reason NEVER leaks even though a real one is set), not_posted (void-before-issuance, empty allocations); structural + textual (sentinel substring) leak checks'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpv1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000325010';
  v_row record;
  v_row_json jsonb;
  v_alloc jsonb;
  v_amounts numeric[];
begin
  -- INV-CPV-000001: paid, two applied allocations (700 + 300 = 1000).
  select * into v_row from app.get_customer_portal_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000325101');
  if v_row.payment_status <> 'paid' or v_row.original_amount <> 1000 or v_row.open_amount <> 0 or v_row.is_held is distinct from false then
    raise exception 'assertion failed: expected INV-CPV-000001 payment_status=paid original_amount=1000 open_amount=0 is_held=false, got %', v_row;
  end if;
  if jsonb_array_length(v_row.allocations) <> 2 then
    raise exception 'assertion failed: expected exactly 2 applied allocations for INV-CPV-000001, got %', v_row.allocations;
  end if;
  select array_agg((elem ->> 'amount')::numeric order by (elem ->> 'amount')::numeric) into v_amounts from jsonb_array_elements(v_row.allocations) elem;
  if v_amounts <> array[300, 700]::numeric[] then
    raise exception 'assertion failed: expected allocation amounts {300,700} for INV-CPV-000001, got %', v_amounts;
  end if;
  -- Ordered by receipt_date asc -- R-A1 (2026-08-01, amount 700) first.
  v_alloc := v_row.allocations -> 0;
  if v_alloc ->> 'receiptReference' <> 'RCPT-CPV-A1' or (v_alloc ->> 'amount')::numeric <> 700 or v_alloc ->> 'currency' <> 'USD' then
    raise exception 'assertion failed: expected the first allocation to be RCPT-CPV-A1 amount=700 currency=USD, got %', v_alloc;
  end if;
  v_row_json := to_jsonb(v_row);
  if v_row_json ? 'ar_open_item_id' or v_row_json ? 'hold_reason' or v_row_json ? 'id' then
    raise exception 'assertion failed: app.get_customer_portal_payment_status leaked an internal-only field, got keys %', (select array_agg(k) from jsonb_object_keys(v_row_json) k);
  end if;
  if v_alloc ? 'bankAccountLabel' or v_alloc ? 'payerName' or v_alloc ? 'bank_account_label' or v_alloc ? 'payer_name' then
    raise exception 'assertion failed: an allocation entry leaked bank_account_label/payer_name as a key, got %', v_alloc;
  end if;
  if v_row_json::text like '%BANK-LABEL-SECRET-CPV%' or v_row_json::text like '%PAYER-SECRET-CPV%' then
    raise exception 'assertion failed: the sentinel bank_account_label/payer_name substring appeared in app.get_customer_portal_payment_status'' own returned row, got %', v_row_json;
  end if;

  -- INV-CPV-000002: partial, exactly ONE applied allocation (200) -- the
  -- REVERSED 999 allocation on the SAME ar_open_item_id must never appear
  -- (design decision 8's own exclusion, live-proved here, not merely
  -- present in the SQL text).
  select * into v_row from app.get_customer_portal_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000325102');
  if v_row.payment_status <> 'partial' or v_row.original_amount <> 500 or v_row.open_amount <> 300 then
    raise exception 'assertion failed: expected INV-CPV-000002 payment_status=partial original_amount=500 open_amount=300 (500-200), got %', v_row;
  end if;
  if jsonb_array_length(v_row.allocations) <> 1 then
    raise exception 'assertion failed: expected exactly 1 applied allocation for INV-CPV-000002 (the reversed 999 must be excluded), got %', v_row.allocations;
  end if;
  v_alloc := v_row.allocations -> 0;
  if v_alloc ->> 'receiptReference' <> 'RCPT-CPV-A3' or (v_alloc ->> 'amount')::numeric <> 200 then
    raise exception 'assertion failed: expected the sole allocation to be RCPT-CPV-A3 amount=200, got %', v_alloc;
  end if;

  -- INV-CPV-000003: open, HELD -- is_held=true is the honest "blocked/on
  -- hold" signal; hold_reason (a real, distinctive value) NEVER leaks;
  -- zero allocations (nothing has been applied to this held item).
  select * into v_row from app.get_customer_portal_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000325103');
  if v_row.payment_status <> 'open' or v_row.is_held is distinct from true or v_row.open_amount <> 300 then
    raise exception 'assertion failed: expected INV-CPV-000003 payment_status=open is_held=true open_amount=300, got %', v_row;
  end if;
  if jsonb_array_length(v_row.allocations) <> 0 then
    raise exception 'assertion failed: expected zero allocations for the held, unpaid INV-CPV-000003, got %', v_row.allocations;
  end if;
  if to_jsonb(v_row)::text like '%HOLD-REASON-SECRET-CPV%' then
    raise exception 'assertion failed: the real, distinctive hold_reason sentinel leaked into app.get_customer_portal_payment_status'' own returned row for the held item';
  end if;

  -- INV-CPV-000004: void-before-ever-issued -- the synthesized not_posted
  -- state, empty allocations, never a fabricated zero.
  select * into v_row from app.get_customer_portal_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000325104');
  if v_row.payment_status <> 'not_posted' or v_row.original_amount is not null or v_row.open_amount is not null or v_row.is_held is not null then
    raise exception 'assertion failed: expected the void-before-issuance invoice to resolve payment_status=not_posted with NULL amounts, got %', v_row;
  end if;
  if v_row.allocations <> '[]'::jsonb then
    raise exception 'assertion failed: expected an empty allocations array for the not_posted invoice, got %', v_row.allocations;
  end if;
end $$;

\echo '>> anti-enumeration: a genuinely nonexistent invoice, Alpha probing Beta''s own invoice, and a cross-tenant probe all raise the IDENTICAL record_not_found app._resolve_customer_portal_invoice (CPL-311) already raises'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpv1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cpv2');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000325010';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000326010';
  v_fake_id uuid := '77777777-7777-7777-7777-777777777779';
  v_msg_fake text;
  v_msg_beta text;
  v_msg_crosstenant text;
begin
  begin
    perform app.get_customer_portal_payment_status(v_tenant1, v_customer_alpha, v_fake_id);
    raise exception 'assertion failed: expected record_not_found for a genuinely nonexistent invoice id';
  exception when others then v_msg_fake := sqlerrm; if v_msg_fake not like 'record_not_found%' then raise; end if;
  end;

  begin
    perform app.get_customer_portal_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000325120');
    raise exception 'assertion failed: expected record_not_found -- Alpha must not see Beta''s own invoice''s payment status';
  exception when others then v_msg_beta := sqlerrm; if v_msg_beta not like 'record_not_found%' then raise; end if;
  end;

  begin
    perform app.get_customer_portal_payment_status(v_tenant1, v_customer_delta, '00000000-0000-0000-0000-000000325101');
    raise exception 'assertion failed: expected record_not_found -- customer-delta (tenant2) must not read tenant1''s own Alpha invoice payment status even by cross-tenant guess';
  exception when others then v_msg_crosstenant := sqlerrm; if v_msg_crosstenant not like 'record_not_found%' then raise; end if;
  end;

  if left(v_msg_fake, 16) <> left(v_msg_beta, 16) or left(v_msg_fake, 16) <> left(v_msg_crosstenant, 16) then
    raise exception 'assertion failed: expected nonexistent/cross-account/cross-tenant to all raise the IDENTICAL anti-enumerating message prefix, got % / % / %', v_msg_fake, v_msg_beta, v_msg_crosstenant;
  end if;

  -- The real, correctly-scoped positive case in tenant2 still works.
  perform app.get_customer_portal_payment_status(v_tenant2, v_customer_delta, '00000000-0000-0000-0000-000000326101');
end $$;

\echo '>> app.list_customer_portal_receipts: Alpha sees exactly its own 6 receipts (5 real fixture receipts + the reversed-proof receipt, never Beta''s or Delta''s), status filter correctness (both real statuses portal-visible), cursor pagination terminates cleanly, bank_account_label/payer_name never appear anywhere -- structural AND textual (sentinel) leak checks across every row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpv1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cpv2');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000325010';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000326010';
  v_count integer;
  v_row record;
  v_row_json jsonb;
  v_all_text text := '';
  v_seen_ids uuid[] := array[]::uuid[];
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page_count integer;
  v_total_pages integer := 0;
begin
  select count(*) into v_count from app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, null, null, null, 200);
  if v_count <> 6 then
    raise exception 'assertion failed: expected exactly 6 receipts for Alpha (5 fixture + 1 reversed-proof), got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, 'captured', null, null, 200);
  if v_count <> 5 then
    raise exception 'assertion failed: expected exactly 5 captured receipts for Alpha, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, 'void', null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 void receipt for Alpha, got %', v_count;
  end if;

  -- Cross-account: Alpha's own list never contains Beta's receipt.
  select count(*) into v_count from app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, null, null, null, 200) v where v.id = '00000000-0000-0000-0000-000000325420';
  if v_count <> 0 then
    raise exception 'assertion failed: expected Beta''s own receipt to never appear in Alpha''s list, got %', v_count;
  end if;

  -- Structural + textual leak check over every one of Alpha's own 6 rows
  -- (not just one sampled row) -- concatenates every returned row's own
  -- to_jsonb() text and asserts the sentinel substrings never appear.
  for v_row in select * from app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, null, null, null, 200) loop
    v_row_json := to_jsonb(v_row);
    if v_row_json ? 'bank_account_label' or v_row_json ? 'payer_name' or v_row_json ? 'bankAccountLabel' or v_row_json ? 'payerName' then
      raise exception 'assertion failed: app.list_customer_portal_receipts leaked a bank_account_label/payer_name key, got %', (select array_agg(k) from jsonb_object_keys(v_row_json) k);
    end if;
    v_all_text := v_all_text || v_row_json::text;
  end loop;
  if v_all_text like '%BANK-LABEL-SECRET-CPV%' or v_all_text like '%PAYER-SECRET-CPV%' then
    raise exception 'assertion failed: the sentinel bank_account_label/payer_name substring appeared somewhere across app.list_customer_portal_receipts'' own returned rows';
  end if;

  -- R-A4: captured but fully unapplied -- the closest honest "pending
  -- reconciliation"-shaped signal this schema has (design decision 8).
  select * into v_row from app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, null, null, null, 200) v where v.id = '00000000-0000-0000-0000-000000325404';
  if v_row.amount <> 150 or v_row.allocated_amount <> 0 or v_row.unapplied_amount <> 150 or v_row.status <> 'captured' then
    raise exception 'assertion failed: expected RCPT-CPV-A4 amount=150 allocated_amount=0 unapplied_amount=150 status=captured, got %', v_row;
  end if;

  -- Cursor pagination: p_limit=1 across Alpha's 6 own receipts must yield 6
  -- distinct pages that together cover all 6 rows exactly once.
  loop
    v_page_count := 0;
    for v_row in select * from app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, null, v_cursor_updated_at, v_cursor_id, 1) loop
      v_page_count := v_page_count + 1;
      if v_row.id = any(v_seen_ids) then
        raise exception 'assertion failed: cursor pagination returned a duplicate row %, seen so far %', v_row.id, v_seen_ids;
      end if;
      v_seen_ids := v_seen_ids || v_row.id;
      v_cursor_updated_at := v_row.updated_at;
      v_cursor_id := v_row.id;
    end loop;
    exit when v_page_count = 0;
    v_total_pages := v_total_pages + 1;
    if v_total_pages > 10 then
      raise exception 'assertion failed: cursor pagination did not terminate within 10 pages -- possible infinite loop';
    end if;
  end loop;
  if v_total_pages <> 6 or array_length(v_seen_ids, 1) <> 6 then
    raise exception 'assertion failed: expected exactly 6 pages of 1 row each covering 6 distinct rows, got % pages / % rows', v_total_pages, array_length(v_seen_ids, 1);
  end if;

  -- Half-supplied cursor fails loud.
  begin
    perform app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_updated_at';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;

  -- Cross-tenant isolation: customer-delta probing tenant1 with tenant1's
  -- own id sees ZERO rows; sees exactly their own 1 receipt in tenant2.
  select count(*) into v_count from app.list_customer_portal_receipts(v_tenant1, v_customer_delta, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a genuinely cross-tenant identity probing tenant1 with tenant1''s own id, got %', v_count;
  end if;
  select count(*) into v_count from app.list_customer_portal_receipts(v_tenant2, v_customer_delta, null, null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 receipt for customer-delta in their own tenant, got %', v_count;
  end if;
end $$;

\echo '>> raw-table RLS defense-in-depth: app.finance_receipts/app.finance_receipt_allocations/app.finance_ar_open_items are UNCHANGED by this migration -- already denied to a customer_user actor outright, re-confirmed live here rather than assumed from each table''s own text'
do $$
declare
  v_raw_receipt_count integer;
  v_raw_allocation_count integer;
  v_raw_ar_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000325010", "role": "authenticated"}';

  select count(*) into v_raw_receipt_count from app.finance_receipts;
  if v_raw_receipt_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.finance_receipts to be denied outright for a customer_user actor, got %', v_raw_receipt_count;
  end if;

  select count(*) into v_raw_allocation_count from app.finance_receipt_allocations;
  if v_raw_allocation_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.finance_receipt_allocations to be denied outright for a customer_user actor, got %', v_raw_allocation_count;
  end if;

  select count(*) into v_raw_ar_count from app.finance_ar_open_items;
  if v_raw_ar_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.finance_ar_open_items to be denied outright for a customer_user actor, got %', v_raw_ar_count;
  end if;

  reset role;
end $$;

\echo '>> raw-function grant defense in depth: anon holds no EXECUTE on either new public function; authenticated/service_role both do'
do $$
declare
  v_fn text;
  v_has_priv boolean;
begin
  foreach v_fn in array array[
    'app.get_customer_portal_payment_status(uuid, uuid, uuid)',
    'app.list_customer_portal_receipts(uuid, uuid, text, timestamptz, uuid, integer)'
  ] loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has_priv;
    if v_has_priv then
      raise exception 'assertion failed: anon must NOT hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('service_role', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: service_role SHOULD hold EXECUTE on %', v_fn;
    end if;
  end loop;
end $$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity, on both new RPCs (ATW-031/032 discipline, applied from the first draft)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpv1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000325010';
  v_impersonator uuid := '00000000-0000-0000-0000-000000325050';
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000325050", "role": "authenticated"}';

  begin
    perform app.get_customer_portal_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000325101');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_portal_payment_status -- the impersonator session may not claim to act as customer-alpha';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_receipts';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (no relationship to
  -- customer-alpha's own account) is not rejected by the identity check --
  -- it is correctly denied by the SCOPE check instead (record_not_found /
  -- zero rows), proving the identity check and the scope check are two
  -- independent gates.
  begin
    perform app.get_customer_portal_payment_status(v_tenant1, v_impersonator, '00000000-0000-0000-0000-000000325101');
    raise exception 'assertion failed: expected record_not_found -- the impersonator, acting as themselves, has no finance scope over Alpha''s invoice';
  exception when others then if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  reset role;
end $$;

\echo '>> a real, live authenticated-role positive path: customer-alpha''s own real authenticated session sees the exact same result a direct superuser call returns, on both new RPCs'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cpv1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000325010';
  v_superuser_count integer;
  v_session_count integer;
  v_superuser_status text;
  v_session_status text;
begin
  select count(*) into v_superuser_count from app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, null, null, null, 200);
  select payment_status into v_superuser_status from app.get_customer_portal_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000325101');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000325010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_receipts(v_tenant1, v_customer_alpha, null, null, null, 200);
  select payment_status into v_session_status from app.get_customer_portal_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000325101');
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero receipt count (%) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
  if v_session_status <> v_superuser_status or v_session_status is distinct from 'paid' then
    raise exception 'assertion failed: expected a real authenticated session to see the identical payment_status (%) a direct superuser call returns, got % via session', v_superuser_status, v_session_status;
  end if;
end $$;
