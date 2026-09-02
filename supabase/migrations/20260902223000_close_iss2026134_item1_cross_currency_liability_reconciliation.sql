-- ISS-2026-134 item 1 (docs/runtime/KNOWN_ISSUES.md) -- cross-currency reconciliation.
-- The entry's own 2026-09-02 update left this open for a precise reason: "a real,
-- configured currency-conversion source this repository does not have." Checked live
-- before writing anything, per this task's own instruction: ISS-2026-197's own FX-
-- conversion work HAS landed on this branch --
-- 20260902050000_wire_fx_conversion_into_operations_job_profitability.sql built a real,
-- reusable internal helper, app.resolve_operations_fx_conversion(p_tenant_id, p_amount,
-- p_source_currency, p_target_currency, p_as_of), reading the same already-shipped,
-- versioned/dated app.finance_exchange_rates (FIN-193/194) this repository's Finance
-- module already maintains. This migration extends the reconciliation to run across
-- every one of a tenant's currencies in ONE call, using that exact helper -- the entry's
-- own recommended fix, now buildable.
--
-- WHAT "ACROSS ALL CURRENCIES IN ONE CALL" MEANS HERE, PRECISELY:
--
-- It does NOT collapse the per-currency architecture item 1's own original text (and
-- ISS-2026-122's own item 1 sibling reasoning) established as correct -- cashback/
-- discount/voucher totals are still computed per-currency, by the existing, unmodified
-- app.execute_loyalty_liability_reconciliation_run, once per currency the tenant
-- actually has entitlements in. What this migration adds is a CONSOLIDATED, READ-ONLY
-- rollup that (a) drives that existing function once per currency automatically instead
-- of requiring staff to remember to run it once per currency (item 1's own original text
-- names this as the "documented, intended usage pattern" today; this makes it
-- unforgettable rather than merely documented), and (b) converts each currency-scoped
-- entitlement total into the tenant's own base/reporting currency via
-- app.resolve_operations_fx_conversion, then sums the converted amounts into one true
-- total -- something a staff member manually summing raw per-currency figures could
-- never do correctly (summing different currencies' raw numbers is meaningless; only a
-- converted sum is).
--
-- THE TWO LINES THAT ARE NOT CURRENCY-SCOPED AT ALL, HANDLED CORRECTLY RATHER THAN
-- NAIVELY SUMMED:
--
--   points_liability_total carries no currency (design decision 1, ISS-2026-134's own
--   text) -- every per-currency run of the SAME as_of already reports the IDENTICAL raw
--   points figure (it is computed before any currency filter is applied). Summing it
--   across N currency runs would multiply a real number by N for no reason. This
--   migration takes it from exactly one member run and reports it once, explicitly
--   labeled as a raw, unconverted, dimensionless figure -- never pretended to be money.
--
--   reward_fulfillment_liability_total is ALREADY correctly currency-scoped by
--   ISS-2026-136 item 1 (20260801270000) to the tenant's own default currency only --
--   every non-default-currency run already reports exactly 0 for this line. Summing it
--   across every member run is therefore safe and already correct (N-1 runs contribute
--   0), and this migration does exactly that rather than special-casing "the one run
--   that matters."
--
-- NEVER FABRICATE, DISCLOSE THE GAP: a currency pair with no approved
-- app.finance_exchange_rates row returns fx_status=''rate_unavailable'' from the shared
-- helper (never a guessed rate). That line's contribution is EXCLUDED from the
-- consolidated total (never treated as zero, which would silently understate a real
-- liability) and the run is marked status=''partial_rate_unavailable'' with the exact
-- (currency, line, raw amount) triples recorded in unconverted_lines -- mirroring this
-- same migration set's own reward_internal_cost_missing precedent (disclose, never
-- guess) rather than inventing a new suppression rule.
--
-- NOT A CERTIFIABLE ARTIFACT: certification (app.certify_loyalty_liability_
-- reconciliation_run) still happens per currency, on the underlying member runs, exactly
-- as today -- this consolidated row is a rollup convenience for reporting, never a
-- second certification surface. Building one would require its own exception-resolution
-- workflow across every member run's own exceptions, a materially larger, undirected
-- scope this fix does not attempt.

-- ===========================================================================
-- 1. app.loyalty_liability_reconciliation_consolidated_runs.
-- ===========================================================================

create table app.loyalty_liability_reconciliation_consolidated_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  as_of timestamptz not null,
  base_currency text not null,
  member_run_ids uuid[] not null,
  member_currencies text[] not null,
  points_liability_total numeric not null default 0,
  cashback_liability_base_amount numeric not null default 0,
  discount_liability_base_amount numeric not null default 0,
  voucher_liability_base_amount numeric not null default 0,
  reward_fulfillment_liability_base_amount numeric not null default 0,
  unconverted_lines jsonb not null default '[]'::jsonb,
  status text not null default 'complete',
  config_version integer not null default 1,
  idempotency_key text not null,
  executed_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint llrcr_base_currency_check check (base_currency ~ '^[A-Z]{3}$'),
  constraint llrcr_status_check check (status in ('complete', 'partial_rate_unavailable')),
  constraint llrcr_points_check check (points_liability_total >= 0),
  constraint llrcr_cashback_check check (cashback_liability_base_amount >= 0),
  constraint llrcr_discount_check check (discount_liability_base_amount >= 0),
  constraint llrcr_voucher_check check (voucher_liability_base_amount >= 0),
  constraint llrcr_reward_check check (reward_fulfillment_liability_base_amount >= 0),
  constraint llrcr_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.loyalty_liability_reconciliation_consolidated_runs is
  'ISS-2026-134 item 1: a read-only, cross-currency ROLLUP of one app.execute_loyalty_liability_reconciliation_run per currency the tenant has entitlements in (member_run_ids), each entitlement line converted into base_currency via app.resolve_operations_fx_conversion (ISS-2026-197) and summed. points_liability_total is raw/dimensionless, taken once (never summed -- it carries no currency, design decision 1 of 20260801250000). reward_fulfillment_liability_base_amount is already correctly currency-scoped per-run (ISS-2026-136 item 1) so a plain sum across member runs is correct. status=partial_rate_unavailable (with the excluded (currency, line, raw amount) triples in unconverted_lines) when any conversion lacked an approved app.finance_exchange_rates row -- that line is EXCLUDED from the total, never treated as zero. NOT a certifiable artifact -- certification stays per-currency on the member runs themselves.';

create index llrcr_tenant_updated_id_idx on app.loyalty_liability_reconciliation_consolidated_runs (tenant_id, updated_at desc, id desc);
create index llrcr_tenant_asof_idx on app.loyalty_liability_reconciliation_consolidated_runs (tenant_id, as_of desc);

create function app.touch_loyalty_liability_reconciliation_consolidated_run_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_liability_reconciliation_consolidated_runs_touch_row
  before update on app.loyalty_liability_reconciliation_consolidated_runs
  for each row
  execute function app.touch_loyalty_liability_reconciliation_consolidated_run_row();

-- ===========================================================================
-- 2. app.execute_loyalty_liability_reconciliation_run_all_currencies.
-- ===========================================================================

create function app.execute_loyalty_liability_reconciliation_run_all_currencies(
  p_tenant_id uuid,
  p_as_of timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_idempotency_key text default null,
  p_config_version integer default 1
)
returns app.loyalty_liability_reconciliation_consolidated_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, clock_timestamp());
  v_idem text;
  v_existing app.loyalty_liability_reconciliation_consolidated_runs;
  v_consolidated app.loyalty_liability_reconciliation_consolidated_runs;
  v_base_currency text;
  v_currencies text[];
  v_currency text;
  v_run app.loyalty_liability_reconciliation_runs;
  v_member_run_ids uuid[] := '{}';
  v_member_currencies text[] := '{}';
  v_points_total numeric;
  v_reward_total numeric := 0;
  v_cashback_total numeric := 0;
  v_discount_total numeric := 0;
  v_voucher_total numeric := 0;
  v_conv_amount numeric;
  v_conv_status text;
  v_unconverted jsonb := '[]'::jsonb;
  v_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_idem := coalesce(nullif(trim(p_idempotency_key), ''), 'liability-recon-all:' || to_char(v_as_of, 'YYYY-MM-DD'));

  select * into v_existing from app.loyalty_liability_reconciliation_consolidated_runs where tenant_id = p_tenant_id and idempotency_key = v_idem;
  if found then
    return v_existing;
  end if;

  select default_currency into v_base_currency from app.resolve_tenant_locale(p_tenant_id);

  -- Currencies in scope: every distinct entitlement currency as of v_as_of, plus the
  -- tenant's own base currency (guarantees points/reward_fulfillment coverage even for
  -- a tenant with zero entitlements yet).
  select array_agg(distinct x.currency) into v_currencies
  from (
    select e.currency from app.loyalty_benefit_entitlements e where e.tenant_id = p_tenant_id and e.created_at <= v_as_of
    union
    select v_base_currency
  ) x;

  foreach v_currency in array v_currencies loop
    -- p_idempotency_key deliberately null: each per-currency run gets ITS OWN
    -- auto-derived key (design decision 10 of 20260801250000), so a staff member who
    -- already ran this currency manually today has that same run reused here, never
    -- duplicated.
    v_run := app.execute_loyalty_liability_reconciliation_run(p_tenant_id, v_as_of, v_currency, p_actor_auth_user_id, p_actor_label, null, p_config_version);
    v_member_run_ids := v_member_run_ids || v_run.id;
    v_member_currencies := v_member_currencies || v_run.currency;

    if v_points_total is null then
      -- Raw and dimensionless (design decision 1) -- identical across every member run
      -- of this same as_of, since it is computed before any currency filter. Taken
      -- once, never summed, never converted.
      v_points_total := v_run.points_liability_total;
    end if;

    -- Already correctly currency-scoped to base_currency only (ISS-2026-136 item 1) --
    -- every non-default-currency run already reports 0 here, so a plain sum is correct.
    v_reward_total := v_reward_total + v_run.reward_fulfillment_liability_total;

    select converted_amount, fx_status into v_conv_amount, v_conv_status
    from app.resolve_operations_fx_conversion(p_tenant_id, v_run.cashback_liability_total, v_run.currency, v_base_currency, v_as_of);
    if v_conv_status = 'rate_unavailable' then
      v_unconverted := v_unconverted || jsonb_build_array(jsonb_build_object('line', 'cashback', 'currency', v_run.currency, 'raw_amount', v_run.cashback_liability_total));
    else
      v_cashback_total := v_cashback_total + v_conv_amount;
    end if;

    select converted_amount, fx_status into v_conv_amount, v_conv_status
    from app.resolve_operations_fx_conversion(p_tenant_id, v_run.discount_liability_total, v_run.currency, v_base_currency, v_as_of);
    if v_conv_status = 'rate_unavailable' then
      v_unconverted := v_unconverted || jsonb_build_array(jsonb_build_object('line', 'discount', 'currency', v_run.currency, 'raw_amount', v_run.discount_liability_total));
    else
      v_discount_total := v_discount_total + v_conv_amount;
    end if;

    select converted_amount, fx_status into v_conv_amount, v_conv_status
    from app.resolve_operations_fx_conversion(p_tenant_id, v_run.voucher_liability_total, v_run.currency, v_base_currency, v_as_of);
    if v_conv_status = 'rate_unavailable' then
      v_unconverted := v_unconverted || jsonb_build_array(jsonb_build_object('line', 'voucher', 'currency', v_run.currency, 'raw_amount', v_run.voucher_liability_total));
    else
      v_voucher_total := v_voucher_total + v_conv_amount;
    end if;
  end loop;

  v_status := case when jsonb_array_length(v_unconverted) > 0 then 'partial_rate_unavailable' else 'complete' end;

  begin
    insert into app.loyalty_liability_reconciliation_consolidated_runs (
      tenant_id, as_of, base_currency, member_run_ids, member_currencies,
      points_liability_total, cashback_liability_base_amount, discount_liability_base_amount,
      voucher_liability_base_amount, reward_fulfillment_liability_base_amount,
      unconverted_lines, status, config_version, idempotency_key, executed_by
    ) values (
      p_tenant_id, v_as_of, v_base_currency, v_member_run_ids, v_member_currencies,
      coalesce(v_points_total, 0), v_cashback_total, v_discount_total,
      v_voucher_total, v_reward_total,
      v_unconverted, v_status, coalesce(p_config_version, 1), v_idem, p_actor_label
    )
    returning * into v_consolidated;
  exception
    when unique_violation then
      select * into v_consolidated from app.loyalty_liability_reconciliation_consolidated_runs where tenant_id = p_tenant_id and idempotency_key = v_idem;
      if not found then
        raise;
      end if;
      return v_consolidated;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_loyalty_liability_reconciliation_run_all_currencies',
    'app.loyalty_liability_reconciliation_consolidated_runs', v_consolidated.id, 'success', null, null,
    jsonb_build_object('base_currency', v_base_currency, 'member_currencies', v_member_currencies, 'status', v_status, 'as_of', v_as_of)
  );

  return v_consolidated;
end;
$$;

comment on function app.execute_loyalty_liability_reconciliation_run_all_currencies is
  'ISS-2026-134 item 1: runs (or idempotently reuses) app.execute_loyalty_liability_reconciliation_run once per currency the tenant has entitlements in, then converts and sums the cashback/discount/voucher lines into the tenant''s own base_currency via app.resolve_operations_fx_conversion (ISS-2026-197). points_liability_total is raw/unconverted (taken once, it carries no currency); reward_fulfillment_liability_base_amount is a plain sum (already per-run currency-scoped by ISS-2026-136 item 1). A currency pair with no approved app.finance_exchange_rates row is EXCLUDED from the relevant total (never treated as zero) and recorded in unconverted_lines, with status=partial_rate_unavailable. Idempotent on (tenant_id, idempotency_key); each per-currency member run keeps its own independent idempotency and certify workflow, unaffected by this rollup.';

-- ===========================================================================
-- 3. Read RPCs -- LYL:View.
-- ===========================================================================

create function app.get_loyalty_liability_reconciliation_consolidated_run(p_tenant_id uuid, p_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_liability_reconciliation_consolidated_runs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.loyalty_liability_reconciliation_consolidated_runs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.loyalty_liability_reconciliation_consolidated_runs where id = p_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_liability_reconciliation_consolidated_run_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  return v_row;
end;
$$;

create function app.list_loyalty_liability_reconciliation_consolidated_runs(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_liability_reconciliation_consolidated_runs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.*
  from app.loyalty_liability_reconciliation_consolidated_runs r
  where r.tenant_id = p_tenant_id
    and (p_before_created_at is null or (r.created_at, r.id) < (p_before_created_at, p_before_id))
  order by r.created_at desc, r.id desc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 4. Grants + public.* wrappers (RGL-394 Option 2).
-- ===========================================================================

grant select, insert, update on app.loyalty_liability_reconciliation_consolidated_runs to service_role;
grant execute on function app.touch_loyalty_liability_reconciliation_consolidated_run_row() to service_role;

revoke execute on all functions in schema app from public;

grant execute on function app.execute_loyalty_liability_reconciliation_run_all_currencies(uuid, timestamptz, uuid, text, text, integer) to authenticated, service_role;
grant execute on function app.get_loyalty_liability_reconciliation_consolidated_run(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_liability_reconciliation_consolidated_runs(uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;

create function public.execute_loyalty_liability_reconciliation_run_all_currencies(
  p_tenant_id uuid, p_as_of timestamptz, p_actor_auth_user_id uuid, p_actor_label text,
  p_idempotency_key text default null, p_config_version integer default 1
)
returns app.loyalty_liability_reconciliation_consolidated_runs
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.execute_loyalty_liability_reconciliation_run_all_currencies(p_tenant_id, p_as_of, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_config_version);
$wrap$;

comment on function public.execute_loyalty_liability_reconciliation_run_all_currencies(uuid, timestamptz, uuid, text, text, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.execute_loyalty_liability_reconciliation_run_all_currencies, never a reimplementation.';

revoke execute on function public.execute_loyalty_liability_reconciliation_run_all_currencies(uuid, timestamptz, uuid, text, text, integer) from anon, authenticated, service_role, public;
grant execute on function public.execute_loyalty_liability_reconciliation_run_all_currencies(uuid, timestamptz, uuid, text, text, integer) to authenticated, service_role;

create function public.get_loyalty_liability_reconciliation_consolidated_run(p_tenant_id uuid, p_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_liability_reconciliation_consolidated_runs
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.get_loyalty_liability_reconciliation_consolidated_run(p_tenant_id, p_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_loyalty_liability_reconciliation_consolidated_run(uuid, uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.get_loyalty_liability_reconciliation_consolidated_run, never a reimplementation.';

revoke execute on function public.get_loyalty_liability_reconciliation_consolidated_run(uuid, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_loyalty_liability_reconciliation_consolidated_run(uuid, uuid, uuid) to authenticated, service_role;

create function public.list_loyalty_liability_reconciliation_consolidated_runs(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_before_created_at timestamptz default null,
  p_before_id uuid default null, p_limit integer default 50
)
returns setof app.loyalty_liability_reconciliation_consolidated_runs
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_loyalty_liability_reconciliation_consolidated_runs(p_tenant_id, p_actor_auth_user_id, p_before_created_at, p_before_id, p_limit);
$wrap$;

comment on function public.list_loyalty_liability_reconciliation_consolidated_runs(uuid, uuid, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_loyalty_liability_reconciliation_consolidated_runs, never a reimplementation.';

revoke execute on function public.list_loyalty_liability_reconciliation_consolidated_runs(uuid, uuid, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_loyalty_liability_reconciliation_consolidated_runs(uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
