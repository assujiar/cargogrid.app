-- Phase 9 capability IAE-002 (Reporting Engine, Prompt 330, CG-S14-IAE-002)
-- Adds real report-definition versioning and structural per-report parameter
-- validation on top of the already-`VERIFIED` COM-159 report catalog
-- (`app.report_types`/`app.report_runs`, `20260724330000_create_commercial_reports.sql`)
-- that Commercial, Operations (OPS-183), Finance (FIN-213) and Procurement have
-- already extended with 29 report codes across 4 domains -- this migration is
-- a governance layer over that existing, already-audited catalog, never a
-- second, parallel reporting engine (`ADR-0025`'s own "extend, do not duplicate"
-- discipline, applied here to a Phase 1-8 primitive rather than a Phase 9 one).
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **Definition versioning is additive, append-only history, never a rewrite
--   of prior evidence** (Prompt 330 business rule, `330_*.md` §24: "changes do
--   not rewrite prior evidence"). `app.report_type_versions` is the new
--   append-only ledger; `app.report_types` itself keeps being the single
--   "current definition" row every existing caller (`record_report_run`,
--   `enqueue_report_export`, all 29 domain dashboard reads) already reads
--   unchanged -- publishing a new version updates `report_types`' own
--   `source_function`/`parameter_schema`/`description`/`version` columns AND
--   appends a new `report_type_versions` row in the same transaction, so
--   "current" and "history" can never drift apart.
-- * **Backfill is a real, direct copy of already-existing column values, not a
--   fabricated history.** Every one of the 29 pre-existing `report_types` rows
--   gets exactly one `report_type_versions` row (`version_number = 1`) built
--   from that row's own `source_function`/`description`/`registered_by`/
--   `created_at` -- there was only ever one version of any of them until now.
--   `report_runs.report_type_version_id` is backfilled the same way: every
--   existing run cites the one version that existed when it ran.
-- * **`parameter_schema` defaults to `'{}'::jsonb` (no declared contract) for
--   every one of the 29 pre-existing reports**, deliberately left un-retrofitted
--   rather than this checkpoint inventing 29 bespoke schemas by inference from
--   each domain's own function signature (a correctness risk this migration
--   does not take on) -- `app.validate_report_parameters` treats an empty
--   schema as "no engine-level contract, defer entirely to the domain
--   function's own validation," so every existing report's behavior is
--   byte-for-byte unchanged. Retrofitting real schemas onto the 29 existing
--   reports is a disclosed, named, future documentation-only task, not this
--   migration's own bounded scope. A real, tested example schema is published
--   for one fresh test report type in `scripts/db-tests/reporting-engine.sql`,
--   proving the mechanism itself, not merely asserting it exists.
-- * **`app.validate_report_parameters` is strict-by-declared-schema, permissive
--   by absence**: an empty schema always passes (backward compatible); a
--   non-empty schema requires every `required: true` key present with a
--   matching `jsonb_typeof`, and rejects any parameter key the schema does not
--   declare (closed-world once a schema exists, open-world before one does).
-- * **`app.publish_report_type_version` is Supreme-only**, mirroring
--   `app.register_report_type`/`app.retire_report_type`'s own already-ratified
--   "reports are a product feature, not a tenant-authored config object" design
--   (COM-159's own header) -- never routed through the Configuration Engine's
--   tenant-publish flow.
-- * **`app.cancel_report_run` operates on `app.report_runs` only, never
--   `app.jobs`.** No generic `app.cancel_job` primitive exists on the shared
--   durable queue (only domain-specific cancel functions like
--   `app.cancel_import_export_job` exist) and no live worker anywhere in this
--   repository ever advances a `report_generation` job past `queued` (the same
--   disclosed `NOT_RUN` condition `PLT-132`'s own migration header already
--   carries) -- cancelling the bookkeeping row is the complete, correct action
--   in this environment; a future live-worker capability owns real in-flight
--   job cancellation.
-- * **No new REST/GraphQL route is added.** `app.report_types`/`app.report_runs`/
--   `app.report_type_versions` already grant direct `select` to `authenticated`
--   behind `report_runs`' own RLS policy (tenant-wide visibility, COM-159's own
--   precedent) -- `server/queries/report.ts` (extended, not a new file) reads
--   them directly, the same "typed direct read over an already-RLS-scoped
--   table" convention most `server/queries/*.ts` files in this repository
--   already use, rather than adding parallel read RPCs.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
--   its own explicit `revoke execute on all functions in schema app from
--   public` statement before its final grants, the standing per-migration
--   convention since `PLT-118`.
-- * **ATW-032 (`ISS-2026-032`) actor-identity fix, found by this migration's
--   own `scripts/db-tests/rbac-enforcement.sql` re-run, not fixed silently.**
--   The repository-wide sweep that every side-effecting, `authenticated`-
--   granted function taking `p_actor_auth_user_id` must reach
--   `app.assert_actor_is_session_identity` (directly or via
--   `app.evaluate_permission`, which already calls it per `ATW-031`) flagged
--   THREE functions this migration's own diff touches: the two pre-existing
--   COM-159 functions this migration re-creates via `create or replace`
--   (`app.register_report_type`, `app.record_report_run` -- neither ever
--   called either primitive, a standing gap since Phase 2 that this
--   checkpoint's own `create or replace` now closes rather than silently
--   reproducing) and this migration's own new `app.publish_report_type_version`.
--   All three, plus `app.cancel_report_run` (a genuine, not merely
--   linter-driven, fix -- its own identity check only ran inside the
--   `requested_by_auth_user_id <> p_actor_auth_user_id` branch, so a caller
--   could claim `p_actor_auth_user_id` equal to the run's own requester and
--   skip it entirely), now call `app.assert_actor_is_session_identity` as
--   their first statement. `app.enqueue_report_export` already called
--   `app.evaluate_permission` unconditionally and needed no change.
-- * **Two further Tier B self-review fixes (`docs/standards/RECURRING_DEFECT_TAXONOMY.md`
--   §4), found before commit, not by a later review round:** (C-04) two concurrent
--   `app.publish_report_type_version` calls for the same code could both compute
--   the same `v_next_version` from an unlocked read -- the report_types row is now
--   locked `for update` before that decision. (C-05) `app.cancel_report_run` read
--   `app.report_runs` by id (a `SECURITY DEFINER` function bypasses RLS) and would
--   have raised `insufficient_authority` for a caller with no relationship to that
--   run's own tenant, disclosing that the id exists somewhere -- it now raises the
--   identical `report_run_not_found` a genuinely missing id produces, mirroring the
--   already-established `vendor_payment_term_proposal_not_found` precedent
--   (`PRC-269`, `ISS-2026-054` C-05).

alter table app.report_types
  add column parameter_schema jsonb not null default '{}'::jsonb,
  add constraint report_types_parameter_schema_check check (jsonb_typeof(parameter_schema) = 'object');

comment on column app.report_types.parameter_schema is
  'IAE-002: structural parameter contract, e.g. {"currency": {"type": "string", "required": false}}. Empty object (the default for every pre-existing report) means no engine-level contract -- validation defers entirely to the domain source_function, unchanged behavior.';

create table app.report_type_versions (
  id uuid primary key default gen_random_uuid(),
  report_type_code text not null references app.report_types (code),
  version_number integer not null,
  source_function text not null,
  parameter_schema jsonb not null default '{}'::jsonb,
  description text not null,
  published_by_auth_user_id uuid references auth.users (id),
  published_by text,
  published_at timestamptz not null default now(),
  constraint report_type_versions_version_check check (version_number > 0),
  constraint report_type_versions_schema_check check (jsonb_typeof(parameter_schema) = 'object'),
  constraint report_type_versions_unique unique (report_type_code, version_number)
);

comment on table app.report_type_versions is
  'IAE-002: append-only definition-version history for app.report_types (Prompt 330 §13/§24 "report definition/version"). app.report_types itself always reflects the latest published version; this table is the immutable evidence trail a report_runs row cites via report_type_version_id, never rewritten by a later publish.';

create index report_type_versions_code_idx on app.report_type_versions (report_type_code, version_number desc);

insert into app.report_type_versions (report_type_code, version_number, source_function, parameter_schema, description, published_by, published_at)
select code, 1, source_function, parameter_schema, description, registered_by, created_at
from app.report_types;

alter table app.report_runs
  add column report_type_version_id uuid references app.report_type_versions (id);

update app.report_runs r
set report_type_version_id = v.id
from app.report_type_versions v
where v.report_type_code = r.report_type_code
  and v.version_number = 1
  and r.report_type_version_id is null;

create index report_runs_version_idx on app.report_runs (report_type_version_id) where report_type_version_id is not null;

comment on column app.report_runs.report_type_version_id is
  'IAE-002: the exact report_type_versions row this run executed against, stamped at record_report_run/enqueue_report_export time -- backfilled to each report''s own version 1 for every run that predates this migration, since only one version of any report ever existed until now.';

create or replace function app.register_report_type(
  p_code text,
  p_name text,
  p_description text,
  p_source_function text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.report_types
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.report_types;
  v_type app.report_types;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a report type'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.report_types where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.report_types (code, name, description, source_function, registered_by)
  values (p_code, p_name, p_description, p_source_function, p_registered_by)
  returning * into v_type;

  insert into app.report_type_versions (report_type_code, version_number, source_function, parameter_schema, description, published_by_auth_user_id, published_by)
  values (v_type.code, 1, v_type.source_function, v_type.parameter_schema, v_type.description, p_actor_auth_user_id, p_registered_by);

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_report_type',
    'app.report_types', null, 'success', null, null, to_jsonb(v_type)
  );

  return v_type;
end;
$$;

comment on function app.register_report_type is
  'COM-159, extended IAE-002: same idempotent Supreme-only registration as before, now additionally seeds the matching version-1 app.report_type_versions row at registration time, so every report type -- pre-existing or newly registered -- always has a real version history from the moment it exists.';

create function app.validate_report_parameters(p_schema jsonb, p_parameters jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_key text;
  v_field jsonb;
  v_required boolean;
  v_type text;
  v_value jsonb;
begin
  if not app.validate_config_value(coalesce(p_parameters, '{}'::jsonb)) then
    return false;
  end if;

  if p_schema is null or jsonb_typeof(p_schema) <> 'object' or p_schema = '{}'::jsonb then
    return true;
  end if;

  for v_key, v_field in select * from jsonb_each(p_schema) loop
    v_required := coalesce((v_field ->> 'required')::boolean, false);
    v_type := v_field ->> 'type';
    v_value := p_parameters -> v_key;

    if v_value is null then
      if v_required then
        return false;
      end if;
      continue;
    end if;

    if v_type is not null and jsonb_typeof(v_value) <> v_type then
      return false;
    end if;
  end loop;

  for v_key in select jsonb_object_keys(coalesce(p_parameters, '{}'::jsonb)) loop
    if not (p_schema ? v_key) then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

comment on function app.validate_report_parameters is
  'IAE-002: structural parameter-schema validation. Empty schema always passes (backward compatible with every pre-existing report); a declared schema requires every required key present with a matching jsonb_typeof and rejects any undeclared key.';

create function app.publish_report_type_version(
  p_code text,
  p_source_function text,
  p_parameter_schema jsonb,
  p_description text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.report_type_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_type app.report_types;
  v_next_version integer;
  v_version app.report_type_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may publish a report type version'
      using errcode = 'insufficient_privilege';
  end if;

  -- C-04 (docs/standards/RECURRING_DEFECT_TAXONOMY.md): lock the row before deciding
  -- the next version number -- without this, two concurrent publishes for the same
  -- code could both compute the same v_next_version and race on the insert.
  select * into v_type from app.report_types where code = p_code for update;
  if not found then
    raise exception 'report_type_unknown: %', p_code using errcode = 'no_data_found';
  end if;

  if p_parameter_schema is null or jsonb_typeof(p_parameter_schema) <> 'object' then
    raise exception 'report_invalid_parameter_schema: parameter_schema must be a JSON object'
      using errcode = 'check_violation';
  end if;

  if p_source_function is null or length(trim(p_source_function)) = 0 then
    raise exception 'report_invalid_source_function: source_function is required' using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version
  from app.report_type_versions where report_type_code = p_code;

  insert into app.report_type_versions (
    report_type_code, version_number, source_function, parameter_schema, description,
    published_by_auth_user_id, published_by
  ) values (
    p_code, v_next_version, p_source_function, p_parameter_schema, coalesce(p_description, v_type.description),
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_version;

  update app.report_types
  set source_function = p_source_function,
      parameter_schema = p_parameter_schema,
      description = coalesce(p_description, description),
      version = v_next_version
  where code = p_code;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'publish_report_type_version',
    'app.report_type_versions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$$;

comment on function app.publish_report_type_version is
  'IAE-002: Supreme-only, append-only definition-version publish. Updates app.report_types to the new "current" state and appends the immutable version-history row in the same transaction -- every report_runs row already recorded keeps citing its own prior report_type_version_id, never rewritten.';

create or replace function app.record_report_run(
  p_tenant_id uuid,
  p_report_type_code text,
  p_parameters jsonb,
  p_row_count integer,
  p_masked_columns text[],
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.report_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_type app.report_types;
  v_version_id uuid;
  v_run app.report_runs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_type from app.report_types where code = p_report_type_code;
  if not found then
    raise exception 'report_type_unknown: %', p_report_type_code using errcode = 'no_data_found';
  end if;
  if v_type.status <> 'active' then
    raise exception 'report_type_retired: % is retired and can no longer be run', p_report_type_code using errcode = 'check_violation';
  end if;

  if not (app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_report_parameters(v_type.parameter_schema, coalesce(p_parameters, '{}'::jsonb)) then
    raise exception 'report_unsafe_parameters: parameters failed structural or schema validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_row_count, 0) < 0 then
    raise exception 'report_invalid_row_count: row_count must not be negative' using errcode = 'check_violation';
  end if;

  select id into v_version_id from app.report_type_versions
  where report_type_code = p_report_type_code order by version_number desc limit 1;

  insert into app.report_runs (
    tenant_id, report_type_code, run_type, status, parameters, row_count, masked_columns,
    report_type_version_id, requested_by_auth_user_id, created_by, completed_at
  ) values (
    p_tenant_id, p_report_type_code, 'preview', 'completed', coalesce(p_parameters, '{}'::jsonb), p_row_count, coalesce(p_masked_columns, '{}'),
    v_version_id, p_actor_auth_user_id, p_actor_label, now()
  )
  returning * into v_run;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_report_run',
    'app.report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('report_type_code', p_report_type_code, 'run_type', 'preview', 'row_count', p_row_count)
  );

  return v_run;
end;
$$;

comment on function app.record_report_run is
  'COM-159, extended IAE-002: same signature and evidence-recording behavior as before, now additionally validates p_parameters against the report type''s own declared parameter_schema (a no-op for every report with the default empty schema) and stamps the current report_type_version_id.';

create or replace function app.enqueue_report_export(
  p_tenant_id uuid,
  p_report_type_code text,
  p_parameters jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.report_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_type app.report_types;
  v_decision app.rbac_decision;
  v_version_id uuid;
  v_job app.jobs;
  v_run app.report_runs;
begin
  select * into v_type from app.report_types where code = p_report_type_code;
  if not found then
    raise exception 'report_type_unknown: %', p_report_type_code using errcode = 'no_data_found';
  end if;
  if v_type.status <> 'active' then
    raise exception 'report_type_retired: % is retired and can no longer be exported', p_report_type_code using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Export');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Export (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_report_parameters(v_type.parameter_schema, coalesce(p_parameters, '{}'::jsonb)) then
    raise exception 'report_unsafe_parameters: parameters failed structural or schema validation'
      using errcode = 'check_violation';
  end if;

  select id into v_version_id from app.report_type_versions
  where report_type_code = p_report_type_code order by version_number desc limit 1;

  v_job := app.enqueue_job(
    p_tenant_id, 'report_generation',
    jsonb_build_object('report_type_code', p_report_type_code, 'parameters', coalesce(p_parameters, '{}'::jsonb)),
    0, null, 3, p_actor_auth_user_id, p_actor_label
  );

  insert into app.report_runs (
    tenant_id, report_type_code, run_type, status, parameters, job_id,
    report_type_version_id, requested_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_report_type_code, 'export', 'queued', coalesce(p_parameters, '{}'::jsonb), v_job.job_id,
    v_version_id, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_run;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_report_export',
    'app.report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('report_type_code', p_report_type_code, 'job_id', v_job.job_id)
  );

  return v_run;
end;
$$;

comment on function app.enqueue_report_export is
  'COM-159, extended IAE-002: same signature and behavior as before, now additionally validates p_parameters against the report type''s own declared parameter_schema and stamps the current report_type_version_id.';

create function app.cancel_report_run(
  p_run_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.report_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.report_runs;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_run from app.report_runs where id = p_run_id;
  if not found then
    raise exception 'report_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  -- C-05 (docs/standards/RECURRING_DEFECT_TAXONOMY.md): a caller with no relationship
  -- to this run's own tenant gets the identical report_run_not_found a genuinely
  -- missing id would produce, never insufficient_authority -- which would disclose
  -- that a run/tenant exists at all, mirroring the already-established
  -- vendor_payment_term_proposal_not_found precedent (PRC-269, ISS-2026-054 C-05).
  if not (app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id)) then
    raise exception 'report_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  if v_run.requested_by_auth_user_id <> p_actor_auth_user_id and not app.is_supreme_admin(p_actor_auth_user_id) then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_run.tenant_id, 'COM', 'Export');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % may not cancel a report run it did not request', p_actor_auth_user_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  if v_run.status <> 'queued' then
    raise exception 'report_run_not_cancellable: status is % (only queued runs can be cancelled)', v_run.status
      using errcode = 'check_violation';
  end if;

  update app.report_runs
  set status = 'failed', error_reason = 'cancelled_by_requester', completed_at = now()
  where id = p_run_id
  returning * into v_run;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_report_run',
    'app.report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('report_type_code', v_run.report_type_code)
  );

  return v_run;
end;
$$;

comment on function app.cancel_report_run is
  'IAE-002: cancels a still-queued export run (the only state a cancel is meaningful in, since no live worker ever advances one further in this environment -- disclosed above). The original requester or an actor holding COM:Export (mirroring enqueue_report_export''s own gate) or Supreme Admin may cancel; a completed/failed run cannot be re-cancelled.';

revoke execute on all functions in schema app from public;

grant execute on function app.validate_report_parameters(jsonb, jsonb) to authenticated, service_role;
grant execute on function app.publish_report_type_version(text, text, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_report_run(uuid, uuid, text) to authenticated, service_role;

grant select on app.report_type_versions to authenticated, service_role;
grant insert on app.report_type_versions to service_role;
