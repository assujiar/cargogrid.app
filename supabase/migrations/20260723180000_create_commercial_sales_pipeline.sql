-- Commercial capability COM-146 (CRM Sales Plan and Pipeline, CG-S7-COM-005)
-- A CRM planning/forecast layer over the canonical Lead/Prospect records already built
-- by COM-143/144 -- never a parallel copy of them. Sales plans/targets are versioned and
-- effective-dated; the pipeline view and forecast reconciliation always read live from
-- app.leads/app.prospects, never a duplicated transaction table.
--
-- Scope boundary (disclosed): Prompt 146 §13 asks the plan/target/forecast layer to
-- reference "canonical leads/prospects/opportunities". The Opportunity entity itself does
-- not exist yet -- 00_COMMERCIAL_WBS.md §3 row 5 places Opportunity Management at Prompt
-- 147, *after* this task, depending on `143..146`. This task therefore scopes its pipeline
-- and metric definitions to Lead and Prospect only (the only canonical revenue-track
-- records that exist at this checkpoint). The polymorphic surfaces added here
-- (app.commercial_pipeline_view, app.pipeline_outcomes, app.resolve_commercial_record_ref's
-- existing related_type check) are additive and designed to extend to 'opportunity' once
-- COM-147 lands, not a parallel scheme that would need reconciling later.
--
-- "Category" (Prompt 146 §13's fifth entity noun, alongside plan/target/forecast/win-loss
-- reason) is not otherwise defined by the prompt. This migration interprets it as a
-- tenant-managed reference list for grouping sales targets by funnel stage (e.g. "Top of
-- funnel" vs "Bottom of funnel") for reporting -- app.pipeline_categories -- a bounded,
-- disclosed interpretation, not a hidden guess.
--
-- Two access-safety design points worth calling out up front (see also COM-146's own
-- build log):
--  1. Live pipeline reads (app.commercial_pipeline_view, app.get_pipeline_summary) are
--     SECURITY INVOKER end-to-end -- they rely on RLS on app.leads/app.prospects to filter
--     rows, so "aggregates respect the same row permissions as drill-down records" holds
--     by construction, not by re-implementing the same predicate a second time.
--  2. Forecast reconciliation (app.compute_sales_metric_count, used by both
--     app.get_sales_target_actual and app.capture_forecast_snapshot) unavoidably runs
--     SECURITY DEFINER (it must write audit events / span org-unit-descendant scope), so
--     it re-states the identical app.can_access_record(...) row filter explicitly rather
--     than trusting RLS -- the one place in this migration where the predicate is
--     deliberately restated, and only ever in this one function.

-- Real defect found while authoring this capability's own tests, fixed here via
-- CREATE OR REPLACE (app.can_access_record's applied migration, PLT-114, is never
-- edited): app.sales_plans/app.sales_targets are the first tables in this repository
-- whose owner_user_id can legitimately be NULL (an org-unit-wide plan/target has no
-- single owning user). The original body compared `p_owner_user_id = p_auth_user_id`
-- directly -- when p_owner_user_id is NULL this yields SQL NULL, not false, and
-- `false OR null` is NULL rather than false. Every existing caller's `if not
-- app.can_access_record(...)` guard silently *skipped* its denial branch on a NULL
-- result (`if not null` is NULL, which a plpgsql IF treats as not-true, i.e. it does
-- not raise) -- meaning a NULL owner comparison could silently grant access instead of
-- denying it. No caller before COM-146 ever passed a NULL owner_user_id, so this was
-- latent, never exercised, and never previously caught by any test. Fixed by making the
-- owner comparison deterministically boolean and wrapping the full OR expression in a
-- defense-in-depth coalesce(..., false).
create or replace function app.can_access_record(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_owner_user_id uuid,
  p_shared_org_unit_ids uuid[] default '{}',
  p_customer_account_ref text default null
)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    app.has_active_tenant_membership(p_tenant_id, p_auth_user_id)
    and coalesce(
      app.is_supreme_admin(p_auth_user_id)
      or (p_owner_user_id is not null and p_owner_user_id = p_auth_user_id)
      or exists (
        select 1 from app.users u
        where u.auth_user_id = p_auth_user_id
          and u.tenant_id = p_tenant_id
          and u.status = 'active'
          and u.org_unit_id = any(p_shared_org_unit_ids)
      )
      or (
        p_customer_account_ref is not null
        and exists (
          select 1 from app.principal_memberships pm
          where pm.auth_user_id = p_auth_user_id
            and pm.tenant_id = p_tenant_id
            and pm.layer = 'customer_user'
            and pm.status = 'active'
            and pm.customer_account_ref = p_customer_account_ref
        )
      ),
      false
    );
$$;

comment on function app.can_access_record is
  'PLT-114, patched by COM-146: tenant-scoped record access -- supreme admin, exact owner match, shared org-unit membership, or an active customer-account membership. The owner/shared-scope/customer-ref checks are coalesced to false so a NULL owner_user_id (org-unit-wide records, first introduced by COM-146''s app.sales_plans/app.sales_targets) can never silently resolve to a NULL (falsy-in-SQL, but not caught by a plpgsql "if not" guard) grant.';

-- Prospect lifecycle (COM-144) has no per-transition timestamp for disqualify/archive
-- (only merged_at). Accurate period-scoped forecast reconciliation needs one. Adding a
-- nullable column via ALTER TABLE, and superseding the two affected functions' bodies via
-- CREATE OR REPLACE, does not edit COM-144's already-applied migration file -- it is a
-- new, additive migration, consistent with this repository's immutable-migrations
-- convention (the same technique COM-143 used to add the 'Assign' permission after the
-- fact).
alter table app.prospects add column disqualified_at timestamptz;
alter table app.prospects add column archived_at timestamptz;

comment on column app.prospects.disqualified_at is
  'COM-146: added to support period-scoped pipeline/forecast reconciliation. Set by app.disqualify_prospect (superseded in this migration via CREATE OR REPLACE -- COM-144''s migration file itself is never edited).';

comment on column app.prospects.archived_at is
  'COM-146: added for the same reason as disqualified_at. Set by app.archive_prospect (superseded in this migration via CREATE OR REPLACE).';

create or replace function app.disqualify_prospect(
  p_prospect_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.prospects
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prospect app.prospects;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: disqualifying a prospect requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_prospect.record_version <> p_expected_version then
    raise exception 'stale_version: prospect % expected version % but found %', p_prospect_id, p_expected_version, v_prospect.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_prospect.status <> 'active' then
    raise exception 'invalid_transition: prospect % is % and cannot be disqualified', p_prospect_id, v_prospect.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id, app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access prospect %', p_actor_auth_user_id, p_prospect_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.prospects
  set status = 'disqualified', disqualify_reason = p_reason, disqualified_at = now(), updated_at = now(), record_version = record_version + 1
  where id = p_prospect_id and record_version = p_expected_version
  returning * into v_prospect;

  perform app.capture_audit_event(
    v_prospect.tenant_id, p_actor_auth_user_id, p_actor_label, 'disqualify_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_prospect;
end;
$$;

create or replace function app.archive_prospect(
  p_prospect_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.prospects
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prospect app.prospects;
begin
  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_prospect.record_version <> p_expected_version then
    raise exception 'stale_version: prospect % expected version % but found %', p_prospect_id, p_expected_version, v_prospect.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_prospect.status <> 'active' then
    raise exception 'invalid_transition: prospect % is % and cannot be archived', p_prospect_id, v_prospect.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id, app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access prospect %', p_actor_auth_user_id, p_prospect_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.prospects
  set status = 'archived', archived_at = now(), updated_at = now(), record_version = record_version + 1
  where id = p_prospect_id and record_version = p_expected_version
  returning * into v_prospect;

  perform app.capture_audit_event(
    v_prospect.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, null
  );

  return v_prospect;
end;
$$;

-- Descendant-side org-unit scope wrapper. app.lead_record_scope_org_unit_ids (COM-143)
-- wraps app.org_unit_ancestor_ids and answers "can an actor positioned at an ancestor see
-- this record" (row-visibility direction, upward). Pipeline/plan/target scoping needs the
-- opposite direction -- "which records belong to org unit X or anything beneath it"
-- (drill-down filter direction, downward) -- so this wraps the sibling
-- app.org_unit_descendant_ids (also PLT-109, also service_role-only) instead. This is not
-- a duplicate of the COM-143 wrapper; it wraps a different underlying function for a
-- different query direction.
create function app.pipeline_scope_org_unit_ids(p_org_unit_id uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ids uuid[];
begin
  if p_org_unit_id is null then
    return '{}'::uuid[];
  end if;

  select coalesce(array_agg(x), '{}'::uuid[]) into v_ids from app.org_unit_descendant_ids(p_org_unit_id) as x;
  return v_ids || p_org_unit_id;
end;
$$;

comment on function app.pipeline_scope_org_unit_ids is
  'COM-146: descendant-plus-self org-unit scope for "records belonging to this org unit or below" filtering, distinct in direction from COM-143''s ancestor-plus-self app.lead_record_scope_org_unit_ids used for row-visibility checks.';

-- Read-model view: unions leads and prospects into one governed pipeline shape.
-- security_invoker = true means every query against this view runs with the calling
-- role's own privileges, so the existing leads_select_scoped / prospects RLS policies
-- filter rows exactly as they would for a direct drill-down query -- the view cannot leak
-- a row its own RLS policy would hide.
create view app.commercial_pipeline_view
with (security_invoker = true)
as
select
  l.tenant_id,
  'lead'::text as related_type,
  l.id as related_id,
  l.org_unit_id,
  l.owner_user_id,
  case l.status
    when 'new' then 'lead_new'
    when 'contacted' then 'lead_contacted'
    when 'qualified' then 'lead_qualified'
    when 'disqualified' then 'lead_lost'
    when 'converted' then 'lead_converted'
    when 'merged' then 'lead_merged'
  end as stage,
  l.company_name as record_label,
  l.created_at,
  l.updated_at
from app.leads l
union all
select
  p.tenant_id,
  'prospect'::text as related_type,
  p.id as related_id,
  p.org_unit_id,
  p.owner_user_id,
  case p.status
    when 'active' then 'prospect_active'
    when 'disqualified' then 'prospect_lost'
    when 'archived' then 'prospect_archived'
    when 'merged' then 'prospect_merged'
  end as stage,
  p.legal_name as record_label,
  p.created_at,
  p.updated_at
from app.prospects p;

comment on view app.commercial_pipeline_view is
  'COM-146: the one governed pipeline read-model, unioning app.leads and app.prospects into a common (stage, org_unit_id, owner_user_id) shape. security_invoker=true -- relies entirely on the underlying tables'' own RLS, never re-implements record-scope. Extend the two CASE expressions (or add a further UNION ALL branch) once COM-147 introduces app.opportunities; do not create a second competing pipeline view.';

create function app.get_pipeline_summary(
  p_tenant_id uuid,
  p_org_unit_id uuid
)
returns table (stage text, record_count bigint)
language sql
stable
set search_path = app, pg_temp
as $$
  select v.stage, count(*)::bigint as record_count
  from app.commercial_pipeline_view v
  where v.tenant_id = p_tenant_id
    and (p_org_unit_id is null or v.org_unit_id = any(app.pipeline_scope_org_unit_ids(p_org_unit_id)))
  group by v.stage;
$$;

comment on function app.get_pipeline_summary is
  'COM-146: deliberately SECURITY INVOKER (no elevation) -- runs as the calling authenticated user, so app.commercial_pipeline_view''s own RLS-backed filtering applies exactly as it would for a direct query. p_org_unit_id is a business drill-down filter (descendant-scoped), not itself the security boundary.';

create table app.pipeline_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  label text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pipeline_categories_tenant_code_unique unique (tenant_id, code)
);

comment on table app.pipeline_categories is
  'COM-146: tenant-managed reference list for grouping sales targets by funnel stage for reporting (Prompt 146 §13''s "category" noun -- a disclosed, bounded interpretation, not a configurable rule engine; the deferred Configuration Engine rule evaluator, ADR-CAND-ARCH-014/015, is a separate, still-open capability).';

create table app.sales_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  name text not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft',
  supersedes_plan_id uuid references app.sales_plans (id),
  owner_user_id uuid references auth.users (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_plans_status_check check (status in ('draft', 'published', 'archived')),
  constraint sales_plans_period_check check (period_end >= period_start),
  constraint sales_plans_not_self_supersede check (supersedes_plan_id is null or supersedes_plan_id <> id)
);

comment on table app.sales_plans is
  'COM-146: a versioned, effective-dated sales plan scoped to an organization unit. Editing a published plan is never allowed in place -- app.publish_sales_plan''s p_supersedes_plan_id parameter archives the prior published plan and links the new one, which is this capability''s "versioned" mechanism (Prompt 146 §24).';

create index sales_plans_tenant_org_status_idx on app.sales_plans (tenant_id, org_unit_id, status);
create index sales_plans_tenant_status_idx on app.sales_plans (tenant_id, status);

create table app.sales_targets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  sales_plan_id uuid not null references app.sales_plans (id),
  pipeline_category_id uuid references app.pipeline_categories (id),
  metric_type text not null,
  org_unit_id uuid references app.org_units (id),
  owner_user_id uuid references auth.users (id),
  target_value integer not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_targets_metric_type_check check (
    metric_type in ('leads_captured', 'leads_qualified', 'prospects_created', 'prospects_disqualified')
  ),
  constraint sales_targets_value_check check (target_value >= 0)
);

comment on table app.sales_targets is
  'COM-146: a count-based target against one of four metrics computable from canonical Lead/Prospect data at this checkpoint (no selling-value/currency field exists on any canonical record yet -- Quotation Builder, COM-151, is the first capability to introduce one). owner_user_id set means a per-seller quota; left null means an org-unit-wide target. Only editable while the parent plan is draft (app.update_sales_target).';

create unique index sales_targets_plan_metric_scope_unique on app.sales_targets (
  sales_plan_id,
  metric_type,
  coalesce(org_unit_id, '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(owner_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
);

create index sales_targets_tenant_owner_idx on app.sales_targets (tenant_id, owner_user_id);

create table app.forecast_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  sales_target_id uuid not null references app.sales_targets (id),
  computed_value integer not null,
  override_value integer,
  override_reason text,
  snapshot_at timestamptz not null default now(),
  created_by text,
  created_at timestamptz not null default now(),
  constraint forecast_snapshots_computed_check check (computed_value >= 0),
  constraint forecast_snapshots_override_check check (override_value is null or override_value >= 0),
  constraint forecast_snapshots_override_reason_check check (
    (override_value is not null and override_reason is not null and length(trim(override_reason)) > 0)
    or (override_value is null)
  )
);

comment on table app.forecast_snapshots is
  'COM-146: an append-only, point-in-time capture of a sales target''s reconciled actual (computed_value, always recomputed from canonical records at capture time -- app.compute_sales_metric_count) plus an optional, reasoned manual override. A row is never edited or deleted -- capturing again creates a new snapshot.';

create index forecast_snapshots_target_idx on app.forecast_snapshots (sales_target_id, snapshot_at desc);

create table app.win_loss_reasons (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  code text not null,
  label text not null,
  outcome text not null,
  is_active boolean not null default true,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint win_loss_reasons_outcome_check check (outcome in ('won', 'lost')),
  constraint win_loss_reasons_tenant_code_unique unique (tenant_id, code)
);

comment on table app.win_loss_reasons is
  'COM-146: tenant-managed reference list of canonical won/lost reasons, referenced (never re-typed as free text) by app.pipeline_outcomes.';

create table app.pipeline_outcomes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  related_type text not null,
  related_id uuid not null,
  outcome text not null,
  win_loss_reason_id uuid not null references app.win_loss_reasons (id),
  notes text,
  is_current boolean not null default true,
  superseded_by_id uuid references app.pipeline_outcomes (id),
  recorded_by text,
  recorded_at timestamptz not null default now(),
  constraint pipeline_outcomes_related_type_check check (related_type in ('lead', 'prospect')),
  constraint pipeline_outcomes_outcome_check check (outcome in ('won', 'lost'))
);

comment on table app.pipeline_outcomes is
  'COM-146: an additive win/loss categorization event against a lead or prospect (via app.resolve_commercial_record_ref -- reused, not re-derived) -- never mutates the source record. Recording a new outcome for the same (related_type, related_id) supersedes the prior current row (is_current/superseded_by_id chain) rather than overwriting it, preserving the full override history (Prompt 146 §18/§22).';

create unique index pipeline_outcomes_current_unique on app.pipeline_outcomes (tenant_id, related_type, related_id) where is_current;
create index pipeline_outcomes_related_idx on app.pipeline_outcomes (related_type, related_id);

-- The one reconciliation implementation shared by app.get_sales_target_actual (live
-- drill-down) and app.capture_forecast_snapshot (point-in-time capture) -- see this
-- migration's header note on why this function, alone, is SECURITY DEFINER with an
-- explicit re-stated app.can_access_record(...) filter rather than relying on RLS.
create function app.compute_sales_metric_count(
  p_tenant_id uuid,
  p_metric_type text,
  p_target_org_unit_id uuid,
  p_target_owner_user_id uuid,
  p_period_start date,
  p_period_end date,
  p_actor_auth_user_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope_org_unit_ids uuid[];
  v_count integer;
begin
  v_scope_org_unit_ids := app.pipeline_scope_org_unit_ids(p_target_org_unit_id);

  case p_metric_type
    when 'leads_captured' then
      select count(*) into v_count
      from app.leads l
      where l.tenant_id = p_tenant_id
        and l.org_unit_id = any(v_scope_org_unit_ids)
        and (p_target_owner_user_id is null or l.owner_user_id = p_target_owner_user_id)
        and l.created_at::date between p_period_start and p_period_end
        and app.can_access_record(p_actor_auth_user_id, l.tenant_id, l.owner_user_id, app.lead_record_scope_org_unit_ids(l.org_unit_id), null);
    when 'leads_qualified' then
      select count(*) into v_count
      from app.leads l
      where l.tenant_id = p_tenant_id
        and l.org_unit_id = any(v_scope_org_unit_ids)
        and (p_target_owner_user_id is null or l.owner_user_id = p_target_owner_user_id)
        and l.qualified_at is not null
        and l.qualified_at::date between p_period_start and p_period_end
        and app.can_access_record(p_actor_auth_user_id, l.tenant_id, l.owner_user_id, app.lead_record_scope_org_unit_ids(l.org_unit_id), null);
    when 'prospects_created' then
      select count(*) into v_count
      from app.prospects p
      where p.tenant_id = p_tenant_id
        and p.org_unit_id = any(v_scope_org_unit_ids)
        and (p_target_owner_user_id is null or p.owner_user_id = p_target_owner_user_id)
        and p.created_at::date between p_period_start and p_period_end
        and app.can_access_record(p_actor_auth_user_id, p.tenant_id, p.owner_user_id, app.lead_record_scope_org_unit_ids(p.org_unit_id), null);
    when 'prospects_disqualified' then
      select count(*) into v_count
      from app.prospects p
      where p.tenant_id = p_tenant_id
        and p.org_unit_id = any(v_scope_org_unit_ids)
        and (p_target_owner_user_id is null or p.owner_user_id = p_target_owner_user_id)
        and p.disqualified_at is not null
        and p.disqualified_at::date between p_period_start and p_period_end
        and app.can_access_record(p_actor_auth_user_id, p.tenant_id, p.owner_user_id, app.lead_record_scope_org_unit_ids(p.org_unit_id), null);
    else
      raise exception 'unknown_metric_type: %', p_metric_type using errcode = 'check_violation';
  end case;

  return coalesce(v_count, 0);
end;
$$;

create function app.get_sales_target_actual(
  p_sales_target_id uuid,
  p_actor_auth_user_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_target app.sales_targets;
  v_plan app.sales_plans;
begin
  select * into v_target from app.sales_targets where id = p_sales_target_id;
  if not found then
    raise exception 'sales_target_not_found: %', p_sales_target_id using errcode = 'no_data_found';
  end if;

  select * into v_plan from app.sales_plans where id = v_target.sales_plan_id;

  if not app.can_access_record(p_actor_auth_user_id, v_target.tenant_id, v_target.owner_user_id, app.lead_record_scope_org_unit_ids(v_target.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales target %', p_actor_auth_user_id, p_sales_target_id
      using errcode = 'insufficient_privilege';
  end if;

  return app.compute_sales_metric_count(
    v_target.tenant_id, v_target.metric_type, v_target.org_unit_id, v_target.owner_user_id,
    v_plan.period_start, v_plan.period_end, p_actor_auth_user_id
  );
end;
$$;

comment on function app.get_sales_target_actual is
  'COM-146: live drill-down parity check -- returns the same reconciled count app.capture_forecast_snapshot would compute right now, without writing a snapshot row.';

create function app.create_pipeline_category(
  p_tenant_id uuid,
  p_code text,
  p_label text,
  p_sort_order integer,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.pipeline_categories
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_category app.pipeline_categories;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.pipeline_categories (tenant_id, code, label, sort_order, created_by)
  values (p_tenant_id, p_code, p_label, coalesce(p_sort_order, 0), p_created_by)
  returning * into v_category;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_pipeline_category',
    'app.pipeline_categories', v_category.id, 'success', null, null, to_jsonb(v_category)
  );

  return v_category;
exception
  when unique_violation then
    raise exception 'duplicate_category_code: code % already exists for tenant %', p_code, p_tenant_id
      using errcode = 'unique_violation';
end;
$$;

create function app.update_pipeline_category(
  p_category_id uuid,
  p_expected_version integer,
  p_label text,
  p_sort_order integer,
  p_is_active boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.pipeline_categories
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_category app.pipeline_categories;
  v_decision app.rbac_decision;
begin
  select * into v_category from app.pipeline_categories where id = p_category_id;
  if not found then
    raise exception 'pipeline_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;

  if v_category.record_version <> p_expected_version then
    raise exception 'stale_version: pipeline category % expected version % but found %', p_category_id, p_expected_version, v_category.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_category.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_category.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.pipeline_categories
  set label = coalesce(p_label, label),
      sort_order = coalesce(p_sort_order, sort_order),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now(),
      record_version = record_version + 1
  where id = p_category_id and record_version = p_expected_version
  returning * into v_category;

  perform app.capture_audit_event(
    v_category.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_pipeline_category',
    'app.pipeline_categories', v_category.id, 'success', null, null, to_jsonb(v_category)
  );

  return v_category;
end;
$$;

create function app.create_sales_plan(
  p_tenant_id uuid,
  p_org_unit_id uuid,
  p_name text,
  p_period_start date,
  p_period_end date,
  p_owner_user_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.sales_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_plan app.sales_plans;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_period_end < p_period_start then
    raise exception 'invalid_period: period_end % precedes period_start %', p_period_end, p_period_start
      using errcode = 'check_violation';
  end if;

  insert into app.sales_plans (tenant_id, org_unit_id, name, period_start, period_end, owner_user_id, created_by)
  values (p_tenant_id, p_org_unit_id, p_name, p_period_start, p_period_end, p_owner_user_id, p_created_by)
  returning * into v_plan;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_sales_plan',
    'app.sales_plans', v_plan.id, 'success', null, null, to_jsonb(v_plan)
  );

  return v_plan;
end;
$$;

create function app.publish_sales_plan(
  p_plan_id uuid,
  p_expected_version integer,
  p_supersedes_plan_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.sales_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_plan app.sales_plans;
  v_superseded app.sales_plans;
  v_decision app.rbac_decision;
  v_overlap_count integer;
begin
  select * into v_plan from app.sales_plans where id = p_plan_id;
  if not found then
    raise exception 'sales_plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;

  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: sales plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_plan.status <> 'draft' then
    raise exception 'invalid_transition: sales plan % is % and cannot be published', p_plan_id, v_plan.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, v_plan.owner_user_id, app.lead_record_scope_org_unit_ids(v_plan.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales plan %', p_actor_auth_user_id, p_plan_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_plan_id is not null then
    select * into v_superseded from app.sales_plans where id = p_supersedes_plan_id;
    if not found then
      raise exception 'superseded_plan_not_found: %', p_supersedes_plan_id using errcode = 'no_data_found';
    end if;
    if v_superseded.tenant_id <> v_plan.tenant_id or v_superseded.org_unit_id is distinct from v_plan.org_unit_id then
      raise exception 'invalid_supersede: superseded plan must share tenant and organization scope'
        using errcode = 'check_violation';
    end if;
    if v_superseded.status <> 'published' then
      raise exception 'invalid_supersede: superseded plan % is not published (is %)', p_supersedes_plan_id, v_superseded.status
        using errcode = 'check_violation';
    end if;
  end if;

  select count(*) into v_overlap_count
  from app.sales_plans sp
  where sp.tenant_id = v_plan.tenant_id
    and sp.org_unit_id is not distinct from v_plan.org_unit_id
    and sp.status = 'published'
    and sp.id <> coalesce(p_supersedes_plan_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and sp.period_start <= v_plan.period_end
    and sp.period_end >= v_plan.period_start;

  if v_overlap_count > 0 then
    raise exception 'overlapping_plan: another published plan already covers an overlapping period for this organization scope'
      using errcode = 'check_violation';
  end if;

  if p_supersedes_plan_id is not null then
    update app.sales_plans
    set status = 'archived', updated_at = now(), record_version = record_version + 1
    where id = p_supersedes_plan_id;
  end if;

  update app.sales_plans
  set status = 'published', supersedes_plan_id = p_supersedes_plan_id, updated_at = now(), record_version = record_version + 1
  where id = p_plan_id and record_version = p_expected_version
  returning * into v_plan;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_sales_plan',
    'app.sales_plans', v_plan.id, 'success', null, null, jsonb_build_object('supersedes_plan_id', p_supersedes_plan_id)
  );

  return v_plan;
end;
$$;

comment on function app.publish_sales_plan is
  'COM-146: draft->published transition. p_supersedes_plan_id, when set, atomically archives the named prior published plan (must already be published, same tenant/org scope) and links it -- this is the "versioned plan" mechanism (Prompt 146 §24), never an in-place edit of a published plan. Rejects any other overlapping published plan for the same organization scope.';

create function app.archive_sales_plan(
  p_plan_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.sales_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
begin
  select * into v_plan from app.sales_plans where id = p_plan_id;
  if not found then
    raise exception 'sales_plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;

  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: sales plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_plan.status = 'archived' then
    raise exception 'invalid_transition: sales plan % is already archived', p_plan_id
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, v_plan.owner_user_id, app.lead_record_scope_org_unit_ids(v_plan.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales plan %', p_actor_auth_user_id, p_plan_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.sales_plans
  set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_plan_id and record_version = p_expected_version
  returning * into v_plan;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_sales_plan',
    'app.sales_plans', v_plan.id, 'success', null, null, null
  );

  return v_plan;
end;
$$;

create function app.create_sales_target(
  p_sales_plan_id uuid,
  p_pipeline_category_id uuid,
  p_metric_type text,
  p_org_unit_id uuid,
  p_owner_user_id uuid,
  p_target_value integer,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.sales_targets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
  v_target app.sales_targets;
begin
  select * into v_plan from app.sales_plans where id = p_sales_plan_id;
  if not found then
    raise exception 'sales_plan_not_found: %', p_sales_plan_id using errcode = 'no_data_found';
  end if;

  if v_plan.status <> 'draft' then
    raise exception 'invalid_transition: sales plan % is % -- targets can only be added while the plan is draft', p_sales_plan_id, v_plan.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, v_plan.owner_user_id, app.lead_record_scope_org_unit_ids(v_plan.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales plan %', p_actor_auth_user_id, p_sales_plan_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_target_value < 0 then
    raise exception 'invalid_target_value: target_value must be non-negative' using errcode = 'check_violation';
  end if;

  insert into app.sales_targets (
    tenant_id, sales_plan_id, pipeline_category_id, metric_type, org_unit_id, owner_user_id, target_value, created_by
  ) values (
    v_plan.tenant_id, p_sales_plan_id, p_pipeline_category_id, p_metric_type, coalesce(p_org_unit_id, v_plan.org_unit_id), p_owner_user_id, p_target_value, p_created_by
  )
  returning * into v_target;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_created_by, 'create_sales_target',
    'app.sales_targets', v_target.id, 'success', null, null, to_jsonb(v_target)
  );

  return v_target;
exception
  when unique_violation then
    raise exception 'duplicate_target: a target for this metric/organization/owner combination already exists on this plan'
      using errcode = 'unique_violation';
end;
$$;

create function app.update_sales_target(
  p_target_id uuid,
  p_expected_version integer,
  p_target_value integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.sales_targets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_target app.sales_targets;
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
begin
  select * into v_target from app.sales_targets where id = p_target_id;
  if not found then
    raise exception 'sales_target_not_found: %', p_target_id using errcode = 'no_data_found';
  end if;

  if v_target.record_version <> p_expected_version then
    raise exception 'stale_version: sales target % expected version % but found %', p_target_id, p_expected_version, v_target.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_plan from app.sales_plans where id = v_target.sales_plan_id;
  if v_plan.status <> 'draft' then
    raise exception 'invalid_transition: sales plan % is % -- targets can only be edited while the plan is draft', v_plan.id, v_plan.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_target.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_target.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_target.tenant_id, v_target.owner_user_id, app.lead_record_scope_org_unit_ids(v_target.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales target %', p_actor_auth_user_id, p_target_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_target_value < 0 then
    raise exception 'invalid_target_value: target_value must be non-negative' using errcode = 'check_violation';
  end if;

  update app.sales_targets
  set target_value = p_target_value, updated_at = now(), record_version = record_version + 1
  where id = p_target_id and record_version = p_expected_version
  returning * into v_target;

  perform app.capture_audit_event(
    v_target.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_sales_target',
    'app.sales_targets', v_target.id, 'success', null, null, jsonb_build_object('target_value', p_target_value)
  );

  return v_target;
end;
$$;

create function app.capture_forecast_snapshot(
  p_sales_target_id uuid,
  p_override_value integer,
  p_override_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.forecast_snapshots
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_target app.sales_targets;
  v_plan app.sales_plans;
  v_decision app.rbac_decision;
  v_computed integer;
  v_snapshot app.forecast_snapshots;
begin
  select * into v_target from app.sales_targets where id = p_sales_target_id;
  if not found then
    raise exception 'sales_target_not_found: %', p_sales_target_id using errcode = 'no_data_found';
  end if;

  select * into v_plan from app.sales_plans where id = v_target.sales_plan_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_target.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_target.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_target.tenant_id, v_target.owner_user_id, app.lead_record_scope_org_unit_ids(v_target.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access sales target %', p_actor_auth_user_id, p_sales_target_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_override_value is not null and (p_override_reason is null or length(trim(p_override_reason)) = 0) then
    raise exception 'override_reason_required: an override value requires a non-empty override reason'
      using errcode = 'check_violation';
  end if;

  v_computed := app.compute_sales_metric_count(
    v_target.tenant_id, v_target.metric_type, v_target.org_unit_id, v_target.owner_user_id,
    v_plan.period_start, v_plan.period_end, p_actor_auth_user_id
  );

  insert into app.forecast_snapshots (tenant_id, sales_target_id, computed_value, override_value, override_reason, created_by)
  values (v_target.tenant_id, p_sales_target_id, v_computed, p_override_value, p_override_reason, p_actor_label)
  returning * into v_snapshot;

  perform app.capture_audit_event(
    v_target.tenant_id, p_actor_auth_user_id, p_actor_label, 'capture_forecast_snapshot',
    'app.forecast_snapshots', v_snapshot.id, 'success', null, null, to_jsonb(v_snapshot)
  );

  return v_snapshot;
end;
$$;

create function app.create_win_loss_reason(
  p_tenant_id uuid,
  p_code text,
  p_label text,
  p_outcome text,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.win_loss_reasons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reason app.win_loss_reasons;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.win_loss_reasons (tenant_id, code, label, outcome, created_by)
  values (p_tenant_id, p_code, p_label, p_outcome, p_created_by)
  returning * into v_reason;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_win_loss_reason',
    'app.win_loss_reasons', v_reason.id, 'success', null, null, to_jsonb(v_reason)
  );

  return v_reason;
exception
  when unique_violation then
    raise exception 'duplicate_reason_code: code % already exists for tenant %', p_code, p_tenant_id
      using errcode = 'unique_violation';
end;
$$;

create function app.update_win_loss_reason(
  p_reason_id uuid,
  p_expected_version integer,
  p_label text,
  p_is_active boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.win_loss_reasons
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_reason app.win_loss_reasons;
  v_decision app.rbac_decision;
begin
  select * into v_reason from app.win_loss_reasons where id = p_reason_id;
  if not found then
    raise exception 'win_loss_reason_not_found: %', p_reason_id using errcode = 'no_data_found';
  end if;

  if v_reason.record_version <> p_expected_version then
    raise exception 'stale_version: win/loss reason % expected version % but found %', p_reason_id, p_expected_version, v_reason.record_version
      using errcode = 'serialization_failure';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reason.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reason.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.win_loss_reasons
  set label = coalesce(p_label, label),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now(),
      record_version = record_version + 1
  where id = p_reason_id and record_version = p_expected_version
  returning * into v_reason;

  perform app.capture_audit_event(
    v_reason.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_win_loss_reason',
    'app.win_loss_reasons', v_reason.id, 'success', null, null, to_jsonb(v_reason)
  );

  return v_reason;
end;
$$;

create function app.record_pipeline_outcome(
  p_related_type text,
  p_related_id uuid,
  p_outcome text,
  p_win_loss_reason_id uuid,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.pipeline_outcomes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ref record;
  v_reason app.win_loss_reasons;
  v_decision app.rbac_decision;
  v_previous app.pipeline_outcomes;
  v_outcome app.pipeline_outcomes;
begin
  select * into v_ref from app.resolve_commercial_record_ref(p_related_type, p_related_id);

  select * into v_reason from app.win_loss_reasons where id = p_win_loss_reason_id;
  if not found then
    raise exception 'win_loss_reason_not_found: %', p_win_loss_reason_id using errcode = 'no_data_found';
  end if;

  if v_reason.tenant_id <> v_ref.tenant_id then
    raise exception 'cross_tenant_reason_denied: reason and record belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  if v_reason.outcome <> p_outcome then
    raise exception 'reason_outcome_mismatch: reason % is scoped to outcome % but % was requested', p_win_loss_reason_id, v_reason.outcome, p_outcome
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_ref.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_ref.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_ref.tenant_id, v_ref.owner_user_id, app.lead_record_scope_org_unit_ids(v_ref.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access the record', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_previous from app.pipeline_outcomes
  where related_type = p_related_type and related_id = p_related_id and is_current;

  if v_previous.id is not null then
    update app.pipeline_outcomes set is_current = false where id = v_previous.id;
  end if;

  insert into app.pipeline_outcomes (
    tenant_id, related_type, related_id, outcome, win_loss_reason_id, notes, recorded_by
  ) values (
    v_ref.tenant_id, p_related_type, p_related_id, p_outcome, p_win_loss_reason_id, p_notes, p_actor_label
  )
  returning * into v_outcome;

  if v_previous.id is not null then
    update app.pipeline_outcomes set superseded_by_id = v_outcome.id where id = v_previous.id;
  end if;

  perform app.capture_audit_event(
    v_ref.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_pipeline_outcome',
    'app.pipeline_outcomes', v_outcome.id, 'success', null,
    case when v_previous.id is not null then to_jsonb(v_previous) else null end,
    to_jsonb(v_outcome)
  );

  return v_outcome;
end;
$$;

comment on function app.record_pipeline_outcome is
  'COM-146: win/loss categorization is an additive event, never a mutation of the source lead/prospect row. A new call for the same (related_type, related_id) supersedes the prior current row rather than editing it -- the full override history is always reconstructable.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

alter table app.pipeline_categories enable row level security;
alter table app.sales_plans enable row level security;
alter table app.sales_targets enable row level security;
alter table app.forecast_snapshots enable row level security;
alter table app.win_loss_reasons enable row level security;
alter table app.pipeline_outcomes enable row level security;

-- Reference/master-data tables: tenant-membership-scoped rather than owner/org_unit
-- record-scope, matching the same disclosed coarser-trade-off precedent COM-145 already
-- established for app.contact_links.
create policy pipeline_categories_select_scoped on app.pipeline_categories
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id));

create policy win_loss_reasons_select_scoped on app.win_loss_reasons
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id));

create policy sales_plans_select_scoped on app.sales_plans
  for select to authenticated
  using (
    app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null)
  );

create policy sales_targets_select_scoped on app.sales_targets
  for select to authenticated
  using (
    app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null)
  );

create policy forecast_snapshots_select_scoped on app.forecast_snapshots
  for select to authenticated
  using (
    exists (
      select 1 from app.sales_targets t
      where t.id = forecast_snapshots.sales_target_id
        and app.can_access_record(auth.uid(), t.tenant_id, t.owner_user_id, app.lead_record_scope_org_unit_ids(t.org_unit_id), null)
    )
  );

create policy pipeline_outcomes_select_scoped on app.pipeline_outcomes
  for select to authenticated
  using (
    exists (
      select 1 from app.resolve_commercial_record_ref(pipeline_outcomes.related_type, pipeline_outcomes.related_id) r
      where app.can_access_record(auth.uid(), pipeline_outcomes.tenant_id, r.owner_user_id, app.lead_record_scope_org_unit_ids(r.org_unit_id), null)
    )
  );

grant usage on schema app to authenticated;
grant select on app.pipeline_categories to authenticated, service_role;
grant select on app.sales_plans to authenticated, service_role;
grant select on app.sales_targets to authenticated, service_role;
grant select on app.forecast_snapshots to authenticated, service_role;
grant select on app.win_loss_reasons to authenticated, service_role;
grant select on app.pipeline_outcomes to authenticated, service_role;
grant insert, update, delete on app.pipeline_categories to service_role;
grant insert, update, delete on app.sales_plans to service_role;
grant insert, update, delete on app.sales_targets to service_role;
grant insert, update, delete on app.forecast_snapshots to service_role;
grant insert, update, delete on app.win_loss_reasons to service_role;
grant insert, update, delete on app.pipeline_outcomes to service_role;
grant select on app.commercial_pipeline_view to authenticated, service_role;

grant execute on function app.disqualify_prospect(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.archive_prospect(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.pipeline_scope_org_unit_ids(uuid) to authenticated, service_role;
grant execute on function app.get_pipeline_summary(uuid, uuid) to authenticated, service_role;
grant execute on function app.create_pipeline_category(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.update_pipeline_category(uuid, integer, text, integer, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.create_sales_plan(uuid, uuid, text, date, date, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.publish_sales_plan(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.archive_sales_plan(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.create_sales_target(uuid, uuid, text, uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.update_sales_target(uuid, integer, integer, uuid, text) to authenticated, service_role;
grant execute on function app.compute_sales_metric_count(uuid, text, uuid, uuid, date, date, uuid) to authenticated, service_role;
grant execute on function app.get_sales_target_actual(uuid, uuid) to authenticated, service_role;
grant execute on function app.capture_forecast_snapshot(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_win_loss_reason(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_win_loss_reason(uuid, integer, text, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.record_pipeline_outcome(text, uuid, text, uuid, text, uuid, text) to authenticated, service_role;
