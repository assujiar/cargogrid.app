-- Commercial capability COM-159 (Commercial Reports, CG-S7-COM-018)
-- Governed Commercial reports -- a permissioned, audited, exportable rendering of
-- metrics COM-158's own dashboard already proved correct and access-controlled, never a
-- second, ungoverned analytics engine (Prompt 159 §24: "one shared multi-tenant
-- codebase").
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint):
--
-- * **Every report reuses a COM-158 `app.get_dashboard_*` function as its one query
--   engine, verbatim.** `app.report_types.source_function` names it directly. This
--   migration adds no new aggregation SQL at all -- reports are a governance/audit/
--   export layer over already-`VERIFIED` reads, not a duplicate. Of the ten report
--   subjects Prompt 159 §4 names (conversion/aging/activity/pipeline/forecast/costing/
--   quote SLA/win-loss/pricing/margin), the seven this checkpoint's own dashboard
--   already computes are implemented (aging, activity, pipeline, quote SLA, margin,
--   win-loss, forecast); conversion/costing/pricing have no existing governed query to
--   reuse (they belong to `COM-144`/`148`/`156`'s own future report-catalogue work, not
--   built here) and are a disclosed, out-of-scope gap, not a silent omission.
-- * **`app.report_types` is a Supreme-registered, code-shipped catalogue**, mirroring
--   `app.document_types`' own shape (`PLT-128`) -- reports are a product feature, not a
--   tenant-authored config object, so this migration seeds the seven rows directly
--   rather than routing through the Configuration Engine's tenant-publish flow.
-- * **`app.report_runs` is the one audit/bookkeeping table** for both flows: `preview`
--   (synchronous, `status` always lands `completed`/`failed` in the same call) and
--   `export` (asynchronous -- `app.enqueue_report_export` enqueues a real
--   `report_generation` job via `PLT-132`'s own generic queue, `app.enqueue_job`,
--   unchanged). **No live worker processes a `report_generation` job anywhere in this
--   repository** (the same disclosed `NOT_RUN` condition `PLT-132`'s own migration
--   header already carries for every job type it added) -- an export therefore reaches
--   `status='queued'` and stops there in this environment; `report_runs.file_id` (wired
--   to `PLT-128`'s own `app.files`/`app.authorize_file_access` -- private, malware-
--   scanned, signed, audited download, unchanged) is the real, provable target shape a
--   future worker would populate, not a fabricated pipeline.
-- * **Export requires the real, seeded, previously-unused `COM:Export` permission**
--   (already present in the original catalogue at `category='standard'`, `protected=false`
--   -- Prompt 159 §26's "sensitive commercial exports require explicit permission" is
--   satisfied by gating on it at all, not by widening its own protection level, which is
--   out of this bounded task's scope to change), distinct from ordinary preview (no new
--   gate beyond what the underlying `app.get_dashboard_*` function/RLS already enforces
--   -- the same "ordinary view, no extra check" posture COM-158's own functions already
--   established).
-- * **Formula-injection protection is a pure, unit-tested cell-sanitization function at
--   the service layer** (`server/policies/csv-export-sanitize.ts`), not something this
--   migration can prove end-to-end against a real generated file, since no live export
--   pipeline exists to generate one -- disclosed, not invented.
-- * **`app.retire_report_type` is the "retire unsafe exports" mechanism** Prompt 159
--   §19 asks for at the definition level: Supreme-only, sets `status='retired'`, and
--   `app.enqueue_report_export`/`app.record_report_run` both refuse a retired code. No
--   retroactive retraction of an already-issued file is modeled (no live file pipeline
--   exists to retract anything from).
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`.

-- 'COM:Export' was already seeded in the original permission catalogue
-- (20260716103445_create_roles_permissions.sql, PLT-111) but never consumed by any
-- Commercial capability until now -- the same reuse choice COM-148 made for
-- 'View cost' and COM-156 made for 'View margin', except this row already existed
-- rather than needing a fresh insert.

create table app.report_types (
  code text primary key,
  name text not null,
  description text not null,
  source_function text not null,
  version integer not null default 1,
  status text not null default 'active',
  registered_by text,
  created_at timestamptz not null default now(),
  constraint report_types_status_check check (status in ('active', 'retired')),
  constraint report_types_version_check check (version > 0)
);

comment on table app.report_types is
  'COM-159: Supreme-registered, code-shipped report catalogue (mirrors app.document_types, PLT-128). source_function names the exact COM-158 app.get_dashboard_* RPC this report renders -- never a second query engine.';

insert into app.report_types (code, name, description, source_function, registered_by) values
  ('lead_aging', 'Lead Aging', 'Open lead count bucketed by age since last activity.', 'get_dashboard_lead_aging', 'system'),
  ('activity_queue', 'Activity Queue', 'Scheduled activity count bucketed by due-date urgency.', 'get_dashboard_activity_queue', 'system'),
  ('pipeline_summary', 'Pipeline Summary', 'Open opportunity count and value by stage and currency.', 'get_dashboard_pipeline_summary', 'system'),
  ('quote_sla', 'Quote SLA', 'Open submitted-quotation queue bucketed by turnaround/expiry risk.', 'get_dashboard_quote_sla', 'system'),
  ('margin_summary', 'Margin Summary', 'Current margin calculations by currency over an optional period.', 'get_dashboard_margin_summary', 'system'),
  ('win_loss_summary', 'Win / Loss', 'Won and lost opportunity count and value by currency over an optional period.', 'get_dashboard_win_loss_summary', 'system'),
  ('forecast_summary', 'Forecast', 'Probability-weighted open-pipeline value by currency.', 'get_dashboard_forecast_summary', 'system');

create function app.register_report_type(
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

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_report_type',
    'app.report_types', null, 'success', null, null, to_jsonb(v_type)
  );

  return v_type;
end;
$$;

comment on function app.register_report_type is
  'COM-159: idempotent Supreme-only report-type registration, mirrors app.register_document_type (PLT-128) exactly. Returns the existing row unchanged if the code is already registered -- never a duplicate, never an error.';

create function app.retire_report_type(
  p_code text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.report_types
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_type app.report_types;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may retire a report type'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_type from app.report_types where code = p_code;
  if not found then
    raise exception 'report_type_unknown: %', p_code using errcode = 'no_data_found';
  end if;

  update app.report_types set status = 'retired' where code = p_code
  returning * into v_type;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'retire_report_type',
    'app.report_types', null, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_type;
end;
$$;

comment on function app.retire_report_type is
  'COM-159: Prompt 159 §19''s "retire unsafe exports" mechanism at the definition level -- a retired code is refused by both app.record_report_run and app.enqueue_report_export. No retroactive retraction of an already-issued file (no live file pipeline exists to retract from).';

create table app.report_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  report_type_code text not null references app.report_types (code),
  run_type text not null,
  status text not null default 'completed',
  parameters jsonb not null default '{}'::jsonb,
  row_count integer,
  masked_columns text[] not null default '{}',
  job_id uuid references app.jobs (job_id),
  file_id uuid references app.files (id),
  error_reason text,
  requested_by_auth_user_id uuid not null references auth.users (id),
  created_by text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint report_runs_run_type_check check (run_type in ('preview', 'export')),
  constraint report_runs_status_check check (status in ('queued', 'running', 'completed', 'failed')),
  constraint report_runs_row_count_check check (row_count is null or row_count >= 0),
  constraint report_runs_parameters_check check (jsonb_typeof(parameters) = 'object'),
  constraint report_runs_error_reason_check check (
    (status = 'failed' and error_reason is not null and length(trim(error_reason)) > 0)
    or (status <> 'failed')
  )
);

comment on table app.report_runs is
  'COM-159: one audit/bookkeeping row per report execution -- Prompt 159 §18''s own "definition/version, parameters/scope, requester, row count, sensitive columns, run/result access" evidence record. preview runs are synchronous (status always completed/failed by the time the row exists); export runs start queued via app.enqueue_job (PLT-132) and stay there in this environment -- no live worker exists to advance them further, disclosed in this migration''s header, not invented.';

create index report_runs_tenant_type_idx on app.report_runs (tenant_id, report_type_code, requested_at desc);
create index report_runs_tenant_requester_idx on app.report_runs (tenant_id, requested_by_auth_user_id);
create index report_runs_job_idx on app.report_runs (job_id) where job_id is not null;

create function app.record_report_run(
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
  v_run app.report_runs;
begin
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

  if not app.validate_config_value(coalesce(p_parameters, '{}'::jsonb)) then
    raise exception 'report_unsafe_parameters: parameters failed structural validation'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_row_count, 0) < 0 then
    raise exception 'report_invalid_row_count: row_count must not be negative' using errcode = 'check_violation';
  end if;

  insert into app.report_runs (
    tenant_id, report_type_code, run_type, status, parameters, row_count, masked_columns,
    requested_by_auth_user_id, created_by, completed_at
  ) values (
    p_tenant_id, p_report_type_code, 'preview', 'completed', coalesce(p_parameters, '{}'::jsonb), p_row_count, coalesce(p_masked_columns, '{}'),
    p_actor_auth_user_id, p_actor_label, now()
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
  'COM-159: records a synchronous preview run''s evidence (Prompt 159 §18). row_count/masked_columns are self-reported by the caller, which already ran the real app.get_dashboard_* RPC and parsed its own *_masked flags -- this function never re-derives the query or the masking decision, only the audit record of what already happened, the same "record what the caller reports" shape app.capture_audit_event itself already uses everywhere.';

create function app.enqueue_report_export(
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

  if not app.validate_config_value(coalesce(p_parameters, '{}'::jsonb)) then
    raise exception 'report_unsafe_parameters: parameters failed structural validation'
      using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'report_generation',
    jsonb_build_object('report_type_code', p_report_type_code, 'parameters', coalesce(p_parameters, '{}'::jsonb)),
    0, null, 3, p_actor_auth_user_id, p_actor_label
  );

  insert into app.report_runs (
    tenant_id, report_type_code, run_type, status, parameters, job_id,
    requested_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_report_type_code, 'export', 'queued', coalesce(p_parameters, '{}'::jsonb), v_job.job_id,
    p_actor_auth_user_id, p_actor_label
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
  'COM-159: COM:Export-gated (Prompt 159 §26). Enqueues a real report_generation job via PLT-132''s own app.enqueue_job (never a bespoke queue) and records the linking app.report_runs row at status=queued. No live worker advances it further in this environment -- disclosed in this migration''s header, the same NOT_RUN condition every job type PLT-132 added already carries.';

alter table app.report_runs enable row level security;

-- Tenant-wide visibility (mirrors app.margin_rule_versions/app.accounts' own "tenant-
-- wide reference/policy data" precedent) -- who ran which report, when, is management
-- visibility, not per-owner private data.
create policy report_runs_select_scoped on app.report_runs
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant usage on schema app to authenticated;

grant select on app.report_types to authenticated, service_role;
grant insert, update, delete on app.report_types to service_role;

grant select on app.report_runs to authenticated, service_role;
grant insert, update, delete on app.report_runs to service_role;

grant execute on function app.register_report_type(text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.retire_report_type(text, uuid, text) to authenticated, service_role;
grant execute on function app.record_report_run(uuid, text, jsonb, integer, text[], uuid, text) to authenticated, service_role;
grant execute on function app.enqueue_report_export(uuid, text, jsonb, uuid, text) to authenticated, service_role;
