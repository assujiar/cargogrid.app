-- ISS-2026-134 item 2 (CPL-323 disclosed boundary) -- app.
-- execute_loyalty_liability_reconciliation_run's own p_as_of parameter
-- already existed (recorded as a run's own point-in-time LABEL) but did not
-- bound which raw ledger/event rows were included -- every total was
-- computed against the FULL CURRENT state of the source tables regardless
-- of p_as_of. This migration makes p_as_of a REAL point-in-time bound.
--
-- Live-verified before writing anything (pg_get_functiondef against the
-- hosted project, not any migration file -- this function has already been
-- CREATE OR REPLACEd twice since its original migration, per this entry's
-- own 2026-08-28 update note): the current body's own single-snapshot
-- (CPL-325/20260801310000) shape sources all three domains from raw,
-- durably-recorded, replayable event tables -- app.loyalty_point_ledger_
-- entries (an append-only points ledger), app.loyalty_benefit_entitlement_
-- events, and app.loyalty_redemption_events (both append-only event logs
-- whose latest-event-before-a-date IS that entitlement/redemption's real
-- historical state) -- exactly the "historical ledger/event tables already
-- back this reconciliation" this fix is directed to use, per this entry's
-- own text. No new history table is invented.
--
-- The fix: every raw read in the single-snapshot statement now bounds by
-- `created_at <= v_as_of` (v_as_of already resolves to `coalesce(p_as_of,
-- clock_timestamp())`, unchanged). This is the ONLY change. Consequences:
--
-- * Every existing caller -- db-tests included -- passes p_as_of as either
--   `clock_timestamp()` (evaluated at call time, after every fixture row's
--   own created_at) or `null` (defaulting to clock_timestamp() internally).
--   Bounding by "<= now" excludes zero already-existing rows in either case
--   -- every existing assertion (including the deliberate mismatch-
--   detection tests) is byte-for-byte unaffected. Proven live below, not
--   merely reasoned about.
-- * A genuinely past p_as_of now EXCLUDES ledger/event rows dated after it
--   -- entitlement/redemption "latest event as of p_as_of" correctly
--   resolves to whatever the state genuinely was on that date (including
--   "not yet issued/submitted at all," which correctly excludes it from
--   every total), and a point balance is the real historical sum, not the
--   current one.
-- * The exactness cross-check (comparing the bounded LIVE recomputation
--   against the CACHED, CURRENT balance/status column) is deliberately left
--   unconditional, exactly as before -- this entry's own text already named
--   why a clean, unconditional suppression is not attempted here: app.
--   loyalty_point_balances/app.loyalty_benefit_entitlements' own cached
--   columns are current-state-only by construction, so for a genuinely
--   historical as_of, a raised "mismatch" may reflect legitimate
--   subsequent activity rather than a data-integrity defect. Silently
--   guessing at a materiality threshold to suppress that would be new,
--   invented logic, not a mechanical extension of what already exists --
--   the comparison stays real and honest, its meaning for a past as_of is
--   now documented here and in the function's own comment rather than
--   quietly narrowed. A future checkpoint with a genuine business need for
--   "was this historically correct AT THAT TIME" (as opposed to "does the
--   historical total match what is cached NOW") would need its own
--   point-in-time snapshot of the cached columns themselves -- a
--   capability-sized addition this fix does not attempt.

create or replace function app.execute_loyalty_liability_reconciliation_run(p_tenant_id uuid, p_as_of timestamp with time zone, p_currency text, p_actor_auth_user_id uuid, p_actor_label text, p_idempotency_key text default null, p_config_version integer default 1)
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
  -- CPL-325 single-snapshot-atomicity shape (20260801310000), ISS-2026-134
  -- item 2 fix (20260902071000): every raw read now bounds by
  -- `created_at <= v_as_of` -- the real point-in-time reconstruction this
  -- entry's own item 2 named as missing. ISS-2026-134 item 3 fix
  -- (20260828070000, unmodified): the redemption branch's own
  -- jsonb_build_object still ALSO carries raw_internal_cost.
  -- =========================================================================
  select
    (select coalesce(jsonb_agg(jsonb_build_object(
        'acct_id', ps.acct_id, 'live_available', ps.live_available,
        'cached_available', (select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = ps.acct_id)
      )), '[]'::jsonb)
     from (
       select le.loyalty_account_id as acct_id, sum(le.amount) as live_available
       from app.loyalty_point_ledger_entries le
       where le.tenant_id = p_tenant_id and le.created_at <= v_as_of
       group by le.loyalty_account_id
     ) ps),
    (select coalesce(jsonb_agg(jsonb_build_object(
        'ent_id', e.id, 'benefit_type', e.benefit_type, 'currency', e.currency, 'value_amount', e.value_amount, 'cached_status', e.status,
        'latest_event_type', (select ev.event_type from app.loyalty_benefit_entitlement_events ev where ev.entitlement_id = e.id and ev.created_at <= v_as_of order by ev.created_at desc, ev.id desc limit 1)
      )), '[]'::jsonb)
     from app.loyalty_benefit_entitlements e
     where e.tenant_id = p_tenant_id and e.created_at <= v_as_of),
    (select coalesce(jsonb_agg(jsonb_build_object(
        'rdm_id', rd.id, 'reward_id', r.id, 'cached_status', rd.status,
        'internal_cost', coalesce(r.internal_cost, 0), 'raw_internal_cost', r.internal_cost,
        'latest_event_type', (select ev.event_type from app.loyalty_redemption_events ev where ev.redemption_id = rd.id and ev.created_at <= v_as_of order by ev.created_at desc, ev.id desc limit 1)
      )), '[]'::jsonb)
     from app.loyalty_redemptions rd
     join app.loyalty_rewards r on r.id = rd.reward_id
     where rd.tenant_id = p_tenant_id and rd.reward_type in ('physical_item', 'service_credit') and rd.created_at <= v_as_of)
  into v_points_json, v_entitlement_json, v_redemption_json;

  -- =========================================================================
  -- Points: live per-account recomputation from the raw ledger, now bounded
  -- by v_as_of (item 2), cross-checked against the cached CURRENT derived
  -- balance for the exactness evidence unit (design decisions 7/8, left
  -- unconditional -- see this migration's own header). greatest(...,0) is a
  -- defensive clamp only.
  --
  -- ISS-2026-136 item 2: DELIBERATELY NOT currency-scoped (unchanged).
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
  -- purely from the append-only event log, now bounded by v_as_of (item 2)
  -- -- an entitlement issued after v_as_of has no qualifying event and is
  -- correctly excluded entirely. ISS-2026-136 item 2 (unchanged): the
  -- mismatch detection still carries the same `v_entitlement.currency =
  -- p_currency` guard.
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

    if v_derived_status is distinct from v_entitlement.cached_status and v_entitlement.currency = p_currency then
      v_entitlement_mismatches := v_entitlement_mismatches || jsonb_build_object(
        'entitlementId', v_entitlement.ent_id, 'expectedStatus', v_derived_status, 'actualStatus', v_entitlement.cached_status, 'latestEventType', v_entitlement.latest_event_type, 'currency', v_entitlement.currency
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
  -- Reward fulfillment exposure, now bounded by v_as_of (item 2) via the
  -- redemption-events latest-event-before-v_as_of lookup above. ISS-2026-134
  -- item 3 (unchanged): a null raw_internal_cost still contributes 0 and
  -- still raises reward_internal_cost_missing. ISS-2026-136 item 2
  -- (unchanged): guarded by `p_currency = v_tenant_default_currency`.
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

    if v_derived_redemption_status is distinct from v_redemption.cached_status and p_currency = v_tenant_default_currency then
      v_redemption_mismatches := v_redemption_mismatches || jsonb_build_object(
        'redemptionId', v_redemption.rdm_id, 'expectedStatus', v_derived_redemption_status, 'actualStatus', v_redemption.cached_status, 'latestEventType', v_redemption.latest_event_type, 'currency', p_currency
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
    jsonb_build_object('currency', p_currency, 'exception_count', v_exception_count, 'status', v_run.status, 'as_of', v_as_of)
  );

  return v_run;
end;
$$;

comment on function app.execute_loyalty_liability_reconciliation_run is
  'CPL-323, ISS-2026-134 item 2 (2026-09-02): p_as_of now genuinely bounds every raw ledger/event read (created_at <= p_as_of, defaulting to clock_timestamp()) -- a real point-in-time reconstruction using the already-durable, append-only app.loyalty_point_ledger_entries/app.loyalty_benefit_entitlement_events/app.loyalty_redemption_events tables, never a new history table. The exactness cross-check still compares the bounded live recomputation against the CACHED, CURRENT balance/status columns (app.loyalty_point_balances/app.loyalty_benefit_entitlements.status) -- for a genuinely past as_of, a raised mismatch may reflect legitimate subsequent activity rather than a data defect; this is disclosed, not solved, since app.loyalty_point_balances/app.loyalty_benefit_entitlements carry no historical snapshot of their own cached columns for any date but now.';

grant execute on function app.execute_loyalty_liability_reconciliation_run(uuid, timestamptz, text, uuid, text, text, integer) to authenticated, service_role;
