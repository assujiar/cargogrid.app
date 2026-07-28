-- Operations capability OPS-183 (Operations Reports, CG-S8-OPS-017)
-- Governed Operations reports -- a permissioned, audited, exportable rendering of
-- metrics OPS-182's own dashboard already proved correct and access-controlled, never
-- a second, ungoverned analytics engine (Prompt 183 §24: "one shared multi-tenant
-- codebase"). Mirrors `COM-159`'s own Commercial Reports precedent exactly, and
-- deliberately reuses its own generic infrastructure rather than duplicating it.
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint):
--
-- * **Every report reuses an OPS-182 `app.get_ops_dashboard_*` function as its one
--   query engine, verbatim.** `app.report_types.source_function` names it directly.
--   This migration adds no new aggregation SQL at all -- reports are a governance/
--   audit/export layer over already-`VERIFIED` reads, not a duplicate. Of the seven
--   report subjects Prompt 183 §4 names (aging, on-time milestones, exceptions, ePOD
--   turnaround, actual-cost variance, profitability, billing readiness), the six this
--   checkpoint's own dashboard already computes are implemented; profitability has no
--   existing governed *summary* query to reuse (`OPS-179`'s own
--   `app.job_profitability_directory` is a per-Job-Order detail read, not an
--   aggregate the dashboard ever computed) and is a disclosed, out-of-scope gap here --
--   the same class of gap `COM-159`'s own header already disclosed for
--   conversion/costing/pricing.
-- * **`app.report_types`/`app.report_runs`/`app.record_report_run` are reused directly
--   from `COM-159` -- no duplicate table, no duplicate bookkeeping function.** These
--   were already generic, schema-wide infrastructure despite their originating
--   checkpoint (the same "reuse a prior checkpoint's own generic utility, don't fork
--   it" precedent `OPS-182` already established for `app.dashboard_scope_org_unit_ids`).
--   `app.register_report_type` (Supreme-only, idempotent) registers this checkpoint's
--   own six codes into the exact same catalogue Commercial's seven already occupy --
--   report codes are globally unique by design (`code` is the table's own primary
--   key), so no per-module namespacing is needed. `app.record_report_run` performs no
--   module-specific check at all (only tenant membership) -- the same "ordinary view,
--   no extra gate beyond what the underlying dashboard RPC/RLS already enforces"
--   posture already applies unchanged to an Operations preview.
-- * **Export is the one genuinely new function this migration adds**:
--   `app.enqueue_ops_report_export`, gated on `OPS:Export` (already seeded in the
--   original `PLT-111` permission catalogue, `category='standard'`, `protected=false`,
--   previously unused by any Operations capability until now -- the same "reuse an
--   already-seeded, previously-idle permission action" choice `COM-159` made for
--   `COM:Export`). It cannot simply call `COM-159`'s own `app.enqueue_report_export`
--   because that function hard-codes a `COM:Export` check; this is a distinct,
--   parallel entry point for the `OPS` module, not a modification of `COM-159`'s own
--   immutable migration. Both functions enqueue the identical `report_generation` job
--   type via `PLT-132`'s own generic `app.enqueue_job` and insert into the identical
--   shared `app.report_runs` table.
-- * **No live worker processes a `report_generation` job anywhere in this repository**
--   -- the same disclosed `NOT_RUN` condition `COM-159`'s own migration already
--   carried, unchanged by this checkpoint. An Operations export therefore reaches
--   `status='queued'` and stops there in this environment.
-- * **Formula-injection protection reuses the existing, already unit-tested
--   `server/policies/csv-export-sanitize.ts` directly** (`COM-159`) -- a generic,
--   report-subject-agnostic cell sanitizer, not something to duplicate per module.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

insert into app.report_types (code, name, description, source_function, registered_by) values
  ('shipment_status_summary', 'Shipment Status Summary', 'Shipment Order count by canonical lifecycle status.', 'get_ops_dashboard_shipment_status', 'system'),
  ('milestone_sla_summary', 'Milestone SLA', 'In-transit Shipment Order count bucketed by on-time/delayed/no-projection.', 'get_ops_dashboard_milestone_sla', 'system'),
  ('exception_queue_summary', 'Exception Queue', 'Active operational exception count by severity.', 'get_ops_dashboard_exception_queue', 'system'),
  ('epod_completion_summary', 'ePOD Completion', 'Latest ePOD capture count by status.', 'get_ops_dashboard_epod_completion', 'system'),
  ('cost_variance_summary', 'Actual Cost Variance', 'Approved actual-cost versions bucketed by variance-vs-estimate, by currency.', 'get_ops_dashboard_cost_variance', 'system'),
  ('billing_readiness_summary', 'Billing Readiness', 'Current billing-readiness evaluation count by effective status.', 'get_ops_dashboard_billing_readiness', 'system');

-- The one genuinely new function -- OPS:Export-gated export enqueue, mirroring
-- COM-159's own app.enqueue_report_export body exactly except for the module code the
-- RBAC check evaluates. Reuses the identical app.report_runs table and app.enqueue_job
-- (PLT-132) queue COM-159 already established -- never a bespoke queue or a duplicate
-- bookkeeping table.
create function app.enqueue_ops_report_export(
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

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Export');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Export (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
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
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_ops_report_export',
    'app.report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('report_type_code', p_report_type_code, 'job_id', v_job.job_id)
  );

  return v_run;
end;
$$;

comment on function app.enqueue_ops_report_export is
  'OPS-183: OPS:Export-gated (Prompt 183 §26). A parallel entry point to COM-159''s own app.enqueue_report_export -- identical body shape, distinct module-code RBAC check -- since that function hard-codes COM:Export and its migration is immutable. Enqueues a real report_generation job via PLT-132''s own app.enqueue_job (never a bespoke queue) and records the linking app.report_runs row (the same shared table COM-159 already created) at status=queued. No live worker advances it further in this environment -- disclosed in COM-159''s own migration header, unchanged by this checkpoint.';

revoke execute on all functions in schema app from public;

grant execute on function app.enqueue_ops_report_export(uuid, text, jsonb, uuid, text) to authenticated, service_role;
