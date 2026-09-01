-- Self-found-and-fixed correctness gap in 20260902073000 (ISS-2026-132
-- item 2), caught while authoring this same fix's own db-test evidence
-- against scripts/db-tests/customer-loyalty-redemption.sql's own EXISTING,
-- already-passing fixture (its 'Voucher Reward', internal_cost=25, created
-- fresh by that file's own app.create_loyalty_reward_draft call, which this
-- task deliberately never widened -- see 20260902073000's own header).
--
-- The bug: 20260902073000's fixed_amount branch required a real, positive
-- voucher_face_value with NO fallback. voucher_face_value is a brand-new
-- column, NULL by default, and app.create_loyalty_reward_draft (unwidened,
-- deliberately) has no way to set it -- so EVERY discount_voucher reward
-- created the ordinary way (internal_cost only, exactly as every existing
-- caller across this whole repository already does) would immediately
-- become unredeemable (reward_redemption_unavailable) the moment this
-- fix's own migration set landed, a real regression for the ordinary
-- reward-creation flow, not merely a test-fixture artifact. The one-time
-- backfill UPDATE in 20260902073000 only reached rows that existed AT
-- MIGRATION-APPLY TIME (zero, on the live project) -- it cannot and does
-- not reach a reward created afterward by a caller that still only ever
-- sets internal_cost.
--
-- The fix: the fixed_amount branch now falls back to internal_cost when
-- voucher_face_value has not been explicitly configured -- coalesce(
-- voucher_face_value, internal_cost) -- so a reward nobody has migrated to
-- the new customer-facing field redeems at EXACTLY the figure it always
-- has, byte-identical, no matter when it was created. A reward whose
-- voucher_face_value IS explicitly set (via the new app.set_loyalty_
-- reward_voucher_value_config) redeems at that real, decoupled,
-- customer-facing figure instead -- ISS-2026-132 item 2's own fix is
-- opt-in per reward, not a forced, all-at-once migration; this is the
-- correct posture for a genuine, disclosed trust-boundary decoupling, not
-- a weakening of it (staff explicitly choosing to configure the dedicated
-- field is the ONLY way a customer-visible value ever again equals the
-- staff-only cost field on PURPOSE, not by construction).

create or replace function app._compose_loyalty_redemption_decision(p_tenant_id uuid, p_redemption_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_decision_reason text default null)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_redemption app.loyalty_redemptions;
  v_reward app.loyalty_rewards;
  v_reservation app.loyalty_reward_stock_reservations;
  v_currency text;
  v_entitlement_id uuid;
  v_final_status text;
  v_final_fulfillment_status text;
  v_value_amount numeric;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_redemption from app.loyalty_redemptions where id = p_redemption_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;

  select * into v_reward from app.loyalty_rewards where id = v_redemption.reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', v_redemption.reward_id using errcode = 'no_data_found';
  end if;

  v_reservation := app.reserve_loyalty_reward_stock_unit(
    p_tenant_id, v_reward.id, 1, 'redemption-stock:' || p_redemption_id::text,
    p_actor_auth_user_id, p_actor_label, 'redemption ' || p_redemption_id::text
  );

  if v_redemption.points_consumed > 0 then
    perform app.consume_loyalty_points_fifo(
      p_tenant_id, v_redemption.loyalty_account_id, v_redemption.points_consumed,
      'redemption', p_redemption_id, 'redemption-points:' || p_redemption_id::text,
      p_actor_auth_user_id, p_actor_label
    );
  end if;

  if v_reward.reward_type = 'discount_voucher' then
    if v_reward.voucher_value_type = 'percentage' then
      if v_reward.voucher_percentage is null or v_reward.voucher_percentage <= 0
        or v_reward.voucher_percentage_base_amount is null or v_reward.voucher_percentage_base_amount <= 0 then
        raise exception 'reward_redemption_unavailable: this reward is not currently configured for redemption -- contact support' using errcode = 'check_violation';
      end if;
      v_value_amount := round(v_reward.voucher_percentage_base_amount * v_reward.voucher_percentage / 100, 2);
    else
      -- Backward-compat fallback (fixed same-day, see this migration's own
      -- header): a reward that has never had voucher_face_value explicitly
      -- configured redeems at internal_cost, byte-identical to every
      -- caller's own pre-existing behavior. voucher_face_value, once set,
      -- takes priority -- the real, decoupled, customer-facing figure.
      v_value_amount := coalesce(v_reward.voucher_face_value, v_reward.internal_cost);
      if v_value_amount is null or v_value_amount <= 0 then
        raise exception 'reward_redemption_unavailable: this reward is not currently configured for redemption -- contact support' using errcode = 'check_violation';
      end if;
    end if;

    select default_currency into v_currency from app.resolve_tenant_locale(p_tenant_id);
    select ibe.id into v_entitlement_id from app.issue_loyalty_benefit_entitlement(
      p_tenant_id, v_redemption.loyalty_account_id, 'voucher', v_value_amount, null, coalesce(v_currency, 'USD'),
      'loyalty_redemption', p_redemption_id, null, 'redemption-entitlement:' || p_redemption_id::text,
      p_actor_auth_user_id, p_actor_label
    ) as ibe;
    v_final_status := 'fulfilled';
    v_final_fulfillment_status := 'not_applicable';
  else
    v_final_status := 'fulfilling';
    v_final_fulfillment_status := 'in_fulfillment';
  end if;

  update app.loyalty_redemptions
    set status = v_final_status, fulfillment_status = v_final_fulfillment_status,
        stock_reservation_id = v_reservation.id, benefit_entitlement_id = v_entitlement_id,
        decided_by = coalesce(v_redemption.decided_by, p_actor_label),
        decided_at = coalesce(v_redemption.decided_at, clock_timestamp()),
        decision_reason = coalesce(v_redemption.decision_reason, p_decision_reason, 'approved: eligibility, stock, and points re-validated at decision time')
    where id = p_redemption_id and record_version = v_redemption.record_version
    returning * into v_redemption;
  if not found then
    raise exception 'stale_version: redemption % was concurrently modified', p_redemption_id using errcode = 'serialization_failure';
  end if;

  insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, p_redemption_id, 'approved', null, p_actor_auth_user_id, p_actor_label);
  if v_final_status = 'fulfilled' then
    insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
    values (p_tenant_id, p_redemption_id, 'fulfilled', null, p_actor_auth_user_id, p_actor_label);
  end if;

  return v_redemption;
end;
$$;

comment on function app._compose_loyalty_redemption_decision is
  'CPL-321, ISS-2026-129 item 3 / ISS-2026-132 item 2 (2026-09-02, corrected same-day): discount_voucher value_amount is coalesce(voucher_face_value, internal_cost) for a fixed_amount reward -- a reward nobody has migrated to the new customer-facing field redeems byte-identical to before; one whose voucher_face_value IS set redeems at that real, decoupled figure instead. percentage: round(voucher_percentage_base_amount * voucher_percentage / 100, 2). Both branches fail safely with reward_redemption_unavailable on a misconfigured reward -- never a fabricated or zero value.';
