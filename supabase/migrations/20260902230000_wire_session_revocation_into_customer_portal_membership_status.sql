-- ISS-2026-125 item 2 (docs/runtime/KNOWN_ISSUES.md): CPL-315's own
-- app.set_customer_portal_account_membership_status never composed with the
-- real, applied IAE-027 session/API-key revocation primitives
-- (app.user_sessions / app.revoke_user_session / app.revoke_all_actor_sessions,
-- 20260807100000) -- suspending or revoking a customer-portal membership left
-- that identity's own live sessions and API keys untouched, relying solely on
-- this capability's own per-call live authority re-check to eventually deny
-- them. This migration composes the real primitives, additively.
--
-- Design decisions (verified live against pg_get_functiondef before writing,
-- not assumed from migration file text):
--
-- 1. app.revoke_all_actor_sessions itself is NOT called. Its live body
--    (20260807100000, widened by 20260831270000 for the IP-allowlist gate)
--    unconditionally requires the ACTING identity to hold staff SEC:Configure
--    via app.evaluate_permission -- a permission model that never applies to
--    the customer_user layer (ADR-0024 Part B: this whole capability's own
--    ordinary authority check, app.actor_is_active_customer_portal_account_
--    admin, is a Layer-4-only chain that never touches app.evaluate_permission
--    / app.permissions at all). Every legitimate caller of THIS function
--    already passed that exact check above in this same function body before
--    reaching this branch, and therefore structurally can never hold
--    SEC:Configure. Calling app.revoke_all_actor_sessions as the entry's own
--    literal text first suggested would make every real suspend/revoke raise
--    insufficient_authority -- the identical "mismatched pair" class item 1's
--    own fix (20260901140000) already warned against for a different pair of
--    primitives. Instead this composes the SAME underlying primitives that
--    function itself uses -- the identical app.user_sessions status flip, and
--    the existing, unmodified app.revoke_api_key (PLT-129) -- gated by the
--    authority this call has already established, never a new or widened
--    RBAC surface on the shared staff-facing Enterprise Security primitive.
-- 2. API-key revocation is filtered on customer_actor_auth_user_id, never
--    created_by_auth_user_id (the column app.revoke_all_actor_sessions itself
--    filters on). IAE-010 (20260804020000) documents these as deliberately
--    different identities: created_by_auth_user_id is whoever PROVISIONED the
--    key (sometimes a tenant admin, acting on a customer contact's behalf);
--    customer_actor_auth_user_id is the REAL identity every downstream
--    Customer Portal call the key makes dispatches as. For this specific
--    capability -- revoking a named identity's own portal access -- the
--    correct filter is the identity the key actually authorizes as.
--    app.revoke_all_actor_sessions's own created_by_auth_user_id filter would
--    silently miss exactly that admin-provisioned-on-behalf-of case for this
--    identity; using it here would be a narrower, incorrect composition, not
--    a faithful one.
-- 3. API-key revocation is further scoped to customer_account_id =
--    v_updated.account_id (the account this membership transition concerns),
--    not every account-scoped key this identity holds tenant-wide. app.
--    customer_portal_account_memberships is a genuine many-to-many grant --
--    "one row per (tenant, identity, account)" (20260801010000's own table
--    comment) -- so the same auth_user_id can hold a separate, unrelated,
--    still-active membership on a DIFFERENT account in this same tenant.
--    app.revoke_api_key re-checks app.check_api_key_manage_authority(tenant,
--    key.customer_account_id, actor) itself; an unscoped loop would attempt
--    to revoke a key scoped to an account this actor does not administer,
--    raising insufficient_authority INSIDE this same transaction and rolling
--    back the membership status change itself as a side effect -- a real
--    defect this scoping avoids, not a hypothetical one.
-- 4. Session revocation has no equivalent account-scoping available: app.
--    user_sessions (20260807100000) carries only (tenant_id, auth_user_id),
--    no account_id -- session tracking is deliberately tenant+identity
--    granular, not account granular, matching the primitive's own real shape.
--    Disclosed plainly, not silently narrowed: revoking one membership's
--    status revokes ALL of that identity's active sessions in this tenant,
--    including any used for a separate, unrelated, still-active membership on
--    a different account of the same tenant, if one exists. Narrowing this
--    further would require a structural change to app.user_sessions itself
--    (adding account granularity), out of this bounded fix's own scope.
-- 5. Reactivation is never gated here, matching item 1's own established
--    precedent (20260901140000): reactivation restores access, it does not
--    remove it, so there is nothing to revoke.
-- 6. What this still does NOT do, disclosed honestly rather than implied:
--    app.revoke_user_session/app.revoke_all_actor_sessions (and this
--    composition, which reuses their same app.user_sessions status flip)
--    invalidate the real, PERSISTED app.user_sessions.status signal only.
--    None of them invalidate a live Supabase JWT/refresh token -- that
--    requires the external Supabase Admin API (auth.admin.signOut), which
--    IAE-027's own design decision 4 already disclosed as not performed by
--    any function in this family, this one included. A suspended/revoked
--    identity's already-issued access token remains cryptographically valid
--    until it naturally expires; what is genuinely new here is that the
--    PERSISTED session/API-key registry now reflects the revocation
--    immediately (for any caller that checks it) instead of never being
--    written at all for this capability.

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
  v_session_revoked_count integer;
  v_api_key_id uuid;
  v_api_keys_revoked_count integer := 0;
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

    -- ISS-2026-125 item 2: compose with the real IAE-027 session/API-key
    -- revocation primitives. See this migration's own header comment for why
    -- app.revoke_all_actor_sessions is not called directly, and for the
    -- filtering/scoping decisions below.
    update app.user_sessions
    set status = 'revoked', revoked_at = now(), revoked_reason = p_reason, revoked_by = p_actor_label
    where tenant_id = v_updated.tenant_id and auth_user_id = v_updated.auth_user_id and status = 'active';
    get diagnostics v_session_revoked_count = row_count;

    for v_api_key_id in
      select id from app.api_keys
      where tenant_id = v_updated.tenant_id
        and customer_actor_auth_user_id = v_updated.auth_user_id
        and customer_account_id = v_updated.account_id
        and status = 'active'
    loop
      perform app.revoke_api_key(v_api_key_id, p_reason, p_actor_auth_user_id, p_actor_label);
      v_api_keys_revoked_count := v_api_keys_revoked_count + 1;
    end loop;

    perform app.capture_audit_event(
      v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_customer_portal_membership_sessions',
      'app.user_sessions', v_updated.auth_user_id, 'success', p_reason, null,
      jsonb_build_object('sessions_revoked', v_session_revoked_count, 'api_keys_revoked', v_api_keys_revoked_count, 'membership_id', v_updated.id)
    );
  elsif p_to_status = 'active' and v_membership.status = 'suspended' then
    perform app.grant_principal_membership(v_updated.auth_user_id, 'customer_user', v_updated.tenant_id, v_updated.account_id::text, p_actor_label);
  end if;

  return v_updated;
end;
$$;

comment on function app.set_customer_portal_account_membership_status is
  'CPL-300, hardened by ISS-2026-125 items 1-3 and this migration''s own item 2: suspend/revoke now also revokes the identity''s own active app.user_sessions rows (tenant+identity scoped -- the primitive carries no account granularity) and their active API keys scoped to THIS account (customer_actor_auth_user_id + customer_account_id, never created_by_auth_user_id -- see header comment on 20260902230000). Does not invalidate an already-issued Supabase JWT/refresh token (external Admin API, not performed here or anywhere in this repository yet). Reactivation is never gated or session-revoked.';
