-- Platform Core capability PLT-110 (User Lifecycle, CG-S6-PLT-007)
-- The tenant-scoped user *profile* -- distinct from PLT-107's app.tenant_user_identities
-- (which only proves an auth identity is linked to a tenant, carrying no name/org/status
-- richness) and from PLT-108's app.principal_memberships (which carries the four-layer
-- context, not a profile). app.users composes both: every row requires an existing
-- app.tenant_user_identities linkage (composite FK, same discipline as PLT-108), and every
-- lifecycle transition here keeps that linkage and any active PLT-108 memberships in sync
-- rather than letting three tables drift independently.
--
-- Invite-by-email-before-signup (no auth_user_id yet) is disclosed NOT_RUN here, same as
-- PLT-107's own live-GoTrue-invite disclosure: app.tenant_user_identities already requires
-- an existing auth.users row via FK, so app.users (one layer above it) inherits the same
-- constraint. This checkpoint models inviting an *already-known* auth identity into a new
-- tenant, not a cold email invite to someone with no account anywhere.

create table app.users (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  auth_user_id uuid not null references auth.users (id),
  email text not null,
  display_name text not null,
  status text not null default 'invited',
  org_unit_id uuid references app.org_units (id),
  invited_by text,
  invited_at timestamptz not null default now(),
  invite_expires_at timestamptz not null,
  activated_at timestamptz,
  suspended_at timestamptz,
  suspended_reason text,
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint users_status_check
    check (status in ('invited', 'active', 'suspended', 'revoked')),
  constraint users_tenant_auth_user_unique unique (tenant_id, auth_user_id),
  constraint users_tenant_email_unique unique (tenant_id, email),
  -- The identity must already be linked to this tenant (PLT-107) before a profile can
  -- exist for it here -- the same "no orphan membership" discipline PLT-108 established.
  constraint users_identity_tenant_fk
    foreign key (auth_user_id, tenant_id)
    references app.tenant_user_identities (auth_user_id, tenant_id)
);

comment on table app.users is
  'Tenant-scoped user profile and lifecycle (PLT-110), layered on top of PLT-107''s identity linkage and kept in sync with PLT-108''s principal memberships on revoke. Not a role/permission table -- see PLT-111.';

create index users_tenant_id_idx on app.users (tenant_id);
create index users_auth_user_id_idx on app.users (auth_user_id);
create index users_org_unit_id_idx on app.users (org_unit_id);

create table app.user_lifecycle_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  tenant_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  reason text,
  requested_by text,
  occurred_at timestamptz not null default now(),
  constraint user_lifecycle_history_event_type_check
    check (event_type in ('invite', 'resend_invite', 'activate', 'suspend', 'reactivate', 'revoke', 'cancel_invite', 'org_reassign'))
);

create index user_lifecycle_history_user_id_idx
  on app.user_lifecycle_history (user_id, occurred_at desc);

create function app.touch_user_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger users_touch_row
  before update on app.users
  for each row
  execute function app.touch_user_row();

-- Valid transition matrix: invited -> active | revoked; active -> suspended | revoked;
-- suspended -> active | revoked; revoked is terminal -- same discipline as every prior
-- lifecycle table this session (PLT-105/107/108/109).
create function app.enforce_user_status_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status = 'revoked' then
    raise exception 'invalid_user_transition: user % is revoked, no further transition is allowed', old.id
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'invited' and new.status in ('active', 'revoked'))
    or (old.status = 'active' and new.status in ('suspended', 'revoked'))
    or (old.status = 'suspended' and new.status in ('active', 'revoked'))
  ) then
    raise exception 'invalid_user_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger users_enforce_transition
  before update of status on app.users
  for each row
  execute function app.enforce_user_status_transition();

-- Idempotent invitation -- composes app.link_auth_identity (PLT-107) to guarantee the
-- underlying identity linkage exists, then idempotently creates (or returns) the profile.
create function app.invite_user(
  p_tenant_id uuid,
  p_auth_user_id uuid,
  p_email text,
  p_display_name text,
  p_org_unit_id uuid,
  p_invited_by text,
  p_invite_expires_at timestamptz
)
returns app.users
language plpgsql
as $$
declare
  v_existing app.users;
  v_user app.users;
begin
  select * into v_existing from app.users where tenant_id = p_tenant_id and auth_user_id = p_auth_user_id;
  if found then
    return v_existing;
  end if;

  perform app.link_auth_identity(p_auth_user_id, p_tenant_id, p_invited_by, 'invited');

  insert into app.users (tenant_id, auth_user_id, email, display_name, org_unit_id, invited_by, invite_expires_at)
  values (p_tenant_id, p_auth_user_id, p_email, p_display_name, p_org_unit_id, p_invited_by, p_invite_expires_at)
  returning * into v_user;

  insert into app.user_lifecycle_history (user_id, tenant_id, event_type, from_status, to_status, requested_by)
  values (v_user.id, p_tenant_id, 'invite', null, 'invited', p_invited_by);

  return v_user;
end;
$$;

-- Extends a still-pending invitation's expiry. Only valid while status = 'invited' -- an
-- already-active/suspended/revoked user has nothing to "resend."
create function app.resend_invitation(
  p_id uuid,
  p_new_expires_at timestamptz,
  p_requested_by text
)
returns app.users
language plpgsql
as $$
declare
  v_current app.users;
  v_updated app.users;
begin
  select * into v_current from app.users where id = p_id;
  if not found then
    raise exception 'user_not_found: no user %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.status <> 'invited' then
    raise exception 'invalid_resend: user % is % , only a pending invitation can be resent', p_id, v_current.status
      using errcode = 'check_violation';
  end if;

  update app.users set invite_expires_at = p_new_expires_at where id = p_id returning * into v_updated;

  insert into app.user_lifecycle_history (user_id, tenant_id, event_type, from_status, to_status, requested_by)
  values (p_id, v_current.tenant_id, 'resend_invite', 'invited', 'invited', p_requested_by);

  return v_updated;
end;
$$;

-- The canonical status transition -- covers activate/suspend/reactivate/revoke/cancel-invite
-- (a cancel is simply invited -> revoked through this same function; the history event_type
-- below distinguishes it from a post-activation revoke).
--
-- Two integration behaviors run inside the same transaction (Prompt 110 §20 task 3):
-- (1) leaving 'active' toward 'suspended' or 'revoked' is blocked if this identity holds
-- the tenant's *only* active tenant_admin membership (PLT-108) -- "last critical admin"
-- protection (Prompt 110 §23); (2) reaching 'revoked' propagates real downstream cleanup:
-- the underlying PLT-107 identity linkage is revoked and every active PLT-108 principal
-- membership for this identity in this tenant is revoked too, so access does not
-- silently outlive the offboarding event.
create function app.transition_user_status(
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
    when p_new_status = 'revoked' then 'revoke'
    else p_new_status
  end;

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

  if p_new_status = 'active' and v_current.status = 'invited' then
    update app.tenant_user_identities
    set status = 'active'
    where auth_user_id = v_current.auth_user_id and tenant_id = v_current.tenant_id and status = 'invited';
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

  return v_updated;
end;
$$;

-- Org reassignment -- its own optimistic-concurrency-guarded function (Prompt 110 §20
-- task 2), matching PLT-109's move_org_unit discipline.
create function app.reassign_user_org_unit(
  p_id uuid,
  p_new_org_unit_id uuid,
  p_expected_version integer,
  p_requested_by text
)
returns app.users
language plpgsql
as $$
declare
  v_current app.users;
  v_updated app.users;
  v_org app.org_units;
begin
  select * into v_current from app.users where id = p_id;
  if not found then
    raise exception 'user_not_found: no user %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'user_version_conflict: expected version %, found %', p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;

  if p_new_org_unit_id is not null then
    select * into v_org from app.org_units where id = p_new_org_unit_id;
    if not found or v_org.tenant_id <> v_current.tenant_id then
      raise exception 'cross_tenant_org_unit: org unit % does not belong to tenant %', p_new_org_unit_id, v_current.tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  update app.users set org_unit_id = p_new_org_unit_id where id = p_id returning * into v_updated;

  insert into app.user_lifecycle_history (user_id, tenant_id, event_type, requested_by)
  values (p_id, v_current.tenant_id, 'org_reassign', p_requested_by);

  return v_updated;
end;
$$;

-- RLS: identical defense-in-depth posture to PLT-105/106/107/108/109.
alter table app.users enable row level security;
alter table app.user_lifecycle_history enable row level security;

grant select, insert, update, delete
  on app.users, app.user_lifecycle_history
  to service_role;
grant execute on function app.invite_user(uuid, uuid, text, text, uuid, text, timestamptz) to service_role;
grant execute on function app.resend_invitation(uuid, timestamptz, text) to service_role;
grant execute on function app.transition_user_status(uuid, text, text, text) to service_role;
grant execute on function app.reassign_user_org_unit(uuid, uuid, integer, text) to service_role;
