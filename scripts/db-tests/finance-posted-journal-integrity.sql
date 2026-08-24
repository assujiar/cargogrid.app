-- Real, executable test evidence for FIN-204 (Posted-Journal Integrity,
-- CG-S9-FIN-015) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: the pre-existing repository-wide grant-only protection
-- (`authenticated` has zero UPDATE/DELETE on app.finance_journals at all,
-- a real role-switch attempt denied by Postgres itself, ERR-2026-004);
-- this checkpoint's own NEW table-level trigger additionally blocks a
-- privileged `service_role` direct UPDATE/DELETE against an already-posted
-- journal or its lines (a strictly stronger guard than the grant alone);
-- the guard applies only to posted rows, never a draft one; the RPD-022
-- Supreme Admin bypass is real, permits the mutation, and captures
-- best-effort audit evidence; schema-privilege defense in depth; audit
-- trail.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant with a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin), one open fiscal period, a small chart of accounts, one Global Supreme Admin identity (no supreme_admin grant yet), and one posted manual journal plus one draft manual journal'
do $$
declare
  v_tenant_a uuid;
  v_team_a uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_account app.finance_accounts;
  v_cash_id uuid;
  v_rev_id uuid;
  v_journal app.finance_journals;
  v_draft_journal app.finance_journals;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000029901', 'admina@acmepji.test'),
    ('00000000-0000-0000-0000-000000029902', 'financemanagera@acmepji.test'),
    ('00000000-0000-0000-0000-000000029903', 'supremeadmin@acmepji.test');

  perform app.provision_tenant('acmepjia', 'Acme Posted Journal Integrity A', 'idem-acmepjia', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmepjia');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEPJIA-CO', 'Acme Posted Journal Integrity A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEPJIA-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029901', 'admina@acmepji.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmepji.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029901', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029902', 'financemanagera@acmepji.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmepji.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029902', 'tenant_admin', v_tenant_a, null, 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Journal authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000029902', '00000000-0000-0000-0000-000000029901', 'tester');
  -- HDN-373 (ISS-2026-181, maker/checker): admina also holds Finance Manager so it can
  -- act as a genuinely distinct approver/poster from financemanagera, the preparer, in
  -- the scenarios below -- app.approve_finance_journal/app.post_finance_journal now deny
  -- an actor approving or posting their own submission.
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000029901', '00000000-0000-0000-0000-000000029901', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029903', 'supremeadmin@acmepji.test', 'Global Supreme Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'supremeadmin@acmepji.test'), 'active', 'onboarded', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000029902', 'financemanagera');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-PJI', 'Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029902', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029902', 'financemanagera');
  v_cash_id := v_account.id;
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-PJI', 'Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000029902', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029902', 'financemanagera');
  v_rev_id := v_account.id;

  select * into v_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-03-10'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 800),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 800)
    ), 'pji-posted-1', '00000000-0000-0000-0000-000000029902', 'financemanagera');
  select * into v_journal from app.submit_finance_journal_for_approval(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029902', 'financemanagera');
  select * into v_journal from app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029901', 'admina');
  select * into v_journal from app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029901', 'admina');

  select * into v_draft_journal from app.create_finance_journal_draft(v_tenant_a, null, '2026-03-11'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 50),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 50)
    ), 'pji-draft-1', '00000000-0000-0000-0000-000000029902', 'financemanagera');
end;
$$;

\echo '>> baseline (pre-existing) protection: authenticated has zero UPDATE/DELETE grant on app.finance_journals at all -- a real role-switch attempt is denied by Postgres itself, before this checkpoint''s own trigger is ever reached'
do $$
declare
  v_journal_id uuid;
begin
  select id into v_journal_id from app.finance_journals where idempotency_key = 'pji-posted-1';

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000029902", "role": "authenticated"}';
  begin
    execute format('update app.finance_journals set total_amount = 999 where id = %L', v_journal_id);
    raise exception 'assertion failed: expected authenticated to be denied UPDATE on app.finance_journals entirely, but the statement succeeded';
  exception
    when insufficient_privilege then
      null;
  end;
  reset role;
end;
$$;

\echo '>> new trigger-level protection: a privileged service_role direct UPDATE/DELETE against the posted journal (and its lines) is blocked with a distinct named exception even though service_role holds the base table grant; the identical attempt against the still-draft journal succeeds (the guard is scoped to posted rows only)'
do $$
declare
  v_posted_id uuid;
  v_draft_id uuid;
  v_posted_line_id uuid;
begin
  select id into v_posted_id from app.finance_journals where idempotency_key = 'pji-posted-1';
  select id into v_draft_id from app.finance_journals where idempotency_key = 'pji-draft-1';
  select id into v_posted_line_id from app.finance_journal_lines where journal_id = v_posted_id limit 1;

  set local role service_role;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000029902", "role": "service_role"}';

  begin
    execute format('update app.finance_journals set total_amount = 999 where id = %L', v_posted_id);
    raise exception 'assertion failed: expected finance_journal_posted_immutable for a non-Supreme-Admin direct UPDATE of a posted journal';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_posted_immutable' then
        raise exception 'assertion failed: expected finance_journal_posted_immutable, got %', sqlerrm;
      end if;
  end;

  begin
    execute format('delete from app.finance_journals where id = %L', v_posted_id);
    raise exception 'assertion failed: expected finance_journal_posted_immutable for a non-Supreme-Admin direct DELETE of a posted journal';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_posted_immutable' then
        raise exception 'assertion failed: expected finance_journal_posted_immutable, got %', sqlerrm;
      end if;
  end;

  begin
    execute format('update app.finance_journal_lines set amount = 1 where id = %L', v_posted_line_id);
    raise exception 'assertion failed: expected finance_journal_line_posted_immutable for a non-Supreme-Admin direct UPDATE of a posted journal''s own line';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_line_posted_immutable' then
        raise exception 'assertion failed: expected finance_journal_line_posted_immutable, got %', sqlerrm;
      end if;
  end;

  begin
    execute format('delete from app.finance_journal_lines where id = %L', v_posted_line_id);
    raise exception 'assertion failed: expected finance_journal_line_posted_immutable for a non-Supreme-Admin direct DELETE of a posted journal''s own line';
  exception
    when others then
      if sqlerrm !~ 'finance_journal_line_posted_immutable' then
        raise exception 'assertion failed: expected finance_journal_line_posted_immutable, got %', sqlerrm;
      end if;
  end;

  -- The guard is scoped to posted rows only -- a still-draft journal
  -- remains directly mutable by service_role, proving this is not a
  -- blanket table lock.
  execute format('update app.finance_journals set total_amount = 51 where id = %L', v_draft_id);
  if (select total_amount from app.finance_journals where id = v_draft_id) <> 51 then
    raise exception 'assertion failed: expected the still-draft journal to accept a direct service_role UPDATE';
  end if;

  reset role;
end;
$$;

\echo '>> RPD-022 Supreme Admin bypass: a live supreme_admin principal membership permits the identical direct UPDATE/DELETE against posted rows, and each mutation captures a best-effort audit_logs event disclosing it'
do $$
declare
  v_posted_id uuid;
  v_posted_line_id uuid;
  v_audit_count_before integer;
  v_audit_count_after integer;
  v_new_total numeric;
begin
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029903', 'supreme_admin', null, null, 'tester');

  select id into v_posted_id from app.finance_journals where idempotency_key = 'pji-posted-1';
  select id into v_posted_line_id from app.finance_journal_lines where journal_id = v_posted_id and direction = 'debit' limit 1;

  select count(*) into v_audit_count_before from app.audit_logs where action = 'mutate_posted_finance_journal' and resource_id = v_posted_id;

  set local role service_role;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000029903", "role": "service_role"}';

  execute format('update app.finance_journals set total_amount = 999 where id = %L', v_posted_id);
  select total_amount into v_new_total from app.finance_journals where id = v_posted_id;
  if v_new_total <> 999 then
    raise exception 'assertion failed: expected the Supreme Admin direct UPDATE to actually apply, got total_amount=%', v_new_total;
  end if;

  execute format('update app.finance_journal_lines set amount = 999 where id = %L', v_posted_line_id);

  reset role;

  select count(*) into v_audit_count_after from app.audit_logs where action = 'mutate_posted_finance_journal' and resource_id = v_posted_id;
  if v_audit_count_after <= v_audit_count_before then
    raise exception 'assertion failed: expected at least one new mutate_posted_finance_journal audit event disclosing the RPD-022 bypass, before=% after=%', v_audit_count_before, v_audit_count_after;
  end if;

  if not exists (select 1 from app.audit_logs where action = 'update_posted_finance_journal_line' and resource_id = v_posted_line_id) then
    raise exception 'assertion failed: expected an update_posted_finance_journal_line audit event for the bypassed line mutation';
  end if;

  -- Delete bypass, exercised on the same posted journal -- lines first
  -- (FK), then the journal header, both as Supreme Admin.
  set local role service_role;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000029903", "role": "service_role"}';
  execute format('delete from app.finance_journal_lines where journal_id = %L', v_posted_id);
  execute format('delete from app.finance_journals where id = %L', v_posted_id);
  reset role;

  if exists (select 1 from app.finance_journals where id = v_posted_id) then
    raise exception 'assertion failed: expected the Supreme Admin direct DELETE to actually remove the posted journal';
  end if;
  if not exists (select 1 from app.audit_logs where action = 'delete_posted_finance_journal' and resource_id = v_posted_id) then
    raise exception 'assertion failed: expected a delete_posted_finance_journal audit event disclosing the RPD-022 delete bypass';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on either new FIN-204 trigger function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array['protect_posted_finance_journal', 'protect_posted_finance_journal_line']) loop
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
