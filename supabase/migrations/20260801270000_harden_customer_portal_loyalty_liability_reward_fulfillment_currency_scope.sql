-- CPL-324 (CG-S13-CPL-026, Prompt 324, Customer Portal and Loyalty
-- Integrated Verification) -- bounded defect repair, closing ISS-2026-136
-- item 1 before this checkpoint may advance to CPL-325, per the source
-- prompt's own literal acceptance criterion ("No unresolved critical/high
-- blocker may advance").
--
-- ===========================================================================
-- Root cause, independently re-derived from direct code reads (not accepted
-- from any lens report on its word) -- see docs/runtime/KNOWN_ISSUES.md
-- ISS-2026-136 for the full live-reproduced finding.
-- ===========================================================================
--
-- app.execute_loyalty_liability_reconciliation_run's own reward-fulfillment
-- exposure loop (20260801250000_create_customer_portal_loyalty_liability_
-- reconciliation_analytics.sql, originally lines 592-624) carried no
-- p_currency predicate anywhere, unlike the cashback/discount/voucher loop
-- immediately above it (`and v_entitlement.currency = p_currency`, line 126
-- of that same function). Confirmed live: an identical tenant/instant, one
-- `fulfilling` physical_item redemption (internal_cost 75), produced
-- reward_fulfillment_liability_total = 75 on BOTH a USD-scoped run and an
-- IDR-scoped run of the same tenant -- both certified cleanly with zero
-- exceptions. That migration's own design decision 6 documents running
-- reconciliation once per currency for full multi-currency coverage; a
-- staff member following that exact documented workflow and summing the
-- four other lines' own per-currency totals gets a correct number, but
-- doing the same for reward_fulfillment_liability_total silently overcounts
-- it once per additional currency the tenant has an open `fulfilling`
-- redemption in, with no exception ever raised.
--
-- app.loyalty_rewards has no currency column of its own -- design decision
-- 1 of the original migration already discloses this as a "tenant-default-
-- currency assumption" for internal_cost. That assumption already has a
-- real, established resolution primitive elsewhere in this exact batch:
-- app.resolve_tenant_locale(p_tenant_id) (PLT, 20260717112000) is this
-- repository's own real tenant-currency-preference primitive, and CPL-321's
-- own app.issue_loyalty_benefit_entitlement already resolves an analogous
-- "no explicit currency column" value the identical way (its own design
-- decision 4: "currency = the tenant's own resolved default_currency"). This
-- fix reuses that SAME already-accepted convention rather than inventing a
-- new one or adding a schema column (which this bounded-repair checkpoint's
-- own "no planned feature schema" charter forbids): every internal_cost
-- value on app.loyalty_rewards is treated as denominated in the tenant's own
-- resolved default_currency, and the reward-fulfillment loop now only
-- accumulates into a run whose own p_currency matches that value -- exactly
-- mirroring the entitlement loop's own `and v_entitlement.currency =
-- p_currency` shape one line above it.
--
-- Item 2 of ISS-2026-136 (tenant-wide, not currency-scoped, mismatch
-- DETECTION for entitlements/redemptions) is a separate, lower-severity,
-- disclosed-as-acceptable operational-noise characteristic -- not touched by
-- this fix, left exactly as documented in ISS-2026-136 item 2.
--
-- ===========================================================================
-- Fix: `CREATE OR REPLACE FUNCTION` against app.execute_loyalty_liability_
-- reconciliation_run only. Every other line is byte-identical to the
-- already-applied body -- no other predicate, column, ordering, side
-- effect, or exception type is touched, and the already-applied
-- 20260801250000 migration file is never edited (mirrors this repository's
-- own established `harden_*.sql` pattern, e.g. `20260801160000`,
-- `20260801260000`). No new GRANT/REVOKE needed -- `CREATE OR REPLACE` on an
-- identical signature preserves the existing ACL.
--
-- Regression coverage: a new two-currency regression block is added to
-- scripts/db-tests/customer-loyalty-liability-reconciliation.sql, live-
-- reproducing ISS-2026-136 item 1's own exact scenario (one `fulfilling`
-- physical_item redemption, a USD-scoped run and an IDR-scoped run of the
-- same tenant) and asserting the fix: only the run matching the tenant's own
-- resolved default_currency reports the reward-fulfillment exposure; the
-- other reports zero for that line.
-- ===========================================================================

create or replace function app.execute_loyalty_liability_reconciliation_run(
  p_tenant_id uuid,
  p_as_of timestamptz,
  p_currency text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_idempotency_key text default null,
  p_config_version integer default 1
)
returns app.loyalty_liability_reconciliation_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, clock_timestamp());
  v_idem text;
  v_existing app.loyalty_liability_reconciliation_runs;
  v_run app.loyalty_liability_reconciliation_runs;
  v_points_total numeric := 0;
  v_cashback_total numeric := 0;
  v_discount_total numeric := 0;
  v_voucher_total numeric := 0;
  v_reward_total numeric := 0;
  v_account record;
  v_cached_available numeric;
  v_entitlement record;
  v_derived_status text;
  v_redemption record;
  v_derived_redemption_status text;
  v_point_mismatches jsonb[] := '{}';
  v_entitlement_mismatches jsonb[] := '{}';
  v_redemption_mismatches jsonb[] := '{}';
  v_mismatch jsonb;
  v_exception_count integer;
  v_tenant_default_currency text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a valid ISO currency code' , p_currency using errcode = 'check_violation';
  end if;

  v_idem := coalesce(nullif(trim(p_idempotency_key), ''), 'liability-recon:' || to_char(v_as_of, 'YYYY-MM-DD') || ':' || p_currency);

  -- Idempotent short-circuit AFTER the authority check (mandatory pattern).
  -- Never recomputes on a replay -- a run's own totals/exceptions are
  -- exactly what they were the moment they were first computed.
  select * into v_existing from app.loyalty_liability_reconciliation_runs where tenant_id = p_tenant_id and idempotency_key = v_idem;
  if found then
    return v_existing;
  end if;

  -- The reward's own internal_cost has no currency column of its own
  -- (design decision 1) -- resolved once here as the tenant's own currency
  -- preference, mirroring app.issue_loyalty_benefit_entitlement's (CPL-321)
  -- own identical resolution for the same class of value (this migration's
  -- own header fix note above).
  select default_currency into v_tenant_default_currency from app.resolve_tenant_locale(p_tenant_id);

  -- =========================================================================
  -- Points: live per-account recomputation from the raw ledger (design
  -- decision 3), cross-checked against the cached derived balance for the
  -- exactness evidence unit (design decisions 7/8). greatest(...,0) is a
  -- defensive clamp only -- the negative-balance guard on app.post_loyalty_
  -- point_ledger_entry already structurally prevents a negative live sum in
  -- a healthy system; it should never actually engage for a legitimate
  -- account.
  -- =========================================================================
  for v_account in
    select le.loyalty_account_id as acct_id, sum(le.amount) as live_available
    from app.loyalty_point_ledger_entries le
    where le.tenant_id = p_tenant_id
    group by le.loyalty_account_id
  loop
    v_points_total := v_points_total + greatest(v_account.live_available, 0);

    select pb.available into v_cached_available
      from app.loyalty_point_balances pb
      where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_account.acct_id;

    if not found then
      v_point_mismatches := v_point_mismatches || jsonb_build_object(
        'loyaltyAccountId', v_account.acct_id, 'expectedAvailable', v_account.live_available, 'actualAvailable', null, 'note', 'no cached app.loyalty_point_balances row found for an account with ledger activity'
      );
    elsif v_cached_available is distinct from v_account.live_available then
      v_point_mismatches := v_point_mismatches || jsonb_build_object(
        'loyaltyAccountId', v_account.acct_id, 'expectedAvailable', v_account.live_available, 'actualAvailable', v_cached_available
      );
    end if;
  end loop;

  -- =========================================================================
  -- Cashback/discount/voucher: current status independently re-derived
  -- purely from the append-only event log (design decision 7) -- the
  -- entitlements row's own `status` column is read ONLY as the exactness
  -- comparison target, never trusted for the liability total itself.
  -- =========================================================================
  for v_entitlement in
    select
      e.id as ent_id, e.benefit_type, e.currency, e.value_amount, e.status as cached_status,
      (
        select ev.event_type from app.loyalty_benefit_entitlement_events ev
        where ev.entitlement_id = e.id
        order by ev.created_at desc, ev.id desc
        limit 1
      ) as latest_event_type
    from app.loyalty_benefit_entitlements e
    where e.tenant_id = p_tenant_id
  loop
    v_derived_status := case v_entitlement.latest_event_type
      when 'issued' then 'issued'
      when 'redeemed' then 'redeemed'
      when 'reversed' then 'reversed'
      when 'expired' then 'expired'
      when 'held' then 'held'
      when 'released' then 'issued'
      else null
    end;

    if v_derived_status is distinct from v_entitlement.cached_status then
      v_entitlement_mismatches := v_entitlement_mismatches || jsonb_build_object(
        'entitlementId', v_entitlement.ent_id, 'expectedStatus', v_derived_status, 'actualStatus', v_entitlement.cached_status, 'latestEventType', v_entitlement.latest_event_type
      );
    end if;

    if v_derived_status in ('issued', 'held') and v_entitlement.currency = p_currency then
      if v_entitlement.benefit_type = 'cashback' then
        v_cashback_total := v_cashback_total + v_entitlement.value_amount;
      elsif v_entitlement.benefit_type = 'discount' then
        v_discount_total := v_discount_total + v_entitlement.value_amount;
      elsif v_entitlement.benefit_type = 'voucher' then
        v_voucher_total := v_voucher_total + v_entitlement.value_amount;
      end if;
    end if;
  end loop;

  -- =========================================================================
  -- Reward fulfillment exposure (design decision 5): physical_item/
  -- service_credit redemptions committed but not yet delivered, valued at
  -- the reward's own staff-only internal_cost (tenant-default-currency
  -- assumption, design decision 1). A null internal_cost contributes 0
  -- (disclosed limitation, ISS-2026-134). Tier C review fix (Batch 5
  -- close): current status is independently RE-DERIVED from the append-
  -- only app.loyalty_redemption_events log (latest event_type -> status),
  -- mirroring design decision 7's own entitlement-status derivation
  -- exactly. CPL-324 hardening fix (this migration): the internal_cost
  -- assumption is now genuinely currency-SCOPED -- only accumulated when
  -- p_currency matches the tenant's own resolved default_currency
  -- (v_tenant_default_currency, resolved once above) -- closing ISS-2026-136
  -- item 1 (a currency-mismatched run previously double-counted this line).
  -- =========================================================================
  for v_redemption in
    select
      rd.id as rdm_id, rd.status as cached_status, coalesce(r.internal_cost, 0) as internal_cost,
      (
        select ev.event_type from app.loyalty_redemption_events ev
        where ev.redemption_id = rd.id
        order by ev.created_at desc, ev.id desc
        limit 1
      ) as latest_event_type
    from app.loyalty_redemptions rd
    join app.loyalty_rewards r on r.id = rd.reward_id
    where rd.tenant_id = p_tenant_id and rd.reward_type in ('physical_item', 'service_credit')
  loop
    v_derived_redemption_status := case v_redemption.latest_event_type
      when 'submitted' then 'pending_approval'
      when 'approved' then 'fulfilling'
      when 'rejected' then 'rejected'
      when 'cancelled' then 'cancelled'
      when 'fulfilled' then 'fulfilled'
      when 'fulfillment_failed' then 'failed'
      else null
    end;

    if v_derived_redemption_status is distinct from v_redemption.cached_status then
      v_redemption_mismatches := v_redemption_mismatches || jsonb_build_object(
        'redemptionId', v_redemption.rdm_id, 'expectedStatus', v_derived_redemption_status, 'actualStatus', v_redemption.cached_status, 'latestEventType', v_redemption.latest_event_type
      );
    end if;

    if v_derived_redemption_status = 'fulfilling' and p_currency = v_tenant_default_currency then
      v_reward_total := v_reward_total + v_redemption.internal_cost;
    end if;
  end loop;

  v_exception_count := coalesce(array_length(v_point_mismatches, 1), 0) + coalesce(array_length(v_entitlement_mismatches, 1), 0) + coalesce(array_length(v_redemption_mismatches, 1), 0);

  -- The run row's own INSERT establishes the idempotency claim FIRST -- a
  -- genuine concurrent duplicate-idempotency-key race is caught by the real
  -- exception handler below, mirroring every other posting-shaped RPC in
  -- this domain (design decision 9).
  begin
    insert into app.loyalty_liability_reconciliation_runs (
      tenant_id, as_of, currency, status,
      points_liability_total, cashback_liability_total, discount_liability_total, voucher_liability_total, reward_fulfillment_liability_total,
      config_version, idempotency_key, executed_by
    ) values (
      p_tenant_id, v_as_of, p_currency, case when v_exception_count > 0 then 'exceptions_pending' else 'open' end,
      v_points_total, v_cashback_total, v_discount_total, v_voucher_total, v_reward_total,
      coalesce(p_config_version, 1), v_idem, p_actor_label
    )
    returning * into v_run;
  exception
    when unique_violation then
      select * into v_run from app.loyalty_liability_reconciliation_runs where tenant_id = p_tenant_id and idempotency_key = v_idem;
      if not found then
        raise;
      end if;
      return v_run;
  end;

  foreach v_mismatch in array v_point_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'point_balance_derivation_mismatch', v_mismatch);
  end loop;

  foreach v_mismatch in array v_entitlement_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'entitlement_state_derivation_mismatch', v_mismatch);
  end loop;

  foreach v_mismatch in array v_redemption_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'redemption_liability_status_mismatch', v_mismatch);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_loyalty_liability_reconciliation_run',
    'app.loyalty_liability_reconciliation_runs', v_run.id, 'success', null, null,
    jsonb_build_object('currency', p_currency, 'exception_count', v_exception_count, 'status', v_run.status)
  );

  return v_run;
end;
$$;

comment on function app.execute_loyalty_liability_reconciliation_run is
  'CPL-323, hardened at CPL-324 (ISS-2026-136 item 1 fix): one deterministic, reproducible Loyalty-liability reconciliation run, as of a recorded point in time. points_liability_total is a RAW POINTS total (no fabricated conversion rate); cashback/discount/voucher/reward_fulfillment totals are all currency-scoped to this run''s own currency column -- reward_fulfillment_liability_total now compares p_currency against the tenant''s own resolved default_currency (app.resolve_tenant_locale), mirroring app.issue_loyalty_benefit_entitlement''s (CPL-321) own identical no-currency-column resolution, closing the double-count a currency-mismatched run previously produced with zero exception. status=certified requires zero open exceptions on this run -- certification never silently forces equality.';
