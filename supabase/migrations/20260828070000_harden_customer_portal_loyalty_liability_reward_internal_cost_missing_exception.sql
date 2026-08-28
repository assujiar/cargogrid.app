-- Track B Batch 4 (loyalty-fraud-reconciliation), ISS-2026-134 item 3
-- (docs/runtime/KNOWN_ISSUES.md): the reward-fulfillment-exposure liability
-- line (reward_fulfillment_liability_total) silently contributes 0 for an
-- actively-fulfilling physical_item/service_credit redemption whose own
-- reward.internal_cost is null, rather than raising an exception a staff
-- member would see and could correct.
--
-- Independently re-verified before drafting this fix (not accepted from
-- the issue's own text at face value): app.execute_loyalty_liability_
-- reconciliation_run has been replaced twice since it was first created
-- (supabase/migrations/20260801250000_create_customer_portal_loyalty_
-- liability_reconciliation_analytics.sql) -- once by ISS-2026-136 item 1's
-- own currency-scope fix (20260801270000) and again by the CPL-325
-- single-snapshot-atomicity fix (20260801310000_harden_customer_portal_
-- loyalty_liability_reconciliation_snapshot_atomicity.sql, the three
-- source reads folded into ONE top-level statement via jsonb_agg/
-- jsonb_to_recordset so all three domains share one MVCC snapshot). THIS
-- migration builds on the CURRENT (post-20260801310000) body -- the
-- single-statement jsonb_agg/jsonb_to_recordset shape, unmodified -- not
-- an earlier version, so this fix does not regress the snapshot-atomicity
-- guarantee 20260801310000 established (a mistake this migration's own
-- author caught and corrected before drafting, by diffing against a
-- separate-loop draft accidentally based on 20260801270000 instead of the
-- true current 20260801310000 body -- live-reproduced: that draft broke
-- scripts/db-tests/customer-loyalty-liability-reconciliation.sql's own
-- CPL-325 hardening regression, `CRITICAL: ... a torn, non-atomic read`).
-- Direct read of the current body (20260801310000:182) confirms
-- `coalesce(r.internal_cost, 0)` is still used inside the redemption
-- jsonb_agg projection, with no companion detection of the null case
-- anywhere in the function.
--
-- This is the SAME shape as the two already-established derivation-mismatch
-- exception types this exact function already raises for the points and
-- entitlement/redemption-status lines (design decisions 7/8) -- a genuine
-- data-quality signal a staff member needs to see and resolve, not a
-- silent understatement. This migration adds the third exception type
-- ISS-2026-134 item 3's own recommended fix names verbatim
-- (`reward_internal_cost_missing`), mirroring the exact CREATE OR REPLACE
-- FUNCTION (same signature, additive only) shape both prior hardening
-- fixes to this function already used.
--
-- Currency-scoping the DETECTION itself, not only the total (deliberate,
-- avoids reintroducing ISS-2026-136 item 2's own already-disclosed "tenant-
-- wide, not currency-scoped" detection-noise shape for this new exception
-- type): the exception is only raised when `p_currency =
-- v_tenant_default_currency` -- the SAME predicate that gates whether this
-- redemption's cost would actually be accumulated into THIS run's own
-- total at all. A currency-scoped run in a tenant's non-default currency
-- would otherwise re-flag the identical gap on every run regardless of
-- currency, exactly the operational-noise shape ISS-2026-136 item 2 already
-- disclosed as acceptable-but-real for the two pre-existing mismatch types
-- -- deliberately not repeated here for a new type where it is avoidable.
--
-- Deliberately unchanged: the liability TOTAL itself still contributes 0
-- for a null-internal_cost open redemption (inventing a fabricated
-- placeholder cost would be worse than a disclosed, staff-visible
-- understatement) -- this migration only makes the gap VISIBLE as a real,
-- resolvable exception instead of a silent zero, exactly as ISS-2026-134's
-- own recommended fix describes ("a third exception type... if this gap is
-- ever observed in practice"). A run with an open
-- reward_internal_cost_missing exception cannot be certified (design
-- decision 8's own existing certify-blocked-while-open-exceptions-remain
-- gate, unchanged, now also covering this case) until a staff member either
-- corrects the reward's own internal_cost (closing the gap for future runs)
-- or explicitly resolves the exception with a reason (accepting the
-- understatement for this run, same as any other exception type).
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
-- its own explicit `revoke execute on all functions in schema app from
-- public` statement before its final grants, the standing per-migration
-- convention since PLT-118.

-- ===========================================================================
-- 1. Widen the exception_type check constraint to admit the new type.
-- ===========================================================================

alter table app.loyalty_liability_reconciliation_exceptions
  drop constraint llre_exception_type_check;

alter table app.loyalty_liability_reconciliation_exceptions
  add constraint llre_exception_type_check check (exception_type in (
    'point_balance_derivation_mismatch',
    'entitlement_state_derivation_mismatch',
    'redemption_liability_status_mismatch',
    'reward_internal_cost_missing'
  ));

comment on table app.loyalty_liability_reconciliation_exceptions is
  'CPL-323: one exception per real derivation mismatch or data-quality gap found by app.execute_loyalty_liability_reconciliation_run (design decisions 7/8, the CPL-325 single-snapshot-atomicity fix, and the ISS-2026-134 item 3 reward_internal_cost_missing fix, this migration) -- expected/actual carried in `detail` jsonb (this checkpoint''s own disclosed choice over separate expected_value/actual_value columns, since the exception types carry structurally different detail shapes). Resolution requires an explicit, non-empty reason -- never a silent dismissal.';

-- ===========================================================================
-- 2. app.execute_loyalty_liability_reconciliation_run -- same signature.
--    Base body is the CURRENT (post-20260801310000, single-snapshot-
--    atomicity) version -- the one-statement jsonb_agg/jsonb_to_recordset
--    shape, unmodified. Adds raw_internal_cost to the redemption branch's
--    own jsonb_build_object and to the jsonb_to_recordset column list, then
--    detects a null value in the SAME currency-scoped branch as the
--    existing accumulation -- every other line, including the single-
--    statement snapshot read itself, is byte-identical to the prior body.
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
  v_entitlement record;
  v_derived_status text;
  v_redemption record;
  v_derived_redemption_status text;
  v_point_mismatches jsonb[] := '{}';
  v_entitlement_mismatches jsonb[] := '{}';
  v_redemption_mismatches jsonb[] := '{}';
  v_cost_missing_mismatches jsonb[] := '{}';
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
  -- CPL-325 single-snapshot-atomicity shape (20260801310000, unmodified).
  -- ONE statement, three independent jsonb_agg() branches (one per source
  -- domain), each an exact row-for-row/column-for-column projection of what
  -- the three separate queries would select -- the points branch inlines
  -- the point-balance cache lookup as a correlated subquery in the SAME
  -- statement. ISS-2026-134 item 3 fix (this migration): the redemption
  -- branch's own jsonb_build_object now ALSO carries raw_internal_cost
  -- (r.internal_cost, WITHOUT the coalesce) alongside the existing coalesced
  -- internal_cost, so the loop below can distinguish "really 0" from "null,
  -- coalesced to 0" without a second, separately-snapshotted query.
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
        'rdm_id', rd.id, 'reward_id', r.id, 'cached_status', rd.status,
        'internal_cost', coalesce(r.internal_cost, 0), 'raw_internal_cost', r.internal_cost,
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
  -- 20260801270000). Loop body sourced from the single-snapshot projection
  -- above, not a live query. ISS-2026-134 item 3 fix (this migration): a
  -- null raw_internal_cost still contributes 0 to the total (unchanged --
  -- a fabricated placeholder cost would be worse than a disclosed
  -- understatement) but now ALSO raises a real reward_internal_cost_missing
  -- exception, in the same currency-scoped branch as the accumulation
  -- itself, so a staff member can see and correct the gap instead of it
  -- being silent.
  -- =========================================================================
  for v_redemption in select * from jsonb_to_recordset(v_redemption_json) as x(rdm_id uuid, reward_id uuid, cached_status text, internal_cost numeric, raw_internal_cost numeric, latest_event_type text)
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

      if v_redemption.raw_internal_cost is null then
        v_cost_missing_mismatches := v_cost_missing_mismatches || jsonb_build_object(
          'redemptionId', v_redemption.rdm_id, 'rewardId', v_redemption.reward_id, 'note', 'reward.internal_cost is null on an actively fulfilling redemption -- contributes 0 to reward_fulfillment_liability_total'
        );
      end if;
    end if;
  end loop;

  v_exception_count := coalesce(array_length(v_point_mismatches, 1), 0) + coalesce(array_length(v_entitlement_mismatches, 1), 0) + coalesce(array_length(v_redemption_mismatches, 1), 0) + coalesce(array_length(v_cost_missing_mismatches, 1), 0);

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

  foreach v_mismatch in array v_cost_missing_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'reward_internal_cost_missing', v_mismatch);
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
  'CPL-323, hardened at CPL-324 (ISS-2026-136 item 1 currency-scope fix), CPL-325 (single-snapshot atomicity fix, 20260801310000), and again here (ISS-2026-134 item 3 fix): one deterministic, reproducible Loyalty-liability reconciliation run, as of a recorded point in time. points_liability_total is a RAW POINTS total (no fabricated conversion rate); cashback/discount/voucher/reward_fulfillment totals are all currency-scoped to this run''s own currency column. All three source domains (points/entitlements/reward-fulfillment redemptions), plus the point-balance cache comparison, are read via ONE single top-level SQL statement -- one MVCC snapshot under READ COMMITTED. A null reward.internal_cost on an actively-fulfilling redemption in the currency-scoped branch still contributes 0 to the total but now raises a reward_internal_cost_missing exception instead of failing silently. status=certified requires zero open exceptions on this run -- certification never silently forces equality.';

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default, applied before any role-specific grant below.
revoke execute on all functions in schema app from public;

grant execute on function app.execute_loyalty_liability_reconciliation_run(uuid, timestamptz, text, uuid, text, text, integer) to authenticated, service_role;
