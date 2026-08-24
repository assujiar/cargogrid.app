-- HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit, `CG-S15-HDN-005`) — closes
-- `HDN-BLK-012`/`ISS-2026-165`, carried forward from `HDN-372`'s own Tier C review.
--
-- The 13 dashboard-read functions below (`app.get_ops_dashboard_*` ×6,
-- `app.get_dashboard_*` ×7) share the identical actor-identity-forgery shape
-- `HDN-BLK-011` fixed at `20260810000000_harden_tenant_isolation_actor_identity_gaps.sql`
-- / `20260810100000_..._round2.sql`: each is `SECURITY DEFINER`, granted `EXECUTE` to
-- `authenticated`, and takes `p_actor_auth_user_id uuid default auth.uid()` — but the
-- claimed actor was never cross-checked against the real session identity before being
-- passed into `app.can_access_record`/`app.has_view_actual_cost`/`app.has_view_cost`/
-- `app.has_view_selling_price`, all of which validate the CLAIMED actor and never the
-- caller. A forged `p_actor_auth_user_id` therefore let any authenticated session read
-- another identity's own record-scoped dashboard aggregates (and, for the cost/margin/
-- selling-price-masked ones, that identity's own field-masking entitlement) — the
-- unmasking half of the class is a genuine escalation, not merely a scope widening: a
-- caller with no `OPS:View cost`/`COM:View cost`/`COM:View selling price` grant of their
-- own could see unmasked `avg_variance_pct`/`avg_margin_pct`/`total_margin_amount`/
-- `value_amount_total`/`weighted_value_total` simply by forging an actor UUID known to
-- hold that grant.
--
-- Unlike the `ATW-023`/`ATW-016` families `HDN-BLK-011` closed at one root each, these 13
-- have no shared root — each is an independent `LANGUAGE sql` entry point — so each is
-- fixed individually here, converting `LANGUAGE sql` → `LANGUAGE plpgsql` to carry
-- `perform app.assert_actor_is_session_identity(p_actor_auth_user_id);` as the first
-- statement, identical to `HDN-BLK-011`'s own fix pattern
-- (`docs/build-log/full-system-hardening/HDN-372.md` §5.5's own reference citation).
--
-- Full disposition: `docs/build-log/full-system-hardening/HDN-373.md` §5.

create or replace function app.get_ops_dashboard_shipment_status(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (status text, shipment_count bigint)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select so.status, count(*) as shipment_count
  from app.shipment_orders so
  where so.tenant_id = p_tenant_id
    and (p_org_unit_id is null or so.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or so.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  group by so.status;
end;
$$;

create or replace function app.get_ops_dashboard_milestone_sla(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, shipment_count bigint)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
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
end;
$$;

create or replace function app.get_ops_dashboard_exception_queue(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (severity text, exception_count bigint)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select oe.severity, count(*) as exception_count
  from app.operational_exceptions oe
  join app.shipment_orders so on so.id = oe.shipment_order_id
  where oe.tenant_id = p_tenant_id
    and oe.status not in ('resolved', 'closed')
    and (p_org_unit_id is null or so.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or so.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  group by oe.severity;
end;
$$;

create or replace function app.get_ops_dashboard_epod_completion(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (status text, capture_count bigint)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select ec.status, count(*) as capture_count
  from app.epod_captures ec
  join app.shipment_orders so on so.id = ec.shipment_order_id
  where ec.tenant_id = p_tenant_id
    and ec.is_latest_version
    and (p_org_unit_id is null or so.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or so.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  group by ec.status;
end;
$$;

create or replace function app.get_ops_dashboard_cost_variance(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, currency text, shipment_count bigint, avg_variance_pct numeric, variance_masked boolean)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
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
end;
$$;

create or replace function app.get_ops_dashboard_billing_readiness(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, job_count bigint)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
  select bre.effective_status as bucket, count(*) as job_count
  from app.billing_readiness_evaluations bre
  join app.job_orders jo on jo.id = bre.job_order_id
  where bre.tenant_id = p_tenant_id
    and bre.is_current
    and (p_org_unit_id is null or jo.org_unit_id in (select app.dashboard_scope_org_unit_ids(p_org_unit_id)))
    and (p_owner_user_id is null or jo.owner_user_id = p_owner_user_id)
    and app.can_access_record(p_actor_auth_user_id, jo.tenant_id, jo.owner_user_id, app.lead_record_scope_org_unit_ids(jo.org_unit_id), null)
  group by bre.effective_status;
end;
$$;

create or replace function app.get_dashboard_lead_aging(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, lead_count bigint)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
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
end;
$$;

create or replace function app.get_dashboard_activity_queue(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, activity_count bigint)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
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
end;
$$;

create or replace function app.get_dashboard_pipeline_summary(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (stage text, currency text, opportunity_count bigint, value_amount_total numeric, value_masked boolean)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
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
end;
$$;

create or replace function app.get_dashboard_quote_sla(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (bucket text, quote_count bigint)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
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
end;
$$;

create or replace function app.get_dashboard_margin_summary(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_period_start date default null,
  p_period_end date default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (currency text, calculation_count bigint, avg_margin_pct numeric, total_margin_amount numeric, margin_masked boolean)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
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
end;
$$;

create or replace function app.get_dashboard_win_loss_summary(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_period_start date default null,
  p_period_end date default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (outcome text, currency text, opportunity_count bigint, value_amount_total numeric, value_masked boolean)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
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
end;
$$;

create or replace function app.get_dashboard_forecast_summary(
  p_tenant_id uuid,
  p_org_unit_id uuid default null,
  p_owner_user_id uuid default null,
  p_actor_auth_user_id uuid default auth.uid()
)
returns table (currency text, open_opportunity_count bigint, weighted_value_total numeric, value_masked boolean)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  return query
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
end;
$$;

revoke execute on all functions in schema app from public;

grant execute on function app.get_ops_dashboard_shipment_status(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_milestone_sla(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_exception_queue(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_epod_completion(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_cost_variance(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_ops_dashboard_billing_readiness(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_lead_aging(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_activity_queue(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_pipeline_summary(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_quote_sla(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_margin_summary(uuid, uuid, uuid, date, date, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_win_loss_summary(uuid, uuid, uuid, date, date, uuid) to authenticated, service_role;
grant execute on function app.get_dashboard_forecast_summary(uuid, uuid, uuid, uuid) to authenticated, service_role;
