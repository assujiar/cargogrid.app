-- Real, executable test evidence for CG-AUDIT-2026-09-02 B2a (general ledger
-- trial balance), run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: FIN:View authority gate (a Plain User with no FIN grant is
-- denied); a tenant B Finance Manager cannot read tenant A's trial balance
-- (cross-tenant isolation); only posted journals count (a draft-only
-- journal never moves any balance); only journals dated on/before
-- p_as_of_date count (a future-dated posted journal is excluded); an
-- account touched by more than one journal currency yields one row per
-- currency actually posted against it, never a blended cross-currency sum
-- (this migration's own disclosed limitation); a zero-activity account
-- still appears, at 0/0; company-scoped accounts are filtered the same
-- `company_id is not distinct from p_company_id` way app.list_finance_
-- accounts already establishes; debit_balance/credit_balance are net and
-- mutually exclusive per the standard trial-balance columnar convention;
-- p_as_of_date is required, not silently treated as "no cutoff".

\set ON_ERROR_STOP on

\echo '>> setup: tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View), a Finance Editor (FIN:Edit/View only, no Approve -- submits drafts so the Finance Manager can approve/post them without tripping HDN-373''s own self-approval guard), and a Plain User (no FIN grant), a second company/org unit, an open FY2026 fiscal calendar, and a small real chart of accounts; tenant B gets its own Finance Manager and its own account/journal, for the cross-tenant isolation assertion'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_a2 uuid;
  v_team_b uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_editor_role_a uuid;
  v_editor_draft_a app.role_versions;
  v_manager_role_b uuid;
  v_manager_draft_b app.role_versions;
  v_account app.finance_accounts;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000031901', 'financemanagera@acmetba.test'),
    ('00000000-0000-0000-0000-000000031902', 'plainusera@acmetba.test'),
    ('00000000-0000-0000-0000-000000031903', 'financemanagerb@acmetba.test'),
    ('00000000-0000-0000-0000-000000031904', 'financeeditora@acmetba.test');

  perform app.provision_tenant('acmetba', 'Acme Trial Balance A', 'idem-acmetba', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmetba');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMETBA-CO', 'Acme TB A Co', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMETBA-CO');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMETBA-CO2', 'Acme TB A Co 2', 'tester');
  v_team_a2 := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMETBA-CO2');

  perform app.provision_tenant('acmetbb', 'Acme Trial Balance B', 'idem-acmetbb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmetbb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMETBB-CO', 'Acme TB B Co', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMETBB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000031901', 'financemanagera@acmetba.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmetba.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000031901', 'tenant_admin', v_tenant_a, null, 'tester');
  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Trial balance authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000031901', '00000000-0000-0000-0000-000000031901', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000031904', 'financeeditora@acmetba.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmetba.test'), 'active', 'onboarded', 'tester');
  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000031904', '00000000-0000-0000-0000-000000031901', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000031902', 'plainusera@acmetba.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmetba.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000031903', 'financemanagerb@acmetba.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmetba.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Trial balance authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000031903', '00000000-0000-0000-0000-000000031903', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026TB', 'FY2026 Monthly', '2026-01-01'::date, 12, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  perform app.generate_finance_fiscal_calendar(v_tenant_b, null, 'FY2026TBB', 'FY2026 Monthly', '2026-01-01'::date, 12, '00000000-0000-0000-0000-000000031903', 'financemanagerb');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-TB', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-TB', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'MULTI-CCY-TB', 'Multi-Currency Holding', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'ZERO-TB', 'Never Posted', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, v_team_a2, 'CO2-CASH-TB', 'Company 2 Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, v_team_a2, 'CO2-REV-TB', 'Company 2 Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000031901', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031901', 'financemanagera');

  select * into v_account from app.create_finance_account_draft(v_tenant_b, null, 'CASH-TBB', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000031903', 'financemanagerb');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031903', 'financemanagerb');
  select * into v_account from app.create_finance_account_draft(v_tenant_b, null, 'REV-TBB', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000031903', 'financemanagerb');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031903', 'financemanagerb');
end;
$$;

\echo '>> helper: pg_temp.tb_post_journal drives the real manual draft -> submit -> approve -> post lifecycle in one call (Finance Editor A submits, Finance Manager A approves/posts -- distinct identities, so HDN-373''s own self-approval guard never trips)'
create function pg_temp.tb_post_journal(
  p_tenant_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_idem_key text
)
returns app.finance_journals
language plpgsql
as $$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.create_finance_journal_draft(
    p_tenant_id, null, p_journal_date, p_currency, p_lines, p_idem_key,
    '00000000-0000-0000-0000-000000031904', 'financeeditora'
  );
  select * into v_journal from app.submit_finance_journal_for_approval(
    v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000031904', 'financeeditora'
  );
  select * into v_journal from app.approve_finance_journal(
    v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000031901', 'financemanagera'
  );
  select * into v_journal from app.post_finance_journal(
    v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000031901', 'financemanagera'
  );
  return v_journal;
end;
$$;

\echo '>> post real journals: two USD postings on CASH-TB/REV-TB inside the cutoff, one future-dated USD posting past the cutoff (must be excluded), two postings in different currencies on MULTI-CCY-TB (must yield two separate rows, never a blended sum), one posting on the company-2-scoped accounts, and one draft-only (never posted) journal that must never move any balance'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_multi_id uuid;
  v_co2_cash_id uuid;
  v_co2_rev_id uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetba');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-TB');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-TB');
  v_multi_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'MULTI-CCY-TB');
  v_co2_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CO2-CASH-TB');
  v_co2_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CO2-REV-TB');

  perform pg_temp.tb_post_journal(v_tenant_a, '2026-02-10'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 1000),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 1000)
    ), 'tb-jrnl-1');

  perform pg_temp.tb_post_journal(v_tenant_a, '2026-02-20'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 400),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 400)
    ), 'tb-jrnl-2');

  -- Future-dated relative to the '2026-03-31' as-of cutoff used below -- must never appear in that read.
  perform pg_temp.tb_post_journal(v_tenant_a, '2026-04-01'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 9999),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 9999)
    ), 'tb-jrnl-3');

  perform pg_temp.tb_post_journal(v_tenant_a, '2026-02-15'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_multi_id, 'direction', 'debit', 'amount', 50),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 50)
    ), 'tb-jrnl-4');

  perform pg_temp.tb_post_journal(v_tenant_a, '2026-02-16'::date, 'EUR',
    jsonb_build_array(
      jsonb_build_object('accountId', v_multi_id, 'direction', 'debit', 'amount', 30),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 30)
    ), 'tb-jrnl-5');

  perform pg_temp.tb_post_journal(v_tenant_a, '2026-02-12'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_co2_cash_id, 'direction', 'debit', 'amount', 250),
      jsonb_build_object('accountId', v_co2_rev_id, 'direction', 'credit', 'amount', 250)
    ), 'tb-jrnl-6');

  -- Draft only, never submitted/approved/posted -- must never move any balance below.
  perform app.create_finance_journal_draft(v_tenant_a, null, '2026-02-18'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 77),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 77)
    ), 'tb-draft-only-1', '00000000-0000-0000-0000-000000031901', 'financemanagera');
end;
$$;

\echo '>> authority: a Plain User with no FIN grant is denied FIN:View; a tenant B Finance Manager cannot read tenant A''s trial balance; p_as_of_date is required'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetba');

  begin
    perform app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031902');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031903');
    raise exception 'assertion failed: expected insufficient_authority for tenant B''s own Finance Manager reading tenant A''s trial balance';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.get_finance_trial_balance(v_tenant_a, null, null, '00000000-0000-0000-0000-000000031901');
    raise exception 'assertion failed: expected finance_trial_balance_as_of_date_required for a null as-of date';
  exception
    when others then
      if sqlerrm !~ 'finance_trial_balance_as_of_date_required' then
        raise exception 'assertion failed: expected finance_trial_balance_as_of_date_required, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> real trial balance, tenant-wide (company_id null): CASH-TB nets 1400 USD debit (the future-dated 9999 and the never-posted draft 77 both excluded), REV-TB nets 1450 USD credit (1000+400+50) and 30 EUR credit, MULTI-CCY-TB shows two separate rows (50 USD debit, 30 EUR debit -- never a blended 80), ZERO-TB appears at 0/0 with a null currency, and the company-2-scoped CO2-CASH-TB/CO2-REV-TB never appear in a p_company_id-null read'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_multi_id uuid;
  v_zero_id uuid;
  v_row record;
  v_row_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetba');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-TB');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-TB');
  v_multi_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'MULTI-CCY-TB');
  v_zero_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'ZERO-TB');

  select count(*) into v_row_count from app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901');
  if v_row_count <> 6 then
    raise exception 'assertion failed: expected exactly 6 rows (CASH-TB, REV-TB x2 currencies, MULTI-CCY-TB x2 currencies, ZERO-TB) for the tenant-wide read, got %', v_row_count;
  end if;

  select * into v_row from app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901')
    where account_id = v_cash_id;
  if v_row.currency <> 'USD' or v_row.debit_balance <> 1400 or v_row.credit_balance <> 0 then
    raise exception 'assertion failed: expected CASH-TB net USD debit 1400 (drafts/future-dated excluded), got currency=% debit=% credit=%', v_row.currency, v_row.debit_balance, v_row.credit_balance;
  end if;

  select * into v_row from app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901')
    where account_id = v_rev_id and currency = 'USD';
  if v_row.debit_balance <> 0 or v_row.credit_balance <> 1450 then
    raise exception 'assertion failed: expected REV-TB net USD credit 1450, got debit=% credit=%', v_row.debit_balance, v_row.credit_balance;
  end if;

  select * into v_row from app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901')
    where account_id = v_rev_id and currency = 'EUR';
  if v_row.debit_balance <> 0 or v_row.credit_balance <> 30 then
    raise exception 'assertion failed: expected REV-TB net EUR credit 30, got debit=% credit=%', v_row.debit_balance, v_row.credit_balance;
  end if;

  if (select count(*) from app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901') where account_id = v_multi_id) <> 2 then
    raise exception 'assertion failed: expected MULTI-CCY-TB to yield exactly 2 rows (one per currency actually posted), never a blended single row';
  end if;
  select * into v_row from app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901')
    where account_id = v_multi_id and currency = 'USD';
  if v_row.debit_balance <> 50 then
    raise exception 'assertion failed: expected MULTI-CCY-TB USD debit 50, got %', v_row.debit_balance;
  end if;
  select * into v_row from app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901')
    where account_id = v_multi_id and currency = 'EUR';
  if v_row.debit_balance <> 30 then
    raise exception 'assertion failed: expected MULTI-CCY-TB EUR debit 30, got %', v_row.debit_balance;
  end if;

  select * into v_row from app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901')
    where account_id = v_zero_id;
  if v_row.currency is not null or v_row.debit_balance <> 0 or v_row.credit_balance <> 0 then
    raise exception 'assertion failed: expected ZERO-TB at null currency, 0/0, got currency=% debit=% credit=%', v_row.currency, v_row.debit_balance, v_row.credit_balance;
  end if;

  if exists (select 1 from app.get_finance_trial_balance(v_tenant_a, null, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901') where account_id in (
    select id from app.finance_accounts where tenant_id = v_tenant_a and code in ('CO2-CASH-TB', 'CO2-REV-TB')
  )) then
    raise exception 'assertion failed: company-2-scoped accounts must never appear in a p_company_id-null (tenant-wide-only) read';
  end if;
end;
$$;

\echo '>> company scoping mirrors app.list_finance_accounts'' own `company_id is not distinct from p_company_id` semantics: passing the company-2 org unit id returns only CO2-CASH-TB/CO2-REV-TB, each with their own real posted balance'
do $$
declare
  v_tenant_a uuid;
  v_team_a2 uuid;
  v_row_count integer;
  v_row record;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetba');
  v_team_a2 := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMETBA-CO2');

  select count(*) into v_row_count from app.get_finance_trial_balance(v_tenant_a, v_team_a2, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901');
  if v_row_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 rows for the company-2-scoped read, got %', v_row_count;
  end if;

  select * into v_row from app.get_finance_trial_balance(v_tenant_a, v_team_a2, '2026-03-31'::date, '00000000-0000-0000-0000-000000031901')
    where account_code = 'CO2-CASH-TB';
  if v_row.debit_balance <> 250 then
    raise exception 'assertion failed: expected CO2-CASH-TB net USD debit 250, got %', v_row.debit_balance;
  end if;
end;
$$;

\echo '>> as-of-date cutoff: reading as of 2026-04-30 includes the future-dated 9999 posting, moving CASH-TB''s net USD debit from 1400 to 11399'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_row record;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmetba');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-TB');

  select * into v_row from app.get_finance_trial_balance(v_tenant_a, null, '2026-04-30'::date, '00000000-0000-0000-0000-000000031901')
    where account_id = v_cash_id;
  if v_row.debit_balance <> 11399 then
    raise exception 'assertion failed: expected CASH-TB net USD debit 11399 once the future-dated posting is within the cutoff, got %', v_row.debit_balance;
  end if;
end;
$$;

\echo '>> schema privilege: app schema is not exposed to PostgREST; the public.* wrapper is the only externally-reachable surface (RGL-394 Option-2), cross-checked exhaustively by scripts/db-tests/public-api-wrapper-regression.sql'
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_finance_trial_balance'
  ) then
    raise exception 'assertion failed: expected a public.get_finance_trial_balance wrapper to exist';
  end if;
end;
$$;

\echo '>> ALL PASSED: finance-trial-balance.sql'
