-- Real, executable evidence for the RPD-025 retention/legal-hold registry
-- (20260831120000_create_data_retention_and_legal_hold_registry.sql), closing `ISS-2026-091`
-- and `ISS-2026-142`. Run via `pnpm run db:test` against a real, disposable Postgres database.
--
-- Fixture identifier range: 00000000-0000-0000-0000-000000443001..003.
-- Grep-verified unclaimed against every other *.sql fixture in this directory before use.
--
-- The property this file exists to defend is not "columns exist". It is that the system can
-- answer, honestly, **which data is under a reviewed retention rule and which is not** — and
-- cannot be made to answer that dishonestly. So the assertions concentrate on: a seeded row is
-- provisional and cannot silently become confirmed; a hold's scope widens correctly through its
-- nulls, including for rows that did not exist when it was placed; and the coverage report keeps
-- provisional and confirmed apart.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant (ret1) with a Supreme Admin, a tenant_admin, and a plain member'
do $$
declare
  v_tenant1 uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000443001', 'supreme@ret1.test'),
    ('00000000-0000-0000-0000-000000443002', 'admin@ret1.test'),
    ('00000000-0000-0000-0000-000000443003', 'member@ret1.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000443001', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('ret1', 'Retention Co 1', 'idem-ret1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'ret1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000443002', 'admin@ret1.test', 'Ret1 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@ret1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000443002', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000443003', 'member@ret1.test', 'Ret1 Member', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'member@ret1.test'), 'active', 'onboarded', 'tester');
end;
$$;

\echo '>> ISS-2026-091 / ISS-2026-142: the tables both entries name by name are now genuinely governed — and every seeded row is PROVISIONAL, because no migration can perform the legal review those entries insist on'
do $$
declare
  v_hr integer;
  v_payroll integer;
  v_loyalty integer;
  v_confirmed integer;
  v_class text;
begin
  -- ISS-2026-091's own named tables.
  select count(*) into v_hr from app.data_retention_classifications
  where table_name in ('employees', 'candidates', 'leave_requests', 'payroll_run_employee_results', 'performance_outcomes', 'training_certificates');
  if v_hr <> 6 then
    raise exception 'assertion failed: all 6 tables ISS-2026-091 names must be classified, got %', v_hr;
  end if;

  -- Payroll takes the finance class, on the inference the registry already documents.
  select class_code into v_class from app.data_retention_classifications where table_name = 'payroll_run_employee_results';
  if v_class <> 'finance_tax_10y' then
    raise exception 'assertion failed: payroll results should take the finance retention class, got %', v_class;
  end if;
  select count(*) into v_payroll from app.data_retention_classifications where domain = 'hr_payroll';
  if v_payroll < 10 then
    raise exception 'assertion failed: expected the payroll/timesheet/overtime family to be classified, got % rows', v_payroll;
  end if;

  -- ISS-2026-142's own six append-only Loyalty ledger tables are financial records: points and
  -- vouchers are a liability the tenant owes a customer.
  select count(*) into v_loyalty from app.data_retention_classifications where domain = 'loyalty_ledger';
  if v_loyalty = 0 then
    raise exception 'assertion failed: the Loyalty ledger tables must be classified as financial records';
  end if;

  -- The load-bearing assertion of this whole file. ISS-2026-091 warns against a copy-paste
  -- default; a migration that seeded rows as `confirmed` would be exactly that, dressed as
  -- compliance. NOTHING may arrive confirmed.
  select count(*) into v_confirmed from app.data_retention_classifications where review_status = 'confirmed';
  if v_confirmed <> 0 then
    raise exception 'assertion failed: no seeded classification may arrive pre-confirmed -- % did', v_confirmed;
  end if;

  raise notice 'PASS: % HR/payroll-family and % loyalty-ledger tables governed, and zero arrive confirmed', v_payroll, v_loyalty;
end;
$$;

\echo '>> a confirmed classification is impossible without a named reviewer and a stated basis — enforced at BOTH the RPC and the table constraint, so a raw UPDATE cannot manufacture false assurance either'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000000443001';
  v_admin uuid := '00000000-0000-0000-0000-000000443002';
  v_row app.data_retention_classifications;
begin
  begin
    perform app.confirm_data_retention_classification('employees', 'looks fine', v_admin, 'admin');
    raise exception 'assertion failed: a tenant_admin must not be able to confirm a retention classification';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.confirm_data_retention_classification('employees', '   ', v_supreme, 'supreme');
    raise exception 'assertion failed: expected review_note_required for a blank basis';
  exception when check_violation then
    if sqlerrm not like 'review_note_required%' then raise; end if;
  end;

  select * into v_row from app.confirm_data_retention_classification(
    'employees', 'Reviewed against local employment-records law; operational + 90 days confirmed.', v_supreme, 'supreme');
  if v_row.review_status <> 'confirmed' or v_row.reviewed_by_auth_user_id <> v_supreme or v_row.reviewed_at is null then
    raise exception 'assertion failed: a confirmation must record the reviewer and the instant';
  end if;

  -- The constraint, not just the RPC: a service_role UPDATE cannot mark a row confirmed with no
  -- reviewer. This is the "false assurance" case the entry is really about.
  begin
    update app.data_retention_classifications
    set review_status = 'confirmed', reviewed_by_auth_user_id = null, reviewed_at = null
    where table_name = 'candidates';
    raise exception 'assertion failed: a raw UPDATE must not be able to confirm a classification with no reviewer';
  exception when check_violation then
    if sqlerrm not like '%confirmed_shape_check%' then raise; end if;
  end;

  raise notice 'PASS: confirmation is Supreme-Admin-only, requires a stated basis, and cannot be manufactured by a raw UPDATE';
end;
$$;

\echo '>> re-classifying a table to a DIFFERENT class resets its review: a table moved from operational to financial retention has not been reviewed under its new rule, whatever was true of the old one'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000000443001';
  v_row app.data_retention_classifications;
begin
  select * into v_row from app.data_retention_classifications where table_name = 'employees';
  if v_row.review_status <> 'confirmed' then
    raise exception 'assertion failed: this block expects the confirmed row from the previous one';
  end if;

  -- Same class again: the confirmation stands. Re-stating a decision is not a new decision.
  select * into v_row from app.classify_table_retention('employees', 'operational_contract_plus_90d', 'hr_people', v_supreme, 'supreme');
  if v_row.review_status <> 'confirmed' then
    raise exception 'assertion failed: re-classifying to the SAME class must not discard the existing review';
  end if;

  -- Different class: back to provisional, reviewer cleared.
  select * into v_row from app.classify_table_retention('employees', 'finance_tax_10y', 'hr_people', v_supreme, 'supreme');
  if v_row.review_status <> 'provisional' or v_row.reviewed_by_auth_user_id is not null or v_row.reviewed_at is not null then
    raise exception 'assertion failed: changing the class must reset the review and clear the reviewer, got % / %', v_row.review_status, v_row.reviewed_by_auth_user_id;
  end if;

  -- Governance cannot be created for a table that does not exist.
  begin
    perform app.classify_table_retention('no_such_table_at_all', 'finance_tax_10y', 'hr_people', v_supreme, 'supreme');
    raise exception 'assertion failed: expected table_not_found for a nonexistent table';
  exception when no_data_found then
    if sqlerrm not like 'table_not_found%' then raise; end if;
  end;

  -- Put it back, so later assertions and any future reader see the intended mapping.
  perform app.classify_table_retention('employees', 'operational_contract_plus_90d', 'hr_people', v_supreme, 'supreme');

  raise notice 'PASS: a class change resets the review; re-stating the same class does not; an unknown table cannot be governed';
end;
$$;

\echo '>> the hold scope widens through its nulls — a record, a table, a tenant, the platform — and covers rows that did not exist when it was placed, which is precisely what a per-row boolean could never do'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ret1');
  v_supreme uuid := '00000000-0000-0000-0000-000000443001';
  v_admin uuid := '00000000-0000-0000-0000-000000443002';
  v_member uuid := '00000000-0000-0000-0000-000000443003';
  v_record uuid := gen_random_uuid();
  v_other_record uuid := gen_random_uuid();
  v_hold app.data_legal_holds;
begin
  -- Nothing held yet.
  if app.is_record_under_legal_hold('employees', v_tenant1, v_record) then
    raise exception 'assertion failed: nothing should be under hold before one is placed';
  end if;

  -- A plain member cannot place one.
  begin
    perform app.place_data_legal_hold(v_tenant1, 'employees', v_record, 'because', null, v_member, 'member');
    raise exception 'assertion failed: a plain tenant member must not be able to place a legal hold';
  exception when insufficient_privilege then null;
  end;

  -- Record scope: exactly that record, and nothing else.
  select * into v_hold from app.place_data_legal_hold(v_tenant1, 'employees', v_record, 'Dispute ref 2026-114', 'CASE-114', v_admin, 'admin');
  if not app.is_record_under_legal_hold('employees', v_tenant1, v_record) then
    raise exception 'assertion failed: the named record must be under hold';
  end if;
  if app.is_record_under_legal_hold('employees', v_tenant1, v_other_record) then
    raise exception 'assertion failed: a record-scoped hold must not cover a different record';
  end if;
  perform app.release_data_legal_hold(v_hold.id, 'Dispute closed', v_admin, 'admin');

  -- Table scope: every row of that table, INCLUDING one that does not exist yet. This is the
  -- case the entries' own proposed per-row boolean could not express -- a hold placed today
  -- must cover a row written tomorrow.
  select * into v_hold from app.place_data_legal_hold(v_tenant1, 'employees', null, 'Regulator request', 'REG-9', v_admin, 'admin');
  if not app.is_record_under_legal_hold('employees', v_tenant1, gen_random_uuid()) then
    raise exception 'assertion failed: a table-scoped hold must cover a record that did not exist when it was placed';
  end if;
  if app.is_record_under_legal_hold('candidates', v_tenant1, v_record) then
    raise exception 'assertion failed: a table-scoped hold must not leak to another table';
  end if;
  perform app.release_data_legal_hold(v_hold.id, 'Request satisfied', v_admin, 'admin');

  -- Tenant scope: every table in that tenant.
  select * into v_hold from app.place_data_legal_hold(v_tenant1, null, null, 'Whole-tenant preservation order', null, v_admin, 'admin');
  if not app.is_record_under_legal_hold('candidates', v_tenant1, v_record)
     or not app.is_record_under_legal_hold('payroll_runs', v_tenant1, null) then
    raise exception 'assertion failed: a tenant-scoped hold must cover every table in that tenant';
  end if;
  if app.is_record_under_legal_hold('candidates', gen_random_uuid(), v_record) then
    raise exception 'assertion failed: a tenant-scoped hold must not cover a different tenant';
  end if;
  perform app.release_data_legal_hold(v_hold.id, 'Order lifted', v_admin, 'admin');

  -- Platform scope: Supreme-Admin-only to place, and it covers every tenant.
  begin
    perform app.place_data_legal_hold(null, null, null, 'Platform-wide', null, v_admin, 'admin');
    raise exception 'assertion failed: a tenant_admin must not be able to place a PLATFORM-wide hold';
  exception when insufficient_privilege then null;
  end;
  select * into v_hold from app.place_data_legal_hold(null, null, null, 'Platform-wide investigation', 'INV-1', v_supreme, 'supreme');
  if not app.is_record_under_legal_hold('candidates', gen_random_uuid(), gen_random_uuid()) then
    raise exception 'assertion failed: a platform-wide hold must cover every tenant';
  end if;
  perform app.release_data_legal_hold(v_hold.id, 'Investigation closed', v_supreme, 'supreme');

  if app.is_record_under_legal_hold('candidates', v_tenant1, v_record) then
    raise exception 'assertion failed: releasing every hold must leave nothing held';
  end if;

  raise notice 'PASS: hold scope widens correctly through its nulls, covers not-yet-written rows, and does not leak across table or tenant';
end;
$$;

\echo '>> releasing a hold carries at least as much evidence as placing one, and the row is never deleted — it IS the record of what was preserved and why'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'ret1');
  v_admin uuid := '00000000-0000-0000-0000-000000443002';
  v_member uuid := '00000000-0000-0000-0000-000000443003';
  v_hold app.data_legal_holds;
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before from app.data_legal_holds;
  select * into v_hold from app.place_data_legal_hold(v_tenant1, 'employees', null, 'Evidence test', null, v_admin, 'admin');

  begin
    perform app.release_data_legal_hold(v_hold.id, 'no', v_member, 'member');
    raise exception 'assertion failed: a plain member must not be able to release a hold';
  exception when insufficient_privilege then null;
  end;

  begin
    perform app.release_data_legal_hold(v_hold.id, '   ', v_admin, 'admin');
    raise exception 'assertion failed: expected release_reason_required for a blank release reason';
  exception when check_violation then
    if sqlerrm not like 'release_reason_required%' then raise; end if;
  end;

  select * into v_hold from app.release_data_legal_hold(v_hold.id, 'Matter concluded', v_admin, 'admin');
  if v_hold.released_by_auth_user_id <> v_admin or v_hold.release_reason <> 'Matter concluded' then
    raise exception 'assertion failed: a release must record who and why';
  end if;

  begin
    perform app.release_data_legal_hold(v_hold.id, 'again', v_admin, 'admin');
    raise exception 'assertion failed: expected hold_already_released on a second release';
  exception when check_violation then
    if sqlerrm not like 'hold_already_released%' then raise; end if;
  end;

  -- The row survives its own release.
  select count(*) into v_after from app.data_legal_holds;
  if v_after <> v_before + 1 then
    raise exception 'assertion failed: releasing must not delete the hold row -- it is the history';
  end if;

  raise notice 'PASS: release is authority-gated, requires a reason, is not repeatable, and never destroys the record';
end;
$$;

\echo '>> the coverage report keeps PROVISIONAL and CONFIRMED apart, and names what is not governed at all — the artifact that turns an invisible gap into a worklist'
do $$
declare
  v_supreme uuid := '00000000-0000-0000-0000-000000443001';
  v_admin uuid := '00000000-0000-0000-0000-000000443002';
  v_row record;
begin
  begin
    perform app.get_data_retention_coverage(v_admin);
    raise exception 'assertion failed: platform-wide retention coverage must be Supreme-Admin-only';
  exception when insufficient_privilege then null;
  end;

  select * into v_row from app.get_data_retention_coverage(v_supreme);

  if v_row.total_tables <= 0 or v_row.classified <= 0 then
    raise exception 'assertion failed: the coverage report must count real tables and real classifications';
  end if;
  if v_row.classified + v_row.unclassified <> v_row.total_tables then
    raise exception 'assertion failed: classified + unclassified must account for every table (%+%<>%)', v_row.classified, v_row.unclassified, v_row.total_tables;
  end if;
  if v_row.provisional + v_row.confirmed <> v_row.classified then
    raise exception 'assertion failed: provisional + confirmed must account for every classification';
  end if;
  -- Reported separately on purpose: collapsing them would let a wall of unreviewed defaults read
  -- as compliance, which is precisely the failure ISS-2026-091 warns about.
  if v_row.provisional = 0 then
    raise exception 'assertion failed: the seeded rows are provisional and the report must say so';
  end if;
  if v_row.unclassified = 0 then
    raise exception 'assertion failed: this platform has far more tables than the two domains seeded -- an unclassified count of zero would mean the report is not measuring what it claims';
  end if;

  raise notice 'PASS: coverage reports % of % tables classified (% provisional, % confirmed), % ungoverned, % active hold(s)',
    v_row.classified, v_row.total_tables, v_row.provisional, v_row.confirmed, v_row.unclassified, v_row.active_holds;
end;
$$;

\echo '>> defence in depth: anon holds nothing, authenticated cannot write classifications or holds directly, and the hold table is RLS-scoped'
do $$
begin
  if has_function_privilege('anon', 'app.classify_table_retention(text, text, text, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'app.place_data_legal_hold(uuid, text, uuid, text, text, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'app.release_data_legal_hold(uuid, text, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'app.get_data_retention_coverage(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.place_data_legal_hold(uuid, text, uuid, text, text, uuid, text)', 'EXECUTE')
  then
    raise exception 'assertion failed: anon must hold zero EXECUTE on every retention/legal-hold function (ERR-2026-004 regression guard)';
  end if;

  if has_table_privilege('authenticated', 'app.data_retention_classifications', 'INSERT')
     or has_table_privilege('authenticated', 'app.data_retention_classifications', 'UPDATE')
     or has_table_privilege('authenticated', 'app.data_legal_holds', 'INSERT')
     or has_table_privilege('authenticated', 'app.data_legal_holds', 'UPDATE')
  then
    raise exception 'assertion failed: authenticated must never write classifications or holds directly';
  end if;

  -- app.is_record_under_legal_hold is the purge predicate: service_role only. An authenticated
  -- caller has no business asking whether an arbitrary record is held.
  if has_function_privilege('authenticated', 'app.is_record_under_legal_hold(text, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.is_record_under_legal_hold(text, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.is_record_under_legal_hold(text, uuid, uuid)', 'EXECUTE') then
    raise exception 'assertion failed: the legal-hold predicate is service_role-only on both schemas';
  end if;

  if (select count(*) from pg_policies where schemaname = 'app' and tablename = 'data_legal_holds') <> 1 then
    raise exception 'assertion failed: expected exactly one RLS policy on app.data_legal_holds';
  end if;

  raise notice 'PASS: anon holds nothing, authenticated cannot write either table, the predicate is service_role-only, and holds are RLS-scoped';
end;
$$;

\echo 'ALL data-retention/legal-hold assertions passed.'
