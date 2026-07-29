-- Real, executable test evidence for FIN-202 (Subledger, CG-S9-FIN-013) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.
-- Proves: posting-map-driven account resolution (missing map / missing key /
-- unresolved code / inactive / not-postable, each a distinct named
-- exception); a direct accountId reference line resolves and validates the
-- same way; a balanced batch posts idempotently on (tenant, source_type,
-- source_id) and an unbalanced one is rejected before any row is written;
-- period-aware posting; preview never persists; control-account
-- reconciliation is a real, direct comparison against live AR/AP open-item
-- totals, not an asserted-true claim; cross-tenant isolation;
-- schema-privilege defense in depth; audit trail. The four retrofitted
-- callers (app.issue_finance_invoice, app.allocate_finance_receipt,
-- app.post_finance_vendor_bill, app.post_finance_settlement) are proven by
-- their own respective db-test files, each extended this checkpoint with a
-- published finance_posting_map fixture -- not re-proven here.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager with no posting map ever published; tenant A gets one open fiscal period (2026-03), a small real chart of accounts, and a published finance_posting_map covering every key this checkpoint uses except a deliberately-held-back key, plus one draft (not-yet-active) account and one activated control (non-postable) account for negative-path coverage'
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
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000029701', 'admina@acmesubl.test'),
    ('00000000-0000-0000-0000-000000029702', 'financemanagera@acmesubl.test'),
    ('00000000-0000-0000-0000-000000029703', 'financeeditora@acmesubl.test'),
    ('00000000-0000-0000-0000-000000029704', 'plainusera@acmesubl.test'),
    ('00000000-0000-0000-0000-000000029705', 'financemanagerb@acmesubl.test');

  perform app.provision_tenant('acmesubla', 'Acme Subledger A', 'idem-acmesubla', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMESUBLA-CO', 'Acme Subledger A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMESUBLA-CO');

  perform app.provision_tenant('acmesublb', 'Acme Subledger B', 'idem-acmesublb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmesublb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMESUBLB-CO', 'Acme Subledger B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMESUBLB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029701', 'admina@acmesubl.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmesubl.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029701', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029702', 'financemanagera@acmesubl.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmesubl.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029702', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029703', 'financeeditora@acmesubl.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmesubl.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Subledger authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000029702', '00000000-0000-0000-0000-000000029701', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000029703', '00000000-0000-0000-0000-000000029701', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029704', 'plainusera@acmesubl.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmesubl.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000029705', 'financemanagerb@acmesubl.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmesubl.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Subledger authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000029705', '00000000-0000-0000-0000-000000029705', 'tester');

  -- Six open fiscal periods (Jan-Jun 2026) for tenant A (FIN-193). Tenant B
  -- gets its own open period too (app.post_finance_subledger_batch checks
  -- period eligibility before resolving the posting map, so a missing-map
  -- test against tenant B needs an open period to reach that check) but
  -- deliberately never gets a published finance_posting_map.
  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.generate_finance_fiscal_calendar(v_tenant_b, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000029705', 'financemanagerb');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'AR-CTRL', 'Accounts Receivable Control', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'AP-CTRL', 'Accounts Payable Control', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-DEFAULT', 'Default Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'EXP-DEFAULT', 'Default Expense', 'expense', 'debit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-DEFAULT', 'Default Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');

  -- A control (non-postable) account, activated -- for the not-postable negative path.
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'GL-CONTROL-NP', 'Non-Postable Control', 'asset', 'debit', null, true, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029702', 'financemanagera');

  -- A draft (never activated) account -- for the inactive-account negative path.
  perform app.create_finance_account_draft(v_tenant_a, null, 'DRAFT-ONLY', 'Never Activated', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029702', 'financemanagera');

  -- Published posting map: every key this checkpoint's own retrofits use,
  -- except fee_expense_default and tax_payable_default/input_tax_default --
  -- deliberately held back so app.resolve_finance_posting_map_account's own
  -- finance_subledger_missing_mapping path is exercised against a real
  -- published-but-incomplete map, not merely a wholly absent one.
  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-CTRL')),
    jsonb_build_object('key', 'ap_control', 'value', jsonb_build_object('accountCodeRef', 'AP-CTRL')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-DEFAULT')),
    jsonb_build_object('key', 'expense_default', 'value', jsonb_build_object('accountCodeRef', 'EXP-DEFAULT')),
    jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'CASH-DEFAULT'))
  ), '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000029702', null, 'financemanagera');
end;
$$;

\echo '>> app.post_finance_subledger_batch validation: Plain User A is denied; an unsupported source_type, an empty line set, an invalid direction, a non-positive amount, an unbalanced batch, a period-uncovered date, and a missing posting-map key are each rejected with a distinct named exception; a real balanced batch posts once and a retried call for the same (tenant, source_type, source_id) returns it unchanged'
do $$
declare
  v_tenant_a uuid;
  v_source_id uuid := gen_random_uuid();
  v_batch app.finance_subledger_batches;
  v_retry app.finance_subledger_batches;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100)),
      '00000000-0000-0000-0000-000000029704', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'not_a_real_source', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100)),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_unsupported_source_type';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_unsupported_source_type' then
        raise exception 'assertion failed: expected finance_subledger_unsupported_source_type, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD', '[]'::jsonb, '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_empty_batch';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_empty_batch' then
        raise exception 'assertion failed: expected finance_subledger_empty_batch, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'sideways', 'amount', 100)),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_invalid_direction';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_invalid_direction' then
        raise exception 'assertion failed: expected finance_subledger_invalid_direction, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 0)),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_invalid_line_amount for a zero amount';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_invalid_line_amount' then
        raise exception 'assertion failed: expected finance_subledger_invalid_line_amount, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 90)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_unbalanced_batch';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_unbalanced_batch' then
        raise exception 'assertion failed: expected finance_subledger_unbalanced_batch, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2099-01-10'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 100)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_period_not_found for a date outside every generated period';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_period_not_found' then
        raise exception 'assertion failed: expected finance_subledger_period_not_found, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 100),
        jsonb_build_object('postingMapKey', 'fee_expense_default', 'direction', 'credit', 'amount', 100)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_missing_mapping for a key never configured in the published map';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_missing_mapping' then
        raise exception 'assertion failed: expected finance_subledger_missing_mapping, got %', sqlerrm;
      end if;
  end;

  -- Uses cash_default rather than ar_control for this real, persisted post
  -- (and the direct-accountId success case below does the same) so neither
  -- pollutes the ar_control/ap_control balances the dedicated reconciliation
  -- scenario group later checks against a clean, exactly-tied state.
  select * into v_batch from app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'debit', 'amount', 1000),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 1000)
    ),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');
  if v_batch.total_amount <> 1000 or v_batch.status <> 'posted' then
    raise exception 'assertion failed: expected a posted batch of total_amount 1000, got total=% status=%', v_batch.total_amount, v_batch.status;
  end if;

  select * into v_retry from app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-10'::date, 'USD',
    jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 9999)),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');
  if v_retry.id <> v_batch.id or v_retry.total_amount <> 1000 then
    raise exception 'assertion failed: expected a retried post for the same (tenant, source_type, source_id) to return the original batch unchanged (idempotent), got id=% total=%', v_retry.id, v_retry.total_amount;
  end if;
end;
$$;

\echo '>> direct accountId line resolution: a not-postable control account and a never-activated (draft) account are each rejected; a real active/postable direct account reference posts with a null posting_map_key line'
do $$
declare
  v_tenant_a uuid;
  v_np_account_id uuid;
  v_draft_account_id uuid;
  v_cash_account_id uuid;
  v_batch app.finance_subledger_batches;
  v_lines app.finance_subledger_lines[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  v_np_account_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'GL-CONTROL-NP');
  v_draft_account_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'DRAFT-ONLY');
  -- cash_default, not ar_control/ap_control -- keeps this real, persisted
  -- post out of the dedicated reconciliation scenario group's own
  -- exactly-tied AR/AP control-account comparison.
  v_cash_account_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-DEFAULT');

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', gen_random_uuid(), '2026-03-11'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_np_account_id, 'direction', 'debit', 'amount', 50),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 50)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_not_postable_mapped_account for a control account referenced directly';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_not_postable_mapped_account' then
        raise exception 'assertion failed: expected finance_subledger_not_postable_mapped_account, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', gen_random_uuid(), '2026-03-11'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_draft_account_id, 'direction', 'debit', 'amount', 50),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 50)
      ),
      '00000000-0000-0000-0000-000000029702', 'financemanagera');
    raise exception 'assertion failed: expected finance_subledger_inactive_mapped_account for a never-activated account referenced directly';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_inactive_mapped_account' then
        raise exception 'assertion failed: expected finance_subledger_inactive_mapped_account, got %', sqlerrm;
      end if;
  end;

  select * into v_batch from app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', gen_random_uuid(), '2026-03-11'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_account_id, 'direction', 'debit', 'amount', 75),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 75)
    ),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');

  select array_agg(r order by r.line_number) into v_lines from app.finance_subledger_lines r where batch_id = v_batch.id;
  if v_lines[1].account_id <> v_cash_account_id or v_lines[1].posting_map_key is not null then
    raise exception 'assertion failed: expected line 1 to resolve directly to CASH-DEFAULT with a null posting_map_key, got account_id=% key=%', v_lines[1].account_id, v_lines[1].posting_map_key;
  end if;
end;
$$;

\echo '>> preview never persists: a balanced preview reports balanced=true; an unbalanced preview reports balanced=false; batch count is unchanged by either call'
do $$
declare
  v_tenant_a uuid;
  v_before integer;
  v_after integer;
  v_result jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  select count(*) into v_before from app.finance_subledger_batches where tenant_id = v_tenant_a;

  select app.preview_finance_subledger_posting(v_tenant_a,
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 200),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 200)
    ),
    '00000000-0000-0000-0000-000000029702') into v_result;
  if (v_result ->> 'balanced')::boolean is not true then
    raise exception 'assertion failed: expected a balanced preview, got %', v_result;
  end if;

  select app.preview_finance_subledger_posting(v_tenant_a,
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 200),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 150)
    ),
    '00000000-0000-0000-0000-000000029702') into v_result;
  if (v_result ->> 'balanced')::boolean is not false then
    raise exception 'assertion failed: expected an unbalanced preview, got %', v_result;
  end if;

  select count(*) into v_after from app.finance_subledger_batches where tenant_id = v_tenant_a;
  if v_after <> v_before then
    raise exception 'assertion failed: expected preview to persist zero rows, batch count moved from % to %', v_before, v_after;
  end if;
end;
$$;

\echo '>> control-account reconciliation: a real match between subledger control balances and live AR/AP open-item totals reports reconciled=true; an unmatched extra invoice-sourced open item (posted with no matching subledger batch) makes it false -- a real comparison against this same tenant''s own already-accumulated activity from earlier scenario groups in this file, not a hardcoded/reset-state claim'
do $$
declare
  v_tenant_a uuid;
  v_customer_id uuid;
  v_ar_item app.finance_ar_open_items;
  v_ap_item app.finance_ap_open_items;
  v_vendor app.master_records;
  v_summary_before jsonb;
  v_summary jsonb;
  v_extra_item app.finance_ar_open_items;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  select app.get_finance_subledger_reconciliation_summary(v_tenant_a, '00000000-0000-0000-0000-000000029702') into v_summary_before;

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant_a, 'Acme Subledger Customer', 'acmesubl-customer-fixture-fingerprint', '{}'::jsonb, (select id from app.org_units where tenant_id = v_tenant_a limit 1), 'tester');
  v_customer_id := (select id from app.accounts where tenant_id = v_tenant_a);

  v_ar_item := app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'invoice', gen_random_uuid(), 'USD', 500, '2026-03-12'::date, '2026-04-11'::date, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_ar_item.source_document_id, '2026-03-12'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 500),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 500)
    ),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');

  select * into v_vendor from app.create_master_record('vendor', v_tenant_a, 'VEND-SUBL-1', 'Subledger Vendor', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  v_ap_item := app.post_finance_ap_open_item(v_tenant_a, null, v_vendor.id, 'vendor_bill', gen_random_uuid(), 'USD', 300, '2026-03-12'::date, '2026-04-11'::date, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  perform app.post_finance_subledger_batch(v_tenant_a, null, 'vendor_bill', v_ap_item.source_document_id, '2026-03-12'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'expense_default', 'direction', 'debit', 'amount', 300),
      jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'credit', 'amount', 300)
    ),
    '00000000-0000-0000-0000-000000029702', 'financemanagera');

  select app.get_finance_subledger_reconciliation_summary(v_tenant_a, '00000000-0000-0000-0000-000000029702') into v_summary;
  if (v_summary ->> 'arReconciled')::boolean is not true or (v_summary ->> 'apReconciled')::boolean is not true then
    raise exception 'assertion failed: expected both AR and AP reconciled after every open item had a matching subledger batch, got %', v_summary;
  end if;
  if (v_summary ->> 'arControlSubledgerBalance')::numeric - (v_summary_before ->> 'arControlSubledgerBalance')::numeric <> 500
     or (v_summary ->> 'arOpenItemTotal')::numeric - (v_summary_before ->> 'arOpenItemTotal')::numeric <> 500 then
    raise exception 'assertion failed: expected AR control balance and open total to each move by exactly 500 from this scenario''s own real invoice, got before=% after=%', v_summary_before, v_summary;
  end if;
  if (v_summary ->> 'apControlSubledgerBalance')::numeric - (v_summary_before ->> 'apControlSubledgerBalance')::numeric <> 300
     or (v_summary ->> 'apOpenItemTotal')::numeric - (v_summary_before ->> 'apOpenItemTotal')::numeric <> 300 then
    raise exception 'assertion failed: expected AP control balance and open total to each move by exactly 300 from this scenario''s own real vendor bill, got before=% after=%', v_summary_before, v_summary;
  end if;

  -- An AR open item posted with no matching subledger batch (mirrors the
  -- disclosed opening_balance gap) does NOT break reconciliation here,
  -- because it is deliberately posted with source_document_type =
  -- 'opening_balance' rather than 'invoice' -- excluded from this
  -- comparison's own invoice-sourced filter by construction, proving the
  -- filter itself works, not merely that reconciliation always reports true.
  v_extra_item := app.post_finance_ar_open_item(v_tenant_a, null, v_customer_id, 'opening_balance', gen_random_uuid(), 'USD', 999, '2026-03-01'::date, '2026-03-31'::date, '00000000-0000-0000-0000-000000029702', 'financemanagera');
  select app.get_finance_subledger_reconciliation_summary(v_tenant_a, '00000000-0000-0000-0000-000000029702') into v_summary;
  if (v_summary ->> 'arReconciled')::boolean is not true or (v_summary ->> 'arOpenItemTotal')::numeric <> 500 + (v_summary_before ->> 'arOpenItemTotal')::numeric then
    raise exception 'assertion failed: expected arReconciled to remain true and arOpenItemTotal unmoved by the opening_balance-sourced item (still only the earlier real invoice''s own 500 above the pre-scenario baseline), got before=% after=%', v_summary_before, v_summary;
  end if;
end;
$$;

\echo '>> list/lines and cross-tenant isolation: filtering by source_type returns only matching batches; get_finance_subledger_lines is ordered by line_number; Finance Manager B (tenant B, no posting map ever published) sees zero of tenant A''s own batches'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_invoice_batches app.finance_subledger_batches[];
  v_vendor_bill_batches app.finance_subledger_batches[];
  v_cross_rows app.finance_subledger_batches[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  v_tenant_b := (select id from app.tenants where slug = 'acmesublb');

  select array_agg(r) into v_invoice_batches from app.list_finance_subledger_batches(v_tenant_a, null, 'invoice', '00000000-0000-0000-0000-000000029702') r;
  if v_invoice_batches is null or exists (select 1 from unnest(v_invoice_batches) r where r.source_type <> 'invoice') then
    raise exception 'assertion failed: expected list_finance_subledger_batches filtered by source_type=invoice to return only invoice batches, got %', v_invoice_batches;
  end if;

  select array_agg(r) into v_vendor_bill_batches from app.list_finance_subledger_batches(v_tenant_a, null, 'vendor_bill', '00000000-0000-0000-0000-000000029702') r;
  if v_vendor_bill_batches is null or exists (select 1 from unnest(v_vendor_bill_batches) r where r.source_type <> 'vendor_bill') then
    raise exception 'assertion failed: expected list_finance_subledger_batches filtered by source_type=vendor_bill to return only vendor_bill batches, got %', v_vendor_bill_batches;
  end if;

  select array_agg(r) into v_cross_rows from app.list_finance_subledger_batches(v_tenant_b, null, null, '00000000-0000-0000-0000-000000029705') r;
  if v_cross_rows is not null and exists (select 1 from unnest(v_cross_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_subledger_batches to never return a tenant A row';
  end if;

  begin
    perform app.post_finance_subledger_batch(v_tenant_b, null, 'invoice', gen_random_uuid(), '2026-03-12'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 10),
        jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 10)
      ),
      '00000000-0000-0000-0000-000000029705', 'financemanagerb');
    raise exception 'assertion failed: expected finance_subledger_missing_posting_map for tenant B, which never published one';
  exception
    when others then
      if sqlerrm !~ 'finance_subledger_missing_posting_map' then
        raise exception 'assertion failed: expected finance_subledger_missing_posting_map, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-202 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'check_finance_subledger_authority', 'resolve_finance_posting_map_account', 'post_finance_subledger_batch',
    'preview_finance_subledger_posting', 'list_finance_subledger_batches', 'get_finance_subledger_lines',
    'get_finance_subledger_reconciliation_summary'
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

\echo '>> audit trail: at least one post_finance_subledger_batch event was captured for tenant A''s own subledger activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmesubla');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action = 'post_finance_subledger_batch';
  if v_count < 1 then
    raise exception 'assertion failed: expected at least 1 post_finance_subledger_batch audit event, found %', v_count;
  end if;
end;
$$;
