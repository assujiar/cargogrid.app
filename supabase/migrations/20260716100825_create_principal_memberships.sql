-- Platform Core capability PLT-108 (Four-Layer Identity and Access Context, CG-S6-PLT-005)
-- Adds the "layer" dimension on top of PLT-107's tenant_user_identities linkage: which of
-- the four canonical principals (Supreme Admin, Tenant Admin, tenant organizational user,
-- customer user) an already-linked identity is entitled to act as, and in what tenant/
-- customer scope. This is context, not permission -- Prompt 108 §24: "Layer is not
-- permission; RBAC/scope/field/record still required" (PLT-111/112/113/114 own those).
--
-- Supreme Admin is modeled as a global, cross-tenant grant (tenant_id is null) --
-- RPD-022's disclosed absolute-CRUD exception (docs/architecture/06_RLS_RBAC_WORKSTREAM.md
-- §8). A Supreme Admin acting *inside* a specific tenant's data (support/troubleshooting)
-- does not get there through this table -- that is a separate, time-bound, reason-logged
-- grant owned by PLT-115 (Support Access and Impersonation). Keeping the two mechanisms
-- distinct is a deliberate scope boundary, not an oversight: an ordinary membership row
-- here is never expiring/reason-gated, so it must never carry cross-tenant reach.
--
-- No customers/companies/branches table exists yet in this repository (companies/branches
-- belong to PLT-109 Organization Hierarchy; a business-domain "customers" table belongs to
-- a later phase's CRM module, never Platform Core). customer_account_ref is therefore a
-- reserved scope-dimension placeholder (free-text external reference), not a live foreign
-- key -- disclosed rather than fabricating a table this prompt is not scoped to create.

create table app.principal_memberships (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users (id),
  layer text not null,
  tenant_id uuid references app.tenants (id),
  customer_account_ref text,
  status text not null default 'active',
  granted_by text,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint principal_memberships_layer_check
    check (layer in ('supreme_admin', 'tenant_admin', 'org_user', 'customer_user')),
  constraint principal_memberships_status_check
    check (status in ('active', 'suspended', 'revoked')),
  -- Layer-to-scope shape: exactly the dimensions each layer is allowed to carry, no more.
  constraint principal_memberships_layer_scope_shape check (
    (layer = 'supreme_admin' and tenant_id is null and customer_account_ref is null)
    or (layer in ('tenant_admin', 'org_user') and tenant_id is not null and customer_account_ref is null)
    or (layer = 'customer_user' and tenant_id is not null and customer_account_ref is not null)
  ),
  -- A membership can only be granted for an identity already linked to that tenant
  -- (PLT-107). Composite FK is a no-op for supreme_admin rows (tenant_id is null, so
  -- Postgres MATCH SIMPLE does not enforce it) -- that is intentional, not a gap.
  constraint principal_memberships_identity_tenant_fk
    foreign key (auth_user_id, tenant_id)
    references app.tenant_user_identities (auth_user_id, tenant_id)
);

comment on table app.principal_memberships is
  'The four-layer principal grant (PLT-108): which layer (supreme_admin/tenant_admin/org_user/customer_user) an auth identity may resolve a context as, in what tenant/customer scope. Context, not permission -- see table comment header in the defining migration.';

create index principal_memberships_auth_user_id_idx on app.principal_memberships (auth_user_id);
create index principal_memberships_tenant_id_idx on app.principal_memberships (tenant_id);

-- One active row per (identity, tenant, layer, customer_account_ref) -- the coalesce keeps
-- the uniqueness meaningful even though customer_account_ref is null for non-customer
-- layers and Postgres would otherwise treat every null as distinct.
create unique index principal_memberships_active_unique
  on app.principal_memberships (auth_user_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), layer, coalesce(customer_account_ref, ''))
  where status = 'active';

create table app.principal_membership_history (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null,
  auth_user_id uuid not null,
  layer text not null,
  tenant_id uuid,
  customer_account_ref text,
  from_status text,
  to_status text not null,
  reason text,
  requested_by text,
  occurred_at timestamptz not null default now()
);

create index principal_membership_history_membership_id_idx
  on app.principal_membership_history (membership_id, occurred_at desc);

-- Valid transition matrix: active -> suspended | revoked; suspended -> active | revoked;
-- revoked is terminal (same "never resurrected in place" discipline as PLT-107's identity
-- links -- re-granting is a new row, preserving an unambiguous grant/revoke history).
create function app.enforce_principal_membership_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status = 'revoked' then
    raise exception 'invalid_membership_transition: membership % is revoked, no further transition is allowed', old.id
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'active' and new.status in ('suspended', 'revoked'))
    or (old.status = 'suspended' and new.status in ('active', 'revoked'))
  ) then
    raise exception 'invalid_membership_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger principal_memberships_enforce_transition
  before update of status on app.principal_memberships
  for each row
  execute function app.enforce_principal_membership_transition();

create function app.touch_principal_membership_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger principal_memberships_touch_row
  before update on app.principal_memberships
  for each row
  execute function app.touch_principal_membership_row();

-- Idempotent grant -- a repeated grant for the same (identity, tenant, layer,
-- customer_account_ref) returns the existing active row rather than raising or
-- duplicating, matching the established PLT-105/107 idempotency pattern.
create function app.grant_principal_membership(
  p_auth_user_id uuid,
  p_layer text,
  p_tenant_id uuid,
  p_customer_account_ref text,
  p_granted_by text
)
returns app.principal_memberships
language plpgsql
as $$
declare
  v_existing app.principal_memberships;
  v_membership app.principal_memberships;
begin
  select * into v_existing
  from app.principal_memberships
  where auth_user_id = p_auth_user_id
    and layer = p_layer
    and tenant_id is not distinct from p_tenant_id
    and customer_account_ref is not distinct from p_customer_account_ref
    and status = 'active';

  if found then
    return v_existing;
  end if;

  insert into app.principal_memberships (auth_user_id, layer, tenant_id, customer_account_ref, granted_by)
  values (p_auth_user_id, p_layer, p_tenant_id, p_customer_account_ref, p_granted_by)
  returning * into v_membership;

  insert into app.principal_membership_history
    (membership_id, auth_user_id, layer, tenant_id, customer_account_ref, from_status, to_status, reason, requested_by)
  values (v_membership.id, p_auth_user_id, p_layer, p_tenant_id, p_customer_account_ref, null, 'active', 'membership granted', p_granted_by);

  return v_membership;
end;
$$;

create function app.revoke_principal_membership(
  p_membership_id uuid,
  p_reason text,
  p_requested_by text
)
returns app.principal_memberships
language plpgsql
as $$
declare
  v_current app.principal_memberships;
  v_updated app.principal_memberships;
begin
  select * into v_current from app.principal_memberships where id = p_membership_id;

  if not found then
    raise exception 'principal_membership_not_found: no membership %', p_membership_id
      using errcode = 'no_data_found';
  end if;

  update app.principal_memberships
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = p_membership_id
  returning * into v_updated;

  insert into app.principal_membership_history
    (membership_id, auth_user_id, layer, tenant_id, customer_account_ref, from_status, to_status, reason, requested_by)
  values (v_current.id, v_current.auth_user_id, v_current.layer, v_current.tenant_id, v_current.customer_account_ref, v_current.status, 'revoked', p_reason, p_requested_by);

  return v_updated;
end;
$$;

-- The context resolver -- the concrete mechanism behind Prompt 108's acceptance criterion
-- "every request obtains one unforgeable canonical access context or fails closed."
-- Unlike PLT-106's evaluate_entitlement (which returns an allowed/denied *decision* record
-- because UI callers need the reason/limit even on denial), this always either returns
-- exactly one resolved context row or raises -- there is no "resolved but denied" shape,
-- because a context is an identity fact, not a permission decision (Prompt 108 §24).
create type app.access_context as (
  membership_id uuid,
  auth_user_id uuid,
  layer text,
  tenant_id uuid,
  customer_account_ref text,
  resolved_at timestamptz
);

create function app.resolve_access_context(
  p_auth_user_id uuid,
  p_tenant_id uuid default null,
  p_customer_account_ref text default null
)
returns app.access_context
language plpgsql
stable
as $$
declare
  v_membership app.principal_memberships;
  v_match_count integer;
begin
  if p_tenant_id is null then
    -- Global request: a live Supreme Admin grant always resolves first and alone --
    -- Supreme Admin never shares an unqualified request with a tenant-scoped layer.
    select * into v_membership
    from app.principal_memberships
    where auth_user_id = p_auth_user_id and layer = 'supreme_admin' and status = 'active';

    if found then
      return row(v_membership.id, v_membership.auth_user_id, v_membership.layer, v_membership.tenant_id, v_membership.customer_account_ref, now())::app.access_context;
    end if;

    select count(*) into v_match_count
    from app.principal_memberships
    where auth_user_id = p_auth_user_id and status = 'active';

    if v_match_count = 0 then
      raise exception 'no_active_membership: identity % holds no active principal membership', p_auth_user_id
        using errcode = 'no_data_found';
    elsif v_match_count > 1 then
      raise exception 'ambiguous_context: identity % holds % active memberships, tenant_id must be specified', p_auth_user_id, v_match_count
        using errcode = 'check_violation';
    end if;

    select * into v_membership
    from app.principal_memberships
    where auth_user_id = p_auth_user_id and status = 'active';

    return row(v_membership.id, v_membership.auth_user_id, v_membership.layer, v_membership.tenant_id, v_membership.customer_account_ref, now())::app.access_context;
  end if;

  -- Tenant-qualified request: the target tenant must itself be active -- an inactive
  -- tenant fails closed regardless of membership state (Prompt 108 §23).
  if not exists (select 1 from app.tenants where id = p_tenant_id and canonical_status = 'active') then
    raise exception 'inactive_tenant: tenant % is not active' , p_tenant_id
      using errcode = 'check_violation';
  end if;

  -- The underlying identity linkage (PLT-107) must itself be active, not merely invited
  -- or already revoked -- authentication proves identity, membership proves layer, and
  -- both must independently be live.
  if not exists (
    select 1 from app.tenant_user_identities
    where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id and status = 'active'
  ) then
    raise exception 'inactive_identity_link: identity % has no active linkage to tenant %', p_auth_user_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select count(*) into v_match_count
  from app.principal_memberships
  where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id and status = 'active'
    and (p_customer_account_ref is null or customer_account_ref = p_customer_account_ref);

  if v_match_count = 0 then
    raise exception 'no_active_membership_for_tenant: identity % holds no active membership in tenant %', p_auth_user_id, p_tenant_id
      using errcode = 'no_data_found';
  elsif v_match_count > 1 then
    raise exception 'ambiguous_context: identity % holds % active memberships in tenant %, customer_account_ref must be specified', p_auth_user_id, v_match_count, p_tenant_id
      using errcode = 'check_violation';
  end if;

  select * into v_membership
  from app.principal_memberships
  where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id and status = 'active'
    and (p_customer_account_ref is null or customer_account_ref = p_customer_account_ref);

  return row(v_membership.id, v_membership.auth_user_id, v_membership.layer, v_membership.tenant_id, v_membership.customer_account_ref, now())::app.access_context;
end;
$$;

-- RLS: identical defense-in-depth posture to PLT-105/106/107.
alter table app.principal_memberships enable row level security;
alter table app.principal_membership_history enable row level security;

grant select, insert, update, delete
  on app.principal_memberships, app.principal_membership_history
  to service_role;
grant execute on function app.grant_principal_membership(uuid, text, uuid, text, text) to service_role;
grant execute on function app.revoke_principal_membership(uuid, text, text) to service_role;
grant execute on function app.resolve_access_context(uuid, uuid, text) to service_role;
