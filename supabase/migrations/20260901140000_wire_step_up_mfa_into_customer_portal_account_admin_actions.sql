-- ISS-2026-125 item 1 (docs/runtime/KNOWN_ISSUES.md) -- re-verified live, not assumed, before
-- writing a single line here: this entry's own premise ("no MFA/current-authorization (RPD-023)
-- mechanism exists anywhere in this repository yet") is now FALSE. 20260807100000_create_
-- intelligence_enterprise_mfa_session_controls.sql (IAE-027) shipped a real, applied step-up-MFA
-- mechanism, and TWO capabilities landed earlier this same day (20260901080000_create_customer_
-- portal_legal_identity_change_requests.sql, 20260901090000_create_customer_portal_contact_
-- change_requests.sql) already wired it onto a customer-portal-ADJACENT decision. This migration
-- extends it to the specific privileged actions ISS-2026-125 item 1 names: role change, suspend,
-- revoke of a customer-portal user, performed by another customer-portal account_admin on their
-- OWN account -- Layer-4 customer self-management (`app.actor_is_active_customer_portal_
-- account_admin`), never staff RBAC.
--
-- ===========================================================================
-- The composition question this entry's own task explicitly required answering by reading code,
-- not assuming, and what was actually found
-- ===========================================================================
--
-- app.assert_current_step_up_authorization(tenant, actor, module_code, action) and app.
-- is_high_risk_action(tenant, module_code, action) are BOTH genuinely generic: neither takes a
-- staff RBAC role assignment as an input, neither calls app.evaluate_permission, and is_high_risk_
-- action's own tenant-additive list (app.mfa_tenant_policies.additional_high_risk_actions) is a
-- bare jsonb {moduleCode, action} tag with no foreign key into app.permissions at all. Confirmed
-- live via pg_get_functiondef against the hosted project (awdlicmwzdxquopwtcfd), not from the
-- migration file text, which could have drifted since 20260807100000 -- it has not.
--
-- The one real, narrow, structural gap: the ONLY function that lets an actor OBTAIN a verified
-- challenge, app.request_mfa_step_up_challenge, gates its own precondition on app.has_active_
-- tenant_membership(tenant, actor) OR app.is_supreme_admin(actor). app.has_active_tenant_
-- membership reads app.tenant_user_identities.status = 'active' -- and a customer_user-layer
-- identity's own app.tenant_user_identities row is, BY EXPLICIT, REPEATEDLY-DOCUMENTED DESIGN
-- across this whole capability family (20260801030000 design decision 4(b) and at least six other
-- migrations' own comments, grep-confirmed), deliberately NEVER 'active' -- only the staff-only
-- app.transition_user_status flips that. Left unwidened, a customer-portal account_admin could
-- NEVER obtain a verified challenge for themselves: wiring app.assert_current_step_up_
-- authorization onto their own RPCs without ALSO fixing this would not be "requires MFA", it
-- would be a silent, permanent lockout the moment any tenant opted the action in -- worse than the
-- disclosed gap this migration closes.
--
-- This repository has already established, and used, the safe, narrow, additive fix for EXACTLY
-- this recurring shape: app.check_file_action_authority (PLT-128, widened by CPL-302 design
-- decision 4(b)) widened an identical has_active_tenant_membership-only precondition with `OR
-- app.actor_holds_customer_user_layer(tenant, actor)` (20260730311000) once the identical "a
-- customer_user's own tenant_user_identities row never reaches active" gap surfaced there. app.
-- actor_holds_customer_user_layer(tenant, actor) reads app.principal_memberships (layer =
-- 'customer_user', status = 'active') -- confirmed live that an ACTIVE customer-portal
-- account_admin genuinely holds a matching row: app.accept_customer_portal_invite grants it and
-- app.set_customer_portal_account_membership_status keeps it in lock-step on suspend/revoke/
-- reactivate (20260801010000, design decisions 2 and 7). This migration applies the IDENTICAL
-- widening to app.request_mfa_step_up_challenge -- never a new, bespoke mechanism.
--
-- Widening request_mfa_step_up_challenge's own membership precondition is a pure ADD: nobody who
-- could request a challenge before this migration loses that ability, and nobody who could not
-- (a genuinely unrelated identity, or a different tenant's own staff/customer) gains it --
-- verified against scripts/db-tests/enterprise-mfa-session-controls.sql's own existing
-- insufficient_authority assertions, none of which exercise a customer_user-layer actor, before
-- writing this migration.
--
-- ===========================================================================
-- Module/action vocabulary: a genuinely NEW tag, not a reuse of an existing staff RBAC pair --
-- and why reusing one would itself be the "mismatched pair" this task's own instructions warn
-- against
-- ===========================================================================
--
-- Both same-day precedents (COM:Approve) reused an EXISTING app.permissions pair because their
-- own ordinary authority check, immediately above the new step-up call, IS app.evaluate_permission
-- against that exact pair -- reusing it is a real, accurate label for the same decision being
-- gated twice. This capability's ordinary authority check is app.actor_is_active_customer_portal_
-- account_admin -- a Layer-4-only chain that never touches app.evaluate_permission/app.permissions
-- at all (ADR-0024 Part B, restated verbatim in this migration's own target functions' comments).
-- There is therefore no existing (module, action) pair to reuse. The nearest existing candidate,
-- 'CPT' ("Customer Portal", 20260716094432), is itself STAFF RBAC vocabulary -- e.g. the CPT:
-- Create grant app.grant_initial_customer_portal_account_admin requires of the STAFF caller who
-- bootstraps a portal account's first admin. Tagging a Layer-4 self-service action with 'CPT'
-- would misleadingly imply this gate composes with staff CPT permissions, when it does not --
-- exactly the mismatched-pair failure mode to avoid. This migration therefore introduces a new,
-- unambiguous, Layer-4-only tag, ('CPADM', 'ManageMembership'), used nowhere else and requiring no
-- new app.entitlement_modules/app.permissions rows (is_high_risk_action's tenant-additive list has
-- no such foreign key -- see above). It covers all three of this entry's own named actions (role
-- change, suspend, revoke) under one label, so a tenant configures it once.
--
-- ===========================================================================
-- Blast radius: strictly additive, never mandatory by default, never touches the platform-default
-- tuple list
-- ===========================================================================
--
-- app.is_high_risk_action's own hardcoded platform-default 7-tuple list is UNCHANGED -- ('CPADM',
-- 'ManageMembership') is reachable only via a tenant's own additional_high_risk_actions, which a
-- tenant must explicitly opt into via the already-shipped app.set_mfa_tenant_policy. A tenant with
-- no app.mfa_tenant_policies row, or one that has not added this specific tuple, sees app.assert_
-- current_step_up_authorization no-op exactly as it always has -- identical behavior to before
-- this migration for every existing tenant/fixture/the live project. Suspend/revoke are gated;
-- reactivation (restoring access, not removing it) is deliberately NOT gated -- this entry's own
-- item 1 text names only role change/suspend/revoke.
--
-- ===========================================================================
-- Mechanics
-- ===========================================================================
--
-- All three CREATE OR REPLACE bodies below are the LIVE pg_get_functiondef output (queried
-- directly against the hosted project, not read from the on-disk migration files, which could
-- have drifted since 20260828193000/20260807100000) with exactly one additive block inserted each
-- -- language plpgsql, SECURITY DEFINER and SET search_path are restated explicitly on every one
-- of them, per the corrective precedent this exact recurrence class already needed once
-- (20260831290000_restore_security_definer_on_drifted_finance_wrappers.sql: a CREATE OR REPLACE
-- that silently dropped SECURITY DEFINER on 111 functions). No already-applied migration file is
-- edited. Signatures, return types, and grants are byte-identical to before -- CREATE OR REPLACE
-- preserves existing ACLs automatically, and this migration re-asserts them explicitly anyway,
-- per the standing per-migration convention since PLT-118/ERR-2026-004.

-- ===========================================================================
-- 1. app.request_mfa_step_up_challenge -- widen the membership precondition
-- ===========================================================================

create or replace function app.request_mfa_step_up_challenge(
  p_tenant_id uuid,
  p_module_code text,
  p_action text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.mfa_step_up_challenges
language plpgsql
security definer
set search_path = app, pg_temp
as $function$
declare
  v_challenge app.mfa_step_up_challenges;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- ISS-2026-125 item 1: widened to also accept an active customer_user-layer principal (a
  -- customer-portal user, of ANY role) -- their own app.tenant_user_identities row deliberately
  -- never reaches 'active' (see this migration's own header), so the unwidened predicate was
  -- unconditionally false for every one of them. Identical widening shape to app.check_file_
  -- action_authority (PLT-128/CPL-302, 20260730311000). Safe to widen broadly to "any active
  -- customer_user" rather than "an account_admin specifically": obtaining a verified challenge
  -- grants nothing by itself -- the actual privileged RPC still separately requires app.actor_is_
  -- active_customer_portal_account_admin before it ever reaches its own step-up check.
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id)
     and not app.is_supreme_admin(p_actor_auth_user_id)
     and not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_high_risk_action(p_tenant_id, p_module_code, p_action) then
    raise exception 'mfa_step_up_not_required: %:% is not classified as a high-risk action for tenant %', p_module_code, p_action, p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.mfa_step_up_challenges (tenant_id, auth_user_id, module_code, action)
  values (p_tenant_id, p_actor_auth_user_id, p_module_code, p_action)
  returning * into v_challenge;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_mfa_step_up_challenge',
    'app.mfa_step_up_challenges', v_challenge.id, 'success', null, null,
    jsonb_build_object('module_code', p_module_code, 'action', p_action)
  );

  return v_challenge;
end;
$function$;

comment on function app.request_mfa_step_up_challenge is
  'IAE-027, widened by ISS-2026-125 item 1 (20260901140000): the membership precondition now also accepts an active customer_user-layer principal (app.actor_holds_customer_user_layer), identical in shape to the PLT-128/CPL-302 widening -- a customer-portal user''s own app.tenant_user_identities row deliberately never reaches active. Obtaining a challenge grants nothing by itself; app.is_high_risk_action still gates which (module, action) tuples are reachable at all.';

-- ===========================================================================
-- 2. app.update_customer_portal_account_membership_role -- add the step-up gate
-- ===========================================================================

create or replace function app.update_customer_portal_account_membership_role(
  p_membership_id uuid,
  p_expected_version integer,
  p_new_role text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_account_memberships
language plpgsql
security definer
set search_path = app, pg_temp
as $function$
declare
  v_membership app.customer_portal_account_memberships;
  v_updated app.customer_portal_account_memberships;
  v_remaining_admins integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_new_role not in ('account_admin', 'member') then
    raise exception 'invalid_role: % is not a recognized customer portal role', p_new_role using errcode = 'check_violation';
  end if;

  select * into v_membership from app.customer_portal_account_memberships where id = p_membership_id for update;
  if not found then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  -- Design decision 9 (20260801170000): fetching the target row before the authority check
  -- (to learn its own tenant_id/account_id, required to evaluate authority at
  -- all) deliberately mirrors CPL-300's own already-accepted ISS-2026-116
  -- error shape -- not a new disclosure.
  if not app.actor_is_active_customer_portal_account_admin(v_membership.tenant_id, v_membership.account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active account_admin on account %', p_actor_auth_user_id, v_membership.account_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-125 item 1 (docs/runtime/KNOWN_ISSUES.md): a strict no-op unless this tenant has
  -- itself opted ('CPADM', 'ManageMembership') into its own additional_high_risk_actions AND
  -- turned MFA on -- see app.assert_current_step_up_authorization / app.is_high_risk_action
  -- (20260807100000, IAE-027). Never widens the platform-default high-risk tuple list. Placed
  -- immediately after the ordinary Layer-4 authority check, mirroring app.decide_customer_
  -- legal_identity_change_request's own placement (20260901080000).
  perform app.assert_current_step_up_authorization(v_membership.tenant_id, p_actor_auth_user_id, 'CPADM', 'ManageMembership');

  if v_membership.status <> 'active' then
    raise exception 'invalid_transition: customer portal membership % is %, only an active membership''s role may be changed', p_membership_id, v_membership.status
      using errcode = 'check_violation';
  end if;

  -- Tier C review fix: p_expected_version IS NULL must not silently bypass
  -- this check -- `record_version <> NULL` evaluates to SQL NULL, which a
  -- bare `if ... then raise` treats as false. This early check stays (it
  -- gives the common "wrong version supplied" case a clear message), and
  -- the UPDATE below ALSO repeats `and record_version = p_expected_version`
  -- so a NULL (or any other value that reaches this far some other way)
  -- matches zero rows and falls through to the same stale_version error --
  -- defense in depth, never a single point of failure for this guard.
  if v_membership.record_version <> p_expected_version then
    raise exception 'stale_version: customer portal membership % expected version % but found %', p_membership_id, p_expected_version, v_membership.record_version
      using errcode = 'serialization_failure';
  end if;

  -- Idempotent no-op (design decision 6): the identical role is already in
  -- effect -- return unchanged, no spurious touch-row bump / history entry.
  if v_membership.role = p_new_role then
    return v_membership;
  end if;

  -- Last-account_admin guard (design decision 3). Row-lock the FULL active
  -- account_admin set for this account (not merely v_membership's own row,
  -- already locked above) before deciding, closing the TOCTOU window a bare
  -- count() after only-this-row's-own-lock would leave open.
  if v_membership.role = 'account_admin' and p_new_role = 'member' then
    perform 1 from app.customer_portal_account_memberships
    where tenant_id = v_membership.tenant_id
      and account_id = v_membership.account_id
      and role = 'account_admin'
      and status = 'active'
    for update;

    select count(*) into v_remaining_admins
    from app.customer_portal_account_memberships
    where tenant_id = v_membership.tenant_id
      and account_id = v_membership.account_id
      and role = 'account_admin'
      and status = 'active'
      and id <> v_membership.id;

    if v_remaining_admins = 0 then
      raise exception 'last_account_admin: account % must retain at least one active account_admin', v_membership.account_id
        using errcode = 'check_violation';
    end if;
  end if;

  update app.customer_portal_account_memberships
  set role = p_new_role
  where id = p_membership_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: customer portal membership % was concurrently modified (expected version %)', p_membership_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.customer_portal_account_membership_history
    (membership_id, auth_user_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values
    (v_updated.id, v_updated.auth_user_id, v_updated.tenant_id, v_updated.account_id, v_updated.status, v_updated.status,
     format('role changed from %s to %s', v_membership.role, p_new_role), p_actor_label);

  return v_updated;
end;
$function$;

comment on function app.update_customer_portal_account_membership_role is
  'CPL-315, step-up-MFA-gated by ISS-2026-125 item 1 (20260901140000): change role (account_admin <-> member) for an existing ACTIVE membership. Caller-gated by app.actor_is_active_customer_portal_account_admin on the SAME account_id (design decision 5 of CPL-300, composed here unchanged), ADDITIONALLY gated on app.assert_current_step_up_authorization(tenant, actor, ''CPADM'', ''ManageMembership'') immediately after -- a no-op unless the tenant has both turned on MFA and added (CPADM, ManageMembership) to its own additional_high_risk_actions list. Mirrors app.set_customer_portal_account_membership_status''s own shape exactly (optimistic concurrency, audit write into app.customer_portal_account_membership_history). Flat two-role model (design decision 2) -- no role escalation is possible beyond the caller''s own already-maximal account_admin authority. Rejects (last_account_admin) a demotion that would leave the account with zero active account_admin rows (design decision 3).';

-- ===========================================================================
-- 3. app.set_customer_portal_account_membership_status -- add the step-up gate,
-- scoped to suspend/revoke only (never activate/reactivate)
-- ===========================================================================

create or replace function app.set_customer_portal_account_membership_status(
  p_membership_id uuid,
  p_expected_version integer,
  p_to_status text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_account_memberships
language plpgsql
security definer
set search_path = app, pg_temp
as $function$
declare
  v_membership app.customer_portal_account_memberships;
  v_updated app.customer_portal_account_memberships;
  v_legacy_membership_id uuid;
  v_remaining_admins integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_to_status not in ('active', 'suspended', 'revoked') then
    raise exception 'invalid_status: % is not a status this function may set', p_to_status using errcode = 'check_violation';
  end if;

  if p_to_status in ('suspended', 'revoked') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to % a customer portal membership', p_to_status using errcode = 'not_null_violation';
  end if;

  select * into v_membership from app.customer_portal_account_memberships where id = p_membership_id for update;
  if not found then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  if not app.actor_is_active_customer_portal_account_admin(v_membership.tenant_id, v_membership.account_id, p_actor_auth_user_id) then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  -- ISS-2026-125 item 1 (docs/runtime/KNOWN_ISSUES.md): the identical additive step-up gate app.
  -- update_customer_portal_account_membership_role now carries (20260901140000), scoped here to
  -- the two PRIVILEGED transitions this entry's own text names -- suspend, revoke -- never
  -- activate/reactivate, which restores access rather than removing it. Strict no-op unless the
  -- tenant has both turned on MFA and added (CPADM, ManageMembership) to its own additional_
  -- high_risk_actions list.
  if p_to_status in ('suspended', 'revoked') then
    perform app.assert_current_step_up_authorization(v_membership.tenant_id, p_actor_auth_user_id, 'CPADM', 'ManageMembership');
  end if;

  if v_membership.status = 'invited' and p_to_status = 'active' then
    raise exception 'accept_required: an invited membership may only be activated by the invited identity itself, via app.accept_customer_portal_invite'
      using errcode = 'check_violation';
  end if;

  if p_expected_version is null or v_membership.record_version <> p_expected_version then
    raise exception 'stale_version: customer portal membership % expected version % but found %', p_membership_id, p_expected_version, v_membership.record_version
      using errcode = 'serialization_failure';
  end if;

  -- Track B Batch 8, ISS-2026-125 item 3: last-account_admin guard, the
  -- IDENTICAL shape app.update_customer_portal_account_membership_role
  -- already applies (design decision 3 of 20260801170000) -- row-lock the
  -- FULL active account_admin set for this account (not merely
  -- v_membership's own row, already locked above) before deciding, closing
  -- the same TOCTOU window a bare count() after only-this-row's-own-lock
  -- would leave open. Fires only when the CURRENT row is an active
  -- account_admin transitioning OUT of active (suspended/revoked); a plain
  -- member or an already-non-active row is never blocked by this guard, and
  -- neither is a reactivation (active is not in this branch's own status
  -- list at all).
  if v_membership.role = 'account_admin' and v_membership.status = 'active' and p_to_status in ('suspended', 'revoked') then
    perform 1 from app.customer_portal_account_memberships
    where tenant_id = v_membership.tenant_id
      and account_id = v_membership.account_id
      and role = 'account_admin'
      and status = 'active'
    for update;

    select count(*) into v_remaining_admins
    from app.customer_portal_account_memberships
    where tenant_id = v_membership.tenant_id
      and account_id = v_membership.account_id
      and role = 'account_admin'
      and status = 'active'
      and id <> v_membership.id;

    if v_remaining_admins = 0 then
      raise exception 'last_account_admin: account % must retain at least one active account_admin', v_membership.account_id
        using errcode = 'check_violation';
    end if;
  end if;

  update app.customer_portal_account_memberships
  set status = p_to_status,
      suspended_by = case when p_to_status = 'suspended' then p_actor_label else suspended_by end,
      suspended_at = case when p_to_status = 'suspended' then now() else suspended_at end,
      suspended_reason = case when p_to_status = 'suspended' then p_reason else suspended_reason end,
      revoked_by = case when p_to_status = 'revoked' then p_actor_label else revoked_by end,
      revoked_at = case when p_to_status = 'revoked' then now() else revoked_at end,
      revoked_reason = case when p_to_status = 'revoked' then p_reason else revoked_reason end
  where id = p_membership_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: customer portal membership % was concurrently modified (expected version %)', p_membership_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.customer_portal_account_membership_history
    (membership_id, auth_user_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values
    (v_updated.id, v_updated.auth_user_id, v_updated.tenant_id, v_updated.account_id, v_membership.status, p_to_status, p_reason, p_actor_label);

  if p_to_status in ('suspended', 'revoked') then
    select id into v_legacy_membership_id
    from app.principal_memberships
    where auth_user_id = v_updated.auth_user_id
      and tenant_id = v_updated.tenant_id
      and layer = 'customer_user'
      and customer_account_ref = v_updated.account_id::text
      and status = 'active';

    if found then
      perform app.revoke_principal_membership(v_legacy_membership_id, p_reason, p_actor_label);
    end if;
  elsif p_to_status = 'active' and v_membership.status = 'suspended' then
    perform app.grant_principal_membership(v_updated.auth_user_id, 'customer_user', v_updated.tenant_id, v_updated.account_id::text, p_actor_label);
  end if;

  return v_updated;
end;
$function$;

comment on function app.set_customer_portal_account_membership_status is
  'CPL-300, last-account_admin-guarded by ISS-2026-125 item 3 (20260828193000), step-up-MFA-gated by ISS-2026-125 item 1 (20260901140000): suspend/revoke/reactivate for an existing membership, caller-gated by app.actor_is_active_customer_portal_account_admin on the SAME account_id. The step-up gate fires only for p_to_status IN (suspended, revoked) -- never activate/reactivate -- and is a strict no-op unless the tenant has both turned on MFA and added (CPADM, ManageMembership) to its own additional_high_risk_actions list. Source prompt §24: "Revocation invalidates sessions, saved views, exports, signed URLs and cached summaries" -- every read RPC in this migration re-checks status=''active'' LIVE against this table on every call, never caching it, so revocation takes effect immediately by construction. Also drives the legacy app.principal_memberships row (revoke on suspend/revoke, re-grant on suspended -> active reactivation) so already-shipped legacy consumers lose/regain access in step.';

-- ===========================================================================
-- 4. Grants -- byte-identical to before, CREATE OR REPLACE preserves them
-- automatically; re-asserted explicitly per the standing convention since
-- PLT-118/ERR-2026-004.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.request_mfa_step_up_challenge(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_customer_portal_account_membership_role(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_customer_portal_account_membership_status(uuid, integer, text, text, uuid, text) to authenticated, service_role;
