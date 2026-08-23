-- Operations capability OPS-179 (Basic Job Profitability, CG-S8-OPS-013)
-- Deterministic, versioned operational-margin snapshot from the Job Order's own pinned
-- Commercial revenue (`app.job_orders.revenue_snapshot`) and every approved Shipment
-- Order actual-cost version (`OPS-178`) -- an operational view, never accounting P&L
-- (Prompt 179 §4/§24).
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **One new permission action.** The fixed, pre-approved 19-action `PLT-111`
--   vocabulary includes `View margin` (already registered for the `COM` module at
--   `COM-156`) -- this migration registers the identical action paired with the `OPS`
--   module (`OPS:View margin`, a distinct catalogue row, never a collision, keyed on
--   `(resource_module_code, action)`), the same pattern `OPS-174` already used to
--   register `OPS:View cost` from the same fixed vocabulary. Reading or triggering a
--   recalculation of this snapshot requires `OPS:View margin` -- deliberately its own
--   bit, not reused from `OPS-178`'s own `OPS:View cost`, since an actor may legitimately
--   see one without the other (the same orthogonality Commercial's own
--   `COM:View cost`/`COM:View margin` split already established).
-- * **Revenue is read verbatim from the Job Order's own already-pinned snapshot,
--   never recomputed.** `docs/build-log/phase-03/00_OPERATIONS_WBS.md` §3 disclosed
--   `app.job_orders.revenue_snapshot` as exactly the governed revenue basis this
--   capability would read -- `revenue_snapshot ->> 'totalAmount'`/`'currency'` is the
--   Commercial-accepted sell price, read once per calculation, never re-derived from
--   quotation lines this capability has no governed right to re-open.
-- * **Cost is the sum of every currently-approved `OPS-178` actual-cost version**
--   across every Shipment Order belonging to the Job Order -- `is_current = true and
--   status = 'approved'` only; a draft/submitted/rejected version never contributes.
--   No FX conversion is performed (§25: "any FX use requires explicit source/date/
--   version; otherwise cross-currency result is unavailable") -- a currency mismatch
--   between the revenue snapshot and any contributing cost version (or between cost
--   versions themselves) makes the whole snapshot `unavailable` with a named
--   `blocked_reason`, never a silently-wrong cross-currency subtraction.
-- * **Versioned snapshot, historical versions remain linked, never rewritten in
--   place** (§24): `app.job_profitability_snapshots` is `is_current`-exclusive
--   (partial unique index); the first calculation for a job needs no reason, but every
--   subsequent recalculation while a current snapshot already exists requires a
--   non-empty `recalculation_reason` -- the same "adjustment preserves lineage"
--   discipline `OPS-178`'s own `app.create_actual_cost_adjustment` already established.
-- * **Explainability reuses `source_cost_version_ids`, no second read path is
--   invented.** The snapshot row itself carries the exact `app.shipment_actual_costs.id`
--   array it summed -- already independently readable (RLS-scoped, record-scoped) by
--   any caller who can see this snapshot in the first place, so no bespoke "explain"
--   RPC duplicates that existing, already-governed read surface.
-- * **This is operational profitability, not accounting P&L** (§24): no GL/subledger/
--   recognized-revenue table is touched or created; `margin_amount`/`margin_percent`
--   are recorded, non-authoritative-for-accounting operational figures, the same
--   disclosed boundary `OPS-174`'s `claim_amount`/`OPS-178`'s `total_amount` already
--   established for their own domains.
-- * Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
--   explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
--   its final grants, the standing per-migration convention since PLT-118.

insert into app.permissions (action, resource_module_code, category, protected)
values ('View margin', 'OPS', 'sensitive', true);

create function app.has_view_job_margin(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'OPS', 'View margin')).allowed;
$$;

comment on function app.has_view_job_margin is
  'OPS-179: thin wrapper over app.evaluate_permission(..., ''OPS'', ''View margin'') -- the same fixed 19-action PLT-111 vocabulary COM-156''s own COM:View margin already draws from, registered here for the OPS module.';

create table app.job_profitability_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  job_order_id uuid not null references app.job_orders (id),
  version_number integer not null default 1,
  is_current boolean not null default true,
  status text not null,
  blocked_reason text,
  revenue_currency text,
  revenue_amount numeric(14, 2),
  cost_currency text,
  cost_amount numeric(14, 2),
  margin_amount numeric(14, 2),
  margin_percent numeric(9, 4),
  source_cost_version_ids uuid[] not null default '{}',
  recalculation_reason text,
  calculated_by_auth_user_id uuid not null,
  calculated_at timestamptz not null default now(),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint job_profitability_snapshots_status_check check (status in ('calculated', 'unavailable')),
  constraint job_profitability_snapshots_blocked_reason_check check (status <> 'unavailable' or (blocked_reason is not null and length(trim(blocked_reason)) > 0)),
  constraint job_profitability_snapshots_version_number_check check (version_number > 0)
);

comment on table app.job_profitability_snapshots is
  'OPS-179: one versioned, deterministic operational-margin snapshot per Job Order (is_current exclusive via partial unique index). status=unavailable (with a named blocked_reason) whenever no approved cost exists or currencies do not reconcile -- never a fabricated zero/guessed value. source_cost_version_ids names the exact app.shipment_actual_costs rows summed, the capability''s own explainability seam (already independently readable, no second read path invented).';

create unique index job_profitability_snapshots_one_current_idx on app.job_profitability_snapshots (job_order_id) where is_current;
create index job_profitability_snapshots_tenant_job_idx on app.job_profitability_snapshots (tenant_id, job_order_id);

create function app.touch_job_profitability_snapshots_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger job_profitability_snapshots_touch_row
  before update on app.job_profitability_snapshots
  for each row
  execute function app.touch_job_profitability_snapshots_row();

create function app.calculate_job_profitability(
  p_job_order_id uuid,
  p_recalculation_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_profitability_snapshots
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.job_orders;
  v_decision app.rbac_decision;
  v_existing_current app.job_profitability_snapshots;
  v_revenue_currency text;
  v_revenue_amount numeric(14, 2);
  v_cost_currency_count integer;
  v_cost_currency text;
  v_cost_amount numeric(14, 2);
  v_cost_count integer;
  v_cost_version_ids uuid[];
  v_status text;
  v_blocked_reason text;
  v_margin_amount numeric(14, 2);
  v_margin_percent numeric(9, 4);
  v_new_version integer;
  v_snapshot app.job_profitability_snapshots;
begin
  select * into v_job from app.job_orders jo where jo.id = p_job_order_id;
  if not found then
    raise exception 'job_order_not_found: %', p_job_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_job_margin(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View margin for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_job.tenant_id, v_job.owner_user_id, app.lead_record_scope_org_unit_ids(v_job.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order %', p_actor_auth_user_id, p_job_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_current from app.job_profitability_snapshots where job_order_id = p_job_order_id and is_current;
  if found and (p_recalculation_reason is null or length(trim(p_recalculation_reason)) = 0) then
    raise exception 'job_profitability_recalculation_reason_required: a reason is required to recalculate an existing profitability snapshot' using errcode = 'check_violation';
  end if;

  v_revenue_currency := v_job.revenue_snapshot ->> 'currency';
  v_revenue_amount := (v_job.revenue_snapshot ->> 'totalAmount')::numeric(14, 2);

  select count(distinct sac.currency), count(*), coalesce(sum(sac.total_amount), 0), coalesce(array_agg(sac.id), '{}'::uuid[])
  into v_cost_currency_count, v_cost_count, v_cost_amount, v_cost_version_ids
  from app.shipment_actual_costs sac
  join app.shipment_orders so on so.id = sac.shipment_order_id
  where so.job_order_id = p_job_order_id and sac.is_current and sac.status = 'approved';

  if v_cost_count = 0 then
    v_status := 'unavailable';
    v_blocked_reason := 'no_approved_cost';
    v_cost_currency := null;
    v_cost_amount := null;
    v_margin_amount := null;
    v_margin_percent := null;
  elsif v_cost_currency_count > 1 or (select sac.currency from app.shipment_actual_costs sac where sac.id = v_cost_version_ids[1]) <> v_revenue_currency then
    v_status := 'unavailable';
    v_blocked_reason := 'mixed_currency';
    v_cost_currency := null;
    v_cost_amount := null;
    v_margin_amount := null;
    v_margin_percent := null;
  else
    v_status := 'calculated';
    v_blocked_reason := null;
    v_cost_currency := v_revenue_currency;
    v_margin_amount := v_revenue_amount - v_cost_amount;
    v_margin_percent := case when v_revenue_amount <> 0 then round((v_margin_amount / v_revenue_amount) * 100, 4) else null end;
  end if;

  v_new_version := coalesce(v_existing_current.version_number, 0) + 1;
  if found then
    update app.job_profitability_snapshots set is_current = false where id = v_existing_current.id;
  end if;

  insert into app.job_profitability_snapshots (
    tenant_id, job_order_id, version_number, is_current, status, blocked_reason,
    revenue_currency, revenue_amount, cost_currency, cost_amount, margin_amount, margin_percent,
    source_cost_version_ids, recalculation_reason, calculated_by_auth_user_id, created_by
  ) values (
    v_job.tenant_id, p_job_order_id, v_new_version, true, v_status, v_blocked_reason,
    v_revenue_currency, v_revenue_amount, v_cost_currency, v_cost_amount, v_margin_amount, v_margin_percent,
    v_cost_version_ids, p_recalculation_reason, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_snapshot;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_job_profitability',
    'app.job_profitability_snapshots', v_snapshot.id, 'success', p_recalculation_reason, null, to_jsonb(v_snapshot)
  );

  return v_snapshot;
end;
$$;

alter table app.job_profitability_snapshots enable row level security;

create policy job_profitability_snapshots_select_scoped on app.job_profitability_snapshots
  for select to authenticated
  using (
    exists (
      select 1 from app.job_orders jo
      where jo.id = job_profitability_snapshots.job_order_id
        and app.can_access_record((select auth.uid()), jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null)
    )
  );

-- Field-masked projection -- revenue/cost/margin amounts nulled out for a
-- record-scoped actor lacking OPS:View margin (status/version/blocked_reason remain
-- visible, matching app.shipment_actual_costs_directory's own precedent).
create view app.job_profitability_directory
as
select
  jps.id, jps.tenant_id, jps.job_order_id, jps.version_number, jps.is_current, jps.status, jps.blocked_reason,
  case when app.has_view_job_margin(jps.tenant_id) then jps.revenue_currency else null end as revenue_currency,
  case when app.has_view_job_margin(jps.tenant_id) then jps.revenue_amount else null end as revenue_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.cost_currency else null end as cost_currency,
  case when app.has_view_job_margin(jps.tenant_id) then jps.cost_amount else null end as cost_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.margin_amount else null end as margin_amount,
  case when app.has_view_job_margin(jps.tenant_id) then jps.margin_percent else null end as margin_percent,
  case when app.has_view_job_margin(jps.tenant_id) then jps.source_cost_version_ids else '{}'::uuid[] end as source_cost_version_ids,
  not app.has_view_job_margin(jps.tenant_id) as margin_masked,
  jps.recalculation_reason, jps.calculated_by_auth_user_id, jps.calculated_at, jps.record_version, jps.created_by, jps.created_at, jps.updated_at
from app.job_profitability_snapshots jps
join app.job_orders jo on jo.id = jps.job_order_id
where app.can_access_record(auth.uid(), jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null);

comment on view app.job_profitability_directory is
  'OPS-179: field-masked projection of app.job_profitability_snapshots -- revenue/cost/margin amounts and source_cost_version_ids nulled/emptied (margin_masked=true) without OPS:View margin.';

revoke execute on all functions in schema app from public;

grant select on app.job_profitability_snapshots to authenticated, service_role;
grant insert, update, delete on app.job_profitability_snapshots to service_role;
grant select on app.job_profitability_directory to authenticated, service_role;

grant execute on function app.has_view_job_margin(uuid, uuid) to authenticated, service_role;
grant execute on function app.calculate_job_profitability(uuid, text, uuid, text) to authenticated, service_role;
