-- HDN-372 (Step 15, Prompt 372, Tenant Isolation Audit, `CG-S15-HDN-004`) — round 2,
-- found by this same checkpoint's own Tier C security/tenant lens (live-tested) and
-- fixed in the same checkpoint rather than merely registered, since a Tenant Isolation
-- Audit lane fixing a tenant-isolation defect its own review found is squarely within
-- its own charter.
--
-- The Tier C lens ran an independent, wider closure sweep than `20260810000000`'s own
-- (which stopped at the 9 functions it had already found) and live-forced 4 more
-- `SECURITY DEFINER` functions granted `EXECUTE` to `authenticated`, each evaluating
-- authority against a client-supplied actor UUID instead of the verified session
-- identity — the identical root cause `20260810000000` fixed, missed by that
-- migration's own bounded, evidence-driven (not exhaustive) 9-function list:
--
--   * `app.get_notification_preferences` — the direct sibling, in the same migration
--     (`20260719130000_create_notification_engine.sql`), of `app.list_notifications_
--     for_recipient`/`app.count_unread_notifications`, which `20260810000000` already
--     fixed. Live-forced: read a victim tenant's notification channel/locale
--     preferences via a forged `p_actor_auth_user_id`.
--   * `app.get_custom_field_values` — live-forced: read a victim tenant's sensitive
--     custom-field content (`{"secret_field": "..."}`), which the function's own
--     `v_has_sensitive` branch exists specifically to protect and does not, since the
--     branch itself trusts the same forged actor.
--   * `app.list_pending_approval_steps_for_actor` — live-forced: read a victim
--     tenant's pending approval-request steps.
--   * `app.resolve_actor_owner_account_scope` — the direct sibling and, per its own
--     `ATW-016` comment, forerunner of `app.resolve_customer_owner_account_scope`
--     (the `20260810000000` root fix for the `ATW-023` family). Live-forced: read a
--     victim tenant's customer-account owner scope. `LANGUAGE sql`, converted to
--     `LANGUAGE plpgsql` here for the same reason and by the same precedent
--     (`CPL-300`) `20260810000000` already cites for its own two conversions.
--     `app.actor_can_view_owner_scoped_row` calls this function and passes its own
--     `p_auth_user_id` through unmutated (verified: no re-derivation, no alternate
--     resolution branch) — fixing this root therefore also closes the identical gap
--     in that function, which is independently `EXECUTE`-granted to `authenticated`
--     and callable standalone (confirmed: it stays on `rbac-enforcement.sql`'s own
--     `v_expected` AUTHORITY-sweep exemption list for an unrelated, still-correct
--     reason — it has no authority check beyond its own owner-scope predicate and
--     needs none, exactly `app.get_self_employee`'s situation at `20260810000000`;
--     this migration closes its IDENTITY gap, not its exemption from that separate
--     sweep).
--
-- Full disposition, live re-verification transcript, and the corrected total function
-- count: `docs/build-log/full-system-hardening/HDN-372.md` §5.6.
--
-- The same Tier C sweep also surfaced roughly 24 further `SECURITY DEFINER` candidates
-- sharing this shape (mostly boolean/narrow-oracle primitives and CRM readiness/
-- duplicate-detection helpers) that were **not** live-forced against real two-tenant
-- data this checkpoint and are **not** fixed here — bundling an unverified ~24-function
-- change into this migration would repeat the exact scope-creep `20260810000000` itself
-- warned against. Registered instead as `HDN-BLK-014`/`ISS-2026-179`, owner `HDN-373`
-- (Tenant Isolation's own immediate successor lane), with the full candidate list, the
-- 3 that the Tier C lens did spot-check live, and an explicit instruction that the
-- remaining candidates are unverified and must be checked, not assumed, before fixing.
--
-- Regression proof: `scripts/db-tests/rbac-enforcement.sql` extends its `HDN-372`
-- named-list check to all 13 now-fixed functions (position-aware: the assert must be
-- the function's first executable statement, not merely present anywhere in the body —
-- correcting a real weakness the Tier C correctness lens found in the original
-- substring-only check), and adds a genuine live two-session forced-spoof assertion
-- (a real `authenticated`-claiming session, via `request.jwt.claims`, actually calling
-- 4 of the fixed functions and being refused) — the original migration's header claimed
-- this kind of committed evidence existed; it did not, and this migration adds it for
-- real rather than merely correcting the claim.

create or replace function app.get_notification_preferences(p_tenant_id uuid, p_auth_user_id uuid, p_actor_auth_user_id uuid)
returns setof app.notification_preferences
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_actor_auth_user_id <> p_auth_user_id and not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % may not read notification preferences for %', p_actor_auth_user_id, p_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.notification_preferences where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id;
end;
$$;

create or replace function app.get_custom_field_values(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_actor_auth_user_id uuid
)
returns app.custom_field_values
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.custom_field_values;
  v_fields jsonb;
  v_has_sensitive boolean;
  v_object_tenant_id uuid;
  v_object_scope_level text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_custom_field_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.custom_field_values where tenant_id = p_tenant_id and entity_type = coalesce(p_entity_type, 'generic') and entity_id = p_entity_id;
  if not found then
    raise exception 'custom_field_values_not_found: no custom field values for tenant % entity %/%', p_tenant_id, p_entity_type, p_entity_id
      using errcode = 'no_data_found';
  end if;

  select value into v_fields from app.config_items where config_version_id = v_row.config_version_id and key = 'fields';
  select exists (select 1 from jsonb_array_elements(coalesce(v_fields, '[]'::jsonb)) f where coalesce((f ->> 'sensitive')::boolean, false)) into v_has_sensitive;

  if v_has_sensitive and v_row.submitted_by_auth_user_id <> p_actor_auth_user_id then
    select o.tenant_id, o.scope_level into v_object_tenant_id, v_object_scope_level
    from app.config_versions v join app.config_objects o on o.id = v.config_object_id
    where v.id = v_row.config_version_id;

    if not app.check_config_object_authority(v_object_scope_level, v_object_tenant_id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % may not read a sensitive custom-field values row they did not submit', p_actor_auth_user_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return v_row;
end;
$$;

create or replace function app.list_pending_approval_steps_for_actor(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.approval_request_steps
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.check_approval_request_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select s.*
    from app.approval_request_steps s
    join app.approval_requests r on r.id = s.request_id
    where r.tenant_id = p_tenant_id and r.status = 'pending' and s.status = 'active'
      and app.is_eligible_approval_approver(s, p_tenant_id, p_actor_auth_user_id);
end;
$$;

create or replace function app.resolve_actor_owner_account_scope(p_auth_user_id uuid, p_tenant_id uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- HDN-372 round 2: p_auth_user_id is a free parameter naming WHOSE owner-account scope
  -- to resolve -- without this check any authenticated session could pass ANY other
  -- identity's uuid and read that identity's customer-account scope (live-verified IDOR),
  -- the same shape app.resolve_customer_owner_account_scope was fixed for at
  -- 20260810000000. app.actor_can_view_owner_scoped_row calls this function and passes
  -- p_auth_user_id straight through, so it is transitively protected by this fix too.
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  return case
    -- Supreme Admin and any staff (tenant_admin/org_user) membership in this tenant see
    -- every owner, exactly as today -- "staff/tenant-wide actors ... continue to see
    -- tenant-wide."  An actor with no principal_memberships row at all in this tenant
    -- also falls through unrestricted here -- RBAC (OPS:View) remains the real gate for
    -- that case, unchanged from this migration's own pre-existing behavior; only an
    -- actor explicitly holding a customer_user membership is ever narrowed.
    when app.is_supreme_admin(p_auth_user_id) then null
    when exists (
      select 1 from app.principal_memberships
      where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id
        and layer in ('tenant_admin', 'org_user') and status = 'active'
    ) then null
    when exists (
      select 1 from app.principal_memberships
      where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id
        and layer = 'customer_user' and status = 'active'
    ) then coalesce((
      select array_agg(distinct pm.customer_account_ref::uuid)
      from app.principal_memberships pm
      where pm.auth_user_id = p_auth_user_id and pm.tenant_id = p_tenant_id
        and pm.layer = 'customer_user' and pm.status = 'active'
        and pm.customer_account_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ), array[]::uuid[])
    else null
  end;
end;
$$;

comment on function app.resolve_actor_owner_account_scope is
  'ATW-016: null means unrestricted/tenant-wide (staff, Supreme Admin, or no principal membership at all in this tenant); a real (possibly empty) uuid[] means the actor is a customer_user-layer, owner-scoped actor and may only see rows whose owner_account_id is in that array. See design note 6b for the customer_account_ref=owner_account_id::text convention this resolves against. HDN-372 round 2: now asserts the caller-supplied p_auth_user_id is the real session identity before resolving.';

revoke execute on all functions in schema app from public;

grant execute on function app.get_notification_preferences(p_tenant_id uuid, p_auth_user_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.get_custom_field_values(p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.list_pending_approval_steps_for_actor(p_tenant_id uuid, p_actor_auth_user_id uuid) to authenticated, service_role;
grant execute on function app.resolve_actor_owner_account_scope(p_auth_user_id uuid, p_tenant_id uuid) to authenticated, service_role;
