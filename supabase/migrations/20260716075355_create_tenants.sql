-- Platform Core capability PLT-105 (Tenant Provisioning and Lifecycle, CG-S6-PLT-002)
-- Tenant control-plane table + canonical lifecycle state machine + status history.
--
-- Schema decision: single flat `app` schema (docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md
-- §1/§3, resolved ADR-CAND-ARCH-007) -- no per-domain schema.
--
-- RLS decision: enabled from this table's own creation (Tech Arch §11 "RLS mandatory"), but
-- Prompt 105 does not implement the general tenant-scoping policy pattern -- that is Prompt 113's
-- own capability (RLS tenant policy foundation). This table's own posture is the correct minimal
-- real policy for *this* table specifically: `app.tenants` is the tenant registry itself, has no
-- parent tenant_id to scope by, and only the Supreme Admin control plane (server-side,
-- service-role) may read/write it directly (Prompt 105 §16/§26: "Only authorized Supreme control
-- plane provisions/terminates ... strict tenant context and no service-role client exposure").
-- Default-deny RLS (no policy for anon/authenticated) plus Supabase's standard service_role
-- BYPASSRLS grant achieves exactly that -- real and enforced today, not a placeholder.

create schema if not exists app;

create extension if not exists pgcrypto;

create table app.tenants (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  name text not null,
  canonical_status text not null default 'provisioning',
  plan_snapshot jsonb not null default '{}'::jsonb,
  idempotency_key text not null,
  requested_by text,
  reason text,
  legal_hold boolean not null default false,
  record_version integer not null default 1,
  effective_from timestamptz,
  effective_until timestamptz,
  activated_at timestamptz,
  deactivated_at timestamptz,
  terminated_at timestamptz,
  created_by text,
  updated_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenants_canonical_status_check
    check (canonical_status in ('provisioning', 'active', 'suspended', 'terminated')),
  constraint tenants_slug_format
    check (slug ~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'),
  constraint tenants_slug_unique unique (slug),
  constraint tenants_idempotency_key_unique unique (idempotency_key)
);

comment on table app.tenants is
  'Tenant control-plane registry (PLT-105). Canonical lifecycle: provisioning -> active -> suspended -> active (reactivate) -> terminated (terminal). No hard delete -- RPD-022/retention obligations (see app.tenant_status_history for the full transition trail).';

create index tenants_canonical_status_idx on app.tenants (canonical_status);

-- Append-only transition trail (this task's own bounded, lifecycle-scoped audit log --
-- deliberately not the generic audit_log table PLT-116/AUD owns; recording exactly the fields
-- Prompt 105 §18 requires: requester, reason, plan/config snapshot, transitions, bootstrap
-- effects and failures).
create table app.tenant_status_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  from_status text,
  to_status text not null,
  reason text,
  requested_by text,
  occurred_at timestamptz not null default now()
);

comment on table app.tenant_status_history is
  'Append-only tenant lifecycle transition trail (PLT-105). Every provision/activate/suspend/reactivate/terminate call appends exactly one row here, including failed/rejected transition attempts recorded by the caller.';

create index tenant_status_history_tenant_id_idx
  on app.tenant_status_history (tenant_id, occurred_at desc);

-- Valid transition matrix (Prompt 105 §20 task 1/§24: "Tenant lifecycle is canonical and cannot
-- be hard-coded per customer" -- the matrix below is the one canonical definition, enforced in
-- the database, not duplicated or overridable in application code):
--   provisioning -> active       (bootstrap completed)
--   provisioning -> terminated   (bootstrap failed / rejected before ever going live)
--   active       -> suspended
--   active       -> terminated
--   suspended    -> active       (reactivate)
--   suspended    -> terminated
--   terminated   -> (none; terminal state)
create function app.enforce_tenant_status_transition()
returns trigger
language plpgsql
as $$
begin
  if new.canonical_status = old.canonical_status then
    return new;
  end if;

  if old.canonical_status = 'terminated' then
    raise exception 'invalid_tenant_transition: tenant % is terminated, no further transition is allowed', old.id
      using errcode = 'check_violation';
  end if;

  if not (
    (old.canonical_status = 'provisioning' and new.canonical_status in ('active', 'terminated'))
    or (old.canonical_status = 'active' and new.canonical_status in ('suspended', 'terminated'))
    or (old.canonical_status = 'suspended' and new.canonical_status in ('active', 'terminated'))
  ) then
    raise exception 'invalid_tenant_transition: % -> % is not a canonical transition', old.canonical_status, new.canonical_status
      using errcode = 'check_violation';
  end if;

  if new.canonical_status = 'terminated' and old.legal_hold then
    raise exception 'invalid_tenant_transition: tenant % has an active legal hold and cannot be terminated', old.id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger tenants_enforce_transition
  before update of canonical_status on app.tenants
  for each row
  execute function app.enforce_tenant_status_transition();

create function app.touch_tenant_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenants_touch_row
  before update on app.tenants
  for each row
  execute function app.touch_tenant_row();

-- Idempotent transactional provisioning (Prompt 105 §20 task 2/§22: "Retry with same idempotency
-- key returns/reconciles prior result"). A second call with the same idempotency_key is a no-op
-- that returns the original row, never a duplicate tenant -- proven in
-- scripts/db-tests/tenant-lifecycle.sql, not merely asserted here.
create function app.provision_tenant(
  p_slug text,
  p_name text,
  p_idempotency_key text,
  p_requested_by text,
  p_plan_snapshot jsonb default '{}'::jsonb
)
returns app.tenants
language plpgsql
as $$
declare
  v_existing app.tenants;
  v_tenant app.tenants;
begin
  select * into v_existing from app.tenants where idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  insert into app.tenants (slug, name, idempotency_key, requested_by, plan_snapshot, created_by, updated_by)
  values (p_slug, p_name, p_idempotency_key, p_requested_by, p_plan_snapshot, p_requested_by, p_requested_by)
  returning * into v_tenant;

  insert into app.tenant_status_history (tenant_id, from_status, to_status, reason, requested_by)
  values (v_tenant.id, null, 'provisioning', 'initial provisioning request', p_requested_by);

  return v_tenant;
end;
$$;

comment on function app.provision_tenant is
  'Idempotent tenant provisioning entry point (PLT-105). A duplicate call with the same idempotency_key returns the original row unchanged -- never inserts a second tenant. Raises a unique_violation if p_slug is already claimed by a different idempotency_key (duplicate-domain exception flow, Prompt 105 §23).';

-- Guarded state transition (Prompt 105 §20 task 3: suspend/reactivate/terminate without unsafe
-- deletion). The transition-validity check itself lives in the trigger above so it cannot be
-- bypassed by any other write path to this table -- this function is the *recommended* entry
-- point (records reason/requester into the history trail), not the only enforcement layer.
create function app.transition_tenant_status(
  p_tenant_id uuid,
  p_new_status text,
  p_reason text,
  p_requested_by text
)
returns app.tenants
language plpgsql
as $$
declare
  v_old_status text;
  v_tenant app.tenants;
begin
  select canonical_status into v_old_status from app.tenants where id = p_tenant_id for update;
  if not found then
    raise exception 'tenant_not_found: no tenant with id %', p_tenant_id
      using errcode = 'no_data_found';
  end if;

  update app.tenants
  set
    canonical_status = p_new_status,
    reason = p_reason,
    updated_by = p_requested_by,
    activated_at = case when p_new_status = 'active' then now() else activated_at end,
    deactivated_at = case when p_new_status = 'suspended' then now() else deactivated_at end,
    terminated_at = case when p_new_status = 'terminated' then now() else terminated_at end
  where id = p_tenant_id
  returning * into v_tenant;

  insert into app.tenant_status_history (tenant_id, from_status, to_status, reason, requested_by)
  values (p_tenant_id, v_old_status, p_new_status, p_reason, p_requested_by);

  return v_tenant;
end;
$$;

comment on function app.transition_tenant_status is
  'Guarded tenant lifecycle transition (PLT-105). The canonical transition matrix is enforced by the tenants_enforce_transition trigger regardless of entry point; this function additionally records requester/reason into app.tenant_status_history and stamps the relevant lifecycle timestamp.';

-- RLS: enabled from creation, default-deny for anon/authenticated (no policy is granted to
-- either role below), service_role bypasses via Supabase's standard BYPASSRLS grant on that role.
-- Real, enforced today -- not deferred to Prompt 113, which builds the *general* tenant-scoping
-- pattern for tenant-owned business tables, a different (later) concern from this table's own
-- Supreme-Admin-only access model.
alter table app.tenants enable row level security;
alter table app.tenant_status_history enable row level security;

-- Defense in depth, deliberately stronger than "RLS alone": anon/authenticated receive no
-- schema-level USAGE grant on `app` at all for this migration, so a direct query against
-- app.tenants from either role fails at the privilege-check layer before RLS is even evaluated
-- (Prompt 105 §16: "no service-role client exposure" -- this table is never meant to be reachable
-- from a browser/anon-authenticated client, only from server-side code holding service_role).
-- service_role needs an *explicit* grant here too -- BYPASSRLS only bypasses row security, not
-- the underlying GRANT-based schema/table/function privilege checks.
grant usage on schema app to service_role;
grant select, insert, update, delete on app.tenants, app.tenant_status_history to service_role;
grant execute on function app.provision_tenant(text, text, text, text, jsonb) to service_role;
grant execute on function app.transition_tenant_status(uuid, text, text, text) to service_role;
