-- Track B Batch 8, ISS-2026-125 item 3 (docs/runtime/KNOWN_ISSUES.md): a real, live,
-- unfixed authority gap disclosed at CG-S13-CPL-017 (Prompt 315) and never picked up
-- since -- app.set_customer_portal_account_membership_status (CPL-300,
-- 20260801010000_create_customer_portal_account_scope.sql, latest body in
-- 20260828030000_harden_customer_portal_membership_anti_enumeration.sql, re-confirmed
-- unfixed by direct read of that exact latest body before writing this migration) lets
-- the SOLE active account_admin on an account suspend or revoke themselves (or the
-- account's only other account_admin), leaving the account with ZERO active
-- account_admins and no self-service recovery path: app.grant_initial_customer_portal_
-- account_admin (the one staff-facing bootstrap escape hatch) is a no-op once any row
-- already exists for that identity+account -- it returns the existing (now suspended/
-- revoked) row unchanged, never re-promotes/reactivates it.
--
-- This exact guard shape already exists, one prompt later, on the sibling role-change
-- RPC: app.update_customer_portal_account_membership_role (20260801170000_create_
-- customer_portal_user_management.sql:315-339, design decision 3) row-locks the full
-- active account_admin set for the account before deciding, then rejects a
-- account_admin -> member change that would leave zero. This migration applies the
-- IDENTICAL guard (same lock-then-count shape, same last_account_admin errcode/message)
-- to app.set_customer_portal_account_membership_status's own active -> suspended/revoked
-- transition -- the other way a caller can remove their own admin status. Not a new
-- capability, not a schema change: a genuine CREATE OR REPLACE FUNCTION against an
-- already-shipped RPC's own existing signature, so its ACL (already authenticated/
-- service_role, granted once in 20260801010000) carries forward automatically, no new
-- GRANT/REVOKE needed, mirroring every other harden_*.sql in this repository.
--
-- Scope of the guard, deliberately narrow (mirrors the sibling function's own decision 3
-- exactly): fires ONLY when the membership being transitioned is CURRENTLY an ACTIVE
-- account_admin (v_membership.role = 'account_admin' and v_membership.status = 'active')
-- AND the target status is 'suspended' or 'revoked'. A membership that is already
-- suspended/revoked (not counted as an active admin either way) may still be pushed
-- suspended -> revoked freely; a plain 'member' target is never touched by this guard at
-- all (role is read-only here, never mutated by this function); reactivating
-- suspended -> active is never blocked either (adding an admin back can only ever
-- increase the active-admin count, never remove the last one).
--
-- Every other line of this function (mandatory reason, anti-enumeration
-- customer_portal_membership_not_found shape from ISS-2026-116/20260828030000, the
-- accept_required invited->active guard, the CPL-324 NULL-bypass-proof optimistic-
-- concurrency check repeated on both the early guard and the UPDATE's own WHERE clause,
-- and the Tier C legacy app.principal_memberships propagation) is byte-identical to its
-- own already-applied body in 20260828030000 -- confirmed by diff against that file
-- before writing this one. Only the new guard block is inserted, placed after the
-- version check and before the UPDATE, matching where the sibling function places its
-- own equivalent guard (after its version check, before its UPDATE).
--
-- Regression coverage: scripts/db-tests/customer-user-management.sql gains a new,
-- self-contained test block mirroring its own existing "last-account_admin guard"
-- coverage for app.update_customer_portal_account_membership_role -- a sole admin
-- (Beta, already fixture-established, untouched) cannot suspend or revoke themselves;
-- a fresh, dedicated 2-admin account (Gamma) proves the full shape the issue itself
-- asked for -- one admin is suspended (a non-last admin, allowed, leaving the true
-- last), the true last is then rejected on both suspend and revoke, and a plain
-- member is never blocked by this guard.

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
as $$
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

  -- Mandatory non-empty reason for suspend/revoke, mirroring app.hold_credit_
  -- profile's own mandatory-reason discipline -- checked before touching the
  -- row, same ordering that function itself uses.
  if p_to_status in ('suspended', 'revoked') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to % a customer portal membership', p_to_status using errcode = 'not_null_violation';
  end if;

  select * into v_membership from app.customer_portal_account_memberships where id = p_membership_id for update;
  if not found then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  -- ISS-2026-116 Track B Batch 4 fix: raise the identical customer_portal_
  -- membership_not_found (errcode no_data_found) as the not-found branch
  -- above, not a distinguishable insufficient_authority, mirroring app.get_
  -- customer_inventory_balance's own single anti-enumeration error shape --
  -- a real-but-wrong-actor p_membership_id is no longer observably different
  -- from a nonexistent one.
  if not app.actor_is_active_customer_portal_account_admin(v_membership.tenant_id, v_membership.account_id, p_actor_auth_user_id) then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  -- invited -> active is exclusively app.accept_customer_portal_invite's own
  -- job (self-accept only, business rule above) -- an admin may not force it
  -- here even though the underlying transition trigger would otherwise permit
  -- invited -> active.
  if v_membership.status = 'invited' and p_to_status = 'active' then
    raise exception 'accept_required: an invited membership may only be activated by the invited identity itself, via app.accept_customer_portal_invite'
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
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

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
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

  -- Tier C security-rls review fix (Finding 2): propagate suspend/revoke/
  -- reactivate to the legacy app.principal_memberships row this migration's
  -- own accept/bootstrap flow grants -- otherwise already-shipped consumers
  -- of app.resolve_customer_owner_account_scope (ATW-023 WMS/inventory, the
  -- ticketing customer channel's app._is_ticket_requester_party) and app.
  -- actor_holds_customer_user_layer (this migration's own portal-entry
  -- guard) keep admitting a suspended/revoked member indefinitely -- a
  -- live-verified bypass both lenses independently reproduced. Mirrors app.
  -- transition_user_status' own established HRT-295 pattern of driving
  -- app.revoke_principal_membership off the matching active row, never
  -- re-derived. principal_memberships' own revoke is terminal (no
  -- suspend-in-place primitive exists there), so a later suspended -> active
  -- reactivation through this same RPC re-grants a fresh row via app.grant_
  -- principal_membership (idempotent, and a new row is exactly how that
  -- table's own re-grant-after-revoke shape already works).
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
$$;

comment on function app.set_customer_portal_account_membership_status is
  'CPL-300: suspend/revoke/reactivate, caller-gated by app.actor_is_active_customer_portal_account_admin on the SAME account_id -- a caller who is not an active account_admin on this membership''s own account now receives the identical customer_portal_membership_not_found (errcode no_data_found) as a genuinely nonexistent membership id, ISS-2026-116 Track B Batch 4 fix (previously a distinguishable insufficient_authority), mirroring app.get_customer_inventory_balance''s own single anti-enumeration error shape (design decision 5). Source prompt §24: "Revocation invalidates sessions, saved views, exports, signed URLs and cached summaries" -- every read RPC in this migration re-checks status=''active'' LIVE against this table on every call, never caching it, so revocation takes effect immediately by construction (design decision 7). Tier C review fix: ALSO drives the legacy app.principal_memberships row this migration''s own accept/bootstrap flow grants (revoke on suspend/revoke, re-grant on suspended -> active reactivation) so already-shipped legacy consumers (ATW-023 WMS/inventory, the ticketing customer channel, this migration''s own portal-entry guard) lose/regain access in step, not only this migration''s own resolver -- no separate session-invalidation mechanism is built beyond that, none exists anywhere in this repository. CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth. Track B Batch 8, ISS-2026-125 item 3 fix: the SOLE active account_admin on an account may no longer suspend or revoke themselves (or the account''s only other account_admin) -- last_account_admin (errcode check_violation), row-locking the account''s full active-admin set first, the identical guard app.update_customer_portal_account_membership_role already applies to its own account_admin -> member transition (design decision 3 of 20260801170000).';
