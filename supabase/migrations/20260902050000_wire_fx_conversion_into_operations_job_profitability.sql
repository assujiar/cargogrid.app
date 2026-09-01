-- ISS-2026-197 (docs/runtime/KNOWN_ISSUES.md) -- real, additive fix for the entry's own core
-- subject: "no FX/multi-currency conversion exists anywhere in the revenue chain;
-- app.calculate_job_profitability (Operations) always reports the static quote-time total,
-- never the actual invoiced/billed figure." ADR-0027 owner-authorized broader remediation scope.
--
-- What was verified LIVE before writing a single line here (the entry's own prior passes
-- already established this, re-confirmed against the current schema, not re-derived from
-- memory):
--   * `app.finance_exchange_rates` (FIN-193/194) already exists, is a real versioned/dated
--     rate table -- `(tenant_id, rate_type, source_currency, target_currency, rate,
--     effective_from, effective_to, status)`, `status='approved'` only usable, overlap-checked
--     at approval time (ATW-032) -- the exact "valid as of a date, not a single mutable
--     current value" shape this entry's own remediation brief asked for, already shipped, not
--     rebuilt here. `app.resolve_finance_exchange_rate` already does the as-of lookup;
--     `app.convert_finance_amount` already does rate*amount with governed rounding.
--   * A real admin surface to input/publish rates already exists too, both at the RPC layer
--     (`app.create_finance_exchange_rate_draft` / `app.approve_finance_exchange_rate` /
--     `app.list_finance_exchange_rates`, FIN:Edit to draft, FIN:Approve to publish) and at the
--     UI layer (`app/(tenant)/[tenantSlug]/finance/exchange-rates`, a full draft/approve form
--     already shipped). Neither is touched by this migration -- there was nothing to build.
--   * The entry's own text names where the "actual invoiced/billed figure" lives: Finance AR,
--     `app.finance_invoices` (`status='issued'`), the exact table
--     `app.calculate_finance_job_profitability` (FIN-212) already reads for its own 'billed'
--     revenue_basis. This migration reads the same table the same way (issued invoices for the
--     Job Order, `subtotal_amount`), not a new or parallel source of billed truth.
--
-- So the entry's genuinely missing piece was narrow and precise: `app.calculate_job_profitability`
-- (Operations, OPS-179) itself never called any of the above. It read the Job Order's own
-- quote-time `revenue_snapshot.totalAmount` verbatim and, on a currency mismatch against the
-- approved cost, refused to answer (`status='unavailable'`/`blocked_reason='mixed_currency'`) --
-- correct as far as it went, but zero FX conversion was ever attempted, and the actual invoiced
-- total was never looked at, cost/mismatch aside. That is what this migration wires in,
-- additively:
--
--  1. `app.job_profitability_snapshots` gains 13 new nullable columns (never touching or
--     reinterpreting any existing one): the tenant's own base/reporting currency at calculation
--     time (`base_currency`, via `app.resolve_tenant_locale` -- the same established source
--     every other multi-currency-aware capability in this repo already reads, PLT-119/loyalty
--     liability/COM-156), the quote-time revenue converted into it
--     (`revenue_base_amount`/`revenue_fx_rate`/`revenue_fx_as_of`/`revenue_fx_status`), and the
--     actual invoiced total plus its own conversion
--     (`invoiced_currency`/`invoiced_amount`/`invoiced_status`/`invoiced_base_amount`/
--     `invoiced_fx_rate`/`invoiced_fx_as_of`/`invoiced_fx_status`/`source_invoice_ids`). The
--     ORIGINAL-currency figures (`revenue_currency`/`revenue_amount`,
--     `invoiced_currency`/`invoiced_amount`) are never discarded or overwritten by the
--     converted ones -- both sit side by side on the same row, per this entry's own explicit
--     "never silently discard the original" instruction.
--  2. A new internal helper, `app.resolve_operations_fx_conversion`, is the single, uniform call
--     site both conversions go through -- source-currency-equals-target-currency is handled
--     INSIDE this one shared helper (rate=1, `fx_status='identity'`) exactly the way
--     `app.convert_finance_amount` already handles its own identity case, never as a
--     special-cased branch at either call site in `calculate_job_profitability`. Unlike
--     `convert_finance_amount`, this helper carries no `FIN:View` authority gate -- it is an
--     internal reporting enrichment called from inside an already-authority-checked
--     `OPS:Edit`+`OPS:View margin` function, never granted to `authenticated`/`anon`, and it
--     never raises: a missing approved rate returns `fx_status='rate_unavailable'` (converted
--     amount left null) rather than aborting the whole profitability calculation an Operations
--     actor has every right to see in its own original currency regardless of Finance's rate
--     coverage. Requiring `FIN:View` here, or letting a rate gap raise, would both be silent
--     regressions for existing Operations-only callers -- verified nothing in this repository
--     depends on that expanded authority surface before choosing this shape.
--  3. `app.calculate_job_profitability` is rebuilt via `CREATE OR REPLACE FUNCTION`, body
--     verified byte-for-byte against the LIVE `pg_get_functiondef` output before editing (no
--     drift since `20260901050000`). Every line up to and including the existing
--     status/blocked_reason/margin branch is untouched, character for character; the new
--     conversion logic is appended after it, before the one `INSERT`, which gains the 13 new
--     columns. `language plpgsql`/`security definer`/`set search_path = app, pg_temp` restated
--     explicitly (ISS-2026-318's own recurrence class).
--  4. `app.job_profitability_directory` is rebuilt via `CREATE OR REPLACE VIEW`, new columns
--     appended after `revenue_basis` (`CREATE OR REPLACE VIEW` cannot reorder or insert
--     mid-list). Anything that is itself a dollar figure, a rate, a currency code tied to a
--     specific job's money, or an id array a masked viewer could use to look the money up
--     elsewhere (`revenue_base_amount`, `revenue_fx_rate`, `invoiced_currency`,
--     `invoiced_amount`, `invoiced_base_amount`, `invoiced_fx_rate`, `source_invoice_ids`) is
--     masked under the identical `app.has_view_job_margin(...)` CASE the original five columns
--     already use -- the same treatment `revenue_currency`/`revenue_amount` already get, applied
--     consistently to the new figures. Pure state/timing metadata that reveals no money
--     (`base_currency`, `revenue_fx_as_of`, `revenue_fx_status`, `invoiced_status`,
--     `invoiced_fx_as_of`, `invoiced_fx_status`) stays unmasked, the same treatment
--     `status`/`blocked_reason`/`revenue_basis` already get.
--  5. `public.calculate_job_profitability` (RGL-394 Option-2 wrapper,
--     `20260826000000_create_public_api_data_wrappers.sql`) is untouched -- verified live: it
--     `returns app.job_profitability_snapshots` by type reference, not an explicit column list,
--     so the 13 new columns flow through automatically, the identical fact
--     `20260901050000`'s own header already recorded for `revenue_basis`.
--
-- What this deliberately does NOT do, so the closure text in KNOWN_ISSUES.md does not overstate
-- it: no new admin UI panel is added (a real one already exists, see above); the quote-time "as
-- of" date is the Job Order's own `created_at` (the moment `revenue_snapshot` was pinned,
-- immutable thereafter) rather than a bespoke new "quoted at" field -- the closest honest proxy
-- already on the row, not a new concept invented for this migration; the invoiced "as of" date
-- is the invoice's own business `issue_date` (not the `issued_at` audit timestamp) -- the date a
-- real FX desk would look up, deliberately independent of when someone happened to click
-- "issue" in the system; only `rate_type='spot'` is read (the same default
-- `app.resolve_finance_exchange_rate`/`app.convert_finance_amount` already use) -- a forward,
-- budget or other rate type is not wired in, since nothing upstream of this table records which
-- rate type a quote or invoice was priced against; and the Operations job-order profitability
-- panel UI is not touched -- the new figures are exposed at the RPC/view/Zod-contract layer
-- (server/contracts/job-profitability/job-profitability.ts,
-- server/queries/job-profitability.ts), same as every other field on this row, but rendering
-- them is a follow-up, not required for this closure.
--
-- Verified live before writing this migration (disposable-equivalent read against the LIVE
-- hosted project, every migration through `20260901140000` already applied):
--   * `app.trg_capture_lineage_job_to_profitability` (transaction-lineage capture trigger on
--     this table) digests four explicitly named columns only (`revenue_amount`, `cost_amount`,
--     `margin_amount`, `status`) via `select *` into a typed row variable -- it does not
--     enumerate columns for the hash itself, so the new columns change nothing about its
--     lineage digest. No edit needed there, and none made.
--   * `app.finance_currencies` (`code`, `minor_unit_precision`, `is_active`) already carries
--     EUR/IDR/SGD/USD at 2dp and JPY at 0dp -- read by the new helper for converted-amount
--     rounding precision, the same table `app.convert_finance_amount` already reads for the
--     identical purpose.
--   * `app.resolve_tenant_locale` already falls back to `default_currency='IDR'` for a tenant
--     with no published `app.tenant_locale_versions` row (its own documented three-branch
--     shape) -- every existing tenant, including every db-test fixture tenant, resolves a real
--     base currency with zero new setup required by this migration.

alter table app.job_profitability_snapshots
  add column base_currency text,
  add column revenue_base_amount numeric(14, 2),
  add column revenue_fx_rate numeric,
  add column revenue_fx_as_of timestamptz,
  add column revenue_fx_status text,
  add column invoiced_currency text,
  add column invoiced_amount numeric(14, 2),
  add column invoiced_status text,
  add column invoiced_base_amount numeric(14, 2),
  add column invoiced_fx_rate numeric,
  add column invoiced_fx_as_of timestamptz,
  add column invoiced_fx_status text,
  add column source_invoice_ids uuid[] not null default '{}';

alter table app.job_profitability_snapshots
  add constraint job_profitability_snapshots_revenue_fx_status_check
    check (revenue_fx_status is null or revenue_fx_status in ('identity', 'converted', 'rate_unavailable')),
  add constraint job_profitability_snapshots_invoiced_status_check
    check (invoiced_status is null or invoiced_status in ('not_yet_invoiced', 'mixed_currency', 'available')),
  add constraint job_profitability_snapshots_invoiced_fx_status_check
    check (invoiced_fx_status is null or invoiced_fx_status in ('identity', 'converted', 'rate_unavailable')),
  add constraint job_profitability_snapshots_revenue_base_amount_check check (revenue_base_amount is null or revenue_base_amount >= 0),
  add constraint job_profitability_snapshots_invoiced_amount_check check (invoiced_amount is null or invoiced_amount >= 0),
  add constraint job_profitability_snapshots_invoiced_base_amount_check check (invoiced_base_amount is null or invoiced_base_amount >= 0);

comment on column app.job_profitability_snapshots.base_currency is
  'ISS-2026-197: the tenant''s own configured base/reporting currency (app.resolve_tenant_locale.default_currency) AT CALCULATION TIME -- never assumed, never hardcoded. Metadata, never masked.';
comment on column app.job_profitability_snapshots.revenue_base_amount is
  'ISS-2026-197: revenue_amount (the quote-time total, revenue_currency) converted into base_currency using the rate effective at revenue_fx_as_of. Null when revenue_fx_status=''rate_unavailable''. Masked alongside revenue_amount.';
comment on column app.job_profitability_snapshots.revenue_fx_rate is
  'ISS-2026-197: the source_currency=revenue_currency -> target_currency=base_currency rate actually applied (1 when revenue_fx_status=''identity''). Masked alongside revenue_amount.';
comment on column app.job_profitability_snapshots.revenue_fx_as_of is
  'ISS-2026-197: the date the revenue conversion rate was resolved for -- the Job Order''s own created_at, the moment revenue_snapshot was pinned. Metadata, never masked.';
comment on column app.job_profitability_snapshots.revenue_fx_status is
  '''identity'' (revenue_currency=base_currency, rate=1, no table lookup needed), ''converted'' (a real cross-currency app.finance_exchange_rates lookup succeeded), or ''rate_unavailable'' (no approved rate covers revenue_fx_as_of -- revenue_base_amount/revenue_fx_rate stay null, never a guess). Metadata, never masked.';
comment on column app.job_profitability_snapshots.invoiced_currency is
  'ISS-2026-197: the actual invoiced/billed total''s own currency, read from app.finance_invoices (status=''issued'') for this Job Order -- the same source app.finance_job_profitability_facts.revenue_basis=''billed'' already reads. Null unless invoiced_status=''available'' (a single currency across every issued invoice). Masked alongside revenue_amount.';
comment on column app.job_profitability_snapshots.invoiced_amount is
  'ISS-2026-197: sum(subtotal_amount) across every issued app.finance_invoices row for this Job Order, in invoiced_currency. Null unless invoiced_status=''available''. Masked alongside revenue_amount.';
comment on column app.job_profitability_snapshots.invoiced_status is
  '''not_yet_invoiced'' (zero issued invoices), ''mixed_currency'' (more than one currency across issued invoices -- summing would be meaningless, so invoiced_currency/invoiced_amount stay null, the same refusal-not-guess discipline the top-level status/blocked_reason pair already uses), or ''available''. Metadata, never masked.';
comment on column app.job_profitability_snapshots.invoiced_base_amount is
  'ISS-2026-197: invoiced_amount converted into base_currency using the rate effective at invoiced_fx_as_of. Null unless invoiced_status=''available'' and invoiced_fx_status=''converted''/''identity''. Masked alongside revenue_amount.';
comment on column app.job_profitability_snapshots.invoiced_fx_rate is
  'ISS-2026-197: the invoiced_currency -> base_currency rate actually applied. Masked alongside revenue_amount.';
comment on column app.job_profitability_snapshots.invoiced_fx_as_of is
  'ISS-2026-197: the date the invoiced-total conversion rate was resolved for -- the latest issue_date (the invoice''s own business date, not the issued_at audit timestamp) across every issued invoice counted into invoiced_amount. Metadata, never masked.';
comment on column app.job_profitability_snapshots.invoiced_fx_status is
  'Same three-value vocabulary as revenue_fx_status, for the invoiced total''s own conversion. Metadata, never masked.';
comment on column app.job_profitability_snapshots.source_invoice_ids is
  'ISS-2026-197: the exact app.finance_invoices ids summed into invoiced_amount -- the same explainability discipline source_cost_version_ids already established for cost. Masked alongside revenue_amount.';

comment on table app.job_profitability_snapshots is
  'OPS-179: one versioned, deterministic operational-margin snapshot per Job Order (is_current exclusive via partial unique index). status=unavailable (with a named blocked_reason) whenever no approved cost exists or currencies do not reconcile -- never a fabricated zero/guessed value. source_cost_version_ids names the exact app.shipment_actual_costs rows summed, the capability''s own explainability seam (already independently readable, no second read path invented). ISS-2026-197: revenue_basis is fixed to ''quoted'' -- the Commercial-accepted, quote-time sell price read verbatim from app.job_orders.revenue_snapshot, an operational estimate, never re-derived or reconciled against actual billing. Contrast: app.finance_job_profitability_facts (FIN-212) is the accounting-truth counterpart, revenue_basis fixed to ''billed'' there -- the actual amount from every issued app.finance_invoices row for the same Job Order. The two figures are deliberately independent, can legitimately differ (e.g. this table''s revenue is the quote''s tax-inclusive total, Finance''s is the pre-tax billed subtotal), and neither is wrong. ISS-2026-197 (2026-09-02): both the quote-time revenue AND the actual invoiced total (read from Finance AR, app.finance_invoices) are now ALSO reported converted into the tenant''s own base_currency, each at the rate effective on its own respective date (revenue_fx_as_of/invoiced_fx_as_of) -- see base_currency/revenue_base_amount/invoiced_base_amount and their sibling columns. The original-currency figures are never discarded or overwritten by the converted ones; both are always on the row.';

-- ISS-2026-197: the single, uniform FX-conversion call site both the quote-time revenue and the
-- actual invoiced total go through -- see this migration's own header for why this exists
-- separately from app.convert_finance_amount (no FIN:View gate; never raises) rather than
-- calling that function directly.
create function app.resolve_operations_fx_conversion(
  p_tenant_id uuid,
  p_amount numeric,
  p_source_currency text,
  p_target_currency text,
  p_as_of timestamptz
)
returns table(converted_amount numeric, fx_rate numeric, fx_status text)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.finance_exchange_rates;
  v_precision integer;
begin
  if p_amount is null or p_source_currency is null or p_target_currency is null then
    return query select null::numeric, null::numeric, null::text;
    return;
  end if;

  -- Identity fast path lives INSIDE this one shared helper -- callers never special-case a
  -- same-currency pair themselves, the same discipline app.convert_finance_amount's own
  -- identity branch already established.
  if p_source_currency = p_target_currency then
    return query select round(p_amount, 2), 1::numeric, 'identity'::text;
    return;
  end if;

  select * into v_rate from app.resolve_finance_exchange_rate(p_tenant_id, 'spot', p_source_currency, p_target_currency, coalesce(p_as_of, now()));
  if not found then
    return query select null::numeric, null::numeric, 'rate_unavailable'::text;
    return;
  end if;

  select coalesce(minor_unit_precision, 2) into v_precision from app.finance_currencies where code = p_target_currency;
  return query select round(p_amount * v_rate.rate, coalesce(v_precision, 2)), v_rate.rate, 'converted'::text;
end;
$$;

comment on function app.resolve_operations_fx_conversion is
  'ISS-2026-197: internal reporting-enrichment helper -- no FIN:View authority gate (called only from inside already-authority-checked Operations functions), never raises (a missing approved rate returns fx_status=''rate_unavailable'' with a null converted_amount, never an exception that would abort the caller''s own successful calculation). Not granted to authenticated/anon -- see the schema-wide REVOKE EXECUTE below.';

-- Rebuilt via CREATE OR REPLACE FUNCTION -- every line through the existing status/blocked_
-- reason/margin branch copied verbatim from the LIVE pg_get_functiondef output (re-verified
-- byte-for-byte identical to 20260901050000, no drift), new conversion logic appended after it,
-- before the one INSERT. language/security definer/search_path restated explicitly (see header).
create or replace function app.calculate_job_profitability(
  p_job_order_id uuid,
  p_recalculation_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_profitability_snapshots
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_existing_current app.job_profitability_snapshots;
  v_revenue_currency text;
  v_revenue_amount numeric(14, 2);
  v_cost_currency_count integer;
  v_cost_currency text;
  v_cost_amount numeric(14, 2);
  v_cost_count integer;
  v_cost_version_ids uuid[];
  v_status text;
  v_blocked_reason text;
  v_margin_amount numeric(14, 2);
  v_margin_percent numeric(9, 4);
  v_new_version integer;
  v_snapshot app.job_profitability_snapshots;
  v_base_currency text;
  v_revenue_fx_as_of timestamptz;
  v_revenue_base_amount numeric(14, 2);
  v_revenue_fx_rate numeric;
  v_revenue_fx_status text;
  v_invoice_currency_count integer;
  v_invoice_count integer;
  v_invoiced_currency text;
  v_invoiced_amount numeric(14, 2);
  v_invoiced_as_of timestamptz;
  v_invoice_ids uuid[];
  v_invoiced_status text;
  v_invoiced_base_amount numeric(14, 2);
  v_invoiced_fx_rate numeric;
  v_invoiced_fx_status text;
begin
  select * into v_job from app.job_orders jo where jo.id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_job_margin(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View margin for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_current from app.job_profitability_snapshots where job_order_id = p_job_order_id and is_current;
  if found and (p_recalculation_reason is null or length(trim(p_recalculation_reason)) = 0) then
    raise exception 'job_profitability_recalculation_reason_required: a reason is required to recalculate an existing profitability snapshot' using errcode = 'check_violation';
  end if;

  v_revenue_currency := v_job.revenue_snapshot ->> 'currency';
  v_revenue_amount := (v_job.revenue_snapshot ->> 'totalAmount')::numeric(14, 2);

  select count(distinct sac.currency), count(*), coalesce(sum(sac.total_amount), 0), coalesce(array_agg(sac.id), '{}'::uuid[])
  into v_cost_currency_count, v_cost_count, v_cost_amount, v_cost_version_ids
  from app.shipment_actual_costs sac
  join app.shipment_orders so on so.id = sac.shipment_order_id
  where so.job_order_id = p_job_order_id and sac.is_current and sac.status = 'approved';

  if v_cost_count = 0 then
    v_status := 'unavailable';
    v_blocked_reason := 'no_approved_cost';
    v_cost_currency := null;
    v_cost_amount := null;
    v_margin_amount := null;
    v_margin_percent := null;
  elsif v_cost_currency_count > 1 or (select sac.currency from app.shipment_actual_costs sac where sac.id = v_cost_version_ids[1]) <> v_revenue_currency then
    v_status := 'unavailable';
    v_blocked_reason := 'mixed_currency';
    v_cost_currency := null;
    v_cost_amount := null;
    v_margin_amount := null;
    v_margin_percent := null;
  else
    v_status := 'calculated';
    v_blocked_reason := null;
    v_cost_currency := v_revenue_currency;
    v_margin_amount := v_revenue_amount - v_cost_amount;
    v_margin_percent := case when v_revenue_amount <> 0 then round((v_margin_amount / v_revenue_amount) * 100, 4) else null end;
  end if;

  -- ISS-2026-197: FX conversion, additive reporting enrichment only -- never gates or alters
  -- the status/blocked_reason/margin computed above. Both the quote-time revenue and the
  -- actual invoiced total are converted into the tenant's own base_currency, each through the
  -- SAME app.resolve_operations_fx_conversion call regardless of whether the source currency
  -- already equals base_currency (uniform, no special-cased branch here).
  select default_currency into v_base_currency from app.resolve_tenant_locale(v_job.tenant_id);

  v_revenue_fx_as_of := v_job.created_at;
  select converted_amount, fx_rate, fx_status
  into v_revenue_base_amount, v_revenue_fx_rate, v_revenue_fx_status
  from app.resolve_operations_fx_conversion(v_job.tenant_id, v_revenue_amount, v_revenue_currency, v_base_currency, v_revenue_fx_as_of);

  -- The actual invoiced/billed total: every ISSUED Finance invoice for this Job Order (the same
  -- app.finance_invoices source app.calculate_finance_job_profitability's own 'billed' basis
  -- reads), summed by subtotal_amount. More than one currency across issued invoices makes the
  -- sum meaningless -- invoiced_status='mixed_currency', invoiced_currency/invoiced_amount left
  -- null, never a cross-currency sum -- the identical refusal-not-guess discipline the
  -- top-level status/blocked_reason pair above already applies to cost.
  select count(distinct fi.currency), count(*), sum(fi.subtotal_amount), max(fi.currency), max(fi.issue_date)::timestamptz, coalesce(array_agg(fi.id), '{}'::uuid[])
  into v_invoice_currency_count, v_invoice_count, v_invoiced_amount, v_invoiced_currency, v_invoiced_as_of, v_invoice_ids
  from app.finance_invoices fi
  where fi.job_order_id = p_job_order_id and fi.status = 'issued';

  if v_invoice_count = 0 then
    v_invoiced_status := 'not_yet_invoiced';
    v_invoiced_currency := null;
    v_invoiced_amount := null;
    v_invoiced_as_of := null;
  elsif v_invoice_currency_count > 1 then
    v_invoiced_status := 'mixed_currency';
    v_invoiced_currency := null;
    v_invoiced_amount := null;
  else
    v_invoiced_status := 'available';
  end if;

  if v_invoiced_status = 'available' then
    select converted_amount, fx_rate, fx_status
    into v_invoiced_base_amount, v_invoiced_fx_rate, v_invoiced_fx_status
    from app.resolve_operations_fx_conversion(v_job.tenant_id, v_invoiced_amount, v_invoiced_currency, v_base_currency, v_invoiced_as_of);
  else
    v_invoiced_base_amount := null;
    v_invoiced_fx_rate := null;
    v_invoiced_fx_status := null;
  end if;

  v_new_version := coalesce(v_existing_current.version_number, 0) + 1;
  if found then
    update app.job_profitability_snapshots set is_current = false where id = v_existing_current.id;
  end if;

  insert into app.job_profitability_snapshots (
    tenant_id, job_order_id, version_number, is_current, status, blocked_reason, revenue_basis,
    revenue_currency, revenue_amount, cost_currency, cost_amount, margin_amount, margin_percent,
    source_cost_version_ids, recalculation_reason, calculated_by_auth_user_id, created_by,
    base_currency, revenue_base_amount, revenue_fx_rate, revenue_fx_as_of, revenue_fx_status,
    invoiced_currency, invoiced_amount, invoiced_status, invoiced_base_amount, invoiced_fx_rate,
    invoiced_fx_as_of, invoiced_fx_status, source_invoice_ids
  ) values (
    v_job.tenant_id, p_job_order_id, v_new_version, true, v_status, v_blocked_reason, 'quoted',
    v_revenue_currency, v_revenue_amount, v_cost_currency, v_cost_amount, v_margin_amount, v_margin_percent,
    v_cost_version_ids, p_recalculation_reason, p_actor_auth_user_id, p_actor_label,
    v_base_currency, v_revenue_base_amount, v_revenue_fx_rate, v_revenue_fx_as_of, v_revenue_fx_status,
    v_invoiced_currency, v_invoiced_amount, v_invoiced_status, v_invoiced_base_amount, v_invoiced_fx_rate,
    v_invoiced_as_of, v_invoiced_fx_status, v_invoice_ids
  )
  returning * into v_snapshot;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_job_profitability',
    'app.job_profitability_snapshots', v_snapshot.id, 'success', p_recalculation_reason, null, to_jsonb(v_snapshot)
  );

  return v_snapshot;
end;
$$;

-- Rebuilt via CREATE OR REPLACE VIEW -- new columns appended after revenue_basis (CREATE OR
-- REPLACE VIEW cannot reorder or insert mid-list). Any new column that is itself a dollar
-- figure, a rate, a job-specific currency code, or an id array masked under the SAME
-- app.has_view_job_margin(...) CASE the original five already use; pure state/timing metadata
-- stays unmasked (see this migration's own header).
create or replace view app.job_profitability_directory
as
select
  jps.id, jps.tenant_id, jps.job_order_id, jps.version_number, jps.is_current, jps.status, jps.blocked_reason,
  case when app.has_view_job_margin(jps.tenant_id) then jps.revenue_currency else null end as revenue_currency,
  case when app.has_view_job_margin(jps.tenant_id) then jps.revenue_amount else null end as revenue_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.cost_currency else null end as cost_currency,
  case when app.has_view_job_margin(jps.tenant_id) then jps.cost_amount else null end as cost_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.margin_amount else null end as margin_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.margin_percent else null end as margin_percent,
  case when app.has_view_job_margin(jps.tenant_id) then jps.source_cost_version_ids else '{}'::uuid[] end as source_cost_version_ids,
  not app.has_view_job_margin(jps.tenant_id) as margin_masked,
  jps.recalculation_reason, jps.calculated_by_auth_user_id, jps.calculated_at, jps.record_version, jps.created_by, jps.created_at, jps.updated_at,
  jps.revenue_basis,
  jps.base_currency,
  case when app.has_view_job_margin(jps.tenant_id) then jps.revenue_base_amount else null end as revenue_base_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.revenue_fx_rate else null end as revenue_fx_rate,
  jps.revenue_fx_as_of,
  jps.revenue_fx_status,
  case when app.has_view_job_margin(jps.tenant_id) then jps.invoiced_currency else null end as invoiced_currency,
  case when app.has_view_job_margin(jps.tenant_id) then jps.invoiced_amount else null end as invoiced_amount,
  jps.invoiced_status,
  case when app.has_view_job_margin(jps.tenant_id) then jps.invoiced_base_amount else null end as invoiced_base_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.invoiced_fx_rate else null end as invoiced_fx_rate,
  jps.invoiced_fx_as_of,
  jps.invoiced_fx_status,
  case when app.has_view_job_margin(jps.tenant_id) then jps.source_invoice_ids else '{}'::uuid[] end as source_invoice_ids
from app.job_profitability_snapshots jps
join app.job_orders jo on jo.id = jps.job_order_id
where app.can_access_record(auth.uid(), jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null);

comment on view app.job_profitability_directory is
  'OPS-179: field-masked projection of app.job_profitability_snapshots -- revenue/cost/margin amounts and source_cost_version_ids nulled/emptied (margin_masked=true) without OPS:View margin. ISS-2026-197: revenue_basis (fixed ''quoted'') is metadata, never a computed figure, so it is exposed unconditionally, even when margin_masked=true or status=unavailable. ISS-2026-197 (2026-09-02): base_currency/revenue_fx_as_of/revenue_fx_status/invoiced_status/invoiced_fx_as_of/invoiced_fx_status are likewise unmasked state/timing metadata; revenue_base_amount/revenue_fx_rate/invoiced_currency/invoiced_amount/invoiced_base_amount/invoiced_fx_rate/source_invoice_ids are masked the same way revenue_currency/revenue_amount already are, since each could let a margin-masked viewer reconstruct a dollar figure they are not entitled to see.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit revoke of PostgreSQL's PUBLIC-execute
-- default, the standing per-migration convention since PLT-118.
revoke execute on all functions in schema app from public;

grant execute on function app.calculate_job_profitability(uuid, text, uuid, text) to authenticated, service_role;
grant select on app.job_profitability_directory to authenticated, service_role;
-- app.resolve_operations_fx_conversion is deliberately NOT granted to authenticated/anon -- it
-- is an internal helper called only from inside app.calculate_job_profitability's own
-- SECURITY DEFINER context (see this migration's own header).
