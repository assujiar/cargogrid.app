-- CG-AUDIT-2026-09-02 B2 (bounded core): "P&L, balance sheet, GL report,
-- and year-end close all need work" -- carried as one undivided item
-- needing "period-scoped net-income roll-up, account-hierarchy
-- subtotaling, and a real reporting-currency/FX conversion layer" and
-- never itself independently re-verified since B2a closed the trial-
-- balance half.
--
-- A dedicated research pass, the same "verify before trusting a bundled
-- disposition" discipline that found B7's/B2a's/E6's/B4's/A2b's/E3's/C1's/
-- B3's own real bounded cores, found the "GL report" sub-item was mis-
-- bundled with the genuinely harder P&L/balance-sheet/year-end-close trio:
--
--   * P&L (net-income roll-up), balance sheet (account-hierarchy
--     subtotaling), and year-end close all genuinely need the three
--     things the backlog names -- stay DEFERRED_LARGE, untouched.
--
--   * "GL report" -- a general ledger DETAIL report, the classic
--     bookkeeper's tool for reconciling one account's own posted
--     activity -- needs none of those three things. Today there is no
--     way to view an account's own posted transaction history at all:
--     app.list_finance_journals (20260729170000) lists whole journals
--     filtered by source_type/status/company, never by account_id; app.
--     get_finance_journal_lines returns lines for exactly ONE journal_id
--     at a time. The audit's own "GL is write-only" framing is thus
--     still literally true even after B2a's own trial-balance fix: you
--     can browse individual journals or see a trial-balance TOTAL, but
--     you cannot ask "show me every posted entry against Accounts
--     Receivable this quarter" -- exactly the everyday reconciliation
--     need a trial-balance figure exists to be checked against.
--     finance_journal_lines_account_idx (tenant_id, account_id), already
--     present since 20260729170000 and unused by any query in this
--     codebase until now, is a strong "assembly, not invention" signal --
--     the same signal B2a itself used to justify closing trial balance.
--     A GL detail report for one account needs none of the three blocking
--     things: no net-income roll-up (P&L-only), no account-hierarchy
--     subtotaling (a control account is structurally never postable,
--     `finance_accounts_control_not_postable_check`, so a ledger report
--     only ever targets one leaf/postable account directly), and no new
--     FX/reporting-currency layer (reuses B2a's own already-accepted,
--     already-disclosed "group by currency actually posted, never blend"
--     convention verbatim).
--
-- Fix: app.get_finance_account_ledger -- one account, one date range, an
-- opening balance PER CURRENCY (net posted activity strictly before
-- p_date_from, in the account's own normal_balance direction) followed by
-- every posted line within [p_date_from, p_date_to] with a running
-- balance carried forward from that opening balance. Never blends
-- currencies, mirroring app.get_finance_trial_balance's own disclosed
-- limitation exactly.

create function app.get_finance_account_ledger(
  p_tenant_id uuid,
  p_company_id uuid,
  p_account_id uuid,
  p_date_from date,
  p_date_to date,
  p_actor_auth_user_id uuid
)
returns table (
  entry_date date,
  journal_id uuid,
  journal_number text,
  source_type text,
  description text,
  direction text,
  amount numeric,
  running_balance numeric,
  currency text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_account app.finance_accounts;
begin
  if not app.check_finance_account_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.finance_accounts
    where id = p_account_id and tenant_id = p_tenant_id and company_id is not distinct from p_company_id;
  if not found then
    raise exception 'finance_account_ledger_account_not_found: % is not a known account for tenant %', p_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  if p_date_from is null or p_date_to is null then
    raise exception 'finance_account_ledger_date_range_required: both p_date_from and p_date_to are required'
      using errcode = 'not_null_violation';
  end if;
  if p_date_to < p_date_from then
    raise exception 'finance_account_ledger_invalid_date_range: p_date_to (%) is before p_date_from (%)', p_date_to, p_date_from
      using errcode = 'check_violation';
  end if;

  -- Every intermediate CTE column below is deliberately prefixed (x_*) to
  -- avoid ambiguity against this function's own RETURNS TABLE column names,
  -- which PL/pgSQL treats as in-scope variables throughout this function
  -- body -- a bare `currency`/`amount`/`journal_id`/etc. column reference
  -- inside the query would otherwise be genuinely ambiguous between the
  -- CTE's own column and the OUT parameter of the identical name (caught
  -- live: "column reference \"currency\" is ambiguous" on this migration's
  -- own first quick-iteration db-test run). Only the final, outermost
  -- select re-aliases back to the real output column names.
  return query
    with eligible as (
      select
        jl.journal_id as x_journal_id, j.journal_number as x_journal_number, j.journal_date as x_journal_date,
        j.source_type as x_source_type, jl.description as x_description, jl.direction as x_direction, jl.amount as x_amount,
        j.currency as x_currency,
        (case when jl.direction = v_account.normal_balance then jl.amount else -jl.amount end) as x_signed_amount
      from app.finance_journal_lines jl
      join app.finance_journals j on j.id = jl.journal_id
      where jl.tenant_id = p_tenant_id and jl.account_id = p_account_id and j.status = 'posted'
    ),
    window_activity as (
      select * from eligible where x_journal_date between p_date_from and p_date_to
    ),
    window_currencies as (
      select distinct x_currency from window_activity
    ),
    opening as (
      select wc.x_currency, coalesce(sum(e.x_signed_amount), 0) as x_opening_balance
      from window_currencies wc
      left join eligible e on e.x_currency = wc.x_currency and e.x_journal_date < p_date_from
      group by wc.x_currency
    ),
    opening_rows as (
      select
        p_date_from as x_entry_date, null::uuid as x_journal_id, null::text as x_journal_number, null::text as x_source_type,
        'Opening balance'::text as x_description, null::text as x_direction, null::numeric as x_amount,
        o.x_opening_balance as x_running_balance, o.x_currency
      from opening o
    ),
    activity_rows as (
      select
        wa.x_journal_date as x_entry_date, wa.x_journal_id, wa.x_journal_number, wa.x_source_type, wa.x_description, wa.x_direction, wa.x_amount,
        o.x_opening_balance + sum(wa.x_signed_amount) over (partition by wa.x_currency order by wa.x_journal_date, wa.x_journal_id rows unbounded preceding) as x_running_balance,
        wa.x_currency
      from window_activity wa
      join opening o on o.x_currency = wa.x_currency
    ),
    combined as (
      select * from opening_rows
      union all
      select * from activity_rows
    )
    select
      x_entry_date, x_journal_id, x_journal_number, x_source_type, x_description, x_direction, x_amount, x_running_balance, x_currency
    from combined
    order by x_currency, x_entry_date, x_journal_id nulls first;
end;
$$;

comment on function app.get_finance_account_ledger is
  'CG-AUDIT-2026-09-02 B2 (GL detail report half): one account''s own posted transaction history for a date range, with a per-currency opening balance (net posted activity strictly before p_date_from, never blended across currencies -- mirrors app.get_finance_trial_balance''s own disclosed convention) and a running balance carried forward through every posted line in range. Only app.finance_journal_lines rows on a status=posted app.finance_journals count -- a draft/submitted/approved-but-not-posted journal never appears. FIN:View-gated.';

revoke execute on function app.get_finance_account_ledger(uuid, uuid, uuid, date, date, uuid) from public;
grant execute on function app.get_finance_account_ledger(uuid, uuid, uuid, date, date, uuid) to authenticated, service_role;

-- ===========================================================================
-- RGL-394 Option-2 public.* wrapper
-- ===========================================================================

create function public.get_finance_account_ledger(p_tenant_id uuid, p_company_id uuid, p_account_id uuid, p_date_from date, p_date_to date, p_actor_auth_user_id uuid)
returns table (
  entry_date date,
  journal_id uuid,
  journal_number text,
  source_type text,
  description text,
  direction text,
  amount numeric,
  running_balance numeric,
  currency text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_finance_account_ledger(p_tenant_id, p_company_id, p_account_id, p_date_from, p_date_to, p_actor_auth_user_id);
$wrap$;

comment on function public.get_finance_account_ledger(p_tenant_id uuid, p_company_id uuid, p_account_id uuid, p_date_from date, p_date_to date, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_finance_account_ledger with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.get_finance_account_ledger(p_tenant_id uuid, p_company_id uuid, p_account_id uuid, p_date_from date, p_date_to date, p_actor_auth_user_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_account_ledger(p_tenant_id uuid, p_company_id uuid, p_account_id uuid, p_date_from date, p_date_to date, p_actor_auth_user_id uuid) to authenticated, service_role;
