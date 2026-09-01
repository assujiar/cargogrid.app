-- ISS-2026-129 item 3 (percentage-based voucher model) and ISS-2026-132
-- item 2 (discount_voucher entitlement value sourced from staff-only
-- internal_cost) -- addressed together in one migration since both live in
-- the SAME code path: app._compose_loyalty_redemption_decision's own
-- discount_voucher branch (CPL-321 design decision 4).
--
-- ISS-2026-132 item 2 investigation, done BEFORE writing any code, per this
-- task's own instruction to verify original intent from the build log
-- first: docs/build-log/phase-08/CPL-321.md design decision 4, read
-- verbatim -- "CPL-320's own reward row has no dedicated customer-facing
-- monetary value column; internal_cost is the only numeric, monetary-shaped
-- field available." This is a disclosed STOPGAP forced by a real schema gap
-- (no customer-facing value column existed), not a design decision that
-- internal_cost and entitlement value are INTENDED to be the same figure --
-- CPL-320's own design decision 8 marks internal_cost staff-only-visible
-- for cost-accounting purposes, while CPL-321 was, at the same time, using
-- that exact number as the value a customer actually redeems. This is
-- genuinely the trust-boundary bug this entry's own item 2 describes, not
-- an intentional equivalence -- fixed here by giving app.loyalty_rewards a
-- REAL, separate customer-facing value column.
--
-- ISS-2026-129 item 3 investigation: app.loyalty_redemptions carries no
-- order/invoice reference of any kind (grep + live schema check confirmed
-- -- no FK, no order_id/invoice_id column anywhere on the table), so the
-- "likely the order/invoice total at redemption time" base-amount reading
-- this task's own text speculated does not apply to THIS system as it
-- actually exists. The only "base amount" that can be contextually correct
-- without inventing a fabricated linkage is a value staff explicitly
-- configure on the reward itself at definition time -- the same choice this
-- checkpoint already makes for internal_cost/min_points_required. A
-- percentage-type discount_voucher reward therefore carries its own
-- voucher_percentage_base_amount, staff-configured, required and validated
-- (>0) before the reward can ever be redeemed at that type -- never a
-- fabricated or zero base.
--
-- Design (kept additive and narrowly scoped to avoid the RETURNS-TABLE /
-- PostgREST-wrapper-widening cascade ISS-2026-124 already demonstrated is
-- required whenever a function's own OUTPUT column list changes): all four
-- new columns land on app.loyalty_rewards (the reward CATALOGUE, CPL-320)
-- rather than app.loyalty_benefit_entitlements (CPL-319) or app.
-- issue_loyalty_benefit_entitlement's own signature/RETURNS TABLE, both of
-- which stay completely untouched -- value_amount remains the one
-- authoritative, already-resolved currency figure recorded on every
-- entitlement, computed correctly for both value types by the redemption
-- composition function BEFORE calling the unmodified issuance RPC, exactly
-- as it already does for internal_cost today. Zero existing caller of app.
-- issue_loyalty_benefit_entitlement is affected.

-- ===========================================================================
-- 1. app.loyalty_rewards: four new nullable/defaulted columns.
-- ===========================================================================

alter table app.loyalty_rewards
  add column voucher_value_type text not null default 'fixed_amount',
  add column voucher_face_value numeric(14, 2),
  add column voucher_percentage numeric(5, 2),
  add column voucher_percentage_base_amount numeric(14, 2);

alter table app.loyalty_rewards
  add constraint loyalty_rewards_voucher_value_type_check check (voucher_value_type in ('fixed_amount', 'percentage'));

alter table app.loyalty_rewards
  add constraint loyalty_rewards_voucher_value_shape_check check (
    (voucher_value_type = 'fixed_amount' and voucher_percentage is null and voucher_percentage_base_amount is null)
    or (
      voucher_value_type = 'percentage'
      and voucher_percentage is not null and voucher_percentage > 0 and voucher_percentage <= 100
      and voucher_percentage_base_amount is not null and voucher_percentage_base_amount > 0
    )
  );

alter table app.loyalty_rewards
  add constraint loyalty_rewards_voucher_face_value_check check (voucher_face_value is null or voucher_face_value > 0);

comment on column app.loyalty_rewards.voucher_value_type is
  'ISS-2026-129 item 3, ISS-2026-132 item 2 (2026-09-02): fixed_amount (default, backward compatible) or percentage. Only meaningful for reward_type=discount_voucher; every other reward_type carries the default and NULL percentage/base, satisfied trivially by loyalty_rewards_voucher_value_shape_check.';
comment on column app.loyalty_rewards.voucher_face_value is
  'ISS-2026-132 item 2: the REAL customer-facing monetary value of a fixed_amount discount_voucher reward -- distinct from internal_cost (staff-only cost accounting, CPL-320 design decision 8). Backfilled from internal_cost for any pre-existing discount_voucher row (below) so an already-configured reward redeems at the exact same figure it always has; going forward the two are independently staff-configured.';
comment on column app.loyalty_rewards.voucher_percentage is
  'ISS-2026-129 item 3: percentage (0, 100] applied to voucher_percentage_base_amount at redemption time for a percentage-type discount_voucher reward. NULL for fixed_amount rewards.';
comment on column app.loyalty_rewards.voucher_percentage_base_amount is
  'ISS-2026-129 item 3: the staff-configured reference amount a percentage-type discount_voucher reward''s value is computed against. app.loyalty_redemptions carries no order/invoice reference for this system to derive a base from instead (live-verified) -- staff configure it explicitly, mirroring internal_cost/min_points_required''s own existing configuration shape. NULL for fixed_amount rewards.';

-- One-time backfill: an already-configured discount_voucher reward keeps
-- redeeming at the EXACT figure it always has (internal_cost) -- the
-- decoupling is forward-only, never a silent value change for an existing
-- reward. Zero rows affected on the live project today (grep-confirmed no
-- discount_voucher reward exists yet); written for correctness regardless.
update app.loyalty_rewards
  set voucher_face_value = internal_cost
  where reward_type = 'discount_voucher' and internal_cost is not null and internal_cost > 0;

-- ===========================================================================
-- 2. app.set_loyalty_reward_voucher_value_config -- a new, additive,
-- narrowly-scoped RPC letting staff configure the four new columns on a
-- DRAFT reward, mirroring app.update_loyalty_reward_draft's own gate/
-- concurrency shape exactly, without touching that function's own signature
-- (avoiding any overload/PostgREST-wrapper collision).
-- ===========================================================================

create function app.set_loyalty_reward_voucher_value_config(
  p_tenant_id uuid,
  p_reward_id uuid,
  p_expected_version integer,
  p_voucher_value_type text,
  p_voucher_face_value numeric,
  p_voucher_percentage numeric,
  p_voucher_percentage_base_amount numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_rewards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reward app.loyalty_rewards;
  v_updated app.loyalty_rewards;
  v_value_type text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_value_type := coalesce(p_voucher_value_type, 'fixed_amount');
  if v_value_type not in ('fixed_amount', 'percentage') then
    raise exception 'invalid_voucher_value_type: % is not one of fixed_amount/percentage', v_value_type using errcode = 'check_violation';
  end if;
  if v_value_type = 'fixed_amount' and (p_voucher_percentage is not null or p_voucher_percentage_base_amount is not null) then
    raise exception 'invalid_voucher_value_config: percentage/base_amount must be null when voucher_value_type=fixed_amount' using errcode = 'check_violation';
  end if;
  if v_value_type = 'percentage' then
    if p_voucher_percentage is null or p_voucher_percentage <= 0 or p_voucher_percentage > 100 then
      raise exception 'invalid_voucher_percentage: percentage must be in (0, 100] when voucher_value_type=percentage' using errcode = 'check_violation';
    end if;
    if p_voucher_percentage_base_amount is null or p_voucher_percentage_base_amount <= 0 then
      raise exception 'invalid_voucher_percentage_base_amount: base_amount must be greater than zero when voucher_value_type=percentage' using errcode = 'check_violation';
    end if;
  end if;
  if v_value_type = 'fixed_amount' and p_voucher_face_value is not null and p_voucher_face_value <= 0 then
    raise exception 'invalid_voucher_face_value: face_value must be greater than zero when supplied' using errcode = 'check_violation';
  end if;

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  if p_expected_version is null or v_reward.record_version <> p_expected_version then
    raise exception 'stale_version: reward % expected version % but found %', p_reward_id, p_expected_version, v_reward.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_reward.status <> 'draft' then
    raise exception 'invalid_transition: reward % is % -- only a draft may be edited', p_reward_id, v_reward.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_rewards
    set voucher_value_type = v_value_type,
        voucher_face_value = case when v_value_type = 'fixed_amount' then p_voucher_face_value else null end,
        voucher_percentage = case when v_value_type = 'percentage' then p_voucher_percentage else null end,
        voucher_percentage_base_amount = case when v_value_type = 'percentage' then p_voucher_percentage_base_amount else null end
    where id = p_reward_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: reward % was concurrently modified (expected version %)', p_reward_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_loyalty_reward_voucher_value_config',
    'app.loyalty_rewards', v_updated.id, 'success', null, null,
    jsonb_build_object('voucher_value_type', v_updated.voucher_value_type, 'voucher_face_value', v_updated.voucher_face_value, 'voucher_percentage', v_updated.voucher_percentage, 'voucher_percentage_base_amount', v_updated.voucher_percentage_base_amount)
  );

  return v_updated;
end;
$$;

comment on function app.set_loyalty_reward_voucher_value_config is
  'ISS-2026-129 item 3, ISS-2026-132 item 2: LYL:Edit-gated, draft-only, mirrors app.update_loyalty_reward_draft''s own concurrency/authority shape. A dedicated, additive companion RPC rather than widening app.create_loyalty_reward_draft/app.update_loyalty_reward_draft''s own signature -- both, and their public.* PostgREST wrappers, stay byte-identical.';

grant execute on function app.set_loyalty_reward_voucher_value_config(uuid, uuid, integer, text, numeric, numeric, numeric, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 3. app._compose_loyalty_redemption_decision (CPL-321): the discount_
-- voucher branch now branches on voucher_value_type. Live-verified before
-- writing anything (pg_get_functiondef) -- unmodified since its own
-- original migration. CREATE OR REPLACE, byte-identical signature/
-- language/security definer/search_path.
-- ===========================================================================

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

  -- Design decision 13: every downstream call below is UNCAUGHT here -- any
  -- failure (insufficient stock, insufficient points, a misconfigured
  -- voucher reward) aborts this WHOLE function, and every caller of this
  -- helper either lets that propagate further (decide_loyalty_redemption)
  -- or catches it and leaves its own already-inserted redemption row
  -- exactly where it is (submit_loyalty_redemption's own graceful
  -- fallback, design decision 5, Tier C review fix -- catches ANY
  -- composition exception, not only insufficient_authority) -- no partial
  -- mutation of the composition's own downstream work is ever left behind.
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
    -- ISS-2026-132 item 2 fix: value_amount now sourced from a real
    -- customer-facing field, never the staff-only internal_cost. ISS-2026-
    -- 129 item 3 fix: a percentage-type reward computes its value against
    -- its own staff-configured voucher_percentage_base_amount -- this
    -- system has no order/invoice context to derive a base from instead
    -- (live-verified, see this migration's own header). Either branch
    -- fails safely with the SAME customer-safe reward_redemption_
    -- unavailable error a misconfigured reward has always raised here --
    -- never a fabricated or zero value.
    if v_reward.voucher_value_type = 'percentage' then
      if v_reward.voucher_percentage is null or v_reward.voucher_percentage <= 0
        or v_reward.voucher_percentage_base_amount is null or v_reward.voucher_percentage_base_amount <= 0 then
        raise exception 'reward_redemption_unavailable: this reward is not currently configured for redemption -- contact support' using errcode = 'check_violation';
      end if;
      v_value_amount := round(v_reward.voucher_percentage_base_amount * v_reward.voucher_percentage / 100, 2);
    else
      if v_reward.voucher_face_value is null or v_reward.voucher_face_value <= 0 then
        raise exception 'reward_redemption_unavailable: this reward is not currently configured for redemption -- contact support' using errcode = 'check_violation';
      end if;
      v_value_amount := v_reward.voucher_face_value;
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
    -- NULL-bypass fix (design decision 10): the predicate is repeated here.
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
  'CPL-321, ISS-2026-129 item 3 / ISS-2026-132 item 2 (2026-09-02): discount_voucher value_amount now sourced from app.loyalty_rewards.voucher_face_value (fixed_amount, the real customer-facing field) or round(voucher_percentage_base_amount * voucher_percentage / 100, 2) (percentage) -- never internal_cost. Both branches fail safely with reward_redemption_unavailable on a misconfigured reward, exactly as the prior internal_cost-sourced check already did -- never a fabricated or zero value.';

-- No grant here, deliberately -- live-verified this private helper carries
-- zero EXECUTE grant to any role, not even service_role (called only from
-- within other SECURITY DEFINER functions owned by the same definer role).
-- Unchanged from before this migration.
