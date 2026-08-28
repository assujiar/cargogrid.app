-- Track B Batch 4, ISS-2026-116 (docs/runtime/KNOWN_ISSUES.md): app.accept_customer_
-- portal_invite / app.set_customer_portal_account_membership_status each raise a
-- distinguishable customer_portal_membership_not_found (errcode no_data_found) for a
-- nonexistent p_membership_id vs. a distinguishable insufficient_authority (errcode
-- insufficient_privilege) for a real-but-wrong-actor p_membership_id -- deviating from
-- the ATW-023 (app.get_customer_inventory_balance et al., 20260730310000) precedent of
-- raising the SAME anti-enumeration error regardless of true cause. Confirmed still
-- open by direct read of both functions' true latest bodies (CREATE OR REPLACE FUNCTION
-- in 20260801260000_harden_customer_portal_optimistic_concurrency_null_bypass.sql, the
-- newest migration touching either function; the only other file referencing either
-- name, 20260826000000_create_public_api_data_wrappers.sql, is a thin PostgREST
-- pass-through wrapper that does not alter either body).
--
-- Root cause: both functions look up the row first (raising customer_portal_membership_
-- not_found on a genuine miss), then separately check the caller's own relationship to
-- the row (raising insufficient_authority on a real-but-wrong-actor miss) -- two
-- observably different error shapes for "you may not see this membership," letting a
-- caller who already holds a candidate membership id distinguish "this id does not
-- exist" from "this id exists but is not yours," an oracle ATW-023's own precedent
-- (app.get_customer_inventory_balance/app.get_customer_outbound_order,
-- 20260730310000:392-397/653-657) deliberately collapses into one identical error.
--
-- As the issue entry itself already discloses, this is low-severity and not a live
-- exploitation path: p_membership_id is a random, non-guessable uuid the caller must
-- already possess (from their own invite notification) or already have legitimate
-- visibility into via app.list_customer_portal_account_memberships (itself identity-
-- checked). Fixed here anyway per the entry's own recommended remediation, as a bounded,
-- same-signature consistency fix -- no new capability, no schema change.
--
-- Fix: CREATE OR REPLACE FUNCTION against both functions, changing ONLY the
-- insufficient_authority raise in each function's own wrong-actor branch to the
-- identical customer_portal_membership_not_found message/errcode already used by that
-- same function's own not-found branch immediately above it. Every other line of both
-- functions (including the CPL-324 NULL-bypass optimistic-concurrency fix) is
-- byte-identical to its own already-applied body in 20260801260000. No other insufficient_
-- authority raise in either function is touched (set_customer_portal_account_membership_
-- status's own invalid_status/reason_required/accept_required/stale_version branches are
-- unaffected -- only the "not an active account_admin on this account" authority check
-- collapses into the not-found shape, matching what a caller who does not already hold
-- this membership id can observe either way).
--
-- No new GRANT/REVOKE needed (CREATE OR REPLACE on an identical, already-existing
-- signature preserves the existing ACL, mirroring every other harden_*.sql in this
-- repository).
--
-- Regression coverage: scripts/db-tests/customer-portal-scope.sql already asserts
-- 'insufficient_authority%' for both of these functions' own wrong-actor branches
-- (lines ~300-304 for accept_customer_portal_invite, ~540-544 for
-- set_customer_portal_account_membership_status) -- those two assertions are updated in
-- the same pass to expect 'customer_portal_membership_not_found%' instead, since they
-- were directly testing the exact pre-fix behavior this migration changes. A new
-- assertion is also added confirming the not-found and wrong-actor branches are now
-- byte-identical in message text, mirroring how ATW-023's own db-test proves its single
-- anti-enumeration shape.

-- ---------------------------------------------------------------------------
-- 1/2. app.accept_customer_portal_invite (CPL-300; verbatim current body from
-- 20260801260000_harden_customer_portal_optimistic_concurrency_null_bypass.sql, with
-- exactly the wrong-actor raise changed)
-- ---------------------------------------------------------------------------

create or replace function app.accept_customer_portal_invite(
  p_membership_id uuid,
  p_expected_version integer,
  p_auth_user_id uuid
)
returns app.customer_portal_account_memberships
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_membership app.customer_portal_account_memberships;
  v_updated app.customer_portal_account_memberships;
begin
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  select * into v_membership from app.customer_portal_account_memberships where id = p_membership_id for update;
  if not found then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  -- Business rule (source prompt §"RPCs to create" item 4): only the identity
  -- the invite names may accept it -- a raw self-row-identity equality check,
  -- the same class app.get_self_employee/app.is_ticket_queue_member already
  -- document as correct-by-design (design decision 10).
  --
  -- ISS-2026-116 Track B Batch 4 fix: raise the identical customer_portal_
  -- membership_not_found (errcode no_data_found) as the not-found branch
  -- above, not a distinguishable insufficient_authority, mirroring app.get_
  -- customer_inventory_balance's own single anti-enumeration error shape --
  -- a real-but-wrong-actor p_membership_id is no longer observably different
  -- from a nonexistent one.
  if v_membership.auth_user_id <> p_auth_user_id then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  -- CPL-324 Tier C fix: p_expected_version = NULL no longer silently
  -- bypasses this guard.
  if p_expected_version is null or v_membership.record_version <> p_expected_version then
    raise exception 'stale_version: customer portal membership % expected version % but found %', p_membership_id, p_expected_version, v_membership.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_membership.status <> 'invited' then
    raise exception 'invalid_transition: customer portal membership % is %, only a pending invite can be accepted', p_membership_id, v_membership.status
      using errcode = 'check_violation';
  end if;

  -- CPL-324 Tier C fix: repeat the version predicate as defense-in-depth.
  update app.customer_portal_account_memberships
  set status = 'active', accepted_at = now()
  where id = p_membership_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: customer portal membership % was concurrently modified (expected version %)', p_membership_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.customer_portal_account_membership_history
    (membership_id, auth_user_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values
    (v_updated.id, v_updated.auth_user_id, v_updated.tenant_id, v_updated.account_id, 'invited', 'active', 'invite accepted', p_auth_user_id::text);

  -- Tier C security-rls review fix (moved from app.invite_customer_portal_
  -- user, see that function's own comment): the Layer-4 CHECK-required app.
  -- principal_memberships marker (design decision 2) is granted HERE, on
  -- genuine acceptance, not at invite time -- idempotent, safe to call every
  -- time. This is the point at which the identity first becomes entitled to
  -- live WMS/inventory (ATW-023) and portal-entry (app.actor_holds_
  -- customer_user_layer) access through the legacy resolver.
  perform app.grant_principal_membership(v_updated.auth_user_id, 'customer_user', v_updated.tenant_id, v_updated.account_id::text, v_updated.invited_by);

  return v_updated;
end;
$$;

comment on function app.accept_customer_portal_invite is
  'CPL-300: invited -> active only, by the invited identity itself. p_auth_user_id must equal the row''s own auth_user_id (raises customer_portal_membership_not_found otherwise, ISS-2026-116 Track B Batch 4 fix -- previously a distinguishable insufficient_authority) -- a forged/copied auth_user_id on accept is rejected, indistinguishably from a nonexistent membership id, mirroring app.get_customer_inventory_balance''s own single anti-enumeration error shape. Optimistic-concurrency record_version check (stale_version), mirroring app.decide_overtime_request''s own version-check shape. Grants the legacy app.principal_memberships marker here (Tier C review fix, moved from app.invite_customer_portal_user) -- an invited-but-not-yet-accepted identity holds no legacy WMS/inventory or portal-entry access. CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth, matching the pattern already used by app.unlink_ticket_portal_record/app.update_customer_portal_account_membership_role and every CPL-320..323 mutation.';

-- ---------------------------------------------------------------------------
-- 2/2. app.set_customer_portal_account_membership_status (CPL-300; verbatim
-- current body from 20260801260000_harden_customer_portal_optimistic_
-- concurrency_null_bypass.sql, with exactly the wrong-actor raise changed)
-- ---------------------------------------------------------------------------

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
  'CPL-300: suspend/revoke/reactivate, caller-gated by app.actor_is_active_customer_portal_account_admin on the SAME account_id -- a caller who is not an active account_admin on this membership''s own account now receives the identical customer_portal_membership_not_found (errcode no_data_found) as a genuinely nonexistent membership id, ISS-2026-116 Track B Batch 4 fix (previously a distinguishable insufficient_authority), mirroring app.get_customer_inventory_balance''s own single anti-enumeration error shape (design decision 5). Source prompt §24: "Revocation invalidates sessions, saved views, exports, signed URLs and cached summaries" -- every read RPC in this migration re-checks status=''active'' LIVE against this table on every call, never caching it, so revocation takes effect immediately by construction (design decision 7). Tier C review fix: ALSO drives the legacy app.principal_memberships row this migration''s own accept/bootstrap flow grants (revoke on suspend/revoke, re-grant on suspended -> active reactivation) so already-shipped legacy consumers (ATW-023 WMS/inventory, the ticketing customer channel, this migration''s own portal-entry guard) lose/regain access in step, not only this migration''s own resolver -- no separate session-invalidation mechanism is built beyond that, none exists anywhere in this repository. CPL-324 Tier C fix (integrated verification): p_expected_version=NULL no longer silently bypasses the version check -- the early guard now treats NULL as automatically stale, and the UPDATE''s own WHERE clause repeats the record_version predicate (IF NOT FOUND raises stale_version) as defense-in-depth.';
