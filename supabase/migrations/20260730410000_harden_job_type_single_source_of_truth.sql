-- CG-S10-ATW-031 (post-Prompt-248 codebase audit — closes `ISS-2026-012`).
--
-- `app.jobs.job_type`'s closed valid-list was independently duplicated in four places,
-- and had genuinely drifted apart:
--
--   1. the `app.jobs` table CHECK constraint ........................ 12 values
--   2. `app.enqueue_job`'s own `v_valid_job_types` array ............ 10 values
--   3. `app.dispatch_event_as_job`'s own separate array .............  8 values
--   4. `GENERIC_JOB_TYPES` in server/contracts/background-job/*.ts ..  8 values
--
-- `ATW-224` (Prompt 243) added `route_load_planning` and `ATW-021` added `print_label`,
-- but each widened only (1) and (2). The live consequence: a `route_load_planning` or
-- `print_label` job is a perfectly valid row the table accepts and `app.enqueue_job`
-- creates, yet `app.dispatch_event_as_job` rejects it outright with
-- `event_invalid_job_type` — so those two job types can never be dispatched from an
-- event, for no reason other than a list nobody remembered to update. The TypeScript
-- union has the same two-value hole, so a caller typing either value fails contract
-- parsing before it ever reaches the database.
--
-- ===========================================================================
-- Repair: one source of truth, and a gate that fails if it ever drifts again
-- ===========================================================================
--
-- `app.generic_job_types()` and `app.all_job_types()` become the single authority.
-- Both `app.enqueue_job` and `app.dispatch_event_as_job` now call
-- `app.generic_job_types()` instead of carrying their own literal, so (2) and (3)
-- collapse into (1) source and the dispatch hole closes as a direct consequence.
--
-- The table CHECK (1) is deliberately NOT rewritten to call the function. A CHECK
-- constraint that calls a function is not re-validated when that function changes, so it
-- would look like a single source of truth while silently becoming a second one — the
-- exact failure this issue is about. Instead the CHECK keeps its literal list, and
-- `scripts/db-tests/background-job-framework.sql` gains an assertion that the CHECK's own
-- list and `app.all_job_types()` are set-equal. Drift now fails `pnpm run db:test`
-- rather than sitting undetected for two capabilities.
--
-- The TypeScript union (4) is widened to match, and its own unit test now asserts the
-- exact list with a pointer back to this migration.
--
-- Additive and reversible: two new IMMUTABLE functions and `CREATE OR REPLACE FUNCTION`
-- on two identical signatures. No table, column, constraint, index, policy, or grant is
-- touched, and no already-applied migration file is edited.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012): the single authority for which job_type values the GENERIC queue mechanics accept -- app.enqueue_job and app.dispatch_event_as_job both call this instead of carrying their own literal copy. Excludes import/export, which keep their own dedicated app.create_import_export_job entrypoint (PLT-131). Mirrored in TypeScript as GENERIC_JOB_TYPES (server/contracts/background-job/background-job.ts); scripts/db-tests/background-job-framework.sql asserts this list and the app.jobs CHECK constraint stay set-equal.';

create or replace function app.all_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select app.generic_job_types() || array['import', 'export']::text[];
$$;

comment on function app.all_job_types is
  'ATW-031 (ISS-2026-012): every job_type app.jobs accepts -- the generic set plus the two dedicated import/export types. The app.jobs job_type CHECK constraint deliberately keeps its own literal list (a CHECK that calls a function is never re-validated when that function changes, which would recreate exactly the drift this closes); scripts/db-tests/background-job-framework.sql asserts the two stay set-equal.';

CREATE OR REPLACE FUNCTION app.enqueue_job(p_tenant_id uuid, p_job_type text, p_payload jsonb, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.jobs
 LANGUAGE plpgsql
AS $function$
declare
  v_existing app.jobs;
  v_job app.jobs;
  v_valid_job_types text[] := app.generic_job_types();
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
      -- ATW-031 (ISS-2026-029): a key already used for a DIFFERENT target is a
      -- conflict, never a replay. Returning the earlier target's row here silently
      -- misattributed this request to it (or silently discarded it entirely).
      if v_existing.job_type is distinct from p_job_type then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different job (job type %, not %)', p_idempotency_key, v_existing.job_type, p_job_type
          using errcode = 'unique_violation';
      end if;
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
$function$;

CREATE OR REPLACE FUNCTION app.dispatch_event_as_job(p_event_id uuid, p_job_type text, p_priority integer, p_idempotency_key text, p_max_attempts integer, p_actor_label text)
 RETURNS app.jobs
 LANGUAGE plpgsql
AS $function$
declare
  v_event app.event_logs;
  v_job app.jobs;
  v_valid_job_types text[] := app.generic_job_types();
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
$function$;


revoke execute on all functions in schema app from public;

grant execute on function app.generic_job_types() to authenticated, service_role;
grant execute on function app.all_job_types() to authenticated, service_role;
grant execute on function app.dispatch_event_as_job(uuid,text,integer,text,integer,text) to service_role;
grant execute on function app.enqueue_job(uuid,text,jsonb,integer,text,integer,uuid,text) to authenticated, service_role;
