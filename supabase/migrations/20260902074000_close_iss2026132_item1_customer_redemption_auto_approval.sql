-- ISS-2026-132 item 1 -- a genuine, synchronous auto-approval path for an
-- unassisted customer_user self-service redemption, opt-in per reward.
--
-- Live-verified before writing anything (pg_get_functiondef against
-- app.submit_loyalty_redemption/app._compose_loyalty_redemption_decision):
-- this entry's own root-cause analysis still holds -- app.role_assignments
-- has exactly one INSERT call site in this repository (app.assign_role_to_
-- user, staff-only), so a genuine customer_user identity never holds
-- LYL:Edit, the authority app.issue_loyalty_benefit_entitlement (and the
-- other composed primitives) require on the ACTOR PASSED TO THEM. ADR-0024
-- Part B / ISS-2026-040 forbid widening those shared primitives' own RBAC
-- gate to admit customer_user -- this migration does not touch that gate,
-- anywhere, for any of the three composed primitives.
--
-- The fix this entry's own "Recommended fix" already named: "a dedicated,
-- cross-cutting, per-tenant 'system/automation identity' provisioning
-- capability, after which app.submit_loyalty_redemption's own composition
-- attempt could use that identity instead of the raw customer's own." This
-- migration builds the NARROW slice of that: not a new user-creation
-- mechanism (this repository's real auth.users provisioning is out of
-- reach of a SQL migration, and inventing one here would be the exact
-- "new, cross-cutting, per-tenant-provisioning capability" this entry
-- already correctly scoped as too large) -- instead, a tenant DESIGNATES an
-- ALREADY-EXISTING staff-provisioned identity (created and granted LYL:Edit
-- through this repository's ordinary, already-shipped invite/app.assign_
-- role_to_user machinery, zero new code) as its own "loyalty redemption
-- auto-approval principal." app.submit_loyalty_redemption, for a genuine
-- customer_user submission against a reward the tenant has explicitly
-- opted into auto-approval, composes using THAT designated principal's
-- identity -- never the raw customer's own, never a fabricated bypass of
-- the primitives' own real LYL:Edit check (re-verified live, every call).
-- If no principal is configured, or the configured principal no longer
-- holds LYL:Edit (re-checked on every attempt, never cached), the
-- submission gracefully falls back to pending_approval, byte-identical to
-- today's behavior -- exactly this entry's own "never make this the
-- default... opt-in only" requirement, satisfied structurally, not just by
-- a default value.

-- ===========================================================================
-- 1. app.loyalty_rewards: the opt-in, reward-level toggle. Defaults false --
-- every existing reward's own redemption behavior is completely unchanged.
-- ===========================================================================

alter table app.loyalty_rewards
  add column auto_approve_customer_redemption boolean not null default false;

comment on column app.loyalty_rewards.auto_approve_customer_redemption is
  'ISS-2026-132 item 1 (2026-09-02): opt-in, per-reward. When true AND the tenant has a currently-LYL:Edit-holding auto-approval principal configured (app.loyalty_redemption_auto_approval_principals), a genuine customer_user submission against this reward composes synchronously instead of falling back to pending_approval. Defaults false -- never the default for any existing or newly-created reward.';

create function app.set_loyalty_reward_auto_approve_customer_redemption(
  p_tenant_id uuid,
  p_reward_id uuid,
  p_expected_version integer,
  p_enabled boolean,
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
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Governance-grade: enabling unattended entitlement issuance for a
  -- genuine customer identity is a real authorization-shape decision, the
  -- same bar app.certify_loyalty_liability_reconciliation_run/app.publish_
  -- loyalty_reward already require for their own consequential actions --
  -- never merely LYL:Edit.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_enabled is null then
    raise exception 'invalid_enabled: a non-null enabled flag is required' using errcode = 'check_violation';
  end if;

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;

  if p_expected_version is null or v_reward.record_version <> p_expected_version then
    raise exception 'stale_version: reward % expected version % but found %', p_reward_id, p_expected_version, v_reward.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.loyalty_rewards set auto_approve_customer_redemption = p_enabled
    where id = p_reward_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: reward % was concurrently modified (expected version %)', p_reward_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_loyalty_reward_auto_approve_customer_redemption',
    'app.loyalty_rewards', v_updated.id, 'success', null, null, jsonb_build_object('auto_approve_customer_redemption', v_updated.auto_approve_customer_redemption)
  );

  return v_updated;
end;
$$;

comment on function app.set_loyalty_reward_auto_approve_customer_redemption is
  'ISS-2026-132 item 1: LYL:Configure-gated (governance-grade, matches app.certify_loyalty_liability_reconciliation_run''s own bar). Works on a reward of ANY status, unlike app.set_loyalty_reward_voucher_value_config -- a runtime redemption-behavior toggle, not a catalogue edit.';

grant execute on function app.set_loyalty_reward_auto_approve_customer_redemption(uuid, uuid, integer, boolean, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 2. app.loyalty_redemption_auto_approval_principals -- one designated,
-- already-LYL:Edit-holding identity per tenant. Re-checked live on every
-- redemption attempt, never trusted as still-valid from configuration time.
-- ===========================================================================

create table app.loyalty_redemption_auto_approval_principals (
  tenant_id uuid primary key references app.tenants (id),
  auth_user_id uuid not null,
  principal_label text not null,
  configured_by text,
  configured_at timestamptz not null default clock_timestamp(),
  record_version integer not null default 1,
  updated_at timestamptz not null default clock_timestamp()
);

comment on table app.loyalty_redemption_auto_approval_principals is
  'ISS-2026-132 item 1: at most one per tenant. auth_user_id must ALREADY hold LYL:Edit at configuration time (checked below) and is RE-CHECKED live on every auto-approval attempt (app.submit_loyalty_redemption) -- never cached, never assumed still valid. Deliberately does not create or provision any identity -- points at one a tenant''s own staff already created via the ordinary invite/app.assign_role_to_user flow.';

create function app.touch_loyalty_redemption_auto_approval_principal_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_redemption_auto_approval_principals_touch before update on app.loyalty_redemption_auto_approval_principals
  for each row execute function app.touch_loyalty_redemption_auto_approval_principal_row();

create function app.set_loyalty_redemption_auto_approval_principal(
  p_tenant_id uuid,
  p_principal_auth_user_id uuid,
  p_principal_label text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_redemption_auto_approval_principals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_principal_decision app.rbac_decision;
  v_row app.loyalty_redemption_auto_approval_principals;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_principal_auth_user_id is null then
    raise exception 'invalid_principal: a principal auth_user_id is required' using errcode = 'check_violation';
  end if;
  if p_principal_label is null or length(trim(p_principal_label)) = 0 then
    raise exception 'invalid_principal_label: a non-empty label is required' using errcode = 'check_violation';
  end if;

  -- The designated principal must ALREADY be a real, staff-provisioned
  -- identity holding LYL:Edit for THIS tenant -- never a bare uuid, never
  -- an identity conjured for this purpose. Re-checked again, live, on every
  -- actual auto-approval attempt (app.submit_loyalty_redemption) -- this
  -- check is a helpful up-front rejection, not the enforcement point.
  v_principal_decision := app.evaluate_permission(p_principal_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_principal_decision.allowed then
    raise exception 'invalid_principal: identity % does not currently hold LYL:Edit for tenant % -- grant it via the ordinary staff role-assignment flow first', p_principal_auth_user_id, p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.loyalty_redemption_auto_approval_principals (tenant_id, auth_user_id, principal_label, configured_by)
  values (p_tenant_id, p_principal_auth_user_id, trim(p_principal_label), p_actor_label)
  on conflict (tenant_id) do update
    set auth_user_id = excluded.auth_user_id, principal_label = excluded.principal_label, configured_by = excluded.configured_by
  returning * into v_row;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_loyalty_redemption_auto_approval_principal',
    'app.loyalty_redemption_auto_approval_principals', p_tenant_id, 'success', null, null,
    jsonb_build_object('auth_user_id', p_principal_auth_user_id, 'principal_label', v_row.principal_label)
  );

  return v_row;
end;
$$;

comment on function app.set_loyalty_redemption_auto_approval_principal is
  'ISS-2026-132 item 1: LYL:Configure-gated. Rejects a target identity that does not currently hold LYL:Edit -- the ONE guardrail this migration adds against pointing auto-approval at an identity that could never actually compose anyway.';

create function app.get_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_redemption_auto_approval_principals
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.loyalty_redemption_auto_approval_principals;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_row from app.loyalty_redemption_auto_approval_principals where tenant_id = p_tenant_id;
  return v_row;
end;
$$;

create function app.clear_loyalty_redemption_auto_approval_principal(p_tenant_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  delete from app.loyalty_redemption_auto_approval_principals where tenant_id = p_tenant_id;
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'clear_loyalty_redemption_auto_approval_principal',
    'app.loyalty_redemption_auto_approval_principals', p_tenant_id, 'success', null, null, null
  );
end;
$$;

alter table app.loyalty_redemption_auto_approval_principals enable row level security;

create policy loyalty_redemption_auto_approval_principals_select_scoped on app.loyalty_redemption_auto_approval_principals
  for select to authenticated
  using (app.is_supreme_admin() or (app.evaluate_permission((select auth.uid()), tenant_id, 'LYL', 'View')).allowed);

revoke execute on all functions in schema app from public;

grant select on app.loyalty_redemption_auto_approval_principals to authenticated, service_role;
grant insert, update, delete on app.loyalty_redemption_auto_approval_principals to service_role;
grant execute on function app.touch_loyalty_redemption_auto_approval_principal_row() to service_role;
grant execute on function app.set_loyalty_redemption_auto_approval_principal(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_redemption_auto_approval_principal(uuid, uuid) to authenticated, service_role;
grant execute on function app.clear_loyalty_redemption_auto_approval_principal(uuid, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 3. app.submit_loyalty_redemption: ONE new elsif arm. Live-verified before
-- writing anything -- unmodified since its own original migration. CREATE
-- OR REPLACE, byte-identical signature/language/security definer/
-- search_path. The existing staff-submission auto-compose arm (LYL:
-- Configure on the submitting actor) is completely untouched, including
-- its own pre-existing behavior quirks -- out of this item's own scope.
-- ===========================================================================

create or replace function app.submit_loyalty_redemption(p_tenant_id uuid, p_loyalty_account_id uuid, p_reward_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
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
  v_principal app.loyalty_redemption_auto_approval_principals;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_is_staff := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit')).allowed;
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if not v_is_staff and array_length(v_scope, 1) is null then
    raise exception 'insufficient_authority: identity % holds neither LYL:Edit nor any customer_user account scope for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.loyalty_redemptions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.loyalty_account_id <> p_loyalty_account_id or v_existing.reward_id <> p_reward_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different redemption request', p_idempotency_key using errcode = 'check_violation';
    end if;
    return v_existing;
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found or v_account.status <> 'active' or not (v_is_staff or v_account.customer_account_id = any (v_scope)) then
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_loyalty_account_id::text, 6));

  select * into v_reward from app.loyalty_rewards where id = p_reward_id and tenant_id = p_tenant_id and program_id = v_account.program_id for update;
  if not found then
    raise exception 'loyalty_reward_not_found: %', p_reward_id using errcode = 'no_data_found';
  end if;
  if v_reward.status <> 'published' or v_reward.effective_from > clock_timestamp() or (v_reward.effective_to is not null and v_reward.effective_to <= clock_timestamp()) then
    raise exception 'reward_not_currently_redeemable: reward % is not currently available for redemption', p_reward_id using errcode = 'check_violation';
  end if;

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

  v_points_consumed := coalesce(v_reward.min_points_required, 0);
  if v_points_consumed > 0 then
    v_current_points := coalesce((select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = v_account.id), 0);
    if v_current_points < v_points_consumed then
      raise exception 'ineligible_reward: this account does not have enough points for this reward' using errcode = 'check_violation';
    end if;
  end if;

  v_redemption_id := gen_random_uuid();

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

  if v_reward.reward_type = 'discount_voucher' and (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure')).allowed then
    begin
      v_redemption := app._compose_loyalty_redemption_decision(p_tenant_id, v_redemption_id, p_actor_auth_user_id, p_actor_label, null);
    exception
      when others then
        null;
    end;
  elsif v_reward.reward_type = 'discount_voucher' and not v_is_staff and coalesce(v_reward.auto_approve_customer_redemption, false) then
    -- ISS-2026-132 item 1: a genuine, unassisted customer_user submission
    -- against a reward the tenant has opted into auto-approval. Composes
    -- using the tenant's own DESIGNATED principal identity -- re-checked
    -- live for LYL:Edit right here, never trusted from configuration time
    -- -- never the raw customer's own identity, which never holds LYL:Edit
    -- and never will via this migration. No principal configured, or the
    -- configured one no longer holds LYL:Edit: falls through unchanged,
    -- exactly today's pending_approval outcome.
    select * into v_principal from app.loyalty_redemption_auto_approval_principals where tenant_id = p_tenant_id;
    if found and (app.evaluate_permission(v_principal.auth_user_id, p_tenant_id, 'LYL', 'Edit')).allowed then
      begin
        v_redemption := app._compose_loyalty_redemption_decision(
          p_tenant_id, v_redemption_id, v_principal.auth_user_id,
          'system:' || v_principal.principal_label, 'auto-approved: reward configured for automatic customer redemption'
        );
      exception
        when others then
          null;
      end;
    end if;
  end if;

  return v_redemption;
end;
$$;

comment on function app.submit_loyalty_redemption is
  'CPL-321, ISS-2026-132 item 1 (2026-09-02): dual authority (customer_user own scope OR staff LYL:Edit), always creates the real pending_approval intent record first. discount_voucher composition is attempted synchronously in two cases -- a submitting actor who independently holds LYL:Configure (staff/system, unchanged), OR a genuine customer_user submission against a reward with auto_approve_customer_redemption=true AND a tenant-configured auto-approval principal that currently holds LYL:Edit (new). Any composition failure -- including no principal configured -- gracefully falls back to pending_approval, never a hard failure of the submission itself.';

grant execute on function app.submit_loyalty_redemption(uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
