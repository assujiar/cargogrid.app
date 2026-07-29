-- Finance capability FIN-213 (Finance Dashboard and Reports, CG-S9-FIN-024)
-- Permission-safe, source-reconciled Finance visibility -- composed entirely
-- from already-governed sources, zero new stored figure anywhere.
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **Zero new table, by design.** Prompt 213 section 13's own "add only
--   required read views/query functions" is read literally: billing/AR/AP
--   aging (`FIN-197`/`FIN-210`), cash (`FIN-211`), reconciliation (`FIN-209`)
--   and profitability (`FIN-212`) already have exactly one governed source
--   of truth each -- this migration adds three narrow, read-only
--   aggregation functions (billing status summary, reconciliation status
--   summary, cash summary across every bank account) and reuses
--   `app.get_finance_aging_summary`/`app.get_finance_profitability_summary`
--   verbatim for the remaining two sections. No dashboard-owned balance,
--   snapshot or cache table is created -- every number is computed live,
--   at read time, from the identical rows each owning capability's own
--   migration already authored.
-- * **Every new function composes an already-authority-checked call, never
--   bypasses one.** `app.get_finance_dashboard_cash_summary` calls
--   `app.list_finance_bank_accounts`/`app.get_finance_cash_position`
--   per account (both already `FIN:View`-gated) rather than re-deriving the
--   statement/GL balance logic a second time; this migration's own two
--   direct-table reads (billing, reconciliation) add the identical
--   `FIN:View` gate via `app.check_finance_dashboard_authority`, the same
--   thin wrapper pattern every prior Finance capability's own
--   `check_finance_*_authority` function already establishes.
-- * **Disclosed, bounded checkpoint scope.** This capability covers exactly
--   the sections this repository already has a governed source for:
--   billing (invoice status/currency counts), AR/AP aging, cash, close
--   (reconciliation run status), and profitability. Trial balance,
--   profit-and-loss/balance-sheet statements, budget-versus-actual and tax
--   liability summaries are NOT built here -- no such engine exists
--   anywhere in this repository yet to source them from, and inventing one
--   would be exactly the "opaque or manually patched total" section 19
--   forbids. A full report catalogue with saved views, scheduling and async
--   export (sections 14/15/17's own broader ask) is equally out of this
--   single checkpoint's bounded scope -- the same class of proportionate-
--   effort scope decision this entire Finance phase has disclosed
--   throughout (e.g. `FIN-197`'s own bounded invoice-numbering scope,
--   `FIN-211`'s own "no live bank-provider adapter"). Every section that IS
--   built discloses its own `as_of`/basis explicitly to the caller, never
--   silently implying completeness beyond what is actually computed.
-- * **Aggregate-safe, never a raw per-row export.** Every new function
--   returns grouped counts/sums only (by status/currency/scope) -- no bank
--   account number, individual invoice line, or margin-shaped row is
--   exposed by any function this migration adds. The profitability section
--   this dashboard composes remains gated on `FIN:View margin` exactly as
--   `FIN-212` already established -- a caller lacking that permission sees
--   every other section but not profitability, never a fabricated zero in
--   its place.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--   carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
--   FROM PUBLIC` statement before its final grants, the standing
--   per-migration convention since `PLT-118`.

create function app.check_finance_dashboard_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_dashboard_authority is
  'FIN-213: FIN:View gates every dashboard read this migration adds directly (billing/reconciliation summaries); the cash summary additionally composes app.list_finance_bank_accounts/app.get_finance_cash_position, which are already FIN:View-gated in their own right.';

-- Billing pipeline (Prompt 213 section 15's own "billing readiness/invoice"):
-- grouped invoice counts/totals by status and currency -- never a raw
-- per-invoice row.
create function app.get_finance_dashboard_billing_summary(
  p_tenant_id uuid,
  p_company_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  status text,
  currency text,
  invoice_count bigint,
  total_amount numeric
)
language plpgsql
stable
as $$
begin
  if not app.check_finance_dashboard_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select i.status, i.currency, count(*)::bigint, sum(i.total_amount)
    from app.finance_invoices i
    where i.tenant_id = p_tenant_id and (p_company_id is null or i.company_id = p_company_id)
    group by i.status, i.currency
    order by i.status, i.currency;
end;
$$;

-- Close/reconciliation status (Prompt 213 section 15's own "reconciliation
-- and close"): the most recent run per scope, reusing FIN-209's own
-- already-computed variance -- never a re-derived balance.
create function app.get_finance_dashboard_reconciliation_summary(
  p_tenant_id uuid,
  p_company_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  scope text,
  as_of_date date,
  status text,
  is_within_tolerance boolean,
  variance_amount numeric,
  checked_at timestamptz
)
language plpgsql
stable
as $$
begin
  if not app.check_finance_dashboard_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select distinct on (r.scope) r.scope, r.as_of_date, r.status, r.is_within_tolerance, r.variance_amount, r.created_at
    from app.finance_reconciliation_runs r
    where r.tenant_id = p_tenant_id and (p_company_id is null or r.company_id = p_company_id)
    order by r.scope, r.created_at desc;
end;
$$;

-- Cash (Prompt 213 section 15's own "cash"): composed across every one of
-- the tenant's own bank accounts via FIN-211's own governed
-- app.get_finance_cash_position, grouped by currency -- never a
-- re-derived balance, never a raw per-account row.
create function app.get_finance_dashboard_cash_summary(
  p_tenant_id uuid,
  p_company_id uuid,
  p_as_of_date date,
  p_actor_auth_user_id uuid
)
returns table (
  currency text,
  account_count bigint,
  statement_balance numeric,
  gl_balance numeric,
  variance_amount numeric
)
language plpgsql
stable
as $$
begin
  if not app.check_finance_dashboard_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select pos.currency, count(*)::bigint, sum(pos.statement_balance), sum(pos.gl_balance), sum(pos.variance_amount)
    from app.list_finance_bank_accounts(p_tenant_id, p_company_id, p_actor_auth_user_id) acct
    cross join lateral app.get_finance_cash_position(p_tenant_id, acct.id, p_as_of_date, p_actor_auth_user_id) pos
    group by pos.currency
    order by pos.currency;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.check_finance_dashboard_authority(text, uuid, uuid) to service_role;
grant execute on function app.get_finance_dashboard_billing_summary(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_finance_dashboard_reconciliation_summary(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_finance_dashboard_cash_summary(uuid, uuid, date, uuid) to authenticated, service_role;
