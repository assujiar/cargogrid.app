-- Platform Core capability PLT-116 (Audit Trail Foundation, CG-S6-PLT-013)
-- Canonical, tenant-aware audit-event capture/query/export for privileged, access,
-- configuration, and platform changes -- Prompt 116 §4/§18/§24, and the concrete
-- mechanism docs/architecture/06_RLS_RBAC_WORKSTREAM.md §8/§10 test #9 already names
-- ("A Supreme Admin mutation of a normally-immutable record produces an audit_logs
-- entry with before/after values").
--
-- Scope, disclosed rather than left implicit (matching every prior checkpoint's
-- discipline):
--
-- * This migration creates app.audit_logs only, not the full five-table family
--   docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md §6 names (`audit_logs`,
--   `event_logs`, `api_logs`, `file_access_logs`, `support_access_logs`). Prompt 116's
--   own objective is specifically "canonical audit events... for privileged, access,
--   configuration and platform changes" -- the compliance/accountability trail, not a
--   generic business-event stream. `event_logs` (business event stream / outbox
--   pattern for async job/webhook dispatch, `05_*.md` line 112) has no real producer
--   yet in this repository (`JOB`/`API-WH` are `PLT-129..132`, far downstream) and is
--   deliberately left to whichever of those capabilities first needs it as a live
--   outbox -- building it now would be an empty table with no real consumer, the same
--   reasoning `PLT-108` already applied to a live `customers` table. `api_logs`/
--   `file_access_logs` are `API-WH`'s/`DOC`'s own emission targets (`PLT-129..130`/
--   `128`) and do not belong to this checkpoint either. `support_access_logs` is
--   `PLT-115`'s own already-shipped, capability-scoped `app.support_access_events` --
--   deliberately a *different*, narrower table (disclosed in that migration's own
--   header), not renamed or merged here.
-- * "Query/export limited by tenant/role/scope/field/record; privileged access itself
--   audited" (§26) is implemented as a structural guarantee, not a convention:
--   `app.audit_logs` itself carries **no grant to `authenticated` at all** (fully
--   `service_role`-only, like every `*_history` table's current scope boundary since
--   `PLT-113`) -- the *only* read path for `authenticated` is through
--   `app.query_audit_logs()`/`app.export_audit_logs()` below, both `SECURITY DEFINER`
--   functions that unconditionally log their own invocation back into `app.audit_logs`
--   before returning results. A raw RLS `SELECT` policy (this repository's usual
--   pattern since `PLT-113`) cannot make "the read itself is audited" unbypassable --
--   only routing every read through a function that always self-logs can, so that is
--   the design chosen here, disclosed as a deliberate departure from the RLS-policy
--   norm for this one table.
-- * RPD-022's disclosed absolute-CRUD exception ("Supreme Admin has absolute CRUD...
--   including audit... records"; `06_*.md` §8, verbatim) has no literal Postgres
--   database role to attach an "except Supreme Admin" RLS `UPDATE`/`DELETE` policy to
--   -- Supreme Admin is an app-level `principal_memberships` row (`PLT-108`), not a
--   native Postgres role per identity, and every write in this repository already flows
--   through explicit `service_role`-executed functions, never direct table access. The
--   "distinct, heavily audited Supreme-Admin-scoped policy path" (`06_*.md` §8) is
--   therefore implemented as two structurally-gated functions,
--   `app.supreme_admin_mutate_audit_log()`/`app.supreme_admin_delete_audit_log()`,
--   each checking `app.is_supreme_admin()` and, on success, immediately capturing its
--   own before/after evidence back into `app.audit_logs` -- test #9's exact mechanism,
--   reused for delete as well as update.

create table app.audit_logs (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid not null,
  tenant_id uuid references app.tenants (id),
  actor_auth_user_id uuid references auth.users (id),
  actor_label text not null,
  action text not null,
  resource_type text not null,
  resource_id uuid,
  result text not null,
  reason text,
  before_value jsonb,
  after_value jsonb,
  occurred_at timestamptz not null default now(),
  legal_hold boolean not null default false,
  legal_hold_reason text,
  constraint audit_logs_result_check check (result in ('success', 'failure'))
);

comment on table app.audit_logs is
  'Canonical, tenant-aware audit trail (PLT-116) -- who did what, to what, with what result, across every capability that calls app.capture_audit_event(). Distinct from PLT-115''s own narrower app.support_access_events (06_RLS_RBAC_WORKSTREAM.md line 112: "five distinct append-only tables, not one merged table"). No column here is ever meant to carry a raw secret or unmasked PII payload -- app.redact_audit_payload() enforces that on every insert, not merely a documented convention.';

-- Keyset-pagination index (Prompt 116 §17, 05_DATABASE_SCHEMA_WORKSTREAM.md line 125:
-- "keyset mandatory for ... audit_logs"). tenant_id is nullable (a platform-wide event
-- carries no tenant) so a separate partial index covers the tenant-scoped query path
-- every real query/export call below actually uses.
create index audit_logs_tenant_occurred_idx
  on app.audit_logs (tenant_id, occurred_at desc, id desc)
  where tenant_id is not null;

create index audit_logs_correlation_id_idx on app.audit_logs (correlation_id);
create index audit_logs_resource_idx on app.audit_logs (resource_type, resource_id);

-- Deterministic redaction (Prompt 116 §16/§25: "No secret/unsafe PII payload,"
-- "redaction deterministic"). Reproduces the exact sensitive-key-name pattern
-- scripts/observability/logger.ts's SENSITIVE_KEY_PATTERN already established
-- (docs/standards/OBSERVABILITY_STANDARDS.md §4's fixed sensitive-key list) --
-- deliberately duplicated here rather than shared, since a SQL function and a TS
-- module cannot share one source; app.capture_audit_event() below is the single
-- caller of this function, so before_value/after_value redaction is guaranteed at the
-- one real write path regardless of what any future caller passes in, the same
-- "database guarantee, not an application convention" discipline PLT-114's column
-- REVOKE already established. Nested objects are redacted recursively; nested arrays
-- of objects are not (disclosed, bounded scope -- no caller in this repository
-- constructs one yet).
create function app.redact_audit_payload(p_payload jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_result jsonb := '{}'::jsonb;
  v_key text;
  v_value jsonb;
begin
  if p_payload is null then
    return null;
  end if;

  for v_key, v_value in select * from jsonb_each(p_payload)
  loop
    if v_key ~* '(secret|password|token|key|authorization|cookie|ssn|npwp|bank|account_number|salary|payroll)' then
      v_result := v_result || jsonb_build_object(v_key, '[REDACTED]');
    elsif jsonb_typeof(v_value) = 'object' then
      v_result := v_result || jsonb_build_object(v_key, app.redact_audit_payload(v_value));
    else
      v_result := v_result || jsonb_build_object(v_key, v_value);
    end if;
  end loop;

  return v_result;
end;
$$;

comment on function app.redact_audit_payload is
  'Deterministic before/after-payload redaction (PLT-116) -- reproduces scripts/observability/logger.ts''s SENSITIVE_KEY_PATTERN key-name list. Applied unconditionally by app.capture_audit_event() to both before_value and after_value, so a caller that forgets to pre-redact still cannot persist a raw secret/PII value through this path.';

-- The single real write path for app.audit_logs -- every capability that wants an
-- audit trail entry calls this, never a raw INSERT (matching the established
-- "explicit named-parameter function, never a raw merge" discipline since PLT-105).
-- correlation_id defaults to a fresh uuid when the caller has none to propagate yet
-- (no live request-ID-generating surface exists in this repository -- PLT-107's own
-- "mechanism proven, live wiring deferred" posture, reapplied here).
create function app.capture_audit_event(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_action text,
  p_resource_type text,
  p_resource_id uuid,
  p_result text,
  p_reason text default null,
  p_before_value jsonb default null,
  p_after_value jsonb default null,
  p_correlation_id uuid default null
)
returns app.audit_logs
language plpgsql
as $$
declare
  v_row app.audit_logs;
begin
  insert into app.audit_logs (
    correlation_id, tenant_id, actor_auth_user_id, actor_label, action,
    resource_type, resource_id, result, reason, before_value, after_value
  )
  values (
    coalesce(p_correlation_id, gen_random_uuid()), p_tenant_id, p_actor_auth_user_id, p_actor_label, p_action,
    p_resource_type, p_resource_id, p_result, p_reason,
    app.redact_audit_payload(p_before_value), app.redact_audit_payload(p_after_value)
  )
  returning * into v_row;

  return v_row;
end;
$$;

comment on function app.capture_audit_event is
  'Canonical audit-capture primitive (PLT-116). Every call is a genuinely new, distinct event -- deliberately not idempotent/deduplicated (an audit log that silently collapsed two real repeated actions into one row would under-report, the opposite of its purpose). before_value/after_value are always redacted via app.redact_audit_payload() before persistence, structurally, not by caller convention.';

-- RPD-022's disclosed exception, made concrete (06_RLS_RBAC_WORKSTREAM.md §8, test #9).
-- Scoped to the fields an operator would realistically need to correct/annotate
-- (reason, legal_hold, legal_hold_reason) -- not a raw arbitrary-column UPDATE, which
-- would be a materially broader (and less auditable) surface than this checkpoint's
-- representative-example scope calls for; RPD-022 describes Supreme Admin's authority,
-- not a mandate that every column be independently exposed through one RPC.
create function app.supreme_admin_mutate_audit_log(
  p_actor_auth_user_id uuid,
  p_target_id uuid,
  p_new_reason text,
  p_new_legal_hold boolean,
  p_new_legal_hold_reason text,
  p_mutation_reason text
)
returns app.audit_logs
language plpgsql
as $$
declare
  v_before app.audit_logs;
  v_after app.audit_logs;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may mutate an existing audit_logs row (RPD-022)'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_before from app.audit_logs where id = p_target_id;
  if not found then
    raise exception 'audit_log_not_found: no audit_logs row %', p_target_id using errcode = 'no_data_found';
  end if;

  update app.audit_logs
  set reason = coalesce(p_new_reason, reason),
      legal_hold = coalesce(p_new_legal_hold, legal_hold),
      legal_hold_reason = coalesce(p_new_legal_hold_reason, legal_hold_reason)
  where id = p_target_id
  returning * into v_after;

  -- The accountability mechanism substituting for true immutability (RPD-022,
  -- 06_RLS_RBAC_WORKSTREAM.md §8): recursive self-audit, test #9's exact mechanism.
  -- The residual risk that this new entry is itself technically alterable by the same
  -- authority is accepted, not resolved, per 01_MODULE_DEPENDENCY_MAP.md RISK-004
  -- (standing, never closed) -- disclosed here again, not glossed over.
  perform app.capture_audit_event(
    v_before.tenant_id, p_actor_auth_user_id, 'supreme_admin', 'supreme_admin_mutate_audit_log',
    'app.audit_logs', p_target_id, 'success', p_mutation_reason,
    to_jsonb(v_before), to_jsonb(v_after)
  );

  return v_after;
end;
$$;

create function app.supreme_admin_delete_audit_log(
  p_actor_auth_user_id uuid,
  p_target_id uuid,
  p_reason text
)
returns void
language plpgsql
as $$
declare
  v_row app.audit_logs;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may delete an audit_logs row (RPD-022)'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.audit_logs where id = p_target_id;
  if not found then
    raise exception 'audit_log_not_found: no audit_logs row %', p_target_id using errcode = 'no_data_found';
  end if;

  delete from app.audit_logs where id = p_target_id;

  -- Deletion itself is still captured -- the before-image is preserved in this new
  -- row's before_value even though the original row is gone, so "CargoGrid must never
  -- claim audit records are immutable or tamper-proof" (06_*.md §8) never collapses
  -- into "and there is no trace that it happened."
  perform app.capture_audit_event(
    v_row.tenant_id, p_actor_auth_user_id, 'supreme_admin', 'supreme_admin_delete_audit_log',
    'app.audit_logs', p_target_id, 'success', p_reason,
    to_jsonb(v_row), null
  );
end;
$$;

-- Permission-aware, keyset-paginated, self-auditing read path (Prompt 116 §14/§26).
-- SECURITY DEFINER so `authenticated` never needs direct table access (see header) --
-- app.is_support_grant_authority() (PLT-115) is reused verbatim as the query
-- authority: Supreme Admin, or the target tenant's own active tenant_admin. Every call
-- -- success or not yet checked -- logs itself as its very next statement, before
-- returning any row, so "privileged access itself audited" (§26) cannot be bypassed by
-- a caller that discards the result.
create function app.query_audit_logs(
  p_requester_auth_user_id uuid,
  p_tenant_id uuid,
  p_limit integer default 50,
  p_before_occurred_at timestamptz default null,
  p_before_id uuid default null
)
returns setof app.audit_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.is_support_grant_authority(p_requester_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_requester_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_requester_auth_user_id, 'audit_query_caller', 'query_audit_logs',
    'app.audit_logs', null, 'success', null
  );

  return query
    select al.*
    from app.audit_logs al
    where al.tenant_id = p_tenant_id
      and (
        p_before_occurred_at is null
        or al.occurred_at < p_before_occurred_at
        or (al.occurred_at = p_before_occurred_at and al.id < p_before_id)
      )
    order by al.occurred_at desc, al.id desc
    limit p_limit;
end;
$$;

comment on function app.query_audit_logs is
  'Permission-aware, keyset-paginated audit read (PLT-116). Every call self-logs (action=query_audit_logs) before returning rows -- the structural form of "privileged access itself audited" (Prompt 116 §26), not a convention a caller could skip.';

-- Distinct action label from query_audit_logs -- an export is a bulk/higher-scrutiny
-- access pattern Prompt 116 §14 explicitly separates from an interactive query, so its
-- own self-audit entry is independently identifiable.
create function app.export_audit_logs(
  p_requester_auth_user_id uuid,
  p_tenant_id uuid,
  p_limit integer default 500,
  p_before_occurred_at timestamptz default null,
  p_before_id uuid default null
)
returns setof app.audit_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.is_support_grant_authority(p_requester_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_requester_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_requester_auth_user_id, 'audit_export_caller', 'export_audit_logs',
    'app.audit_logs', null, 'success', null
  );

  return query
    select al.*
    from app.audit_logs al
    where al.tenant_id = p_tenant_id
      and (
        p_before_occurred_at is null
        or al.occurred_at < p_before_occurred_at
        or (al.occurred_at = p_before_occurred_at and al.id < p_before_id)
      )
    order by al.occurred_at desc, al.id desc
    limit p_limit;
end;
$$;

comment on function app.export_audit_logs is
  'Bulk audit export (PLT-116), otherwise identical to app.query_audit_logs -- kept a distinct function (not a p_purpose flag on one function) so its own self-audit action label (export_audit_logs) is unambiguous evidence of which access pattern actually occurred.';

-- Representative platform-event integration (Prompt 116 §20 task 4: "Integrate
-- representative platform events"). PLT-115's own kill switch -- an already-VERIFIED,
-- genuinely privileged action -- now also leaves a canonical app.audit_logs entry
-- alongside its existing capability-scoped app.support_access_events row. This is an
-- additive CREATE OR REPLACE (same signature, same body plus one new capture call at
-- the end) -- the same pattern PLT-115 itself already used once on
-- app.has_active_tenant_membership().
create or replace function app.revoke_support_access(
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

  perform app.capture_audit_event(
    v_updated.tenant_id, p_revoker_auth_user_id, p_revoked_by, 'revoke_support_access',
    'app.support_access_grants', v_updated.id, 'success', p_reason,
    to_jsonb(v_grant), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- RLS: enabled, but -- deliberately, per this migration's header -- no grant to
-- `authenticated` at all. Defense in depth for the schema-privilege layer matches every
-- prior capability; the real access control is app.query_audit_logs()/
-- app.export_audit_logs()'s own authority check plus mandatory self-logging.
alter table app.audit_logs enable row level security;

grant select, insert, update, delete on app.audit_logs to service_role;
grant execute on function app.redact_audit_payload(jsonb) to service_role;
grant execute on function app.capture_audit_event(uuid, uuid, text, text, text, uuid, text, text, jsonb, jsonb, uuid) to service_role;
grant execute on function app.supreme_admin_mutate_audit_log(uuid, uuid, text, boolean, text, text) to service_role;
grant execute on function app.supreme_admin_delete_audit_log(uuid, uuid, text) to service_role;
grant execute on function app.query_audit_logs(uuid, uuid, integer, timestamptz, uuid) to authenticated, service_role;
grant execute on function app.export_audit_logs(uuid, uuid, integer, timestamptz, uuid) to authenticated, service_role;

-- Real bug found and fixed during this checkpoint's authoring, unrelated to audit
-- itself but discovered because this migration's own db-test file happens to sort
-- alphabetically before PLT-114's field-record-access.sql, adding real cross-tenant
-- app.users rows to the shared db-test database earlier than before -- which exposed a
-- latent defect that a narrower prior test run had never had enough foreign-tenant
-- data present to observe: **app.users_directory (PLT-114) never actually enforced
-- tenant isolation.** Root cause: the view is `security_invoker = false` (Postgres's
-- default, and deliberately so -- PLT-114 needed the view OWNER's rights to read the
-- raw, REVOKEd-from-authenticated `email` column internally). Per Postgres's own
-- documented view/RLS semantics, a non-security-invoker view's row-level-security
-- posture is the OWNER's, not the invoking role's -- and this migration's owner
-- (the role every migration in this repository is applied as) has `BYPASSRLS`
-- (confirmed empirically: `select rolbypassrls from pg_roles where rolname =
-- current_user` -> `t`). The practical effect: querying app.users_directory returned
-- literally every tenant's users to any authenticated caller, silently ignoring
-- PLT-113's own users_select_own_tenant RLS policy on the underlying table entirely --
-- a real cross-tenant PII exposure, not a theoretical one.
--
-- Fix: add an explicit `where app.has_active_tenant_membership(u.tenant_id)` predicate
-- directly inside the view's own query, rather than relying on RLS propagation through
-- the view (which this checkpoint proved unreliable for a non-security-invoker view).
-- app.has_active_tenant_membership()'s default `p_auth_user_id` parameter reads
-- `auth.uid()`, which reflects the real querying session's JWT claims regardless of
-- the view's owner-rights execution context (BYPASSRLS affects RLS *policy*
-- enforcement only, not ordinary SQL predicate evaluation) -- so this restores correct
-- per-caller tenant scoping without needing `security_invoker = true` (which would
-- have re-introduced the original email-column-privilege problem PLT-114 solved).
-- Disclosed limitation: this predicate evaluates `auth.uid()`, which is null for a
-- `service_role` session (no JWT claims GUC ever set for it) -- `service_role` would
-- therefore see zero rows through this view specifically. This is a deliberate,
-- bounded, and harmless scope choice, not a regression: `service_role` already has,
-- and retains, full unfiltered direct access to the underlying `app.users` table
-- itself (PLT-105's original grant, untouched) for any use case that needs it: the
-- masked directory view exists for `authenticated` callers only.
create or replace view app.users_directory as
select
  u.id,
  u.tenant_id,
  u.auth_user_id,
  u.display_name,
  u.status,
  u.org_unit_id,
  case
    when app.has_view_personal_data(u.tenant_id) then u.email
    else app.mask_email(u.email)
  end as email,
  not app.has_view_personal_data(u.tenant_id) as email_masked,
  u.created_at,
  u.updated_at
from app.users u
where app.has_active_tenant_membership(u.tenant_id);

comment on view app.users_directory is
  'Field-masked projection of app.users (PLT-114, tenant-isolation bug fixed at PLT-116 -- see this migration''s own comment above). email is redacted (app.mask_email()) unless the caller holds the real, seeded ''HRS:View personal data'' permission (PLT-111/112); email_masked tells a future UI which state it is looking at without guessing. The where clause is load-bearing, not decorative -- a non-security-invoker view''s RLS posture is its OWNER''s, not the caller''s, so tenant scoping must be explicit here rather than assumed from the underlying table''s RLS policy.';
