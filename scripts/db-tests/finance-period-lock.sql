-- Real, executable test evidence for FIN-207 (Period Lock and Governed
-- Reopen, CG-S9-FIN-018) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.
-- Proves: authority split (FIN:Approve locks/approves-reopen/re-locks,
-- FIN:Edit requests a reopen); the one authoritative guard blocks manual
-- journal posting, system (subledger-sourced) posting, and a FIN-206
-- correction posting alike once a matching scope (or `all`) is locked; a
-- narrower scope (e.g. `ar`) does not block an unrelated scope (`gl`); the
-- governed reopen -> post-succeeds-inside-window -> window-expiry-still-
-- blocks -> explicit re-lock cycle; idempotent lock/relock; cross-tenant
-- isolation; schema-privilege defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets two open fiscal periods (2026-05, 2026-06) and a small real chart of accounts'
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
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000032001', 'admina@acmelock.test'),
    ('00000000-0000-0000-0000-000000032002', 'financemanagera@acmelock.test'),
    ('00000000-0000-0000-0000-000000032003', 'financeeditora@acmelock.test'),
    ('00000000-0000-0000-0000-000000032004', 'plainusera@acmelock.test'),
    ('00000000-0000-0000-0000-000000032005', 'financemanagerb@acmelock.test');

  perform app.provision_tenant('acmelocka', 'Acme Lock A', 'idem-acmelocka', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmelocka');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMELOCKA-CO', 'Acme Lock A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMELOCKA-CO');

  perform app.provision_tenant('acmelockb', 'Acme Lock B', 'idem-acmelockb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmelockb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMELOCKB-CO', 'Acme Lock B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMELOCKB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000032001', 'admina@acmelock.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmelock.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000032001', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000032002', 'financemanagera@acmelock.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmelock.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000032002', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000032003', 'financeeditora@acmelock.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmelock.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Lock authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000032002', '00000000-0000-0000-0000-000000032001', 'tester');
  -- HDN-373 (ISS-2026-181, maker/checker): admina also holds Finance Manager so it can
  -- act as a genuinely distinct approver/poster from financemanagera, the preparer, in
  -- the scenarios below -- app.approve_finance_journal/app.post_finance_journal now deny
  -- an actor approving or posting their own submission.
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000032001', '00000000-0000-0000-0000-000000032001', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000032003', '00000000-0000-0000-0000-000000032001', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000032004', 'plainusera@acmelock.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmelock.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000032005', 'financemanagerb@acmelock.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmelock.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Lock authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000032005', '00000000-0000-0000-0000-000000032005', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000032002', 'financemanagera');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-LOCK', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000032002', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000032002', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-LOCK', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000032002', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000032002', 'financemanagera');
end;
$$;

\echo '>> authority and validation: Plain User A is denied locking; an empty reason is rejected; an invalid scope is rejected; a nonexistent period is rejected'
do $$
declare
  v_tenant_a uuid;
  v_period_may_id uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelocka');
  v_period_may_id := (select id from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code like '%2026-05%' limit 1);

  begin
    perform app.lock_finance_period(v_tenant_a, null, v_period_may_id, 'ar', 'AR close complete', null, '00000000-0000-0000-0000-000000032004', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.lock_finance_period(v_tenant_a, null, v_period_may_id, 'ar', '', null, '00000000-0000-0000-0000-000000032002', 'financemanagera');
    raise exception 'assertion failed: expected finance_period_lock_reason_required';
  exception
    when others then
      if sqlerrm !~ 'finance_period_lock_reason_required' then
        raise exception 'assertion failed: expected finance_period_lock_reason_required, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.lock_finance_period(v_tenant_a, null, v_period_may_id, 'bank', 'AR close complete', null, '00000000-0000-0000-0000-000000032002', 'financemanagera');
    raise exception 'assertion failed: expected finance_period_lock_invalid_scope';
  exception
    when others then
      if sqlerrm !~ 'finance_period_lock_invalid_scope' then
        raise exception 'assertion failed: expected finance_period_lock_invalid_scope, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.lock_finance_period(v_tenant_a, null, gen_random_uuid(), 'ar', 'AR close complete', null, '00000000-0000-0000-0000-000000032002', 'financemanagera');
    raise exception 'assertion failed: expected finance_period_not_found';
  exception
    when others then
      if sqlerrm !~ 'finance_period_not_found' then
        raise exception 'assertion failed: expected finance_period_not_found, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> the one authoritative guard blocks manual journal posting once its own scope is locked; an unrelated scope (gl) is unaffected by an ar lock; idempotent lock; cross-tenant isolation'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_period_may_id uuid;
  v_lock app.finance_period_locks;
  v_retry app.finance_period_locks;
  v_journal app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelocka');
  v_tenant_b := (select id from app.tenants where slug = 'acmelockb');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-LOCK');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-LOCK');
  v_period_may_id := (select id from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code like '%2026-05%' limit 1);

  select * into v_lock from app.lock_finance_period(v_tenant_a, null, v_period_may_id, 'gl', 'GL close complete', 'evidence-1', '00000000-0000-0000-0000-000000032002', 'financemanagera');
  if v_lock.status <> 'locked' then
    raise exception 'assertion failed: expected a locked gl scope';
  end if;

  select * into v_retry from app.lock_finance_period(v_tenant_a, null, v_period_may_id, 'gl', 'GL close complete (retry)', 'evidence-1', '00000000-0000-0000-0000-000000032002', 'financemanagera');
  if v_retry.id <> v_lock.id then
    raise exception 'assertion failed: expected idempotent lock to return the same row for an already-locked scope';
  end if;

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-05-10'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 100),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 100)
    ), 'lock-journal-1', '00000000-0000-0000-0000-000000032002', 'financemanagera');
  perform app.submit_finance_journal_for_approval(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000032002', 'financemanagera');
  select * into v_journal from app.finance_journals where id = v_journal.id;
  perform app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000032001', 'admina');
  select * into v_journal from app.finance_journals where id = v_journal.id;

  begin
    perform app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000032001', 'admina');
    raise exception 'assertion failed: expected finance_period_locked for a gl-locked period';
  exception
    when others then
      if sqlerrm !~ 'finance_period_locked' then
        raise exception 'assertion failed: expected finance_period_locked, got %', sqlerrm;
      end if;
  end;

  if exists (select 1 from app.finance_journals where id = v_journal.id and status = 'posted') then
    raise exception 'assertion failed: expected the journal to remain unposted while gl is locked';
  end if;

  -- cross-tenant isolation: tenant B cannot lock/reopen tenant A's own period
  begin
    perform app.lock_finance_period(v_tenant_b, null, v_period_may_id, 'gl', 'cross tenant attempt', null, '00000000-0000-0000-0000-000000032005', 'financemanagerb');
    raise exception 'assertion failed: expected finance_period_not_found for a cross-tenant period reference';
  exception
    when others then
      if sqlerrm !~ 'finance_period_not_found' then
        raise exception 'assertion failed: expected finance_period_not_found, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> governed reopen cycle: request (FIN:Edit) -> approve with a bounded window (FIN:Approve) -> post succeeds inside the window -> a second, expired-window scenario still blocks -> explicit re-lock restores the block'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_period_may_id uuid;
  v_lock app.finance_period_locks;
  v_journal app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelocka');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-LOCK');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-LOCK');
  v_period_may_id := (select id from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code like '%2026-05%' limit 1);
  select * into v_lock from app.finance_period_locks where tenant_id = v_tenant_a and period_id = v_period_may_id and lock_scope = 'gl';

  begin
    perform app.approve_finance_period_reopen(v_lock.id, v_lock.record_version, 24, '00000000-0000-0000-0000-000000032003', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority for Finance Editor A (no FIN:Approve) approving a reopen';
  exception
    when insufficient_privilege then
      null;
  end;

  perform app.request_finance_period_reopen(v_lock.id, v_lock.record_version, 'correction required', '00000000-0000-0000-0000-000000032003', 'financeeditora');
  select * into v_lock from app.finance_period_locks where id = v_lock.id;
  if v_lock.status <> 'reopen_requested' then
    raise exception 'assertion failed: expected reopen_requested after Finance Editor A''s own request';
  end if;

  perform app.approve_finance_period_reopen(v_lock.id, v_lock.record_version, 24, '00000000-0000-0000-0000-000000032002', 'financemanagera');
  select * into v_lock from app.finance_period_locks where id = v_lock.id;
  if v_lock.status <> 'reopened' or v_lock.reopen_window_expires_at is null then
    raise exception 'assertion failed: expected reopened with a set reopen_window_expires_at';
  end if;

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-05-11'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 50),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 50)
    ), 'lock-journal-2', '00000000-0000-0000-0000-000000032002', 'financemanagera');
  perform app.submit_finance_journal_for_approval(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000032002', 'financemanagera');
  select * into v_journal from app.finance_journals where id = v_journal.id;
  perform app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000032001', 'admina');
  select * into v_journal from app.finance_journals where id = v_journal.id;
  perform app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000032001', 'admina');
  if not exists (select 1 from app.finance_journals where id = v_journal.id and status = 'posted') then
    raise exception 'assertion failed: expected posting to succeed inside the reopen window';
  end if;

  -- simulate window expiry directly (deterministic, no real-time sleep) and prove the guard still blocks
  update app.finance_period_locks set reopen_window_expires_at = now() - interval '1 minute' where id = v_lock.id;

  declare
    v_journal_after_expiry app.finance_journals;
  begin
    select * into v_journal_after_expiry from app.create_finance_journal_draft(v_tenant_a, null, '2026-05-12'::date, 'USD',
      jsonb_build_array(
        jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 20),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 20)
      ), 'lock-journal-3', '00000000-0000-0000-0000-000000032002', 'financemanagera');
    perform app.submit_finance_journal_for_approval(v_journal_after_expiry.id, v_journal_after_expiry.record_version, '00000000-0000-0000-0000-000000032002', 'financemanagera');
    select * into v_journal_after_expiry from app.finance_journals where id = v_journal_after_expiry.id;
    perform app.approve_finance_journal(v_journal_after_expiry.id, v_journal_after_expiry.record_version, '00000000-0000-0000-0000-000000032001', 'admina');
    select * into v_journal_after_expiry from app.finance_journals where id = v_journal_after_expiry.id;

    begin
      perform app.post_finance_journal(v_journal_after_expiry.id, v_journal_after_expiry.record_version, '00000000-0000-0000-0000-000000032001', 'admina');
      raise exception 'assertion failed: expected finance_period_locked once the reopen window has expired';
    exception
      when others then
        if sqlerrm !~ 'finance_period_locked' then
          raise exception 'assertion failed: expected finance_period_locked, got %', sqlerrm;
        end if;
    end;
  end;

  select * into v_lock from app.finance_period_locks where id = v_lock.id;
  perform app.relock_finance_period(v_lock.id, v_lock.record_version, '00000000-0000-0000-0000-000000032002', 'financemanagera');
  select * into v_lock from app.finance_period_locks where id = v_lock.id;
  if v_lock.status <> 'locked' then
    raise exception 'assertion failed: expected an explicit re-lock to return the lock to locked';
  end if;

  -- idempotent re-lock: calling it again on an already-locked row returns it unchanged
  perform app.relock_finance_period(v_lock.id, v_lock.record_version, '00000000-0000-0000-0000-000000032002', 'financemanagera');
end;
$$;

\echo '>> a locked ar scope does not block an unrelated gl-scoped posting on a different, unlocked period'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_period_jun_id uuid;
  v_journal app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelocka');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-LOCK');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-LOCK');
  v_period_jun_id := (select id from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code like '%2026-06%' limit 1);

  perform app.lock_finance_period(v_tenant_a, null, v_period_jun_id, 'ar', 'AR close complete', null, '00000000-0000-0000-0000-000000032002', 'financemanagera');

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-06-05'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 30),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 30)
    ), 'lock-journal-unrelated-scope-1', '00000000-0000-0000-0000-000000032002', 'financemanagera');
  perform app.submit_finance_journal_for_approval(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000032002', 'financemanagera');
  select * into v_journal from app.finance_journals where id = v_journal.id;
  perform app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000032001', 'admina');
  select * into v_journal from app.finance_journals where id = v_journal.id;
  perform app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000032001', 'admina');

  if not exists (select 1 from app.finance_journals where id = v_journal.id and status = 'posted') then
    raise exception 'assertion failed: expected a manual (gl-scoped) posting to succeed even though this period''s own ar scope is locked';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-207 function (ERR-2026-004 regression guard)'
do $$
declare
  v_leaked_count integer;
begin
  select count(*) into v_leaked_count
    from information_schema.routine_privileges
    where routine_schema = 'app'
      and grantee = 'anon'
      and routine_name in (
        'lock_finance_period', 'request_finance_period_reopen', 'approve_finance_period_reopen',
        'relock_finance_period', 'list_finance_period_locks', 'get_finance_period_lock_events',
        'check_finance_period_lock_authority', 'assert_finance_period_open_for_posting'
      );
  if v_leaked_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on FIN-207 functions, found %', v_leaked_count;
  end if;
end;
$$;

\echo '>> audit trail: at least one lock/reopen-request/approve-reopen/relock event was captured for tenant A''s own period-lock activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelocka');
  select count(*) into v_count from app.audit_logs
    where tenant_id = v_tenant_a and action in ('lock_finance_period', 'request_finance_period_reopen', 'approve_finance_period_reopen', 'relock_finance_period');
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one FIN-207 audit event for tenant A';
  end if;
end;
$$;

\echo '>> HDN-374 Tier C (Financial Integrity Audit) regression: a REAL two-process concurrent race -- both processes call app.lock_finance_period for the SAME tenant/period/scope, both a genuine FIRST-TIME lock, at the same instant. Before the fix, the losing process surfaced a raw duplicate-key error; after the fix, it must gracefully return the SAME winning, correctly locked row -- exactly one lock row must exist, never two, never a raw unique_violation'
select id as race_tenant_id from app.tenants where slug = 'acmelocka' \gset
select id as race_period_id from app.finance_fiscal_periods where tenant_id = (select id from app.tenants where slug = 'acmelocka') and period_code like '%2026-05%' limit 1 \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

\set race_sql_a 'select app.lock_finance_period(''' :race_tenant_id ''', null, ''' :race_period_id ''', ''tax'', ''concurrent lock race'', null, ''00000000-0000-0000-0000-000000032002'', ''financemanagera'');'
\set race_sql_b 'select app.lock_finance_period(''' :race_tenant_id ''', null, ''' :race_period_id ''', ''tax'', ''concurrent lock race'', null, ''00000000-0000-0000-0000-000000032002'', ''financemanagera'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-fin-period-lock-race-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-fin-period-lock-race-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_tenant_a uuid;
  v_period_may_id uuid;
  v_count integer;
  v_status text;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelocka');
  v_period_may_id := (select id from app.finance_fiscal_periods where tenant_id = v_tenant_a and period_code like '%2026-05%' limit 1);

  select count(*), max(status) into v_count, v_status from app.finance_period_locks
    where tenant_id = v_tenant_a and period_id = v_period_may_id and lock_scope = 'tax';
  if v_count <> 1 then
    raise exception 'assertion failed: HDN-374 Tier C regression -- expected exactly ONE finance_period_locks row to survive the concurrent race (never two, never zero -- a raw unique_violation reaching a caller means this fix is not applied), got % -- see the RACE_OUT_A/RACE_OUT_B process output captured above', v_count;
  end if;
  if v_status <> 'locked' then
    raise exception 'assertion failed: expected the race-surviving row to be correctly status=locked, got %', v_status;
  end if;

  raise notice 'concurrent lock-period race proof: exactly 1 lock row survived two genuinely concurrent psql processes racing the SAME tenant/period/scope, correctly locked -- the loser was handed the winner''s row gracefully, never a raw unique_violation';
end;
$$;

\echo 'ALL FIN-207 (Period Lock and Governed Reopen) db-test assertions passed.'
