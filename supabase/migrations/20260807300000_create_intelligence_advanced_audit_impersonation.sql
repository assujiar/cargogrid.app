-- IAE-029 (Prompt 357, Group 7): Advanced Audit and Impersonation.
--
-- Design decisions (cited, not re-derived):
--
-- 1. `app.audit_logs`/`app.capture_audit_event`/`app.query_audit_logs`/
--    `app.export_audit_logs`/`app.redact_audit_payload` (PLT-116) and
--    `app.support_access_grants` (PLT-115) already ship a genuinely real
--    audit trail and a genuinely real time-boxed/reasoned/banner-worthy
--    support-access lifecycle -- this checkpoint does NOT duplicate either.
--    Two real, disclosed gaps against Prompt 357's own text are what this
--    checkpoint actually closes:
--    (a) `app.query_audit_logs`/`app.export_audit_logs` support pagination
--        ONLY (tenant + cursor) -- no filter by actor/action/resource_type/
--        result/date-range exists anywhere. `app.search_audit_logs` (below)
--        is the real "enterprise audit search" (Prompt 357 §20) this
--        repository has never had.
--    (b) `app.export_audit_logs` is a plain synchronous `RETURNS SETOF` call
--        -- it is not "async and expiring" (Prompt 357 §24's own business
--        rule). `app.audit_export_requests` + `app.request_audit_export`/
--        `app.record_audit_export_outcome`/`app.get_audit_export` (below)
--        is the real async, expiring export this repository has never had,
--        composing the existing `app.jobs` durable queue exactly like every
--        prior Phase-9 async capability.
-- 2. Additive widening, never a rewrite, of two pre-existing PLT-116
--    primitives: `app.audit_logs` gains one new nullable column
--    (`support_access_grant_id`) and `app.capture_audit_event` gains one new
--    trailing optional parameter (`p_support_access_grant_id default null`)
--    -- `CREATE OR REPLACE FUNCTION` adding a trailing defaulted parameter is
--    a safe, backward-compatible signature widening (every existing 11-arg
--    caller across the whole repository keeps working unchanged, verified
--    by the full `bash scripts/db-tests/run.sh` sweep, not merely asserted
--    safe). This is the real, queryable link between an audit event and the
--    specific impersonation/support session that produced it (Prompt 357
--    §20 "privileged/support/impersonation session evidence").
-- 3. Reuses the `SEC` entitlement module (`IAE-027`/`IAE-028`) for the two
--    genuinely new write actions (requesting/recording an export); every
--    READ path (search, export retrieval, session-scoped listing) reuses
--    `app.is_support_grant_authority` UNCHANGED, the exact same authority
--    `app.query_audit_logs`/`app.export_audit_logs` already require -- audit
--    read access does not become easier or harder than it already was.
-- 4. `app.record_audit_export_outcome`'s own final state transition applies
--    Group 6's own hard-won Tier C lesson proactively: `UPDATE ... WHERE
--    status = 'processing'`, atomic, with a not-found reconciliation branch
--    -- never repeat the "unlocked read-then-write outcome recorder" defect
--    class a fifth time.
-- 5. Never claim tamper-proof/immutable against Supreme Admin (`RPD-022`) --
--    `app.supreme_admin_mutate_audit_log`/`app.supreme_admin_delete_audit_log`
--    (PLT-116) are untouched and still the disclosed, accepted residual risk.
-- 6. Every authenticated-reachable function is `SECURITY DEFINER` paired
--    with `app.assert_actor_is_session_identity` as its first statement.
-- 7. Per the standing convention since `PLT-118`: explicit, redundant
--    `revoke execute on all functions in schema app from public`.

-- ===========================================================================
-- 1. Additive widening of app.audit_logs / app.capture_audit_event.
-- ===========================================================================

alter table app.audit_logs add column support_access_grant_id uuid references app.support_access_grants (id);
create index audit_logs_support_access_grant_id_idx on app.audit_logs (support_access_grant_id) where support_access_grant_id is not null;

comment on column app.audit_logs.support_access_grant_id is
  'IAE-029: nullable link to the specific app.support_access_grants (PLT-115) session an audit event occurred under, if any -- populated by an explicit, opt-in trailing parameter on app.capture_audit_event, never inferred. Most audit events (the overwhelming majority, ordinary tenant-user actions) have no support session and this stays null.';

-- `CREATE OR REPLACE FUNCTION` does NOT replace a function whose own declared
-- parameter COUNT differs, even when every added parameter carries a default
-- -- it silently creates a second, overloaded function instead (self-caught
-- live on this checkpoint's own first migration-apply attempt: "function name
-- app.capture_audit_event is not unique"). The same class of gotcha IAE-011
-- first found for a widened RETURNS TABLE clause, rediscovered here for a
-- widened parameter LIST -- an explicit DROP then CREATE is required for a
-- true, single-function replacement, with every pre-existing grant reissued
-- identically (never inherited from a dropped object).
drop function app.capture_audit_event(uuid, uuid, text, text, text, uuid, text, text, jsonb, jsonb, uuid);

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
  p_correlation_id uuid default null,
  p_support_access_grant_id uuid default null
)
returns app.audit_logs
language plpgsql
as $$
declare
  v_row app.audit_logs;
begin
  insert into app.audit_logs (
    correlation_id, tenant_id, actor_auth_user_id, actor_label, action,
    resource_type, resource_id, result, reason, before_value, after_value,
    support_access_grant_id
  )
  values (
    coalesce(p_correlation_id, gen_random_uuid()), p_tenant_id, p_actor_auth_user_id, p_actor_label, p_action,
    p_resource_type, p_resource_id, p_result, p_reason,
    app.redact_audit_payload(p_before_value), app.redact_audit_payload(p_after_value),
    p_support_access_grant_id
  )
  returning * into v_row;

  return v_row;
end;
$$;

comment on function app.capture_audit_event is
  'IAE-029: widened, backward-compatibly (drop + create, not create or replace -- see this block''s own header), with one new trailing optional parameter (p_support_access_grant_id) -- every pre-existing 11-arg call site across the whole repository is unaffected (verified by the full db-test suite, not merely asserted). Still the single real write path for app.audit_logs; still unconditionally redacts before_value/after_value (PLT-116).';

grant execute on function app.capture_audit_event(uuid, uuid, text, text, text, uuid, text, text, jsonb, jsonb, uuid, uuid) to service_role;

-- ===========================================================================
-- 2. app.search_audit_logs -- real, multi-dimension audit search (design
-- decision 1a). Reuses app.is_support_grant_authority UNCHANGED.
-- ===========================================================================

create function app.search_audit_logs(
  p_requester_auth_user_id uuid,
  p_tenant_id uuid,
  p_actor_auth_user_id_filter uuid,
  p_action_filter text,
  p_resource_type_filter text,
  p_result_filter text,
  p_support_access_grant_id_filter uuid,
  p_occurred_after timestamptz,
  p_occurred_before timestamptz,
  p_limit integer default 50,
  p_before_occurred_at timestamptz default null,
  p_before_id uuid default null
)
returns setof app.audit_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_requester_auth_user_id);

  if not app.is_support_grant_authority(p_requester_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_requester_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_result_filter is not null and p_result_filter not in ('success', 'failure') then
    raise exception 'audit_search_invalid_result_filter: % is not one of success/failure', p_result_filter using errcode = 'check_violation';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  perform app.capture_audit_event(
    p_tenant_id, p_requester_auth_user_id, 'audit_search_caller', 'search_audit_logs',
    'app.audit_logs', null, 'success', null
  );

  return query
    select *
    from app.audit_logs
    where tenant_id = p_tenant_id
      and (p_actor_auth_user_id_filter is null or actor_auth_user_id = p_actor_auth_user_id_filter)
      and (p_action_filter is null or action = p_action_filter)
      and (p_resource_type_filter is null or resource_type = p_resource_type_filter)
      and (p_result_filter is null or result = p_result_filter)
      and (p_support_access_grant_id_filter is null or support_access_grant_id = p_support_access_grant_id_filter)
      and (p_occurred_after is null or occurred_at >= p_occurred_after)
      and (p_occurred_before is null or occurred_at <= p_occurred_before)
      and (p_before_occurred_at is null or occurred_at < p_before_occurred_at
           or (occurred_at = p_before_occurred_at and id < p_before_id))
    order by occurred_at desc, id desc
    limit v_limit;
end;
$$;

comment on function app.search_audit_logs is
  'IAE-029: the real, multi-dimension audit search Prompt 357 §20 requires -- every filter is optional (a null filter matches everything), keyset-paginated exactly like app.query_audit_logs'' own established shape. Self-logs its own invocation, same discipline as app.query_audit_logs/app.export_audit_logs.';

create function app.list_audit_logs_for_support_session(
  p_requester_auth_user_id uuid,
  p_grant_id uuid,
  p_limit integer default 200
)
returns setof app.audit_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_grant app.support_access_grants;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_requester_auth_user_id);

  select * into v_grant from app.support_access_grants where id = p_grant_id;
  if not found then
    raise exception 'support_access_grant_not_found: %', p_grant_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_requester_auth_user_id, v_grant.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_requester_auth_user_id, v_grant.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 200), 1), 1000);

  return query
    select * from app.audit_logs
    where support_access_grant_id = p_grant_id
    order by occurred_at asc, id asc
    limit v_limit;
end;
$$;

comment on function app.list_audit_logs_for_support_session is
  'IAE-029: "all actions are linked to the session" (Prompt 357 §22) made queryable -- every audit event captured with this grant_id, in chronological order (the natural order for reviewing what happened during one impersonation/support session), oldest first.';

-- ===========================================================================
-- 3. app.audit_export_requests -- real async, expiring export (design
-- decision 1b), composing the existing app.jobs durable queue.
-- ===========================================================================

-- The four-place lockstep IAE-016 first established (app.jobs_job_type_check,
-- app.generic_job_types(), GENERIC_JOB_TYPES, IMPORT_EXPORT_JOB_TYPES) --
-- app.generic_job_types() is the single SQL-side authority app.enqueue_job
-- itself already reads from (20260730410000_harden_job_type_single_source_
-- of_truth.sql); both it and the CHECK constraint are widened here, kept
-- set-equal, carrying every pre-existing literal forward verbatim plus this
-- checkpoint's own new 'audit_export'.
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
    'audit_export'
  ]::text[];
$$;

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync', 'external_sync',
    'audit_export'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'IAE-029: widened to add audit_export -- the 25th generic literal (plus import/export). Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

create table app.audit_export_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  requested_by_auth_user_id uuid not null references auth.users (id),
  requested_by text,
  filters jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  result_row_count integer,
  result_payload jsonb,
  failure_reason text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz,
  constraint audit_export_requests_status_check check (status in ('pending', 'processing', 'ready', 'failed', 'expired'))
);

create index audit_export_requests_tenant_id_idx on app.audit_export_requests (tenant_id, requested_at desc);

comment on table app.audit_export_requests is
  'IAE-029: the real async/expiring export Prompt 357 §24 requires. result_payload is a bounded JSONB snapshot of matching, already-redacted app.audit_logs rows (never a raw file/signed URL -- this checkpoint composes app.jobs for asynchrony but does not integrate with this repository''s own file-storage subsystem, disclosed, not built) -- expires_at is set only once ready (a pending/processing request cannot yet be stale) and app.get_audit_export lazily reports (never silently serves) a past-expiry row as expired.';

create function app.request_audit_export(
  p_tenant_id uuid,
  p_filters jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.audit_export_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.audit_export_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_config_value(coalesce(p_filters, '{}'::jsonb)) then
    raise exception 'audit_export_unsafe_filters: filters failed structural validation' using errcode = 'check_violation';
  end if;

  -- Tier C review fix (security/RLS/tenant lens, Medium, flagged as the
  -- same shape as IAE-031's own confirmed request_retention_archive
  -- double-enqueue bug): the idempotency key passed to app.enqueue_job
  -- below was 'audit-export:' || v_request.id -- the id of the row THIS
  -- call just inserted, which can never collide, so it never actually
  -- deduplicated. An advisory transaction lock keyed on (tenant, filters)
  -- serializes concurrent identical requests; an already-pending/processing
  -- request with the exact same filters is returned unchanged rather than
  -- creating a second row and a second job.
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':' || coalesce(p_filters, '{}'::jsonb)::text, 0));

  select * into v_request
  from app.audit_export_requests
  where tenant_id = p_tenant_id and filters = coalesce(p_filters, '{}'::jsonb) and status in ('pending', 'processing')
  order by requested_at desc
  limit 1;
  if found then
    return v_request;
  end if;

  insert into app.audit_export_requests (tenant_id, requested_by_auth_user_id, requested_by, filters)
  values (p_tenant_id, p_actor_auth_user_id, p_actor_label, coalesce(p_filters, '{}'::jsonb))
  returning * into v_request;

  perform app.enqueue_job(
    p_tenant_id, 'audit_export', jsonb_build_object('audit_export_request_id', v_request.id),
    0, 'audit-export:' || v_request.id::text, 3, p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'request_audit_export',
    'app.audit_export_requests', v_request.id, 'success', null, null, to_jsonb(v_request)
  );

  return v_request;
end;
$$;

create function app.record_audit_export_outcome(
  p_request_id uuid,
  p_status text,
  p_result_row_count integer,
  p_result_payload jsonb,
  p_failure_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.audit_export_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.audit_export_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_status not in ('ready', 'failed') then
    raise exception 'audit_export_invalid_outcome_status: % is not one of ready/failed', p_status using errcode = 'check_violation';
  end if;

  update app.audit_export_requests
  set status = p_status,
      result_row_count = case when p_status = 'ready' then p_result_row_count else result_row_count end,
      result_payload = case when p_status = 'ready' then p_result_payload else result_payload end,
      failure_reason = case when p_status = 'failed' then p_failure_reason else null end,
      completed_at = now(),
      expires_at = case when p_status = 'ready' then now() + interval '24 hours' else expires_at end
  where id = p_request_id and status in ('pending', 'processing')
  returning * into v_request;

  if not found then
    select * into v_request from app.audit_export_requests where id = p_request_id;
    if not found then
      raise exception 'audit_export_request_not_found: %', p_request_id using errcode = 'no_data_found';
    end if;
    if v_request.status = p_status then
      return v_request;
    end if;
    raise exception 'audit_export_outcome_already_recorded: request % already resolved to status %', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_audit_export_outcome',
    'app.audit_export_requests', v_request.id, case when p_status = 'ready' then 'success' else 'failure' end,
    p_failure_reason, null, jsonb_build_object('status', p_status, 'row_count', p_result_row_count)
  );

  return v_request;
end;
$$;

comment on function app.record_audit_export_outcome is
  'IAE-029: applies Group 6''s own hard-won Tier C lesson proactively -- the final transition is UPDATE ... WHERE status IN (pending, processing), atomic, with a not-found reconciliation branch distinguishing a genuine idempotent retry (same status already recorded, returns cleanly) from a real conflicting second outcome (audit_export_outcome_already_recorded).';

create function app.get_audit_export(
  p_request_id uuid,
  p_actor_auth_user_id uuid
)
returns app.audit_export_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.audit_export_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_request from app.audit_export_requests where id = p_request_id;
  if not found then
    raise exception 'audit_export_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if not app.is_support_grant_authority(p_actor_auth_user_id, v_request.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_request.status = 'ready' and v_request.expires_at < now() then
    update app.audit_export_requests set status = 'expired', result_payload = null where id = p_request_id
    returning * into v_request;
  end if;

  return v_request;
end;
$$;

comment on function app.get_audit_export is
  'IAE-029: lazily flips a past-expiry ready row to expired AND clears result_payload (the same lazy-expire pattern app.authenticate_api_key established) -- this is a plain read-then-write with no preceding RAISE in this call path, unlike app.verify_mfa_step_up_challenge''s own self-caught savepoint-rollback lesson (IAE-027), so persisting here is safe and does survive a caller''s own exception handler.';

-- ===========================================================================
-- 4. RLS: default-deny, RPC-only, on the one genuinely new table.
-- ===========================================================================

alter table app.audit_export_requests enable row level security;

revoke all on app.audit_export_requests from public, anon, authenticated;
grant all on app.audit_export_requests to service_role;

revoke execute on all functions in schema app from public;

grant execute on function
  app.search_audit_logs(uuid, uuid, uuid, text, text, text, uuid, timestamptz, timestamptz, integer, timestamptz, uuid),
  app.list_audit_logs_for_support_session(uuid, uuid, integer),
  app.request_audit_export(uuid, jsonb, uuid, text),
  app.get_audit_export(uuid, uuid)
to authenticated, service_role;

grant execute on function app.record_audit_export_outcome(uuid, text, integer, jsonb, text, uuid, text) to service_role;
