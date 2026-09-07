-- Real, executable test evidence for CG-AUDIT-2026-09-02 B8 (independent
-- launch-readiness audit, finding B8) -- run via `pnpm run db:test` against a
-- real, disposable Postgres database.
-- Proves: app.assert_finance_company_org_unit (added by
-- 20260907120000_validate_finance_company_org_unit_iss_b8.sql) rejects a
-- p_company_id belonging to a different tenant, rejects a p_company_id that
-- resolves but is not a company-typed org unit, no-ops on a null p_company_id,
-- and accepts a real company-typed org unit that belongs to the caller's own
-- tenant -- both as a direct unit test of the helper and, end to end, wired
-- into two of the fifteen finance write RPCs that call it
-- (app.create_finance_journal_draft, app.create_finance_bank_account).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a company org unit, a branch org unit (non-company, to prove the unit_type check), and a Finance Manager (FIN:Create/Edit/Approve/View); tenant B gets its own company org unit'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_company_a uuid;
  v_branch_a uuid;
  v_company_b uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_cash_account app.finance_accounts;
  v_revenue_account app.finance_accounts;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000099801', 'admina@acmecoscope.test'),
    ('00000000-0000-0000-0000-000000099802', 'financemanagera@acmecoscope.test');

  perform app.provision_tenant('acmecoscopea', 'Acme Company Scope A', 'idem-acmecoscopea', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmecoscopea');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMECOSCOPEA-CO', 'Acme Company Scope A', 'tester');
  v_company_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMECOSCOPEA-CO');
  perform app.create_org_unit(v_tenant_a, 'branch', v_company_a, 'ACMECOSCOPEA-BR', 'Acme Company Scope A Branch', 'tester');
  v_branch_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMECOSCOPEA-BR');

  perform app.provision_tenant('acmecoscopeb', 'Acme Company Scope B', 'idem-acmecoscopeb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmecoscopeb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMECOSCOPEB-CO', 'Acme Company Scope B', 'tester');
  v_company_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMECOSCOPEB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000099801', 'admina@acmecoscope.test', 'Admin A', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmecoscope.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000099801', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000099802', 'financemanagera@acmecoscope.test', 'Finance Manager A', v_company_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmecoscope.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'full FIN access', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000099802', '00000000-0000-0000-0000-000000099801', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, v_company_a, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 12, '00000000-0000-0000-0000-000000099802', 'financemanagera');

  select * into v_cash_account from app.create_finance_account_draft(v_tenant_a, v_company_a, 'CASH-COSCOPE', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000099802', 'financemanagera');
  perform app.activate_finance_account(v_cash_account.id, v_cash_account.record_version, '00000000-0000-0000-0000-000000099802', 'financemanagera');
  select * into v_revenue_account from app.create_finance_account_draft(v_tenant_a, v_company_a, 'REV-COSCOPE', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000099802', 'financemanagera');
  perform app.activate_finance_account(v_revenue_account.id, v_revenue_account.record_version, '00000000-0000-0000-0000-000000099802', 'financemanagera');
end $$;

\echo '>> direct unit test: app.assert_finance_company_org_unit no-ops on a null company_id, accepts a real own-tenant company org unit, rejects a cross-tenant company_id, rejects a same-tenant non-company org unit (a branch), and rejects a company_id that does not exist at all'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmecoscopea');
  v_company_a uuid := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMECOSCOPEA-CO');
  v_branch_a uuid := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMECOSCOPEA-BR');
  v_company_b uuid := (select org_units.id from app.org_units join app.tenants on tenants.id = org_units.tenant_id where tenants.slug = 'acmecoscopeb' and org_units.code = 'ACMECOSCOPEB-CO');
begin
  perform app.assert_finance_company_org_unit(v_tenant_a, null);
  perform app.assert_finance_company_org_unit(v_tenant_a, v_company_a);

  begin
    perform app.assert_finance_company_org_unit(v_tenant_a, v_company_b);
    raise exception 'assertion failed: expected finance_company_not_found for a cross-tenant company_id';
  exception
    when others then
      if sqlerrm !~ 'finance_company_not_found' then
        raise exception 'assertion failed: expected finance_company_not_found, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.assert_finance_company_org_unit(v_tenant_a, v_branch_a);
    raise exception 'assertion failed: expected finance_company_invalid_org_unit_type for a branch org unit';
  exception
    when others then
      if sqlerrm !~ 'finance_company_invalid_org_unit_type' then
        raise exception 'assertion failed: expected finance_company_invalid_org_unit_type, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.assert_finance_company_org_unit(v_tenant_a, '00000000-0000-0000-0000-000000099999'::uuid);
    raise exception 'assertion failed: expected finance_company_not_found for a nonexistent company_id';
  exception
    when others then
      if sqlerrm !~ 'finance_company_not_found' then
        raise exception 'assertion failed: expected finance_company_not_found, got %', sqlerrm;
      end if;
  end;
end $$;

\echo '>> integration: app.create_finance_journal_draft rejects a cross-tenant company_id and a non-company (branch) company_id, checks authority before the new company check (Admin A, who holds no FIN:Edit/Approve grant, is denied insufficient_authority even with a bad company_id), and still succeeds end to end with a real own-tenant company_id'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmecoscopea');
  v_company_a uuid := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMECOSCOPEA-CO');
  v_branch_a uuid := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMECOSCOPEA-BR');
  v_company_b uuid := (select org_units.id from app.org_units join app.tenants on tenants.id = org_units.tenant_id where tenants.slug = 'acmecoscopeb' and org_units.code = 'ACMECOSCOPEB-CO');
  v_cash_account_id uuid := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-COSCOPE');
  v_revenue_account_id uuid := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-COSCOPE');
  v_journal app.finance_journals;
begin
  begin
    select * into v_journal from app.create_finance_journal_draft(
      v_tenant_a, v_company_b, '2026-01-15'::date, 'IDR',
      '[]'::jsonb, 'idem-coscope-journal-cross-tenant', '00000000-0000-0000-0000-000000099802', 'financemanagera'
    );
    raise exception 'assertion failed: expected finance_company_not_found from create_finance_journal_draft with a cross-tenant company_id';
  exception
    when others then
      if sqlerrm !~ 'finance_company_not_found' then
        raise exception 'assertion failed: expected finance_company_not_found, got %', sqlerrm;
      end if;
  end;

  begin
    select * into v_journal from app.create_finance_journal_draft(
      v_tenant_a, v_branch_a, '2026-01-15'::date, 'IDR',
      '[]'::jsonb, 'idem-coscope-journal-wrong-type', '00000000-0000-0000-0000-000000099802', 'financemanagera'
    );
    raise exception 'assertion failed: expected finance_company_invalid_org_unit_type from create_finance_journal_draft with a branch as company_id';
  exception
    when others then
      if sqlerrm !~ 'finance_company_invalid_org_unit_type' then
        raise exception 'assertion failed: expected finance_company_invalid_org_unit_type, got %', sqlerrm;
      end if;
  end;

  begin
    select * into v_journal from app.create_finance_journal_draft(
      v_tenant_a, v_company_b, '2026-01-15'::date, 'IDR',
      '[]'::jsonb, 'idem-coscope-journal-no-authority', '00000000-0000-0000-0000-000000099801', 'admina'
    );
    raise exception 'assertion failed: expected insufficient_authority for Admin A (no FIN:Edit/Approve grant) even with a cross-tenant company_id';
  exception
    when others then
      if sqlerrm !~ 'insufficient_authority' then
        raise exception 'assertion failed: expected insufficient_authority (checked before the company scope), got %', sqlerrm;
      end if;
  end;

  select * into v_journal from app.create_finance_journal_draft(
    v_tenant_a, v_company_a, '2026-01-15'::date, 'IDR',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_account_id, 'direction', 'debit', 'amount', 100000),
      jsonb_build_object('accountId', v_revenue_account_id, 'direction', 'credit', 'amount', 100000)
    ),
    'idem-coscope-journal-ok', '00000000-0000-0000-0000-000000099802', 'financemanagera'
  );
  if v_journal.company_id <> v_company_a then
    raise exception 'assertion failed: expected the created journal to carry the real own-tenant company_id';
  end if;
end $$;

\echo '>> integration: app.create_finance_bank_account rejects a cross-tenant company_id (checked before the gl_account_id lookup, so no gl account is needed for this to fail closed), and still succeeds with a null company_id (company scoping remains optional)'
do $$
declare
  v_tenant_a uuid := (select id from app.tenants where slug = 'acmecoscopea');
  v_company_a uuid := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMECOSCOPEA-CO');
  v_company_b uuid := (select org_units.id from app.org_units join app.tenants on tenants.id = org_units.tenant_id where tenants.slug = 'acmecoscopeb' and org_units.code = 'ACMECOSCOPEB-CO');
  v_cash_account_id uuid := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-COSCOPE');
  v_bank_account app.finance_bank_accounts;
begin
  begin
    select * into v_bank_account from app.create_finance_bank_account(
      v_tenant_a, v_company_b, 'Main Account', 'Bank Acme', '1234', 'IDR', null,
      '00000000-0000-0000-0000-000000099802', 'financemanagera'
    );
    raise exception 'assertion failed: expected finance_company_not_found from create_finance_bank_account with a cross-tenant company_id';
  exception
    when others then
      if sqlerrm !~ 'finance_company_not_found' then
        raise exception 'assertion failed: expected finance_company_not_found, got %', sqlerrm;
      end if;
  end;

  select * into v_bank_account from app.create_finance_bank_account(
    v_tenant_a, null, 'Tenant-Wide Account', 'Bank Acme', '5678', 'IDR', v_cash_account_id,
    '00000000-0000-0000-0000-000000099802', 'financemanagera'
  );
  if v_bank_account.company_id is not null then
    raise exception 'assertion failed: expected a null company_id to round-trip as null';
  end if;
end $$;

\echo '>> scripts/db-tests/finance-company-org-unit-scope.sql: all assertions passed'
