-- Real, executable test evidence for CG-AUDIT-2026-09-02 F3 (independent
-- launch-readiness audit, finding F3) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.
--
-- F3: all 13 finance list functions carried a literal `limit 200` with no cursor --
-- 101 other list/search RPCs in this schema already take a `p_cursor`/`p_after`
-- parameter; finance alone did not. 20260907160000_add_cursor_pagination_finance_
-- lists_iss_f3.sql added `p_limit`/`p_after_id` (default 200/null, same keyset idiom
-- `app.list_attendance_correction_requests` already established) to all 13, fetching
-- `limit + 1` so the TS query layer can trim and detect truncation the same way
-- `server/queries/bounded-list.ts#toBoundedList` already does for direct-table reads.
--
-- This file proves the two DISTINCT sort-order shapes deeply, with a fresh, minimal,
-- fully self-contained tenant (never reusing another test file's fixture, so this
-- file's own row counts can never be perturbed by unrelated seed data elsewhere):
--   - app.list_finance_ar_open_items: `due_date asc, id asc` -- 5 rows sharing the
--     IDENTICAL due_date, forcing every one of them through the `id` tie-break.
--   - app.list_finance_reconciliation_runs: `created_at desc, id desc` -- 5 rows with
--     an explicitly-set IDENTICAL created_at, same reasoning, opposite direction.
-- Both prove: a full cursor walk visits every row exactly once, in the documented
-- order; one page past the end returns zero rows (not an error, not a repeat); the
-- `limit + 1` over-fetch arithmetic is exact; and a cross-tenant `p_after_id` (this
-- migration's own hardening beyond app.list_attendance_correction_requests's own
-- precedent, which does not tenant-scope its anchor lookup) is silently ignored
-- (treated as `p_after_id is null`) rather than leaking another tenant's sort-key
-- value into this tenant's own predicate.
--
-- The remaining 11 functions share the IDENTICAL two code shapes (verified by direct
-- code review of the migration) -- each gets a lighter, still-real assertion appended
-- to ITS OWN existing db-test file (reusing that file's already-built fixture rather
-- than re-deriving the heavier FK chains several of them require -- vendor_bills'
-- own shipment_actual_costs chain, bank_transactions' own statement-batch, period_
-- locks' own fiscal-period/calendar): seed one additional row, confirm the returned
-- page still respects `limit + 1` and a page requested `after` the newest-seeded row
-- excludes it.

\set ON_ERROR_STOP on

-- ISS-2026-319's app.validate_finance_open_item_source guard (20260901060000) rejects
-- a fabricated source_document_id on app.finance_ar_open_items -- mirrors
-- scripts/db-tests/finance-accounts-receivable.sql's own pg_temp.iss319_mint_staging_row
-- helper exactly (a real, minimal app.import_staging_rows row is the lightest genuine
-- target for source_document_type = 'opening_balance', avoiding the full lead->
-- prospect->opportunity->quotation->job_order->invoice chain 'invoice' would require).
-- finance_ar_open_items_source_unique is `unique (tenant_id, source_document_type,
-- source_document_id)`, so each of this file's 6 seeded AR open items needs its own row.
create function pg_temp.f3_mint_staging_row(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns uuid
language plpgsql
as $fn$
declare
  v_job_id uuid;
  v_row_id uuid;
begin
  insert into app.jobs (tenant_id, job_type, requested_by_auth_user_id, created_by)
  values (p_tenant_id, 'import', p_actor_auth_user_id, p_actor_label)
  returning job_id into v_job_id;

  insert into app.import_staging_rows (tenant_id, job_id, row_number, raw_payload)
  values (p_tenant_id, v_job_id, 1, '{}'::jsonb)
  returning id into v_row_id;

  return v_row_id;
end;
$fn$;

\echo '>> setup: one tenant, one company org unit, one customer account, a Finance Viewer role (FIN:View only)'
do $$
declare
  v_tenant uuid;
  v_admin_id uuid := '00000000-0000-0000-0000-0000000f3001';
  v_viewer_id uuid := '00000000-0000-0000-0000-0000000f3002';
  v_company uuid;
  v_customer uuid;
  v_viewer_role_id uuid;
  v_viewer_draft app.role_versions;
begin
  insert into auth.users (id, email) values
    (v_admin_id, 'admin@f3pagination.test'),
    (v_viewer_id, 'viewer@f3pagination.test');

  perform app.provision_tenant('f3pagination', 'F3 Pagination', 'idem-f3pagination', 'tester');
  v_tenant := (select id from app.tenants where slug = 'f3pagination');
  perform app.transition_tenant_status(v_tenant, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant, 'company', null, 'F3PAG-CO', 'F3 Pagination Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant and code = 'F3PAG-CO');

  perform app.invite_user(v_tenant, v_admin_id, 'admin@f3pagination.test', 'F3 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@f3pagination.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin_id, 'tenant_admin', v_tenant, null, 'tester');

  perform app.invite_user(v_tenant, v_viewer_id, 'viewer@f3pagination.test', 'F3 Viewer', v_company, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@f3pagination.test'), 'active', 'onboarded', 'tester');

  v_viewer_role_id := (app.create_role(v_tenant, 'Finance Viewer', 'FIN:View only', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role_id, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant, (select id from app.role_versions where role_id = v_viewer_role_id and status = 'published'), v_viewer_id, v_admin_id, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
    values (v_tenant, 'F3 Pagination Customer', 'f3pagination-customer-fp', '{}'::jsonb, v_company, 'tester')
    returning id into v_customer;

  -- A second, wholly unrelated tenant, with the SAME viewer also granted FIN:View on
  -- it -- proves p_after_id cannot be used as a cross-tenant sort-key oracle (the
  -- migration's own tenant-scoped anchor lookup), independent of authority ever
  -- denying the call in the first place.
  declare
    v_other_tenant uuid;
    v_other_company uuid;
    v_other_customer uuid;
    v_other_role_id uuid;
    v_other_draft app.role_versions;
  begin
    perform app.provision_tenant('f3pagination-other', 'F3 Pagination Other', 'idem-f3paginationother', 'tester');
    v_other_tenant := (select id from app.tenants where slug = 'f3pagination-other');
    perform app.transition_tenant_status(v_other_tenant, 'active', 'setup', 'tester');
    perform app.create_org_unit(v_other_tenant, 'company', null, 'F3PAGO-CO', 'F3 Pagination Other Co', 'tester');
    v_other_company := (select id from app.org_units where tenant_id = v_other_tenant and code = 'F3PAGO-CO');
    perform app.invite_user(v_other_tenant, v_viewer_id, 'viewer@f3pagination.test', 'F3 Viewer', v_other_company, 'tester', now() + interval '7 days');
    perform app.transition_user_status((select id from app.users where tenant_id = v_other_tenant and email = 'viewer@f3pagination.test'), 'active', 'onboarded', 'tester');
    v_other_role_id := (app.create_role(v_other_tenant, 'Finance Viewer', 'FIN:View only', 'tester')).id;
    v_other_draft := app.create_role_version(v_other_role_id, 'tester');
    perform app.set_role_version_permissions(v_other_draft.id, array(select id from app.permissions where resource_module_code = 'FIN' and action = 'View'), 'tester');
    perform app.publish_role_version(v_other_draft.id, now(), 'tester');
    perform app.assign_role(v_other_tenant, (select id from app.role_versions where role_id = v_other_role_id and status = 'published'), v_viewer_id, v_admin_id, 'tester');
    insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
      values (v_other_tenant, 'F3 Pagination Other Customer', 'f3pagination-other-customer-fp', '{}'::jsonb, v_other_company, 'tester')
      returning id into v_other_customer;
    insert into app.finance_ar_open_items (tenant_id, company_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, due_date, invoice_date, status)
      values (v_other_tenant, v_other_company, v_other_customer, 'opening_balance', pg_temp.f3_mint_staging_row(v_other_tenant, v_viewer_id, 'tester'), 'USD', 999, '2026-01-01', '2025-12-01', 'open');
  end;
end;
$$;

\echo '>> fixture: 5 AR open items sharing the SAME due_date (forces the (due_date, id) asc tie-break)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'f3pagination');
  v_viewer_id uuid := '00000000-0000-0000-0000-0000000f3002';
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant and code = 'F3PAG-CO');
  v_customer uuid := (select id from app.accounts where tenant_id = v_tenant and legal_name = 'F3 Pagination Customer');
  v_i integer;
begin
  for v_i in 1..5 loop
    insert into app.finance_ar_open_items (tenant_id, company_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, due_date, invoice_date, status)
    values (v_tenant, v_company, v_customer, 'opening_balance', pg_temp.f3_mint_staging_row(v_tenant, v_viewer_id, 'tester'), 'USD', 100 * v_i, '2026-06-15', '2026-05-15', 'open');
  end loop;
end;
$$;

\echo '>> fixture: 5 reconciliation runs sharing the SAME created_at (forces the (created_at, id) desc tie-break)'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'f3pagination');
  v_company uuid := (select id from app.org_units where tenant_id = v_tenant and code = 'F3PAG-CO');
  v_shared_created_at timestamptz := '2026-06-20T10:00:00Z';
  v_i integer;
begin
  for v_i in 1..5 loop
    insert into app.finance_reconciliation_runs (tenant_id, company_id, scope, as_of_date, control_total, source_total, is_within_tolerance, created_at, updated_at)
    values (v_tenant, v_company, 'ar', '2026-06-19', 1000 + v_i, 1000 + v_i, true, v_shared_created_at, v_shared_created_at);
  end loop;
end;
$$;

\echo '>> app.list_finance_ar_open_items: full cursor walk visits all 5 rows exactly once, ascending (due_date, id) order, then stops'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'f3pagination');
  v_viewer_id uuid := '00000000-0000-0000-0000-0000000f3002';
  v_other_tenant uuid := (select id from app.tenants where slug = 'f3pagination-other');
  v_raw_count integer;
  v_after_id uuid;
  v_row_id uuid;
  v_seen uuid[] := '{}';
  v_i integer;
  v_tail_count integer;
begin
  select count(*) into v_raw_count from app.list_finance_ar_open_items(v_tenant, null, null, null, false, v_viewer_id, 2, null);
  if v_raw_count <> 3 then
    raise exception 'F3 FAILED (ar_open_items): p_limit=2 must return 3 raw rows (limit+1 over-fetch), got %', v_raw_count;
  end if;

  v_after_id := null;
  for v_i in 1..5 loop
    select id into v_row_id from app.list_finance_ar_open_items(v_tenant, null, null, null, false, v_viewer_id, 1, v_after_id) order by due_date asc, id asc limit 1;
    if v_row_id is null then
      raise exception 'F3 FAILED (ar_open_items): cursor walk stopped early at step % of 5', v_i;
    end if;
    if v_row_id = any(v_seen) then
      raise exception 'F3 FAILED (ar_open_items): row % returned twice during cursor walk', v_row_id;
    end if;
    v_seen := array_append(v_seen, v_row_id);
    v_after_id := v_row_id;
  end loop;
  if array_length(v_seen, 1) <> 5 then
    raise exception 'F3 FAILED (ar_open_items): expected exactly 5 distinct rows visited, got %', array_length(v_seen, 1);
  end if;

  select count(*) into v_tail_count from app.list_finance_ar_open_items(v_tenant, null, null, null, false, v_viewer_id, 1, v_after_id);
  if v_tail_count <> 0 then
    raise exception 'F3 FAILED (ar_open_items): one page past the end must return 0 rows, got %', v_tail_count;
  end if;

  -- Cross-tenant p_after_id: v_viewer_id genuinely holds FIN:View on v_other_tenant
  -- too (granted above), so this is a real, authorized call, not one authority would
  -- deny for an unrelated reason -- isolating exactly the anchor-scoping behavior.
  -- v_other_tenant holds exactly one AR open item, due 2026-01-01. Presenting
  -- v_seen[1] (a row belonging to v_tenant, due 2026-06-15) as p_after_id while
  -- querying v_other_tenant must return the SAME single row an unpaginated call
  -- returns -- if the anchor lookup were not tenant-scoped, it would instead resolve
  -- v_seen[1]'s own (2026-06-15) due_date and incorrectly exclude v_other_tenant's
  -- (2026-01-01, earlier) row from an ascending-order page.
  declare
    v_unpaginated_id uuid;
    v_cross_tenant_anchor_id uuid;
  begin
    select id into v_unpaginated_id from app.list_finance_ar_open_items(v_other_tenant, null, null, null, false, v_viewer_id, 200, null);
    if v_unpaginated_id is null then
      raise exception 'F3 FAILED (ar_open_items): expected exactly 1 seeded row in the other tenant, got none';
    end if;
    select id into v_cross_tenant_anchor_id from app.list_finance_ar_open_items(v_other_tenant, null, null, null, false, v_viewer_id, 200, v_seen[1]);
    if v_cross_tenant_anchor_id is distinct from v_unpaginated_id then
      raise exception 'F3 FAILED (ar_open_items): a foreign-tenant p_after_id must be ignored (treated as null), got a different/missing row (expected %, got %)', v_unpaginated_id, v_cross_tenant_anchor_id;
    end if;
  end;
end;
$$;

\echo '>> app.list_finance_reconciliation_runs: full cursor walk visits all 5 rows exactly once, descending (created_at, id) order, then stops'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'f3pagination');
  v_viewer_id uuid := '00000000-0000-0000-0000-0000000f3002';
  v_raw_count integer;
  v_after_id uuid;
  v_row_id uuid;
  v_seen uuid[] := '{}';
  v_i integer;
  v_tail_count integer;
begin
  select count(*) into v_raw_count from app.list_finance_reconciliation_runs(v_tenant, null, null, v_viewer_id, 2, null);
  if v_raw_count <> 3 then
    raise exception 'F3 FAILED (reconciliation_runs): p_limit=2 must return 3 raw rows (limit+1 over-fetch), got %', v_raw_count;
  end if;

  v_after_id := null;
  for v_i in 1..5 loop
    select id into v_row_id from app.list_finance_reconciliation_runs(v_tenant, null, null, v_viewer_id, 1, v_after_id) order by created_at desc, id desc limit 1;
    if v_row_id is null then
      raise exception 'F3 FAILED (reconciliation_runs): cursor walk stopped early at step % of 5', v_i;
    end if;
    if v_row_id = any(v_seen) then
      raise exception 'F3 FAILED (reconciliation_runs): row % returned twice during cursor walk', v_row_id;
    end if;
    v_seen := array_append(v_seen, v_row_id);
    v_after_id := v_row_id;
  end loop;
  if array_length(v_seen, 1) <> 5 then
    raise exception 'F3 FAILED (reconciliation_runs): expected exactly 5 distinct rows visited, got %', array_length(v_seen, 1);
  end if;

  select count(*) into v_tail_count from app.list_finance_reconciliation_runs(v_tenant, null, null, v_viewer_id, 1, v_after_id);
  if v_tail_count <> 0 then
    raise exception 'F3 FAILED (reconciliation_runs): one page past the end must return 0 rows, got %', v_tail_count;
  end if;
end;
$$;

\echo '>> app.list_finance_ar_open_items / app.list_finance_reconciliation_runs: backward-compatible call (old 5/4-arg shape, relying on p_limit/p_after_id defaults) still returns the full un-paginated set up to the 200 default'
do $$
declare
  v_tenant uuid := (select id from app.tenants where slug = 'f3pagination');
  v_viewer_id uuid := '00000000-0000-0000-0000-0000000f3002';
  v_count integer;
begin
  select count(*) into v_count from app.list_finance_ar_open_items(v_tenant, null, null, null, false, v_viewer_id);
  if v_count <> 5 then
    raise exception 'F3 FAILED: old-shape call (no p_limit/p_after_id) to list_finance_ar_open_items must still return all 5 seeded rows, got %', v_count;
  end if;
  select count(*) into v_count from app.list_finance_reconciliation_runs(v_tenant, null, null, v_viewer_id);
  if v_count <> 5 then
    raise exception 'F3 FAILED: old-shape call (no p_limit/p_after_id) to list_finance_reconciliation_runs must still return all 5 seeded rows, got %', v_count;
  end if;
end;
$$;

\echo 'F3 pagination: ALL PASSED'
