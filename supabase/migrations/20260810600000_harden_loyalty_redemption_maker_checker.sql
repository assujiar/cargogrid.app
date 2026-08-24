-- HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit, `CG-S15-HDN-005`) — closes
-- `ISS-2026-139`, seeded from `HARDENING_MATRIX.md` §4's own carry-forward and
-- live-forced this checkpoint's own investigation.
--
-- `app.submit_loyalty_redemption`'s `discount_voucher` auto-compose branch calls
-- `app._compose_loyalty_redemption_decision` — the exact same mutation
-- `app.decide_loyalty_redemption` performs — directly, with no authority check of its
-- own. `decide_loyalty_redemption` itself requires `LYL:Configure` (an `admin`-tier
-- permission, distinct from the bare `LYL:Edit` `standard`-tier grant
-- `submit_loyalty_redemption` already requires just to submit at all,
-- `supabase/migrations/20260716103445_create_roles_permissions.sql:71-72`). The
-- auto-compose branch never calls `decide_loyalty_redemption`, so `LYL:Configure` is
-- never checked on this path — a maker/checker collapse: a single `LYL:Edit`-only
-- identity can both submit and instantly fulfill a `discount_voucher` redemption for any
-- loyalty account in the tenant, in one call, with no second approver.
--
-- **Live-forced and confirmed** (Tier C investigation lens, `docs/build-log/full-system-
-- hardening/HDN-373.md` §6): a "Redemption Clerk" role holding only `LYL:View/Create/
-- Edit` — explicitly not `Configure` — walked two unrelated, uninvolved customer
-- accounts' real point balances into real, dollar-denominated voucher entitlements in one
-- session, zero second reviewer, fully attributed to the same identity as both
-- `created_by` and `decided_by`.
--
-- **Fix**: the auto-compose branch now requires `LYL:Configure` before attempting
-- composition — identical to the check `decide_loyalty_redemption` already performs.
-- Lacking it is not an error: the existing, already-established graceful fallback (this
-- migration's predecessor's own Tier C fix, `20260801300000_harden_customer_portal_
-- loyalty_redemption_hold_race.sql`) already catches every composition failure and
-- leaves the redemption at `pending_approval`, awaiting a real, distinct `LYL:Configure`
-- holder's decision via `app.decide_loyalty_redemption` — exactly the same outcome an
-- ordinary `customer_user` submitter (who never held `LYL:Edit` to begin with) already
-- receives today. The only behavior this narrows is the specific `LYL:Edit`-alone,
-- same-call-fulfillment shortcut; a genuine `LYL:Configure` holder submitting a
-- `discount_voucher` redemption for themselves still auto-composes exactly as before
-- (self-service for someone who already holds the higher-tier grant is not the defect —
-- the collapse was `LYL:Edit` substituting for `LYL:Configure`, not self-service itself).
--
-- Full disposition: `docs/build-log/full-system-hardening/HDN-373.md` §6.

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
  -- when the submitting actor ALSO independently holds LYL:Configure
  -- (HDN-373: not merely LYL:Edit, which this function's own coarse
  -- standing check above already required just to submit at all --
  -- app.decide_loyalty_redemption, the only other caller of
  -- _compose_loyalty_redemption_decision, has always required Configure,
  -- and this branch bypassed that entirely, letting a bare LYL:Edit holder
  -- both submit and instantly fulfill any account's redemption in one
  -- call, live-forced and confirmed -- ISS-2026-139). A genuine,
  -- unassisted customer_user actor, or a staff actor holding LYL:Edit but
  -- not LYL:Configure, gracefully falls back to pending_approval, awaiting
  -- a real staff app.decide_loyalty_redemption call from a distinct
  -- Configure-holding identity.
  if v_reward.reward_type = 'discount_voucher' and (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure')).allowed then
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
  'CPL-321/CPL-325/HDN-373: submits a redemption request (staff or in-scope customer_user); a discount_voucher submitted by an identity independently holding LYL:Configure auto-composes synchronously in the same call, exactly mirroring what a real, separate app.decide_loyalty_redemption approval would do -- LYL:Edit alone is no longer sufficient (ISS-2026-139, was a maker/checker collapse). Every other submission -- physical_item/service_credit always, or a discount_voucher submitted by an LYL:Edit-only or customer_user actor -- lands at pending_approval, awaiting a real staff decision.';

revoke execute on all functions in schema app from public;

grant execute on function app.submit_loyalty_redemption(uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
