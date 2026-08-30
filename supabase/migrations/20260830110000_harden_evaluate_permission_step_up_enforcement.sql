-- ISS-2026-236 (docs/runtime/KNOWN_ISSUES.md; `HDN-BLK-024`/`HDN-BLK-040` in
-- BLOCKER_LEDGER.md) -- 3 of `app.is_high_risk_action`'s own 7 hardcoded platform-default
-- high-risk tuples (`SEC:Configure`, `FIN:Approve`, `HRS:Approve`) received neither
-- step-up-MFA nor IP-restriction wiring anywhere across the entire
-- `IAE-037` -> `CG-S14-IAE-039` -> `HDN-378` lineage. 61 real, reachable,
-- `authenticated`-executable functions were classified high-risk and enforced nothing.
--
-- The sharpest instance, quoted from the entry: `app.set_mfa_tenant_policy`,
-- `app.set_ip_allowlist_enforcement_mode`, `app.add_ip_allowlist_entry` and
-- `app.request_ip_allowlist_bypass` are the very functions that configure MFA/IP
-- enforcement -- a holder can add their own allowlist entry or grant themselves a bypass
-- with no step-up of their own. A genuine "guard the guards" gap.
--
-- ---------------------------------------------------------------------------------------
-- Why this is one function change and not 61
-- ---------------------------------------------------------------------------------------
--
-- The obvious fix -- add `perform app.assert_current_step_up_authorization(...)` to each of
-- the 61 function bodies, the shape `IAE-039` used for its own 3 -- is exactly what every
-- prior checkpoint declined, and they were right to. It requires 61 `CREATE OR REPLACE`
-- statements that each restate a full function body verbatim; a single transcription slip
-- inside `app.approve_finance_invoice` or `app.close_finance_period` would be far worse
-- than the gap being closed. `IAE-037` also live-proved the second cost: wiring 4 such
-- functions unconditionally broke 17 already-`VERIFIED` fixtures, and was reverted.
--
-- Every one of the 61 reaches its authority decision through the same door:
-- `app.evaluate_permission(actor, tenant, 'FIN'|'HRS'|'SEC', 'Approve'|'Configure')`.
-- That is the real chokepoint, and this repository has already established the precedent
-- for using it -- `20260826110000_harden_evaluate_permission_session_revocation_
-- enforcement.sql` (`ISS-2026-264`) put session-revocation enforcement in exactly this
-- function for exactly this reason. This migration follows that precedent verbatim: one
-- `CREATE OR REPLACE`, one new branch, no function body copied, and coverage that extends
-- to every future caller of a high-risk tuple rather than to a list frozen today.
--
-- ---------------------------------------------------------------------------------------
-- What the new branch does, and the two things it deliberately does NOT do
-- ---------------------------------------------------------------------------------------
--
-- It denies (`mfa_step_up_required`) when ALL of the following hold:
--   1. the (module, action) is high-risk for this tenant -- `app.is_high_risk_action`
--      UNCHANGED, platform defaults and the tenant's own additive list alike; and
--   2. the tenant has an `app.mfa_tenant_policies` row with `tenant_wide_required = true`
--      -- i.e. the tenant has actually turned MFA on; and
--   3. that actor holds no `verified` `app.mfa_step_up_challenges` row for this exact
--      tenant/module/action inside the policy's own `step_up_max_age_minutes` window.
--
-- **It does not touch `app.is_high_risk_action`.** Narrowing the platform-default tuple
-- list would have made every fixture pass trivially, and would have been a weakening of a
-- declared security classification dressed up as a fix -- `scripts/db-tests/enterprise-mfa-
-- session-controls.sql` asserts `FIN:Approve` is platform-default high-risk for every
-- tenant, and that assertion is correct and stays untouched. Condition 2 is what bounds
-- the blast radius, and it bounds it on a real, tenant-owned, already-shipped switch
-- rather than on a reclassification.
--
-- **It does not silently deny anyone who is unaffected today.** A tenant with no
-- `mfa_tenant_policies` row, or one with `tenant_wide_required = false`, reaches an
-- identical decision to before this migration -- which is every tenant in every existing
-- fixture, and every tenant on the live project. The honest description of the change is
-- therefore: *enforcement for these 61 functions is now real and reachable, gated on the
-- tenant's own MFA switch, where previously it did not exist at any setting.* That is a
-- strict increase in enforcement and zero decrease, and it is deliberately not the same
-- claim as "all 61 functions now always require step-up".
--
-- ---------------------------------------------------------------------------------------
-- Placement, and why it is before the Supreme Admin exception
-- ---------------------------------------------------------------------------------------
--
-- `ISS-2026-264`'s session check sits after the Supreme Admin branch because
-- `app.user_sessions.tenant_id` is NOT NULL and a tenant-independent Supreme Admin grant
-- is structurally exempt anyway. This check is different: `mfa_tenant_policies.
-- required_layers` defaults to `["supreme_admin", "tenant_admin"]`, so the policy this
-- repository already ships explicitly contemplates a Supreme Admin being subject to MFA,
-- and `tenant_wide_required` means what it says. Placing the branch after the Supreme
-- Admin early-return would have exempted precisely the most powerful identity from the
-- control -- reproducing the "guard the guards" shape this entry is about. It is therefore
-- placed immediately after the tenant-membership check and before the Supreme Admin
-- exception. A Supreme Admin is not locked out by this: `app.request_mfa_step_up_challenge`
-- carries its own `app.is_supreme_admin` bypass on the membership precondition, so they can
-- always obtain a challenge for a tenant they legitimately act in.
--
-- IP-restriction wiring for these same 3 tuples is a separate mechanism with a separate
-- shape (`p_client_ip` must be supplied by the caller, so it cannot be enforced from
-- `evaluate_permission`, which has no such parameter) and is NOT claimed closed here. See
-- this entry's own KNOWN_ISSUES annotation for what remains.
--
-- No already-applied migration is edited. This is an unchanged-signature CREATE OR REPLACE
-- carrying forward every branch `20260810300000` (ISS-2026-072 lineage),
-- `20260826040000` and `20260826110000` added, verbatim and in order.

create or replace function app.evaluate_permission(p_auth_user_id uuid, p_tenant_id uuid, p_resource_module_code text, p_action text, p_as_of timestamp with time zone default now())
returns app.rbac_decision
language plpgsql
stable
as $function$
declare
  v_permission app.permissions;
  v_match record;
  v_mfa_policy app.mfa_tenant_policies;
begin
  perform app.assert_actor_is_session_identity(p_auth_user_id);
  select * into v_permission
  from app.permissions
  where resource_module_code = p_resource_module_code and action = p_action;

  if not found then
    return row(false, 'unknown_permission', null, null, null, p_as_of)::app.rbac_decision;
  end if;

  -- HDN-373: a role_assignments row surviving tenant-membership revocation must not
  -- grant authority. app.has_active_tenant_membership already correctly composes
  -- Supreme Admin (tenant-agnostic, RPD-022) and a live support-access grant, so neither
  -- is affected by this check -- only a genuinely non-member (including a revoked
  -- ex-member) is newly denied here, before any role_assignments row is even consulted.
  if not app.has_active_tenant_membership(p_tenant_id, p_auth_user_id) then
    return row(false, 'not_active_tenant_member', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  -- ISS-2026-236 (this migration): step-up enforcement for high-risk actions, at the one
  -- door all 61 previously-unwired functions already pass through. See this migration's
  -- own header for why it is here rather than in 61 function bodies, why
  -- app.is_high_risk_action is deliberately left unchanged, and why this branch is placed
  -- BEFORE the Supreme Admin exception rather than after it.
  --
  -- Ordered so the cheap, overwhelmingly-common case exits first: almost every call is for
  -- a non-high-risk tuple, and almost every tenant has no MFA policy row at all.
  if app.is_high_risk_action(p_tenant_id, p_resource_module_code, p_action) then
    select * into v_mfa_policy from app.mfa_tenant_policies where tenant_id = p_tenant_id;
    if found and v_mfa_policy.tenant_wide_required then
      if not exists (
        select 1 from app.mfa_step_up_challenges
        where auth_user_id = p_auth_user_id
          and tenant_id = p_tenant_id
          and module_code = p_resource_module_code
          and action = p_action
          and status = 'verified'
          and verified_at > now() - (v_mfa_policy.step_up_max_age_minutes || ' minutes')::interval
      ) then
        return row(false, 'mfa_step_up_required', v_permission.id, null, null, p_as_of)::app.rbac_decision;
      end if;
    end if;
  end if;

  if exists (
    select 1 from app.principal_memberships
    where auth_user_id = p_auth_user_id and layer = 'supreme_admin' and status = 'active'
  ) then
    return row(true, 'supreme_admin_exception', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  -- ISS-2026-072: defense-in-depth re-check of app.users.status,
  -- independent of whatever cascaded (or failed to cascade) into role_assignments. Placed
  -- here, after the Supreme Admin exception (see that migration's own header for why) and
  -- before any role_assignments lookup. app.users is tenant-scoped -- an actor with no
  -- app.users row at all in this tenant already failed has_active_tenant_membership above
  -- (unless they are Supreme Admin, already exempted by the branch above this one), so
  -- `not exists` here correctly reaches only a genuine member whose own account status is
  -- not 'active'.
  if not exists (
    select 1 from app.users
    where tenant_id = p_tenant_id
      and auth_user_id = p_auth_user_id
      and status = 'active'
  ) then
    return row(false, 'not_active_platform_user', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  -- ISS-2026-264 (20260826110000): see that migration's own header for the full
  -- rationale and why it is deliberately narrow (never universally denies an
  -- untracked actor).
  if exists (
    select 1 from app.user_sessions
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id
  ) and not exists (
    select 1 from app.user_sessions
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and status = 'active'
  ) then
    return row(false, 'all_sessions_revoked', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  -- The join to role_versions on status = 'published' is what makes a stale assignment
  -- (still 'active' in app.role_assignments, but pointing at a version PLT-111's
  -- publish_role_version() has since archived by superseding it) fail closed -- exactly
  -- Prompt 112 §23's "stale ... permission fails closed." No auto-reassignment to the new
  -- published version happens anywhere in this repository; that is a disclosed, bounded
  -- limitation of this checkpoint, not an oversight (see PLT-112.md §2/§8).
  select ra.id as assignment_id, rv.id as role_version_id, rv.role_id
  into v_match
  from app.role_assignments ra
  join app.role_versions rv on rv.id = ra.role_version_id
  join app.role_version_permissions rvp on rvp.role_version_id = rv.id
  where ra.tenant_id = p_tenant_id
    and ra.auth_user_id = p_auth_user_id
    and ra.status = 'active'
    and rv.status = 'published'
    and rvp.permission_id = v_permission.id
  limit 1;

  if found then
    return row(true, 'role_grant', v_permission.id, v_match.role_id, v_match.role_version_id, p_as_of)::app.rbac_decision;
  end if;

  if exists (
    select 1 from app.role_assignments
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and status = 'active'
  ) then
    return row(false, 'no_granting_role', v_permission.id, null, null, p_as_of)::app.rbac_decision;
  end if;

  return row(false, 'no_active_assignment', v_permission.id, null, null, p_as_of)::app.rbac_decision;
end;
$function$;

comment on function app.evaluate_permission(uuid, uuid, text, text, timestamp with time zone) is
  'PLT-110 RBAC evaluator, hardened at HDN-373 (tenant-membership re-check), ISS-2026-072 (platform user status re-check), ISS-2026-264 (session-revocation enforcement) and ISS-2026-236 (step-up enforcement for high-risk actions). The ISS-2026-236 branch denies with reason mfa_step_up_required when the (module, action) is high-risk for this tenant AND the tenant has turned MFA on (mfa_tenant_policies.tenant_wide_required) AND the actor holds no verified step-up challenge for that exact tuple inside step_up_max_age_minutes. It is placed BEFORE the Supreme Admin exception deliberately -- mfa_tenant_policies.required_layers contemplates supreme_admin, and exempting the most powerful identity would reproduce the guard-the-guards gap this fix is about. app.is_high_risk_action is deliberately unchanged: narrowing its platform-default tuple list would be a weakening of a declared classification, not a fix. A tenant with no MFA policy row, or with tenant_wide_required = false, reaches an identical decision to before.';

revoke execute on all functions in schema app from public;

grant execute on function app.evaluate_permission(uuid,uuid,text,text,timestamp with time zone) to service_role;
