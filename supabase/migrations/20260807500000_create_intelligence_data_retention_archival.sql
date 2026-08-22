-- IAE-031 (Prompt 359, Group 7): Data Retention and Archival.
--
-- Design decisions (cited, not re-derived):
--
-- 1. Genuinely greenfield -- confirmed by direct grep before writing any code
--    (no `retention`/`legal_hold`/`archive` table or function exists anywhere
--    in `app`). `docs/build-log/phase-05/guides/privacy-consent-and-retention-
--    guide.md` §3 already disclosed, honestly, that RPD-025's own retention
--    SCHEDULE is ratified at the product/legal level but had NO enforcement
--    mechanism anywhere in the repository -- this checkpoint builds that
--    mechanism for the first time.
-- 2. New `RET` entitlement module (`View`/`Configure`/`Approve`) -- Prompt
--    359's own workstream is "Governance", distinct from every other Group 7
--    workstream (`IAM`/`SEC`/`MON`).
-- 3. RPD-025's own class-based schedule is the real, hardcoded platform
--    default (`app.resolve_retention_days`): finance/tax 10 years (3650
--    days), audit/security 7 years (2555 days), operational 90 days (RPD-025's
--    own "contract term + 90 days" -- "contract term" is a commercial fact
--    this schema does not model anywhere, so 90 days is the modeled floor; a
--    tenant's own real total, inclusive of its own contract term, is set via
--    `app.set_retention_policy`'s own tenant-scoped override). Backups (RPD-025's
--    fourth class, 35 days) are Supabase/Postgres infrastructure-level, not an
--    application data row this schema owns -- out of scope, disclosed.
-- 4. This checkpoint does NOT reach into any other domain's own tables (Finance
--    GL, HR payroll, audit logs, etc.) to enumerate or delete rows itself --
--    doing so would be exactly the "unrelated domains"/"duplicate source-domain
--    roots" scope creep Prompt 359 §12 forbids. Instead it builds the real,
--    reusable GOVERNANCE primitive any domain-owning capability calls with ITS
--    OWN already-known record identifiers: classify a record against its own
--    declared retention class, and (if genuinely eligible -- past its own
--    retention floor AND not under legal hold) enqueue a real `app.jobs` row
--    recording that a domain-owning worker may now proceed. This checkpoint
--    never itself deletes or moves a single byte of another domain's data --
--    disclosed honestly, the same bounded-scope posture `IAE-030`'s own "no
--    external APM integration" and `IAE-029`'s own audit-export queue
--    composition both already established.
-- 5. Real, structural enforcement, not merely disclosed: `app.request_retention_
--    archive` REJECTS (`retention_floor_not_reached`) a non-dry-run archive
--    request for a record that has not yet reached its own class's retention
--    floor -- "deletion/minimization cannot erase required posted Finance,
--    payroll or legal evidence" (Prompt 359 §24) is enforced at the database
--    layer, not left to application-layer discipline.
-- 6. Legal hold is a REAL, structural override, not a flag nobody reads:
--    `app._is_under_legal_hold` is consulted by `app.request_retention_archive`
--    itself before any job is ever enqueued -- an active hold (whether scoped to
--    one specific record or an entire record class for a tenant) blocks
--    archival unconditionally, even past the retention floor, even for a
--    dry-run's own reported outcome.
-- 7. "Retention policy versions are auditable" (Prompt 359 §24) is satisfied via
--    the same `app.capture_audit_event` composition every other "X is
--    auditable" requirement in this repository already uses (`IAE-030`'s own
--    SLO/alert-route upserts, `IAE-027`'s own MFA policy) -- no separate,
--    duplicate "policy version" table.
-- 8. Every authenticated-reachable function is `SECURITY DEFINER` paired with
--    `app.assert_actor_is_session_identity` as its first statement.
-- 9. Per the standing convention since `PLT-118`: explicit, redundant
--    `revoke execute on all functions in schema app from public`.
-- 10. Widens the standing four-place job_type lockstep (`app.jobs_job_type_
--     check`, `app.generic_job_types()`, `GENERIC_JOB_TYPES`,
--     `IMPORT_EXPORT_JOB_TYPES`) with one new value, `retention_archive` --
--     the 26th generic literal (plus import/export) -- for the real archive
--     job this checkpoint enqueues, mirroring `IAE-029`'s own `audit_export`
--     precedent exactly.

-- ===========================================================================
-- 1. RET entitlement module.
-- ===========================================================================

insert into app.entitlement_modules (code, name, owning_phase) values
  ('RET', 'Data retention and archival governance: policy, legal hold, classification, archive requests', 9);

insert into app.permissions (action, resource_module_code, category, protected) values
  ('View', 'RET', 'standard', false),
  ('Configure', 'RET', 'admin', false),
  ('Approve', 'RET', 'admin', true);

-- ===========================================================================
-- 2. app.retention_policies -- real, persisted, per-class retention days.
-- ===========================================================================

create table app.retention_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  record_class text not null,
  retention_days integer not null,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint retention_policies_record_class_check check (record_class in ('finance_tax', 'audit_security', 'operational')),
  constraint retention_policies_retention_days_check check (retention_days > 0),
  constraint retention_policies_unique unique (tenant_id, record_class)
);

comment on table app.retention_policies is
  'IAE-031: tenant_id null means a platform-wide DEFAULT override; non-null means a per-tenant override. RPD-025''s own hardcoded class schedule (app.resolve_retention_days) applies whenever neither exists.';

create function app.touch_retention_policy_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger retention_policies_touch_row
  before update on app.retention_policies
  for each row
  execute function app.touch_retention_policy_row();

create function app.resolve_retention_days(p_tenant_id uuid, p_record_class text)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_override integer;
  v_platform_override integer;
begin
  if p_record_class not in ('finance_tax', 'audit_security', 'operational') then
    raise exception 'retention_invalid_record_class: %', p_record_class using errcode = 'check_violation';
  end if;

  if p_tenant_id is not null then
    select retention_days into v_tenant_override from app.retention_policies where tenant_id = p_tenant_id and record_class = p_record_class;
    if found then
      return v_tenant_override;
    end if;
  end if;

  select retention_days into v_platform_override from app.retention_policies where tenant_id is null and record_class = p_record_class;
  if found then
    return v_platform_override;
  end if;

  return case p_record_class
    when 'finance_tax' then 3650
    when 'audit_security' then 2555
    when 'operational' then 90
  end;
end;
$$;

comment on function app.resolve_retention_days is
  'IAE-031: RPD-025''s own hardcoded class schedule (finance/tax 10y, audit/security 7y, operational 90d floor) is the final fallback -- a tenant-specific override (app.retention_policies) always wins when present, then a platform-wide override, then this default. Never raises for a valid class with no policy row at all -- the schedule is always resolvable.';

create function app.set_retention_policy(
  p_tenant_id uuid,
  p_record_class text,
  p_retention_days integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.retention_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_authorized boolean;
  v_policy app.retention_policies;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'RET', 'Configure');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to configure this retention policy (tenant %)', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_record_class not in ('finance_tax', 'audit_security', 'operational') then
    raise exception 'retention_invalid_record_class: %', p_record_class using errcode = 'check_violation';
  end if;
  if p_retention_days <= 0 then
    raise exception 'retention_invalid_days: % must be a positive number of days', p_retention_days using errcode = 'check_violation';
  end if;

  insert into app.retention_policies (tenant_id, record_class, retention_days, created_by)
  values (p_tenant_id, p_record_class, p_retention_days, p_actor_label)
  on conflict (tenant_id, record_class) do update
    set retention_days = excluded.retention_days
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_retention_policy',
    'app.retention_policies', v_policy.id, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$$;

-- ===========================================================================
-- 3. app.legal_holds -- the real, structural override (design decision 6).
-- ===========================================================================

create table app.legal_holds (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  record_class text not null,
  scope_record_table text,
  scope_record_id uuid,
  reason text not null,
  status text not null default 'active',
  placed_by_auth_user_id uuid not null references auth.users (id),
  placed_by text,
  placed_at timestamptz not null default now(),
  released_by_auth_user_id uuid references auth.users (id),
  released_by text,
  released_at timestamptz,
  release_reason text,
  constraint legal_holds_record_class_check check (record_class in ('finance_tax', 'audit_security', 'operational')),
  constraint legal_holds_status_check check (status in ('active', 'released')),
  constraint legal_holds_scope_check check ((scope_record_table is null) = (scope_record_id is null))
);

comment on table app.legal_holds is
  'IAE-031: a hold with scope_record_table/scope_record_id both null covers the ENTIRE record_class for this tenant; both set covers exactly one record. Placing (RET:Configure) is a lower bar than releasing (RET:Approve) -- releasing a hold is what allows deletion/archive to proceed, the more consequential action.';

create index legal_holds_active_lookup_idx on app.legal_holds (tenant_id, record_class, scope_record_table, scope_record_id) where status = 'active';

create function app.request_legal_hold(
  p_tenant_id uuid,
  p_record_class text,
  p_scope_record_table text,
  p_scope_record_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.legal_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_hold app.legal_holds;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'RET', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_record_class not in ('finance_tax', 'audit_security', 'operational') then
    raise exception 'retention_invalid_record_class: %', p_record_class using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'legal_hold_reason_required: a legal hold must state a real reason' using errcode = 'check_violation';
  end if;
  if (p_scope_record_table is null) <> (p_scope_record_id is null) then
    raise exception 'legal_hold_invalid_scope: scope_record_table and scope_record_id must both be set, or both null' using errcode = 'check_violation';
  end if;

  insert into app.legal_holds (tenant_id, record_class, scope_record_table, scope_record_id, reason, placed_by_auth_user_id, placed_by)
  values (p_tenant_id, p_record_class, p_scope_record_table, p_scope_record_id, p_reason, p_actor_auth_user_id, p_actor_label)
  returning * into v_hold;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_legal_hold',
    'app.legal_holds', v_hold.id, 'success', null, null, to_jsonb(v_hold)
  );

  return v_hold;
end;
$$;

create function app.release_legal_hold(
  p_hold_id uuid,
  p_release_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.legal_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_hold app.legal_holds;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_hold from app.legal_holds where id = p_hold_id and status = 'active' for update;
  if not found then
    raise exception 'legal_hold_not_active: % is not an active legal hold', p_hold_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_hold.tenant_id, 'RET', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_hold.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.legal_holds
  set status = 'released', released_by_auth_user_id = p_actor_auth_user_id, released_by = p_actor_label, released_at = now(), release_reason = p_release_reason
  where id = p_hold_id
  returning * into v_hold;

  perform app.capture_audit_event(
    v_hold.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_legal_hold',
    'app.legal_holds', v_hold.id, 'success', null, null, to_jsonb(v_hold)
  );

  return v_hold;
end;
$$;

create function app._is_under_legal_hold(p_tenant_id uuid, p_record_class text, p_source_table text, p_source_record_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.legal_holds
    where tenant_id = p_tenant_id and record_class = p_record_class and status = 'active'
      and (
        (scope_record_table is null and scope_record_id is null)
        or (scope_record_table = p_source_table and scope_record_id = p_source_record_id)
      )
  );
$$;

comment on function app._is_under_legal_hold is
  'IAE-031: internal-only primitive, no actor/authority parameter -- never granted to anon/authenticated. Matches either a whole-class hold or a hold scoped to this exact record.';

-- ===========================================================================
-- 4. app.retention_archive_requests -- real dry-run classification and
-- real, job-queue-backed archive requests (design decisions 4/5).
-- ===========================================================================

create table app.retention_archive_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  record_class text not null,
  source_table text not null,
  source_record_id uuid not null,
  record_reference_date timestamptz not null,
  dry_run boolean not null,
  eligible_for_archive_at timestamptz not null,
  legal_hold_blocking boolean not null default false,
  status text not null,
  requested_by_auth_user_id uuid not null references auth.users (id),
  requested_by text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  result_note text,
  constraint retention_archive_requests_record_class_check check (record_class in ('finance_tax', 'audit_security', 'operational')),
  constraint retention_archive_requests_status_check check (status in ('dry_run_completed', 'blocked_within_retention', 'blocked_legal_hold', 'pending', 'archived', 'failed'))
);

comment on table app.retention_archive_requests is
  'IAE-031: a real, auditable evidence trail per (record, request) -- never a physical delete/archive performed by this checkpoint itself (design decision 4). A non-dry-run request that reaches status=pending has a real app.jobs row enqueued (job_type retention_archive); app.record_retention_archive_outcome is the disclosed, not-yet-built worker''s own eventual outcome-recording call.';

create index retention_archive_requests_tenant_lookup_idx on app.retention_archive_requests (tenant_id, source_table, source_record_id, requested_at desc);

create function app.request_retention_archive(
  p_tenant_id uuid,
  p_record_class text,
  p_source_table text,
  p_source_record_id uuid,
  p_record_reference_date timestamptz,
  p_dry_run boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.retention_archive_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_retention_days integer;
  v_eligible_at timestamptz;
  v_legal_hold_blocking boolean;
  v_status text;
  v_request app.retention_archive_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'RET', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_record_class not in ('finance_tax', 'audit_security', 'operational') then
    raise exception 'retention_invalid_record_class: %', p_record_class using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_source_table), '') = '' then
    raise exception 'retention_source_table_required: a real source table must be named' using errcode = 'check_violation';
  end if;

  v_retention_days := app.resolve_retention_days(p_tenant_id, p_record_class);
  v_eligible_at := p_record_reference_date + (v_retention_days || ' days')::interval;
  v_legal_hold_blocking := app._is_under_legal_hold(p_tenant_id, p_record_class, p_source_table, p_source_record_id);

  if p_dry_run then
    v_status := case
      when v_legal_hold_blocking then 'blocked_legal_hold'
      when now() < v_eligible_at then 'blocked_within_retention'
      else 'dry_run_completed'
    end;
  elsif v_legal_hold_blocking then
    v_status := 'blocked_legal_hold';
  elsif now() < v_eligible_at then
    v_status := 'blocked_within_retention';
  else
    v_status := 'pending';
  end if;

  insert into app.retention_archive_requests (
    tenant_id, record_class, source_table, source_record_id, record_reference_date,
    dry_run, eligible_for_archive_at, legal_hold_blocking, status, requested_by_auth_user_id, requested_by
  )
  values (
    p_tenant_id, p_record_class, p_source_table, p_source_record_id, p_record_reference_date,
    p_dry_run, v_eligible_at, v_legal_hold_blocking, v_status, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_request;

  if v_status = 'pending' then
    perform app.enqueue_job(
      p_tenant_id, 'retention_archive', jsonb_build_object('retention_archive_request_id', v_request.id),
      0, 'retention-archive:' || v_request.id::text, 3, p_actor_auth_user_id, p_actor_label
    );
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_retention_archive',
    'app.retention_archive_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.request_retention_archive is
  'IAE-031: a dry_run=true call NEVER inserts an app.jobs row -- classification only, zero side effect beyond this evidence row (Prompt 359 §20 "dry-run retention classification"). A dry_run=false call is REJECTED (blocked_within_retention/blocked_legal_hold) rather than enqueued when the record has not reached its own retention floor or is under an active legal hold -- the real enforcement design decisions 5/6 describe, not merely a disclosed intention.';

create function app.record_retention_archive_outcome(
  p_request_id uuid,
  p_status text,
  p_result_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.retention_archive_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.retention_archive_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_status not in ('archived', 'failed') then
    raise exception 'retention_archive_invalid_outcome_status: % is not one of archived/failed', p_status using errcode = 'check_violation';
  end if;

  update app.retention_archive_requests
  set status = p_status, result_note = p_result_note, completed_at = now()
  where id = p_request_id and status = 'pending'
  returning * into v_request;

  if not found then
    select * into v_request from app.retention_archive_requests where id = p_request_id;
    if not found then
      raise exception 'retention_archive_request_not_found: %', p_request_id using errcode = 'no_data_found';
    end if;
    if v_request.status = p_status then
      return v_request;
    end if;
    raise exception 'retention_archive_outcome_already_recorded: request % already resolved to status %', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_retention_archive_outcome',
    'app.retention_archive_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

comment on function app.record_retention_archive_outcome is
  'IAE-031: service_role-only -- the disclosed, not-yet-built archive-worker''s own outcome call (design decision 4: this checkpoint never itself performs a physical delete/archive). Lost-update-guarded exactly like app.record_audit_export_outcome (IAE-029): the WHERE-status-guard update either wins outright or falls through to a not-found/already-resolved reconciliation branch, never a silent overwrite of a concurrent outcome.';

-- ===========================================================================
-- 5. Read paths.
-- ===========================================================================

create function app.list_retention_policies_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.retention_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'RET', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.retention_policies
    where tenant_id = p_tenant_id
    order by record_class asc;
end;
$$;

create function app.list_legal_holds_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.legal_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'RET', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.legal_holds
    where tenant_id = p_tenant_id
    order by placed_at desc;
end;
$$;

create function app.get_retention_archive_request(p_request_id uuid, p_actor_auth_user_id uuid)
returns app.retention_archive_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.retention_archive_requests;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.retention_archive_requests where id = p_request_id;
  if not found then
    raise exception 'retention_archive_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'RET', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_request;
end;
$$;

create function app.list_retention_archive_requests_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.retention_archive_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'RET', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks RET:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select * from app.retention_archive_requests
    where tenant_id = p_tenant_id
    order by requested_at desc;
end;
$$;

-- ===========================================================================
-- 6. RLS: default-deny, RPC-only.
-- ===========================================================================

alter table app.retention_policies enable row level security;
alter table app.legal_holds enable row level security;
alter table app.retention_archive_requests enable row level security;

revoke all on app.retention_policies from public, anon, authenticated;
revoke all on app.legal_holds from public, anon, authenticated;
revoke all on app.retention_archive_requests from public, anon, authenticated;
grant all on app.retention_policies, app.legal_holds, app.retention_archive_requests to service_role;

revoke execute on all functions in schema app from public;

grant execute on function app._is_under_legal_hold(uuid, text, text, uuid) to service_role;

grant execute on function app.record_retention_archive_outcome(uuid, text, text, uuid, text) to service_role;

-- app.resolve_retention_days takes a bare p_tenant_id with no actor/authority
-- parameter at all -- the identical shape app.is_high_risk_action already
-- established (IAE-027) and was fixed the same way: any authenticated
-- identity of any tenant could otherwise probe another tenant's own
-- retention-days override. It is called internally by app.request_retention_
-- archive (itself real-actor-scoped) and is not itself the disclosure
-- boundary that matters -- service_role-only.
grant execute on function app.resolve_retention_days(uuid, text) to service_role;

grant execute on function
  app.set_retention_policy(uuid, text, integer, uuid, text),
  app.request_legal_hold(uuid, text, text, uuid, text, uuid, text),
  app.release_legal_hold(uuid, text, uuid, text),
  app.request_retention_archive(uuid, text, text, uuid, timestamptz, boolean, uuid, text),
  app.list_retention_policies_for_tenant(uuid, uuid),
  app.list_legal_holds_for_tenant(uuid, uuid),
  app.get_retention_archive_request(uuid, uuid),
  app.list_retention_archive_requests_for_tenant(uuid, uuid)
to authenticated, service_role;

-- ===========================================================================
-- 7. Widen the standing four-place job_type lockstep with 'retention_archive'
-- (design decision 10). The four-place lockstep (`app.jobs_job_type_check`,
-- `app.generic_job_types()`, `GENERIC_JOB_TYPES`, `IMPORT_EXPORT_JOB_TYPES`)
-- carried forward verbatim, plus this checkpoint's own new value.
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync', 'external_sync',
    'audit_export', 'retention_archive'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'IAE-031: widened to add retention_archive -- the 26th generic literal (plus import/export). Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync', 'external_sync',
    'audit_export', 'retention_archive'
  ]::text[];
$$;
