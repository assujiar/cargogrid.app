-- CG-AUDIT-2026-09-02 F3 remediation: cursor pagination for the 13 finance list
-- functions. Every one of them carried a literal `limit 200` with no cursor, offset or
-- date parameter -- 101 other list/search RPCs in this schema already take a
-- `p_cursor`/`p_after` parameter (e.g. app.list_attendance_correction_requests's own
-- `p_after_id uuid` keyset idiom, which this migration mirrors exactly); finance alone
-- did not. A 3PL issuing ~200 invoices/journals/receipts reaches the ceiling within
-- weeks, after which AR/AP aging, the GL journal list, receipts, settlements, bank
-- transactions and vendor bills showed only the newest 200 forever, with no path to
-- the rest.
--
-- Fix, applied identically to all 13: add `p_limit integer default 200` and
-- `p_after_id uuid default null`, keeping the existing 200 cap as BOTH the default and
-- the hard ceiling (`bounded-list.ts`'s own BOUNDED_LIST_LIMIT=200 -- "two different
-- caps in one product would be a difference a reader has to learn for no benefit").
-- Each function fetches ONE ROW PAST the requested limit (`limit ... + 1`) rather than
-- a separate `count(*)` -- the same "one extra row is enough to answer 'is there
-- more'" idiom `server/queries/bounded-list.ts#toBoundedList` already establishes for
-- direct-table reads; the TS query layer trims it and reports truncation via that same
-- helper, so RPC-mediated and direct-table lists share one truncation idiom app-wide.
--
-- The anchor-row lookup (`select ... into v_after where id = p_after_id`) is
-- additionally scoped `and tenant_id = p_tenant_id`, which
-- app.list_attendance_correction_requests's own precedent does not do -- passing
-- another tenant's real row id as p_after_id would otherwise let v_after populate from
-- it, and the keyset predicate would then silently compare against that other
-- tenant's own sort-key value. The returned rows stay correctly scoped by the
-- unconditional `tenant_id = p_tenant_id` filter either way, so this is not a data
-- leak by itself, but it is an unnecessary cross-tenant oracle this migration closes
-- while touching every one of these functions regardless.
--
-- Sort keys were already established per function (due_date asc for AR/AP open items,
-- various *_date/created_at desc for the rest) -- unchanged; `id` is added as the
-- keyset tie-breaker in every case (every sort column here is `not null`, so no
-- NULL-tuple-comparison gap). No filter, authority check or return shape changes.
--
-- Each function requires DROP + CREATE (not CREATE OR REPLACE) because the parameter
-- list changes -- Postgres does not allow CREATE OR REPLACE to add parameters, even
-- with defaults (the same reason 20260730100000/20260730130000 dropped+recreated
-- app.lookup_public_shipment_tracking to widen its own signature).
--
-- SECURITY DEFINER / search_path (caught before this migration was ever applied, by
-- diffing this migration's own resulting `pg_get_functiondef` against a disposable
-- database built from the migration set alone -- never assumed): every one of these 13
-- functions was created plain `language plpgsql stable` by its own 2026-07-29 creation
-- migration, but 20260810900000_harden_finance_authority_chain_tierc_completeness.sql
-- later widened all 13 (among ~20 other list_finance_* functions) to `security definer`
-- with `set search_path to 'app', 'pg_temp'` -- the CURRENT, authoritative shape a fresh
-- migration-built database actually has. A DROP + CREATE built from the ORIGINAL
-- (pre-20260810900000) shape, as a naive per-function diff against that one creation
-- migration would produce, would silently REVERT that hardening -- exactly the
-- RLS-bypass-by-wrapper defect class 20260826010000's own header comment documents (a
-- security-mode drift between app.<name> and its public.* wrapper). Every one of the 13
-- `security definer`/`set search_path` clauses below is therefore carried forward from
-- 20260810900000's own current text, not from the 2026-07-29 creation migrations this
-- header otherwise describes -- body/filter/sort logic is otherwise byte-identical
-- between the two, verified line by line.

-- ============================================================================
-- 1. app.list_finance_ar_open_items -- due_date asc, id asc tie-breaker.
-- ============================================================================

drop function app.list_finance_ar_open_items(uuid, uuid, uuid, text, boolean, uuid);

create function app.list_finance_ar_open_items(
  p_tenant_id uuid,
  p_company_id uuid,
  p_customer_account_id uuid,
  p_status text,
  p_overdue_only boolean,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_ar_open_items
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_ar_open_items;
begin
  if not app.check_finance_ar_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_ar_open_items where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_ar_open_items
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_customer_account_id is null or customer_account_id = p_customer_account_id)
      and (p_status is null or status = p_status)
      and (not coalesce(p_overdue_only, false) or (status <> 'paid' and due_date < current_date))
      and (v_after.id is null or (due_date, id) > (v_after.due_date, v_after.id))
    order by due_date asc, id asc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_ar_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 2. app.list_finance_ap_open_items -- due_date asc, id asc tie-breaker.
-- ============================================================================

drop function app.list_finance_ap_open_items(uuid, uuid, uuid, text, boolean, uuid);

create function app.list_finance_ap_open_items(
  p_tenant_id uuid,
  p_company_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_overdue_only boolean,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_ap_open_items
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_ap_open_items;
begin
  if not app.check_finance_ap_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_ap_open_items where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_ap_open_items
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
      and (not coalesce(p_overdue_only, false) or (status <> 'settled' and due_date < current_date))
      and (v_after.id is null or (due_date, id) > (v_after.due_date, v_after.id))
    order by due_date asc, id asc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_ap_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 3. app.list_finance_invoices -- created_at desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_invoices(uuid, uuid, uuid, text, uuid);

create function app.list_finance_invoices(
  p_tenant_id uuid,
  p_company_id uuid,
  p_customer_account_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_invoices
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_invoices;
begin
  if not app.check_finance_invoice_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_invoices where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_invoices
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_customer_account_id is null or customer_account_id = p_customer_account_id)
      and (p_status is null or status = p_status)
      and (v_after.id is null or (created_at, id) < (v_after.created_at, v_after.id))
    order by created_at desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_invoices(uuid, uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 4. app.list_finance_journals -- created_at desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_journals(uuid, uuid, text, text, uuid);

create function app.list_finance_journals(
  p_tenant_id uuid,
  p_company_id uuid,
  p_source_type text,
  p_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_journals
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_journals;
begin
  if not app.check_finance_journal_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_journals where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_journals
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_source_type is null or source_type = p_source_type)
      and (p_status is null or status = p_status)
      and (v_after.id is null or (created_at, id) < (v_after.created_at, v_after.id))
    order by created_at desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_journals(uuid, uuid, text, text, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 5. app.list_finance_receipts -- receipt_date desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_receipts(uuid, uuid, uuid, text, uuid);

create function app.list_finance_receipts(
  p_tenant_id uuid,
  p_company_id uuid,
  p_customer_account_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_receipts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_receipts;
begin
  if not app.check_finance_receipt_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_receipts where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_receipts
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_customer_account_id is null or customer_account_id = p_customer_account_id)
      and (p_status is null or status = p_status)
      and (v_after.id is null or (receipt_date, id) < (v_after.receipt_date, v_after.id))
    order by receipt_date desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_receipts(uuid, uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 6. app.list_finance_settlements -- created_at desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_settlements(uuid, uuid, uuid, text, uuid);

create function app.list_finance_settlements(
  p_tenant_id uuid,
  p_company_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_settlements
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_settlements;
begin
  if not app.check_finance_settlement_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_settlements where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_settlements
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
      and (v_after.id is null or (created_at, id) < (v_after.created_at, v_after.id))
    order by created_at desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_settlements(uuid, uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 7. app.list_finance_bank_accounts -- created_at desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_bank_accounts(uuid, uuid, uuid);

create function app.list_finance_bank_accounts(
  p_tenant_id uuid,
  p_company_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_bank_accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_bank_accounts;
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_bank_accounts where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_bank_accounts
    where tenant_id = p_tenant_id and (p_company_id is null or company_id = p_company_id)
      and (v_after.id is null or (created_at, id) < (v_after.created_at, v_after.id))
    order by created_at desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_bank_accounts(uuid, uuid, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 8. app.list_finance_bank_transactions -- transaction_date desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_bank_transactions(uuid, uuid, text, uuid);

create function app.list_finance_bank_transactions(
  p_tenant_id uuid,
  p_bank_account_id uuid,
  p_match_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_bank_transactions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_bank_transactions;
begin
  if not app.check_finance_cash_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_bank_transactions where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_bank_transactions
    where tenant_id = p_tenant_id
      and (p_bank_account_id is null or bank_account_id = p_bank_account_id)
      and (p_match_status is null or match_status = p_match_status)
      and (v_after.id is null or (transaction_date, id) < (v_after.transaction_date, v_after.id))
    order by transaction_date desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_bank_transactions(uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 9. app.list_finance_vendor_bills -- created_at desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_vendor_bills(uuid, uuid, uuid, text, uuid);

create function app.list_finance_vendor_bills(
  p_tenant_id uuid,
  p_company_id uuid,
  p_vendor_master_id uuid,
  p_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_vendor_bills
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_vendor_bills;
begin
  if not app.check_finance_vendor_bill_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_vendor_bills where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_vendor_bills
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id)
      and (p_status is null or status = p_status)
      and (v_after.id is null or (created_at, id) < (v_after.created_at, v_after.id))
    order by created_at desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_vendor_bills(uuid, uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 10. app.list_finance_period_locks -- created_at desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_period_locks(uuid, uuid, uuid, uuid);

create function app.list_finance_period_locks(
  p_tenant_id uuid,
  p_company_id uuid,
  p_period_id uuid,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_period_locks
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_period_locks;
begin
  if not app.check_finance_period_lock_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_period_locks where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_period_locks
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_period_id is null or period_id = p_period_id)
      and (v_after.id is null or (created_at, id) < (v_after.created_at, v_after.id))
    order by created_at desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_period_locks(uuid, uuid, uuid, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 11. app.list_finance_reconciliation_runs -- created_at desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_reconciliation_runs(uuid, uuid, text, uuid);

create function app.list_finance_reconciliation_runs(
  p_tenant_id uuid,
  p_company_id uuid,
  p_scope text,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_reconciliation_runs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_reconciliation_runs;
begin
  if not app.check_finance_reconciliation_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_reconciliation_runs where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_reconciliation_runs
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_scope is null or scope = p_scope)
      and (v_after.id is null or (created_at, id) < (v_after.created_at, v_after.id))
    order by created_at desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_reconciliation_runs(uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 12. app.list_finance_subledger_batches -- posted_at desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_subledger_batches(uuid, uuid, text, uuid);

create function app.list_finance_subledger_batches(
  p_tenant_id uuid,
  p_company_id uuid,
  p_source_type text,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_subledger_batches
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_subledger_batches;
begin
  if not app.check_finance_subledger_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_subledger_batches where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_subledger_batches
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_source_type is null or source_type = p_source_type)
      and (v_after.id is null or (posted_at, id) < (v_after.posted_at, v_after.id))
    order by posted_at desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_subledger_batches(uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- 13. app.list_finance_journal_corrections -- created_at desc, id desc tie-breaker.
-- ============================================================================

drop function app.list_finance_journal_corrections(uuid, uuid, text, text, uuid);

create function app.list_finance_journal_corrections(
  p_tenant_id uuid,
  p_company_id uuid,
  p_correction_type text,
  p_status text,
  p_actor_auth_user_id uuid,
  p_limit integer default 200,
  p_after_id uuid default null
)
returns setof app.finance_journal_corrections
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.finance_journal_corrections;
begin
  if not app.check_finance_correction_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_after_id is not null then
    select * into v_after from app.finance_journal_corrections where id = p_after_id and tenant_id = p_tenant_id;
  end if;
  return query select * from app.finance_journal_corrections
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_correction_type is null or correction_type = p_correction_type)
      and (p_status is null or status = p_status)
      and (v_after.id is null or (created_at, id) < (v_after.created_at, v_after.id))
    order by created_at desc, id desc
    limit least(coalesce(p_limit, 200), 200) + 1;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since PLT-118 -- DROP +
-- CREATE resets a function's privileges to that default, unlike CREATE OR REPLACE.
revoke execute on all functions in schema app from public;
grant execute on function app.list_finance_journal_corrections(uuid, uuid, text, text, uuid, integer, uuid) to authenticated, service_role;

-- ============================================================================
-- Option-2 public.* wrappers: schema app is not exposed to PostgREST; each is a thin
-- security-definer pass-through with an identical grant set, never a reimplementation.
-- Mirrors 20260826000000_create_public_api_data_wrappers.sql's own wrapper for each of
-- these 13 exactly, widened by the same two trailing parameters.
-- ============================================================================

drop function public.list_finance_ar_open_items(uuid, uuid, uuid, text, boolean, uuid);
create function public.list_finance_ar_open_items(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_ar_open_items
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_ar_open_items(p_tenant_id, p_company_id, p_customer_account_id, p_status, p_overdue_only, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_ar_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_ar_open_items with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_ar_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_ar_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_ar_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) to authenticated;

drop function public.list_finance_ap_open_items(uuid, uuid, uuid, text, boolean, uuid);
create function public.list_finance_ap_open_items(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_overdue_only boolean, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_ap_open_items
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_ap_open_items(p_tenant_id, p_company_id, p_vendor_master_id, p_status, p_overdue_only, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_ap_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_ap_open_items with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_ap_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_ap_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_ap_open_items(uuid, uuid, uuid, text, boolean, uuid, integer, uuid) to authenticated;

drop function public.list_finance_invoices(uuid, uuid, uuid, text, uuid);
create function public.list_finance_invoices(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_invoices
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_invoices(p_tenant_id, p_company_id, p_customer_account_id, p_status, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_invoices(uuid, uuid, uuid, text, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_invoices with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_invoices(uuid, uuid, uuid, text, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_invoices(uuid, uuid, uuid, text, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_invoices(uuid, uuid, uuid, text, uuid, integer, uuid) to authenticated;

drop function public.list_finance_journals(uuid, uuid, text, text, uuid);
create function public.list_finance_journals(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_status text, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_journals
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_journals(p_tenant_id, p_company_id, p_source_type, p_status, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_journals(uuid, uuid, text, text, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_journals with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_journals(uuid, uuid, text, text, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_journals(uuid, uuid, text, text, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_journals(uuid, uuid, text, text, uuid, integer, uuid) to authenticated;

drop function public.list_finance_receipts(uuid, uuid, uuid, text, uuid);
create function public.list_finance_receipts(p_tenant_id uuid, p_company_id uuid, p_customer_account_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_receipts
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_receipts(p_tenant_id, p_company_id, p_customer_account_id, p_status, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_receipts(uuid, uuid, uuid, text, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_receipts with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_receipts(uuid, uuid, uuid, text, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_receipts(uuid, uuid, uuid, text, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_receipts(uuid, uuid, uuid, text, uuid, integer, uuid) to authenticated;

drop function public.list_finance_settlements(uuid, uuid, uuid, text, uuid);
create function public.list_finance_settlements(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_settlements
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_settlements(p_tenant_id, p_company_id, p_vendor_master_id, p_status, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_settlements(uuid, uuid, uuid, text, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_settlements with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_settlements(uuid, uuid, uuid, text, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_settlements(uuid, uuid, uuid, text, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_settlements(uuid, uuid, uuid, text, uuid, integer, uuid) to authenticated;

drop function public.list_finance_bank_accounts(uuid, uuid, uuid);
create function public.list_finance_bank_accounts(p_tenant_id uuid, p_company_id uuid, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_bank_accounts
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_bank_accounts(p_tenant_id, p_company_id, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_bank_accounts(uuid, uuid, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_bank_accounts with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_bank_accounts(uuid, uuid, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_bank_accounts(uuid, uuid, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_bank_accounts(uuid, uuid, uuid, integer, uuid) to authenticated;

drop function public.list_finance_bank_transactions(uuid, uuid, text, uuid);
create function public.list_finance_bank_transactions(p_tenant_id uuid, p_bank_account_id uuid, p_match_status text, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_bank_transactions
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_bank_transactions(p_tenant_id, p_bank_account_id, p_match_status, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_bank_transactions(uuid, uuid, text, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_bank_transactions with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_bank_transactions(uuid, uuid, text, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_bank_transactions(uuid, uuid, text, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_bank_transactions(uuid, uuid, text, uuid, integer, uuid) to authenticated;

drop function public.list_finance_vendor_bills(uuid, uuid, uuid, text, uuid);
create function public.list_finance_vendor_bills(p_tenant_id uuid, p_company_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_vendor_bills
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_vendor_bills(p_tenant_id, p_company_id, p_vendor_master_id, p_status, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_vendor_bills(uuid, uuid, uuid, text, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_vendor_bills with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_vendor_bills(uuid, uuid, uuid, text, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_vendor_bills(uuid, uuid, uuid, text, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_vendor_bills(uuid, uuid, uuid, text, uuid, integer, uuid) to authenticated;

drop function public.list_finance_period_locks(uuid, uuid, uuid, uuid);
create function public.list_finance_period_locks(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_period_locks
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_period_locks(p_tenant_id, p_company_id, p_period_id, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_period_locks(uuid, uuid, uuid, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_period_locks with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_period_locks(uuid, uuid, uuid, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_period_locks(uuid, uuid, uuid, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_period_locks(uuid, uuid, uuid, uuid, integer, uuid) to authenticated;

drop function public.list_finance_reconciliation_runs(uuid, uuid, text, uuid);
create function public.list_finance_reconciliation_runs(p_tenant_id uuid, p_company_id uuid, p_scope text, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_reconciliation_runs
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_reconciliation_runs(p_tenant_id, p_company_id, p_scope, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_reconciliation_runs(uuid, uuid, text, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_reconciliation_runs with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_reconciliation_runs(uuid, uuid, text, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_reconciliation_runs(uuid, uuid, text, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_reconciliation_runs(uuid, uuid, text, uuid, integer, uuid) to authenticated;

drop function public.list_finance_subledger_batches(uuid, uuid, text, uuid);
create function public.list_finance_subledger_batches(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_subledger_batches
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_subledger_batches(p_tenant_id, p_company_id, p_source_type, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_subledger_batches(uuid, uuid, text, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_subledger_batches with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_subledger_batches(uuid, uuid, text, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_subledger_batches(uuid, uuid, text, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_subledger_batches(uuid, uuid, text, uuid, integer, uuid) to authenticated;

drop function public.list_finance_journal_corrections(uuid, uuid, text, text, uuid);
create function public.list_finance_journal_corrections(p_tenant_id uuid, p_company_id uuid, p_correction_type text, p_status text, p_actor_auth_user_id uuid, p_limit integer default 200, p_after_id uuid default null)
returns setof app.finance_journal_corrections
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_finance_journal_corrections(p_tenant_id, p_company_id, p_correction_type, p_status, p_actor_auth_user_id, p_limit, p_after_id);
$wrap$;
comment on function public.list_finance_journal_corrections(uuid, uuid, text, text, uuid, integer, uuid) is
  'CG-AUDIT-2026-09-02 F3 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.list_finance_journal_corrections with an identical grant set, never a reimplementation.';
revoke execute on function public.list_finance_journal_corrections(uuid, uuid, text, text, uuid, integer, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_finance_journal_corrections(uuid, uuid, text, text, uuid, integer, uuid) to service_role;
grant execute on function public.list_finance_journal_corrections(uuid, uuid, text, text, uuid, integer, uuid) to authenticated;
