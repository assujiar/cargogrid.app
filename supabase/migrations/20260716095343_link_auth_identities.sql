-- Platform Core capability PLT-107 (Supabase Auth Integration, CG-S6-PLT-004)
-- Links a Supabase-managed auth identity (auth.users.id) to one or more tenants via a
-- new app.tenant_user_identities table. Authentication proves identity only --
-- entitlement/RBAC/RLS still determine access (Prompt 107 §24); this migration grants
-- no role/permission by itself.
--
-- IMPORTANT: this migration never creates, alters, or grants on the `auth` schema
-- itself. In any real deployment, Supabase provisions and owns `auth.users` (identity,
-- password/OAuth/MFA state) -- this repository's migrations only ever *reference* it
-- via a foreign key, the same pattern every official Supabase project example uses.
-- No live Supabase project exists yet for this repository (ADR-0010, PH0-094): this
-- migration is applied against a local-only test-fixture `auth.users` stub
-- (scripts/db-tests/fixtures/auth-schema-stub.sql, NOT part of this migration set,
-- never shipped to a real project) purely so the FK/linkage/RLS logic below can be
-- proven for real today, disclosed rather than skipped.

create table app.tenant_user_identities (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users (id),
  tenant_id uuid not null references app.tenants (id),
  status text not null default 'invited',
  invited_by text,
  invited_at timestamptz not null default now(),
  activated_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  mfa_enrolled boolean not null default false,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_user_identities_status_check
    check (status in ('invited', 'active', 'revoked')),
  constraint tenant_user_identities_identity_tenant_unique unique (auth_user_id, tenant_id)
);

comment on table app.tenant_user_identities is
  'Links a Supabase-managed auth identity (auth.users.id) to a tenant (PLT-107). One identity may be linked to multiple tenants (the four-layer model does not assume single-tenant membership). Authentication (this table) is deliberately separate from role/permission (PLT-111/112) -- linkage alone grants no access.';

create index tenant_user_identities_tenant_id_idx on app.tenant_user_identities (tenant_id);
create index tenant_user_identities_auth_user_id_idx on app.tenant_user_identities (auth_user_id);

create table app.tenant_user_identity_history (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  tenant_id uuid not null references app.tenants (id),
  from_status text,
  to_status text not null,
  reason text,
  requested_by text,
  occurred_at timestamptz not null default now()
);

create index tenant_user_identity_history_tenant_id_idx
  on app.tenant_user_identity_history (tenant_id, occurred_at desc);

-- Valid transition matrix: invited -> active | revoked; active -> revoked; revoked is
-- terminal (a revoked identity is re-invited as a *new* row, never resurrected in place
-- -- preserves an unambiguous history of every grant/revoke cycle).
create function app.enforce_identity_link_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status = 'revoked' then
    raise exception 'invalid_identity_transition: identity link % is revoked, no further transition is allowed', old.id
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'invited' and new.status in ('active', 'revoked'))
    or (old.status = 'active' and new.status = 'revoked')
  ) then
    raise exception 'invalid_identity_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger tenant_user_identities_enforce_transition
  before update of status on app.tenant_user_identities
  for each row
  execute function app.enforce_identity_link_transition();

create function app.touch_tenant_user_identity_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenant_user_identities_touch_row
  before update on app.tenant_user_identities
  for each row
  execute function app.touch_tenant_user_identity_row();

-- Idempotent invitation/linkage (Prompt 107 §25: "No account enumeration or orphan/
-- duplicate membership") -- a repeated invite for the same (auth_user_id, tenant_id)
-- pair returns the existing row rather than raising, matching app.provision_tenant's
-- established idempotency pattern from PLT-105.
create function app.link_auth_identity(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_invited_by text,
  p_status text default 'invited'
)
returns app.tenant_user_identities
language plpgsql
as $$
declare
  v_existing app.tenant_user_identities;
  v_link app.tenant_user_identities;
begin
  select * into v_existing
  from app.tenant_user_identities
  where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id;

  if found then
    return v_existing;
  end if;

  insert into app.tenant_user_identities (auth_user_id, tenant_id, status, invited_by, activated_at)
  values (p_auth_user_id, p_tenant_id, p_status, p_invited_by, case when p_status = 'active' then now() else null end)
  returning * into v_link;

  insert into app.tenant_user_identity_history (auth_user_id, tenant_id, from_status, to_status, reason, requested_by)
  values (p_auth_user_id, p_tenant_id, null, p_status, 'identity linked', p_invited_by);

  return v_link;
end;
$$;

create function app.revoke_auth_identity(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_reason text,
  p_requested_by text
)
returns app.tenant_user_identities
language plpgsql
as $$
declare
  v_current app.tenant_user_identities;
  v_updated app.tenant_user_identities;
begin
  select * into v_current
  from app.tenant_user_identities
  where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id;

  if not found then
    raise exception 'identity_link_not_found: no linkage for auth_user % and tenant %', p_auth_user_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  update app.tenant_user_identities
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = v_current.id
  returning * into v_updated;

  insert into app.tenant_user_identity_history (auth_user_id, tenant_id, from_status, to_status, reason, requested_by)
  values (p_auth_user_id, p_tenant_id, v_current.status, 'revoked', p_reason, p_requested_by);

  return v_updated;
end;
$$;

-- RLS: identical defense-in-depth posture to PLT-105/106.
alter table app.tenant_user_identities enable row level security;
alter table app.tenant_user_identity_history enable row level security;

grant select, insert, update, delete
  on app.tenant_user_identities, app.tenant_user_identity_history
  to service_role;
grant execute on function app.link_auth_identity(uuid, uuid, text, text) to service_role;
grant execute on function app.revoke_auth_identity(uuid, uuid, text, text) to service_role;
