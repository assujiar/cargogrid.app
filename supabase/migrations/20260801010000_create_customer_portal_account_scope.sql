-- Phase 8 capability CPL-300 (CG-S13-CPL-002, Prompt 300, "Customer User Scope").
-- The foundational Layer 4 scope primitive every later Phase 8 capability prompt
-- (301-327) composes -- ADR-0024's own §"Downstream impact": "every Phase 8 prompt
-- from 300 onward that needs customer read access builds a SECURITY DEFINER RPC
-- pair, never a raw-RLS reopen (Part A)."
--
-- ===========================================================================
-- Design decisions (cited, not re-derived -- 00_EXECUTION_INDEX.md §3 item 5)
-- ===========================================================================
--
-- 1. **No new "company"/"site" table.** `app.accounts` (COM-155,
--    20260724290000_create_commercial_customer_account_conversion.sql, ADR-0018)
--    is the one canonical customer/account/site master -- flat, self-referencing
--    `parent_account_id`. "Company," "account," and "site" are all the SAME row
--    shape, related by `parent_account_id`. Per `docs/build-log/phase-07/
--    HRT-287.md` §4's own established precedent (itself citing ADR-0018), parent
--    -> child scope is explicitly NON-CASCADING: a membership on a parent account
--    never implies access to a child account. Every `app.accounts` row a customer
--    should see needs its OWN explicit grant row in the new table below.
-- 2. **A real many-to-many grant table, `app.customer_portal_account_memberships`,
--    is new.** `app.principal_memberships.customer_account_ref` (PLT-108,
--    20260716100825_create_principal_memberships.sql) is a single free-text
--    field -- sufficient as the Layer-4 CHECK-constraint-required marker
--    (`principal_memberships_layer_scope_shape`) that a `customer_user` layer
--    grant must carry SOME customer_account_ref, but not sufficient to model a
--    single identity holding independent, differently-roled grants across
--    several accounts/sites. It is NOT removed or renamed -- it stays exactly as
--    PLT-108 built it, and every grant this migration's own RPCs make against it
--    (via `app.grant_principal_membership`) is still a real, additive use of it,
--    never a bypass.
-- 3. **Read access shape follows ADR-0024 Part A exactly**, mirroring
--    `20260730310000_create_advanced_tms_customer_inventory_access.sql`'s (ATW-023)
--    own house style read in full before this migration was written: every
--    customer-facing read is a new SECURITY DEFINER RPC, deny-by-default, no raw
--    RLS reopened for either new table (RLS enabled, `authenticated` granted
--    NOTHING directly -- mirrors `app.principal_memberships`'s own convention,
--    grant select/insert/update/delete to `service_role` only).
-- 4. **`app.resolve_customer_account_scope` is additive, not a replacement.**
--    `app.resolve_customer_owner_account_scope` (ATW-242, same source file) stays
--    byte-for-byte unchanged -- it is still correct for its own already-shipped
--    WMS/inventory callers. This migration's own resolver composes it (a real
--    function call, not a re-derivation of its predicate) UNION the new grant
--    table, so the legacy single-account shape and the new multi-account/site
--    shape are never two independently-evolving implementations of the same
--    logic.
-- 5. **Write authority is Layer-4-only, never staff RBAC**, per ADR-0024 Part B's
--    own general principle applied here: an account_admin's authority to
--    invite/suspend/revoke a member of THEIR OWN account is a fact about the new
--    grant table itself (`app.actor_is_active_customer_portal_account_admin`,
--    the one shared authority primitive every write/list RPC below composes,
--    never re-derived -- mirrors ATW-023's own "customer_warehouse_eligibility_
--    active is the ONE shared eligibility predicate" design note 4), never
--    `app.evaluate_permission`/staff RBAC. The one deliberate exception is the
--    bootstrap RPC (`app.grant_initial_customer_portal_account_admin`, decision 6
--    below) -- there is no existing account_admin to authorize the very first
--    grant on a brand-new account, so that one RPC is staff-gated instead, on
--    `CPT:Create` (see decision 6).
-- 6. **`CPT:Create` is a new permission row, not a new module.** `app.
--    entitlement_modules` already carries `CPT` ("Customer Portal",
--    20260716094432_create_entitlements.sql:30) and `app.permissions` already
--    carries `('View','CPT',...)`/`('Export','CPT',...)`/`('Download','CPT',...)`
--    (20260716103445_create_roles_permissions.sql:69) but no `Create` action for
--    it -- checked before inventing a new module code, per this task's own
--    instruction. Adding `('Create','CPT','standard',false)` is a plain,
--    additive `insert` into an already-applied table, the identical technique
--    `20260724300000_create_commercial_customer_contract_pricing.sql`
--    (`'View margin'`/`COM`) and `20260727150000_create_operations_exception_
--    escalation.sql` (`'View cost'`/`OPS`) already used to add a new action to an
--    existing module from a later migration.
-- 7. **Revocation takes effect immediately by construction, no separate
--    invalidation mechanism.** Per the source prompt's own §24 business rule
--    ("Revocation invalidates sessions, saved views, exports, signed URLs and
--    cached summaries") -- every read RPC below re-checks `status = 'active'`
--    LIVE against this table on every call, never caching it (see the one-line
--    comment on `app.set_customer_portal_account_membership_status` below,
--    repeated here since no session-invalidation primitive exists anywhere in
--    this repository to build one with, and building a new one would be a new,
--    out-of-scope primitive per this task's own instruction).
-- 8. **Status-transition/touch-row triggers mirror `app.users`
--    (20260716102620_create_users.sql, `app.enforce_user_status_transition`) and
--    `app.principal_memberships` (`app.touch_principal_membership_row`) exactly**
--    -- one combined touch trigger (updated_at + record_version), matching every
--    real precedent in this repository (principal_memberships/users/
--    tenant_user_identities each combine both concerns into a single trigger
--    function, never two separate ones) rather than the source prompt's own
--    looser "an updated_at-touch trigger and a record_version-increment
--    trigger" phrasing taken as two literal triggers.
-- 9. **Unique constraint is a plain `(tenant_id, auth_user_id, account_id)` key,
--    not partial-on-active** (contrast with `principal_memberships_active_
--    unique`, which is partial and lets a re-grant after revoke become a NEW
--    row). Per the source prompt's own literal instruction and the given status
--    machine (revoked is terminal, no outbound transition), a revoked customer
--    portal membership for a given (tenant, identity, account) triple is
--    permanent -- mirrors `app.users`'s own `users_tenant_auth_user_unique`
--    (also plain, also terminal-on-revoke) rather than `principal_memberships`'s
--    re-grantable shape. Disclosed as a genuine, deliberate design choice matching
--    the given spec literally, not an oversight.
-- 10. **ATW-032 authority-surface sweep (`scripts/db-tests/rbac-enforcement.sql`)
--     compliance, planned up front, not patched after a red gate.** Every new
--     SECURITY DEFINER function granted to `authenticated` either (a) literally
--     calls an already-recognized primitive in its own body
--     (`app.resolve_customer_owner_account_scope`, `app.actor_holds_customer_
--     user_layer`, `app.evaluate_permission`, `app.assert_actor_is_session_
--     identity`), or (b) is covered by widening that shared test file's own
--     `base` regex keyword list to recognize this migration's own two new
--     authority primitives (`app.resolve_customer_account_scope` -- the new
--     canonical resolver every later Phase 8 capability will call, so future
--     callers are credited transitively without editing that file again; `app.
--     actor_is_active_customer_portal_account_admin` -- the new Layer-4-only
--     authority primitive), mirroring HRT-287/288's own established, disclosed
--     technique of widening that file's base keyword list for a genuinely new,
--     narrow authority primitive rather than special-casing each caller by name.
--     `app.accept_customer_portal_invite` is the one function that cannot be
--     covered this way (its own authority shape is a raw self-row-identity
--     equality check, "only the invited identity may accept their own invite" --
--     the same false-positive class `app.get_self_employee`/`app.is_ticket_
--     queue_member` already document and are exempted for) -- added to that
--     file's own `v_expected` list with a written reason, matching that exact
--     precedent. See this migration's own companion edit to `scripts/db-tests/
--     rbac-enforcement.sql`.

-- ===========================================================================
-- 1. app.customer_portal_account_memberships -- the real many-to-many grant table
-- ===========================================================================

create table app.customer_portal_account_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  auth_user_id uuid not null references auth.users (id),
  account_id uuid not null references app.accounts (id),
  role text not null,
  status text not null default 'invited',
  invited_by text,
  invited_at timestamptz,
  accepted_at timestamptz,
  granted_by text,
  granted_at timestamptz not null default now(),
  suspended_by text,
  suspended_at timestamptz,
  suspended_reason text,
  revoked_by text,
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cpam_role_check check (role in ('account_admin', 'member')),
  constraint cpam_status_check check (status in ('invited', 'active', 'suspended', 'revoked'))
);

comment on table app.customer_portal_account_memberships is
  'CPL-300: the real many-to-many customer portal membership grant -- one row per (tenant, identity, account). Non-cascading (design decision 1): a grant on a parent app.accounts row never implies access to a child row. RLS enabled, authenticated holds zero direct grant (design decision 3) -- app.resolve_customer_account_scope/app.get_customer_portal_scope_context/the RPCs below are the only sanctioned access path.';

create unique index customer_portal_account_memberships_tenant_user_account_uq
  on app.customer_portal_account_memberships (tenant_id, auth_user_id, account_id);

-- Covering indexes for the two real query shapes this migration's own RPCs use
-- (source prompt §"RPCs to create", final paragraph) -- inline rather than a
-- companion pagination-index migration, matching that same paragraph's own
-- "your call" latitude.
create index cpam_tenant_auth_status_idx
  on app.customer_portal_account_memberships (tenant_id, auth_user_id, status);
create index cpam_tenant_account_updated_id_idx
  on app.customer_portal_account_memberships (tenant_id, account_id, updated_at desc, id desc);

create table app.customer_portal_account_membership_history (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null,
  auth_user_id uuid not null,
  tenant_id uuid not null,
  account_id uuid not null,
  from_status text,
  to_status text not null,
  reason text,
  requested_by text,
  created_at timestamptz not null default now()
);

comment on table app.customer_portal_account_membership_history is
  'CPL-300: append-only state-transition history for app.customer_portal_account_memberships, mirroring app.principal_membership_history exactly. Written by every state-changing RPC below -- never updated or deleted.';

create index cpamh_membership_id_created_at_idx
  on app.customer_portal_account_membership_history (membership_id, created_at desc);

-- ===========================================================================
-- 2. Triggers -- mirror app.users/app.principal_memberships exactly (design decision 8)
-- ===========================================================================

-- Exactly the same transition matrix as app.enforce_user_status_transition
-- (20260716102620_create_users.sql): invited -> active | revoked; active ->
-- suspended | revoked; suspended -> active | revoked; revoked is terminal.
create function app.enforce_customer_portal_account_membership_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status = 'revoked' then
    raise exception 'invalid_cpam_transition: membership % is revoked, no further transition is allowed', old.id
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'invited' and new.status in ('active', 'revoked'))
    or (old.status = 'active' and new.status in ('suspended', 'revoked'))
    or (old.status = 'suspended' and new.status in ('active', 'revoked'))
  ) then
    raise exception 'invalid_cpam_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger customer_portal_account_memberships_enforce_transition
  before update of status on app.customer_portal_account_memberships
  for each row
  execute function app.enforce_customer_portal_account_membership_transition();

-- One combined touch trigger (updated_at + record_version), mirroring
-- app.touch_principal_membership_row exactly (design decision 8).
create function app.touch_customer_portal_account_membership_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger customer_portal_account_memberships_touch_row
  before update on app.customer_portal_account_memberships
  for each row
  execute function app.touch_customer_portal_account_membership_row();

-- ===========================================================================
-- 3. app.permissions: CPT:Create (design decision 6)
-- ===========================================================================

insert into app.permissions (action, resource_module_code, category, protected)
values ('Create', 'CPT', 'standard', false);

-- ===========================================================================
-- 4. app.resolve_customer_account_scope -- the widened scope resolver
-- ===========================================================================

create function app.resolve_customer_account_scope(p_auth_user_id uuid, p_tenant_id uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
begin
  -- Tier C security-rls/correctness-spec review (post-implementation, this
  -- checkpoint): this is a genuine authority boundary, not a pure lookup --
  -- p_auth_user_id is a free parameter naming WHOSE scope to resolve, so
  -- without this check any authenticated session could pass ANY OTHER
  -- identity's uuid and read that identity's full cross-account scope
  -- (live-verified IDOR both lenses independently reproduced). Converted
  -- from `language sql` to `language plpgsql` to carry this check, mirroring
  -- every write RPC below (`assert_actor_is_session_identity` first, always).
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  with legacy as (
    select unnest(app.resolve_customer_owner_account_scope(p_auth_user_id, p_tenant_id)) as account_id
  )
  select coalesce(array_agg(distinct scope_id), array[]::uuid[])
  into v_scope
  from (
    -- The legacy marker contributes an account ONLY if the new grant table has
    -- NO row at all for that exact (tenant, identity, account) triple -- once
    -- a row exists there (any status), the new table is authoritative for
    -- that triple, never the legacy marker. Without this exclusion, a
    -- revoke/suspend through app.set_customer_portal_account_membership_
    -- status below would not take effect on scope for any account this
    -- migration's own app.invite_customer_portal_user/app.grant_initial_
    -- customer_portal_account_admin granted, since both compose app.grant_
    -- principal_membership and leave that legacy row untouched by design
    -- (app.resolve_customer_owner_account_scope stays exactly as ATW-242 left
    -- it, for its own already-shipped WMS/inventory callers -- this
    -- migration never mutates it beyond the initial grant, per its own
    -- instruction not to touch that resolver''s behavior).
    select legacy.account_id as scope_id
    from legacy
    where not exists (
      select 1 from app.customer_portal_account_memberships cpam2
      where cpam2.tenant_id = p_tenant_id
        and cpam2.auth_user_id = p_auth_user_id
        and cpam2.account_id = legacy.account_id
    )
    union
    select cpam.account_id as scope_id
    from app.customer_portal_account_memberships cpam
    where cpam.auth_user_id = p_auth_user_id
      and cpam.tenant_id = p_tenant_id
      and cpam.status = 'active'
  ) s;

  return v_scope;
end;
$$;

comment on function app.resolve_customer_account_scope is
  'CPL-300: the canonical, widened customer scope resolver every Phase 8 capability prompt from 301 onward should call (design decision 4). Calls app.assert_actor_is_session_identity(p_auth_user_id) first -- Tier C review fix, this is an authority boundary (WHOSE scope to resolve), not a pure lookup. UNION of (a) app.resolve_customer_owner_account_scope''s own unchanged legacy single-account result (ATW-242, reused by direct call, never re-derived) for any account the NEW grant table has no row for at all, and (b) every ACTIVE app.customer_portal_account_memberships row for this (auth_user_id, tenant_id) -- once the new table has a row for a given account (any status), it is authoritative for that account and the legacy marker is ignored, so a revoke/suspend through this migration''s own RPCs takes effect on scope immediately (source prompt §24). Always returns a real, possibly-empty array, never NULL. app.resolve_customer_owner_account_scope itself is untouched and remains correct for its own already-shipped WMS/inventory callers.';

-- ===========================================================================
-- 5. app.actor_is_active_customer_portal_account_admin -- the ONE shared
-- Layer-4-only authority primitive every write/list RPC below composes,
-- never re-derived (design decision 5, mirrors ATW-023 design note 4's own
-- "customer_warehouse_eligibility_active is the ONE shared eligibility
-- predicate" shape).
-- ===========================================================================

create function app.actor_is_active_customer_portal_account_admin(p_tenant_id uuid, p_account_id uuid, p_actor_auth_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- Tier C security-rls review fix: granted directly to authenticated (it is
  -- the one shared authority primitive every write/list RPC composes, per
  -- design decision 5), so without this check any authenticated session
  -- could call it directly with an arbitrary p_actor_auth_user_id and use the
  -- boolean result as an oracle for "is identity X an account_admin of
  -- account Y" -- converted from `language sql` to `language plpgsql` to
  -- carry the check, mirroring every write RPC. A no-op for the nested calls
  -- from those write RPCs below, which already assert the same identity
  -- first in their own body.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return exists (
    select 1 from app.customer_portal_account_memberships
    where tenant_id = p_tenant_id
      and account_id = p_account_id
      and auth_user_id = p_actor_auth_user_id
      and role = 'account_admin'
      and status = 'active'
  );
end;
$$;

comment on function app.actor_is_active_customer_portal_account_admin is
  'CPL-300: true only if p_actor_auth_user_id holds an ACTIVE account_admin-role row on this exact (tenant_id, account_id) in the NEW grant table -- never the legacy app.principal_memberships.customer_account_ref marker, which carries no role concept. Calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first (Tier C review fix -- it is granted directly to authenticated). A Layer-4-only authority chain (ADR-0024 Part B) -- never app.evaluate_permission/staff RBAC. Live, never cached: revocation/suspension of the actor''s own account_admin row denies immediately.';

-- ===========================================================================
-- 6. app.get_customer_portal_scope_context -- the shared scope-preview adapter
-- ===========================================================================

create function app.get_customer_portal_scope_context(p_auth_user_id uuid, p_tenant_id uuid)
returns table (
  account_id uuid,
  account_name text,
  role text,
  is_primary boolean
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_primary_account_id uuid;
begin
  -- Tier C security-rls/correctness-spec review fix: p_auth_user_id is a free
  -- parameter naming WHOSE scope-context to resolve -- without this check any
  -- authenticated session could pass another identity's uuid and read that
  -- identity's account/role/is_primary rows (live-verified IDOR both lenses
  -- independently reproduced). Checked BEFORE the anti-enumeration gate below,
  -- mirroring every write RPC's own "assert_actor_is_session_identity first"
  -- ordering.
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  -- Anti-enumeration/deny-by-default (ADR-0024 Part A): independently re-verify
  -- the caller genuinely holds an active customer_user-layer principal in this
  -- tenant before returning anything at all -- an empty set, never an error, for
  -- a non-customer_user caller (mirrors HRT-287's own list_customer_ticket_
  -- categories/list_my_tickets positive-gate use of this exact primitive).
  if not app.actor_holds_customer_user_layer(p_tenant_id, p_auth_user_id) then
    return;
  end if;

  -- "Primary" (design decision 4/note below) is the account matching the
  -- legacy app.principal_memberships.customer_account_ref, if any -- per the
  -- source prompt's own literal wording. For an identity that now holds
  -- several legacy-style markers (app.invite_customer_portal_user composes
  -- app.grant_principal_membership once per invited account, so a customer
  -- invited to N accounts through the new RPC ends up with N such markers,
  -- design decision 4/RPC 3 below), this deterministically picks the
  -- earliest-granted one (their first invited account) rather than an
  -- arbitrary row -- disclosed here since the source prompt's own "if any"
  -- phrasing assumed at most one, a assumption this migration's own invite
  -- flow no longer guarantees post-migration.
  select pm.customer_account_ref::uuid into v_primary_account_id
  from app.principal_memberships pm
  where pm.auth_user_id = p_auth_user_id
    and pm.tenant_id = p_tenant_id
    and pm.layer = 'customer_user'
    and pm.status = 'active'
    and pm.customer_account_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  order by pm.granted_at asc, pm.id asc
  limit 1;

  return query
  select a.id, a.legal_name, cpam.role, (a.id = v_primary_account_id) as is_primary
  from app.accounts a
  left join app.customer_portal_account_memberships cpam
    on cpam.tenant_id = p_tenant_id
    and cpam.auth_user_id = p_auth_user_id
    and cpam.account_id = a.id
    and cpam.status = 'active'
  where a.tenant_id = p_tenant_id
    and a.id = any (app.resolve_customer_account_scope(p_auth_user_id, p_tenant_id))
  order by a.legal_name;
end;
$$;

comment on function app.get_customer_portal_scope_context is
  'CPL-300: the shared scope-preview/session-context adapter every downstream Phase 8 REST endpoint and UI (this checkpoint''s own customer-portal page included) composes. Calls app.assert_actor_is_session_identity(p_auth_user_id) first (Tier C review fix). account_name is app.accounts.legal_name only -- never normalized_legal_name/duplicate_fingerprint/owner_user_id/org_unit_id. role is the new table''s own role for accounts with an explicit membership row; NULL for an account visible only through the legacy customer_account_ref marker (which carries no role concept) -- disclosed, not a live gap.';

-- ===========================================================================
-- 7. app.invite_customer_portal_user
-- ===========================================================================

create function app.invite_customer_portal_user(
  p_tenant_id uuid,
  p_account_id uuid,
  p_auth_user_id uuid,
  p_role text,
  p_actor_auth_user_id uuid,
  p_invited_by text
)
returns app.customer_portal_account_memberships
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.customer_portal_account_memberships;
  v_membership app.customer_portal_account_memberships;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_role not in ('account_admin', 'member') then
    raise exception 'invalid_role: % is not a recognized customer portal role', p_role using errcode = 'check_violation';
  end if;

  if not app.actor_is_active_customer_portal_account_admin(p_tenant_id, p_account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active account_admin on account %', p_actor_auth_user_id, p_account_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent (source prompt §"RPCs to create" item 3): a repeated invite for
  -- the same (tenant_id, auth_user_id, account_id) with status <> 'revoked'
  -- returns the existing row unchanged, mirroring app.invite_user's own
  -- idempotent-return shape exactly. Status = 'revoked' is terminal (design
  -- decision 9) -- re-inviting a revoked membership is rejected, never silently
  -- resurrected.
  select * into v_existing
  from app.customer_portal_account_memberships
  where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and account_id = p_account_id;

  if found then
    if v_existing.status = 'revoked' then
      raise exception 'membership_revoked: a revoked customer portal membership for identity % on account % cannot be re-invited', p_auth_user_id, p_account_id
        using errcode = 'check_violation';
    end if;
    return v_existing;
  end if;

  -- Composes app.link_auth_identity (PLT-107) to guarantee identity linkage
  -- exists -- a service_role-only function, callable here because this
  -- SECURITY DEFINER function runs as its owner, the same established
  -- pattern app.record_customer_inventory_access_denial/app.export_customer_
  -- inventory_snapshot already use to call app.capture_audit_event.
  -- link_auth_identity carries no layer/access meaning of its own (PLT-107
  -- tenant_user_identities linkage only), so establishing it at invite time
  -- is still correct.
  --
  -- Tier C security-rls review fix: the Layer-4 CHECK-required app.
  -- principal_memberships row (design decision 2) is deliberately NOT
  -- granted here anymore -- app.grant_principal_membership is now called
  -- only from app.accept_customer_portal_invite below, on genuine
  -- acceptance. Granting it here, at invite time, gave an invited-but-never-
  -- accepted identity live WMS/inventory access (app.resolve_customer_owner_
  -- account_scope/app.evaluate_customer_inventory_access, ATW-023) and
  -- portal-entry access (app.actor_holds_customer_user_layer) before they
  -- had done anything at all -- a real, live-verified bypass, not a
  -- theoretical one.
  perform app.link_auth_identity(p_auth_user_id, p_tenant_id, p_invited_by, 'invited');

  insert into app.customer_portal_account_memberships
    (tenant_id, auth_user_id, account_id, role, status, invited_by, invited_at, granted_by, granted_at)
  values
    (p_tenant_id, p_auth_user_id, p_account_id, p_role, 'invited', p_invited_by, now(), p_invited_by, now())
  returning * into v_membership;

  insert into app.customer_portal_account_membership_history
    (membership_id, auth_user_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values
    (v_membership.id, v_membership.auth_user_id, v_membership.tenant_id, v_membership.account_id, null, 'invited', 'customer portal membership invited', p_invited_by);

  return v_membership;
end;
$$;

comment on function app.invite_customer_portal_user is
  'CPL-300: self-service invite by an existing active account_admin on the exact target account (design decision 5, app.actor_is_active_customer_portal_account_admin). Idempotent for a non-revoked existing row. The very first account_admin on a brand-new account has no predecessor to call this -- see app.grant_initial_customer_portal_account_admin below for that bootstrap case.';

-- ===========================================================================
-- 8. app.accept_customer_portal_invite
-- ===========================================================================

create function app.accept_customer_portal_invite(
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
  if v_membership.auth_user_id <> p_auth_user_id then
    raise exception 'insufficient_authority: only the invited identity may accept customer portal membership %', p_membership_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_membership.record_version <> p_expected_version then
    raise exception 'stale_version: customer portal membership % expected version % but found %', p_membership_id, p_expected_version, v_membership.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_membership.status <> 'invited' then
    raise exception 'invalid_transition: customer portal membership % is %, only a pending invite can be accepted', p_membership_id, v_membership.status
      using errcode = 'check_violation';
  end if;

  update app.customer_portal_account_memberships
  set status = 'active', accepted_at = now()
  where id = p_membership_id
  returning * into v_updated;

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
  'CPL-300: invited -> active only, by the invited identity itself. p_auth_user_id must equal the row''s own auth_user_id (raises insufficient_authority otherwise) -- a forged/copied auth_user_id on accept is rejected. Optimistic-concurrency record_version check (stale_version), mirroring app.decide_overtime_request''s own version-check shape. Grants the legacy app.principal_memberships marker here (Tier C review fix, moved from app.invite_customer_portal_user) -- an invited-but-not-yet-accepted identity holds no legacy WMS/inventory or portal-entry access.';

-- ===========================================================================
-- 9. app.set_customer_portal_account_membership_status -- suspend/revoke/reactivate
-- ===========================================================================

create function app.set_customer_portal_account_membership_status(
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

  if not app.actor_is_active_customer_portal_account_admin(v_membership.tenant_id, v_membership.account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active account_admin on account %', p_actor_auth_user_id, v_membership.account_id
      using errcode = 'insufficient_privilege';
  end if;

  -- invited -> active is exclusively app.accept_customer_portal_invite's own
  -- job (self-accept only, business rule above) -- an admin may not force it
  -- here even though the underlying transition trigger would otherwise permit
  -- invited -> active.
  if v_membership.status = 'invited' and p_to_status = 'active' then
    raise exception 'accept_required: an invited membership may only be activated by the invited identity itself, via app.accept_customer_portal_invite'
      using errcode = 'check_violation';
  end if;

  if v_membership.record_version <> p_expected_version then
    raise exception 'stale_version: customer portal membership % expected version % but found %', p_membership_id, p_expected_version, v_membership.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.customer_portal_account_memberships
  set status = p_to_status,
      suspended_by = case when p_to_status = 'suspended' then p_actor_label else suspended_by end,
      suspended_at = case when p_to_status = 'suspended' then now() else suspended_at end,
      suspended_reason = case when p_to_status = 'suspended' then p_reason else suspended_reason end,
      revoked_by = case when p_to_status = 'revoked' then p_actor_label else revoked_by end,
      revoked_at = case when p_to_status = 'revoked' then now() else revoked_at end,
      revoked_reason = case when p_to_status = 'revoked' then p_reason else revoked_reason end
  where id = p_membership_id
  returning * into v_updated;

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
  'CPL-300: suspend/revoke/reactivate, caller-gated by app.actor_is_active_customer_portal_account_admin on the SAME account_id (design decision 5). Source prompt §24: "Revocation invalidates sessions, saved views, exports, signed URLs and cached summaries" -- every read RPC in this migration re-checks status=''active'' LIVE against this table on every call, never caching it, so revocation takes effect immediately by construction (design decision 7). Tier C review fix: ALSO drives the legacy app.principal_memberships row this migration''s own accept/bootstrap flow grants (revoke on suspend/revoke, re-grant on suspended -> active reactivation) so already-shipped legacy consumers (ATW-023 WMS/inventory, the ticketing customer channel, this migration''s own portal-entry guard) lose/regain access in step, not only this migration''s own resolver -- no separate session-invalidation mechanism is built beyond that, none exists anywhere in this repository.';

-- ===========================================================================
-- 10. app.list_customer_portal_account_memberships -- "manage my account's users"
-- ===========================================================================

create function app.list_customer_portal_account_memberships(
  p_tenant_id uuid,
  p_account_id uuid,
  p_actor_auth_user_id uuid,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_account_memberships
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
begin
  -- Tier C security-rls/correctness-spec review fix: p_actor_auth_user_id is
  -- a free parameter naming WHO is claiming to be an account_admin --
  -- without this check any authenticated session could pass another
  -- identity's uuid and read that identity's own account's full membership
  -- roster, including suspended/revoked reasons and every member's real
  -- auth_user_id (live-verified IDOR both lenses independently reproduced).
  -- Checked first, mirroring every write RPC's own ordering.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  -- account_admin-only (design decision 5); deny-by-default, empty set rather
  -- than an error for a non-admin caller (ADR-0024 Part A anti-enumeration
  -- discipline, mirrors ATW-023's own empty-scope-yields-zero-rows shape).
  if not app.actor_is_active_customer_portal_account_admin(p_tenant_id, p_account_id, p_actor_auth_user_id) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select m.*
  from app.customer_portal_account_memberships m
  where m.tenant_id = p_tenant_id
    and m.account_id = p_account_id
    and (p_cursor_id is null or (m.updated_at, m.id) < (p_cursor_updated_at, p_cursor_id))
  order by m.updated_at desc, m.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_account_memberships is
  'CPL-300: account_admin-only "manage my account''s users" list. Calls app.assert_actor_is_session_identity(p_actor_auth_user_id) first (Tier C review fix). Keyset-paginated on (updated_at desc, id desc), never OFFSET, hard-capped at 200 -- mirrors the ATW-023 cursor convention exactly.';

-- ===========================================================================
-- 11. app.grant_initial_customer_portal_account_admin -- staff bootstrap
-- ===========================================================================

create function app.grant_initial_customer_portal_account_admin(
  p_tenant_id uuid,
  p_account_id uuid,
  p_auth_user_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_account_memberships
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_account app.accounts;
  v_decision app.rbac_decision;
  v_existing app.customer_portal_account_memberships;
  v_membership app.customer_portal_account_memberships;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- The one deliberate exception to "Layer-4-only, never staff RBAC" (design
  -- decision 5): the very first grant on a brand-new account has no existing
  -- account_admin to authorize it, so a tenant admin (staff, CPT:Create) seeds
  -- it once. After this call, app.invite_customer_portal_user is the
  -- self-service path for every subsequent member of this same account.
  --
  -- Tier C security-rls review fix (Finding 3): checked BEFORE the account
  -- existence lookup below, not after. The two raised distinct errors
  -- (account_not_found vs insufficient_authority) otherwise let ANY
  -- authenticated identity -- not just staff of this tenant -- probe whether
  -- an arbitrary account id exists in a tenant it has no relationship to, by
  -- reading which error comes back. Ordering the authority check first means
  -- only a caller who already holds CPT:Create in this tenant can reach the
  -- existence check at all -- staff, for whom app.accounts is already
  -- tenant-wide visible (no new disclosure), never an unrelated identity.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'CPT', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks CPT:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.accounts where id = p_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'account_not_found: no account % in tenant %', p_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  select * into v_existing
  from app.customer_portal_account_memberships
  where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and account_id = p_account_id;

  if found then
    if v_existing.status = 'revoked' then
      raise exception 'membership_revoked: a revoked customer portal membership for identity % on account % cannot be re-seeded', p_auth_user_id, p_account_id
        using errcode = 'check_violation';
    end if;
    return v_existing;
  end if;

  perform app.link_auth_identity(p_auth_user_id, p_tenant_id, p_actor_label, 'invited');
  perform app.grant_principal_membership(p_auth_user_id, 'customer_user', p_tenant_id, p_account_id::text, p_actor_label);

  -- Seeded directly at status='active' (not 'invited') -- a tenant admin
  -- performing this bootstrap has already verified this identity out-of-band;
  -- there is no predecessor account_admin to send a self-service invite
  -- through, and the ordinary accept flow remains available to every
  -- subsequent member invited via app.invite_customer_portal_user.
  insert into app.customer_portal_account_memberships
    (tenant_id, auth_user_id, account_id, role, status, invited_by, invited_at, granted_by, granted_at, accepted_at)
  values
    (p_tenant_id, p_auth_user_id, p_account_id, 'account_admin', 'active', p_actor_label, now(), p_actor_label, now(), now())
  returning * into v_membership;

  insert into app.customer_portal_account_membership_history
    (membership_id, auth_user_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values
    (v_membership.id, v_membership.auth_user_id, v_membership.tenant_id, v_membership.account_id, null, 'active', 'initial account_admin seeded by tenant admin', p_actor_label);

  return v_membership;
end;
$$;

comment on function app.grant_initial_customer_portal_account_admin is
  'CPL-300: tenant-admin-only (staff, CPT:Create) bootstrap -- seeds the first account_admin on a brand-new account, once. Every subsequent member is invited by that account_admin through app.invite_customer_portal_user, never through this function again for the same account (idempotent no-op if called again for the same identity+account while not revoked). CPT:Create is checked BEFORE account existence (Tier C review fix) so an identity with no relationship to this tenant cannot use the distinct account_not_found/insufficient_authority errors as a cross-tenant account-id existence oracle.';

-- ===========================================================================
-- 12. RLS -- enable, grant service_role only (design decision 3)
-- ===========================================================================

alter table app.customer_portal_account_memberships enable row level security;
alter table app.customer_portal_account_membership_history enable row level security;

grant select, insert, update, delete
  on app.customer_portal_account_memberships, app.customer_portal_account_membership_history
  to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.resolve_customer_account_scope(uuid, uuid) to authenticated, service_role;
grant execute on function app.actor_is_active_customer_portal_account_admin(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_customer_portal_scope_context(uuid, uuid) to authenticated, service_role;
grant execute on function app.invite_customer_portal_user(uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.accept_customer_portal_invite(uuid, integer, uuid) to authenticated, service_role;
grant execute on function app.set_customer_portal_account_membership_status(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_customer_portal_account_memberships(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.grant_initial_customer_portal_account_admin(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
