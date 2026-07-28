-- Operations capability OPS-182 (Operations Dashboard, CG-S8-OPS-016)
-- Role-specific live Operations dashboard: shipment status, milestone SLA, exceptions,
-- ePOD completion, cost variance and billing readiness -- each sourced from its own
-- app.get_ops_dashboard_* RPC, the exact pattern `COM-158`'s own Commercial Dashboard
-- already established and this migration deliberately mirrors rather than reinvents.
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint):
--
-- * **No new table, no duplicate analytics store** (Prompt 182 §13). Every read below
--   composes only already-`VERIFIED` tables: `app.shipment_orders` (`OPS-169`),
--   `app.shipment_milestone_projections` (`OPS-173`), `app.operational_exceptions`
--   (`OPS-174`), `app.epod_captures` (`OPS-177`), `app.shipment_actual_costs`
--   (`OPS-178`) and `app.billing_readiness_evaluations` (`OPS-181`).
-- * **Every function is `security definer` with its own explicit, re-stated
--   `app.can_access_record(...)` row filter, not an invoker-mode read relying on base-
--   table RLS** -- the identical reasoning `COM-158`'s own header already proved
--   empirically (an invoker-mode dashboard function reproduces `permission denied for
--   table ...` even for a column only ever read inside a masking `CASE` branch).
-- * **`app.dashboard_scope_org_unit_ids`, already created at `COM-158`, is reused
--   directly** for the optional branch/department drill-down filter -- no duplicate
--   wrapper is created for Operations; it is a schema-wide utility, not a Commercial-
--   specific one, despite its originating checkpoint.
-- * **Cost variance is field-masked via `app.has_view_actual_cost` (`OPS-178`)** -- the
--   same gate `app.shipment_actual_costs_directory` already uses. A masked row returns
--   `null` for `avg_variance_pct` and `true` for `variance_masked`, never a zero, the
--   same "never fabricate a value that reads as a real zero" discipline `COM-158`'s own
--   margin/pipeline/forecast summaries already established. Only `is_current and
--   status = 'approved'` actual-cost rows with a non-null, non-zero
--   `estimated_amount` contribute -- a shipment with no estimate has nothing to
--   compare against and is simply absent from this summary, never a fabricated
--   0% variance.
-- * **Milestone SLA only considers shipments still in transit** (`status not in
--   ('closed', 'cancelled')`) -- a closed or cancelled shipment's own delay history is
--   no longer actionable queue noise for this live view; a shipment with no milestone
--   projection row at all (no event ever ingested) is its own explicit `no_projection`
--   bucket, never silently folded into `on_time`.
-- * **Exceptions/ePOD/cost-variance summaries only include the exact rows already
--   independently readable by the caller** -- each function re-joins back to
--   `app.shipment_orders` and re-states the identical `can_access_record` check that
--   shipment's own RLS policy uses, so a caller can never see an exception/ePOD/cost row
--   for a shipment outside their own record scope, even in aggregate.
-- * **Billing readiness summary reads the current evaluation only** (`is_current =
--   true`), scoped via `app.job_orders`' own `owner_user_id`/`org_unit_id` -- the same
--   record-scope columns `app.billing_readiness_evaluations`' own RLS policy (`OPS-181`)
--   already joins through.
-- * **No caching layer, no privileged-access audit trail** -- the same two disclosed
--   boundaries `COM-158`'s own header already established for the identical reasons
--   (live OLTP reads only; ordinary, proportionate-telemetry views, no per-read audit
--   row). Export is out of this checkpoint's scope (`OPS-183`, Operations Reports).
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
--   before its final grants, the standing per-migration convention since `PLT-118`.

-- 1. Shipment status summary: every non-terminal-and-terminal status bucketed as-is --
-- status itself is the meaningful grain here, not a derived aging bucket.
create function app.get_ops_dashboard_shipment_status(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (status text, shipment_count bigint)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select so.status, count(*) as shipment_count
  from app.shipment_orders so
  where so.tenant_id = p_tenant_id
    and (p_org_unit_id is null or so.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or so.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  group by so.status;
$$;

comment on function app.get_ops_dashboard_shipment_status is
  'OPS-182: Shipment Order count by its own canonical app.shipment_orders.status (OPS-170), row-filtered by the exact same app.can_access_record check that table''s own RLS policy uses.';

-- 2. Milestone SLA: in-transit shipments bucketed by app.shipment_milestone_projections'
-- own deterministic is_delayed flag (OPS-173); no projection row at all is its own bucket.
create function app.get_ops_dashboard_milestone_sla(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, shipment_count bigint)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    case
      when smp.shipment_order_id is null then 'no_projection'
      when smp.is_delayed then 'delayed'
      else 'on_time'
    end as bucket,
    count(*) as shipment_count
  from app.shipment_orders so
  left join app.shipment_milestone_projections smp on smp.shipment_order_id = so.id
  where so.tenant_id = p_tenant_id
    and so.status not in ('closed', 'cancelled')
    and (p_org_unit_id is null or so.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or so.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  group by 1;
$$;

comment on function app.get_ops_dashboard_milestone_sla is
  'OPS-182: in-transit (not closed/cancelled) Shipment Orders bucketed by app.shipment_milestone_projections.is_delayed (OPS-173''s own deterministic heuristic) -- a shipment with no projection row yet (no milestone event ever ingested) is its own explicit no_projection bucket, never silently counted as on_time.';

-- 3. Exception queue: active (unresolved) operational exceptions by severity.
create function app.get_ops_dashboard_exception_queue(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (severity text, exception_count bigint)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select oe.severity, count(*) as exception_count
  from app.operational_exceptions oe
  join app.shipment_orders so on so.id = oe.shipment_order_id
  where oe.tenant_id = p_tenant_id
    and oe.status not in ('resolved', 'closed')
    and (p_org_unit_id is null or so.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or so.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  group by oe.severity;
$$;

comment on function app.get_ops_dashboard_exception_queue is
  'OPS-182: active (status not in resolved/closed) app.operational_exceptions (OPS-174) by severity, row-filtered via its own Shipment Order''s app.can_access_record check -- never internal_notes/damage_loss_details/claim_amount, which this summary never selects at all.';

-- 4. ePOD completion: the latest version of every ePOD capture, by status.
create function app.get_ops_dashboard_epod_completion(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (status text, capture_count bigint)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select ec.status, count(*) as capture_count
  from app.epod_captures ec
  join app.shipment_orders so on so.id = ec.shipment_order_id
  where ec.tenant_id = p_tenant_id
    and ec.is_latest_version
    and (p_org_unit_id is null or so.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or so.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  group by ec.status;
$$;

comment on function app.get_ops_dashboard_epod_completion is
  'OPS-182: the latest version (is_latest_version, OPS-177) of every ePOD capture by status, row-filtered via its own Shipment Order''s app.can_access_record check -- never the evidence itself (receiver name, signature/photo file, geolocation), which this summary never selects at all.';

-- 5. Cost variance: approved actual-cost versions with an estimate, bucketed by
-- variance-vs-estimate, by currency (never a cross-currency sum). Masked entirely
-- (variance_masked=true, avg_variance_pct=null) without OPS:View cost.
create function app.get_ops_dashboard_cost_variance(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, currency text, shipment_count bigint, avg_variance_pct numeric, variance_masked boolean)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  with variances as (
    select
      sac.currency,
      round((sac.total_amount - sac.estimated_amount) / sac.estimated_amount * 100, 2) as variance_pct
    from app.shipment_actual_costs sac
    join app.shipment_orders so on so.id = sac.shipment_order_id
    where sac.tenant_id = p_tenant_id
      and sac.is_current
      and sac.status = 'approved'
      and sac.estimated_amount is not null
      and sac.estimated_amount <> 0
      and (p_org_unit_id is null or so.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
      and (p_owner_user_id is null or so.owner_user_id = p_owner_user_id)
      and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  )
  select
    case
      when v.variance_pct > 5 then 'over_budget'
      when v.variance_pct < -5 then 'under_budget'
      else 'on_budget'
    end as bucket,
    v.currency,
    count(*) as shipment_count,
    case when app.has_view_actual_cost(p_tenant_id, p_actor_auth_user_id) then round(avg(v.variance_pct), 2) else null end as avg_variance_pct,
    not app.has_view_actual_cost(p_tenant_id, p_actor_auth_user_id) as variance_masked
  from variances v
  group by 1, 2;
$$;

comment on function app.get_ops_dashboard_cost_variance is
  'OPS-182: approved (is_current, status=approved) actual-cost versions carrying a non-null/non-zero estimated_amount, bucketed by (total_amount - estimated_amount) / estimated_amount over/under 5%, by currency (never a cross-currency sum). avg_variance_pct is null (variance_masked=true) without OPS:View cost, the same app.has_view_actual_cost gate (OPS-178) app.shipment_actual_costs_directory already uses.';

-- 6. Billing readiness: the current evaluation per Job Order, by effective status.
create function app.get_ops_dashboard_billing_readiness(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, job_count bigint)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select bre.effective_status as bucket, count(*) as job_count
  from app.billing_readiness_evaluations bre
  join app.job_orders jo on jo.id = bre.job_order_id
  where bre.tenant_id = p_tenant_id
    and bre.is_current
    and (p_org_unit_id is null or jo.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or jo.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null)
  group by bre.effective_status;
$$;

comment on function app.get_ops_dashboard_billing_readiness is
  'OPS-182: the current (is_current=true) app.billing_readiness_evaluations (OPS-181) row per Job Order, by effective_status (the generated column -- ready while overridden, else the evidence-based result) -- row-filtered via app.job_orders'' own owner_user_id/org_unit_id, the same columns that table''s own RLS policy resolves to.';

revoke execute on all functions in schema app from public;

grant execute on function app.get_ops_dashboard_shipment_status(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_milestone_sla(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_exception_queue(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_epod_completion(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_cost_variance(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_billing_readiness(uuid, uuid, uuid, uuid) to authenticated, service_role;
