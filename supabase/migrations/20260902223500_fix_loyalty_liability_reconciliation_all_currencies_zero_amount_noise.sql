-- Same-day correction to 20260902223000 (ISS-2026-134 item 1), found while
-- authoring this same fix's own db-test evidence, before any wrong-shape
-- assertion was written against it -- mirrors this session's own established
-- "same-day correction, caught before evidence was written against the wrong
-- shape" precedent (20260902070500, 20260902073500) exactly.
--
-- THE BUG: app.execute_loyalty_liability_reconciliation_run_all_currencies
-- attempted app.resolve_operations_fx_conversion for EVERY member run's own
-- cashback/discount/voucher line unconditionally -- including a line whose
-- own per-currency total is genuinely 0 (no entitlements of that benefit_type
-- exist in that currency at all, the overwhelmingly common case for any
-- tenant with more than one currency, since most currencies will only ever
-- carry ONE or TWO of the three benefit types). A currency with no approved
-- exchange rate then produced THREE unconverted_lines entries (cashback,
-- discount, voucher) instead of however many were ACTUALLY nonzero -- pure
-- noise for the two that were already, correctly, contributing nothing
-- regardless of rate availability. This is the identical "detection broader
-- than what actually feeds the total" shape ISS-2026-136 item 2 already named
-- and fixed once in this exact function family -- unconverted_lines must stay
-- congruent with what the total actually needed, never wider than it.
--
-- THE FIX: a zero raw total for a line is never sent through the FX helper at
-- all -- it contributes 0 and is never flagged, exactly as a genuinely-zero
-- line should read (there is nothing to disclose a gap ABOUT). Only a real,
-- nonzero total that could not be converted is recorded in unconverted_lines.
-- This does not change any total this fix's own db-test already proved
-- correct (100 USD + 50*1.10 EUR = 155.00) -- only removes noise from lines
-- that were already contributing 0 for an unrelated, correct reason.

create or replace function app.execute_loyalty_liability_reconciliation_run_all_currencies(
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

  select array_agg(distinct x.currency) into v_currencies
  from (
    select e.currency from app.loyalty_benefit_entitlements e where e.tenant_id = p_tenant_id and e.created_at <= v_as_of
    union
    select v_base_currency
  ) x;

  foreach v_currency in array v_currencies loop
    v_run := app.execute_loyalty_liability_reconciliation_run(p_tenant_id, v_as_of, v_currency, p_actor_auth_user_id, p_actor_label, null, p_config_version);
    v_member_run_ids := v_member_run_ids || v_run.id;
    v_member_currencies := v_member_currencies || v_run.currency;

    if v_points_total is null then
      v_points_total := v_run.points_liability_total;
    end if;

    v_reward_total := v_reward_total + v_run.reward_fulfillment_liability_total;

    -- A genuinely zero line contributes 0 regardless of rate availability --
    -- never sent through the FX helper, never flagged in unconverted_lines
    -- (there is nothing to disclose a gap about). Only a real, nonzero total
    -- that could not be converted is ever recorded there.
    if v_run.cashback_liability_total <> 0 then
      select converted_amount, fx_status into v_conv_amount, v_conv_status
      from app.resolve_operations_fx_conversion(p_tenant_id, v_run.cashback_liability_total, v_run.currency, v_base_currency, v_as_of);
      if v_conv_status = 'rate_unavailable' then
        v_unconverted := v_unconverted || jsonb_build_array(jsonb_build_object('line', 'cashback', 'currency', v_run.currency, 'raw_amount', v_run.cashback_liability_total));
      else
        v_cashback_total := v_cashback_total + v_conv_amount;
      end if;
    end if;

    if v_run.discount_liability_total <> 0 then
      select converted_amount, fx_status into v_conv_amount, v_conv_status
      from app.resolve_operations_fx_conversion(p_tenant_id, v_run.discount_liability_total, v_run.currency, v_base_currency, v_as_of);
      if v_conv_status = 'rate_unavailable' then
        v_unconverted := v_unconverted || jsonb_build_array(jsonb_build_object('line', 'discount', 'currency', v_run.currency, 'raw_amount', v_run.discount_liability_total));
      else
        v_discount_total := v_discount_total + v_conv_amount;
      end if;
    end if;

    if v_run.voucher_liability_total <> 0 then
      select converted_amount, fx_status into v_conv_amount, v_conv_status
      from app.resolve_operations_fx_conversion(p_tenant_id, v_run.voucher_liability_total, v_run.currency, v_base_currency, v_as_of);
      if v_conv_status = 'rate_unavailable' then
        v_unconverted := v_unconverted || jsonb_build_array(jsonb_build_object('line', 'voucher', 'currency', v_run.currency, 'raw_amount', v_run.voucher_liability_total));
      else
        v_voucher_total := v_voucher_total + v_conv_amount;
      end if;
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
  'ISS-2026-134 item 1: runs (or idempotently reuses) app.execute_loyalty_liability_reconciliation_run once per currency the tenant has entitlements in, then converts and sums the cashback/discount/voucher lines into the tenant''s own base_currency via app.resolve_operations_fx_conversion (ISS-2026-197). A genuinely zero per-currency line is never sent through the FX helper and never flagged (2026-09-02 same-day fix: detection scope must stay congruent with what the total actually needs, mirroring ISS-2026-136 item 2''s own precedent). points_liability_total is raw/unconverted (taken once, it carries no currency); reward_fulfillment_liability_base_amount is a plain sum (already per-run currency-scoped by ISS-2026-136 item 1). A currency pair with no approved app.finance_exchange_rates row for a genuinely nonzero line is EXCLUDED from the relevant total (never treated as zero) and recorded in unconverted_lines, with status=partial_rate_unavailable. Idempotent on (tenant_id, idempotency_key); each per-currency member run keeps its own independent idempotency and certify workflow, unaffected by this rollup.';

revoke execute on all functions in schema app from public;
grant execute on function app.execute_loyalty_liability_reconciliation_run_all_currencies(uuid, timestamptz, uuid, text, text, integer) to authenticated, service_role;
