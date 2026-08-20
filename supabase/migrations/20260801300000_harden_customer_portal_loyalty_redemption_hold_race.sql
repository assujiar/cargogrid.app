-- Phase 8 Customer Portal and Loyalty (CPL-325, CG-S13-CPL-027, Prompt 325,
-- "Customer Portal and Loyalty Privacy Integrity Hardening") -- fixes a
-- live-reproduced, deterministic (lock-gated) TOCTOU race between the
-- account-level fraud/tier hold (app.hold_loyalty_account_tier_benefits,
-- CPL-317, 20260801190000) and redemption composition (app.submit_loyalty_
-- redemption / app.decide_loyalty_redemption's approve branch,
-- app._compose_loyalty_redemption_decision, CPL-321, 20260801230000).
--
-- Root cause, live-reproduced this checkpoint (deterministic lock-gated
-- interleaving, not merely a lucky-timing race): both entry points read
-- `app.loyalty_account_tier_holds` via a PLAIN, UNLOCKED SELECT
-- (`select coalesce(is_held, false) into v_held from app.loyalty_account_
-- tier_holds where ...`), then perform several more statements (reward/
-- tier/points re-validation, then the actual composition -- reserve stock,
-- consume points, conditionally issue a voucher entitlement) BEFORE the
-- transaction commits. Nothing re-checks or locks the hold state between
-- that read and the value-consuming mutation. A hold opened by app.hold_
-- loyalty_account_tier_benefits (called directly, or composed by app.open_
-- loyalty_fraud_review_case, CPL-322) DURING that window is silently
-- bypassed: real stock is reserved and real points are consumed for an
-- account that is, by the time the transaction commits, already on hold --
-- exactly the scenario the hold control exists to prevent. Ledger
-- arithmetic itself stays correct throughout (no lost update, no
-- double-consumption -- the FOR UPDATE-protected balance/stock loops are
-- unaffected); this is specifically a control-bypass window, not a
-- balance-corruption defect, so it does not meet this checkpoint''s own
-- Critical-escalation bar (balance/liability manipulation, double-spend, or
-- a cross-tenant/cross-account leak) -- rated High (a real, live-reproduced
-- bypass of a governance control whose entire purpose is blocking exactly
-- this action, reachable by two staff-privileged callers racing each other
-- in a genuine fraud-response scenario, not merely a theoretical window).
--
-- Fix (bounded, additive, `CREATE OR REPLACE FUNCTION` against identical
-- signatures -- the already-applied 20260801190000/20260801230000 files are
-- never edited): serialize every reader AND every writer of a given
-- loyalty account's own hold state behind ONE per-account
-- `pg_advisory_xact_lock`, mirroring this exact repository''s own
-- already-established `hashtextextended(p_loyalty_account_id::text, salt)`
-- per-entity advisory-lock convention (CPL-317''s own salt 3 for tier
-- recalculation, 20260801190000 line 748; CPL-318''s own salt 4 for point
-- consumption, 20260801200000 line 959) -- salt 6 here, a new, independent
-- lock domain scoped to hold-vs-redemption-composition serialization only
-- (deliberately NOT salt 3/4, so this fix does not also serialize against
-- unrelated tier-recalculation or point-consumption calls for the same
-- account). The lock is taken:
--   - in app.hold_loyalty_account_tier_benefits and app.release_loyalty_
--     account_tier_benefits, before their own existing hold-row read;
--   - in app.submit_loyalty_redemption, right after its own account
--     lookup, before its own hold check;
--   - in app.decide_loyalty_redemption''s approve branch, right before its
--     own hold re-check.
-- pg_advisory_xact_lock is held for the remainder of the CALLING
-- transaction (released automatically at COMMIT/ROLLBACK, never needs an
-- explicit unlock) and is safely REENTRANT within one transaction/session --
-- app.decide_loyalty_redemption''s own subsequent call into app._compose_
-- loyalty_redemption_decision (which does not itself take this lock; it
-- does not need to, since its caller already holds it for the whole
-- transaction) is therefore already covered. app.open_loyalty_fraud_review_
-- case (CPL-322) composes app.hold_loyalty_account_tier_benefits directly
-- (20260801240000, design decision 3) -- this fix covers that path too,
-- with no change needed to the fraud-review migration itself.
--
-- Effect: a hold-open/release and a redemption submit/decide for the SAME
-- loyalty account can no longer interleave -- whichever transaction reaches
-- the advisory lock first completes its own full check-then-act sequence
-- (hold state read through composition, or hold state write) before the
-- other proceeds, so a hold that is about to commit is either fully visible
-- to the redemption path's own hold check (correctly rejected,
-- account_on_hold) or fully ordered after it (the redemption's own
-- composition completes first, and the hold then applies going forward,
-- exactly like today's already-correct non-concurrent ordering) -- never
-- the torn, live-reproduced in-between state this migration closes.
--
-- No new GRANT/REVOKE needed -- `CREATE OR REPLACE FUNCTION` on an
-- identical signature preserves the existing ACL for all four functions.

-- ===========================================================================
-- 1. app.hold_loyalty_account_tier_benefits -- lock taken immediately after
--    the account lookup, before the hold-row read.
-- ===========================================================================

create or replace function app.hold_loyalty_account_tier_benefits(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_account_tier_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
  v_hold app.loyalty_account_tier_holds;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to hold a loyalty account''s tier benefits' using errcode = 'not_null_violation';
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  -- CPL-325 fix: serialize against app.submit_loyalty_redemption / app.
  -- decide_loyalty_redemption's own identical lock for this SAME account
  -- (see this migration's own header) -- closes the live-reproduced hold-
  -- vs-composition TOCTOU race.
  perform pg_advisory_xact_lock(hashtextextended(p_loyalty_account_id::text, 6));

  select * into v_hold from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id for update;
  if found and v_hold.is_held then
    return v_hold;
  end if;

  if found then
    update app.loyalty_account_tier_holds
      set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = clock_timestamp(), released_by = null, released_at = null
      where id = v_hold.id
      returning * into v_hold;
  else
    begin
      insert into app.loyalty_account_tier_holds (tenant_id, loyalty_account_id, is_held, hold_reason, held_by, held_at)
      values (p_tenant_id, p_loyalty_account_id, true, p_reason, p_actor_label, clock_timestamp())
      returning * into v_hold;
    exception
      when unique_violation then
        select * into v_hold from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id for update;
        if v_hold.is_held then
          return v_hold;
        end if;
        update app.loyalty_account_tier_holds
          set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = clock_timestamp(), released_by = null, released_at = null
          where id = v_hold.id
          returning * into v_hold;
    end;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_loyalty_account_tier_benefits',
    'app.loyalty_account_tier_holds', v_hold.id, 'success', p_reason, null, jsonb_build_object('is_held', true)
  );

  return v_hold;
end;
$$;

comment on function app.hold_loyalty_account_tier_benefits is
  'CPL-317, hardened at CPL-325 (redemption hold-race fix, this migration): idempotent -- holding an already-held account is a safe no-op returning the unchanged row (original hold_reason/held_by/held_at preserved, never overwritten by a repeated call). A held account''s benefits are suppressed in app.list_customer_portal_loyalty_tier_cards. Serialized against app.submit_loyalty_redemption/app.decide_loyalty_redemption via a per-account pg_advisory_xact_lock (salt 6) -- a hold can no longer commit invisibly mid-composition.';

-- ===========================================================================
-- 2. app.release_loyalty_account_tier_benefits -- lock taken immediately
--    after the authority check, before the hold-row read (this function
--    never looks up app.loyalty_accounts itself).
-- ===========================================================================

create or replace function app.release_loyalty_account_tier_benefits(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_account_tier_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_hold app.loyalty_account_tier_holds;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- CPL-325 fix: same per-account lock as app.hold_loyalty_account_tier_
  -- benefits (see this migration's own header, salt 6).
  perform pg_advisory_xact_lock(hashtextextended(p_loyalty_account_id::text, 6));

  select * into v_hold from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id for update;
  if not found then
    raise exception 'loyalty_account_tier_hold_not_found: no hold exists for loyalty account %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;
  if not v_hold.is_held then
    return v_hold;
  end if;

  update app.loyalty_account_tier_holds
    set is_held = false, released_by = p_actor_label, released_at = clock_timestamp()
    where id = v_hold.id
    returning * into v_hold;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'release_loyalty_account_tier_benefits',
    'app.loyalty_account_tier_holds', v_hold.id, 'success', null, null, jsonb_build_object('is_held', false)
  );

  return v_hold;
end;
$$;

comment on function app.release_loyalty_account_tier_benefits is
  'CPL-317, hardened at CPL-325 (redemption hold-race fix, this migration): serialized against app.submit_loyalty_redemption/app.decide_loyalty_redemption via the SAME per-account pg_advisory_xact_lock (salt 6) app.hold_loyalty_account_tier_benefits uses.';

-- ===========================================================================
-- 3. app.submit_loyalty_redemption -- lock taken immediately after the
--    account lookup, before the hold check.
-- ===========================================================================

create or replace function app.submit_loyalty_redemption(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_reward_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_is_staff boolean;
  v_scope uuid[];
  v_existing app.loyalty_redemptions;
  v_account app.loyalty_accounts;
  v_reward app.loyalty_rewards;
  v_held boolean;
  v_current_tier_rank integer;
  v_min_tier_rank integer;
  v_current_points numeric;
  v_points_consumed numeric;
  v_redemption_id uuid;
  v_redemption app.loyalty_redemptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Coarse standing check (mandatory pattern: scope/authority check BEFORE
  -- the idempotent short-circuit).
  v_is_staff := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit')).allowed;
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if not v_is_staff and array_length(v_scope, 1) is null then
    raise exception 'insufficient_authority: identity % holds neither LYL:Edit nor any customer_user account scope for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  -- Idempotent short-circuit AFTER the standing check, verifying the FULL
  -- target tuple on a key match (C-01), not only the key.
  select * into v_existing from app.loyalty_redemptions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.loyalty_account_id <> p_loyalty_account_id or v_existing.reward_id <> p_reward_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different redemption request', p_idempotency_key using errcode = 'check_violation';
    end if;
    return v_existing;
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found or v_account.status <> 'active' or not (v_is_staff or v_account.customer_account_id = any (v_scope)) then
    -- Anti-enumeration for the caller's own standing.
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  -- CPL-325 fix: serialize against app.hold_loyalty_account_tier_benefits/
  -- app.release_loyalty_account_tier_benefits (see this migration's own
  -- header, salt 6) -- held through this call's own composition attempt
  -- below, so a hold committing concurrently for this SAME account can no
  -- longer land invisibly between this function's own hold check and its
  -- own composition.
  perform pg_advisory_xact_lock(hashtextextended(p_loyalty_account_id::text, 6));

  -- Re-validate eligibility server-side, at THIS checkpoint, inside THIS
  -- transaction -- never trust a client-supplied "I saw this as eligible"
  -- claim (business rule; design decision 9).
  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id and program_id = v_account.program_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;
  if v_reward.status <> 'published' or v_reward.effective_from > clock_timestamp() or (v_reward.effective_to is not null and v_reward.effective_to <= clock_timestamp()) then
    raise exception 'reward_not_currently_redeemable: reward % is not currently available for redemption', p_reward_id using errcode = 'check_violation';
  end if;

  -- Account-level fraud hold (design decision 6) -- blocks new redemptions
  -- the same way CPL-317 already suppresses tier-benefit display for a
  -- held account; a customer-safe, generic denial, never the real reason.
  select coalesce(is_held, false) into v_held from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id;
  if coalesce(v_held, false) then
    raise exception 'account_on_hold: this account cannot redeem rewards at this time. Contact your account administrator or support for details.' using errcode = 'check_violation';
  end if;

  select td.tier_rank into v_current_tier_rank
  from app.loyalty_account_tier_movements tm
  join app.loyalty_tier_definitions td on td.id = tm.to_tier_id
  where tm.tenant_id = p_tenant_id and tm.loyalty_account_id = v_account.id
  order by tm.created_at desc, tm.id desc
  limit 1;

  if v_reward.min_tier_id is not null then
    select tier_rank into v_min_tier_rank from app.loyalty_tier_definitions where id = v_reward.min_tier_id;
    if v_current_tier_rank is null or v_current_tier_rank < v_min_tier_rank then
      raise exception 'ineligible_reward: this account does not currently meet the tier requirement for this reward' using errcode = 'check_violation';
    end if;
  end if;

  -- Design decision 1: points_cost = min_points_required.
  v_points_consumed := coalesce(v_reward.min_points_required, 0);
  if v_points_consumed > 0 then
    v_current_points := coalesce((select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_account.id), 0);
    if v_current_points < v_points_consumed then
      raise exception 'ineligible_reward: this account does not have enough points for this reward' using errcode = 'check_violation';
    end if;
  end if;

  v_redemption_id := gen_random_uuid();

  -- The idempotency-establishing INSERT happens strictly BEFORE any
  -- downstream stock/points/entitlement mutation (design decision 12).
  begin
    insert into app.loyalty_redemptions (
      id, tenant_id, loyalty_account_id, reward_id, reward_version_number, reward_name, reward_type,
      points_consumed, status, fulfillment_status, idempotency_key, created_by
    ) values (
      v_redemption_id, p_tenant_id, p_loyalty_account_id, p_reward_id, v_reward.version_number, v_reward.reward_name, v_reward.reward_type,
      v_points_consumed, 'pending_approval', case when v_reward.reward_type = 'discount_voucher' then 'not_applicable' else 'pending' end,
      p_idempotency_key, p_actor_label
    )
    returning * into v_redemption;
  exception
    when unique_violation then
      select * into v_existing from app.loyalty_redemptions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      return v_existing;
  end;

  insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_redemption_id, 'submitted', null, p_actor_auth_user_id, p_actor_label);

  -- Attempt immediate composition (design decision 5) -- ONLY for
  -- discount_voucher (my own reward_type threshold rule: physical_item/
  -- service_credit ALWAYS require a genuine staff decision, regardless of
  -- who submitted -- deterministic, never actor-dependent for those two
  -- types). Even for discount_voucher, this succeeds synchronously only
  -- when the submitting actor ALSO independently holds LYL:Edit (staff/
  -- system); a genuine, unassisted customer_user actor gracefully falls
  -- back to pending_approval, awaiting a real staff app.decide_loyalty_
  -- redemption call.
  if v_reward.reward_type = 'discount_voucher' then
    begin
      v_redemption := app._compose_loyalty_redemption_decision(p_tenant_id, v_redemption_id, p_actor_auth_user_id, p_actor_label, null);
    exception
      when others then
        -- Tier C review fix (Batch 5 close): catch EVERY composition
        -- failure here, not only insufficient_authority -- a genuine
        -- customer_user actor fails on insufficient_authority (the
        -- originally-anticipated case), but a staff/system actor who DOES
        -- hold LYL:Edit can also reach this branch and have the attempt
        -- fail for a completely ordinary, non-authority reason
        -- (insufficient_reward_stock, insufficient_points_balance, or a
        -- misconfigured discount_voucher reward's own reward_redemption_
        -- unavailable). Filtering the catch by sqlerrm and re-raising
        -- every other exception used to abort this WHOLE function call,
        -- which rolled back the redemption row's own INSERT and its
        -- 'submitted' event too (both happened BEFORE this begin block,
        -- hence before the implicit savepoint it establishes) -- silently
        -- losing the customer's own otherwise-legitimate request with zero
        -- audit trail, directly contradicting this migration's own
        -- documented invariant (design decision 5: "every submission,
        -- regardless of caller, ALWAYS creates the real, portal-owned
        -- intent/request record"). Every composition failure, whatever its
        -- cause, now leaves the row exactly where it already is --
        -- pending_approval, as inserted above -- so a human can resolve it
        -- via app.decide_loyalty_redemption, which independently re-
        -- validates the identical business condition (stock, points,
        -- reward configuration) at decision time rather than destroying
        -- the request outright. The downstream stock/points/entitlement
        -- work attempted inside _compose_loyalty_redemption_decision
        -- itself still correctly and fully rolls back either way (design
        -- decision 13) -- only the OUTER redemption-row/event survival
        -- changes.
        null;
    end;
  end if;

  return v_redemption;
end;
$$;

comment on function app.submit_loyalty_redemption is
  'CPL-321, hardened at CPL-325 (redemption hold-race fix, this migration): dual authority (design decision 5) -- customer_user own account scope OR staff LYL:Edit. Idempotent on (tenant_id, idempotency_key), verifying the full target tuple on a key match (C-01). Re-validates reward status/effective-window/hold/tier/points fully, server-side, inside this transaction, serialized against app.hold_loyalty_account_tier_benefits/app.release_loyalty_account_tier_benefits via a per-account pg_advisory_xact_lock (salt 6) held through this call''s own composition attempt. Attempts immediate reserve+consume(+issue) composition; gracefully falls back to pending_approval on ANY composition failure -- see this migration''s own header design decision 5 for the full, disclosed reasoning.';

-- ===========================================================================
-- 4. app.decide_loyalty_redemption -- lock taken at the start of the
--    approve branch, before the hold re-check.
-- ===========================================================================

create or replace function app.decide_loyalty_redemption(
  p_tenant_id uuid,
  p_redemption_id uuid,
  p_expected_version integer,
  p_decision text,
  p_decision_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_redemption app.loyalty_redemptions;
  v_reward app.loyalty_rewards;
  v_held boolean;
  v_current_tier_rank integer;
  v_min_tier_rank integer;
  v_current_points numeric;
  v_updated app.loyalty_redemptions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision is null or p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % is not one of approve/reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' and (p_decision_reason is null or length(trim(p_decision_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to reject a redemption' using errcode = 'not_null_violation';
  end if;

  select * into v_redemption from app.loyalty_redemptions where id = p_redemption_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_redemption_not_found: %', p_redemption_id using errcode = 'no_data_found';
  end if;
  -- NULL-bypass fix: a bare `<>` comparison against a NULL p_expected_
  -- version evaluates to SQL NULL (falsy), silently skipping this check.
  -- The reject branch's own UPDATE below independently repeats this
  -- predicate too (a second, redundant safeguard) -- but the approve
  -- branch delegates its actual mutation to app._compose_loyalty_
  -- redemption_decision, which uses its OWN freshly re-read record_version
  -- (never p_expected_version) for its own UPDATE, so THIS explicit check
  -- is the ONLY place a stale/NULL p_expected_version is ever rejected on
  -- that path -- must not rely on the bare `<>` alone.
  if p_expected_version is null or v_redemption.record_version <> p_expected_version then
    raise exception 'stale_version: redemption % expected version % but found %', p_redemption_id, p_expected_version, v_redemption.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_redemption.status <> 'pending_approval' then
    raise exception 'invalid_transition: redemption % is % -- only a pending_approval redemption may be decided', p_redemption_id, v_redemption.status
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approve' then
    -- CPL-325 fix: serialize against app.hold_loyalty_account_tier_
    -- benefits/app.release_loyalty_account_tier_benefits (see this
    -- migration's own header, salt 6) -- held through this branch's own
    -- delegation to app._compose_loyalty_redemption_decision below, so a
    -- hold committing concurrently for this SAME account can no longer
    -- land invisibly between this branch's own hold re-check and its own
    -- composition.
    perform pg_advisory_xact_lock(hashtextextended(v_redemption.loyalty_account_id::text, 6));

    -- Re-validate eligibility/hold/reward status ONE more time, fresh, at
    -- THIS checkpoint (design decision 9) -- time may have passed since
    -- submission.
    select * into v_reward from app.loyalty_rewards where id = v_redemption.reward_id and tenant_id = p_tenant_id;
    if not found or v_reward.status <> 'published' or v_reward.effective_from > clock_timestamp() or (v_reward.effective_to is not null and v_reward.effective_to <= clock_timestamp()) then
      raise exception 'reward_not_currently_redeemable: reward % is no longer available for redemption', v_redemption.reward_id using errcode = 'check_violation';
    end if;

    select coalesce(is_held, false) into v_held from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = v_redemption.loyalty_account_id;
    if coalesce(v_held, false) then
      raise exception 'account_on_hold: this account cannot redeem rewards at this time. Contact your account administrator or support for details.' using errcode = 'check_violation';
    end if;

    select td.tier_rank into v_current_tier_rank
      from app.loyalty_account_tier_movements tm join app.loyalty_tier_definitions td on td.id = tm.to_tier_id
      where tm.tenant_id = p_tenant_id and tm.loyalty_account_id = v_redemption.loyalty_account_id
      order by tm.created_at desc, tm.id desc limit 1;
    if v_reward.min_tier_id is not null then
      select tier_rank into v_min_tier_rank from app.loyalty_tier_definitions where id = v_reward.min_tier_id;
      if v_current_tier_rank is null or v_current_tier_rank < v_min_tier_rank then
        raise exception 'ineligible_reward: this account no longer meets the tier requirement for this reward' using errcode = 'check_violation';
      end if;
    end if;

    if v_redemption.points_consumed > 0 then
      v_current_points := coalesce((select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_redemption.loyalty_account_id), 0);
      if v_current_points < v_redemption.points_consumed then
        raise exception 'ineligible_reward: this account no longer has enough points for this reward' using errcode = 'check_violation';
      end if;
    end if;

    -- Explicit LYL:Edit re-check before delegating (design decision 14,
    -- mirrors CPL-318's own design decision 16 precedent exactly) -- a
    -- Configure-only actor gets a clear, immediate, self-referential
    -- rejection rather than a confusing nested failure.
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant % -- approval delegates to app.reserve_loyalty_reward_stock_unit/app.consume_loyalty_points_fifo, which also require LYL:Edit', p_actor_auth_user_id, v_decision.reason, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;

    v_updated := app._compose_loyalty_redemption_decision(p_tenant_id, p_redemption_id, p_actor_auth_user_id, p_actor_label, p_decision_reason);
  else
    update app.loyalty_redemptions
      set status = 'rejected', fulfillment_status = 'not_applicable', decided_by = p_actor_label, decided_at = clock_timestamp(), decision_reason = p_decision_reason
      -- NULL-bypass fix (design decision 10).
      where id = p_redemption_id and record_version = p_expected_version
      returning * into v_updated;
    if not found then
      raise exception 'stale_version: redemption % was concurrently modified (expected version %)', p_redemption_id, p_expected_version
        using errcode = 'serialization_failure';
    end if;

    -- Reverse whatever was already composed at submit time, if anything
    -- (design decision 8/business rule: rejection reverses stock AND
    -- points together, a real, safe no-op when nothing was reserved).
    perform app._reverse_loyalty_redemption_composition(p_tenant_id, v_redemption, p_actor_auth_user_id, p_actor_label);

    insert into app.loyalty_redemption_events (tenant_id, redemption_id, event_type, reason, actor_auth_user_id, actor_label)
    values (p_tenant_id, p_redemption_id, 'rejected', p_decision_reason, p_actor_auth_user_id, p_actor_label);
  end if;

  return v_updated;
end;
$$;

comment on function app.decide_loyalty_redemption is
  'CPL-321, hardened at CPL-325 (redemption hold-race fix, this migration): staff-only, LYL:Configure -- structurally unreachable by any customer_user identity (design decision 7, self-approval impossible). Approve branch is serialized against app.hold_loyalty_account_tier_benefits/app.release_loyalty_account_tier_benefits via a per-account pg_advisory_xact_lock (salt 6, held through delegation to app._compose_loyalty_redemption_decision), then re-validates eligibility/hold/reward-status fresh, explicitly re-checks LYL:Edit before delegating (design decision 14), and is the ONE place a graceful submit-time fallback (design decision 5) is always completed. Reject requires a mandatory non-empty reason and reverses any prior composition (design decision 8).';
