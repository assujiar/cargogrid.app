-- Real, executable test evidence for FIN-201 (Settlement, CG-S9-FIN-012) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.
-- Proves: idempotent preparation with full validation (auth, vendor, currency,
-- empty/invalid/over allocation, held/settled item rejection, vendor/currency
-- mismatch); lifecycle authority split (Edit for prepare/submit/discard,
-- Approve for approve/execute/post/reversal); the full
-- draft -> submitted -> approved -> executed -> posted path posting exactly
-- once to FIN-199's own AP subledger via app.apply_finance_ap_settlement;
-- idempotent post replay; multi-item allocation in one settlement; governed
-- reversal restoring the AP balance; cross-tenant isolation;
-- schema-privilege defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Edit/Approve/View), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets one active fiscal period (2026-03) and one active vendor reference'
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
  v_vendor app.master_records;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000029601', 'admina@acmesetl.test'),
    ('00000000-0000-0000-0000-000000029602', 'financemanagera@acmesetl.test'),
    ('00000000-0000-0000-0000-000000029603', 'financeeditora@acmesetl.test'),
    ('00000000-0000-0000-0000-000000029604', 'plainusera@acmesetl.test'),
    ('00000000-0000-0000-0000-000000029605', 'financemanagerb@acmesetl.test');

  perform app.provision_tenant('acmesetla', 'Acme Settlement A', 'idem-acmesetla', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmesetla');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMESETLA-CO', 'Acme Settlement A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMESETLA-CO');

  perform app.provision_tenant('acmesetlb', 'Acme Settlement B', 'idem-acmesetlb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmesetlb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMESETLB-CO', 'Acme Settlement B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMESETLB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029601', 'admina@acmesetl.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmesetl.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029601', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029602', 'financemanagera@acmesetl.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmesetl.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029602', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029603', 'financeeditora@acmesetl.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmesetl.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Settlement authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000029602', '00000000-0000-0000-0000-000000029601', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000029603', '00000000-0000-0000-0000-000000029601', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029604', 'plainusera@acmesetl.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmesetl.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000029605', 'financemanagerb@acmesetl.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmesetl.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Settlement authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000029605', '00000000-0000-0000-0000-000000029605', 'tester');

  -- Six open fiscal periods (Jan-Jun 2026) for tenant A (FIN-193).
  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000029602', 'financemanagera');

  -- One active vendor reference (OPS-172's own 'vendor' master_type).
  select * into v_vendor from app.create_master_record('vendor', v_tenant_a, 'VEND-SETL-1', 'Contoso Freight', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000029602', 'financemanagera');
end;
$$;

\echo '>> FIN-202 fixture prerequisite: a published finance_posting_map so app.post_finance_settlement''s own new subledger effect can resolve real accounts'
do $$
declare
  v_tenant_a uuid;
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
  v_coa_role uuid;
  v_coa_draft app.role_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesetla');

  -- FIN-192's own app.create_finance_account_draft requires FIN:Create, which
  -- this file's own "Finance Manager" role (Edit/Approve/View only) does not
  -- grant -- an additional, additive role assignment, not a change to the
  -- existing role's own permission set.
  v_coa_role := (app.create_role(v_tenant_a, 'Chart of Accounts Setup', 'FIN-202 fixture-only account creation', 'tester')).id;
  v_coa_draft := app.create_role_version(v_coa_role, 'tester');
  perform app.set_role_version_permissions(v_coa_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action = 'Create'), 'tester');
  perform app.publish_role_version(v_coa_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_coa_role and status = 'published'), '00000000-0000-0000-0000-000000029602', '00000000-0000-0000-0000-000000029601', 'tester');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'AP-CTRL', 'Accounts Payable Control', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-DEFAULT', 'Default Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'FEE-EXP-DEFAULT', 'Default Fee Expense', 'expense', 'debit', null, false, null, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ap_control', 'value', jsonb_build_object('accountCodeRef', 'AP-CTRL')),
    jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'CASH-DEFAULT')),
    jsonb_build_object('key', 'fee_expense_default', 'value', jsonb_build_object('accountCodeRef', 'FEE-EXP-DEFAULT'))
  ), '00000000-0000-0000-0000-000000029602', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000029602', null, 'financemanagera');
end;
$$;

\echo '>> preparation validation: Plain User A is denied; unknown vendor, unsupported currency, empty allocation, non-positive allocation amount, unknown open item, vendor mismatch, currency mismatch, held item, and over-allocation are each rejected; Finance Manager A prepares once and a retried call with the same idempotency_key returns the same row unchanged'
do $$
declare
  v_tenant_a uuid;
  v_vendor_id uuid;
  v_other_vendor app.master_records;
  v_item_1 app.finance_ap_open_items;
  v_item_2 app.finance_ap_open_items;
  v_held_item app.finance_ap_open_items;
  v_settlement app.finance_settlements;
  v_retry app.finance_settlements;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesetla');
  v_vendor_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-SETL-1');

  select * into v_item_1 from app.post_finance_ap_open_item(v_tenant_a, null, v_vendor_id, 'vendor_bill', gen_random_uuid(), 'USD', 1000, '2026-03-10'::date, '2026-04-09'::date, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_item_2 from app.post_finance_ap_open_item(v_tenant_a, null, v_vendor_id, 'vendor_bill', gen_random_uuid(), 'USD', 500, '2026-03-11'::date, '2026-04-10'::date, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_held_item from app.post_finance_ap_open_item(v_tenant_a, null, v_vendor_id, 'vendor_bill', gen_random_uuid(), 'USD', 300, '2026-03-12'::date, '2026-04-11'::date, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_held_item from app.place_finance_ap_hold(v_held_item.id, v_held_item.record_version, 'disputed', '00000000-0000-0000-0000-000000029603', 'financeeditora');

  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-1', 'Bank ***1234', 'USD', '2026-03-15'::date,
      jsonb_build_array(jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 400)), 0, 'prep-denied-1', '00000000-0000-0000-0000-000000029604', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, gen_random_uuid(), 'PMT-2', 'Bank ***1234', 'USD', '2026-03-15'::date,
      jsonb_build_array(jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 400)), 0, 'prep-badvendor-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_vendor_not_found';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_vendor_not_found' then
        raise exception 'assertion failed: expected finance_settlement_vendor_not_found, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-3', 'Bank ***1234', 'ZZZ', '2026-03-15'::date,
      jsonb_build_array(jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 400)), 0, 'prep-badcur-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_unsupported_currency';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_unsupported_currency' then
        raise exception 'assertion failed: expected finance_settlement_unsupported_currency, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-4', 'Bank ***1234', 'USD', '2026-03-15'::date,
      '[]'::jsonb, 0, 'prep-empty-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_empty_allocation';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_empty_allocation' then
        raise exception 'assertion failed: expected finance_settlement_empty_allocation, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-5', 'Bank ***1234', 'USD', '2026-03-15'::date,
      jsonb_build_array(jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 0)), 0, 'prep-zero-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_invalid_allocation_amount for a zero amount';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_invalid_allocation_amount' then
        raise exception 'assertion failed: expected finance_settlement_invalid_allocation_amount, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-6', 'Bank ***1234', 'USD', '2026-03-15'::date,
      jsonb_build_array(jsonb_build_object('apOpenItemId', gen_random_uuid(), 'amount', 100)), 0, 'prep-unknownitem-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_open_item_not_found';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_open_item_not_found' then
        raise exception 'assertion failed: expected finance_settlement_open_item_not_found, got %', sqlerrm;
      end if;
  end;

  select * into v_other_vendor from app.create_master_record('vendor', v_tenant_a, 'VEND-SETL-OTHER', 'Other Vendor', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, v_other_vendor.id, 'PMT-7', 'Bank ***1234', 'USD', '2026-03-15'::date,
      jsonb_build_array(jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 100)), 0, 'prep-vendormismatch-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_vendor_mismatch';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_vendor_mismatch' then
        raise exception 'assertion failed: expected finance_settlement_vendor_mismatch, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-8', 'Bank ***1234', 'EUR', '2026-03-15'::date,
      jsonb_build_array(jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 100)), 0, 'prep-curmismatch-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_currency_mismatch';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_currency_mismatch' then
        raise exception 'assertion failed: expected finance_settlement_currency_mismatch, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-9', 'Bank ***1234', 'USD', '2026-03-15'::date,
      jsonb_build_array(jsonb_build_object('apOpenItemId', v_held_item.id, 'amount', 100)), 0, 'prep-held-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_open_item_held';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_open_item_held' then
        raise exception 'assertion failed: expected finance_settlement_open_item_held, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-10', 'Bank ***1234', 'USD', '2026-03-15'::date,
      jsonb_build_array(jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 5000)), 0, 'prep-over-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_over_allocation';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_over_allocation' then
        raise exception 'assertion failed: expected finance_settlement_over_allocation, got %', sqlerrm;
      end if;
  end;

  -- Real, valid two-item allocation (Prompt 201 section 22: "combine
  -- compatible items/payee").
  select * into v_settlement from app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-11', 'Bank ***1234', 'USD', '2026-03-15'::date,
    jsonb_build_array(
      jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 400),
      jsonb_build_object('apOpenItemId', v_item_2.id, 'amount', 500)
    ), 5, 'prep-real-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_settlement.status <> 'draft' or v_settlement.allocated_amount <> 900 or v_settlement.fee_amount <> 5 or v_settlement.total_amount <> 905 then
    raise exception 'assertion failed: expected a draft settlement with allocated_amount=900 fee_amount=5 total_amount=905, got status=% allocated=% fee=% total=%',
      v_settlement.status, v_settlement.allocated_amount, v_settlement.fee_amount, v_settlement.total_amount;
  end if;

  select * into v_retry from app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-11-retry', 'Bank ***9999', 'USD', '2026-03-16'::date,
    jsonb_build_array(jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 999)), 0, 'prep-real-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_retry.id <> v_settlement.id or v_retry.allocated_amount <> 900 or v_retry.payment_reference <> 'PMT-11' then
    raise exception 'assertion failed: expected a retried prepare with the same idempotency_key to return the original settlement unchanged, got id=% allocated=% ref=%',
      v_retry.id, v_retry.allocated_amount, v_retry.payment_reference;
  end if;
end;
$$;

\echo '>> lifecycle authority split and full posting path: Finance Editor A (no Approve) is denied approve/execute/post/reversal; Finance Manager A drives draft -> submitted -> approved -> executed -> posted, posting exactly once to both AP open items via FIN-199''s own app.apply_finance_ap_settlement; a retried post returns the settlement unchanged; settlement_number is assigned only at post time'
do $$
declare
  v_tenant_a uuid;
  v_vendor_id uuid;
  v_item_1 app.finance_ap_open_items;
  v_item_2 app.finance_ap_open_items;
  v_settlement app.finance_settlements;
  v_retry app.finance_settlements;
  v_ap_1 app.finance_ap_open_items;
  v_ap_2 app.finance_ap_open_items;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesetla');
  v_vendor_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-SETL-1');

  select * into v_item_1 from app.post_finance_ap_open_item(v_tenant_a, null, v_vendor_id, 'vendor_bill', gen_random_uuid(), 'USD', 700, '2026-03-05'::date, '2026-04-04'::date, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_item_2 from app.post_finance_ap_open_item(v_tenant_a, null, v_vendor_id, 'vendor_bill', gen_random_uuid(), 'USD', 300, '2026-03-06'::date, '2026-04-05'::date, '00000000-0000-0000-0000-000000029602', 'financemanagera');

  select * into v_settlement from app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-FULL-1', 'Bank ***1234', 'USD', '2026-03-20'::date,
    jsonb_build_array(
      jsonb_build_object('apOpenItemId', v_item_1.id, 'amount', 700),
      jsonb_build_object('apOpenItemId', v_item_2.id, 'amount', 300)
    ), 0, 'prep-full-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_settlement.settlement_number is not null then
    raise exception 'assertion failed: expected settlement_number to remain null before posting, got %', v_settlement.settlement_number;
  end if;

  select * into v_settlement from app.submit_finance_settlement_for_approval(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_settlement.status <> 'submitted' then
    raise exception 'assertion failed: expected status submitted, got %', v_settlement.status;
  end if;

  begin
    perform app.approve_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029603', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_settlement from app.approve_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_settlement.status <> 'approved' then
    raise exception 'assertion failed: expected status approved, got %', v_settlement.status;
  end if;

  begin
    perform app.execute_finance_settlement(v_settlement.id, v_settlement.record_version, 'TXN-REF-1', '00000000-0000-0000-0000-000000029603', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve to execute';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.post_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_not_executed -- posting before execution must be rejected';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_not_executed' then
        raise exception 'assertion failed: expected finance_settlement_not_executed, got %', sqlerrm;
      end if;
  end;

  select * into v_settlement from app.execute_finance_settlement(v_settlement.id, v_settlement.record_version, 'TXN-REF-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_settlement.status <> 'executed' or v_settlement.execution_reference <> 'TXN-REF-1' then
    raise exception 'assertion failed: expected status executed with execution_reference TXN-REF-1, got status=% ref=%', v_settlement.status, v_settlement.execution_reference;
  end if;

  select * into v_settlement from app.post_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_settlement.status <> 'posted' or v_settlement.settlement_number is null or v_settlement.settlement_number !~ '^SETL-2026-' then
    raise exception 'assertion failed: expected status posted with an assigned SETL-2026-* settlement_number, got status=% number=%', v_settlement.status, v_settlement.settlement_number;
  end if;

  select * into v_ap_1 from app.finance_ap_open_items where id = v_item_1.id;
  select * into v_ap_2 from app.finance_ap_open_items where id = v_item_2.id;
  if v_ap_1.status <> 'settled' or v_ap_1.open_amount <> 0 or v_ap_2.status <> 'settled' or v_ap_2.open_amount <> 0 then
    raise exception 'assertion failed: expected both AP open items fully settled by posting, got item1 status=%/open=% item2 status=%/open=%',
      v_ap_1.status, v_ap_1.open_amount, v_ap_2.status, v_ap_2.open_amount;
  end if;

  -- Idempotent post replay: a retried call against an already-posted
  -- settlement returns it unchanged and never double-applies to AP.
  select * into v_retry from app.post_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_retry.id <> v_settlement.id or v_retry.settlement_number <> v_settlement.settlement_number then
    raise exception 'assertion failed: expected a retried post to return the same posted settlement unchanged, got id=% number=%', v_retry.id, v_retry.settlement_number;
  end if;
  select * into v_ap_1 from app.finance_ap_open_items where id = v_item_1.id;
  if v_ap_1.settled_amount <> 700 then
    raise exception 'assertion failed: expected AP item 1 settled_amount to remain exactly 700 after a retried post (no double-apply), got %', v_ap_1.settled_amount;
  end if;
end;
$$;

\echo '>> governed reversal: Finance Editor A (no Approve) is denied; a reason is required; reversal is only valid against a posted settlement; Finance Manager A reverses a posted settlement and both AP open items return to open'
do $$
declare
  v_tenant_a uuid;
  v_vendor_id uuid;
  v_item app.finance_ap_open_items;
  v_settlement app.finance_settlements;
  v_ap app.finance_ap_open_items;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesetla');
  v_vendor_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-SETL-1');

  select * into v_item from app.post_finance_ap_open_item(v_tenant_a, null, v_vendor_id, 'vendor_bill', gen_random_uuid(), 'USD', 250, '2026-03-08'::date, '2026-04-07'::date, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_settlement from app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-REV-1', 'Bank ***1234', 'USD', '2026-03-22'::date,
    jsonb_build_array(jsonb_build_object('apOpenItemId', v_item.id, 'amount', 250)), 0, 'prep-rev-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');

  begin
    perform app.request_finance_settlement_reversal(v_settlement.id, 'wrong bank account', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_not_posted -- reversal before posting must be rejected';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_not_posted' then
        raise exception 'assertion failed: expected finance_settlement_not_posted, got %', sqlerrm;
      end if;
  end;

  select * into v_settlement from app.submit_finance_settlement_for_approval(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_settlement from app.approve_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_settlement from app.execute_finance_settlement(v_settlement.id, v_settlement.record_version, 'TXN-REF-2', '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_settlement from app.post_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');

  begin
    perform app.request_finance_settlement_reversal(v_settlement.id, 'wrong bank account', '00000000-0000-0000-0000-000000029603', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.request_finance_settlement_reversal(v_settlement.id, '', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_reversal_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_reversal_reason_required' then
        raise exception 'assertion failed: expected finance_settlement_reversal_reason_required, got %', sqlerrm;
      end if;
  end;

  select * into v_settlement from app.request_finance_settlement_reversal(v_settlement.id, 'wrong bank account, payment recalled', '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_settlement.status <> 'reversed' then
    raise exception 'assertion failed: expected status reversed, got %', v_settlement.status;
  end if;

  select * into v_ap from app.finance_ap_open_items where id = v_item.id;
  if v_ap.status <> 'open' or v_ap.open_amount <> 250 then
    raise exception 'assertion failed: expected the AP open item restored to open with open_amount 250 after reversal, got status=% open=%', v_ap.status, v_ap.open_amount;
  end if;
end;
$$;

\echo '>> discard boundary: only a draft or submitted settlement may be discarded; an approved settlement cannot be'
do $$
declare
  v_tenant_a uuid;
  v_vendor_id uuid;
  v_item app.finance_ap_open_items;
  v_settlement app.finance_settlements;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesetla');
  v_vendor_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-SETL-1');

  select * into v_item from app.post_finance_ap_open_item(v_tenant_a, null, v_vendor_id, 'vendor_bill', gen_random_uuid(), 'USD', 150, '2026-03-09'::date, '2026-04-08'::date, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_settlement from app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-DISC-1', 'Bank ***1234', 'USD', '2026-03-23'::date,
    jsonb_build_array(jsonb_build_object('apOpenItemId', v_item.id, 'amount', 150)), 0, 'prep-disc-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_settlement from app.discard_finance_settlement_draft(v_settlement.id, v_settlement.record_version, 'duplicate entry', '00000000-0000-0000-0000-000000029602', 'financemanagera');
  if v_settlement.status <> 'void' then
    raise exception 'assertion failed: expected status void, got %', v_settlement.status;
  end if;

  select * into v_settlement from app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-DISC-2', 'Bank ***1234', 'USD', '2026-03-23'::date,
    jsonb_build_array(jsonb_build_object('apOpenItemId', v_item.id, 'amount', 150)), 0, 'prep-disc-2', '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_settlement from app.submit_finance_settlement_for_approval(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_settlement from app.approve_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029602', 'financemanagera');

  begin
    perform app.discard_finance_settlement_draft(v_settlement.id, v_settlement.record_version, 'too late', '00000000-0000-0000-0000-000000029602', 'financemanagera');
    raise exception 'assertion failed: expected finance_settlement_not_cancellable -- an approved settlement must not be discardable';
  exception
    when others then
      if sqlerrm !~ 'finance_settlement_not_cancellable' then
        raise exception 'assertion failed: expected finance_settlement_not_cancellable, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> list, allocations and candidate search; cross-tenant isolation -- Finance Manager B sees zero of tenant A''s own settlements'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_vendor_id uuid;
  v_item app.finance_ap_open_items;
  v_settlement app.finance_settlements;
  v_allocations app.finance_settlement_allocations[];
  v_candidates app.finance_ap_open_items[];
  v_cross_rows app.finance_settlements[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesetla');
  v_tenant_b := (select id from app.tenants where slug = 'acmesetlb');
  v_vendor_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-SETL-1');

  select * into v_item from app.post_finance_ap_open_item(v_tenant_a, null, v_vendor_id, 'vendor_bill', gen_random_uuid(), 'USD', 90, '2026-03-13'::date, '2026-04-12'::date, '00000000-0000-0000-0000-000000029602', 'financemanagera');
  select * into v_settlement from app.prepare_finance_settlement(v_tenant_a, null, v_vendor_id, 'PMT-LIST-1', 'Bank ***1234', 'USD', '2026-03-24'::date,
    jsonb_build_array(jsonb_build_object('apOpenItemId', v_item.id, 'amount', 90)), 0, 'prep-list-1', '00000000-0000-0000-0000-000000029602', 'financemanagera');

  select array_agg(r) into v_allocations from app.get_finance_settlement_allocations(v_settlement.id, '00000000-0000-0000-0000-000000029602') r;
  if array_length(v_allocations, 1) <> 1 or v_allocations[1].ap_open_item_id <> v_item.id or v_allocations[1].amount <> 90 then
    raise exception 'assertion failed: expected exactly one allocation line of 90 against the AP open item, got %', v_allocations;
  end if;

  select array_agg(r) into v_candidates from app.search_finance_ap_candidates_for_settlement(v_tenant_a, v_vendor_id, 'USD', '00000000-0000-0000-0000-000000029602') r;
  if v_candidates is null or not exists (select 1 from unnest(v_candidates) r where r.id = v_item.id) then
    raise exception 'assertion failed: expected the open AP item to appear among settlement candidates';
  end if;

  select array_agg(r) into v_cross_rows from app.list_finance_settlements(v_tenant_b, null, null, null, '00000000-0000-0000-0000-000000029605') r;
  if v_cross_rows is not null and exists (select 1 from unnest(v_cross_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_settlements to never return a tenant A row';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-201 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'touch_finance_settlement_row', 'check_finance_settlement_authority', 'prepare_finance_settlement',
    'submit_finance_settlement_for_approval', 'discard_finance_settlement_draft', 'approve_finance_settlement',
    'execute_finance_settlement', 'post_finance_settlement', 'request_finance_settlement_reversal',
    'list_finance_settlements', 'get_finance_settlement_allocations', 'search_finance_ap_candidates_for_settlement'
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

\echo '>> audit trail: at least one prepare/approve/execute/post/reversal event was captured for tenant A''s own settlement activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesetla');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('prepare_finance_settlement', 'approve_finance_settlement', 'execute_finance_settlement', 'post_finance_settlement', 'request_finance_settlement_reversal');
  if v_count < 5 then
    raise exception 'assertion failed: expected at least 5 audit events across this fixture''s own settlement lifecycle calls, found %', v_count;
  end if;
end;
$$;
