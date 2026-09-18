-- CG-AUDIT-2026-09-02 B2a: general ledger trial balance / account balance.
--
-- The original finding ("GL is write-only -- no trial balance/account
-- balance/P&L/balance sheet") was carried in the remediation backlog as one
-- undivided DEFERRED_LARGE item, "real report-building effort, weeks per
-- the audit's own estimate". A dedicated research pass (this backlog's own
-- standing "verify before trusting a deferred label" discipline, the same
-- one that found B7's real bounded core) found that estimate accurate for
-- P&L/balance sheet/year-end close, but NOT for a trial balance: every hard
-- part already exists and is already correct --
--   * app.finance_accounts (FIN-192) already carries a hard-constrained
--     account_type (asset/liability/equity/revenue/expense) and
--     normal_balance, exactly the classification a trial balance needs, and
--     a control account is structurally never postable
--     (finance_accounts_control_not_postable_check).
--   * app.finance_journals/app.finance_journal_lines (FIN-203) is a real,
--     enforced double-entry ledger -- app.validate_finance_journal_line_
--     balance is the one shared rule both the manual and every
--     system/subledger-sourced posting path call, so no unbalanced journal
--     can ever exist, and a posted journal is never edited in place
--     (reversal always posts a new offsetting journal --
--     20260826030000/20260917010000 -- so finance_journal_lines is safe to
--     sum directly for any posted, dated cutoff).
--   * The exact "sum debit-minus-credit, grouped, as of a cutoff date"
--     query shape already exists once in this codebase --
--     app.get_finance_cash_position (20260729250000) -- adapted here from a
--     single hardcoded account to every account in the chart, and from the
--     bank-reconciliation subledger view to the canonical GL
--     (finance_journal_lines/finance_journals) directly.
--   * The app.*/public.* wrapper convention (RGL-394 Option-2) is
--     mechanical, established, and applied identically here.
--
-- Real, disclosed limitation carried forward (ties to the still-open B4
-- finding, "multi-currency postings summed as raw numbers"):
-- finance_journals.currency is one field per whole journal;
-- finance_journal_lines carries no currency of its own, and
-- finance_accounts.currency_restriction is defined but never enforced at
-- posting time (checked: neither app.create_finance_journal_draft nor
-- app.post_finance_subledger_batch validates a line's journal currency
-- against its account's currency_restriction). Nothing in the schema
-- prevents the same GL account from receiving lines from journals in
-- different currencies, and a single blended sum across currencies would be
-- financially meaningless if that ever happens for a given tenant. Rather
-- than hide this, app.get_finance_trial_balance groups by (account,
-- journal currency) and returns one row per currency actually in play for
-- that account -- an account touched by exactly one currency (the normal
-- case) yields exactly one row, honest and no different from a single
-- blended figure; an account touched by more than one currency yields one
-- row per currency rather than a silently-wrong blended total. Producing a
-- single reporting-currency figure would require a functional-currency
-- conversion layer (FX rate applied at report time or at posting time) that
-- does not exist anywhere in this schema today -- genuinely out of this
-- slice's own bounded scope, left for B4/a future P&L-and-balance-sheet
-- slice alongside period-scoped net-income roll-up and account-hierarchy
-- subtotaling, which is why B2 remains PARTIAL, not DONE.
--
-- Deliberately excludes all draft/submitted/approved/void journals (status
-- <> 'posted') and any journal dated after the caller's own p_as_of_date --
-- a trial balance is a point-in-time statement of what has actually posted,
-- never of what is merely pending. Deliberately does NOT filter accounts by
-- their own current status (active/inactive/draft): an account deactivated
-- after it carried real posted activity must still show that activity on a
-- historical trial balance, so filtering by current account status would
-- silently drop a real balance -- the one thing a trial balance must never
-- do.

create function app.get_finance_trial_balance(
  p_tenant_id uuid,
  p_company_id uuid,
  p_as_of_date date,
  p_actor_auth_user_id uuid
)
returns table (
  account_id uuid,
  account_code text,
  account_name text,
  account_type text,
  normal_balance text,
  currency text,
  debit_balance numeric,
  credit_balance numeric
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.check_finance_account_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_as_of_date is null then
    raise exception 'finance_trial_balance_as_of_date_required: p_as_of_date must not be null'
      using errcode = 'not_null_violation';
  end if;

  return query
    with eligible_lines as (
      select jl.account_id, jl.direction, jl.amount, j.currency
      from app.finance_journal_lines jl
      join app.finance_journals j on j.id = jl.journal_id
      where jl.tenant_id = p_tenant_id
        and j.status = 'posted'
        and j.journal_date <= p_as_of_date
    ),
    totals as (
      select
        a.id as t_account_id,
        a.code as t_account_code,
        a.name as t_account_name,
        a.account_type as t_account_type,
        a.normal_balance as t_normal_balance,
        el.currency as t_currency,
        coalesce(sum(case when el.direction = 'debit' then el.amount else -el.amount end), 0) as net_amount
      from app.finance_accounts a
      left join eligible_lines el on el.account_id = a.id
      where a.tenant_id = p_tenant_id
        and a.company_id is not distinct from p_company_id
      group by a.id, a.code, a.name, a.account_type, a.normal_balance, el.currency
    )
    select
      t_account_id,
      t_account_code,
      t_account_name,
      t_account_type,
      t_normal_balance,
      t_currency,
      greatest(net_amount, 0) as debit_balance,
      greatest(-net_amount, 0) as credit_balance
    from totals
    order by t_account_code, t_currency nulls first;
end;
$$;

comment on function app.get_finance_trial_balance is
  'CG-AUDIT-2026-09-02 B2a: trial balance as of p_as_of_date -- every finance_accounts row for the tenant/company, joined against posted, dated-eligible finance_journal_lines only. One row per (account, currency actually posted against it) -- see this migration''s own header for why a blended cross-currency sum is deliberately not produced. debit_balance/credit_balance are net, mutually exclusive (a net-debit account has 0 in credit_balance and vice versa), the standard trial-balance columnar convention. A zero-activity account still appears, with currency null and both balances 0, since a trial balance must list every account, not only ones with a nonzero balance.';

revoke execute on function app.get_finance_trial_balance(uuid, uuid, date, uuid) from public;
grant execute on function app.get_finance_trial_balance(uuid, uuid, date, uuid) to authenticated, service_role;

-- app.get_finance_trial_balance(p_tenant_id uuid, p_company_id uuid, p_as_of_date date, p_actor_auth_user_id uuid) -- security definer, matched below
create function public.get_finance_trial_balance(
  p_tenant_id uuid, p_company_id uuid, p_as_of_date date, p_actor_auth_user_id uuid
)
returns table (
  account_id uuid,
  account_code text,
  account_name text,
  account_type text,
  normal_balance text,
  currency text,
  debit_balance numeric,
  credit_balance numeric
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_finance_trial_balance(p_tenant_id, p_company_id, p_as_of_date, p_actor_auth_user_id);
$wrap$;

comment on function public.get_finance_trial_balance(p_tenant_id uuid, p_company_id uuid, p_as_of_date date, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_finance_trial_balance with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.get_finance_trial_balance(uuid, uuid, date, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_trial_balance(uuid, uuid, date, uuid) to service_role;
grant execute on function public.get_finance_trial_balance(uuid, uuid, date, uuid) to authenticated;
