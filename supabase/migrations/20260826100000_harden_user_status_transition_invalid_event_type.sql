-- ISS-2026-263 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- app.transition_user_status's own event_type CASE mapping has an `else` fallback that
-- assigns the raw target status value (e.g. 'suspended', 'active', 'invited') as the
-- event_type, instead of one of the verb-form values
-- app.user_lifecycle_history_event_type_check actually accepts. Live-reproduced at
-- HDN-384's own Tier C review: any call outside the 5 explicit (from_status, to_status)
-- pairs this function recognizes -- including any true no-op call where p_new_status
-- already equals the user's current status -- deterministically fails with a spurious
-- CHECK-constraint violation on the history insert, not a clear, purpose-built error.
--
-- Fixed exactly as this entry's own text proposed: reject an unrecognized transition
-- outright, with a clear error, before ever attempting the history insert -- never widen
-- the CASE to accept every possible (from_status, to_status) combination as if it were a
-- legitimate business transition (most combinations, e.g. suspended -> invited, are not
-- real transitions this domain supports; silently mapping them to a synthetic event type
-- would hide that rather than surface it). This mirrors this repository's own established
-- "reject with a clear error" convention already used elsewhere for exactly this shape of
-- guard (see e.g. advanced-tms-label-barcode-operations.sql's own `invalid_status_transition`
-- regression, a different function using the identical error-code convention).
create or replace function app.transition_user_status(
  p_id uuid,
  p_new_status text,
  p_reason text,
  p_requested_by text
)
returns app.users
language plpgsql
as $$
declare
  v_current app.users;
  v_updated app.users;
  v_other_active_admins integer;
  v_event_type text;
  v_membership record;
  v_role_assignment record;
begin
  select * into v_current from app.users where id = p_id;
  if not found then
    raise exception 'user_not_found: no user %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.status = 'active' and p_new_status in ('suspended', 'revoked') then
    if exists (
      select 1 from app.principal_memberships
      where auth_user_id = v_current.auth_user_id and tenant_id = v_current.tenant_id
        and layer = 'tenant_admin' and status = 'active'
    ) then
      select count(*) into v_other_active_admins
      from app.principal_memberships pm
      join app.users u on u.auth_user_id = pm.auth_user_id and u.tenant_id = pm.tenant_id
      where pm.tenant_id = v_current.tenant_id and pm.layer = 'tenant_admin' and pm.status = 'active'
        and u.status = 'active' and u.id <> p_id;

      if v_other_active_admins = 0 then
        raise exception 'last_critical_admin: cannot % the tenant''s only active tenant admin', p_new_status
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  v_event_type := case
    when v_current.status = 'invited' and p_new_status = 'revoked' then 'cancel_invite'
    when v_current.status = 'invited' and p_new_status = 'active' then 'activate'
    when v_current.status = 'active' and p_new_status = 'suspended' then 'suspend'
    when v_current.status = 'suspended' and p_new_status = 'active' then 'reactivate'
    when v_current.status = 'revoked' and p_new_status = 'active' then 'rehire_reactivate'
    when p_new_status = 'revoked' then 'revoke'
    else null
  end;

  -- ISS-2026-263 fix: every combination not recognized above -- including a true no-op
  -- (p_new_status already equals v_current.status) -- is rejected here, with a clear
  -- error naming both statuses, instead of silently falling through to a raw-status
  -- event_type value that would only be caught downstream by the history table's own
  -- CHECK constraint with a much less legible error.
  if v_event_type is null then
    raise exception 'invalid_status_transition: % -> % is not a recognized user status transition (this includes a no-op call where the target status already equals the current status)', v_current.status, p_new_status
      using errcode = 'check_violation';
  end if;

  update app.users
  set status = p_new_status,
      activated_at = case when p_new_status = 'active' and v_current.activated_at is null then now() else v_current.activated_at end,
      suspended_at = case when p_new_status = 'suspended' then now() else v_current.suspended_at end,
      suspended_reason = case when p_new_status = 'suspended' then p_reason else v_current.suspended_reason end,
      revoked_at = case when p_new_status = 'revoked' then now() else v_current.revoked_at end,
      revoked_reason = case when p_new_status = 'revoked' then p_reason else v_current.revoked_reason end
  where id = p_id
  returning * into v_updated;

  insert into app.user_lifecycle_history (user_id, tenant_id, event_type, from_status, to_status, reason, requested_by)
  values (p_id, v_current.tenant_id, v_event_type, v_current.status, p_new_status, p_reason, p_requested_by);

  -- HRT-295 / ISS-2026-108 amendment: also syncs the underlying
  -- app.tenant_user_identities linkage back to 'active' -- and records a real
  -- history row for it -- when THIS transition is the one deliberately-added
  -- revoked -> active edge. The pre-existing invited -> active sync is unchanged
  -- in shape (still no history row for that pre-existing branch, matching its
  -- own established, unmodified behavior).
  if p_new_status = 'active' and v_current.status in ('invited', 'revoked') then
    update app.tenant_user_identities
    set status = 'active'
    where auth_user_id = v_current.auth_user_id and tenant_id = v_current.tenant_id and status = v_current.status;

    if v_current.status = 'revoked' then
      insert into app.tenant_user_identity_history (auth_user_id, tenant_id, from_status, to_status, reason, requested_by)
      values (v_current.auth_user_id, v_current.tenant_id, 'revoked', 'active', p_reason, p_requested_by);
    end if;
  end if;

  if p_new_status = 'revoked' then
    if exists (
      select 1 from app.tenant_user_identities
      where auth_user_id = v_current.auth_user_id and tenant_id = v_current.tenant_id and status <> 'revoked'
    ) then
      perform app.revoke_auth_identity(v_current.auth_user_id, v_current.tenant_id, 'user offboarded: ' || p_reason, p_requested_by);
    end if;

    for v_membership in
      select id from app.principal_memberships
      where auth_user_id = v_current.auth_user_id and tenant_id = v_current.tenant_id and status = 'active'
    loop
      perform app.revoke_principal_membership(v_membership.id, 'user offboarded: ' || p_reason, p_requested_by);
    end loop;
  end if;

  -- HRT-295 / ISS-2026-072 fix (the role_assignments half, previously OPEN, High)
  -- -- see this migration's own header. Fixed here, centrally, for EVERY current
  -- and future caller: both 'suspended' (a temporary authority freeze) and
  -- 'revoked' (permanent, until a genuine rehire reactivates) now strip every
  -- ACTIVE app.role_assignments row this identity holds in this tenant. Re-grant
  -- is always a separate, explicit, governed act
  -- (app.request_onboarding_access_provisioning) -- never an automatic side
  -- effect of this status flip.
  if p_new_status in ('suspended', 'revoked') then
    for v_role_assignment in
      select id from app.role_assignments
      where tenant_id = v_current.tenant_id and auth_user_id = v_current.auth_user_id and status = 'active'
    loop
      perform app.revoke_role_assignment(v_role_assignment.id, p_reason, p_requested_by);
    end loop;
  end if;

  return v_updated;
end;
$$;
