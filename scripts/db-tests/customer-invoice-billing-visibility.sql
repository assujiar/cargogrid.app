-- Real, executable test evidence for CPL-311 (CG-S13-CPL-013, Prompt 311,
-- "Invoice and Billing Visibility") -- run via `pnpm run db:test` against a
-- real, disposable Postgres database. Structural convention mirrors
-- scripts/db-tests/customer-warehouse-order-visibility.sql (CPL-310) and
-- scripts/db-tests/ticketing-linked-records.sql's own established "direct
-- fixture insert through the full Commercial->Operations->Finance chain,
-- bypassing staff RBAC plumbing not under test here" convention.
--
-- UUID range 00000000-0000-0000-0000-000000322xxx (tenant cib1) /
-- 00000000-0000-0000-0000-000000324xxx (tenant cib2), grep-verified unclaimed
-- against every other file in this directory before writing this fixture.
--
-- Covers, live: (a) cross-tenant/cross-account isolation; (b) draft/
-- submitted/approved invoices are correctly invisible to the customer while
-- issued/void are visible, both on the get and list RPCs; (c) no GL/journal/
-- margin/internal-linkage field (company_id/job_order_id/billing_readiness_
-- handoff_id/posting_period_id/ar_open_item_id/tax_code_id/tax_rule_version_
-- id) ever appears in any projection, structurally (to_jsonb key check on
-- the actual returned row, not merely a static read of the migration's own
-- column list); (d) anti-enumeration -- a real-but-not-yet-issued invoice, a
-- forbidden-but-existing invoice, and a genuinely nonexistent one all raise
-- the identical record_not_found; (e) cursor pagination correctness across
-- the account's own 4 issued/void invoices; (f) status-filter correctness,
-- including an excluded-by-design status value (e.g. 'draft') matching zero
-- rows, never an error; (g) app.get_customer_portal_invoice_payment_status'
-- own partial/paid/open+held/not_posted shapes, sourced live from app.
-- finance_ar_open_items; (h) raw-table RLS defense-in-depth (app.finance_
-- invoices/app.finance_invoice_lines/app.finance_ar_open_items are UNCHANGED
-- by this migration, already denied a customer_user actor outright); (i)
-- raw-function grant defense in depth (anon denied, authenticated/
-- service_role granted, the private helper granted to service_role only);
-- (j) the actor-identity session cross-check on every public RPC; (k) a
-- real, live authenticated-role positive path.

\set ON_ERROR_STOP on

-- A plain, top-level, temporary test helper -- PL/pgSQL does not allow a
-- nested procedure/function declaration inside a DO block's own DECLARE
-- section, so this mirrors scripts/db-tests/ticketing-escalation.sql's own
-- established "create a real app.* function for this file's own fixture
-- need, drop it once the fixture is built" convention (that file's own
-- app.plt132to_sentinel_delay, created then dropped in the same way).
-- Reduces the lead->prospect->opportunity->quotation->job_order_handoff->
-- job_order->billing_readiness_evaluation chain (identical shape to
-- scripts/db-tests/ticketing-linked-records.sql's own established fixture)
-- to one call per account instead of copy-pasting it 3 times.
create function app._cib_test_make_chain(p_tenant uuid, p_company uuid, p_account uuid, p_tag text, p_actor uuid)
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
  values (gen_random_uuid(), p_tenant, 'referral', p_tag || ' Lead', p_tag || '-lead@cib.test', 'fp-cib-' || p_tag || '-lead', 'qualified', 'tester')
  returning id into v_lead;
  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  values (gen_random_uuid(), p_tenant, v_lead, p_tag || ' Prospect Co', 'fp-cib-' || p_tag || '-prospect', p_tag || ' Contact', 'active', 'tester')
  returning id into v_prospect;
  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  values (gen_random_uuid(), p_tenant, v_prospect, p_tag || ' Opportunity', 'ready_for_costing', 'tester')
  returning id into v_opportunity;
  v_quotation := gen_random_uuid();
  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, status, root_quotation_id, created_by)
  values (v_quotation, p_tenant, 'QUO-CIB-' || p_tag, v_opportunity, 1, v_prospect, 'USD', now() + interval '30 days', 'submitted', v_quotation, 'tester');
  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, org_unit_id, created_by)
  values (gen_random_uuid(), p_tenant, v_quotation, p_account, '{"note": "cib fixture"}'::jsonb, 'hash-cib-' || p_tag, p_actor, p_company, 'tester')
  returning id into v_handoff;
  insert into app.job_orders (
    id, tenant_id, job_number, source_handoff_id, quotation_id, account_id,
    customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot,
    status, owner_user_id, org_unit_id, created_by
  ) values (
    gen_random_uuid(), p_tenant, 'JOB-CIB-' || p_tag, v_handoff, v_quotation, p_account,
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

\echo '>> setup: tenant cib1 (accounts Alpha/Beta, company Cib1 Co), tenant cib2 (account Delta) -- one lead->prospect->opportunity->quotation->job_order_handoff->job_order->billing_readiness_evaluation chain per account, then MULTIPLE billing_readiness_handoffs off the SAME job_order (Alpha: 7, Beta/Delta: 1 each), each producing one directly-inserted app.finance_invoices row (bypasses app.prepare_finance_invoice_from_readiness/app.issue_finance_invoice -- neither is under test here, only the customer-portal READ layer is)'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_delta uuid;
  v_supreme uuid := '00000000-0000-0000-0000-000000322001';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000322010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000322020';
  v_customer_badref uuid := '00000000-0000-0000-0000-000000322030';
  v_impersonator uuid := '00000000-0000-0000-0000-000000322050';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000324010';
  v_job_order_alpha uuid;
  v_job_order_beta uuid;
  v_job_order_delta uuid;
  v_eval_alpha uuid;
  v_eval_beta uuid;
  v_eval_delta uuid;
begin
  insert into auth.users (id, email) values
    (v_supreme, 'supreme@cib.test'),
    (v_customer_alpha, 'customer-alpha@cib1.test'),
    (v_customer_beta, 'customer-beta@cib1.test'),
    (v_customer_badref, 'customer-badref@cib1.test'),
    (v_impersonator, 'impersonator@cib1.test'),
    (v_customer_delta, 'customer-delta@cib2.test');

  perform app.grant_principal_membership(v_supreme, 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('cib1', 'Customer Invoice Billing Tenant One', 'idem-cib1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'cib1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'CIB1-CO', 'Cib1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'CIB1-CO');

  perform app.provision_tenant('cib2', 'Customer Invoice Billing Tenant Two', 'idem-cib2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'cib2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'CIB2-CO', 'Cib2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'CIB2-CO');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cib Account Alpha', 'cib-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Cib Account Beta', 'cib-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Cib Account Delta', 'cib-delta-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_delta;

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@cib1.test', 'Cib Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@cib1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@cib1.test', 'Cib Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@cib1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  -- customer-badref: a non-uuid-shaped legacy customer_account_ref -- must
  -- resolve to an EMPTY scope, never an error.
  perform app.invite_user(v_tenant1, v_customer_badref, 'customer-badref@cib1.test', 'Cib Customer Badref', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-badref@cib1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_badref, 'customer_user', v_tenant1, 'LEGACY-CIB-0007', 'tester');

  -- impersonator: a real, active tenant1 identity with ZERO customer_user
  -- grant of any kind -- used only for the actor-identity session cross-check.
  perform app.invite_user(v_tenant1, v_impersonator, 'impersonator@cib1.test', 'Cib Impersonator', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@cib1.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, v_customer_delta, 'customer-delta@cib2.test', 'Cib Customer Delta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-delta@cib2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_delta, 'customer_user', v_tenant2, v_account_delta::text, 'tester');

  select job_order_id, eval_id into v_job_order_alpha, v_eval_alpha from app._cib_test_make_chain(v_tenant1, v_company1, v_account_alpha, 'ALPHA', v_supreme);
  select job_order_id, eval_id into v_job_order_beta, v_eval_beta from app._cib_test_make_chain(v_tenant1, v_company1, v_account_beta, 'BETA', v_supreme);
  select job_order_id, eval_id into v_job_order_delta, v_eval_delta from app._cib_test_make_chain(v_tenant2, v_company2, v_account_delta, 'DELTA', v_supreme);

  -- 7 billing_readiness_handoffs off the SAME Alpha job_order (no
  -- uniqueness constraint besides (tenant_id, job_order_id,
  -- idempotency_key) forces this), one per Alpha invoice fixture below.
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by) values
    ('00000000-0000-0000-0000-000000322201', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cib-br-draft', v_supreme, 'tester'),
    ('00000000-0000-0000-0000-000000322202', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cib-br-submitted', v_supreme, 'tester'),
    ('00000000-0000-0000-0000-000000322203', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cib-br-approved', v_supreme, 'tester'),
    ('00000000-0000-0000-0000-000000322204', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cib-br-issued1', v_supreme, 'tester'),
    ('00000000-0000-0000-0000-000000322205', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cib-br-issued2', v_supreme, 'tester'),
    ('00000000-0000-0000-0000-000000322206', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cib-br-issued3', v_supreme, 'tester'),
    ('00000000-0000-0000-0000-000000322207', v_tenant1, v_job_order_alpha, v_eval_alpha, 'idem-cib-br-void', v_supreme, 'tester');
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by) values
    ('00000000-0000-0000-0000-000000322220', v_tenant1, v_job_order_beta, v_eval_beta, 'idem-cib-br-beta', v_supreme, 'tester');
  insert into app.billing_readiness_handoffs (id, tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by) values
    ('00000000-0000-0000-0000-000000324201', v_tenant2, v_job_order_delta, v_eval_delta, 'idem-cib-br-delta', v_supreme, 'tester');

  -- AR open items -- inserted BEFORE their own referencing invoice row (no
  -- FK from finance_ar_open_items.source_document_id to any table, so
  -- ordering is free; done this way so each invoice's own INSERT can set
  -- ar_open_item_id directly rather than a follow-up UPDATE).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000322304', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000322104', 'USD', 1100, 700, 'partial', false, '2026-07-01', '2026-07-31', 'tester'),
    ('00000000-0000-0000-0000-000000322305', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000322105', 'USD', 200, 200, 'paid', false, '2026-08-10', '2026-09-09', 'tester'),
    ('00000000-0000-0000-0000-000000322306', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000322106', 'USD', 50, 0, 'open', true, '2026-08-05', '2026-09-04', 'tester');
  update app.finance_ar_open_items set hold_reason = 'cib fixture dispute hold', held_by = 'tester', held_at = now() where id = '00000000-0000-0000-0000-000000322306';
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000322320', v_tenant1, v_account_beta, 'invoice', '00000000-0000-0000-0000-000000322120', 'USD', 900, 0, 'open', false, '2026-08-01', '2026-08-31', 'tester');
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000324301', v_tenant2, v_account_delta, 'invoice', '00000000-0000-0000-0000-000000324101', 'USD', 300, 0, 'open', false, '2026-08-01', '2026-08-31', 'tester');

  -- Alpha's 7 invoices -- 3 pre-issuance (never customer-visible), 3 issued
  -- (partial/paid/open+held), 1 void-before-ever-issued (customer-visible,
  -- payment_status must resolve to not_posted since ar_open_item_id is null).
  insert into app.finance_invoices (id, tenant_id, company_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, status, subtotal_amount, tax_amount, created_by) values
    ('00000000-0000-0000-0000-000000322101', v_tenant1, v_company1, null, v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000322201', 'USD', 'draft', 500, 0, 'tester'),
    ('00000000-0000-0000-0000-000000322102', v_tenant1, v_company1, null, v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000322202', 'USD', 'submitted', 500, 0, 'tester'),
    ('00000000-0000-0000-0000-000000322103', v_tenant1, v_company1, null, v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000322203', 'USD', 'approved', 500, 0, 'tester');
  insert into app.finance_invoices (id, tenant_id, company_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, status, subtotal_amount, tax_amount, issue_date, due_date, ar_open_item_id, issued_by, issued_at, created_by) values
    ('00000000-0000-0000-0000-000000322104', v_tenant1, v_company1, 'INV-CIB-000001', v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000322204', 'USD', 'issued', 1000, 100, '2026-07-01', '2026-07-31', '00000000-0000-0000-0000-000000322304', 'tester', now(), 'tester'),
    ('00000000-0000-0000-0000-000000322105', v_tenant1, v_company1, 'INV-CIB-000002', v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000322205', 'USD', 'issued', 200, 0, '2026-08-10', '2026-09-09', '00000000-0000-0000-0000-000000322305', 'tester', now(), 'tester'),
    ('00000000-0000-0000-0000-000000322106', v_tenant1, v_company1, 'INV-CIB-000003', v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000322206', 'USD', 'issued', 50, 0, '2026-08-05', '2026-09-04', '00000000-0000-0000-0000-000000322306', 'tester', now(), 'tester');
  insert into app.finance_invoices (id, tenant_id, company_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, status, subtotal_amount, tax_amount, void_reason, voided_by, voided_at, created_by) values
    ('00000000-0000-0000-0000-000000322107', v_tenant1, v_company1, null, v_account_alpha, v_job_order_alpha, '00000000-0000-0000-0000-000000322207', 'USD', 'void', 300, 0, 'cib fixture void before issuance', 'tester', now(), 'tester');

  insert into app.finance_invoices (id, tenant_id, company_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, status, subtotal_amount, tax_amount, issue_date, due_date, ar_open_item_id, issued_by, issued_at, created_by) values
    ('00000000-0000-0000-0000-000000322120', v_tenant1, v_company1, 'INV-CIB-BETA-0001', v_account_beta, v_job_order_beta, '00000000-0000-0000-0000-000000322220', 'USD', 'issued', 900, 0, '2026-08-01', '2026-08-31', '00000000-0000-0000-0000-000000322320', 'tester', now(), 'tester');

  insert into app.finance_invoices (id, tenant_id, company_id, invoice_number, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, status, subtotal_amount, tax_amount, issue_date, due_date, ar_open_item_id, issued_by, issued_at, created_by) values
    ('00000000-0000-0000-0000-000000324101', v_tenant2, v_company2, 'INV-CIB-DELTA-0001', v_account_delta, v_job_order_delta, '00000000-0000-0000-0000-000000324201', 'USD', 'issued', 300, 0, '2026-08-01', '2026-08-31', '00000000-0000-0000-0000-000000324301', 'tester', now(), 'tester');

  -- Lines for the 3 Alpha issued invoices -- INV-CIB-000001 gets both a
  -- charge and a tax line (tax_code_id deliberately null, the exclusion
  -- proof only depends on the RPC''s own RETURNS TABLE column list never
  -- including that column at all, not on the underlying value existing).
  insert into app.finance_invoice_lines (invoice_id, line_number, line_type, description, amount) values
    ('00000000-0000-0000-0000-000000322104', 1, 'charge', 'Freight and service charges', 1000),
    ('00000000-0000-0000-0000-000000322104', 2, 'tax', 'VAT tax', 100),
    ('00000000-0000-0000-0000-000000322105', 1, 'charge', 'Freight and service charges', 200),
    ('00000000-0000-0000-0000-000000322106', 1, 'charge', 'Freight and service charges', 50);
end $$;

-- Fixture-only helper, no longer needed once the chain rows above exist.
drop function if exists app._cib_test_make_chain(uuid, uuid, uuid, text, uuid);

\echo '>> app.get_customer_portal_invoice: draft/submitted/approved are invisible to Alpha''s own customer -- identical record_not_found to a genuinely fake id; issued/void ARE visible; cross-account (Beta) denied; structural field-leak check (never company_id/job_order_id/billing_readiness_handoff_id/posting_period_id/ar_open_item_id)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cib1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000322010';
  v_fake_id uuid := '77777777-7777-7777-7777-777777777777';
  v_row record;
  v_row_json jsonb;
  v_msg_draft text;
  v_msg_submitted text;
  v_msg_approved text;
  v_msg_beta text;
  v_msg_fake text;
  v_internal_only_fields text[] := array['company_id', 'job_order_id', 'billing_readiness_handoff_id', 'posting_period_id', 'ar_open_item_id', 'void_reason', 'voided_by', 'voided_at', 'submitted_by', 'approved_by', 'issued_by', 'created_by', 'customer_account_id'];
begin
  -- Issued invoice succeeds with the full customer-safe projection.
  select * into v_row from app.get_customer_portal_invoice(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322104');
  if v_row.id <> '00000000-0000-0000-0000-000000322104' or v_row.status <> 'issued' or v_row.invoice_number <> 'INV-CIB-000001' or v_row.total_amount <> 1100 then
    raise exception 'assertion failed: expected Alpha''s own issued invoice with total_amount=1100, got %', v_row;
  end if;
  v_row_json := to_jsonb(v_row);
  if v_row_json ?| v_internal_only_fields then
    raise exception 'assertion failed: app.get_customer_portal_invoice leaked an internal-only field, got keys %', (select array_agg(k) from jsonb_object_keys(v_row_json) k);
  end if;

  -- The void-before-ever-issued invoice IS visible (design decision 4).
  select * into v_row from app.get_customer_portal_invoice(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322107');
  if v_row.id <> '00000000-0000-0000-0000-000000322107' or v_row.status <> 'void' or v_row.invoice_number is not null then
    raise exception 'assertion failed: expected the void-before-issuance invoice to be visible with a null invoice_number, got %', v_row;
  end if;

  begin
    perform app.get_customer_portal_invoice(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322101');
    raise exception 'assertion failed: expected record_not_found -- a draft invoice must never be customer-visible';
  exception when others then v_msg_draft := sqlerrm; if v_msg_draft not like 'record_not_found%' then raise; end if;
  end;
  begin
    perform app.get_customer_portal_invoice(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322102');
    raise exception 'assertion failed: expected record_not_found -- a submitted invoice must never be customer-visible';
  exception when others then v_msg_submitted := sqlerrm; if v_msg_submitted not like 'record_not_found%' then raise; end if;
  end;
  begin
    perform app.get_customer_portal_invoice(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322103');
    raise exception 'assertion failed: expected record_not_found -- an approved invoice must never be customer-visible';
  exception when others then v_msg_approved := sqlerrm; if v_msg_approved not like 'record_not_found%' then raise; end if;
  end;
  begin
    perform app.get_customer_portal_invoice(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322120');
    raise exception 'assertion failed: expected record_not_found -- Alpha must not see Beta''s own invoice';
  exception when others then v_msg_beta := sqlerrm; if v_msg_beta not like 'record_not_found%' then raise; end if;
  end;
  begin
    perform app.get_customer_portal_invoice(v_tenant1, v_customer_alpha, v_fake_id);
    raise exception 'assertion failed: expected record_not_found -- a genuinely nonexistent id';
  exception when others then v_msg_fake := sqlerrm; if v_msg_fake not like 'record_not_found%' then raise; end if;
  end;

  if left(v_msg_draft, 16) <> left(v_msg_fake, 16) or left(v_msg_submitted, 16) <> left(v_msg_fake, 16)
     or left(v_msg_approved, 16) <> left(v_msg_fake, 16) or left(v_msg_beta, 16) <> left(v_msg_fake, 16) then
    raise exception 'assertion failed: expected pre-issuance/cross-account/nonexistent to all raise the IDENTICAL anti-enumerating message prefix, got % / % / % / % / %', v_msg_draft, v_msg_submitted, v_msg_approved, v_msg_beta, v_msg_fake;
  end if;
end $$;

\echo '>> app.get_customer_portal_invoice_lines: own issued invoice''s lines succeed (charge + tax), a forbidden invoice raises the IDENTICAL record_not_found; structural check -- never tax_code_id/tax_rule_version_id'
do $$
declare
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000322010';
  v_count integer;
  v_row record;
  v_row_json jsonb;
begin
  select count(*) into v_count from app.get_customer_portal_invoice_lines((select id from app.tenants where slug = 'cib1'), v_customer_alpha, '00000000-0000-0000-0000-000000322104');
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 lines (charge + tax) for INV-CIB-000001, got %', v_count;
  end if;

  select * into v_row from app.get_customer_portal_invoice_lines((select id from app.tenants where slug = 'cib1'), v_customer_alpha, '00000000-0000-0000-0000-000000322104') where line_number = 2;
  if v_row.line_type <> 'tax' or v_row.amount <> 100 then
    raise exception 'assertion failed: expected line 2 to be the tax line with amount=100, got %', v_row;
  end if;
  v_row_json := to_jsonb(v_row);
  if v_row_json ? 'tax_code_id' or v_row_json ? 'tax_rule_version_id' or v_row_json ? 'invoice_id' or v_row_json ? 'id' then
    raise exception 'assertion failed: app.get_customer_portal_invoice_lines leaked an internal-only field, got keys %', (select array_agg(k) from jsonb_object_keys(v_row_json) k);
  end if;

  begin
    perform app.get_customer_portal_invoice_lines((select id from app.tenants where slug = 'cib1'), v_customer_alpha, '00000000-0000-0000-0000-000000322120');
    raise exception 'assertion failed: expected record_not_found from get_customer_portal_invoice_lines on Beta''s own invoice';
  exception when others then if sqlerrm not like 'record_not_found%' then raise; end if;
  end;
end $$;

\echo '>> app.get_customer_portal_invoice_payment_status: partial/paid/open+held/not_posted all resolve correctly from app.finance_ar_open_items, live; structural check -- never exposes ar_open_item_id'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cib1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000322010';
  v_row record;
  v_row_json jsonb;
begin
  select * into v_row from app.get_customer_portal_invoice_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322104');
  if v_row.payment_status <> 'partial' or v_row.original_amount <> 1100 or v_row.open_amount <> 400 or v_row.is_held is distinct from false then
    raise exception 'assertion failed: expected INV-CIB-000001 payment_status=partial, open_amount=400 (1100-700), got %', v_row;
  end if;
  v_row_json := to_jsonb(v_row);
  if v_row_json ? 'ar_open_item_id' or v_row_json ? 'id' or v_row_json ? 'customer_account_id' then
    raise exception 'assertion failed: app.get_customer_portal_invoice_payment_status leaked an internal-only field, got keys %', (select array_agg(k) from jsonb_object_keys(v_row_json) k);
  end if;

  select * into v_row from app.get_customer_portal_invoice_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322105');
  if v_row.payment_status <> 'paid' or v_row.open_amount <> 0 then
    raise exception 'assertion failed: expected INV-CIB-000002 payment_status=paid, open_amount=0, got %', v_row;
  end if;

  select * into v_row from app.get_customer_portal_invoice_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322106');
  if v_row.payment_status <> 'open' or v_row.is_held is distinct from true then
    raise exception 'assertion failed: expected INV-CIB-000003 payment_status=open, is_held=true, got %', v_row;
  end if;

  -- void-before-ever-issued: ar_open_item_id is null -- the synthesized
  -- not_posted row, never a fabricated zero.
  select * into v_row from app.get_customer_portal_invoice_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322107');
  if v_row.payment_status <> 'not_posted' or v_row.original_amount is not null or v_row.open_amount is not null or v_row.is_held is not null then
    raise exception 'assertion failed: expected the void-before-issuance invoice to resolve payment_status=not_posted with NULL amounts, got %', v_row;
  end if;
end $$;

\echo '>> app.list_customer_portal_invoices: Alpha sees exactly its own 4 issued/void invoices (never the 3 pre-issuance ones, never Beta''s), status filter correctness (including an excluded-by-design status matching zero rows), cursor pagination terminates cleanly'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cib1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000322010';
  v_count integer;
  v_row record;
  v_seen_ids uuid[] := array[]::uuid[];
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page_count integer;
  v_total_pages integer := 0;
begin
  select count(*) into v_count from app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, null, null, null, 200);
  if v_count <> 4 then
    raise exception 'assertion failed: expected exactly 4 (3 issued + 1 void) invoices for Alpha, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, 'issued', null, null, 200);
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 issued invoices for Alpha, got %', v_count;
  end if;

  select count(*) into v_count from app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, 'void', null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 void invoice for Alpha, got %', v_count;
  end if;

  -- 'draft' is a real database status value but excluded-by-design from the
  -- customer projection entirely -- must match zero rows, never an error
  -- (mirrors app.list_customer_portal_outbound_orders' own established
  -- non-validating-filter shape).
  select count(*) into v_count from app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, 'draft', null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for the excluded-by-design draft filter, got %', v_count;
  end if;

  -- Cross-account: Alpha's own list never contains Beta's invoice.
  select count(*) into v_count from app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, null, null, null, 200) v where v.id = '00000000-0000-0000-0000-000000322120';
  if v_count <> 0 then
    raise exception 'assertion failed: expected Beta''s own invoice to never appear in Alpha''s list, got %', v_count;
  end if;

  -- Cursor pagination: p_limit=1 across the 4 own invoices must yield 4
  -- distinct pages that together cover all 4 rows exactly once, then terminate.
  loop
    v_page_count := 0;
    for v_row in select * from app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, null, v_cursor_updated_at, v_cursor_id, 1) loop
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
  if v_total_pages <> 4 or array_length(v_seen_ids, 1) <> 4 then
    raise exception 'assertion failed: expected exactly 4 pages of 1 row each covering 4 distinct rows, got % pages / % rows', v_total_pages, array_length(v_seen_ids, 1);
  end if;

  -- Half-supplied cursor fails loud.
  begin
    perform app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, null, null, gen_random_uuid(), 50);
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_updated_at';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;

  -- An identity with an empty resolved scope (non-uuid legacy ref) sees zero rows, never an error.
  select count(*) into v_count from app.list_customer_portal_invoices(v_tenant1, '00000000-0000-0000-0000-000000322030', null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for the empty-scope (non-uuid customer_account_ref) actor, got %', v_count;
  end if;
end $$;

\echo '>> cross-tenant isolation: customer-delta (tenant cib2) sees ZERO of tenant cib1''s invoices when probing with tenant1''s own id; sees exactly their own 1 invoice in their own tenant'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cib1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'cib2');
  v_customer_delta uuid := '00000000-0000-0000-0000-000000324010';
  v_count integer;
  v_row record;
begin
  select count(*) into v_count from app.list_customer_portal_invoices(v_tenant1, v_customer_delta, null, null, null, 200);
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a genuinely cross-tenant identity probing tenant1 with tenant1''s own id, got %', v_count;
  end if;

  begin
    perform app.get_customer_portal_invoice(v_tenant1, v_customer_delta, '00000000-0000-0000-0000-000000322104');
    raise exception 'assertion failed: expected record_not_found -- customer-delta must not read tenant1''s own Alpha invoice even by cross-tenant guess';
  exception when others then if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  select * into v_row from app.get_customer_portal_invoice(v_tenant2, v_customer_delta, '00000000-0000-0000-0000-000000324101');
  if v_row.id <> '00000000-0000-0000-0000-000000324101' or v_row.status <> 'issued' then
    raise exception 'assertion failed: expected customer-delta to see their own real, issued invoice in tenant2, got %', v_row;
  end if;

  select count(*) into v_count from app.list_customer_portal_invoices(v_tenant2, v_customer_delta, null, null, null, 200);
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 invoice for customer-delta in their own tenant, got %', v_count;
  end if;
end $$;

\echo '>> raw-table RLS defense-in-depth: app.finance_invoices/app.finance_invoice_lines/app.finance_ar_open_items are UNCHANGED by this migration -- already denied to a customer_user actor outright (has_active_tenant_membership(tenant_id) or is_supreme_admin() only, no owner/customer branch), re-confirmed live here rather than assumed from each table''s own text'
do $$
declare
  v_raw_invoice_count integer;
  v_raw_line_count integer;
  v_raw_ar_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000322010", "role": "authenticated"}';

  select count(*) into v_raw_invoice_count from app.finance_invoices;
  if v_raw_invoice_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.finance_invoices to be denied outright for a customer_user actor, got %', v_raw_invoice_count;
  end if;

  select count(*) into v_raw_line_count from app.finance_invoice_lines where invoice_id = '00000000-0000-0000-0000-000000322104';
  if v_raw_line_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.finance_invoice_lines to be denied outright for a customer_user actor, even for their own invoice''s lines, got %', v_raw_line_count;
  end if;

  select count(*) into v_raw_ar_count from app.finance_ar_open_items;
  if v_raw_ar_count <> 0 then
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.finance_ar_open_items to be denied outright for a customer_user actor, got %', v_raw_ar_count;
  end if;

  reset role;
end $$;

\echo '>> raw-function grant defense in depth: anon holds no EXECUTE on any new public function; authenticated/service_role both do; the internal helper app._resolve_customer_portal_invoice is service_role only, never authenticated or anon'
do $$
declare
  v_fn text;
  v_has_priv boolean;
begin
  foreach v_fn in array array[
    'app.evaluate_customer_portal_invoice_access(uuid, uuid, uuid)',
    'app.get_customer_portal_invoice(uuid, uuid, uuid)',
    'app.list_customer_portal_invoices(uuid, uuid, text, timestamptz, uuid, integer)',
    'app.get_customer_portal_invoice_lines(uuid, uuid, uuid)',
    'app.get_customer_portal_invoice_payment_status(uuid, uuid, uuid)'
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

  select has_function_privilege('authenticated', 'app._resolve_customer_portal_invoice(uuid, uuid, uuid)', 'EXECUTE') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: authenticated must NOT hold EXECUTE on the internal-only app._resolve_customer_portal_invoice';
  end if;
  select has_function_privilege('anon', 'app._resolve_customer_portal_invoice(uuid, uuid, uuid)', 'EXECUTE') into v_has_priv;
  if v_has_priv then
    raise exception 'assertion failed: anon must NOT hold EXECUTE on the internal-only app._resolve_customer_portal_invoice';
  end if;
  select has_function_privilege('service_role', 'app._resolve_customer_portal_invoice(uuid, uuid, uuid)', 'EXECUTE') into v_has_priv;
  if not v_has_priv then
    raise exception 'assertion failed: service_role SHOULD hold EXECUTE on app._resolve_customer_portal_invoice';
  end if;
end $$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity, on every new RPC (ATW-031/032 discipline, applied here from the first draft -- the single most common Critical defect class across Phase 8 so far)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cib1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000322010';
  v_impersonator uuid := '00000000-0000-0000-0000-000000322050';
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000322050", "role": "authenticated"}';

  begin
    perform app.get_customer_portal_invoice(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322104');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_portal_invoice -- the impersonator session may not claim to act as customer-alpha';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, null, null, null, 50);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_invoices';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.get_customer_portal_invoice_lines(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322104');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_portal_invoice_lines';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.get_customer_portal_invoice_payment_status(v_tenant1, v_customer_alpha, '00000000-0000-0000-0000-000000322104');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_customer_portal_invoice_payment_status';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  begin
    perform app.evaluate_customer_portal_invoice_access(v_customer_alpha, v_tenant1, '00000000-0000-0000-0000-000000322104');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.evaluate_customer_portal_invoice_access itself -- must not rely solely on a transitive check';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (no relationship to
  -- customer-alpha's own account) is not rejected by the identity check --
  -- it is correctly denied by the SCOPE check instead (record_not_found),
  -- proving the identity check and the scope check are two independent gates.
  begin
    perform app.get_customer_portal_invoice(v_tenant1, v_impersonator, '00000000-0000-0000-0000-000000322104');
    raise exception 'assertion failed: expected record_not_found -- the impersonator, acting as themselves, has no finance scope over Alpha''s invoice';
  exception when others then if sqlerrm not like 'record_not_found%' then raise; end if;
  end;

  reset role;
end $$;

\echo '>> a real, live authenticated-role positive path: customer-alpha''s own real authenticated session sees the exact same result a direct superuser call returns'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'cib1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000322010';
  v_superuser_count integer;
  v_session_count integer;
begin
  select count(*) into v_superuser_count from app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, null, null, null, 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000322010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_invoices(v_tenant1, v_customer_alpha, null, null, null, 200);
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero row count (%) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
end $$;
