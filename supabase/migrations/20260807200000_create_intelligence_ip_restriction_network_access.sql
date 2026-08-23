-- IAE-028 (Prompt 356, Group 7): IP Restriction and Network Access.
--
-- Design decisions (cited, not re-derived):
--
-- 1. Real CIDR containment, not string matching -- app.ip_allowlist_entries.
--    cidr is a genuine Postgres `cidr` column; app.assert_ip_allowed uses the
--    native `<<=` containment operator, correctly handling both IPv4 and
--    IPv6 (Prompt 356 §20 "Test IPv4/IPv6") for free, since `inet`/`cidr` are
--    Postgres built-in types, not a repository-authored parser.
-- 2. Dry-run is a real, structural enforcement MODE, not a UI toggle:
--    app.ip_allowlist_policies.enforcement_mode ('disabled'|'dry_run'|
--    'enforced') -- app.assert_ip_allowed NEVER denies while dry_run, only
--    logs what it WOULD have denied (Prompt 356 §20/§21 "dry-run/test before
--    enforcement to prevent lockout"). Moving disabled->dry_run->enforced is
--    the only supported path (app.set_ip_allowlist_enforcement_mode);
--    enforced->disabled (the real break-glass rollback) has no precondition.
-- 3. Reuses the `SEC` entitlement module (IAE-027, Configure/View/Approve) --
--    IP restriction is this same "Enterprise Security" workstream's third
--    capability; no new module.
-- 4. Emergency bypass mirrors app.mfa_exceptions'/app.support_access_grants'
--    own break-glass shape exactly: SEC:Approve-gated, a real higher-
--    authority grant, short CHECK-enforced expiry, target-actor-scoped.
-- 5. Proxy/header trust ("deployment-aware and spoof-resistant", Prompt 356
--    §24) is an APPLICATION-LAYER concern (which header a Next.js middleware
--    trusts to derive the real client IP) -- this checkpoint's own functions
--    take an already-resolved IP address as a plain parameter and never
--    parse a raw request header themselves. Disclosed, not built: the
--    middleware.ts change that would derive and pass that IP on every
--    request (no dedicated UI/middleware wiring ships this checkpoint,
--    consistent with `IAE-026`/`IAE-027`'s own scope decision).
-- 6. Denied (and dry-run-would-deny) access is logged to a real, append-only
--    table (app.ip_access_evaluations) -- the "denied access logging"
--    requirement (Prompt 356 §20).
-- 7. Every authenticated-reachable function is `SECURITY DEFINER` paired
--    with `app.assert_actor_is_session_identity` as its first statement.
-- 8. Per the standing convention since `PLT-118`: explicit, redundant
--    `revoke execute on all functions in schema app from public`.

-- ===========================================================================
-- 1. app.ip_allowlist_policies -- one row per tenant, real enforcement mode.
-- ===========================================================================

create table app.ip_allowlist_policies (
  tenant_id uuid primary key references app.tenants (id),
  enforcement_mode text not null default 'disabled',
  updated_by text,
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint ip_allowlist_policies_mode_check check (enforcement_mode in ('disabled', 'dry_run', 'enforced'))
);

create function app.touch_ip_allowlist_policy_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger ip_allowlist_policies_touch_row
  before update on app.ip_allowlist_policies
  for each row
  execute function app.touch_ip_allowlist_policy_row();

create function app._get_or_create_ip_allowlist_policy(p_tenant_id uuid)
returns app.ip_allowlist_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.ip_allowlist_policies;
begin
  select * into v_policy from app.ip_allowlist_policies where tenant_id = p_tenant_id;
  if found then
    return v_policy;
  end if;

  -- Tier C review fix (correctness/concurrency lens): two concurrent
  -- bootstrap calls for the same brand-new tenant both pass the SELECT
  -- above, then the loser's own plain INSERT raised a raw, unhandled
  -- duplicate-key error on the primary key -- live-reproduced through the
  -- real app.set_ip_allowlist_enforcement_mode entrypoint, not merely this
  -- internal helper. `on conflict do nothing` + re-select makes the loser
  -- fall through to the winner's own row instead.
  insert into app.ip_allowlist_policies (tenant_id) values (p_tenant_id)
  on conflict (tenant_id) do nothing
  returning * into v_policy;
  if not found then
    select * into v_policy from app.ip_allowlist_policies where tenant_id = p_tenant_id;
  end if;
  return v_policy;
end;
$$;

comment on function app._get_or_create_ip_allowlist_policy is
  'IAE-028: internal-only bootstrap primitive, no actor/authority parameter -- never granted to anon/authenticated. Called internally by app.set_ip_allowlist_enforcement_mode (already SEC:Configure-gated) and by the actor-gated app.get_or_create_ip_allowlist_policy below.';

create function app.get_or_create_ip_allowlist_policy(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.ip_allowlist_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return app._get_or_create_ip_allowlist_policy(p_tenant_id);
end;
$$;

comment on function app.get_or_create_ip_allowlist_policy is
  'IAE-028: idempotent default-row bootstrap, SEC:View-gated -- a tenant with no explicit policy yet still has real, sensible defaults. Originally shipped with no actor/authority parameter at all (any authenticated identity of any tenant could read, and silently bootstrap, another tenant''s own IP allowlist policy) -- caught and fixed by this checkpoint''s own ATW-032/ISS-2026-033 authority-surface sweep before ever being committed.';

create function app.set_ip_allowlist_enforcement_mode(
  p_tenant_id uuid,
  p_enforcement_mode text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ip_allowlist_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.ip_allowlist_policies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_enforcement_mode not in ('disabled', 'dry_run', 'enforced') then
    raise exception 'ip_allowlist_invalid_mode: % is not one of disabled/dry_run/enforced', p_enforcement_mode using errcode = 'check_violation';
  end if;

  perform app._get_or_create_ip_allowlist_policy(p_tenant_id);

  if p_enforcement_mode = 'enforced' and not exists (
    select 1 from app.ip_allowlist_entries where tenant_id = p_tenant_id and status = 'active'
  ) then
    raise exception 'ip_allowlist_no_active_entries: cannot enforce with zero active allowlist entries -- this would lock out every caller'
      using errcode = 'check_violation';
  end if;

  update app.ip_allowlist_policies
  set enforcement_mode = p_enforcement_mode, updated_by = p_actor_label
  where tenant_id = p_tenant_id
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_ip_allowlist_enforcement_mode',
    'app.ip_allowlist_policies', null, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$$;

comment on function app.set_ip_allowlist_enforcement_mode is
  'IAE-028: the structural lockout guard (Prompt 356 §20/§21 "prevent lockout") -- moving to enforced requires at least one active allowlist entry to already exist; moving to dry_run or disabled has no such precondition, the real break-glass rollback path.';

-- ===========================================================================
-- 2. app.ip_allowlist_entries -- real CIDR entries (design decision 1).
-- ===========================================================================

create table app.ip_allowlist_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  cidr cidr not null,
  label text,
  scope text not null default 'all',
  status text not null default 'active',
  created_by_auth_user_id uuid references auth.users (id),
  created_by text,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by text,
  constraint ip_allowlist_entries_scope_check check (scope in ('ui', 'api', 'admin', 'all')),
  constraint ip_allowlist_entries_status_check check (status in ('active', 'revoked'))
);

create index ip_allowlist_entries_tenant_id_idx on app.ip_allowlist_entries (tenant_id, status);

create function app._parse_cidr(p_raw_cidr text)
returns cidr
language plpgsql
immutable
as $$
begin
  if p_raw_cidr is null or length(trim(p_raw_cidr)) = 0 then
    return null;
  end if;
  return trim(p_raw_cidr)::cidr;
exception
  when others then
    return null;
end;
$$;

comment on function app._parse_cidr is
  'IAE-028: defensive CIDR extraction, mirroring Group 6''s own established "_parse_*, never raise" shape for untrusted input -- an admin-typed CIDR string is exactly as untrusted as an AI provider''s own output.';

create function app.add_ip_allowlist_entry(
  p_tenant_id uuid,
  p_raw_cidr text,
  p_label text,
  p_scope text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ip_allowlist_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_cidr cidr;
  v_entry app.ip_allowlist_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_cidr := app._parse_cidr(p_raw_cidr);
  if v_cidr is null then
    raise exception 'ip_allowlist_invalid_cidr: % is not a well-formed IPv4/IPv6 CIDR', p_raw_cidr using errcode = 'invalid_text_representation';
  end if;

  if coalesce(p_scope, 'all') not in ('ui', 'api', 'admin', 'all') then
    raise exception 'ip_allowlist_invalid_scope: % is not one of ui/api/admin/all', p_scope using errcode = 'check_violation';
  end if;

  insert into app.ip_allowlist_entries (tenant_id, cidr, label, scope, created_by_auth_user_id, created_by)
  values (p_tenant_id, v_cidr, p_label, coalesce(p_scope, 'all'), p_actor_auth_user_id, p_actor_label)
  returning * into v_entry;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'add_ip_allowlist_entry',
    'app.ip_allowlist_entries', v_entry.id, 'success', null, null, to_jsonb(v_entry)
  );

  return v_entry;
end;
$$;

create function app.revoke_ip_allowlist_entry(
  p_entry_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ip_allowlist_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_entry app.ip_allowlist_entries;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_entry from app.ip_allowlist_entries where id = p_entry_id and status = 'active' for update;
  if not found then
    raise exception 'ip_allowlist_entry_not_active: % is not an active entry', p_entry_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_entry.tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_entry.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.ip_allowlist_entries
  set status = 'revoked', revoked_at = now(), revoked_by = p_actor_label
  where id = p_entry_id
  returning * into v_entry;

  perform app.capture_audit_event(
    v_entry.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_ip_allowlist_entry',
    'app.ip_allowlist_entries', v_entry.id, 'success', null, null, to_jsonb(v_entry)
  );

  return v_entry;
end;
$$;

-- ===========================================================================
-- 3. app.ip_access_evaluations -- append-only denied/dry-run-would-deny log
-- (design decision 6), and app.assert_ip_allowed -- the real enforcement gate.
-- ===========================================================================

create table app.ip_access_evaluations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  subject_label text,
  ip_address text not null,
  scope text not null,
  decision text not null,
  matched_entry_id uuid references app.ip_allowlist_entries (id),
  occurred_at timestamptz not null default now(),
  constraint ip_access_evaluations_decision_check check (decision in ('allowed', 'denied', 'dry_run_would_deny'))
);

create index ip_access_evaluations_tenant_id_idx on app.ip_access_evaluations (tenant_id, occurred_at desc);

create function app.assert_ip_allowed(
  p_tenant_id uuid,
  p_raw_ip_address text,
  p_scope text,
  p_subject_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.ip_allowlist_policies;
  v_ip inet;
  v_matched app.ip_allowlist_entries;
  v_decision text;
begin
  select * into v_policy from app.ip_allowlist_policies where tenant_id = p_tenant_id;
  if not found or v_policy.enforcement_mode = 'disabled' then
    return;
  end if;

  begin
    v_ip := trim(coalesce(p_raw_ip_address, ''))::inet;
  exception
    when others then
      v_ip := null;
  end;

  if v_ip is null then
    v_decision := case when v_policy.enforcement_mode = 'enforced' then 'denied' else 'dry_run_would_deny' end;
    insert into app.ip_access_evaluations (tenant_id, subject_label, ip_address, scope, decision)
    values (p_tenant_id, p_subject_label, coalesce(p_raw_ip_address, ''), p_scope, v_decision);
    if v_policy.enforcement_mode = 'enforced' then
      raise exception 'ip_not_allowed: malformed IP address % denied for scope %', p_raw_ip_address, p_scope using errcode = 'insufficient_privilege';
    end if;
    return;
  end if;

  select * into v_matched
  from app.ip_allowlist_entries
  where tenant_id = p_tenant_id and status = 'active'
    and (scope = p_scope or scope = 'all')
    and v_ip <<= cidr
  limit 1;

  if found then
    insert into app.ip_access_evaluations (tenant_id, subject_label, ip_address, scope, decision, matched_entry_id)
    values (p_tenant_id, p_subject_label, host(v_ip), p_scope, 'allowed', v_matched.id);
    return;
  end if;

  v_decision := case when v_policy.enforcement_mode = 'enforced' then 'denied' else 'dry_run_would_deny' end;
  insert into app.ip_access_evaluations (tenant_id, subject_label, ip_address, scope, decision)
  values (p_tenant_id, p_subject_label, host(v_ip), p_scope, v_decision);

  if v_policy.enforcement_mode = 'enforced' then
    raise exception 'ip_not_allowed: % is not in any active allowlist entry for scope % (tenant %)', host(v_ip), p_scope, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function app.assert_ip_allowed is
  'IAE-028: the real enforcement gate. disabled -> true no-op, zero log rows (avoids unbounded growth for tenants who never turn this on). dry_run -> always allows, but logs what it WOULD have denied. enforced -> genuinely denies and logs. A malformed IP address is treated exactly like a non-matching one (denied under enforced, logged under dry_run), never silently allowed and never a raw, unclassified crash.';

-- ===========================================================================
-- 4. Emergency bypass -- mirrors app.mfa_exceptions' own break-glass shape
-- (design decision 4).
-- ===========================================================================

create table app.ip_allowlist_bypass_grants (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  target_auth_user_id uuid not null references auth.users (id),
  reason text not null,
  requested_by_auth_user_id uuid not null references auth.users (id),
  requested_by text,
  approved_by_auth_user_id uuid references auth.users (id),
  approved_by text,
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  expires_at timestamptz not null default (now() + interval '2 hours'),
  constraint ip_allowlist_bypass_grants_status_check check (status in ('pending', 'approved', 'denied', 'expired', 'revoked')),
  constraint ip_allowlist_bypass_grants_no_self_approval check (approved_by_auth_user_id is null or approved_by_auth_user_id <> requested_by_auth_user_id)
);

create index ip_allowlist_bypass_grants_tenant_id_idx on app.ip_allowlist_bypass_grants (tenant_id, requested_at desc);

create function app.request_ip_allowlist_bypass(
  p_tenant_id uuid,
  p_target_auth_user_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ip_allowlist_bypass_grants
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_grant app.ip_allowlist_bypass_grants;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(length(trim(p_reason)), 0) = 0 then
    raise exception 'ip_bypass_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  -- Tier C review fix (security/RLS/tenant lens, Low): identical fix to
  -- app.request_mfa_exception's own -- p_target_auth_user_id was accepted
  -- with no check that it actually belongs to p_tenant_id.
  if not app.has_active_tenant_membership(p_tenant_id, p_target_auth_user_id) then
    raise exception 'ip_bypass_target_not_tenant_member: % is not an active member of tenant %', p_target_auth_user_id, p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.ip_allowlist_bypass_grants (tenant_id, target_auth_user_id, reason, requested_by_auth_user_id, requested_by)
  values (p_tenant_id, p_target_auth_user_id, p_reason, p_actor_auth_user_id, p_actor_label)
  returning * into v_grant;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_ip_allowlist_bypass',
    'app.ip_allowlist_bypass_grants', v_grant.id, 'success', p_reason, null, to_jsonb(v_grant)
  );

  return v_grant;
end;
$$;

create function app.approve_ip_allowlist_bypass(
  p_grant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ip_allowlist_bypass_grants
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_grant app.ip_allowlist_bypass_grants;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_grant from app.ip_allowlist_bypass_grants where id = p_grant_id and status = 'pending' for update;
  if not found then
    raise exception 'ip_bypass_not_pending: % is not a pending bypass request', p_grant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_grant.tenant_id, 'SEC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_grant.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'ip_bypass_self_approval_forbidden: identity % cannot approve their own request', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.ip_allowlist_bypass_grants
  set status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by = p_actor_label, decided_at = now()
  where id = p_grant_id
  returning * into v_grant;

  perform app.capture_audit_event(
    v_grant.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_ip_allowlist_bypass',
    'app.ip_allowlist_bypass_grants', v_grant.id, 'success', null, null, to_jsonb(v_grant)
  );

  return v_grant;
end;
$$;

create function app.has_active_ip_allowlist_bypass(p_tenant_id uuid, p_target_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.ip_allowlist_bypass_grants
    where tenant_id = p_tenant_id and target_auth_user_id = p_target_auth_user_id
      and status = 'approved' and expires_at > now()
  );
$$;

comment on function app.has_active_ip_allowlist_bypass is
  'IAE-028: a future caller of app.assert_ip_allowed can check this FIRST and skip the call entirely for a bypass-holding identity -- kept as a separate, explicit check rather than folded into assert_ip_allowed itself, since a bypass is scoped to one identity while assert_ip_allowed has no identity parameter today (it gates a raw IP/scope pair, reusable by an API-key caller with no auth_user_id at all).';

-- ===========================================================================
-- 5. Read paths.
-- ===========================================================================

create function app.list_ip_allowlist_entries_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.ip_allowlist_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.ip_allowlist_entries where tenant_id = p_tenant_id order by created_at desc;
end;
$$;

create function app.list_ip_access_evaluations_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.ip_access_evaluations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  return query select * from app.ip_access_evaluations where tenant_id = p_tenant_id order by occurred_at desc limit v_limit;
end;
$$;

create function app.list_ip_allowlist_bypass_grants_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.ip_allowlist_bypass_grants
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SEC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SEC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.ip_allowlist_bypass_grants where tenant_id = p_tenant_id order by requested_at desc;
end;
$$;

-- ===========================================================================
-- 6. RLS: default-deny, RPC-only.
-- ===========================================================================

alter table app.ip_allowlist_policies enable row level security;
alter table app.ip_allowlist_entries enable row level security;
alter table app.ip_access_evaluations enable row level security;
alter table app.ip_allowlist_bypass_grants enable row level security;

revoke all on app.ip_allowlist_policies from public, anon, authenticated;
revoke all on app.ip_allowlist_entries from public, anon, authenticated;
revoke all on app.ip_access_evaluations from public, anon, authenticated;
revoke all on app.ip_allowlist_bypass_grants from public, anon, authenticated;
grant all on app.ip_allowlist_policies, app.ip_allowlist_entries, app.ip_access_evaluations, app.ip_allowlist_bypass_grants to service_role;

revoke execute on all functions in schema app from public;

grant execute on function app._parse_cidr(text) to service_role;

grant execute on function
  app.get_or_create_ip_allowlist_policy(uuid, uuid),
  app.set_ip_allowlist_enforcement_mode(uuid, text, uuid, text),
  app.add_ip_allowlist_entry(uuid, text, text, text, uuid, text),
  app.revoke_ip_allowlist_entry(uuid, uuid, text),
  app.request_ip_allowlist_bypass(uuid, uuid, text, uuid, text),
  app.approve_ip_allowlist_bypass(uuid, uuid, text),
  app.list_ip_allowlist_entries_for_tenant(uuid, uuid),
  app.list_ip_access_evaluations_for_tenant(uuid, uuid, integer),
  app.list_ip_allowlist_bypass_grants_for_tenant(uuid, uuid)
to authenticated, service_role;

-- app.assert_ip_allowed and app.has_active_ip_allowlist_bypass both take a
-- bare p_tenant_id (and, for the latter, an arbitrary p_target_auth_user_id)
-- with no actor/authority parameter of their own -- by design, per each
-- function's own comment: assert_ip_allowed must stay reachable from an
-- API-key-authenticated caller with no auth_user_id at all, so it cannot be
-- gated via app.evaluate_permission. That design intent means neither was
-- ever meant to be called directly by an arbitrary end-user session -- both
-- are trusted, system-level primitives, invoked by server-side code that has
-- already resolved the correct tenant_id through its own authorized path
-- (the request's own already-authenticated tenant/API-key context), the same
-- "internal helper, no client grant" class this repository's own rbac-
-- enforcement.sql sweep already establishes for functions with no actor
-- parameter at all. Granting them to authenticated would let any identity of
-- any tenant probe or write into another tenant's own IP allowlist
-- evaluation log. Tier C review fix (ATW-032/ISS-2026-033): service_role-only,
-- caught before this migration was ever committed.
grant execute on function
  app.assert_ip_allowed(uuid, text, text, text),
  app.has_active_ip_allowlist_bypass(uuid, uuid)
to service_role;
