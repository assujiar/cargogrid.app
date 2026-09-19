-- CG-AUDIT-2026-09-02 B4 (bounded core): a real, live, shipped cross-currency
-- blend bug in app.get_finance_ar_exposure_summary/app.get_finance_ap_exposure_summary,
-- found by a dedicated research pass, the same "verify before trusting a
-- deferred label" discipline that found B7's/B2a's/E6's own real bounded
-- cores. The original finding ("Multi-currency postings summed as raw
-- numbers, no FX/base-amount columns") was carried in the remediation
-- backlog as one undivided DEFERRED_LARGE item ("schema redesign across
-- finance_journals/finance_journal_lines") and had never itself been
-- independently re-verified.
--
-- What the research pass found, all confirmed by reading the actual current
-- code, never assumed:
--   * app.get_finance_ar_exposure_summary/app.get_finance_ap_exposure_summary
--     (both live since 20260729100000/20260729130000, last touched
--     20260810900000_harden_finance_authority_chain_tierc_completeness.sql,
--     the true current version -- confirmed via a case-insensitive search
--     this time, after E6's own earlier miss on exactly this class of
--     mistake) sum app.finance_ar_open_items.open_amount/app.finance_ap_
--     open_items.open_amount with NO currency filter or grouping at all --
--     `where tenant_id = p_tenant_id and customer_account_id = ...`, full
--     stop. Both are called live by server/queries/accounts-receivable.ts
--     and server/queries/accounts-payable.ts and rendered as a "credit
--     exposure" figure a real Finance user sees today
--     (app/(tenant)/[tenantSlug]/finance/accounts-receivable/
--     accounts-receivable-forms.tsx). Any customer/vendor with open items in
--     more than one currency gets a financially meaningless blended total --
--     a genuine, live, shipped bug, not a theoretical schema gap, matching
--     the severity class of this session's own earlier B5/D3-series fixes.
--   * This is not a rare edge case: app.finance_accounts.currency_
--     restriction (confirmed unenforced at posting time by B2a's own
--     research, re-confirmed here) means any tenant invoicing customers in
--     more than one currency posts to the SAME tenant-wide AR/AP control
--     account regardless of currency (app.resolve_finance_posting_map_
--     account resolves one control account per posting-map key, not one
--     per currency) -- structurally normal for a multi-currency tenant, not
--     exotic.
--   * The "no FX/base-amount columns" half of the finding does NOT require
--     inventing new FX machinery or redesigning finance_journal_lines, as
--     the backlog's own "schema redesign" phrase implied. app.finance_
--     currency_exchange_rate (FIN-194, 20260728230000) already provides a
--     real, governed, versioned (draft->approved->archived), date-effective
--     rate registry -- app.resolve_finance_exchange_rate(tenant, rate_type,
--     source_currency, target_currency, as_of) deterministically resolves a
--     real rate with NO authority check of its own (a pure SQL read,
--     already the correct shape to call from inside another gated
--     function), and it is already proven, exercised, non-theoretical
--     machinery: app.resolve_operations_fx_conversion
--     (20260902050000_wire_fx_conversion_into_operations_job_profitability.sql)
--     already wraps it for job-profitability reporting, and the loyalty-
--     liability consolidated-rollup capability
--     (20260902223000_close_iss2026134_item1_cross_currency_liability_
--     reconciliation.sql) already uses the identical "convert each
--     currency-scoped total, sum only what actually converted, mark what
--     didn't rather than fabricate a rate" pattern this migration mirrors.
--   * app.tenant_locale_versions.default_currency (resolved via app.
--     resolve_tenant_locale, PLT-119/20260717112000) is already, in
--     practice, this repository's own real "base/reporting currency"
--     concept -- already load-bearing for exactly this purpose in job
--     profitability and loyalty liability, despite that migration's own
--     header disclaiming it as "display preference only." This migration
--     reuses it the same way, not a new concept.
--
-- Fix: both functions widen from a single blended jsonb object to a real,
-- honest per-currency breakdown (setof table, one row per currency actually
-- in play -- the same "never blend, group by currency" discipline B2a's own
-- trial balance already established), PLUS a base-currency-converted figure
-- on each row using the tenant's own resolved default_currency and the
-- real, already-proven FX machinery above. A currency that already matches
-- the tenant's base currency needs no rate (fx_status='identity', mirrors
-- app.resolve_operations_fx_conversion's own identity fast path); a
-- currency with no published rate covering "now" returns fx_status=
-- 'rate_unavailable' with a null base_total_open/base_overdue_open --
-- NEVER a fabricated or silently-zeroed figure, the same discipline the
-- loyalty-liability reconciliation's own "partial_rate_unavailable" already
-- established. Rolling up the honest per-currency figures into one further
-- single grand total (if ever wanted) is a caller-side decision, deliberately
-- left to the TS/UI layer rather than this RPC, so the RPC itself never
-- silently presents a partial (some-currencies-unconverted) result as if it
-- were complete.
--
-- Disclosed behavior change: a customer/vendor with literally zero open
-- items now returns zero rows (there is no real currency to attach a
-- zero-count row to), where the old single-object shape always returned
-- exactly one all-zero object. The TS/UI layer is updated accordingly.
--
-- Still explicitly out of scope, correctly left DEFERRED_LARGE: retroactive
-- FX/base-amount persistence on finance_journal_lines itself (the
-- backlog's own original, genuinely larger "schema redesign" reading),
-- app.finance_accounts.currency_restriction enforcement at posting time
-- (a related but separate, not-yet-scoped hardening item), and a true
-- consolidated multi-currency P&L/balance sheet (already correctly
-- deferred under B2's own still-open half). This migration closes the one
-- concrete, live, shipped bug plus the one bounded reporting improvement
-- the research pass found -- not the whole of B4.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): DROP + CREATE resets a
-- function's privileges to the PostgreSQL PUBLIC-execute default, unlike
-- CREATE OR REPLACE (required here since the RETURN TYPE changes from
-- jsonb to a table, which CREATE OR REPLACE FUNCTION cannot do) -- this
-- migration carries its own explicit `revoke execute on all functions in
-- schema app from public` before its final grants, the standing
-- per-migration convention since PLT-118.

drop function app.get_finance_ap_exposure_summary(uuid, uuid, uuid);

create function app.get_finance_ap_exposure_summary(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid)
returns table (
  currency text,
  total_open numeric,
  open_count integer,
  overdue_open numeric,
  overdue_count integer,
  base_currency text,
  base_total_open numeric,
  base_overdue_open numeric,
  fx_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_base_currency text;
  v_base_precision integer;
  v_row record;
  v_rate app.finance_exchange_rates;
begin
  if not app.check_finance_ap_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select rtl.default_currency into v_base_currency from app.resolve_tenant_locale(p_tenant_id) rtl;
  select coalesce(minor_unit_precision, 2) into v_base_precision from app.finance_currencies where code = v_base_currency;
  v_base_precision := coalesce(v_base_precision, 2);

  for v_row in
    select
      i.currency as row_currency,
      coalesce(sum(i.open_amount), 0) as row_total_open,
      count(*) filter (where i.status <> 'settled') as row_open_count,
      coalesce(sum(i.open_amount) filter (where i.status <> 'settled' and i.due_date < current_date), 0) as row_overdue_open,
      count(*) filter (where i.status <> 'settled' and i.due_date < current_date) as row_overdue_count
    from app.finance_ap_open_items i
    where i.tenant_id = p_tenant_id and i.vendor_master_id = p_vendor_master_id
    group by i.currency
    order by i.currency
  loop
    currency := v_row.row_currency;
    total_open := v_row.row_total_open;
    open_count := v_row.row_open_count;
    overdue_open := v_row.row_overdue_open;
    overdue_count := v_row.row_overdue_count;
    base_currency := v_base_currency;

    if v_row.row_currency = v_base_currency then
      base_total_open := round(v_row.row_total_open, v_base_precision);
      base_overdue_open := round(v_row.row_overdue_open, v_base_precision);
      fx_status := 'identity';
    else
      select * into v_rate from app.resolve_finance_exchange_rate(p_tenant_id, 'spot', v_row.row_currency, v_base_currency, now());
      if found then
        base_total_open := round(v_row.row_total_open * v_rate.rate, v_base_precision);
        base_overdue_open := round(v_row.row_overdue_open * v_rate.rate, v_base_precision);
        fx_status := 'converted';
      else
        base_total_open := null;
        base_overdue_open := null;
        fx_status := 'rate_unavailable';
      end if;
    end if;

    return next;
  end loop;

  return;
end;
$$;

comment on function app.get_finance_ap_exposure_summary is
  'CG-AUDIT-2026-09-02 B4: one row per currency actually posted for this vendor (never a blended cross-currency sum -- the exact live bug this migration fixes), each carrying its own base-currency-converted figure via app.resolve_finance_exchange_rate/the tenant''s own app.resolve_tenant_locale default_currency, honestly degraded to null with fx_status=rate_unavailable rather than fabricated when no rate covers now(). Zero open items now returns zero rows (no real currency to anchor a zero row to), a disclosed change from the prior single-blended-object shape.';

revoke execute on all functions in schema app from public;
grant execute on function app.get_finance_ap_exposure_summary(uuid, uuid, uuid) to authenticated, service_role;

drop function app.get_finance_ar_exposure_summary(uuid, uuid, uuid);

create function app.get_finance_ar_exposure_summary(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid)
returns table (
  currency text,
  total_open numeric,
  open_count integer,
  overdue_open numeric,
  overdue_count integer,
  base_currency text,
  base_total_open numeric,
  base_overdue_open numeric,
  fx_status text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_base_currency text;
  v_base_precision integer;
  v_row record;
  v_rate app.finance_exchange_rates;
begin
  if not app.check_finance_ar_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select rtl.default_currency into v_base_currency from app.resolve_tenant_locale(p_tenant_id) rtl;
  select coalesce(minor_unit_precision, 2) into v_base_precision from app.finance_currencies where code = v_base_currency;
  v_base_precision := coalesce(v_base_precision, 2);

  for v_row in
    select
      i.currency as row_currency,
      coalesce(sum(i.open_amount), 0) as row_total_open,
      count(*) filter (where i.status <> 'paid') as row_open_count,
      coalesce(sum(i.open_amount) filter (where i.status <> 'paid' and i.due_date < current_date), 0) as row_overdue_open,
      count(*) filter (where i.status <> 'paid' and i.due_date < current_date) as row_overdue_count
    from app.finance_ar_open_items i
    where i.tenant_id = p_tenant_id and i.customer_account_id = p_customer_account_id
    group by i.currency
    order by i.currency
  loop
    currency := v_row.row_currency;
    total_open := v_row.row_total_open;
    open_count := v_row.row_open_count;
    overdue_open := v_row.row_overdue_open;
    overdue_count := v_row.row_overdue_count;
    base_currency := v_base_currency;

    if v_row.row_currency = v_base_currency then
      base_total_open := round(v_row.row_total_open, v_base_precision);
      base_overdue_open := round(v_row.row_overdue_open, v_base_precision);
      fx_status := 'identity';
    else
      select * into v_rate from app.resolve_finance_exchange_rate(p_tenant_id, 'spot', v_row.row_currency, v_base_currency, now());
      if found then
        base_total_open := round(v_row.row_total_open * v_rate.rate, v_base_precision);
        base_overdue_open := round(v_row.row_overdue_open * v_rate.rate, v_base_precision);
        fx_status := 'converted';
      else
        base_total_open := null;
        base_overdue_open := null;
        fx_status := 'rate_unavailable';
      end if;
    end if;

    return next;
  end loop;

  return;
end;
$$;

comment on function app.get_finance_ar_exposure_summary is
  'CG-AUDIT-2026-09-02 B4: one row per currency actually posted for this customer (never a blended cross-currency sum -- the exact live bug this migration fixes), each carrying its own base-currency-converted figure via app.resolve_finance_exchange_rate/the tenant''s own app.resolve_tenant_locale default_currency, honestly degraded to null with fx_status=rate_unavailable rather than fabricated when no rate covers now(). Zero open items now returns zero rows (no real currency to anchor a zero row to), a disclosed change from the prior single-blended-object shape.';

revoke execute on all functions in schema app from public;
grant execute on function app.get_finance_ar_exposure_summary(uuid, uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- public.* wrappers -- return type changed (jsonb -> table), so these must
-- also DROP + CREATE, never ALTER/replace. Mirrors 20260907160000's own
-- established drop-then-create-then-explicit-anon/authenticated/service_role
-- revoke pattern for exactly this class of signature-incompatible change.
-- ===========================================================================

drop function public.get_finance_ap_exposure_summary(uuid, uuid, uuid);

create function public.get_finance_ap_exposure_summary(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid)
returns table (
  currency text,
  total_open numeric,
  open_count integer,
  overdue_open numeric,
  overdue_count integer,
  base_currency text,
  base_total_open numeric,
  base_overdue_open numeric,
  fx_status text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_finance_ap_exposure_summary(p_tenant_id, p_vendor_master_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_finance_ap_exposure_summary(uuid, uuid, uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_finance_ap_exposure_summary with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.get_finance_ap_exposure_summary(uuid, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_ap_exposure_summary(uuid, uuid, uuid) to service_role;
grant execute on function public.get_finance_ap_exposure_summary(uuid, uuid, uuid) to authenticated;

drop function public.get_finance_ar_exposure_summary(uuid, uuid, uuid);

create function public.get_finance_ar_exposure_summary(p_tenant_id uuid, p_customer_account_id uuid, p_actor_auth_user_id uuid)
returns table (
  currency text,
  total_open numeric,
  open_count integer,
  overdue_open numeric,
  overdue_count integer,
  base_currency text,
  base_total_open numeric,
  base_overdue_open numeric,
  fx_status text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_finance_ar_exposure_summary(p_tenant_id, p_customer_account_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_finance_ar_exposure_summary(uuid, uuid, uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_finance_ar_exposure_summary with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.get_finance_ar_exposure_summary(uuid, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_finance_ar_exposure_summary(uuid, uuid, uuid) to service_role;
grant execute on function public.get_finance_ar_exposure_summary(uuid, uuid, uuid) to authenticated;
