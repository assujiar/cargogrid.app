-- Commercial capability COM-158 (Commercial Dashboard, CG-S7-COM-017)
-- Role-specific live Commercial dashboard: lead aging, activity queue, pipeline,
-- quote SLA, margin, win/loss and forecast, with permission-safe drill-down.
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint):
--
-- * **No new table, no duplicate analytics store** (Prompt 158 §13). Every read below
--   composes only already-`VERIFIED` tables: `app.leads` (`COM-143`), `app.activities`
--   (`COM-145`), `app.opportunities`/`app.opportunity_stage_history` (`COM-147`),
--   `app.quotations` (`COM-151`/`152`/`153`/`154`) and `app.margin_calculations`
--   (`COM-150`).
-- * **Every function is `security definer` with its own explicit, re-stated
--   `app.can_access_record(...)` row filter, not an invoker-mode read relying on base-table
--   RLS.** This is not a stylistic choice -- an invoker-mode attempt was tried first and
--   failed exactly the way `COM-147`'s own build log already documents for `app.
--   opportunities_directory` (its header comment, this migration's own sibling): Postgres
--   checks column privileges against the *invoker* for every column a query references,
--   even one only ever read inside a masking `CASE` branch that ends up null, or one simply
--   never included in `authenticated`'s column-level grant list at all (`app.quotations.
--   customer_decision`/`is_current`/`approval_status`, each added by a later migration's own
--   narrower, purpose-specific column grant, not a blanket one). An invoker-mode function
--   reproduced the identical `permission denied for table opportunities` this repository
--   already hit once -- proven empirically this checkpoint, not assumed. Running as
--   `security definer` is exactly what lets each function read those columns internally
--   while still deciding, per row, what to reveal -- the same trade `app.opportunities_
--   directory`/`app.quotations_directory`/`app.margin_calculations_directory` already made,
--   which is why each function below re-states the identical `app.can_access_record(...)`
--   check those directory views use, rather than trusting RLS to have already run.
-- * **Field-level masking reuses the two already-`VERIFIED` gates directly**: monetary
--   figures on opportunities/quotations/forecast use `app.has_view_selling_price`
--   (`COM-147`); margin figures use `app.has_view_cost` (`COM-149`, the same gate
--   `app.margin_calculations_directory` already uses for `margin_amount`/`margin_pct`).
--   No new permission action is introduced. A masked aggregate returns `null` for the
--   amount column and `true` for its own `*_masked` flag -- never a zero, which would be
--   indistinguishable from a real zero-value result.
-- * **Mixed-currency ambiguity (Prompt 158 §23) is resolved structurally, not by
--   invented FX**: every amount-bearing summary groups by `currency` and returns one row
--   per currency actually present -- no cross-currency sum is ever computed.
-- * **`app.dashboard_scope_org_unit_ids` is a narrow, `authenticated`-facing wrapper**
--   around `PLT-109`'s own `service_role`-only `app.org_unit_descendant_ids`, mirroring
--   `COM-143`'s own `app.lead_record_scope_org_unit_ids` wrapper of `app.org_unit_
--   ancestor_ids` -- the drill-down "this branch and everything under it" filter a
--   manager-level dashboard view needs, without widening the original function's grant.
--   It is an additional, optional narrowing filter layered on top of each function's own
--   `can_access_record` check, never a substitute for it: passing an org unit the caller
--   cannot otherwise see simply yields zero rows, not an access grant.
-- * **No caching layer is introduced this checkpoint** -- every query is live against the
--   authoritative transactional tables (Prompt 158 §13's own "no duplicate analytics
--   store"). Query-budget/timeout enforcement and any future cache/staleness policy are
--   the calling service layer's responsibility (`server/queries/dashboard.ts`), the same
--   split already used by every other Commercial read path.
-- * **No privileged dashboard/export access exists to audit at this checkpoint**
--   (Prompt 158 §18) -- these are ordinary, scoped read functions, proportionate security
--   telemetry only (no per-read `app.audit_logs` entry, the same "ordinary views" carve-out
--   every prior read-only capability in this repository already relies on). Export is
--   explicitly `COM-159`'s own scope (Commercial Reports), not built here.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`.

create function app.dashboard_scope_org_unit_ids(p_org_unit_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select p_org_unit_id
  union
  select app.org_unit_descendant_ids(p_org_unit_id);
$$;

comment on function app.dashboard_scope_org_unit_ids is
  'COM-158: wraps PLT-109''s service_role-only app.org_unit_descendant_ids so authenticated dashboard callers can narrow a summary to one branch/department and everything beneath it, without widening that function''s original grant. app.org_units.path excludes self (PLT-109''s own documented shape), so app.org_unit_descendant_ids alone returns strict descendants only -- p_org_unit_id itself is unioned in explicitly, otherwise a filter by a leaf department (no descendants of its own) would wrongly exclude every record assigned directly to that department. Purely an additional filter -- never a substitute for each function''s own can_access_record check.';

-- 1. Lead aging: open (not yet qualified/disqualified/merged/converted) leads bucketed by
-- time since last activity.
create function app.get_dashboard_lead_aging(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, lead_count bigint)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    case
      when now() - l.last_activity_at < interval '3 days' then '0_2_days'
      when now() - l.last_activity_at < interval '8 days' then '3_7_days'
      when now() - l.last_activity_at < interval '15 days' then '8_14_days'
      else '15_plus_days'
    end as bucket,
    count(*) as lead_count
  from app.leads l
  where l.tenant_id = p_tenant_id
    and l.status in ('new', 'contacted')
    and (p_org_unit_id is null or l.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or l.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, l.tenant_id, l.owner_user_id, app.lead_record_scope_org_unit_ids(l.org_unit_id), null)
  group by 1;
$$;

comment on function app.get_dashboard_lead_aging is
  'COM-158: open-lead count bucketed by age-since-last-activity, row-filtered by the exact same app.can_access_record check app.leads'' own RLS policy (COM-143) uses. Only status in (new, contacted) counts as open -- qualified/disqualified/merged/converted leads have already exited the aging queue by definition.';

-- 2. Activity queue: scheduled activities bucketed by due-date urgency.
create function app.get_dashboard_activity_queue(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, activity_count bigint)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    case
      when a.due_at is null then 'no_due_date'
      when a.due_at < now() then 'overdue'
      when a.due_at::date = current_date then 'due_today'
      else 'upcoming_7_days'
    end as bucket,
    count(*) as activity_count
  from app.activities a
  where a.tenant_id = p_tenant_id
    and a.status = 'scheduled'
    and (p_org_unit_id is null or a.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or a.owner_user_id = p_owner_user_id)
    and (a.due_at is null or a.due_at <= now() + interval '7 days')
    and app.can_access_record(p_actor_auth_user_id, a.tenant_id, a.owner_user_id, app.lead_record_scope_org_unit_ids(a.org_unit_id), null)
  group by 1;
$$;

comment on function app.get_dashboard_activity_queue is
  'COM-158: open activity queue bucketed by due-date urgency, row-filtered by the exact same app.can_access_record check app.activities'' own RLS policy (COM-145) uses. "upcoming_7_days" is capped at 7 days out by design -- an activity due further out is not yet actionable queue noise; the where clause''s own trailing predicate keeps it out of every bucket rather than inventing a fifth, unbounded one.';

-- 3. Pipeline summary: open opportunities by stage, one row per (stage, currency) to
-- avoid any cross-currency sum. value/currency masked per app.has_view_selling_price.
create function app.get_dashboard_pipeline_summary(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (stage text, currency text, opportunity_count bigint, value_amount_total numeric, value_masked boolean)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    o.stage,
    o.value_currency as currency,
    count(*) as opportunity_count,
    case when app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id) then round(sum(coalesce(o.value_amount, 0)), 2) else null end as value_amount_total,
    not app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id) as value_masked
  from app.opportunities o
  where o.tenant_id = p_tenant_id
    and o.stage not in ('won', 'lost')
    and (p_org_unit_id is null or o.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or o.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, o.tenant_id, o.owner_user_id, app.lead_record_scope_org_unit_ids(o.org_unit_id), null)
  group by o.stage, o.value_currency;
$$;

comment on function app.get_dashboard_pipeline_summary is
  'COM-158: open (not won/lost -- those belong to app.get_dashboard_win_loss_summary instead) opportunity count and total value per (stage, currency), row-filtered by the exact same app.can_access_record check app.opportunities_directory (COM-147) uses. Grouped by currency, never summed across currencies, so a mixed-currency pipeline is always an explicit multi-row result rather than an invented conversion. value_amount_total is null (value_masked=true) for any caller lacking COM:View selling price; opportunity_count itself is never masked.';

-- 4. Quote SLA: submitted quotations still awaiting internal approval or customer
-- decision, bucketed by turnaround/expiry risk. No amount column is exposed, so no
-- masking is needed, but approval_status/customer_decision/is_current are all outside
-- authenticated's own column-level grant on app.quotations (added piecemeal by COM-152/
-- 153/154, each scoped to its own new columns only) -- security definer is required to
-- read them at all, exactly like the amount-bearing functions below.
create function app.get_dashboard_quote_sla(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, quote_count bigint)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    case
      when q.approval_status = 'pending' then 'pending_approval'
      when q.validity_to < now() then 'expired_no_decision'
      when q.validity_to <= now() + interval '2 days' then 'expiring_soon'
      else 'awaiting_customer_decision'
    end as bucket,
    count(*) as quote_count
  from app.quotations q
  where q.tenant_id = p_tenant_id
    and q.status = 'submitted'
    and q.approval_status <> 'rejected'
    and q.customer_decision is null
    and q.is_current
    and (p_org_unit_id is null or q.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or q.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null)
  group by 1;
$$;

comment on function app.get_dashboard_quote_sla is
  'COM-158: the open (not yet customer-decided, not internally rejected) submitted-quotation queue, bucketed by turnaround/expiry risk, row-filtered by the exact same app.can_access_record check app.quotations_directory (COM-151) uses. is_current=true (COM-152) excludes superseded versions -- only the live version of a quote counts toward SLA exposure.';

-- 5. Margin summary: margin calculations by currency over an optional period. Margin
-- figures masked per app.has_view_cost.
create function app.get_dashboard_margin_summary(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_period_start date default null,
  p_period_end date default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (currency text, calculation_count bigint, avg_margin_pct numeric, total_margin_amount numeric, margin_masked boolean)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    m.sell_currency as currency,
    count(*) as calculation_count,
    case when app.has_view_cost(p_tenant_id, p_actor_auth_user_id) then round(avg(m.margin_pct), 2) else null end as avg_margin_pct,
    case when app.has_view_cost(p_tenant_id, p_actor_auth_user_id) then round(sum(m.margin_amount), 2) else null end as total_margin_amount,
    not app.has_view_cost(p_tenant_id, p_actor_auth_user_id) as margin_masked
  from app.margin_calculations m
  where m.tenant_id = p_tenant_id
    and m.is_current
    and (p_org_unit_id is null or m.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or m.owner_user_id = p_owner_user_id)
    and (p_period_start is null or m.created_at::date >= p_period_start)
    and (p_period_end is null or m.created_at::date <= p_period_end)
    and app.can_access_record(p_actor_auth_user_id, m.tenant_id, m.owner_user_id, app.lead_record_scope_org_unit_ids(m.org_unit_id), null)
  group by m.sell_currency;
$$;

comment on function app.get_dashboard_margin_summary is
  'COM-158: current (is_current=true, COM-150) margin calculations by currency over an optional [p_period_start, p_period_end] window, row-filtered by app.can_access_record against each calculation''s own owner_user_id/org_unit_id (the same columns app.margin_calculations_directory''s underlying costing_request join ultimately resolves to). avg_margin_pct/total_margin_amount are null (margin_masked=true) for any caller lacking COM:View cost -- the same gate app.margin_calculations_directory already uses, never a new permission.';

-- 6. Win/loss summary: opportunity stage transitions into won/lost within an optional
-- period, by currency. value/currency masked per app.has_view_selling_price.
create function app.get_dashboard_win_loss_summary(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_period_start date default null,
  p_period_end date default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (outcome text, currency text, opportunity_count bigint, value_amount_total numeric, value_masked boolean)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    h.to_stage as outcome,
    o.value_currency as currency,
    count(distinct h.opportunity_id) as opportunity_count,
    case when app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id) then round(sum(coalesce(o.value_amount, 0)), 2) else null end as value_amount_total,
    not app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id) as value_masked
  from app.opportunity_stage_history h
  join app.opportunities o on o.id = h.opportunity_id
  where h.tenant_id = p_tenant_id
    and h.to_stage in ('won', 'lost')
    and (p_org_unit_id is null or o.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or o.owner_user_id = p_owner_user_id)
    and (p_period_start is null or h.changed_at::date >= p_period_start)
    and (p_period_end is null or h.changed_at::date <= p_period_end)
    and app.can_access_record(p_actor_auth_user_id, o.tenant_id, o.owner_user_id, app.lead_record_scope_org_unit_ids(o.org_unit_id), null)
  group by h.to_stage, o.value_currency;
$$;

comment on function app.get_dashboard_win_loss_summary is
  'COM-158: won/lost opportunity count and value by currency, keyed off the actual stage-transition event (app.opportunity_stage_history, COM-147) rather than the opportunity''s own updated_at -- an opportunity edited after closing never shifts into or out of the requested period by accident. Row-filtered by the exact same app.can_access_record check app.opportunities_directory uses. Win rate is a client-side derived value (won / (won + lost)) from these two rows, never precomputed here, so a caller can bucket it however the UI needs.';

-- 7. Forecast summary: probability-weighted value of open (not won/lost) opportunities,
-- by currency. value masked per app.has_view_selling_price.
create function app.get_dashboard_forecast_summary(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (currency text, open_opportunity_count bigint, weighted_value_total numeric, value_masked boolean)
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    o.value_currency as currency,
    count(*) as open_opportunity_count,
    case when app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id) then round(sum(coalesce(o.value_amount, 0) * o.probability / 100.0), 2) else null end as weighted_value_total,
    not app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id) as value_masked
  from app.opportunities o
  where o.tenant_id = p_tenant_id
    and o.stage not in ('won', 'lost')
    and (p_org_unit_id is null or o.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or o.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, o.tenant_id, o.owner_user_id, app.lead_record_scope_org_unit_ids(o.org_unit_id), null)
  group by o.value_currency;
$$;

comment on function app.get_dashboard_forecast_summary is
  'COM-158: probability-weighted pipeline value (value_amount * probability / 100) for open opportunities, by currency, row-filtered by the exact same app.can_access_record check app.opportunities_directory uses. This is the same probability field app.opportunities already carries (COM-147) -- no separate forecast model is introduced. weighted_value_total is null (value_masked=true) for any caller lacking COM:View selling price.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.dashboard_scope_org_unit_ids(uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_lead_aging(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_activity_queue(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_pipeline_summary(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_quote_sla(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_margin_summary(uuid, uuid, uuid, date, date, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_win_loss_summary(uuid, uuid, uuid, date, date, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_forecast_summary(uuid, uuid, uuid, uuid) to authenticated, service_role;
