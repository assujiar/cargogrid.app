-- Platform Core capability PLT-132 (Background Job Framework, CG-S6-PLT-029)
-- Widens PLT-131's `app.jobs` (Tech Arch §32.11) into the generic PostgreSQL durable
-- job queue RPD-012 names, and builds `app.event_logs` (the outbox-pattern table
-- deliberately deferred here since PLT-116 -- see this migration's own header below),
-- plus the enqueue/claim/heartbeat/complete lifecycle and exponential-backoff-with-
-- jitter retry scheduling PLT-131's migration explicitly assigned to this task.
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **`job_type` is widened here, exactly as PLT-131's own migration header disclosed
--   it would be** ("Prompt 132 will need its own migration to widen this constraint
--   when it adds further job types"). The added codes are the real, sourced job-type
--   use-case list `02_CANONICAL_DATA_FLOW_MAP.md` §5.3 names verbatim ("bulk import,
--   export, report generation, notification batch, webhook retry, document/PDF
--   generation, dashboard refresh, loyalty expiration, recurring billing, integration
--   sync"): `report_generation`, `notification_batch`, `webhook_retry`,
--   `document_generation`, `dashboard_refresh`, `loyalty_expiration`,
--   `recurring_billing`, `integration_sync` (`import`/`export` already existed).
--   **No business logic for any of these eight new types is implemented here** --
--   Prompt 132 §12 forbids "domain batch implementation." This migration builds only
--   the generic queue mechanics (enqueue/claim/heartbeat/complete/fail/DLQ/requeue) any
--   future domain-specific worker for one of these types would sit on top of, proven in
--   this checkpoint's own db-test using synthetic non-import/export job rows.
-- * **`app.jobs.locked_by`/`locked_until` are wired to a real atomic claim function for
--   the first time** (`app.claim_next_job()`), exactly as PLT-131's migration header
--   disclosed was deferred to this task ("distributed worker-locking semantics belong
--   to Prompt 132's own live worker"). The claim query uses `SELECT ... FOR UPDATE SKIP
--   LOCKED`, PostgreSQL's own standard, documented-since-9.5 mechanism for exactly this
--   "many workers polling one queue, no two may claim the same row" guarantee (RPD-012:
--   "PostgreSQL durable queue is the initial background-job mechanism") -- genuinely
--   provable without a live multi-process worker fleet, since `SKIP LOCKED`'s row-level
--   locking semantics are a documented PostgreSQL guarantee, not something this
--   migration invents. A stale lease (an `in_progress` row whose `locked_until` has
--   passed, meaning the worker that held it crashed or hung) is structurally eligible
--   for reclaim by the same claim query -- the real crash-recovery mechanic Prompt 132
--   §23 ("exception flow: worker crash/stale lease... enters safe retry") requires.
-- * **Exponential backoff with jitter is a real, tested, disclosed construction, not a
--   cited architecture value.** `02_CANONICAL_DATA_FLOW_MAP.md` §5.4 (Tech Arch §32.17,
--   verbatim) names the qualitative retry pattern ("immediate retry for transient
--   error -> exponential backoff -> max attempts -> DLQ after failure -> manual replay
--   by authorized admin -> idempotency to avoid duplicate effects") but gives no numeric
--   formula anywhere in the architecture corpus or its own reusable job template
--   (`04-reusable-prompts/60_BACKGROUND_JOB_TEMPLATE.md`) -- confirmed via this
--   checkpoint's own research. `app.compute_job_backoff_seconds()` implements the
--   well-known "equal jitter" strategy (half the computed exponential delay is fixed,
--   half is randomized -- never below half the computed backoff, never above it,
--   avoiding both the "thundering herd" of zero-jitter retries and the unbounded
--   randomness of "full jitter"): base 30s, multiplier 2x, capped at 3600s (1 hour).
--   These numeric defaults are ratified in `docs/adr/ADR-0013-job-queue-retry-lease-defaults.md`
--   (resolving a newly-minted `ADR-CAND-ARCH-028`, since this checkpoint's own research
--   confirmed no existing candidate covers this dimension) -- the same "reasoned
--   default absent blueprint-mandated numbers" class `ADR-0002`/`ADR-0004`/`ADR-0011`
--   already used, disclosed as a judgment call, not a citation.
-- * **`app.event_logs` is built here, closing a three-document-deep deferral chain.**
--   `05_DATABASE_SCHEMA_WORKSTREAM.md` line 112 names it as the outbox-pattern table
--   for async job/webhook dispatch; `PLT-116`'s own migration header
--   (`20260716113048_create_audit_trail.sql`) explicitly deferred it ("no real producer
--   yet... `JOB`/`API-WH` are `PLT-129..132`, far downstream"); `PLT-130`'s build log
--   re-confirmed the deferral lands specifically on this task. `app.append_event_log()`
--   is the write path any future domain capability would call to record a business
--   event; `app.dispatch_event_as_job()` is the real outbox-drain mechanic -- it turns a
--   pending event into a real `app.jobs` row (idempotent: re-dispatching an
--   already-dispatched event returns the same linked job, never double-enqueues) -- the
--   live scheduler that would call it periodically is disclosed `NOT_RUN` (no cron/poll
--   infrastructure exists anywhere in this repository yet, the same `NOT_RUN` class
--   `PLT-123`'s escalation timer and `PLT-125`'s numbering counter both already
--   disclosed). Since an event-dispatched job has no human requester, this migration
--   also drops `app.jobs.requested_by_auth_user_id`'s `NOT NULL` constraint --
--   RLS's own `requested_by_auth_user_id = auth.uid()` branch simply never matches a
--   null value, so a system-dispatched job is visible only to Supreme Admin/support
--   authority, never silently to an arbitrary caller.
-- * **`app.jobs`' existing `authenticated`-scoped RLS policy (`jobs_select_scoped`,
--   `PLT-131`) is deliberately left unchanged, not tightened to `service_role_only`.**
--   This checkpoint's own research found `06_RLS_RBAC_WORKSTREAM.md` names `jobs` under
--   its `service_role_only` policy family (lines 92/138/192), which conflicts with
--   `PLT-131`'s already-shipped, already-tested direct-table `authenticated` SELECT
--   policy (justified there as "the 'shared business data' precedent... job status is
--   not itself secret"). Retroactively tightening RLS now would be a breaking behavior
--   change to already-verified functionality with no requesting need, and `PLT-131`'s
--   own reasoning stands on its own merits -- disclosed here as an intentional,
--   considered continuation of that precedent, not an oversight. `app.event_logs`,
--   this migration's own new table, instead follows the literal `append_only_ledger`
--   family text -- zero `authenticated` grant at all, matching `app.audit_logs`'
--   precedent exactly (RLS enabled, zero policies, explicit `service_role`-only grants).
-- * **`app.cancel_import_export_job`/`app.acknowledge_job_cancellation`/
--   `app.record_job_failure`/`app.requeue_dead_letter_job` (all `PLT-131`) are reused
--   directly for the generic job lifecycle, not forked.** Despite their import/export-
--   flavored names, none of their bodies ever inspected `job_type` -- they already
--   operate on any `app.jobs` row via generic tenant-membership/support-authority
--   checks. This migration extends three of them via `CREATE OR REPLACE FUNCTION` to
--   also release the worker lease (`locked_by`/`locked_until`) and clear/compute
--   `next_attempt_at` -- purely additive column-setting, identical signatures and
--   identical exception message prefixes preserved verbatim so `PLT-131`'s own already-
--   passing db-test assertions remain valid unmodified (never weakening an existing
--   test, Prompt 132 §29's own explicit requirement).
-- * Per `ERR-2026-004`: this migration carries its own explicit
--   `revoke execute on all functions in schema app from public;` before its final
--   grants.

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry',
    'document_generation', 'dashboard_refresh', 'loyalty_expiration', 'recurring_billing',
    'integration_sync'
  )
);

alter table app.jobs add column next_attempt_at timestamptz;
alter table app.jobs alter column requested_by_auth_user_id drop not null;

comment on column app.jobs.next_attempt_at is
  'PLT-132: a pending job is not claimable by app.claim_next_job() until this timestamp passes -- the physical exponential-backoff-with-jitter scheduling mechanism (null means immediately claimable, the default for a freshly-enqueued job).';
comment on column app.jobs.requested_by_auth_user_id is
  'PLT-131/132: the human requester for a user-initiated job (import/export); null for a system-dispatched job created by app.dispatch_event_as_job() from app.event_logs, which has no human requester.';

-- ADR-0013's own ratified formula: equal-jitter exponential backoff, base 30s,
-- multiplier 2x, capped at 3600s (1 hour) -- half the computed delay is fixed, half is
-- randomized, so the result is always in [capped/2, capped]. volatile (uses random()),
-- never immutable.
create function app.compute_job_backoff_seconds(p_attempts integer)
returns integer
language plpgsql
volatile
as $$
declare
  v_base constant integer := 30;
  v_multiplier constant integer := 2;
  v_cap constant integer := 3600;
  v_uncapped double precision;
  v_capped integer;
begin
  v_uncapped := v_base * power(v_multiplier, greatest(p_attempts - 1, 0));
  v_capped := least(v_cap, floor(v_uncapped)::integer);
  return greatest(1, (v_capped / 2) + floor(random() * (v_capped / 2)))::integer;
end;
$$;

comment on function app.compute_job_backoff_seconds is
  'PLT-132/ADR-0013: equal-jitter exponential backoff (base 30s, 2x multiplier, capped at 3600s) -- a disclosed reasoned default, no numeric formula exists anywhere in the architecture corpus for this dimension.';

create function app.check_job_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

create function app.check_job_admin_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id);
$$;

-- The generic enqueue entry point for the eight new job_type codes only -- import/export
-- retain their own dedicated app.create_import_export_job() (PLT-131), which resolves a
-- published schema and validates a source_file_id these generic jobs have no equivalent
-- of. Idempotent per (tenant_id, idempotency_key), matching every other capability's
-- own standing idempotency convention this session.
create function app.enqueue_job(
  p_tenant_id uuid,
  p_job_type text,
  p_payload jsonb,
  p_priority integer,
  p_idempotency_key text,
  p_max_attempts integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_existing app.jobs;
  v_job app.jobs;
  v_valid_job_types text[] := array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync'
  ];
begin
  if not app.check_job_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_job_type in ('import', 'export') then
    raise exception 'job_type_requires_dedicated_entrypoint: % jobs must be created via app.create_import_export_job()', p_job_type
      using errcode = 'check_violation';
  end if;

  if not (p_job_type = any (v_valid_job_types)) then
    raise exception 'job_invalid_type: % is not a known generic job type', p_job_type
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
  end if;

  if not app.validate_config_value(coalesce(p_payload, '{}'::jsonb)) then
    raise exception 'job_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_max_attempts, 3) <= 0 then
    raise exception 'job_invalid_max_attempts: max_attempts must be positive'
      using errcode = 'check_violation';
  end if;

  insert into app.jobs (
    tenant_id, job_type, payload, priority, max_attempts, idempotency_key,
    requested_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_job_type, coalesce(p_payload, '{}'::jsonb), coalesce(p_priority, 0), coalesce(p_max_attempts, 3), p_idempotency_key,
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_job;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_id', v_job.job_id, 'job_type', v_job.job_type)
  );

  return v_job;
end;
$$;

-- The atomic claim, service_role/worker-context-only (never authenticated -- a real
-- worker process is a service identity, not a tenant user). SELECT ... FOR UPDATE SKIP
-- LOCKED is PostgreSQL's own standard mechanism ensuring no two concurrent callers can
-- ever claim the same row, genuinely provable via this checkpoint's own db-test without
-- a live multi-process worker fleet, since SKIP LOCKED's row-level locking guarantee is
-- a documented PostgreSQL feature (since 9.5), not something this migration invents.
-- Deliberately does not increment `attempts` -- that remains exclusively
-- app.record_job_failure()'s own responsibility (attempts counts failed tries, not
-- claim attempts), so re-claiming a stale lease after a worker crash does not
-- double-count against max_attempts.
create function app.claim_next_job(
  p_worker_id text,
  p_job_types text[],
  p_lease_duration_seconds integer default 300
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
begin
  if p_worker_id is null or length(p_worker_id) = 0 then
    raise exception 'job_worker_id_required: a worker id is required to claim a job'
      using errcode = 'check_violation';
  end if;
  if p_lease_duration_seconds is null or p_lease_duration_seconds <= 0 then
    raise exception 'job_invalid_lease_duration: lease duration must be positive'
      using errcode = 'check_violation';
  end if;

  select * into v_job
  from app.jobs
  where job_type = any (p_job_types)
    and (
      (status = 'pending' and (next_attempt_at is null or next_attempt_at <= now()))
      or (status = 'in_progress' and locked_until < now())
    )
  order by priority desc, created_at asc
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update app.jobs
  set status = 'in_progress',
      locked_by = p_worker_id,
      locked_until = now() + (p_lease_duration_seconds || ' seconds')::interval,
      next_attempt_at = null
  where job_id = v_job.job_id
  returning * into v_job;

  perform app.capture_audit_event(
    v_job.tenant_id, v_job.requested_by_auth_user_id, p_worker_id, 'claim_next_job',
    'app.jobs', v_job.job_id, 'success', null, null,
    jsonb_build_object('job_type', v_job.job_type, 'locked_by', p_worker_id)
  );

  return v_job;
end;
$$;

-- The real function a live worker calls periodically while still processing a long-
-- running job, to prove liveness and extend its own lease before it expires. Refuses to
-- extend a lease the caller does not currently hold (job_lease_not_held) -- the
-- concrete "no two live workers own the same lease" guarantee (Prompt 132 §25) extended
-- to the heartbeat path, not just the initial claim.
create function app.heartbeat_job(
  p_job_id uuid,
  p_worker_id text,
  p_lease_duration_seconds integer default 300
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status <> 'in_progress' or v_job.locked_by is distinct from p_worker_id then
    raise exception 'job_lease_not_held: worker % does not hold the current lease for job %', p_worker_id, p_job_id
      using errcode = 'check_violation';
  end if;

  update app.jobs
  set locked_until = now() + (p_lease_duration_seconds || ' seconds')::interval
  where job_id = p_job_id
  returning * into v_job;

  return v_job;
end;
$$;

-- Terminal success. Only the worker currently holding the lease may complete a job --
-- the same "no two workers own the same effective side effect" guarantee (§25).
create function app.complete_job(
  p_job_id uuid,
  p_worker_id text,
  p_result_url text,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status <> 'in_progress' or v_job.locked_by is distinct from p_worker_id then
    raise exception 'job_lease_not_held: worker % does not hold the current lease for job %', p_worker_id, p_job_id
      using errcode = 'check_violation';
  end if;

  update app.jobs
  set status = 'completed',
      completed_at = now(),
      result_url = p_result_url,
      locked_by = null,
      locked_until = null,
      next_attempt_at = null,
      error = null
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, v_job.requested_by_auth_user_id, p_actor_label, 'complete_job',
    'app.jobs', p_job_id, 'success', null, jsonb_build_object('status', v_job.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

-- Extended (CREATE OR REPLACE, same signature and exception prefixes as PLT-131 --
-- see this migration's own header): releases the worker lease and schedules the next
-- retry via app.compute_job_backoff_seconds() instead of an immediate-pending requeue.
create or replace function app.record_job_failure(
  p_job_id uuid,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_new_attempts integer;
  v_dead_letter boolean;
  v_backoff_seconds integer;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status in ('completed', 'cancelled', 'dead_letter') then
    raise exception 'import_export_job_already_terminal: job % is already %, cannot record a failure', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  v_new_attempts := v_job.attempts + 1;
  v_dead_letter := v_new_attempts >= v_job.max_attempts;
  v_backoff_seconds := case when v_dead_letter then null else app.compute_job_backoff_seconds(v_new_attempts) end;

  update app.jobs
  set attempts = v_new_attempts,
      error = p_error_message,
      status = case when v_dead_letter then 'dead_letter' else 'pending' end,
      completed_at = case when v_dead_letter then now() else null end,
      locked_by = null,
      locked_until = null,
      next_attempt_at = case when v_dead_letter then null else now() + (v_backoff_seconds || ' seconds')::interval end
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_job_failure',
    'app.jobs', p_job_id, 'failure', p_error_message,
    jsonb_build_object('attempts', v_job.attempts, 'status', v_job.status),
    jsonb_build_object('attempts', v_updated.attempts, 'status', v_updated.status, 'next_attempt_at', v_updated.next_attempt_at)
  );

  return v_updated;
end;
$$;

-- Extended (CREATE OR REPLACE, same signature/prefixes): also clears next_attempt_at/
-- locked_by/locked_until so a requeued job is immediately claimable with a clean lease.
create or replace function app.requeue_dead_letter_job(
  p_job_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_import_export_admin_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_requeue_unauthorized: identity % lacks support/supreme authority over tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status <> 'dead_letter' then
    raise exception 'import_export_job_not_dead_letter: job % is %, only a dead_letter job may be requeued', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  update app.jobs
  set status = 'pending', attempts = 0, error = null, completed_at = null,
      next_attempt_at = null, locked_by = null, locked_until = null
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'requeue_dead_letter_job',
    'app.jobs', p_job_id, 'success', null, jsonb_build_object('status', 'dead_letter'), jsonb_build_object('status', 'pending')
  );

  return v_updated;
end;
$$;

-- Extended (CREATE OR REPLACE, same signature/prefixes): also releases the worker lease
-- so an acknowledged-cancelled job never shows a stale locked_by.
create or replace function app.acknowledge_job_cancellation(
  p_job_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_job app.jobs;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.status <> 'cancelling' then
    raise exception 'import_export_job_not_cancelling: job % is %, only a cancelling job may acknowledge cancellation', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  update app.jobs
  set status = 'cancelled', completed_at = now(), locked_by = null, locked_until = null, next_attempt_at = null
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'acknowledge_job_cancellation',
    'app.jobs', p_job_id, 'success', null, null, jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

-- The outbox-pattern table -- see this migration's own header for the full three-
-- document deferral chain this closes. Append-only: no update/delete path is ever
-- exposed to any role but service_role's own direct table grant.
create table app.event_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  event_type text not null,
  resource_type text not null,
  resource_id uuid,
  payload jsonb not null default '{}'::jsonb,
  dispatch_status text not null default 'pending',
  related_job_id uuid references app.jobs (job_id),
  occurred_at timestamptz not null default now(),
  dispatched_at timestamptz,
  error text,
  created_by text,
  constraint event_logs_dispatch_status_check check (dispatch_status in ('pending', 'dispatched', 'failed'))
);

comment on table app.event_logs is
  'PLT-132: the business event stream / outbox-pattern table for async job/webhook dispatch (05_DATABASE_SCHEMA_WORKSTREAM.md line 112, Tech Arch §9.7/§22) -- deliberately deferred here since PLT-116, this task''s own named owning capability. A pending event becomes a real app.jobs row via app.dispatch_event_as_job(); the live scheduler that would call it periodically is disclosed NOT_RUN (no cron/poll infrastructure exists anywhere in this repository yet).';

create index event_logs_pending_idx on app.event_logs (occurred_at) where dispatch_status = 'pending';
create index event_logs_tenant_idx on app.event_logs (tenant_id, occurred_at desc);

create function app.append_event_log(
  p_tenant_id uuid,
  p_event_type text,
  p_resource_type text,
  p_resource_id uuid,
  p_payload jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.event_logs
language plpgsql
as $$
declare
  v_event app.event_logs;
begin
  if coalesce(length(p_event_type), 0) = 0 then
    raise exception 'event_missing_type: an event_type is required'
      using errcode = 'check_violation';
  end if;
  if coalesce(length(p_resource_type), 0) = 0 then
    raise exception 'event_missing_resource_type: a resource_type is required'
      using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(coalesce(p_payload, '{}'::jsonb)) then
    raise exception 'event_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  insert into app.event_logs (tenant_id, event_type, resource_type, resource_id, payload, created_by)
  values (p_tenant_id, p_event_type, p_resource_type, p_resource_id, coalesce(p_payload, '{}'::jsonb), p_actor_label)
  returning * into v_event;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'append_event_log',
    'app.event_logs', v_event.id, 'success', null, null,
    jsonb_build_object('event_type', p_event_type, 'resource_type', p_resource_type)
  );

  return v_event;
end;
$$;

-- The real outbox-drain mechanic: turns a pending business event into a real app.jobs
-- row. Idempotent -- re-dispatching an already-dispatched event returns the same
-- linked job rather than double-enqueueing. Inserts directly (bypassing
-- app.enqueue_job()'s tenant-membership actor check) since the caller here is the
-- system/scheduler itself, not a tenant-authenticated user -- requested_by_auth_user_id
-- is left null for these jobs (this migration's own header explains the RLS
-- consequence).
create function app.dispatch_event_as_job(
  p_event_id uuid,
  p_job_type text,
  p_priority integer,
  p_idempotency_key text,
  p_max_attempts integer,
  p_actor_label text
)
returns app.jobs
language plpgsql
as $$
declare
  v_event app.event_logs;
  v_job app.jobs;
  v_valid_job_types text[] := array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync'
  ];
begin
  select * into v_event from app.event_logs where id = p_event_id;
  if not found then
    raise exception 'event_not_found: no event %', p_event_id using errcode = 'no_data_found';
  end if;

  if v_event.dispatch_status = 'dispatched' then
    select * into v_job from app.jobs where job_id = v_event.related_job_id;
    return v_job;
  end if;

  if not (p_job_type = any (v_valid_job_types)) then
    raise exception 'event_invalid_job_type: % is not a dispatchable generic job type', p_job_type
      using errcode = 'check_violation';
  end if;

  insert into app.jobs (
    tenant_id, job_type, payload, priority, max_attempts, idempotency_key,
    requested_by_auth_user_id, created_by
  ) values (
    v_event.tenant_id, p_job_type,
    jsonb_build_object('event_id', v_event.id, 'event_type', v_event.event_type, 'resource_type', v_event.resource_type, 'resource_id', v_event.resource_id, 'payload', v_event.payload),
    coalesce(p_priority, 0), coalesce(p_max_attempts, 3), p_idempotency_key,
    null, p_actor_label
  )
  returning * into v_job;

  update app.event_logs
  set dispatch_status = 'dispatched', dispatched_at = now(), related_job_id = v_job.job_id, error = null
  where id = p_event_id;

  return v_job;
end;
$$;

create function app.mark_event_dispatch_failed(
  p_event_id uuid,
  p_error text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.event_logs
language plpgsql
as $$
declare
  v_event app.event_logs;
  v_updated app.event_logs;
begin
  select * into v_event from app.event_logs where id = p_event_id;
  if not found then
    raise exception 'event_not_found: no event %', p_event_id using errcode = 'no_data_found';
  end if;

  update app.event_logs
  set dispatch_status = 'failed', error = p_error
  where id = p_event_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'mark_event_dispatch_failed',
    'app.event_logs', p_event_id, 'failure', p_error, null, null
  );

  return v_updated;
end;
$$;

alter table app.event_logs enable row level security;

revoke execute on all functions in schema app from public;

grant select, insert, update, delete on app.event_logs to service_role;

grant execute on function app.compute_job_backoff_seconds(integer) to service_role;
grant execute on function app.check_job_authority(uuid, uuid) to service_role;
grant execute on function app.check_job_admin_authority(uuid, uuid) to service_role;
grant execute on function app.enqueue_job(uuid, text, jsonb, integer, text, integer, uuid, text) to service_role;
grant execute on function app.claim_next_job(text, text[], integer) to service_role;
grant execute on function app.heartbeat_job(uuid, text, integer) to service_role;
grant execute on function app.complete_job(uuid, text, text, text) to service_role;
grant execute on function app.append_event_log(uuid, text, text, uuid, jsonb, uuid, text) to service_role;
grant execute on function app.dispatch_event_as_job(uuid, text, integer, text, integer, text) to service_role;
grant execute on function app.mark_event_dispatch_failed(uuid, text, uuid, text) to service_role;
