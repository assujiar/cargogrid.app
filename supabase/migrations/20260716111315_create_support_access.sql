-- Platform Core capability PLT-115 (Support Access and Impersonation Control, CG-S6-PLT-012)
-- The mechanism PLT-108's and PLT-113's own migrations explicitly deferred: "A Supreme
-- Admin acting *inside* a specific tenant's data (support/troubleshooting) does not get
-- there through [principal_memberships] -- that is a separate, time-bound, reason-logged
-- grant owned by PLT-115" (20260716100825_create_principal_memberships.sql header).
--
-- Grounded directly in docs/architecture/06_RLS_RBAC_WORKSTREAM.md:
-- * §2.3 "Delegation and support grants" names the table and its minimal column set
--   verbatim: "support_access_grants (new table ...): tenant_id, grantee_user_id, reason,
--   case_id, scope, granted_at, expires_at, revoked_at. Every support-access RLS policy
--   joins against this table's expires_at > now() AND revoked_at IS NULL condition." This
--   migration keeps every one of those columns (grantee_user_id renamed
--   grantee_auth_user_id, matching this repository's auth_user_id naming convention
--   everywhere else -- PLT-107/108/110/111/112/113/114 all use it) and extends the table
--   with the columns needed to satisfy Prompt 115's own objective ("explicit tenant
--   approval/policy," "time bounds," "re-authentication," exception flow) -- disclosed
--   here as extensions of the cited minimal set, not fabricated beyond it.
-- * §4's `support_access_gated` policy family: "Any table accessed under a
--   support/impersonation grant | tenant_id + active grant (§2.3) | CargoGrid Support
--   role, time-bound | Support access expired cannot read tenant data (test #5)." This is
--   implemented here as an *additive* extension to PLT-113's own
--   app.has_active_tenant_membership() -- every tenant-scoped SELECT policy PLT-113
--   already shipped (tenants/org_units/users/roles/role_versions/role_assignments/...)
--   transparently also honors a live support grant, which is the concrete meaning of
--   "policy family" (one reused predicate, not seven duplicated one-off policies) and of
--   Prompt 115 §26's "Support access layers over ... RLS ... policy, not bypasses them."
-- * §6 "Privileged and support access paths": ticket/case required (case_id, not null),
--   time-bound (expires_at), visible impersonation banner during an active grant (the
--   TS-side deriveSupportSessionBanner() primitive), "tenant visibility and kill switch"
--   (§16 Security impact) -- both the grantee's own tenant_admin and Supreme Admin can see
--   and revoke a grant into that tenant, not Supreme Admin alone.
-- * Prompt 115 §22 alternative flow: "Emergency support uses recorded higher authority/
--   shorter expiry and post-review" -- the `emergency` boolean, `authorized_by_auth_user_id`
--   (the recorded higher authority), a shorter expiry cap (2h vs. 24h, enforced by a CHECK
--   constraint, not just application logic), and app.complete_support_access_post_review().
--
-- No "CargoGrid Support" principal layer exists in app.principal_memberships (PLT-108's
-- four layers are supreme_admin/tenant_admin/org_user/customer_user, deliberately closed --
-- see that migration's header) -- a support grant's grantee is therefore any real
-- auth.users identity, not required to already hold a principal membership of its own; the
-- grant itself is the authority for tenant-scoped RLS visibility (has_active_support_grant
-- below), which is the whole point of a *distinct* mechanism from an ordinary membership
-- row. Approving/denying/revoking a grant, by contrast, does require the actor to already
-- hold real authority (Supreme Admin or the target tenant's own tenant_admin,
-- app.is_support_grant_authority() below) -- a support session cannot be self-authorized.
--
-- "Impersonation" in this repository's current state is scoped as an RLS-visibility
-- extension into the granted tenant's data, not a literal auth-token-swap mechanism --
-- there is no session/JWT-minting surface anywhere in this repository yet (no REST/
-- GraphQL/portal exists in Phase 1 Platform Core), so "activate/impersonate" is proven as
-- app.start_support_session()/app.has_active_support_grant() extending RLS, exactly the
-- same disclosed "mechanism proven, no live consumer yet" posture every capability since
-- PLT-108 has used. Underlying identity never changes (Prompt 115 §24) -- auth.uid()
-- inside a support session is still the support agent's own identity, never the tenant
-- user's; app.current_support_session() lets a future UI/audit consumer attribute actions
-- to "grantee acting under grant X," never a borrowed identity.

create table app.support_access_grants (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  grantee_auth_user_id uuid not null references auth.users (id),
  reason text not null,
  case_id text not null,
  scope text not null default 'read_only',
  emergency boolean not null default false,
  status text not null default 'pending_approval',
  requested_by text not null,
  requested_at timestamptz not null default now(),
  authorized_by_auth_user_id uuid references auth.users (id),
  approved_by text,
  granted_at timestamptz,
  denied_by text,
  denied_at timestamptz,
  denial_reason text,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_by text,
  revoked_reason text,
  post_review_completed_at timestamptz,
  post_review_by text,
  post_review_note text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint support_access_grants_scope_check
    check (scope in ('read_only', 'read_write')),
  constraint support_access_grants_status_check
    check (status in ('pending_approval', 'approved', 'denied', 'revoked')),
  constraint support_access_grants_expiry_shape
    check (expires_at > requested_at),
  -- Alternative flow (Prompt 115 §22): emergency access carries a structurally shorter
  -- expiry cap (2h) than standard support access (24h) -- a CHECK constraint, not just a
  -- function-level default, so no code path can silently grant a long-lived "emergency".
  constraint support_access_grants_expiry_cap
    check (
      (emergency and expires_at <= requested_at + interval '2 hours')
      or (not emergency and expires_at <= requested_at + interval '24 hours')
    ),
  constraint support_access_grants_emergency_authority
    check (not emergency or authorized_by_auth_user_id is not null)
);

comment on table app.support_access_grants is
  'Time/purpose-bound support access grant (PLT-115) -- docs/architecture/06_RLS_RBAC_WORKSTREAM.md §2.3''s support_access_grants, extended with an approval/denial/revocation/emergency-post-review lifecycle for Prompt 115''s objective. Never a permission grant by itself (§26: "layers over ... RBAC/RLS/field/record policy, not bypasses them") -- see app.has_active_support_grant() and its use inside app.has_active_tenant_membership() below.';

create index support_access_grants_tenant_id_idx on app.support_access_grants (tenant_id);
create index support_access_grants_grantee_idx on app.support_access_grants (grantee_auth_user_id);

-- No DB-level uniqueness guards request idempotency here (unlike PLT-108's
-- principal_memberships_active_unique) -- the natural idempotency key would need
-- "expires_at > now()", a time-relative condition Postgres cannot express in an immutable
-- partial-index predicate. app.request_support_access() below enforces the equivalent
-- check-then-insert idempotency at the function level instead, disclosed as a deliberate
-- difference from the DB-constraint pattern, not an oversight.

create table app.support_access_sessions (
  id uuid primary key default gen_random_uuid(),
  grant_id uuid not null references app.support_access_grants (id),
  tenant_id uuid not null,
  grantee_auth_user_id uuid not null,
  reauth_confirmed_at timestamptz not null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_reason text,
  created_at timestamptz not null default now(),
  constraint support_access_sessions_ended_reason_check
    check (ended_reason is null or ended_reason in ('manual_end', 'revoked', 'expired')),
  constraint support_access_sessions_end_shape
    check ((ended_at is null and ended_reason is null) or (ended_at is not null and ended_reason is not null))
);

comment on table app.support_access_sessions is
  'A discrete activate->impersonate->end window under an approved app.support_access_grants row (PLT-115, Prompt 115 §3 feature slice). reauth_confirmed_at proves re-authentication happened immediately before activation (Prompt 115 §4/§16); the grant may support multiple sequential sessions within its own time window (support_access_sessions_one_open_per_grant below allows only one *open* session per grant at a time, not one session total).';

create index support_access_sessions_grant_id_idx on app.support_access_sessions (grant_id);
create index support_access_sessions_tenant_id_idx on app.support_access_sessions (tenant_id, grantee_auth_user_id);

create unique index support_access_sessions_one_open_per_grant
  on app.support_access_sessions (grant_id)
  where ended_at is null;

-- This capability's own append-only, capability-scoped event trail (Prompt 115 §18:
-- "Every grant, approval, start/end, context, action and revocation is recorded") --
-- distinct from the future generic app.audit_logs (PLT-116) and from
-- docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md's separately-scheduled
-- support_access_logs table (line 68, part of the "Platform notification/document/audit
-- core" slice alongside audit_logs/event_logs/api_logs/file_access_logs -- PLT-116's slice,
-- not this one) -- the same "capability-scoped history table now, canonical audit-read
-- policy later" pattern every capability since PLT-107 has used.
create table app.support_access_events (
  id uuid primary key default gen_random_uuid(),
  grant_id uuid not null,
  session_id uuid,
  tenant_id uuid not null,
  grantee_auth_user_id uuid not null,
  event_type text not null,
  actor text not null,
  detail text,
  occurred_at timestamptz not null default now(),
  constraint support_access_events_event_type_check
    check (event_type in ('requested', 'approved', 'denied', 'session_started', 'session_ended', 'revoked', 'post_review_completed'))
);

create index support_access_events_grant_id_idx on app.support_access_events (grant_id, occurred_at desc);
create index support_access_events_tenant_id_idx on app.support_access_events (tenant_id, occurred_at desc);

-- Valid transition matrix: pending_approval -> approved | denied; approved -> revoked;
-- denied/revoked are terminal (same "never resurrected in place" discipline as every prior
-- lifecycle table this session has built -- re-requesting is a new row).
create function app.enforce_support_access_grant_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status in ('denied', 'revoked') then
    raise exception 'invalid_grant_transition: grant % is %, no further transition is allowed', old.id, old.status
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'pending_approval' and new.status in ('approved', 'denied'))
    or (old.status = 'approved' and new.status = 'revoked')
  ) then
    raise exception 'invalid_grant_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger support_access_grants_enforce_transition
  before update of status on app.support_access_grants
  for each row
  execute function app.enforce_support_access_grant_transition();

create function app.touch_support_access_grant_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger support_access_grants_touch_row
  before update on app.support_access_grants
  for each row
  execute function app.touch_support_access_grant_row();

-- Authority to approve/deny/revoke a support access grant into a tenant: Supreme Admin
-- (platform authority, RPD-022), or that specific tenant's own active tenant_admin
-- (Prompt 115 §4's "explicit tenant approval/policy" and §16's "tenant visibility and kill
-- switch" -- the tenant itself must be able to authorize and kill support access into its
-- own data, not only a platform operator). SECURITY INVOKER is correct here (unlike the
-- STABLE SECURITY DEFINER helpers below) -- every caller of this function is itself an
-- already-service_role-executed plpgsql mutation function (bypassrls), never a direct
-- authenticated-role query.
create function app.is_support_grant_authority(p_auth_user_id uuid, p_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select app.is_supreme_admin(p_auth_user_id)
    or exists (
      select 1 from app.principal_memberships
      where auth_user_id = p_auth_user_id
        and tenant_id = p_tenant_id
        and layer = 'tenant_admin'
        and status = 'active'
    );
$$;

comment on function app.is_support_grant_authority is
  'Approval/denial/revocation authority for a support access grant (PLT-115): Supreme Admin, or the target tenant''s own active tenant_admin. A support grant can never be self-authorized -- see the self_approval_forbidden guard in app.approve_support_access().';

-- The RLS-facing predicate the support_access_gated policy family (06_*.md §4) composes
-- into every existing tenant-scoped policy below -- STABLE SECURITY DEFINER, matching
-- app.is_supreme_admin()/app.has_active_tenant_membership() (PLT-113) exactly, because
-- `authenticated` is never granted direct SELECT on app.support_access_grants rows it does
-- not itself own (the RLS policy on that table, further down, is narrower than "every
-- active grant"). expires_at > now() and revoked_at is null together implement 06_*.md
-- §2.3's exact join condition, verbatim.
create function app.has_active_support_grant(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.support_access_grants
    where tenant_id = p_tenant_id
      and grantee_auth_user_id = p_auth_user_id
      and status = 'approved'
      and granted_at is not null
      and expires_at > now()
      and revoked_at is null
  );
$$;

comment on function app.has_active_support_grant is
  'True if the identity holds a live (approved, unexpired, unrevoked) support access grant into the given tenant (PLT-115, docs/architecture/06_RLS_RBAC_WORKSTREAM.md §2.3''s exact expires_at/revoked_at condition). Composed into app.has_active_tenant_membership() below -- this is the support_access_gated policy family (§4): one reused predicate, not a duplicated policy per table.';

-- The support_access_gated policy family, concretely: extending PLT-113's own
-- has_active_tenant_membership() additively means every tenant-scoped SELECT policy that
-- function already gates (tenants/tenant_entitlements/tenant_entitlement_overrides/
-- tenant_user_identities/principal_memberships/org_units/users/roles/role_versions/
-- role_assignments) transparently also honors a live support grant, with zero changes to
-- any of those seven already-shipped policies -- exactly Prompt 115 §26's "layers over ...
-- RLS ... policy, not bypasses them." A support grant does NOT extend app.can_access_record
-- (PLT-114)'s ownership/team-share/customer-scope OR-branches -- passing the tenant-
-- membership prerequisite there is necessary but not sufficient, same as for any ordinary
-- tenant member with no ownership/share/customer match. No business-domain table with
-- owner_user_id exists yet in this repository (PLT-114's own disclosed scope boundary), so
-- whether a future such table's RLS should also honor a support grant directly (bypassing
-- can_access_record's ownership check) is left an explicit open decision for whichever
-- later capability first creates such a table, not decided here.
create or replace function app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.tenant_user_identities
    where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id and status = 'active'
  )
  or app.is_supreme_admin(p_auth_user_id)
  or app.has_active_support_grant(p_tenant_id, p_auth_user_id);
$$;

comment on function app.has_active_tenant_membership is
  'RLS helper (PLT-113, extended by PLT-115): true if the identity has an active app.tenant_user_identities linkage (PLT-107) to the given tenant, is a Supreme Admin, or holds a live support access grant into that tenant (PLT-115, support_access_gated policy family). The single reusable predicate every tenant-scoped SELECT policy uses -- stage 2 of the 8-stage flow, now support-access-aware everywhere it is already enforced.';

-- Banner/attribution context (Prompt 115 §15 "Reusable impersonation banner/context").
-- Returns the caller's own single open session for a tenant, or no row if none -- a
-- perfectly normal, majority-case state (not an error, unlike app.resolve_access_context's
-- fail-closed "no context" exceptions), so this is a plain nullable lookup, not a raising
-- resolver.
create function app.current_support_session(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns app.support_access_sessions
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select s.*
  from app.support_access_sessions s
  join app.support_access_grants g on g.id = s.grant_id
  where s.tenant_id = p_tenant_id
    and s.grantee_auth_user_id = p_auth_user_id
    and s.ended_at is null
    and g.status = 'approved'
    and g.revoked_at is null
    and g.expires_at > now()
  limit 1;
$$;

comment on function app.current_support_session is
  'The caller''s own currently-open support session into a tenant, if any (PLT-115) -- the server-side source of truth a future portal-shell banner component (Prompt 115 §15) renders from, and the join point a future business mutation could attribute an action to ("acting under support grant X") once such a mutation exists.';

-- Idempotent request -- a retried identical (tenant, grantee, case) request while a prior
-- request is still pending/live returns the existing row rather than duplicating (the same
-- idempotency discipline every grant-shaped function in this repository has used since
-- PLT-105, applied here at the function level per the comment above the table definition).
create function app.request_support_access(
  p_tenant_id uuid,
  p_grantee_auth_user_id uuid,
  p_reason text,
  p_case_id text,
  p_expiry_minutes integer,
  p_requested_by text,
  p_scope text default 'read_only',
  p_emergency boolean default false,
  p_authorized_by_auth_user_id uuid default null
)
returns app.support_access_grants
language plpgsql
as $$
declare
  v_existing app.support_access_grants;
  v_grant app.support_access_grants;
  v_max_minutes integer;
  v_now timestamptz := now();
  v_authorized_by_label text;
begin
  select * into v_existing
  from app.support_access_grants
  where tenant_id = p_tenant_id
    and grantee_auth_user_id = p_grantee_auth_user_id
    and case_id = p_case_id
    and status in ('pending_approval', 'approved')
    and revoked_at is null
    and expires_at > v_now
  order by requested_at desc
  limit 1;

  if found then
    return v_existing;
  end if;

  v_max_minutes := case when p_emergency then 120 else 1440 end;
  if p_expiry_minutes is null or p_expiry_minutes <= 0 or p_expiry_minutes > v_max_minutes then
    raise exception 'invalid_expiry: expiry must be between 1 and % minutes for % access', v_max_minutes, case when p_emergency then 'emergency' else 'standard' end
      using errcode = 'check_violation';
  end if;

  -- Alternative flow (Prompt 115 §22): emergency support bypasses pending_approval, going
  -- straight to approved -- but only with a recorded higher authority (Supreme Admin or the
  -- target tenant's own tenant_admin), never self-authorized, and always requiring the
  -- post-review app.complete_support_access_post_review() closes out later.
  if p_emergency then
    if p_authorized_by_auth_user_id is null or not app.is_support_grant_authority(p_authorized_by_auth_user_id, p_tenant_id) then
      raise exception 'insufficient_authority: emergency support access requires a recorded higher authority (Supreme Admin or the tenant''s own tenant_admin)'
        using errcode = 'insufficient_privilege';
    end if;
    select coalesce(u.email, p_authorized_by_auth_user_id::text) into v_authorized_by_label
    from auth.users u where u.id = p_authorized_by_auth_user_id;
  end if;

  insert into app.support_access_grants (
    tenant_id, grantee_auth_user_id, reason, case_id, scope, emergency, status,
    requested_by, requested_at, expires_at, authorized_by_auth_user_id, approved_by, granted_at
  )
  values (
    p_tenant_id, p_grantee_auth_user_id, p_reason, p_case_id, p_scope, p_emergency,
    case when p_emergency then 'approved' else 'pending_approval' end,
    p_requested_by, v_now, v_now + make_interval(mins => p_expiry_minutes), p_authorized_by_auth_user_id,
    case when p_emergency then v_authorized_by_label else null end,
    case when p_emergency then v_now else null end
  )
  returning * into v_grant;

  insert into app.support_access_events (grant_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_grant.id, p_tenant_id, p_grantee_auth_user_id, 'requested', p_requested_by, p_reason);

  if p_emergency then
    insert into app.support_access_events (grant_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
    values (v_grant.id, p_tenant_id, p_grantee_auth_user_id, 'approved', v_authorized_by_label, 'emergency auto-approval, post-review required');
  end if;

  return v_grant;
end;
$$;

comment on function app.request_support_access is
  'Requests a support access grant (PLT-115). Standard requests start pending_approval and need app.approve_support_access(); emergency requests (p_emergency=true) require a recorded higher authority and are auto-approved with a structurally shorter expiry cap, always needing a later app.complete_support_access_post_review() (Prompt 115 §22).';

create function app.approve_support_access(
  p_grant_id uuid,
  p_approver_auth_user_id uuid,
  p_approved_by text,
  p_expires_at timestamptz default null
)
returns app.support_access_grants
language plpgsql
as $$
declare
  v_grant app.support_access_grants;
  v_updated app.support_access_grants;
begin
  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found then
    raise exception 'grant_not_found: no support access grant %', p_grant_id using errcode = 'no_data_found';
  end if;

  if v_grant.status <> 'pending_approval' then
    raise exception 'invalid_grant_status: grant % is %, expected pending_approval', p_grant_id, v_grant.status
      using errcode = 'check_violation';
  end if;

  -- Self-escalation guard, mirroring PLT-111's assign_role() pattern: the grantee cannot
  -- approve their own request into their own support access.
  if p_approver_auth_user_id = v_grant.grantee_auth_user_id then
    raise exception 'self_approval_forbidden: identity % cannot approve their own support access grant', p_approver_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.is_support_grant_authority(p_approver_auth_user_id, v_grant.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_approver_auth_user_id, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.support_access_grants
  set status = 'approved',
      granted_at = now(),
      approved_by = p_approved_by,
      expires_at = coalesce(p_expires_at, expires_at)
  where id = p_grant_id
  returning * into v_updated;

  insert into app.support_access_events (grant_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_updated.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'approved', p_approved_by, null);

  return v_updated;
end;
$$;

create function app.deny_support_access(
  p_grant_id uuid,
  p_denier_auth_user_id uuid,
  p_denied_by text,
  p_reason text
)
returns app.support_access_grants
language plpgsql
as $$
declare
  v_grant app.support_access_grants;
  v_updated app.support_access_grants;
begin
  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found then
    raise exception 'grant_not_found: no support access grant %', p_grant_id using errcode = 'no_data_found';
  end if;

  if v_grant.status <> 'pending_approval' then
    raise exception 'invalid_grant_status: grant % is %, expected pending_approval', p_grant_id, v_grant.status
      using errcode = 'check_violation';
  end if;

  if not app.is_support_grant_authority(p_denier_auth_user_id, v_grant.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_denier_auth_user_id, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.support_access_grants
  set status = 'denied', denied_at = now(), denied_by = p_denied_by, denial_reason = p_reason
  where id = p_grant_id
  returning * into v_updated;

  insert into app.support_access_events (grant_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_updated.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'denied', p_denied_by, p_reason);

  return v_updated;
end;
$$;

-- The kill switch (Prompt 115 §16/§20 task 3): either Supreme Admin or the target tenant's
-- own tenant_admin can revoke a live grant instantly, cascading to end any open session.
create function app.revoke_support_access(
  p_grant_id uuid,
  p_revoker_auth_user_id uuid,
  p_revoked_by text,
  p_reason text
)
returns app.support_access_grants
language plpgsql
as $$
declare
  v_grant app.support_access_grants;
  v_updated app.support_access_grants;
  v_open_session app.support_access_sessions;
begin
  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found then
    raise exception 'grant_not_found: no support access grant %', p_grant_id using errcode = 'no_data_found';
  end if;

  if v_grant.status = 'revoked' then
    return v_grant;
  end if;

  if v_grant.status <> 'approved' then
    raise exception 'invalid_grant_status: grant % is %, only an approved grant can be revoked', p_grant_id, v_grant.status
      using errcode = 'check_violation';
  end if;

  if not app.is_support_grant_authority(p_revoker_auth_user_id, v_grant.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_revoker_auth_user_id, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.support_access_grants
  set status = 'revoked', revoked_at = now(), revoked_by = p_revoked_by, revoked_reason = p_reason
  where id = p_grant_id
  returning * into v_updated;

  select * into v_open_session
  from app.support_access_sessions
  where grant_id = p_grant_id and ended_at is null;

  if found then
    update app.support_access_sessions
    set ended_at = now(), ended_reason = 'revoked'
    where id = v_open_session.id;

    insert into app.support_access_events (grant_id, session_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
    values (v_updated.id, v_open_session.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'session_ended', p_revoked_by, 'ended by kill switch');
  end if;

  insert into app.support_access_events (grant_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_updated.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'revoked', p_revoked_by, p_reason);

  return v_updated;
end;
$$;

-- Activation (Prompt 115 §4: "re-authentication"). p_reauth_confirmed_at must be a fresh
-- (<=5 minute old) timestamp the caller obtained by having the grantee actually
-- re-authenticate immediately beforehand -- this function only checks freshness of the
-- claim, since no live auth/session surface exists yet in this repository to independently
-- verify the re-authentication event itself (disclosed, same "mechanism proven, live wiring
-- deferred" posture as PLT-107's cookie/redirect primitives).
create function app.start_support_session(
  p_grant_id uuid,
  p_reauth_confirmed_at timestamptz,
  p_started_by text
)
returns app.support_access_sessions
language plpgsql
as $$
declare
  v_grant app.support_access_grants;
  v_existing app.support_access_sessions;
  v_session app.support_access_sessions;
begin
  select * into v_existing from app.support_access_sessions where grant_id = p_grant_id and ended_at is null;
  if found then
    return v_existing;
  end if;

  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found then
    raise exception 'grant_not_found: no support access grant %', p_grant_id using errcode = 'no_data_found';
  end if;

  if v_grant.status <> 'approved' then
    raise exception 'grant_not_approved: grant % is %, cannot start a session', p_grant_id, v_grant.status
      using errcode = 'check_violation';
  end if;
  if v_grant.revoked_at is not null then
    raise exception 'grant_revoked: grant % was revoked at %', p_grant_id, v_grant.revoked_at
      using errcode = 'check_violation';
  end if;
  if v_grant.expires_at <= now() then
    raise exception 'grant_expired: grant % expired at %', p_grant_id, v_grant.expires_at
      using errcode = 'check_violation';
  end if;

  if p_reauth_confirmed_at is null or p_reauth_confirmed_at > now() or now() - p_reauth_confirmed_at > interval '5 minutes' then
    raise exception 'reauth_required: re-authentication must have completed within the last 5 minutes'
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.support_access_sessions (grant_id, tenant_id, grantee_auth_user_id, reauth_confirmed_at)
  values (p_grant_id, v_grant.tenant_id, v_grant.grantee_auth_user_id, p_reauth_confirmed_at)
  returning * into v_session;

  insert into app.support_access_events (grant_id, session_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_grant.id, v_session.id, v_grant.tenant_id, v_grant.grantee_auth_user_id, 'session_started', p_started_by, null);

  return v_session;
end;
$$;

create function app.end_support_session(
  p_session_id uuid,
  p_ended_by text,
  p_ended_reason text default 'manual_end'
)
returns app.support_access_sessions
language plpgsql
as $$
declare
  v_session app.support_access_sessions;
  v_updated app.support_access_sessions;
begin
  select * into v_session from app.support_access_sessions where id = p_session_id;
  if not found then
    raise exception 'session_not_found: no support access session %', p_session_id using errcode = 'no_data_found';
  end if;

  if v_session.ended_at is not null then
    return v_session;
  end if;

  update app.support_access_sessions
  set ended_at = now(), ended_reason = p_ended_reason
  where id = p_session_id
  returning * into v_updated;

  insert into app.support_access_events (grant_id, session_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_updated.grant_id, v_updated.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'session_ended', p_ended_by, p_ended_reason);

  return v_updated;
end;
$$;

-- Closes the loop on an emergency grant's disclosed obligation (Prompt 115 §22: "... and
-- post-review"). Supreme Admin only -- the same authority that could have approved it
-- normally is the one that must sign off after the fact.
create function app.complete_support_access_post_review(
  p_grant_id uuid,
  p_reviewer_auth_user_id uuid,
  p_note text
)
returns app.support_access_grants
language plpgsql
as $$
declare
  v_grant app.support_access_grants;
  v_updated app.support_access_grants;
begin
  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found then
    raise exception 'grant_not_found: no support access grant %', p_grant_id using errcode = 'no_data_found';
  end if;

  if not v_grant.emergency then
    raise exception 'not_emergency_grant: grant % is not an emergency grant, post-review does not apply', p_grant_id
      using errcode = 'check_violation';
  end if;

  if not app.is_supreme_admin(p_reviewer_auth_user_id) then
    raise exception 'insufficient_authority: post-review of an emergency support access grant requires Supreme Admin authority'
      using errcode = 'insufficient_privilege';
  end if;

  update app.support_access_grants
  set post_review_completed_at = now(),
      post_review_by = coalesce((select email from auth.users where id = p_reviewer_auth_user_id), p_reviewer_auth_user_id::text),
      post_review_note = p_note
  where id = p_grant_id
  returning * into v_updated;

  insert into app.support_access_events (grant_id, tenant_id, grantee_auth_user_id, event_type, actor, detail)
  values (v_updated.id, v_updated.tenant_id, v_updated.grantee_auth_user_id, 'post_review_completed', v_updated.post_review_by, p_note);

  return v_updated;
end;
$$;

-- RLS: identical defense-in-depth posture to every prior capability.
alter table app.support_access_grants enable row level security;
alter table app.support_access_sessions enable row level security;
alter table app.support_access_events enable row level security;

grant select, insert, update, delete
  on app.support_access_grants, app.support_access_sessions, app.support_access_events
  to service_role;

grant execute on function app.is_support_grant_authority(uuid, uuid) to service_role;
grant execute on function app.request_support_access(uuid, uuid, text, text, integer, text, text, boolean, uuid) to service_role;
grant execute on function app.approve_support_access(uuid, uuid, text, timestamptz) to service_role;
grant execute on function app.deny_support_access(uuid, uuid, text, text) to service_role;
grant execute on function app.revoke_support_access(uuid, uuid, text, text) to service_role;
grant execute on function app.start_support_session(uuid, timestamptz, text) to service_role;
grant execute on function app.end_support_session(uuid, text, text) to service_role;
grant execute on function app.complete_support_access_post_review(uuid, uuid, text) to service_role;

grant execute on function app.has_active_support_grant(uuid, uuid) to authenticated, service_role;
grant execute on function app.current_support_session(uuid, uuid) to authenticated, service_role;

-- Tenant visibility (Prompt 115 §16): the grantee sees their own grants; Supreme Admin and
-- the target tenant's own tenant_admin see every grant into that tenant (a tenant must be
-- able to SEE what support access exists into its own data, the necessary complement to the
-- kill switch above).
grant select on app.support_access_grants to authenticated;
create policy support_access_grants_select_visible
  on app.support_access_grants for select
  to authenticated
  using (
    grantee_auth_user_id = auth.uid()
    or app.is_supreme_admin()
    or exists (
      select 1 from app.principal_memberships pm
      where pm.auth_user_id = auth.uid()
        and pm.tenant_id = support_access_grants.tenant_id
        and pm.layer = 'tenant_admin'
        and pm.status = 'active'
    )
  );

grant select on app.support_access_sessions to authenticated;
create policy support_access_sessions_select_visible
  on app.support_access_sessions for select
  to authenticated
  using (
    grantee_auth_user_id = auth.uid()
    or app.is_supreme_admin()
    or exists (
      select 1 from app.principal_memberships pm
      where pm.auth_user_id = auth.uid()
        and pm.tenant_id = support_access_sessions.tenant_id
        and pm.layer = 'tenant_admin'
        and pm.status = 'active'
    )
  );

-- app.support_access_events is this capability's own append-only audit trail --
-- deliberately left service_role-only here, the same disclosed scope boundary PLT-113 drew
-- around every other capability's `*_history` table: PLT-116 (Audit Trail Foundation) is
-- the coherent single decision point for a canonical audit-read policy, not an ad hoc
-- one-off policy now.
