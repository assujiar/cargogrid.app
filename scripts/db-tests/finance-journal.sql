-- Real, executable test evidence for FIN-203 (Double-Entry Journal,
-- CG-S9-FIN-014) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: the one shared balance rule rejects insufficient lines, an
-- invalid direction, a non-positive amount and an unbalanced set before any
-- row is written; manual journal account validation (unknown/inactive/
-- not-postable account, each a distinct named exception); idempotent
-- manual draft creation; the full draft -> submitted -> approved -> posted
-- lifecycle with the correct FIN:Edit/FIN:Approve authority split and
-- idempotent posting; the discard boundary; the system (subledger-sourced)
-- posting path creates and posts exactly one journal immediately, mirrors
-- the subledger batch's own resolved lines exactly, and sets that batch's
-- own gl_journal_id -- closing FIN-202's own disclosed forward reference;
-- list/lines and cross-tenant isolation; schema-privilege defense in
-- depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets one open fiscal period (2026-03), a small real chart of accounts, and a published finance_posting_map (for the system-journal scenario group)'
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
    ('00000000-0000-0000-0000-000000029801', 'admina@acmejrnl.test'),
    ('00000000-0000-0000-0000-000000029802', 'financemanagera@acmejrnl.test'),
    ('00000000-0000-0000-0000-000000029803', 'financeeditora@acmejrnl.test'),
    ('00000000-0000-0000-0000-000000029804', 'plainusera@acmejrnl.test'),
    ('00000000-0000-0000-0000-000000029805', 'financemanagerb@acmejrnl.test');

  perform app.provision_tenant('acmejrnla', 'Acme Journal A', 'idem-acmejrnla', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmejrnla');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEJRNLA-CO', 'Acme Journal A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEJRNLA-CO');

  perform app.provision_tenant('acmejrnlb', 'Acme Journal B', 'idem-acmejrnlb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmejrnlb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEJRNLB-CO', 'Acme Journal B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEJRNLB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029801', 'admina@acmejrnl.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmejrnl.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029801', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029802', 'financemanagera@acmejrnl.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmejrnl.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029802', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029803', 'financeeditora@acmejrnl.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmejrnl.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Journal authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000029802', '00000000-0000-0000-0000-000000029801', 'tester');
  -- HDN-373 (ISS-2026-181, maker/checker): admina also holds Finance Manager so this
  -- file's own new self-approval regression block below has a genuinely distinct
  -- FIN:Approve holder to approve/post what financemanagera submitted.
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000029801', '00000000-0000-0000-0000-000000029801', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000029803', '00000000-0000-0000-0000-000000029801', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029804', 'plainusera@acmejrnl.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmejrnl.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000029805', 'financemanagerb@acmejrnl.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmejrnl.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Journal authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000029805', '00000000-0000-0000-0000-000000029805', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000029802', 'financemanagera');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-JRNL', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-JRNL', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'AR-JRNL', 'Accounts Receivable', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'GL-CONTROL-JRNL', 'Non-Postable Control', 'asset', 'debit', null, true, null, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  perform app.create_finance_account_draft(v_tenant_a, null, 'DRAFT-JRNL', 'Never Activated', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029802', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'ar_control', 'value', jsonb_build_object('accountCodeRef', 'AR-JRNL')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-JRNL'))
  ), '00000000-0000-0000-0000-000000029802', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000029802', null, 'financemanagera');
end;
$$;

\echo '>> shared balance rule and manual journal validation: Plain User A is denied; insufficient lines, an unsupported currency, an invalid direction, a non-positive amount, an unbalanced set, an unknown account, a not-postable account, and a never-activated account are each rejected with a distinct named exception; a real balanced 2-line draft posts with the exact total, and a retried call with the same idempotency_key returns it unchanged'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_np_id uuid;
  v_draft_only_id uuid;
  v_journal app.finance_journals;
  v_retry app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmejrnla');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-JRNL');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-JRNL');
  v_np_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'GL-CONTROL-JRNL');
  v_draft_only_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'DRAFT-JRNL');

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 100),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 100)
      ), 'jrnl-denied-1', '00000000-0000-0000-0000-000000029804', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
      jsonb_build_array(jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 100)),
      'jrnl-insufficient-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_insufficient_lines for a single line';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_insufficient_lines' then
        raise exception 'assertion failed: expected finance_journal_insufficient_lines, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'ZZZ',
      jsonb_build_array(
        jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 100),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 100)
      ), 'jrnl-badcur-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_unsupported_currency';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_unsupported_currency' then
        raise exception 'assertion failed: expected finance_journal_unsupported_currency, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_cash_id, 'direction', 'sideways', 'amount', 100),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 100)
      ), 'jrnl-baddir-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_invalid_direction';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_invalid_direction' then
        raise exception 'assertion failed: expected finance_journal_invalid_direction, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 0),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 100)
      ), 'jrnl-badamt-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_invalid_line_amount for a zero amount';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_invalid_line_amount' then
        raise exception 'assertion failed: expected finance_journal_invalid_line_amount, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 100),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 90)
      ), 'jrnl-unbalanced-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_unbalanced';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_unbalanced' then
        raise exception 'assertion failed: expected finance_journal_unbalanced, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', gen_random_uuid(), 'direction', 'debit', 'amount', 100),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 100)
      ), 'jrnl-unknownacct-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_account_not_found';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_account_not_found' then
        raise exception 'assertion failed: expected finance_journal_account_not_found, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_np_id, 'direction', 'debit', 'amount', 100),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 100)
      ), 'jrnl-notpostable-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_not_postable_account';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_not_postable_account' then
        raise exception 'assertion failed: expected finance_journal_not_postable_account, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_draft_only_id, 'direction', 'debit', 'amount', 100),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 100)
      ), 'jrnl-inactive-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_inactive_account for a never-activated account';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_inactive_account' then
        raise exception 'assertion failed: expected finance_journal_inactive_account, got %', sqlerrm;
      end if;
  end;

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 500, 'description', 'opening cash'),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 500, 'description', 'opening revenue')
    ), 'jrnl-real-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
  if v_journal.status <> 'draft' or v_journal.total_amount <> 500 or v_journal.source_type <> 'manual' then
    raise exception 'assertion failed: expected a draft manual journal of total_amount 500, got status=% total=% source=%', v_journal.status, v_journal.total_amount, v_journal.source_type;
  end if;

  -- FIN-208: a byte-identical retry (same date/currency/lines) under the same idempotency_key returns the original journal unchanged.
  select * into v_retry from app.create_finance_journal_draft(v_tenant_a, null, '2026-03-05'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 500, 'description', 'opening cash'),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 500, 'description', 'opening revenue')
    ), 'jrnl-real-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
  if v_retry.id <> v_journal.id or v_retry.total_amount <> 500 then
    raise exception 'assertion failed: expected a retried draft with the same idempotency_key to return the original journal unchanged, got id=% total=%', v_retry.id, v_retry.total_amount;
  end if;

  -- FIN-208: the identical idempotency_key reused with a genuinely different request (a different single-line payload) is now a named conflict, never a silent return of the original.
  begin
    perform app.create_finance_journal_draft(v_tenant_a, null, '2026-03-06'::date, 'USD',
      jsonb_build_array(jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 9999)),
      'jrnl-real-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_idempotency_fingerprint_conflict for a reused key with a different payload';
  exception
    when others then
      if sqlerrm !~ 'finance_idempotency_fingerprint_conflict' then
        raise exception 'assertion failed: expected finance_idempotency_fingerprint_conflict, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> manual journal lifecycle authority split: Finance Editor A (no Approve) submits but cannot approve or post; Finance Manager A approves and posts; posting is idempotent and journal_number is assigned only at post time; discard boundary rejects an approved journal'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_journal app.finance_journals;
  v_retry app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmejrnla');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-JRNL');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-JRNL');

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-03-07'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 250),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 250)
    ), 'jrnl-lifecycle-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
  if v_journal.journal_number is not null then
    raise exception 'assertion failed: expected journal_number to remain null before posting, got %', v_journal.journal_number;
  end if;

  select * into v_journal from app.submit_finance_journal_for_approval(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029803', 'financeeditora');
  if v_journal.status <> 'submitted' then
    raise exception 'assertion failed: expected status submitted, got %', v_journal.status;
  end if;

  begin
    perform app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029803', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_journal from app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  if v_journal.status <> 'approved' then
    raise exception 'assertion failed: expected status approved, got %', v_journal.status;
  end if;

  begin
    perform app.discard_finance_journal_draft(v_journal.id, v_journal.record_version, 'too late', '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_not_cancellable -- an approved journal must not be discardable';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_not_cancellable' then
        raise exception 'assertion failed: expected finance_journal_not_cancellable, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029803', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve to post';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_journal from app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  if v_journal.status <> 'posted' or v_journal.journal_number is null or v_journal.journal_number !~ '^JRNL-2026-' then
    raise exception 'assertion failed: expected status posted with an assigned JRNL-2026-* journal_number, got status=% number=%', v_journal.status, v_journal.journal_number;
  end if;

  select * into v_retry from app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');
  if v_retry.id <> v_journal.id or v_retry.journal_number <> v_journal.journal_number then
    raise exception 'assertion failed: expected a retried post to return the same posted journal unchanged, got id=% number=%', v_retry.id, v_retry.journal_number;
  end if;
end;
$$;

\echo '>> system (subledger-sourced) journal: posting a subledger batch creates and posts exactly one matching journal immediately, mirroring the batch''s own resolved lines, and sets the batch''s own gl_journal_id; a retried subledger post never creates a second journal'
do $$
declare
  v_tenant_a uuid;
  v_source_id uuid := gen_random_uuid();
  v_batch app.finance_subledger_batches;
  v_retry_batch app.finance_subledger_batches;
  v_journal app.finance_journals;
  v_journal_lines app.finance_journal_lines[];
  v_journal_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmejrnla');

  select * into v_batch from app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-08'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 1200),
      jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', 1200)
    ),
    '00000000-0000-0000-0000-000000029802', 'financemanagera');

  if v_batch.gl_journal_id is null then
    raise exception 'assertion failed: expected the posted subledger batch to carry a real gl_journal_id, got null';
  end if;

  select * into v_journal from app.finance_journals where id = v_batch.gl_journal_id;
  if v_journal.status <> 'posted' or v_journal.source_type <> 'subledger' or v_journal.source_id <> v_batch.id or v_journal.total_amount <> 1200 or v_journal.journal_number !~ '^JRNL-2026-' then
    raise exception 'assertion failed: expected a posted system journal (source_type=subledger, source_id=batch.id, total=1200), got status=% source_type=% source_id=% total=% number=%',
      v_journal.status, v_journal.source_type, v_journal.source_id, v_journal.total_amount, v_journal.journal_number;
  end if;

  select array_agg(r order by r.line_number) into v_journal_lines from app.finance_journal_lines r where journal_id = v_journal.id;
  if array_length(v_journal_lines, 1) <> 2 or v_journal_lines[1].direction <> 'debit' or v_journal_lines[1].amount <> 1200 or v_journal_lines[2].direction <> 'credit' or v_journal_lines[2].amount <> 1200 then
    raise exception 'assertion failed: expected exactly 2 mirrored lines (debit 1200 / credit 1200), got %', v_journal_lines;
  end if;

  -- A retried subledger post (same tenant/source_type/source_id) is
  -- idempotent at the batch layer and must never create a second journal.
  select * into v_retry_batch from app.post_finance_subledger_batch(v_tenant_a, null, 'invoice', v_source_id, '2026-03-08'::date, 'USD',
    jsonb_build_array(jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', 9999)),
    '00000000-0000-0000-0000-000000029802', 'financemanagera');
  if v_retry_batch.id <> v_batch.id or v_retry_batch.gl_journal_id <> v_batch.gl_journal_id then
    raise exception 'assertion failed: expected a retried subledger post to return the same batch/journal unchanged, got batch=%/journal=%', v_retry_batch.id, v_retry_batch.gl_journal_id;
  end if;

  select count(*) into v_journal_count from app.finance_journals where tenant_id = v_tenant_a and source_type = 'subledger' and source_id = v_batch.id;
  if v_journal_count <> 1 then
    raise exception 'assertion failed: expected exactly one system journal for this subledger batch, found %', v_journal_count;
  end if;
end;
$$;

\echo '>> list/lines and cross-tenant isolation: filtering by source_type/status returns only matching journals; Finance Manager B sees zero of tenant A''s own journals'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_manual_rows app.finance_journals[];
  v_cross_rows app.finance_journals[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmejrnla');
  v_tenant_b := (select id from app.tenants where slug = 'acmejrnlb');

  select array_agg(r) into v_manual_rows from app.list_finance_journals(v_tenant_a, null, 'manual', 'posted', '00000000-0000-0000-0000-000000029802') r;
  if v_manual_rows is null or exists (select 1 from unnest(v_manual_rows) r where r.source_type <> 'manual' or r.status <> 'posted') then
    raise exception 'assertion failed: expected list_finance_journals filtered by source_type=manual/status=posted to return only matching rows, got %', v_manual_rows;
  end if;

  select array_agg(r) into v_cross_rows from app.list_finance_journals(v_tenant_b, null, null, null, '00000000-0000-0000-0000-000000029805') r;
  if v_cross_rows is not null and exists (select 1 from unnest(v_cross_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_journals to never return a tenant A row';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-203 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'touch_finance_journal_row', 'check_finance_journal_authority', 'validate_finance_journal_line_balance',
    'create_finance_journal_draft', 'submit_finance_journal_for_approval', 'discard_finance_journal_draft',
    'approve_finance_journal', 'post_finance_journal', 'create_and_post_finance_system_journal',
    'list_finance_journals', 'get_finance_journal_lines'
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

\echo '>> audit trail: at least one create/approve/post event was captured for tenant A''s own journal activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmejrnla');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('create_finance_journal_draft', 'approve_finance_journal', 'post_finance_journal', 'create_and_post_finance_system_journal');
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 audit events across this fixture''s own journal lifecycle calls, found %', v_count;
  end if;
end;
$$;

\echo '>> HDN-373 (ISS-2026-181, maker/checker): app.approve_finance_journal/app.post_finance_journal deny an identity approving or posting its own submission; a genuinely distinct FIN:Approve holder succeeds'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_journal app.finance_journals;
  v_denied boolean := false;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmejrnla');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-JRNL');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-JRNL');

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-03-20'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 250),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 250)
    ), 'jrnl-selfapproval-1', '00000000-0000-0000-0000-000000029802', 'financemanagera');
  select * into v_journal from app.submit_finance_journal_for_approval(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');

  begin
    perform app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected financemanagera to be denied approving its own submission, but the call succeeded';
  exception
    when others then
      if sqlerrm !~ '^self_approval_denied' then
        raise;
      end if;
      v_denied := true;
  end;
  if not v_denied then
    raise exception 'assertion failed: expected a self_approval_denied exception, got none';
  end if;

  select * into v_journal from app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029801', 'admina');
  if v_journal.status <> 'approved' then
    raise exception 'assertion failed: expected admina (a genuinely distinct FIN:Approve holder) to approve successfully, got status=%', v_journal.status;
  end if;

  v_denied := false;
  begin
    perform app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029802', 'financemanagera');
    raise exception 'assertion failed: expected financemanagera to be denied posting the journal it submitted, but the call succeeded';
  exception
    when others then
      if sqlerrm !~ '^self_approval_denied' then
        raise;
      end if;
      v_denied := true;
  end;
  if not v_denied then
    raise exception 'assertion failed: expected a self_approval_denied exception on post, got none';
  end if;

  select * into v_journal from app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029801', 'admina');
  if v_journal.status <> 'posted' then
    raise exception 'assertion failed: expected admina to post successfully, got status=%', v_journal.status;
  end if;
end;
$$;

\echo '>> HDN-373 (Finding B): app.finance_journals/app.finance_journal_lines RLS now requires FIN:View, not membership alone -- live-forced with genuine authenticated sessions, not superuser'
do $$
declare
  v_tenant_a uuid;
  v_viewer_count integer;
  v_zero_perm_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmejrnla');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000029802", "role": "authenticated"}';
  select count(*) into v_viewer_count from app.finance_journals where tenant_id = v_tenant_a;
  reset role;
  if v_viewer_count = 0 then
    raise exception 'assertion failed: expected financemanagera (holds FIN:View) to read at least one real journal row directly via RLS, got 0';
  end if;

  -- HDN-373 (Finding B): before this checkpoint's fix, tenant membership alone admitted
  -- a raw client read of every journal row; plainusera holds active membership and zero
  -- FIN permissions, so this must now return 0, not the same rows financemanagera saw.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000029804", "role": "authenticated"}';
  select count(*) into v_zero_perm_count from app.finance_journals where tenant_id = v_tenant_a;
  reset role;
  if v_zero_perm_count <> 0 then
    raise exception 'assertion failed: expected plainusera (active member, zero FIN permissions) to read 0 rows from app.finance_journals directly via RLS, got %', v_zero_perm_count;
  end if;
end;
$$;
