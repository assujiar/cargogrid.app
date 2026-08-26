-- Real, executable regression evidence for ISS-2026-270 (Step 16 historical-issue-backlog
-- remediation, docs/runtime/KNOWN_ISSUES.md): no safe import/registration path existed
-- for migration-seeded reference tables (app.finance_currencies, app.uoms) -- a raw
-- insert collision raised an unclassified duplicate-key error, and a multi-row batch
-- insert with one colliding row rolled back the entire batch, including genuinely-new
-- rows in the same statement.
--
-- Fix: app.import_reference_currency / app.import_reference_uom
-- (supabase/migrations/20260826130000_create_reference_data_import_registration.sql) --
-- one governed, idempotent RPC per table, Supreme Admin only, returning the existing row
-- on a collision instead of raising or rolling back anything.

\set ON_ERROR_STOP on

\echo '>> setup: a Supreme Admin identity and a non-Supreme-Admin identity, for the authority-boundary proofs below'
do $$
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000270', 'refdataimport-admin@example.test'),
    ('00000000-0000-0000-0000-000000000271', 'refdataimport-nonadmin@example.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000270', 'supreme_admin', null, null, 'tester');
end;
$$;

\echo '>> app.import_reference_currency: idempotent (returns the existing row on a collision, never raises or rolls back), Supreme-only, and a genuinely new code inserts cleanly even in the same test run as a colliding one'
do $$
declare
  v_admin uuid := '00000000-0000-0000-0000-000000000270';
  v_nonadmin uuid := '00000000-0000-0000-0000-000000000271';
  v_existing app.finance_currencies;
  v_new app.finance_currencies;
  v_reimport app.finance_currencies;
begin
  begin
    perform app.import_reference_currency('ZZZ', 'Should Be Denied', 2, v_nonadmin, 'tester');
    raise exception 'assertion failed: expected a non-Supreme-Admin actor to be denied';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- USD already exists (seeded by 20260728230000_create_finance_currency_exchange_rate.sql).
  -- The exact scenario this entry live-reproduced: importing it again must return the
  -- existing row, never raise a duplicate-key error.
  select * into v_existing from app.finance_currencies where code = 'USD';
  select * into v_reimport from app.import_reference_currency('USD', 'United States Dollar', 2, v_admin, 'tester');
  if v_reimport.code <> v_existing.code or v_reimport.name <> v_existing.name or v_reimport.minor_unit_precision <> v_existing.minor_unit_precision then
    raise exception 'assertion failed: expected re-importing USD to return the identical existing row, got %/%/%', v_reimport.code, v_reimport.name, v_reimport.minor_unit_precision;
  end if;

  -- A genuinely new code inserts cleanly.
  select * into v_new from app.import_reference_currency('ZZZ', 'Test Reference Currency', 3, v_admin, 'tester');
  if v_new.code <> 'ZZZ' or v_new.minor_unit_precision <> 3 then
    raise exception 'assertion failed: expected the new ZZZ currency to be inserted with the given values, got code=%, precision=%', v_new.code, v_new.minor_unit_precision;
  end if;

  -- The exact live-reproduced failure mode this entry named: previously, a bare
  -- multi-row batch insert with one colliding row rolled back the ENTIRE batch,
  -- including genuinely-new rows in the same statement. Proving the real fix here means
  -- proving a SEPARATE genuinely-new row (this same ZZZ import above) survives being
  -- called in the same test alongside a colliding re-import (USD above) -- which it did,
  -- since each call is now its own independent, idempotent statement rather than one
  -- multi-row INSERT that fails atomically.
  if not exists (select 1 from app.finance_currencies where code = 'ZZZ') then
    raise exception 'assertion failed: expected the genuinely-new ZZZ row to survive, exactly the row a bare batch insert used to lose on a sibling collision';
  end if;

  -- A real, persisted audit event records the genuinely-new import (never for the
  -- idempotent no-op return above).
  if not exists (
    select 1 from app.audit_logs
    where action = 'import_reference_currency' and resource_type = 'app.finance_currencies'
      and after_value ->> 'code' = 'ZZZ'
  ) then
    raise exception 'assertion failed: expected a real audit_logs event for the genuinely-new ZZZ import';
  end if;

  raise notice 'ISS-2026-270 app.import_reference_currency proof: Supreme-only, idempotent re-import returns the existing row, a genuinely-new code inserts cleanly and survives alongside a colliding sibling call, and a real audit event records the new import';
end;
$$;

\echo '>> app.import_reference_uom: identical shape and proof, mirrored verbatim for the second affected table'
do $$
declare
  v_admin uuid := '00000000-0000-0000-0000-000000000270';
  v_nonadmin uuid := '00000000-0000-0000-0000-000000000271';
  v_existing app.uoms;
  v_new app.uoms;
  v_reimport app.uoms;
begin
  begin
    perform app.import_reference_uom('ZZZ', 'Should Be Denied', 'weight', v_nonadmin, 'tester');
    raise exception 'assertion failed: expected a non-Supreme-Admin actor to be denied';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- KG already exists (seeded by 20260730160000_create_advanced_tms_item_uom_master.sql).
  select * into v_existing from app.uoms where code = 'KG';
  select * into v_reimport from app.import_reference_uom('KG', 'Kilogram', 'weight', v_admin, 'tester');
  if v_reimport.code <> v_existing.code or v_reimport.name <> v_existing.name or v_reimport.unit_category <> v_existing.unit_category then
    raise exception 'assertion failed: expected re-importing KG to return the identical existing row, got %/%/%', v_reimport.code, v_reimport.name, v_reimport.unit_category;
  end if;

  select * into v_new from app.import_reference_uom('ZZZ', 'Test Reference UOM', 'count', v_admin, 'tester');
  if v_new.code <> 'ZZZ' or v_new.unit_category <> 'count' then
    raise exception 'assertion failed: expected the new ZZZ UOM to be inserted with the given values, got code=%, unit_category=%', v_new.code, v_new.unit_category;
  end if;

  if not exists (select 1 from app.uoms where code = 'ZZZ') then
    raise exception 'assertion failed: expected the genuinely-new ZZZ UOM row to survive';
  end if;

  -- The underlying table's own CHECK constraint (never re-implemented in the RPC) still
  -- rejects an invalid unit_category, proving this RPC adds a safe import path without
  -- weakening the table's own existing data-integrity guarantees.
  begin
    perform app.import_reference_uom('BADCAT', 'Bad Category', 'not_a_real_category', v_admin, 'tester');
    raise exception 'assertion failed: expected an invalid unit_category to be rejected by the table''s own CHECK constraint';
  exception
    when others then
      if sqlerrm not like '%uoms_unit_category_check%' then raise; end if;
  end;

  raise notice 'ISS-2026-270 app.import_reference_uom proof: Supreme-only, idempotent re-import returns the existing row, a genuinely-new code inserts cleanly, and the table''s own CHECK constraint still rejects an invalid unit_category';
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on either new function; authenticated has none either (Supreme Admin authority is enforced inside the function body, but the grant itself is service_role-only, matching every other platform-wide registry RPC in this codebase)'
do $$
declare
  v_bad_grant record;
begin
  for v_bad_grant in
    select routine_name, grantee from information_schema.routine_privileges
    where routine_schema = 'app'
      and routine_name in ('import_reference_currency', 'import_reference_uom')
      and grantee in ('anon', 'authenticated')
  loop
    raise exception 'assertion failed: % must not hold EXECUTE on app.%', v_bad_grant.grantee, v_bad_grant.routine_name;
  end loop;
end;
$$;

\echo 'ALL ISS-2026-270 (Reference Data Import Registration) db-test assertions passed.'
