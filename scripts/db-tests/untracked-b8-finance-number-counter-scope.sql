-- Real, executable test evidence for CG-AUDIT-2026-09-02 UNTRACKED-B8 (the
-- "number counters compound it" second half of the original B8 finding) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.
--
-- Directly exercises the exact mechanism this fix changed: the counter-upsert
-- conflict target on all 4 finance number-counter tables, now (tenant_id,
-- year) rather than (tenant_id, coalesce(company_id, sentinel), year). This
-- deliberately tests the mechanism directly (the same INSERT ... ON CONFLICT
-- statement each of the 5 affected RPCs performs, reproduced verbatim here)
-- rather than through the full commercial-to-invoice business chain -- a
-- fresh disposable test database starts with every counter table empty, so
-- there is no pre-existing per-company duplicate data for this migration's
-- own consolidation logic to exercise in this environment (that logic only
-- matters against a live database carrying real pre-fix history); what IS
-- exactly reproducible and meaningful here is the going-forward behavior:
-- two different company_id values under the SAME tenant, same year, must now
-- share one incrementing sequence, never each independently starting at 1.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant with two company-type org_units'
do $$
declare
  v_tenant uuid;
begin
  perform app.provision_tenant('acmeb8seq', 'Acme B8 Sequencing Co', 'idem-acmeb8seq', 'tester');
  v_tenant := (select id from app.tenants where slug = 'acmeb8seq');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant, 'company', null, 'ACMEB8SEQ-CO-A', 'Acme B8 Sequencing Co (Jakarta)', 'tester');
  perform app.create_org_unit(v_tenant, 'company', null, 'ACMEB8SEQ-CO-B', 'Acme B8 Sequencing Co (Surabaya)', 'tester');
end;
$$;

\echo '>> app.finance_invoice_number_counters: two different company_id values, same tenant/year, now share ONE incrementing sequence (1, then 2) instead of each independently starting at 1'
do $$
declare
  v_tenant uuid;
  v_company_a uuid;
  v_company_b uuid;
  v_seq_a integer;
  v_seq_b integer;
begin
  v_tenant := (select id from app.tenants where slug = 'acmeb8seq');
  v_company_a := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMEB8SEQ-CO-A');
  v_company_b := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMEB8SEQ-CO-B');

  -- Reproduces app.issue_finance_invoice's own counter-upsert statement verbatim.
  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant, v_company_a, 2027, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_a;

  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant, v_company_b, 2027, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_b;

  if v_seq_a <> 1 or v_seq_b <> 2 then
    raise exception 'assertion failed: expected company A to get seq 1 and company B to get seq 2 (one shared tenant/year sequence), got %/%', v_seq_a, v_seq_b;
  end if;
  if (v_seq_a::text = v_seq_b::text) then
    raise exception 'assertion failed: the two companies'' own sequences must never be equal';
  end if;
  -- The pre-fix bug: both would have been 1, so 'INV-2027-000001' would have
  -- collided on finance_invoices_tenant_number_unique the moment both were
  -- actually issued. This directly proves that can no longer happen.
end;
$$;

\echo '>> app.finance_journal_number_counters: identical proof (shared by app.post_finance_journal and app.create_and_post_finance_system_journal)'
do $$
declare
  v_tenant uuid;
  v_company_a uuid;
  v_company_b uuid;
  v_seq_a integer;
  v_seq_b integer;
begin
  v_tenant := (select id from app.tenants where slug = 'acmeb8seq');
  v_company_a := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMEB8SEQ-CO-A');
  v_company_b := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMEB8SEQ-CO-B');

  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant, v_company_a, 2027, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_a;

  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant, v_company_b, 2027, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_b;

  if v_seq_a <> 1 or v_seq_b <> 2 then
    raise exception 'assertion failed: expected company A to get seq 1 and company B to get seq 2, got %/%', v_seq_a, v_seq_b;
  end if;
end;
$$;

\echo '>> app.finance_settlement_number_counters: identical proof'
do $$
declare
  v_tenant uuid;
  v_company_a uuid;
  v_company_b uuid;
  v_seq_a integer;
  v_seq_b integer;
begin
  v_tenant := (select id from app.tenants where slug = 'acmeb8seq');
  v_company_a := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMEB8SEQ-CO-A');
  v_company_b := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMEB8SEQ-CO-B');

  insert into app.finance_settlement_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant, v_company_a, 2027, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_settlement_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_a;

  insert into app.finance_settlement_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant, v_company_b, 2027, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_settlement_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_b;

  if v_seq_a <> 1 or v_seq_b <> 2 then
    raise exception 'assertion failed: expected company A to get seq 1 and company B to get seq 2, got %/%', v_seq_a, v_seq_b;
  end if;
end;
$$;

\echo '>> app.finance_vendor_bill_number_counters: identical proof'
do $$
declare
  v_tenant uuid;
  v_company_a uuid;
  v_company_b uuid;
  v_seq_a integer;
  v_seq_b integer;
begin
  v_tenant := (select id from app.tenants where slug = 'acmeb8seq');
  v_company_a := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMEB8SEQ-CO-A');
  v_company_b := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMEB8SEQ-CO-B');

  insert into app.finance_vendor_bill_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant, v_company_a, 2027, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_vendor_bill_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_a;

  insert into app.finance_vendor_bill_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant, v_company_b, 2027, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_vendor_bill_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_b;

  if v_seq_a <> 1 or v_seq_b <> 2 then
    raise exception 'assertion failed: expected company A to get seq 1 and company B to get seq 2, got %/%', v_seq_a, v_seq_b;
  end if;
end;
$$;

\echo '>> a different tenant, or a different year within the same tenant, still gets its own independent sequence starting at 1 (the fix narrows scope from per-company to per-tenant, it does not merge across tenants or years)'
do $$
declare
  v_tenant uuid;
  v_tenant2 uuid;
  v_company_a uuid;
  v_seq_same_tenant_next_year integer;
  v_seq_other_tenant integer;
begin
  v_tenant := (select id from app.tenants where slug = 'acmeb8seq');
  v_company_a := (select id from app.org_units where tenant_id = v_tenant and code = 'ACMEB8SEQ-CO-A');

  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant, v_company_a, 2028, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_same_tenant_next_year;
  if v_seq_same_tenant_next_year <> 1 then
    raise exception 'assertion failed: a new year for the same tenant must start its own sequence at 1, got %', v_seq_same_tenant_next_year;
  end if;

  perform app.provision_tenant('acmeb8seq2', 'Acme B8 Sequencing Co 2', 'idem-acmeb8seq2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeb8seq2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_tenant2, null, 2027, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq_other_tenant;
  if v_seq_other_tenant <> 1 then
    raise exception 'assertion failed: a different tenant must start its own sequence at 1, got %', v_seq_other_tenant;
  end if;
end;
$$;

\echo '>> schema: the 4 counter tables'' own unique index is genuinely (tenant_id, year) now, never company-qualified'
do $$
declare
  v_bad_count integer;
begin
  select count(*) into v_bad_count
  from pg_indexes
  where schemaname = 'app'
    and indexname in (
      'finance_invoice_number_counters_scope_unique',
      'finance_journal_number_counters_scope_unique',
      'finance_settlement_number_counters_scope_unique',
      'finance_vendor_bill_number_counters_scope_unique'
    )
    and indexdef like '%company_id%';
  if v_bad_count <> 0 then
    raise exception 'assertion failed: expected zero of the 4 counter scope-unique indexes to still reference company_id, found %', v_bad_count;
  end if;
end;
$$;

\echo 'ALL CG-AUDIT-2026-09-02 UNTRACKED-B8 db-test assertions passed.'
