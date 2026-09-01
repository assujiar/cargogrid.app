-- Real, executable test evidence for FIN-211 (Cash and Bank Baseline,
-- CG-S9-FIN-022) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: bank-account creation authority/validation (Plain User denied,
-- unsupported currency, unknown/not-postable GL account); idempotent
-- statement import on (tenant, bank_account, source_reference); real
-- per-line deduplication via the database's own unique index (a
-- duplicate line inside a re-imported statement is silently skipped, the
-- returned batch's own line_count reflects only real inserts); match/
-- unmatch authority split and validation; a real posted receipt
-- allocation (debiting the shared cash_default-mapped account) makes the
-- cash position's own GL balance match a matching bank transaction's own
-- statement balance; cross-tenant isolation; schema-privilege defense in
-- depth; audit trail.

\set ON_ERROR_STOP on

-- ISS-2026-319 fixture helpers (docs/runtime/KNOWN_ISSUES.md). The new
-- app.validate_finance_open_item_source guard (20260901060000) now rejects a
-- fabricated source_document_id on app.finance_ar_open_items, so this file's
-- own direct app.post_finance_ar_open_item call below can no longer pass
-- gen_random_uuid() and expect it to be accepted. These pg_temp functions mint
-- a genuinely real, minimal app.finance_invoices row via direct INSERT rather
-- than the full Commercial->Operations RPC pipeline -- the same "direct fixture
-- insert, out of scope for this capability's own test" convention this file
-- already uses for its own minimal app.accounts row elsewhere, extended one
-- layer deeper because the new guard now checks one layer deeper. pg_temp is
-- session-scoped, matching scripts/db-tests/run.sh's one-psql-connection-per-file
-- execution model, so these are defined once and reused by every DO block below.

create function pg_temp.iss319_build_job_order(p_tenant_id uuid, p_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_seed text)
returns uuid
language plpgsql
as $fn$
declare
  v_lead_id uuid;
  v_prospect_id uuid;
  v_opportunity_id uuid;
  v_opp_version integer;
  v_quotation_id uuid := gen_random_uuid();
  v_joh_id uuid;
  v_job_order_id uuid;
begin
  insert into app.leads (tenant_id, source, contact_name, email, created_by)
  values (p_tenant_id, 'manual', p_seed, p_seed || '@iss319-fixture.test', p_actor_label)
  returning id into v_lead_id;

  insert into app.prospects (tenant_id, lead_id, legal_name, contact_name, created_by)
  values (p_tenant_id, v_lead_id, p_seed || ' Co', p_seed, p_actor_label)
  returning id into v_prospect_id;

  insert into app.opportunities (tenant_id, prospect_id, name, created_by)
  values (p_tenant_id, v_prospect_id, p_seed || ' opportunity', p_actor_label)
  returning id, record_version into v_opportunity_id, v_opp_version;

  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, root_quotation_id, created_by)
  values (v_quotation_id, p_tenant_id, p_seed || '-QUOTE', v_opportunity_id, v_opp_version, v_prospect_id, 'USD', now() + interval '30 days', v_quotation_id, p_actor_label);

  insert into app.job_order_handoffs (tenant_id, quotation_id, account_id, payload, payload_hash, prepared_by_auth_user_id, created_by)
  values (p_tenant_id, v_quotation_id, p_account_id, '{}'::jsonb, 'iss319-fixture-hash', p_actor_auth_user_id, p_actor_label)
  returning id into v_joh_id;

  insert into app.job_orders (tenant_id, job_number, source_handoff_id, quotation_id, account_id, customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot, created_by)
  values (p_tenant_id, p_seed || '-JOB', v_joh_id, v_quotation_id, p_account_id, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, p_actor_label)
  returning id into v_job_order_id;

  return v_job_order_id;
end;
$fn$;

-- Mints one real, minimal (draft, never issued -- so it never posts its own AR
-- open item) app.finance_invoices row and returns its id, so a direct
-- app.post_finance_ar_open_item(..., 'invoice', <this id>, ...) call below
-- resolves against a genuinely existing invoice instead of a fabricated one.
create function pg_temp.iss319_mint_invoice(p_tenant_id uuid, p_account_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_seed text)
returns uuid
language plpgsql
as $fn$
declare
  v_job_order_id uuid;
  v_eval_id uuid;
  v_handoff_id uuid;
  v_invoice_id uuid;
begin
  v_job_order_id := pg_temp.iss319_build_job_order(p_tenant_id, p_account_id, p_actor_auth_user_id, p_actor_label, p_seed);

  insert into app.billing_readiness_evaluations (tenant_id, job_order_id, evaluated_status, is_overridden, override_reason, overridden_by_auth_user_id, overridden_by, evaluated_by_auth_user_id, evaluated_by, created_by)
  values (p_tenant_id, v_job_order_id, 'not_ready', true, 'ISS-2026-319 fixture: minted so the new source-lineage guard has a real invoice to resolve', p_actor_auth_user_id, p_actor_label, p_actor_auth_user_id, p_actor_label, p_actor_label)
  returning id into v_eval_id;

  insert into app.billing_readiness_handoffs (tenant_id, job_order_id, evaluation_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by)
  values (p_tenant_id, v_job_order_id, v_eval_id, p_seed || '-handoff', p_actor_auth_user_id, p_actor_label)
  returning id into v_handoff_id;

  insert into app.finance_invoices (tenant_id, customer_account_id, job_order_id, billing_readiness_handoff_id, currency, created_by)
  values (p_tenant_id, p_account_id, v_job_order_id, v_handoff_id, 'USD', p_actor_label)
  returning id into v_invoice_id;

  return v_invoice_id;
end;
$fn$;

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets one open fiscal period (2026-08), a small real chart of accounts (including a non-postable control account), and a published finance_posting_map (cash_default, ar_control resolved) plus a customer account and one AR open item'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_editor_role_a uuid;
  v_editor_draft_a app.role_versions;
  v_manager_role_b uuid;
  v_manager_draft_b app.role_versions;
  v_cash_account app.finance_accounts;
  v_np_account app.finance_accounts;
  v_pm_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000036001', 'admina@acmecash.test'),
    ('00000000-0000-0000-0000-000000036002', 'financemanagera@acmecash.test'),
    ('00000000-0000-0000-0000-000000036003', 'financeeditora@acmecash.test'),
    ('00000000-0000-0000-0000-000000036004', 'plainusera@acmecash.test'),
    ('00000000-0000-0000-0000-000000036005', 'financemanagerb@acmecash.test');

  perform app.provision_tenant('acmecasha', 'Acme Cash A', 'idem-acmecasha', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmecasha');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMECASHA-CO', 'Acme Cash A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMECASHA-CO');

  perform app.provision_tenant('acmecashb', 'Acme Cash B', 'idem-acmecashb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmecashb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMECASHB-CO', 'Acme Cash B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMECASHB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000036001', 'admina@acmecash.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmecash.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000036001', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000036002', 'financemanagera@acmecash.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmecash.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000036002', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000036003', 'financeeditora@acmecash.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmecash.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Cash authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000036002', '00000000-0000-0000-0000-000000036001', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000036003', '00000000-0000-0000-0000-000000036001', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000036004', 'plainusera@acmecash.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmecash.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000036005', 'financemanagerb@acmecash.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmecash.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Cash authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000036005', '00000000-0000-0000-0000-000000036005', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 12, '00000000-0000-0000-0000-000000036002', 'financemanagera');

  select * into v_cash_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-BANK', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000036002', 'financemanagera');
  perform app.activate_finance_account(v_cash_account.id, v_cash_account.record_version, '00000000-0000-0000-0000-000000036002', 'financemanagera');
  select * into v_np_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-CONTROL-NP', 'Non-Postable Cash Control', 'asset', 'debit', null, true, null, '00000000-0000-0000-0000-000000036002', 'financemanagera');
  perform app.activate_finance_account(v_np_account.id, v_np_account.record_version, '00000000-0000-0000-0000-000000036002', 'financemanagera');
  perform app.create_finance_account_draft(v_tenant_a, null, 'AR-CASHBANK', 'Accounts Receivable', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000036002', 'financemanagera');
  perform app.activate_finance_account((select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'AR-CASHBANK'), 1, '00000000-0000-0000-0000-000000036002', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000036002', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'CASH-BANK')),
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CASHBANK'))
  ), '00000000-0000-0000-0000-000000036002', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000036002', null, 'financemanagera');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant_a, 'Acme Cash Customer Pte Ltd', 'acmecash-customer-fixture-fingerprint', '{}'::jsonb, v_team_a, 'tester');
end;
$$;

\echo '>> bank-account creation: Plain User A is denied; an unsupported currency and a not-postable GL account are each rejected'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_np_id uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecasha');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-BANK');
  v_np_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-CONTROL-NP');

  begin
    perform app.create_finance_bank_account(v_tenant_a, null, 'Main Operating', 'Acme Bank', '1234', 'USD', v_cash_id, '00000000-0000-0000-0000-000000036004', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.create_finance_bank_account(v_tenant_a, null, 'Main Operating', 'Acme Bank', '1234', 'ZZZ', v_cash_id, '00000000-0000-0000-0000-000000036002', 'financemanagera');
    raise exception 'assertion failed: expected finance_cash_unsupported_currency';
  exception
    when others then
      if sqlerrm !~ 'finance_cash_unsupported_currency' then
        raise exception 'assertion failed: expected finance_cash_unsupported_currency, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_bank_account(v_tenant_a, null, 'Main Operating', 'Acme Bank', '1234', 'USD', v_np_id, '00000000-0000-0000-0000-000000036002', 'financemanagera');
    raise exception 'assertion failed: expected finance_cash_gl_account_not_postable';
  exception
    when others then
      if sqlerrm !~ 'finance_cash_gl_account_not_postable' then
        raise exception 'assertion failed: expected finance_cash_gl_account_not_postable, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> idempotent statement import; real per-line deduplication via the unique index (a re-imported statement carrying an overlapping line inserts only the genuinely new one); match/unmatch authority split and validation'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_account app.finance_bank_accounts;
  v_batch app.finance_bank_statement_batches;
  v_retry app.finance_bank_statement_batches;
  v_second_batch app.finance_bank_statement_batches;
  v_transaction app.finance_bank_transactions;
  v_real_receipt app.finance_receipts;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecasha');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-BANK');

  -- ISS-2026-206: a REAL receipt, because the successful match below now has to resolve. This
  -- fixture previously matched against gen_random_uuid() -- which is precisely the orphan the
  -- new guard exists to reject, so leaving it would have been testing the bug. Captured with
  -- the same app.capture_finance_receipt call this file already uses further down, against the
  -- customer account the fixture already has: a real id, not a workaround for the guard.
  select * into v_real_receipt from app.capture_finance_receipt(
    v_tenant_a, null, (select id from app.accounts where tenant_id = v_tenant_a), 'BANKREF-MATCH-1',
    '2026-08-01'::date, 'Acme Cash Customer Pte Ltd', 'Main Operating', 'USD', 500, 'receipt-bankmatch-1',
    '00000000-0000-0000-0000-000000036002', 'financemanagera'
  );

  select * into v_account from app.create_finance_bank_account(v_tenant_a, null, 'Main Operating', 'Acme Bank', '1234', 'USD', v_cash_id, '00000000-0000-0000-0000-000000036002', 'financemanagera');

  select * into v_batch from app.import_finance_bank_statement(v_tenant_a, v_account.id, 'stmt-2026-08', jsonb_build_array(
    jsonb_build_object('transactionDate', '2026-08-01', 'direction', 'credit', 'amount', 500, 'reference', 'REF-1'),
    jsonb_build_object('transactionDate', '2026-08-02', 'direction', 'debit', 'amount', 100, 'reference', 'REF-2')
  ), '00000000-0000-0000-0000-000000036002', 'financemanagera');
  if v_batch.line_count <> 2 then
    raise exception 'assertion failed: expected 2 inserted lines, got %', v_batch.line_count;
  end if;

  select * into v_retry from app.import_finance_bank_statement(v_tenant_a, v_account.id, 'stmt-2026-08', jsonb_build_array(
    jsonb_build_object('transactionDate', '2026-08-01', 'direction', 'credit', 'amount', 500, 'reference', 'REF-1')
  ), '00000000-0000-0000-0000-000000036002', 'financemanagera');
  if v_retry.id <> v_batch.id then
    raise exception 'assertion failed: expected a retried import with the same source_reference to return the original batch unchanged';
  end if;

  select * into v_second_batch from app.import_finance_bank_statement(v_tenant_a, v_account.id, 'stmt-2026-08-part2', jsonb_build_array(
    jsonb_build_object('transactionDate', '2026-08-01', 'direction', 'credit', 'amount', 500, 'reference', 'REF-1'),
    jsonb_build_object('transactionDate', '2026-08-03', 'direction', 'credit', 'amount', 75, 'reference', 'REF-3')
  ), '00000000-0000-0000-0000-000000036002', 'financemanagera');
  if v_second_batch.line_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 genuinely new line in the second batch (REF-1 already exists, deduplicated), got %', v_second_batch.line_count;
  end if;

  if (select count(*) from app.finance_bank_transactions where bank_account_id = v_account.id) <> 3 then
    raise exception 'assertion failed: expected exactly 3 distinct transactions total across both batches (REF-1/REF-2/REF-3)';
  end if;

  select * into v_transaction from app.finance_bank_transactions where bank_account_id = v_account.id and reference = 'REF-1';

  begin
    perform app.match_finance_bank_transaction(v_transaction.id, v_transaction.record_version, 'receipt', null, '00000000-0000-0000-0000-000000036004', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A matching';
  exception
    when insufficient_privilege then
      null;
  end;

  -- ISS-2026-206: the orphan is now refused. A statement line matched to a receipt that never
  -- existed reads as SETTLED, so unlike an unmatched line nobody ever goes looking for it --
  -- which is why this is worse than a missing link, not a tidier version of one.
  begin
    perform app.match_finance_bank_transaction(v_transaction.id, v_transaction.record_version, 'receipt', gen_random_uuid(), '00000000-0000-0000-0000-000000036002', 'financemanagera');
    raise exception 'assertion failed: expected finance_bank_transaction_orphan_match_source for a receipt id matching no real app.finance_receipts row';
  exception
    when others then
      if sqlerrm !~ 'finance_bank_transaction_orphan_match_source' then
        raise exception 'assertion failed: expected finance_bank_transaction_orphan_match_source, got %', sqlerrm;
      end if;
  end;

  -- and a real one still matches cleanly -- the guard rejects fabrication, never legitimate use
  select * into v_transaction from app.finance_bank_transactions where id = v_transaction.id;
  perform app.match_finance_bank_transaction(v_transaction.id, v_transaction.record_version, 'receipt', v_real_receipt.id, '00000000-0000-0000-0000-000000036002', 'financemanagera');
  select * into v_transaction from app.finance_bank_transactions where id = v_transaction.id;
  if v_transaction.match_status <> 'matched' or v_transaction.matched_source_id <> v_real_receipt.id then
    raise exception 'assertion failed: expected the transaction to be matched to the real receipt, got status=% source=%', v_transaction.match_status, v_transaction.matched_source_id;
  end if;

  begin
    perform app.match_finance_bank_transaction(v_transaction.id, v_transaction.record_version, 'receipt', null, '00000000-0000-0000-0000-000000036002', 'financemanagera');
    raise exception 'assertion failed: expected finance_cash_transaction_not_unmatched for an already-matched transaction';
  exception
    when others then
      if sqlerrm !~ 'finance_cash_transaction_not_unmatched' then
        raise exception 'assertion failed: expected finance_cash_transaction_not_unmatched, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.unmatch_finance_bank_transaction(v_transaction.id, v_transaction.record_version, '', '00000000-0000-0000-0000-000000036002', 'financemanagera');
    raise exception 'assertion failed: expected finance_cash_unmatch_reason_required';
  exception
    when others then
      if sqlerrm !~ 'finance_cash_unmatch_reason_required' then
        raise exception 'assertion failed: expected finance_cash_unmatch_reason_required, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.unmatch_finance_bank_transaction(v_transaction.id, v_transaction.record_version, 'wrong match', '00000000-0000-0000-0000-000000036003', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority for Finance Editor A (no FIN:Approve) unmatching';
  exception
    when insufficient_privilege then
      null;
  end;

  perform app.unmatch_finance_bank_transaction(v_transaction.id, v_transaction.record_version, 'wrong match, reassigning', '00000000-0000-0000-0000-000000036002', 'financemanagera');
  select * into v_transaction from app.finance_bank_transactions where id = v_transaction.id;
  if v_transaction.match_status <> 'unmatched' or v_transaction.unmatch_reason is null then
    raise exception 'assertion failed: expected the transaction to be unmatched with its own reason recorded';
  end if;
end;
$$;

\echo '>> a real posted receipt allocation (debiting the shared cash_default-mapped account) makes the cash position''s own GL balance match the corresponding bank transaction''s own statement balance'
do $$
declare
  v_tenant_a uuid;
  v_account app.finance_bank_accounts;
  v_customer_id uuid;
  v_ar_item app.finance_ar_open_items;
  v_receipt app.finance_receipts;
  v_position record;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecasha');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  -- a fresh, dedicated bank account (same GL account as the earlier fixture,
  -- since cash_default resolves tenant-wide to CASH-BANK regardless) so this
  -- scenario's own statement balance starts clean, unaffected by the
  -- unrelated transactions the dedup/match scenario above already imported
  -- against its own bank account.
  select * into v_account from app.create_finance_bank_account(
    v_tenant_a, null, 'Cash Position Test Account', 'Acme Bank', '5678', 'USD',
    (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-BANK'),
    '00000000-0000-0000-0000-000000036002', 'financemanagera'
  );

  select * into v_ar_item from app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', pg_temp.iss319_mint_invoice(v_tenant_a, v_customer_id, '00000000-0000-0000-0000-000000036002', 'financemanagera', 'iss319-cashbank-position'), 'USD', 300, '2026-08-01'::date, '2026-08-31'::date, '00000000-0000-0000-0000-000000036002', 'financemanagera');
  select * into v_receipt from app.capture_finance_receipt(v_tenant_a, null, v_customer_id, 'BANKREF-CASHPOS-1', '2026-08-05'::date, 'Acme Cash Customer Pte Ltd', 'Main Operating', 'USD', 300, 'receipt-cashpos-1', '00000000-0000-0000-0000-000000036002', 'financemanagera');
  perform app.allocate_finance_receipt(p_receipt_id => v_receipt.id, p_allocations => jsonb_build_array(jsonb_build_object('arOpenItemId', v_ar_item.id, 'amount', 300)), p_idempotency_key => 'alloc-cashpos-1', p_actor_auth_user_id => '00000000-0000-0000-0000-000000036002', p_actor_label => 'financemanagera');

  perform app.import_finance_bank_statement(v_tenant_a, v_account.id, 'stmt-cashpos-1', jsonb_build_array(
    jsonb_build_object('transactionDate', '2026-08-05', 'direction', 'debit', 'amount', 300, 'reference', 'BANKREF-CASHPOS-1')
  ), '00000000-0000-0000-0000-000000036002', 'financemanagera');

  select * into v_position from app.get_finance_cash_position(v_tenant_a, v_account.id, '2026-08-31'::date, '00000000-0000-0000-0000-000000036002');
  if v_position.gl_balance <> v_position.statement_balance or v_position.variance_amount <> 0 then
    raise exception 'assertion failed: expected the cash position to reconcile exactly (gl=statement, variance=0), got gl=% statement=% variance=%', v_position.gl_balance, v_position.statement_balance, v_position.variance_amount;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot create/import/match against tenant A''s own bank account, and list_finance_bank_accounts never returns tenant A''s rows for tenant B''s own scope'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_account_id uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecasha');
  v_tenant_b := (select id from app.tenants where slug = 'acmecashb');
  v_account_id := (select id from app.finance_bank_accounts where tenant_id = v_tenant_a limit 1);

  begin
    perform app.import_finance_bank_statement(v_tenant_b, v_account_id, 'cross-tenant-attempt', jsonb_build_array(jsonb_build_object('transactionDate', '2026-08-01', 'direction', 'credit', 'amount', 10, 'reference', 'X')), '00000000-0000-0000-0000-000000036005', 'financemanagerb');
    raise exception 'assertion failed: expected finance_cash_bank_account_not_found for a cross-tenant bank account reference';
  exception
    when others then
      if sqlerrm !~ 'finance_cash_bank_account_not_found' then
        raise exception 'assertion failed: expected finance_cash_bank_account_not_found, got %', sqlerrm;
      end if;
  end;

  select count(*) into v_count from app.list_finance_bank_accounts(v_tenant_b, null, '00000000-0000-0000-0000-000000036005');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero bank accounts visible to tenant B, got %', v_count;
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-211 function (ERR-2026-004 regression guard)'
do $$
declare
  v_leaked_count integer;
begin
  select count(*) into v_leaked_count
    from information_schema.routine_privileges
    where routine_schema = 'app'
      and grantee = 'anon'
      and routine_name in (
        'create_finance_bank_account', 'import_finance_bank_statement', 'match_finance_bank_transaction',
        'unmatch_finance_bank_transaction', 'get_finance_cash_position', 'list_finance_bank_accounts',
        'list_finance_bank_transactions', 'check_finance_cash_authority'
      );
  if v_leaked_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on FIN-211 functions, found %', v_leaked_count;
  end if;
end;
$$;

\echo '>> audit trail: at least one create/import/match/unmatch event was captured for tenant A''s own cash-and-bank activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmecasha');
  select count(*) into v_count from app.audit_logs
    where tenant_id = v_tenant_a and action in ('create_finance_bank_account', 'import_finance_bank_statement', 'match_finance_bank_transaction', 'unmatch_finance_bank_transaction');
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one FIN-211 audit event for tenant A';
  end if;
end;
$$;

\echo '>> ISS-2026-206: the match-source lineage guard holds against a DIRECT insert/update, not merely through the RPC -- and a null id stays legal, because absent is incomplete while fabricated is false'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmecasha');
  v_account app.finance_bank_accounts;
  v_batch_id uuid;
  v_txn app.finance_bank_transactions;
  v_failed boolean;
begin
  select * into v_account from app.finance_bank_accounts where tenant_id = v_tenant_a limit 1;
  -- A real batch id, so the ONLY thing either write below can fail on is the lineage guard.
  select id into v_batch_id from app.finance_bank_statement_batches where bank_account_id = v_account.id limit 1;

  -- The RPC is not the threat model. app.match_finance_bank_transaction could be made to check
  -- this and the gap would still be open one layer down, which is the whole reason ISS-2026-202
  -- put its guard on the table rather than in the function. So this asserts against the raw write.
  begin
    insert into app.finance_bank_transactions (tenant_id, batch_id, bank_account_id, transaction_date, direction, amount, reference, line_hash, match_status, matched_source_type, matched_source_id)
    values (v_tenant_a, v_batch_id, v_account.id, '2026-09-01'::date, 'credit', 42, 'REF-ORPHAN', 'hash-iss206-orphan', 'matched', 'receipt', gen_random_uuid());
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm !~ 'finance_bank_transaction_orphan_match_source' then
      raise exception 'assertion failed: expected finance_bank_transaction_orphan_match_source on a direct insert, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: a direct insert claiming a receipt that does not exist was accepted -- the ISS-2026-206 guard is not on the table';
  end if;

  -- Same for a settlement claim, and same for an UPDATE: a row can be poisoned after the fact
  -- just as easily as at insert, so the trigger has to cover both.
  insert into app.finance_bank_transactions (tenant_id, batch_id, bank_account_id, transaction_date, direction, amount, reference, line_hash, match_status)
  values (v_tenant_a, v_batch_id, v_account.id, '2026-09-02'::date, 'credit', 43, 'REF-UNMATCHED', 'hash-iss206-unmatched', 'unmatched')
  returning * into v_txn;

  begin
    update app.finance_bank_transactions set match_status = 'matched', matched_source_type = 'settlement', matched_source_id = gen_random_uuid() where id = v_txn.id;
    v_failed := false;
  exception when others then
    v_failed := true;
    if sqlerrm !~ 'finance_bank_transaction_orphan_match_source' then
      raise exception 'assertion failed: expected finance_bank_transaction_orphan_match_source on a direct update, got %', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'assertion failed: a direct UPDATE claiming a settlement that does not exist was accepted';
  end if;

  -- The deliberate boundary. A matched row with no id names no document -- incomplete, and
  -- already supported by the UI, which offers the field as optional. Tightening that would be a
  -- separate behaviour change, and this proves it was NOT smuggled in with the lineage fix.
  update app.finance_bank_transactions set match_status = 'matched', matched_source_type = 'manual', matched_source_id = null where id = v_txn.id;
  if (select matched_source_type from app.finance_bank_transactions where id = v_txn.id) <> 'manual' then
    raise exception 'assertion failed: expected a manual match with a null source id to remain legal';
  end if;

  raise notice 'PASS: ISS-2026-206 match-source guard rejects a fabricated receipt/settlement id on direct insert AND update, while leaving a null id legal';
end;
$$;

\echo 'ALL FIN-211 (Cash and Bank Baseline) db-test assertions passed.'
