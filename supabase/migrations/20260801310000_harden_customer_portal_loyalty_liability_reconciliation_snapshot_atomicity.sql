-- Phase 8 Customer Portal and Loyalty (CPL-325, CG-S13-CPL-027, Prompt 325,
-- "Customer Portal and Loyalty Privacy Integrity Hardening") -- fixes a
-- live-reproduced, deterministic (lock-gated) concurrency defect in
-- app.execute_loyalty_liability_reconciliation_run: its own three source
-- loops (points/entitlements/reward-fulfillment,
-- supabase/migrations/20260801270000_harden_customer_portal_loyalty_
-- liability_reward_fulfillment_currency_scope.sql, originally lines
-- 148-263) are three SEPARATE top-level SQL statements, each taking its OWN
-- fresh MVCC snapshot under PostgreSQL's default READ COMMITTED isolation --
-- contradicting this function's own documented invariant ("a run reflects a
-- normal MVCC-consistent snapshot," 20260801250000 line 678, unchanged by
-- this fix). A concurrent commit landing between two of the three loops
-- (e.g. a redemption reversal crediting points back mid-run) can be
-- captured by one loop's own snapshot but missed by another's, producing a
-- run whose own combined total does not correspond to any single real
-- instant, with zero exception raised.
--
-- Live-reproduced this checkpoint via a deterministic lock-gated
-- interleaving (a third "gate" session holding `LOCK TABLE app.loyalty_
-- benefit_entitlements IN ACCESS EXCLUSIVE MODE`, released only after a
-- `mark_loyalty_redemption_fulfillment_failed` reversal commits strictly
-- between the points loop and the redemption loop): the run's own reported
-- combined total (points + reward) was 50 LOWER than either a fully-before
-- or fully-after consistent snapshot of the same instant (both independently
-- totaling 1317; the torn run reported 1267), with the run's own
-- `exceptions_pending` status driven only by two unrelated, pre-existing
-- fixture artifacts -- zero exception was raised for the actual torn
-- condition itself.
--
-- Business impact: reporting-integrity only. This does NOT corrupt any
-- underlying ledger/balance/entitlement/redemption row (a re-run recomputes
-- fresh and is correct again) and does not enable balance manipulation,
-- double-spend, or a cross-tenant/cross-account leak (the escalation-to-
-- Critical bar this checkpoint's own charter names) -- rated High, matching
-- this repository's own precedent for the sibling currency-scope defect
-- (ISS-2026-136 item 1, CPL-324/20260801270000), for the identical reason:
-- no automated Finance-side liability handoff consumes this number yet
-- (ISS-2026-129 item 5, independently reconfirmed still accurate) -- today's
-- blast radius is a manual staff reporting step, not a live financial
-- commitment.
--
-- Fix (bounded, additive, `CREATE OR REPLACE FUNCTION` against an identical
-- signature -- the already-applied 20260801250000/20260801270000 files are
-- never edited): the three source reads (plus the point-balance cache
-- comparison, itself previously a FOURTH separately-snapshotted statement
-- nested inside the points loop) are now captured via ONE single top-level
-- SQL statement -- three independent `jsonb_agg()` scalar-subquery
-- expressions in one SELECT's own target list, each drawing from its own
-- CTE. Under READ COMMITTED, a single statement takes exactly one MVCC
-- snapshot for its own execution, including every subquery nested inside
-- it (correlated or not) -- so all three domains, plus the point-balance
-- cache lookup, are now read from the SAME consistent instant. Every loop
-- BODY below (mismatch detection, total accumulation) is byte-identical to
-- the prior logic -- only the data SOURCE changed, from a live-table query
-- to an already-snapshotted `jsonb_to_recordset()` projection of the exact
-- same rows/columns the original three queries selected. No new predicate,
-- no new mismatch/total rule, nothing else touched. No new GRANT/REVOKE
-- needed -- `CREATE OR REPLACE FUNCTION` on an identical signature preserves
-- the existing ACL.
--
-- Why NOT `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ`: PostgreSQL
-- rejects that statement once any query has already executed in the current
-- transaction (`SET TRANSACTION ISOLATION LEVEL must be called before any
-- query`) -- and this function's OWN earlier statements (`app.assert_actor_
-- is_session_identity`, `app.evaluate_permission`, the idempotency
-- short-circuit SELECT) already run first, inside the SAME transaction, by
-- the time the three source loops are reached. Elevating the isolation
-- level would require the CALLER to open the transaction explicitly before
-- invoking this RPC -- a client/service-layer change touching every caller
-- of this function, well outside a single bounded, additive migration.
-- Restructuring the source reads into one statement achieves the identical
-- guarantee without touching any caller.
--
-- Why NOT a `LOCK ... IN ACCESS EXCLUSIVE MODE` (or a real row lock) on the
-- source tables: this function is explicitly, deliberately unlocked against
-- concurrent ledger posting (design decision 3's own comment, "no row-level
-- lock is taken against any source-domain table during recomputation,
-- mirrors FIN-209's own unlocked, snapshot-consistent read") -- a hard
-- concurrency barrier was never this function's own contract; only the
-- SNAPSHOT consistency across its own three reads was ever the documented
-- guarantee, and that is exactly what this fix restores.

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
  v_points_json jsonb;
  v_entitlement_json jsonb;
  v_redemption_json jsonb;
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
  -- own identical resolution for the same class of value.
  select default_currency into v_tenant_default_currency from app.resolve_tenant_locale(p_tenant_id);

  -- =========================================================================
  -- CPL-325 hardening fix (single-snapshot atomicity -- see this migration's
  -- own header). ONE statement, three independent jsonb_agg() branches (one
  -- per source domain), each an exact row-for-row/column-for-column
  -- projection of what the prior three separate queries selected -- the
  -- points branch additionally inlines the point-balance cache lookup
  -- (previously a fourth, separately-snapshotted statement nested inside
  -- the points loop) as a correlated subquery in the SAME statement.
  -- app.loyalty_point_balances.available is a NOT NULL generated column
  -- (20260801200000 line 389) -- a null from that subquery unambiguously
  -- means "no cached row found," matching the original `if not found`
  -- branch exactly, never a real found-but-null value.
  -- =========================================================================
  select
    (select coalesce(jsonb_agg(jsonb_build_object(
        'acct_id', ps.acct_id, 'live_available', ps.live_available,
        'cached_available', (select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = ps.acct_id)
      )), '[]'::jsonb)
     from (
       select le.loyalty_account_id as acct_id, sum(le.amount) as live_available
       from app.loyalty_point_ledger_entries le
       where le.tenant_id = p_tenant_id
       group by le.loyalty_account_id
     ) ps),
    (select coalesce(jsonb_agg(jsonb_build_object(
        'ent_id', e.id, 'benefit_type', e.benefit_type, 'currency', e.currency, 'value_amount', e.value_amount, 'cached_status', e.status,
        'latest_event_type', (select ev.event_type from app.loyalty_benefit_entitlement_events ev where ev.entitlement_id = e.id order by ev.created_at desc, ev.id desc limit 1)
      )), '[]'::jsonb)
     from app.loyalty_benefit_entitlements e
     where e.tenant_id = p_tenant_id),
    (select coalesce(jsonb_agg(jsonb_build_object(
        'rdm_id', rd.id, 'cached_status', rd.status, 'internal_cost', coalesce(r.internal_cost, 0),
        'latest_event_type', (select ev.event_type from app.loyalty_redemption_events ev where ev.redemption_id = rd.id order by ev.created_at desc, ev.id desc limit 1)
      )), '[]'::jsonb)
     from app.loyalty_redemptions rd
     join app.loyalty_rewards r on r.id = rd.reward_id
     where rd.tenant_id = p_tenant_id and rd.reward_type in ('physical_item', 'service_credit'))
  into v_points_json, v_entitlement_json, v_redemption_json;

  -- =========================================================================
  -- Points: live per-account recomputation from the raw ledger (design
  -- decision 3), cross-checked against the cached derived balance for the
  -- exactness evidence unit (design decisions 7/8). greatest(...,0) is a
  -- defensive clamp only. Loop body byte-identical to the prior logic --
  -- sourced from the single-snapshot projection above, not a live query.
  -- =========================================================================
  for v_account in select * from jsonb_to_recordset(v_points_json) as x(acct_id uuid, live_available numeric, cached_available numeric)
  loop
    v_points_total := v_points_total + greatest(v_account.live_available, 0);

    if v_account.cached_available is null then
      v_point_mismatches := v_point_mismatches || jsonb_build_object(
        'loyaltyAccountId', v_account.acct_id, 'expectedAvailable', v_account.live_available, 'actualAvailable', null, 'note', 'no cached app.loyalty_point_balances row found for an account with ledger activity'
      );
    elsif v_account.cached_available is distinct from v_account.live_available then
      v_point_mismatches := v_point_mismatches || jsonb_build_object(
        'loyaltyAccountId', v_account.acct_id, 'expectedAvailable', v_account.live_available, 'actualAvailable', v_account.cached_available
      );
    end if;
  end loop;

  -- =========================================================================
  -- Cashback/discount/voucher: current status independently re-derived
  -- purely from the append-only event log (design decision 7). Loop body
  -- byte-identical to the prior logic -- sourced from the single-snapshot
  -- projection above, not a live query.
  -- =========================================================================
  for v_entitlement in select * from jsonb_to_recordset(v_entitlement_json) as x(ent_id uuid, benefit_type text, currency text, value_amount numeric, cached_status text, latest_event_type text)
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
  -- assumption, design decision 1, currency-scoped since CPL-324/
  -- 20260801270000). Loop body byte-identical to the prior logic --
  -- sourced from the single-snapshot projection above, not a live query.
  -- =========================================================================
  for v_redemption in select * from jsonb_to_recordset(v_redemption_json) as x(rdm_id uuid, cached_status text, internal_cost numeric, latest_event_type text)
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
  'CPL-323, hardened at CPL-324 (ISS-2026-136 item 1 currency-scope fix) and CPL-325 (single-snapshot atomicity fix, this migration): one deterministic, reproducible Loyalty-liability reconciliation run, as of a recorded point in time. points_liability_total is a RAW POINTS total (no fabricated conversion rate); cashback/discount/voucher/reward_fulfillment totals are all currency-scoped to this run''s own currency column. All three source domains (points/entitlements/reward-fulfillment redemptions), plus the point-balance cache comparison, are now read via ONE single top-level SQL statement -- genuinely one MVCC snapshot under READ COMMITTED, restoring this function''s own documented invariant ("a run reflects a normal MVCC-consistent snapshot," 20260801250000) which the prior three-separate-statement shape did not actually deliver. status=certified requires zero open exceptions on this run -- certification never silently forces equality.';
