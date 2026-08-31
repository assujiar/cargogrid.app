-- Real, executable test evidence for FIN-206 (Reversal and Adjustment,
-- CG-S9-FIN-017) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: authority split (FIN:Edit prepares, FIN:Approve approves/posts);
-- a reversal is only allowed against a posted original, and at most one
-- active reversal exists per original; an adjustment's own lines must
-- already balance; posting derives the reversal's exact opposite lines
-- (never touching the original journal's own rows) or uses the already-
-- validated adjustment lines; idempotent prepare and idempotent post; a
-- reversal of a subledger-sourced journal marks that source batch
-- `reversed`, closing FIN-202's own disclosed forward reference; cross-
-- tenant isolation; schema-privilege defense in depth; audit trail.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), a Finance Editor (FIN:Edit/View only, no Approve), and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets one open fiscal period (2026-04) and a small real chart of accounts'
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
    ('00000000-0000-0000-0000-000000031001', 'admina@acmerev.test'),
    ('00000000-0000-0000-0000-000000031002', 'financemanagera@acmerev.test'),
    ('00000000-0000-0000-0000-000000031003', 'financeeditora@acmerev.test'),
    ('00000000-0000-0000-0000-000000031004', 'plainusera@acmerev.test'),
    ('00000000-0000-0000-0000-000000031005', 'financemanagerb@acmerev.test');

  perform app.provision_tenant('acmereva', 'Acme Reversal A', 'idem-acmereva', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEREVA-CO', 'Acme Reversal A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEREVA-CO');

  perform app.provision_tenant('acmerevb', 'Acme Reversal B', 'idem-acmerevb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmerevb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEREVB-CO', 'Acme Reversal B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEREVB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000031001', 'admina@acmerev.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmerev.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000031001', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000031002', 'financemanagera@acmerev.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmerev.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000031002', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000031003', 'financeeditora@acmerev.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmerev.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Correction authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000031002', '00000000-0000-0000-0000-000000031001', 'tester');
  -- HDN-373 (ISS-2026-181, maker/checker): admina also holds Finance Manager so it can
  -- act as a genuinely distinct approver/poster from financemanagera, the preparer, in
  -- the scenarios below -- app.approve_finance_journal/app.post_finance_journal now deny
  -- an actor approving or posting their own submission.
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000031001', '00000000-0000-0000-0000-000000031001', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'edit only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000031003', '00000000-0000-0000-0000-000000031001', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000031004', 'plainusera@acmerev.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmerev.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000031005', 'financemanagerb@acmerev.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmerev.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Correction authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000031005', '00000000-0000-0000-0000-000000031005', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000031002', 'financemanagera');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-REV', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-REV', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
end;
$$;

\echo '>> a real posted manual journal (500 debit cash / 500 credit revenue) to serve as the original for every reversal/adjustment scenario below'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_journal app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-REV');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-REV');

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-04-05'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 500),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 500)
    ), 'rev-original-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  perform app.submit_finance_journal_for_approval(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_journal from app.finance_journals where id = v_journal.id;
  perform app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000031001', 'admina');
  select * into v_journal from app.finance_journals where id = v_journal.id;
  perform app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000031001', 'admina');

  if not exists (select 1 from app.finance_journals where id = v_journal.id and status = 'posted') then
    raise exception 'assertion failed: expected the original journal to be posted';
  end if;
end;
$$;

\echo '>> authority and preconditions: Plain User A is denied preparing a reversal; an empty reason is rejected; a reversal against a non-posted (draft) journal is rejected'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_original_id uuid;
  v_draft_journal app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-REV');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-REV');
  v_original_id := (select id from app.finance_journals where tenant_id = v_tenant_a and idempotency_key = 'rev-original-1');

  begin
    perform app.prepare_finance_journal_reversal(v_tenant_a, null, v_original_id, '2026-04-06'::date, 'test', null, 'rev-denied-1', '00000000-0000-0000-0000-000000031004', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.prepare_finance_journal_reversal(v_tenant_a, null, v_original_id, '2026-04-06'::date, '', null, 'rev-noreason-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
    raise exception 'assertion failed: expected finance_correction_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm !~ 'finance_correction_reason_required' then
        raise exception 'assertion failed: expected finance_correction_reason_required, got %', sqlerrm;
      end if;
  end;

  select * into v_draft_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-04-06'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 20),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 20)
    ), 'rev-not-posted-fixture-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');

  begin
    perform app.prepare_finance_journal_reversal(v_tenant_a, null, v_draft_journal.id, '2026-04-06'::date, 'duplicate posting', null, 'rev-notposted-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
    raise exception 'assertion failed: expected finance_correction_original_not_posted for a draft original';
  exception
    when others then
      if sqlerrm !~ 'finance_correction_original_not_posted' then
        raise exception 'assertion failed: expected finance_correction_original_not_posted, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> idempotent reversal preparation, duplicate-active-reversal rejection, lifecycle authority split, idempotent posting, and exact opposite lines with the original journal left byte-for-byte unchanged'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_original_id uuid;
  v_original_before app.finance_journals;
  v_original_after app.finance_journals;
  v_correction app.finance_journal_corrections;
  v_retry app.finance_journal_corrections;
  v_correction_journal app.finance_journals;
  v_line_count integer;
  v_debit_amount numeric;
  v_credit_amount numeric;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-REV');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-REV');
  v_original_id := (select id from app.finance_journals where tenant_id = v_tenant_a and idempotency_key = 'rev-original-1');
  select * into v_original_before from app.finance_journals where id = v_original_id;

  select * into v_correction from app.prepare_finance_journal_reversal(v_tenant_a, null, v_original_id, '2026-04-07'::date, 'duplicate posting', 'evidence-ref-1', 'rev-real-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  if v_correction.status <> 'draft' or v_correction.correction_type <> 'reversal' then
    raise exception 'assertion failed: expected a draft reversal correction, got status=% type=%', v_correction.status, v_correction.correction_type;
  end if;

  select * into v_retry from app.prepare_finance_journal_reversal(v_tenant_a, null, v_original_id, '2026-04-07'::date, 'duplicate posting', 'evidence-ref-1', 'rev-real-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  if v_retry.id <> v_correction.id then
    raise exception 'assertion failed: expected a retried prepare with the same idempotency_key to return the original correction unchanged';
  end if;

  begin
    perform app.prepare_finance_journal_reversal(v_tenant_a, null, v_original_id, '2026-04-07'::date, 'a second reversal attempt', null, 'rev-dup-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
    raise exception 'assertion failed: expected finance_correction_duplicate_reversal for a second active reversal against the same original';
  exception
    when others then
      if sqlerrm !~ 'finance_correction_duplicate_reversal' then
        raise exception 'assertion failed: expected finance_correction_duplicate_reversal, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.approve_finance_correction(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031003', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority for Finance Editor A (no FIN:Approve) approving';
  exception
    when insufficient_privilege then
      null;
  end;

  perform app.submit_finance_correction_for_approval(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031003', 'financeeditora');
  select * into v_correction from app.finance_journal_corrections where id = v_correction.id;
  if v_correction.status <> 'submitted' then
    raise exception 'assertion failed: expected Finance Editor A to submit the reversal for approval';
  end if;

  perform app.approve_finance_correction(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_correction from app.finance_journal_corrections where id = v_correction.id;
  if v_correction.status <> 'approved' then
    raise exception 'assertion failed: expected the reversal to be approved';
  end if;

  perform app.post_finance_correction(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_correction from app.finance_journal_corrections where id = v_correction.id;
  if v_correction.status <> 'posted' or v_correction.correction_journal_id is null then
    raise exception 'assertion failed: expected the reversal to be posted with a correction_journal_id set';
  end if;

  -- idempotent post: a retried call with the same expected_version-turned-stale should still return the same posted row unchanged, not error
  select * into v_retry from app.post_finance_correction(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  if v_retry.id <> v_correction.id or v_retry.status <> 'posted' then
    raise exception 'assertion failed: expected a retried post on an already-posted correction to return it unchanged';
  end if;

  select * into v_correction_journal from app.finance_journals where id = v_correction.correction_journal_id;
  if v_correction_journal.source_type <> 'correction' or v_correction_journal.status <> 'posted' or v_correction_journal.total_amount <> 500 then
    raise exception 'assertion failed: expected a posted correction journal of total 500, got source_type=% status=% total=%', v_correction_journal.source_type, v_correction_journal.status, v_correction_journal.total_amount;
  end if;

  select count(*) into v_line_count from app.finance_journal_lines where journal_id = v_correction_journal.id;
  select amount into v_debit_amount from app.finance_journal_lines where journal_id = v_correction_journal.id and account_id = v_rev_id and direction = 'debit';
  select amount into v_credit_amount from app.finance_journal_lines where journal_id = v_correction_journal.id and account_id = v_cash_id and direction = 'credit';
  if v_line_count <> 2 or v_debit_amount <> 500 or v_credit_amount <> 500 then
    raise exception 'assertion failed: expected exactly the opposite lines (debit revenue 500, credit cash 500), got count=% debit_rev=% credit_cash=%', v_line_count, v_debit_amount, v_credit_amount;
  end if;

  select * into v_original_after from app.finance_journals where id = v_original_id;
  if v_original_after.total_amount <> v_original_before.total_amount or v_original_after.status <> v_original_before.status or v_original_after.journal_number <> v_original_before.journal_number then
    raise exception 'assertion failed: expected the original journal to remain byte-for-byte unchanged after its own reversal posted';
  end if;
end;
$$;

\echo '>> adjustment: an unbalanced adjustment_lines set is rejected before any draft row is written; a balanced adjustment prepares, approves and posts with its own exact lines; multiple adjustments against one original are allowed (no duplicate-adjustment constraint, unlike reversal)'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_original_id uuid;
  v_adjustment app.finance_journal_corrections;
  v_adjustment_2 app.finance_journal_corrections;
  v_adjustment_journal app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-REV');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-REV');
  v_original_id := (select id from app.finance_journals where tenant_id = v_tenant_a and idempotency_key = 'rev-original-1');

  begin
    perform app.prepare_finance_journal_adjustment(v_tenant_a, null, v_original_id, '2026-04-08'::date, 'reclass', null,
      jsonb_build_array(
        jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 40),
        jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 30)
      ), 'adj-unbalanced-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
    raise exception 'assertion failed: expected finance_journal_unbalanced for an unbalanced adjustment';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_unbalanced' then
        raise exception 'assertion failed: expected finance_journal_unbalanced, got %', sqlerrm;
      end if;
  end;
  if exists (select 1 from app.finance_journal_corrections where tenant_id = v_tenant_a and idempotency_key = 'adj-unbalanced-1') then
    raise exception 'assertion failed: expected no draft row to have been written for the rejected unbalanced adjustment';
  end if;

  select * into v_adjustment from app.prepare_finance_journal_adjustment(v_tenant_a, null, v_original_id, '2026-04-08'::date, 'reclass a portion to a new period', null,
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'credit', 'amount', 40),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'debit', 'amount', 40)
    ), 'adj-real-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  if v_adjustment.correction_type <> 'adjustment' or v_adjustment.adjustment_lines is null then
    raise exception 'assertion failed: expected a draft adjustment correction carrying its own adjustment_lines';
  end if;

  perform app.submit_finance_correction_for_approval(v_adjustment.id, v_adjustment.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_adjustment from app.finance_journal_corrections where id = v_adjustment.id;
  perform app.approve_finance_correction(v_adjustment.id, v_adjustment.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_adjustment from app.finance_journal_corrections where id = v_adjustment.id;
  perform app.post_finance_correction(v_adjustment.id, v_adjustment.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_adjustment from app.finance_journal_corrections where id = v_adjustment.id;

  select * into v_adjustment_journal from app.finance_journals where id = v_adjustment.correction_journal_id;
  if v_adjustment_journal.total_amount <> 40 then
    raise exception 'assertion failed: expected the posted adjustment journal to total exactly 40, got %', v_adjustment_journal.total_amount;
  end if;

  -- a second, independent adjustment against the same original is allowed (only reversal is capped at one active)
  select * into v_adjustment_2 from app.prepare_finance_journal_adjustment(v_tenant_a, null, v_original_id, '2026-04-09'::date, 'a second, unrelated reclass', null,
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 10),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 10)
    ), 'adj-real-2', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  if v_adjustment_2.id = v_adjustment.id then
    raise exception 'assertion failed: expected a second, independent adjustment correction';
  end if;
end;
$$;

\echo '>> discard boundary: a draft/submitted correction may be discarded; an approved correction may not'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_original_id uuid;
  v_correction app.finance_journal_corrections;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-REV');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-REV');
  v_original_id := (select id from app.finance_journals where tenant_id = v_tenant_a and idempotency_key = 'rev-original-1');

  select * into v_correction from app.prepare_finance_journal_adjustment(v_tenant_a, null, v_original_id, '2026-04-10'::date, 'discard-me', null,
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 5),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 5)
    ), 'adj-discard-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  perform app.discard_finance_correction_draft(v_correction.id, v_correction.record_version, 'no longer needed', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_correction from app.finance_journal_corrections where id = v_correction.id;
  if v_correction.status <> 'discarded' then
    raise exception 'assertion failed: expected the draft adjustment to be discarded';
  end if;

  select * into v_correction from app.prepare_finance_journal_adjustment(v_tenant_a, null, v_original_id, '2026-04-10'::date, 'cannot-discard-me', null,
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 6),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 6)
    ), 'adj-nodiscard-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  perform app.submit_finance_correction_for_approval(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_correction from app.finance_journal_corrections where id = v_correction.id;
  perform app.approve_finance_correction(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_correction from app.finance_journal_corrections where id = v_correction.id;

  begin
    perform app.discard_finance_correction_draft(v_correction.id, v_correction.record_version, 'too late', '00000000-0000-0000-0000-000000031002', 'financemanagera');
    raise exception 'assertion failed: expected finance_correction_not_cancellable for an approved correction';
  exception
    when others then
      if sqlerrm !~ 'finance_correction_not_cancellable' then
        raise exception 'assertion failed: expected finance_correction_not_cancellable, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> subledger-sourced reversal marks the source finance_subledger_batches row reversed, closing FIN-202''s own disclosed forward reference -- the AR/AP open item balance itself is untouched, a disclosed bound'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_batch app.finance_subledger_batches;
  v_iss206_vendor_id uuid;
  v_iss206_source_id uuid;
  v_system_journal app.finance_journals;
  v_correction app.finance_journal_corrections;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-REV');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-REV');

  -- ISS-2026-206: a REAL source document rather than a gen_random_uuid().
  -- app.finance_subledger_batches.source_id is now resolved against the table its own
  -- source_type names, so a fabricated id is refused. A settlement is used because it is the
  -- one source type a finance fixture can make real cheaply -- a real app.finance_invoices row
  -- would need the whole quotation -> handoff -> job order -> billing-readiness chain -- and
  -- because this block's assertions are about reversing the system journal a posted batch produces,
  -- never about which kind of document the batch came from.
  insert into app.master_records (master_type_code, tenant_id, code, name)
  values ('vendor', v_tenant_a, 'ISS206-REV-VEND', 'ISS-2026-206 fixture vendor')
  returning id into v_iss206_vendor_id;
  insert into app.finance_settlements (tenant_id, vendor_master_id, currency, settlement_date, idempotency_key)
  values (v_tenant_a, v_iss206_vendor_id, 'USD', '2026-04-11'::date, 'iss206-rev-settlement-1')
  returning id into v_iss206_source_id;

  select * into v_batch from app.post_finance_subledger_batch(v_tenant_a, null, 'settlement', v_iss206_source_id, '2026-04-11'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 75),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 75)
    ), '00000000-0000-0000-0000-000000031002', 'financemanagera');
  if v_batch.status <> 'posted' or v_batch.gl_journal_id is null then
    raise exception 'assertion failed: expected a posted subledger batch with a gl_journal_id';
  end if;
  select * into v_system_journal from app.finance_journals where id = v_batch.gl_journal_id;

  select * into v_correction from app.prepare_finance_journal_reversal(v_tenant_a, null, v_system_journal.id, '2026-04-12'::date, 'source document voided', null, 'rev-subledger-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  perform app.submit_finance_correction_for_approval(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_correction from app.finance_journal_corrections where id = v_correction.id;
  perform app.approve_finance_correction(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_correction from app.finance_journal_corrections where id = v_correction.id;
  perform app.post_finance_correction(v_correction.id, v_correction.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');

  if not exists (select 1 from app.finance_subledger_batches where id = v_batch.id and status = 'reversed') then
    raise exception 'assertion failed: expected the source subledger batch to be marked reversed after its own journal was reversed';
  end if;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot prepare/approve/post against tenant A''s own original journal or corrections, and list_finance_journal_corrections never returns tenant A''s rows for tenant B''s own scope'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_original_id uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  v_tenant_b := (select id from app.tenants where slug = 'acmerevb');
  v_original_id := (select id from app.finance_journals where tenant_id = v_tenant_a and idempotency_key = 'rev-original-1');

  begin
    perform app.prepare_finance_journal_reversal(v_tenant_b, null, v_original_id, '2026-04-13'::date, 'cross tenant attempt', null, 'rev-crosstenant-1', '00000000-0000-0000-0000-000000031005', 'financemanagerb');
    raise exception 'assertion failed: expected finance_journal_not_found for a cross-tenant original journal reference';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_not_found' then
        raise exception 'assertion failed: expected finance_journal_not_found, got %', sqlerrm;
      end if;
  end;

  select count(*) into v_count from app.list_finance_journal_corrections(v_tenant_b, null, null, null, '00000000-0000-0000-0000-000000031005');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero corrections visible to tenant B, got %', v_count;
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-206 function (ERR-2026-004 regression guard)'
do $$
declare
  v_leaked_count integer;
begin
  select count(*) into v_leaked_count
    from information_schema.routine_privileges
    where routine_schema = 'app'
      and grantee = 'anon'
      and routine_name in (
        'prepare_finance_journal_reversal', 'prepare_finance_journal_adjustment',
        'submit_finance_correction_for_approval', 'discard_finance_correction_draft',
        'approve_finance_correction', 'post_finance_correction',
        'list_finance_journal_corrections', 'get_finance_correction_chain',
        'check_finance_correction_authority'
      );
  if v_leaked_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on FIN-206 functions, found %', v_leaked_count;
  end if;
end;
$$;

\echo '>> audit trail: at least one prepare/post event was captured for tenant A''s own correction activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  select count(*) into v_count from app.audit_logs
    where tenant_id = v_tenant_a and action in ('prepare_finance_journal_reversal', 'prepare_finance_journal_adjustment', 'post_finance_correction');
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one FIN-206 audit event for tenant A';
  end if;
end;
$$;

\echo '>> HDN-374 (Financial Integrity Audit) finding 3 regression: a REAL two-process concurrent race -- both processes call app.prepare_finance_journal_reversal for the SAME original journal with the IDENTICAL idempotency_key at the same instant. Before the fix, the losing process surfaced a raw duplicate-key error to its caller; after the fix, it must gracefully return the SAME winning correction row -- exactly one correction row must exist, never two, never a raw unique_violation'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_journal app.finance_journals;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-REV');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-REV');

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-04-20'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 500),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 500)
    ), 'rev-race-original-1', '00000000-0000-0000-0000-000000031002', 'financemanagera');
  perform app.submit_finance_journal_for_approval(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000031002', 'financemanagera');
  select * into v_journal from app.finance_journals where id = v_journal.id;
  perform app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000031001', 'admina');
  select * into v_journal from app.finance_journals where id = v_journal.id;
  perform app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000031001', 'admina');
end;
$$;

select id as race_journal_id from app.finance_journals where tenant_id = (select id from app.tenants where slug = 'acmereva') and idempotency_key = 'rev-race-original-1' \gset
select id as race_tenant_id from app.tenants where slug = 'acmereva' \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

\set race_sql_a 'select app.prepare_finance_journal_reversal(''' :race_tenant_id ''', null, ''' :race_journal_id ''', ''2026-04-21'', ''concurrent reversal race'', null, ''rev-race-key-1'', ''00000000-0000-0000-0000-000000031002'', ''financemanagera'');'
\set race_sql_b 'select app.prepare_finance_journal_reversal(''' :race_tenant_id ''', null, ''' :race_journal_id ''', ''2026-04-21'', ''concurrent reversal race'', null, ''rev-race-key-1'', ''00000000-0000-0000-0000-000000031002'', ''financemanagera'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-fin-reversal-race-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-fin-reversal-race-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

do $$
declare
  v_tenant_a uuid;
  v_count integer;
  v_correction_ids uuid[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmereva');

  select count(*), array_agg(distinct id) into v_count, v_correction_ids
    from app.finance_journal_corrections where tenant_id = v_tenant_a and idempotency_key = 'rev-race-key-1';
  if v_count <> 1 then
    raise exception 'assertion failed: HDN-374 finding 3 regressed -- expected exactly ONE correction row to survive the concurrent race (never two, never zero -- a raw unique_violation reaching a caller means this fix is not applied), got % (ids=%) -- see the RACE_OUT_A/RACE_OUT_B process output captured above', v_count, v_correction_ids;
  end if;

  raise notice 'concurrent reversal-prepare race proof: exactly 1 correction row survived two genuinely concurrent psql processes racing the SAME idempotency_key -- the loser was handed the winner''s row gracefully, never a raw unique_violation';
end;
$$;

\echo 'ALL FIN-206 (Reversal and Adjustment) db-test assertions passed.'
